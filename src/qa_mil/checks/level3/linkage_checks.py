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
    flag_type_to_severity,
    make_flagid,
)
from qa_mil.lookups.models import CheckFlagDef

_MIL_TABID = "MIL"


@dataclass(frozen=True)
class BirthTypeNoLinkageCheck:
    """Check 394: Birth_Type 2-8 with no CPatIDs linked.

    Flags records where Birth_Type is between 2 and 8 but CPatID is missing.
    These are 'orphaned' mother records that should have linked infant records.
    """

    flag_def: CheckFlagDef
    tabid: str = _MIL_TABID

    @property
    def metadata(self) -> CheckMetadata:
        return CheckMetadata(
            check_id="394",
            level=3,
            severity=flag_type_to_severity(self.flag_def.flag_type),
            tables=frozenset({"mil"}),
            output_scope=OutputScope.DPLOCAL,
            description=self.flag_def.flag_descr,
            tabid=self.tabid,
        )

    def build(self, ctx: CheckContext) -> ibis.Table:
        session = ctx.session
        mil = session.table("mil")
        col = mil["Birth_Type"]
        flagged = mil.filter(col.notnull() & (col >= 2) & (col <= 8) & mil["CPatID"].isnull())
        return flagged.mutate(
            flagid=ibis.literal(make_flagid(self.tabid, 3, "00", 394)),
            flag_descr=ibis.literal(self.flag_def.flag_descr),
            message=ibis.literal(""),
            flag_type=ibis.literal(self.flag_def.flag_type),
            abort_yn=ibis.literal(self.flag_def.abort_yn),
        )


@dataclass(frozen=True)
class MotherNotLinkedCheck:
    """Check 396: MPatID not linked to CPatID (mother without infant).

    Flags records where MPatID exists but CPatID is missing.
    """

    flag_def: CheckFlagDef
    tabid: str = _MIL_TABID

    @property
    def metadata(self) -> CheckMetadata:
        return CheckMetadata(
            check_id="396",
            level=3,
            severity=flag_type_to_severity(self.flag_def.flag_type),
            tables=frozenset({"mil"}),
            output_scope=OutputScope.DPLOCAL,
            description=self.flag_def.flag_descr,
            tabid=self.tabid,
        )

    def build(self, ctx: CheckContext) -> ibis.Table:
        session = ctx.session
        mil = session.table("mil")
        flagged = mil.filter(mil["CPatID"].isnull() & mil["MPatID"].notnull())
        return flagged.mutate(
            flagid=ibis.literal(make_flagid(self.tabid, 3, "00", 396)),
            flag_descr=ibis.literal(self.flag_def.flag_descr),
            message=ibis.literal(""),
            flag_type=ibis.literal(self.flag_def.flag_type),
            abort_yn=ibis.literal(self.flag_def.abort_yn),
        )


@dataclass(frozen=True)
class InfantNotLinkedCheck:
    """Check 397: CPatID not linked to MPatID (infant without mother).

    Flags records where CPatID exists but MPatID is missing.
    """

    flag_def: CheckFlagDef
    tabid: str = _MIL_TABID

    @property
    def metadata(self) -> CheckMetadata:
        return CheckMetadata(
            check_id="397",
            level=3,
            severity=flag_type_to_severity(self.flag_def.flag_type),
            tables=frozenset({"mil"}),
            output_scope=OutputScope.DPLOCAL,
            description=self.flag_def.flag_descr,
            tabid=self.tabid,
        )

    def build(self, ctx: CheckContext) -> ibis.Table:
        session = ctx.session
        mil = session.table("mil")
        flagged = mil.filter(mil["CPatID"].notnull() & mil["MPatID"].isnull())
        return flagged.mutate(
            flagid=ibis.literal(make_flagid(self.tabid, 3, "00", 397)),
            flag_descr=ibis.literal(self.flag_def.flag_descr),
            message=ibis.literal(""),
            flag_type=ibis.literal(self.flag_def.flag_type),
            abort_yn=ibis.literal(self.flag_def.abort_yn),
        )
