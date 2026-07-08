"""Level 3 checks 394, 396, 397 — Birth_Type/linkage checks.

Source: inputfiles/scdm_data_qa_mil_review-level3.sas lines 159–213.

- 394: Birth_Type 2-8 with no CPatIDs linked
- 396: MPatID not linked to CPatID (mother without infant)
- 397: CPatID not linked to MPatID (infant without mother)
"""

from __future__ import annotations

from dataclasses import dataclass

import ibis

from qa_mil.checks.base import (
    CheckContext,
    CheckMetadata,
    OutputScope,
    Severity,
    make_flagid,
)

_MIL_TABID = "MIL"


@dataclass(frozen=True)
class BirthTypeNoLinkageCheck:
    """Check 394: Birth_Type 2-8 with no CPatIDs linked.

    Flags records where Birth_Type is between 2 and 8 but CPatID is missing.
    These are 'orphaned' mother records that should have linked infant records.
    """

    tabid: str = _MIL_TABID

    @property
    def metadata(self) -> CheckMetadata:
        return CheckMetadata(
            check_id="394",
            level=3,
            severity=Severity.WARN,
            tables=frozenset({"mil"}),
            output_scope=OutputScope.DPLOCAL,
            description="Birth_Type 2-8 with no CPatIDs linked",
            tabid=self.tabid,
        )

    def build(self, ctx: CheckContext) -> ibis.Table:
        session = ctx.session
        mil = session.table("mil")
        col = mil["Birth_Type"]
        flagged = mil.filter(col.notnull() & (col >= 2) & (col <= 8) & mil["CPatID"].isnull())
        return flagged.mutate(
            flagid=ibis.literal(make_flagid(self.tabid, 3, "00", 394)),
            flag_descr=ibis.literal("Birth_Type= 2-8 and no CPatIDs are linked"),
            message=ibis.literal(""),
            flag_type=ibis.literal("Warn"),
            abort_yn=ibis.literal("N"),
        )


@dataclass(frozen=True)
class MotherNotLinkedCheck:
    """Check 396: MPatID not linked to CPatID (mother without infant).

    Flags records where MPatID exists but CPatID is missing.
    """

    tabid: str = _MIL_TABID

    @property
    def metadata(self) -> CheckMetadata:
        return CheckMetadata(
            check_id="396",
            level=3,
            severity=Severity.WARN,
            tables=frozenset({"mil"}),
            output_scope=OutputScope.DPLOCAL,
            description="MPatID not linked to CPatID",
            tabid=self.tabid,
        )

    def build(self, ctx: CheckContext) -> ibis.Table:
        session = ctx.session
        mil = session.table("mil")
        flagged = mil.filter(mil["CPatID"].isnull() & mil["MPatID"].notnull())
        return flagged.mutate(
            flagid=ibis.literal(make_flagid(self.tabid, 3, "00", 396)),
            flag_descr=ibis.literal("MPatID not linked to CPatID"),
            message=ibis.literal(""),
            flag_type=ibis.literal("Warn"),
            abort_yn=ibis.literal("N"),
        )


@dataclass(frozen=True)
class InfantNotLinkedCheck:
    """Check 397: CPatID not linked to MPatID (infant without mother).

    Flags records where CPatID exists but MPatID is missing.
    """

    tabid: str = _MIL_TABID

    @property
    def metadata(self) -> CheckMetadata:
        return CheckMetadata(
            check_id="397",
            level=3,
            severity=Severity.WARN,
            tables=frozenset({"mil"}),
            output_scope=OutputScope.DPLOCAL,
            description="CPatID not linked to MPatID",
            tabid=self.tabid,
        )

    def build(self, ctx: CheckContext) -> ibis.Table:
        session = ctx.session
        mil = session.table("mil")
        flagged = mil.filter(mil["CPatID"].notnull() & mil["MPatID"].isnull())
        return flagged.mutate(
            flagid=ibis.literal(make_flagid(self.tabid, 3, "00", 397)),
            flag_descr=ibis.literal("CPatID not linked to MPatID"),
            message=ibis.literal(""),
            flag_type=ibis.literal("Warn"),
            abort_yn=ibis.literal("N"),
        )
