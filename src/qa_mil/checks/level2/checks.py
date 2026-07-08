"""Level 2 checks — duplicate/key, date/range, cross-table, enrollment families.

Source: inputfiles/scdm_data_qa_mil_review-level2.sas, inputfiles/scdm_qa_mil_standard_macros.sas
Inventory: docs/level2-inventory.md
"""

from __future__ import annotations

from dataclasses import dataclass
from typing import Any

import ibis

from qa_mil.checks.base import (
    CheckContext,
    CheckMetadata,
    OutputScope,
    flag_type_to_severity,
    make_flagid,
)
from qa_mil.lookups.models import CheckFlagDef

_MIL_TABID = "MIL"


# ---------------------------------------------------------------------------
# NUM-40: Duplicate/key family
# ---------------------------------------------------------------------------


@dataclass(frozen=True)
class DuplicateKeyCheck:
    """Check 211/217-219: Duplicate records by key columns.

    Flags rows where the specified key columns have duplicates.
    """

    check_id: str
    key_columns: tuple[str, ...]
    flag_def: CheckFlagDef
    tabid: str = _MIL_TABID

    def __post_init__(self) -> None:
        if self.flag_def.check_id != self.check_id:
            raise ValueError(
                f"flag_def.check_id={self.flag_def.check_id!r} does not match "
                f"check_id={self.check_id!r}"
            )

    @property
    def metadata(self) -> CheckMetadata:
        int(self.check_id)
        return CheckMetadata(
            check_id=self.check_id,
            level=2,
            severity=flag_type_to_severity(self.flag_def.flag_type),
            tables=frozenset({"mil"}),
            output_scope=OutputScope.DPLOCAL,
            description=self.flag_def.flag_descr,
            tabid=self.tabid,
        )

    def build(self, ctx: CheckContext) -> ibis.Table:
        session = ctx.session
        mil = session.table("mil")

        # Find duplicate keys
        key_list = list(self.key_columns)
        grouped = mil.group_by(key_list).aggregate(count=mil.count())
        dups = grouped.filter(grouped["count"] > 1)

        check_num = int(self.check_id)

        result = mil.join(dups, key_list).select(
            ibis.literal(make_flagid(self.tabid, 2, "00", check_num)).name("flagid"),
            ibis.literal(self.flag_def.flag_descr).name("flag_descr"),
            ibis.literal("").name("message"),
            ibis.literal(self.flag_def.flag_type).name("flag_type"),
            ibis.literal(self.flag_def.abort_yn).name("abort_yn"),
        )
        return result


# ---------------------------------------------------------------------------
# NUM-41: Date/range/value-domain family
# ---------------------------------------------------------------------------


@dataclass(frozen=True)
class DateRangeCheck:
    """Check 201-207: Date range/value validity.

    Flags rows where a date column is outside the specified min/max range.
    """

    check_id: str
    date_column: str
    flag_def: CheckFlagDef
    min_date: str | None = None
    max_date: str | None = None
    tabid: str = _MIL_TABID

    def __post_init__(self) -> None:
        if self.flag_def.check_id != self.check_id:
            raise ValueError(
                f"flag_def.check_id={self.flag_def.check_id!r} does not match "
                f"check_id={self.check_id!r}"
            )

    @property
    def metadata(self) -> CheckMetadata:
        return CheckMetadata(
            check_id=self.check_id,
            level=2,
            severity=flag_type_to_severity(self.flag_def.flag_type),
            tables=frozenset({"mil"}),
            output_scope=OutputScope.DPLOCAL,
            description=self.flag_def.flag_descr,
            tabid=self.tabid,
        )

    def build(self, ctx: CheckContext) -> ibis.Table:
        session = ctx.session
        mil = session.table("mil")
        if self.date_column not in mil.columns:
            return mil.filter(ibis.literal(False)).mutate(
                flagid=ibis.literal(make_flagid(self.tabid, 2, "00", self.check_id)),
                flag_descr=ibis.literal(self.flag_def.flag_descr),
                message=ibis.literal(""),
                flag_type=ibis.literal(self.flag_def.flag_type),
                abort_yn=ibis.literal(self.flag_def.abort_yn),
            )

        col = mil[self.date_column]
        conditions = []
        if self.min_date is not None:
            conditions.append(col < ibis.literal(self.min_date))
        if self.max_date is not None:
            conditions.append(col > ibis.literal(self.max_date))

        if not conditions:
            return mil.filter(ibis.literal(False)).mutate(
                flagid=ibis.literal(make_flagid(self.tabid, 2, "00", self.check_id)),
                flag_descr=ibis.literal(self.flag_def.flag_descr),
                message=ibis.literal(""),
                flag_type=ibis.literal(self.flag_def.flag_type),
                abort_yn=ibis.literal(self.flag_def.abort_yn),
            )

        combined = conditions[0]
        for cond in conditions[1:]:
            combined = combined | cond

        flagged = mil.filter(col.notnull() & combined)
        return flagged.mutate(
            flagid=ibis.literal(make_flagid(self.tabid, 2, "00", self.check_id)),
            flag_descr=ibis.literal(self.flag_def.flag_descr),
            message=ibis.literal(""),
            flag_type=ibis.literal(self.flag_def.flag_type),
            abort_yn=ibis.literal(self.flag_def.abort_yn),
        )


@dataclass(frozen=True)
class ValueDomainCheck:
    """Check 201-207: Value domain validation.

    Flags rows where a variable's value is not in the allowed set.
    """

    check_id: str
    variable: str
    allowed_values: tuple[Any, ...]
    flag_def: CheckFlagDef
    tabid: str = _MIL_TABID

    def __post_init__(self) -> None:
        if self.flag_def.check_id != self.check_id:
            raise ValueError(
                f"flag_def.check_id={self.flag_def.check_id!r} does not match "
                f"check_id={self.check_id!r}"
            )

    @property
    def metadata(self) -> CheckMetadata:
        return CheckMetadata(
            check_id=self.check_id,
            level=2,
            severity=flag_type_to_severity(self.flag_def.flag_type),
            tables=frozenset({"mil"}),
            output_scope=OutputScope.DPLOCAL,
            description=self.flag_def.flag_descr,
            tabid=self.tabid,
        )

    def build(self, ctx: CheckContext) -> ibis.Table:
        session = ctx.session
        mil = session.table("mil")
        if self.variable not in mil.columns:
            return mil.filter(ibis.literal(False)).mutate(
                flagid=ibis.literal(make_flagid(self.tabid, 2, "00", self.check_id)),
                flag_descr=ibis.literal(self.flag_def.flag_descr),
                message=ibis.literal(""),
                flag_type=ibis.literal(self.flag_def.flag_type),
                abort_yn=ibis.literal(self.flag_def.abort_yn),
            )

        col = mil[self.variable]
        # Flag values NOT in allowed set and NOT null
        in_set = ibis.literal(False)
        for val in self.allowed_values:
            in_set = in_set | (col == val)

        flagged = mil.filter(col.notnull() & ~in_set)  # type: ignore[operator]
        return flagged.mutate(
            flagid=ibis.literal(make_flagid(self.tabid, 2, "00", self.check_id)),
            flag_descr=ibis.literal(self.flag_def.flag_descr),
            message=ibis.literal(""),
            flag_type=ibis.literal(self.flag_def.flag_type),
            abort_yn=ibis.literal(self.flag_def.abort_yn),
        )


# ---------------------------------------------------------------------------
# NUM-42: Cross-table consistency family
# ---------------------------------------------------------------------------


@dataclass(frozen=True)
class CrossTableConsistencyCheck:
    """Check 221/223: Cross-table consistency.

    Flags records in MIL that don't have a matching record in a reference table.
    """

    check_id: str
    reference_table: str
    join_column: str
    flag_def: CheckFlagDef
    tabid: str = _MIL_TABID

    def __post_init__(self) -> None:
        if self.flag_def.check_id != self.check_id:
            raise ValueError(
                f"flag_def.check_id={self.flag_def.check_id!r} does not match "
                f"check_id={self.check_id!r}"
            )

    @property
    def metadata(self) -> CheckMetadata:
        return CheckMetadata(
            check_id=self.check_id,
            level=2,
            severity=flag_type_to_severity(self.flag_def.flag_type),
            tables=frozenset({"mil", self.reference_table}),
            output_scope=OutputScope.DPLOCAL,
            description=self.flag_def.flag_descr,
            tabid=self.tabid,
        )

    def build(self, ctx: CheckContext) -> ibis.Table:
        session = ctx.session
        mil = session.table("mil")
        ref = session.table(self.reference_table)

        if self.join_column not in mil.columns or self.join_column not in ref.columns:
            return mil.filter(ibis.literal(False)).mutate(
                flagid=ibis.literal(make_flagid(self.tabid, 2, "00", self.check_id)),
                flag_descr=ibis.literal(self.flag_def.flag_descr),
                message=ibis.literal(""),
                flag_type=ibis.literal(self.flag_def.flag_type),
                abort_yn=ibis.literal(self.flag_def.abort_yn),
            )

        # Find MIL records not in reference table
        col = mil[self.join_column]
        ref_ids = ref.filter(ref[self.join_column].notnull())[self.join_column]
        flagged = mil.filter(
            col.notnull() & ~col.isin(ref_ids)  # type: ignore[operator]
        )
        return flagged.mutate(
            flagid=ibis.literal(make_flagid(self.tabid, 2, "00", self.check_id)),
            flag_descr=ibis.literal(self.flag_def.flag_descr),
            message=ibis.literal(""),
            flag_type=ibis.literal(self.flag_def.flag_type),
            abort_yn=ibis.literal(self.flag_def.abort_yn),
        )


# ---------------------------------------------------------------------------
# NUM-43: Enrollment/eligibility family
# ---------------------------------------------------------------------------


@dataclass(frozen=True)
class EnrollmentCoverageCheck:
    """Check 200/272-275: MIL date outside enrollment coverage.

    Flags MIL records where a date falls outside the enrollment period.
    """

    check_id: str
    date_column: str
    flag_def: CheckFlagDef
    patid_column: str = "MPatID"
    enr_start_column: str = "EnrStart"
    enr_end_column: str = "EnrEnd"
    tabid: str = _MIL_TABID

    def __post_init__(self) -> None:
        if self.flag_def.check_id != self.check_id:
            raise ValueError(
                f"flag_def.check_id={self.flag_def.check_id!r} does not match "
                f"check_id={self.check_id!r}"
            )

    @property
    def metadata(self) -> CheckMetadata:
        return CheckMetadata(
            check_id=self.check_id,
            level=2,
            severity=flag_type_to_severity(self.flag_def.flag_type),
            tables=frozenset({"mil", "enr"}),
            output_scope=OutputScope.DPLOCAL,
            description=self.flag_def.flag_descr,
            tabid=self.tabid,
        )

    def build(self, ctx: CheckContext) -> ibis.Table:
        session = ctx.session
        mil = session.table("mil")
        enr = session.table("enr")

        if self.date_column not in mil.columns:
            return mil.filter(ibis.literal(False)).mutate(
                flagid=ibis.literal(make_flagid(self.tabid, 2, "00", self.check_id)),
                flag_descr=ibis.literal(self.flag_def.flag_descr),
                message=ibis.literal(""),
                flag_type=ibis.literal(self.flag_def.flag_type),
                abort_yn=ibis.literal(self.flag_def.abort_yn),
            )

        date_col = mil[self.date_column]
        patid_col = mil[self.patid_column]
        enr_patid = enr[self.patid_column] if self.patid_column in enr.columns else enr.columns[0]

        # Left join MIL to enrollment on PatID
        joined = mil.left_join(
            enr,
            patid_col == enr_patid,
        )

        # Flag rows where date is outside enrollment period
        enr_start = (
            joined[f"{self.enr_start_column}_right"]
            if f"{self.enr_start_column}_right" in joined.columns
            else joined[self.enr_start_column]
        )
        enr_end = (
            joined[f"{self.enr_end_column}_right"]
            if f"{self.enr_end_column}_right" in joined.columns
            else joined[self.enr_end_column]
        )

        outside = joined.filter(
            date_col.notnull()
            & enr_start.notnull()
            & enr_end.notnull()
            & ((date_col < enr_start) | (date_col > enr_end))
        )

        return outside.select(
            ibis.literal(make_flagid(self.tabid, 2, "00", self.check_id)).name("flagid"),
            ibis.literal(self.flag_def.flag_descr).name("flag_descr"),
            ibis.literal("").name("message"),
            ibis.literal(self.flag_def.flag_type).name("flag_type"),
            ibis.literal(self.flag_def.abort_yn).name("abort_yn"),
        )
