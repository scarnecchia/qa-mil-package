"""Birth_Type linkage consistency checks 371–375.

Source: ``inputfiles/scdm_data_qa_mil_review-level3.sas`` lines 110–157.

For each Birth_Type value (1–5), counts distinct CPatID records grouped by
MPatID, ADate, EncounterID, Birth_Type. If the count of linked infant
records (crows) doesn't match the Birth_Type value, flag the record.
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


@dataclass(frozen=True)
class BirthTypeLinkageCheck:
    """Parameterized Level 3 check for Birth_Type linkage consistency.

    One instance per Birth_Type value (1–5), producing checks 371–375.
    """

    birth_type: int
    flag_def: CheckFlagDef
    tabid: str = "MIL"

    @property
    def metadata(self) -> CheckMetadata:
        check_num = 370 + self.birth_type
        return CheckMetadata(
            check_id=str(check_num),
            level=3,
            severity=flag_type_to_severity(self.flag_def.flag_type),
            tables=frozenset({"mil"}),
            output_scope=OutputScope.DPLOCAL,
            description=self.flag_def.flag_descr,
            tabid=self.tabid,
        )

    def build(self, ctx: CheckContext) -> ibis.Table:
        """Build the Ibis expression for this check.

        Groups by MPatID, ADate, EncounterID, Birth_Type where Birth_Type matches
        this check's value, counts distinct CPatID, and flags rows where the
        count doesn't match the Birth_Type value.
        """
        session = ctx.session
        mil = session.table("mil")

        check_num = 370 + self.birth_type
        flagid = make_flagid(self.tabid, 3, "00", check_num)

        # Filter to this Birth_Type value, non-null CPatID and MPatID
        filtered = mil.filter(
            (mil["Birth_Type"] == self.birth_type)
            & mil["CPatID"].notnull()
            & mil["MPatID"].notnull()
        )

        # Count distinct CPatID per group
        grouped = filtered.group_by(["MPatID", "ADate", "EncounterID", "Birth_Type"]).aggregate(
            crows=filtered["CPatID"].nunique()
        )

        # Flag rows where count doesn't match Birth_Type
        flagged = grouped.filter(grouped["crows"] != grouped["Birth_Type"])

        # Add flag columns
        result = flagged.mutate(
            flagid=ibis.literal(flagid),
            flag_descr=ibis.literal(self.flag_def.flag_descr),
            message=(ibis.literal("")),  # message is informational, built per-row in output layer
            flag_type=ibis.literal(self.flag_def.flag_type),
            abort_yn=ibis.literal(self.flag_def.abort_yn),
        )

        return result
