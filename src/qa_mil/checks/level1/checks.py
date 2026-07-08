"""Level 1 checks — table-level and variable-level compliance.

Source: inputfiles/scdm_data_qa_mil_review-level1.sas

Table-level checks (varid="00"):
  100: Table exists (Abort)
  101: Table populated (Abort)
  102: Table sort order (Abort)

Variable-level checks (varid=variable-specific):
  110: Required column missing (Warn)
  111: Variable not populated (Warn)
  112: Variable type mismatch (Warn)
  113: Variable length mismatch (Warn)
  120: Variable has null values (Warn)
  121: Invalid data/value-format (Warn)
  122: Leading spaces (Warn)
  126: Age range 10-54 (Warn)
  131: Date range (Warn)
  133: Name format (Warn)

Check 130 is inactive — documented as not applicable.
"""

from __future__ import annotations

from dataclasses import dataclass
from typing import Any

import ibis

from qa_mil.checks.base import (
    CheckContext,
    CheckMetadata,
    OutputScope,
    Severity,
    make_flagid,
)
from qa_mil.lookups.loader import load_l1_rules

_MIL_TABID = "MIL"


def _get_mil_rules() -> list[Any]:
    """Load L1 variable rules for the MIL table."""
    return [r for r in load_l1_rules() if r.tabid.upper() == _MIL_TABID]


# ---------------------------------------------------------------------------
# Table-level checks
# ---------------------------------------------------------------------------


@dataclass(frozen=True)
class TableExistsCheck:
    """Check 100: Confirm that the table exists."""

    tabid: str = _MIL_TABID

    @property
    def metadata(self) -> CheckMetadata:
        return CheckMetadata(
            check_id="100",
            level=1,
            severity=Severity.ABORT,
            tables=frozenset({"mil"}),
            output_scope=OutputScope.DPLOCAL,
            description="Table does not exist",
            tabid=self.tabid,
        )

    def build(self, ctx: CheckContext) -> ibis.Table:
        """In Python, the table always exists if the engine registered it.

        This check is a no-op flag generator that produces no rows when the
        table is present. If the table were absent, the engine would have
        failed during session creation (fatal input validation).
        """
        session = ctx.session
        mil = session.table("mil")
        # Return zero rows — table exists because engine registered it
        return mil.filter(ibis.literal(False)).mutate(
            flagid=ibis.literal(make_flagid(self.tabid, 1, "00", 100)),
            flag_descr=ibis.literal("Table does not exist"),
            message=ibis.literal(""),
            flag_type=ibis.literal("Abort"),
            abort_yn=ibis.literal("Y"),
        )


@dataclass(frozen=True)
class TablePopulatedCheck:
    """Check 101: Confirm that the table is populated."""

    tabid: str = _MIL_TABID

    @property
    def metadata(self) -> CheckMetadata:
        return CheckMetadata(
            check_id="101",
            level=1,
            severity=Severity.ABORT,
            tables=frozenset({"mil"}),
            output_scope=OutputScope.DPLOCAL,
            description="Table is not populated",
            tabid=self.tabid,
        )

    def build(self, ctx: CheckContext) -> ibis.Table:
        """Emit a single Abort flag row when the table has zero rows.

        Uses aggregate to always produce exactly one row (the count),
        then filters to keep it only when count == 0.
        """
        session = ctx.session
        mil = session.table("mil")
        return (
            mil.aggregate(_count=mil.count())
            .filter(ibis._["_count"] == 0)
            .select(
                ibis.literal(make_flagid(self.tabid, 1, "00", 101)).name("flagid"),
                ibis.literal("Table is not populated").name("flag_descr"),
                ibis.literal("").name("message"),
                ibis.literal("Abort").name("flag_type"),
                ibis.literal("Y").name("abort_yn"),
            )
        )


@dataclass(frozen=True)
class TableSortOrderCheck:
    """Check 102: Confirm correct table sort order."""

    tabid: str = _MIL_TABID

    @property
    def metadata(self) -> CheckMetadata:
        return CheckMetadata(
            check_id="102",
            level=1,
            severity=Severity.ABORT,
            tables=frozenset({"mil"}),
            output_scope=OutputScope.DPLOCAL,
            description="Table is not sorted correctly",
            tabid=self.tabid,
        )

    def build(self, ctx: CheckContext) -> ibis.Table:
        """Check sort order against expected sort variables.

        Uses lookup metadata sortorder to determine expected sort columns.
        Flags rows that violate the expected non-decreasing sort order.

        Implements typed lexicographic comparison per sort column (not string
        concatenation), with null-first ordering matching SAS semantics:
        null sorts before any non-null value.

        Note: In the parquet/SQL runtime, physical row order is not
        operationally required (all operations are set-based), but this
        check preserves the SAS QA flag behavior for diagnostic purposes.
        """
        session = ctx.session
        mil = session.table("mil")
        rules = _get_mil_rules()
        sort_vars = sorted(
            [r for r in rules if r.sortorder is not None],
            key=lambda r: r.sortorder,
        )

        if not sort_vars:
            # No sort order defined — nothing to check
            return (
                mil.aggregate(_count=mil.count())
                .filter(ibis.literal(False))
                .select(
                    ibis.literal(make_flagid(self.tabid, 1, "00", 102)).name("flagid"),
                    ibis.literal("Table is not sorted correctly").name("flag_descr"),
                    ibis.literal("").name("message"),
                    ibis.literal("Abort").name("flag_type"),
                    ibis.literal("Y").name("abort_yn"),
                )
            )

        sort_cols = [r.variable for r in sort_vars if r.variable in mil.columns]
        if not sort_cols:
            return (
                mil.aggregate(_count=mil.count())
                .filter(ibis.literal(False))
                .select(
                    ibis.literal(make_flagid(self.tabid, 1, "00", 102)).name("flagid"),
                    ibis.literal("Table is not sorted correctly").name("flag_descr"),
                    ibis.literal("").name("message"),
                    ibis.literal("Abort").name("flag_type"),
                    ibis.literal("Y").name("abort_yn"),
                )
            )

        # Use the stable Parquet scan ordinal injected by the engine at table
        # registration time. SQL row_number() without a source-order column is
        # arbitrary and would not preserve the SAS input/file sequence.
        row_ord_col = "file_row_number"
        if row_ord_col not in mil.columns:
            raise ValueError(
                "Check 102 requires a stable input row ordinal; "
                f"registered MIL table is missing {row_ord_col!r}"
            )
        w = ibis.window(order_by=row_ord_col)

        mil_lagged = mil
        for col in sort_cols:
            mil_lagged = mil_lagged.mutate(**{f"_lag_{col}": mil_lagged[col].lag().over(w)})

        # Build cascading typed lexicographic comparison.
        # For each sort column position i, the row violates sort order if:
        #   all columns 0..i-1 are equal AND column i is less than predecessor.
        # Null-first ordering: null < non-null, null == null.
        violates = ibis.literal(False)
        all_prev_equal = ibis.literal(True)

        for col in sort_cols:
            curr = mil_lagged[col]
            prev = mil_lagged[f"_lag_{col}"]

            # null-first "less than":
            #   (curr null AND prev not-null) → null before non-null → violation
            #   (both not-null AND curr < prev) → native typed comparison
            col_less = (curr.isnull() & prev.notnull()) | (
                curr.notnull() & prev.notnull() & (curr < prev)
            )

            # null-safe equality (for cascading):
            #   (both null) OR (both not-null AND curr == prev)
            col_equal = (curr.isnull() & prev.isnull()) | (
                curr.notnull() & prev.notnull() & (curr == prev)
            )

            violates = violates | (all_prev_equal & col_less)
            all_prev_equal = all_prev_equal & col_equal

        flagged = mil_lagged.filter(violates)

        return flagged.select(
            ibis.literal(make_flagid(self.tabid, 1, "00", 102)).name("flagid"),
            ibis.literal("Table is not sorted correctly").name("flag_descr"),
            ibis.literal("").name("message"),
            ibis.literal("Abort").name("flag_type"),
            ibis.literal("Y").name("abort_yn"),
        )


# ---------------------------------------------------------------------------
# Variable-level checks (parameterized)
# ---------------------------------------------------------------------------


@dataclass(frozen=True)
class MissingColumnCheck:
    """Check 110: Required SCDM variable is missing from the table."""

    variable: str
    varid: str
    tabid: str = _MIL_TABID

    @property
    def metadata(self) -> CheckMetadata:
        return CheckMetadata(
            check_id="110",
            level=1,
            severity=Severity.WARN,
            tables=frozenset({"mil"}),
            output_scope=OutputScope.DPLOCAL,
            description=f"Required SCDM variable '{self.variable}' is missing",
            tabid=self.tabid,
        )

    def build(self, ctx: CheckContext) -> ibis.Table:
        session = ctx.session
        mil = session.table("mil")
        columns = mil.columns

        if self.variable not in columns:
            # Variable is missing — emit a flag row
            return mil.limit(1).select(
                ibis.literal(make_flagid(self.tabid, 1, self.varid, 110)).name("flagid"),
                ibis.literal(f"Required SCDM variable '{self.variable}' is missing").name(
                    "flag_descr"
                ),
                ibis.literal("").name("message"),
                ibis.literal("Warn").name("flag_type"),
                ibis.literal("N").name("abort_yn"),
            )
        return mil.filter(ibis.literal(False)).mutate(
            flagid=ibis.literal(make_flagid(self.tabid, 1, self.varid, 110)),
            flag_descr=ibis.literal(f"Required SCDM variable '{self.variable}' is missing"),
            message=ibis.literal(""),
            flag_type=ibis.literal("Warn"),
            abort_yn=ibis.literal("N"),
        )


@dataclass(frozen=True)
class VariableNotPopulatedCheck:
    """Check 111: Variable is not populated (all values null)."""

    variable: str
    varid: str
    tabid: str = _MIL_TABID

    @property
    def metadata(self) -> CheckMetadata:
        return CheckMetadata(
            check_id="111",
            level=1,
            severity=Severity.WARN,
            tables=frozenset({"mil"}),
            output_scope=OutputScope.DPLOCAL,
            description=f"Variable '{self.variable}' is not populated",
            tabid=self.tabid,
        )

    def build(self, ctx: CheckContext) -> ibis.Table:
        session = ctx.session
        mil = session.table("mil")
        if self.variable not in mil.columns:
            return mil.filter(ibis.literal(False)).mutate(
                flagid=ibis.literal(make_flagid(self.tabid, 1, self.varid, 111)),
                flag_descr=ibis.literal(f"Variable '{self.variable}' is not populated"),
                message=ibis.literal(""),
                flag_type=ibis.literal("Warn"),
                abort_yn=ibis.literal("N"),
            )
        # If non_null_count == 0, all values are null
        result = (
            mil.filter(mil[self.variable].notnull().count() == 0)
            .limit(1)
            .mutate(
                flagid=ibis.literal(make_flagid(self.tabid, 1, self.varid, 111)),
                flag_descr=ibis.literal(f"Variable '{self.variable}' is not populated"),
                message=ibis.literal(""),
                flag_type=ibis.literal("Warn"),
                abort_yn=ibis.literal("N"),
            )
        )
        return result


@dataclass(frozen=True)
class VariableTypeCheck:
    """Check 112: Variable type does not match SCDM."""

    variable: str
    varid: str
    expected_type: str
    tabid: str = _MIL_TABID

    @property
    def metadata(self) -> CheckMetadata:
        return CheckMetadata(
            check_id="112",
            level=1,
            severity=Severity.WARN,
            tables=frozenset({"mil"}),
            output_scope=OutputScope.DPLOCAL,
            description=f"Variable '{self.variable}' type does not match SCDM",
            tabid=self.tabid,
        )

    def build(self, ctx: CheckContext) -> ibis.Table:
        session = ctx.session
        mil = session.table("mil")
        if self.variable not in mil.columns:
            return mil.filter(ibis.literal(False)).mutate(
                flagid=ibis.literal(make_flagid(self.tabid, 1, self.varid, 112)),
                flag_descr=ibis.literal(f"Variable '{self.variable}' type mismatch"),
                message=ibis.literal(""),
                flag_type=ibis.literal("Warn"),
                abort_yn=ibis.literal("N"),
            )
        # Check actual type — parquet string vs numeric
        col_type = mil[self.variable].type()
        is_string = str(col_type).lower().startswith("string")
        expected_char = self.expected_type.upper() == "C"
        if is_string != expected_char:
            return mil.limit(1).select(
                ibis.literal(make_flagid(self.tabid, 1, self.varid, 112)).name("flagid"),
                ibis.literal(f"Variable '{self.variable}' type mismatch").name("flag_descr"),
                ibis.literal("").name("message"),
                ibis.literal("Warn").name("flag_type"),
                ibis.literal("N").name("abort_yn"),
            )
        return mil.filter(ibis.literal(False)).mutate(
            flagid=ibis.literal(make_flagid(self.tabid, 1, self.varid, 112)),
            flag_descr=ibis.literal(f"Variable '{self.variable}' type mismatch"),
            message=ibis.literal(""),
            flag_type=ibis.literal("Warn"),
            abort_yn=ibis.literal("N"),
        )


@dataclass(frozen=True)
class VariableLengthCheck:
    """Check 113: Variable length does not match SCDM.

    Parquet-era semantics: validate observed maximum string length against
    expected SAS length metadata.
    """

    variable: str
    varid: str
    expected_length: int
    tabid: str = _MIL_TABID

    @property
    def metadata(self) -> CheckMetadata:
        return CheckMetadata(
            check_id="113",
            level=1,
            severity=Severity.WARN,
            tables=frozenset({"mil"}),
            output_scope=OutputScope.DPLOCAL,
            description=f"Variable '{self.variable}' length exceeds SCDM max",
            tabid=self.tabid,
        )

    def build(self, ctx: CheckContext) -> ibis.Table:
        session = ctx.session
        mil = session.table("mil")
        if self.variable not in mil.columns:
            return mil.filter(ibis.literal(False)).mutate(
                flagid=ibis.literal(make_flagid(self.tabid, 1, self.varid, 113)),
                flag_descr=ibis.literal(f"Variable '{self.variable}' length exceeds SCDM max"),
                message=ibis.literal(""),
                flag_type=ibis.literal("Warn"),
                abort_yn=ibis.literal("N"),
            )
        col = mil[self.variable]
        col_type = str(col.type()).lower()
        # Only string columns have meaningful length in parquet;
        # numeric length is storage width (always 8 in SAS), not applicable here
        if not col_type.startswith("string"):
            return mil.filter(ibis.literal(False)).mutate(
                flagid=ibis.literal(make_flagid(self.tabid, 1, self.varid, 113)),
                flag_descr=ibis.literal(
                    f"Variable '{self.variable}' length exceeds SCDM max of {self.expected_length}"
                ),
                message=ibis.literal(""),
                flag_type=ibis.literal("Warn"),
                abort_yn=ibis.literal("N"),
            )
        # Flag rows where observed string length exceeds expected
        flagged = mil.filter(col.length() > self.expected_length)
        return flagged.mutate(
            flagid=ibis.literal(make_flagid(self.tabid, 1, self.varid, 113)),
            flag_descr=ibis.literal(
                f"Variable '{self.variable}' length exceeds SCDM max of {self.expected_length}"
            ),
            message=ibis.literal(""),
            flag_type=ibis.literal("Warn"),
            abort_yn=ibis.literal("N"),
        )


@dataclass(frozen=True)
class NullValuesCheck:
    """Check 120: Variable contains null values."""

    variable: str
    varid: str
    tabid: str = _MIL_TABID

    @property
    def metadata(self) -> CheckMetadata:
        return CheckMetadata(
            check_id="120",
            level=1,
            severity=Severity.WARN,
            tables=frozenset({"mil"}),
            output_scope=OutputScope.DPLOCAL,
            description=f"Variable '{self.variable}' contains null values",
            tabid=self.tabid,
        )

    def build(self, ctx: CheckContext) -> ibis.Table:
        session = ctx.session
        mil = session.table("mil")
        if self.variable not in mil.columns:
            return mil.filter(ibis.literal(False)).mutate(
                flagid=ibis.literal(make_flagid(self.tabid, 1, self.varid, 120)),
                flag_descr=ibis.literal(f"Variable '{self.variable}' contains null values"),
                message=ibis.literal(""),
                flag_type=ibis.literal("Warn"),
                abort_yn=ibis.literal("N"),
            )
        flagged = mil.filter(mil[self.variable].isnull())
        return flagged.mutate(
            flagid=ibis.literal(make_flagid(self.tabid, 1, self.varid, 120)),
            flag_descr=ibis.literal(f"Variable '{self.variable}' contains null values"),
            message=ibis.literal(""),
            flag_type=ibis.literal("Warn"),
            abort_yn=ibis.literal("N"),
        )


@dataclass(frozen=True)
class AgeRangeCheck:
    """Check 126: Age value must be between 10 and 54 inclusive."""

    variable: str = "Age"
    varid: str = "06"
    tabid: str = _MIL_TABID

    @property
    def metadata(self) -> CheckMetadata:
        return CheckMetadata(
            check_id="126",
            level=1,
            severity=Severity.WARN,
            tables=frozenset({"mil"}),
            output_scope=OutputScope.DPLOCAL,
            description="Age value outside range 10-54",
            tabid=self.tabid,
        )

    def build(self, ctx: CheckContext) -> ibis.Table:
        session = ctx.session
        mil = session.table("mil")
        if self.variable not in mil.columns:
            return mil.filter(ibis.literal(False)).mutate(
                flagid=ibis.literal(make_flagid(self.tabid, 1, self.varid, 126)),
                flag_descr=ibis.literal("Age value outside range 10-54"),
                message=ibis.literal(""),
                flag_type=ibis.literal("Warn"),
                abort_yn=ibis.literal("N"),
            )
        col = mil[self.variable]
        flagged = mil.filter(col.notnull() & ((col < 10) | (col > 54)))
        return flagged.mutate(
            flagid=ibis.literal(make_flagid(self.tabid, 1, self.varid, 126)),
            flag_descr=ibis.literal("Age value outside range 10-54"),
            message=ibis.literal(""),
            flag_type=ibis.literal("Warn"),
            abort_yn=ibis.literal("N"),
        )
