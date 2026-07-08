"""Tests for check framework: flagid, registry, base models (NUM-32)."""

from __future__ import annotations

import pytest

from qa_mil.checks.base import (
    CheckMetadata,
    FlagRow,
    OutputScope,
    Severity,
    make_flagid,
)
from qa_mil.checks.registry import (
    disabled_checks,
    enabled_checks,
    level_ordered_groups,
    list_checks,
    required_tables,
)

# ---------------------------------------------------------------------------
# flagid helper
# ---------------------------------------------------------------------------


class TestFlagId:
    def test_table_level_flagid(self) -> None:
        assert make_flagid("MIL", 3, "00", 371) == "MIL_3_00_00-0_371"

    def test_variable_level_flagid(self) -> None:
        assert make_flagid("MIL", 1, "MPATID", 110) == "MIL_1_MPATID_00-0_110"

    def test_tabid_uppercased(self) -> None:
        assert make_flagid("mil", 3, "00", 375) == "MIL_3_00_00-0_375"

    def test_checknum_as_string(self) -> None:
        assert make_flagid("MIL", 3, "00", "371") == "MIL_3_00_00-0_371"

    @pytest.mark.parametrize(
        "tabid,level,varid,checknum,expected",
        [
            ("MIL", 1, "00", 100, "MIL_1_00_00-0_100"),
            ("MIL", 2, "00", 200, "MIL_2_00_00-0_200"),
            ("MIL", 3, "00", 394, "MIL_3_00_00-0_394"),
            ("MIL", 3, "00", 396, "MIL_3_00_00-0_396"),
            ("MIL", 3, "00", 397, "MIL_3_00_00-0_397"),
        ],
    )
    def test_flagid_patterns(
        self, tabid: str, level: int, varid: str, checknum: int, expected: str
    ) -> None:
        assert make_flagid(tabid, level, varid, checknum) == expected


# ---------------------------------------------------------------------------
# Enums
# ---------------------------------------------------------------------------


class TestEnums:
    def test_severity_values(self) -> None:
        assert Severity.WARN.value == "Warn"
        assert Severity.ABORT.value == "Abort"

    def test_output_scope_values(self) -> None:
        assert OutputScope.DPLOCAL.value == "dplocal"
        assert OutputScope.MSOC.value == "msoc"


# ---------------------------------------------------------------------------
# Registry
# ---------------------------------------------------------------------------


class TestRegistry:
    def test_list_checks_has_371_375(self) -> None:
        checks = list_checks()
        check_ids = {c.metadata.check_id for c in checks}
        assert {"371", "372", "373", "374", "375"}.issubset(check_ids)

    def test_list_checks_has_level_1(self) -> None:
        checks = list_checks()
        check_ids = {c.metadata.check_id for c in checks}
        assert {"100", "101", "110"}.issubset(check_ids)
        assert "102" not in check_ids  # SAS-only physical sort-order check is de-scoped

    def test_list_checks_all_dplocal(self) -> None:
        checks = list_checks()
        for check in checks:
            assert check.metadata.output_scope == OutputScope.DPLOCAL

    def test_list_checks_all_require_mil(self) -> None:
        checks = list_checks()
        for check in checks:
            assert "mil" in check.metadata.tables

    def test_enabled_checks_no_filter(self) -> None:
        enabled = enabled_checks()
        assert len(enabled) == len(list_checks())

    def test_enabled_checks_with_disabled(self) -> None:
        enabled = enabled_checks(disabled_ids=["371"])
        check_ids = {c.metadata.check_id for c in enabled}
        assert "371" not in check_ids
        assert "372" in check_ids

    def test_enabled_checks_with_enabled_only(self) -> None:
        enabled = enabled_checks(enabled_ids=["371", "375"])
        check_ids = {c.metadata.check_id for c in enabled}
        assert check_ids == {"371", "375"}

    def test_disabled_checks(self) -> None:
        disabled = disabled_checks(["371", "372"])
        check_ids = {c.metadata.check_id for c in disabled}
        assert check_ids == {"371", "372"}

    def test_required_tables(self) -> None:
        tables = required_tables()
        assert "mil" in tables
        assert len(tables["mil"]) >= 5  # at least 371-375

    def test_required_tables_with_disabled(self) -> None:
        tables = required_tables(disabled_ids=["371"])
        assert "371" not in tables["mil"]

    def test_level_ordered_groups(self) -> None:
        groups = level_ordered_groups()
        assert len(groups) >= 1  # at least Level 1 and/or Level 3


# ---------------------------------------------------------------------------
# CheckMetadata
# ---------------------------------------------------------------------------


class TestCheckMetadata:
    def test_metadata_immutable(self) -> None:
        md = CheckMetadata(
            check_id="371",
            level=3,
            severity=Severity.WARN,
            tables=frozenset({"mil"}),
            output_scope=OutputScope.DPLOCAL,
            description="test",
            tabid="MIL",
        )
        with pytest.raises(AttributeError):
            md.check_id = "999"  # type: ignore[misc]


# ---------------------------------------------------------------------------
# FlagRow
# ---------------------------------------------------------------------------


class TestFlagRow:
    def test_flag_row_creation(self) -> None:
        fr = FlagRow(
            flagid="MIL_3_00_00-0_371",
            flag_descr="test description",
            message="test message",
            flag_type="Warn",
            abort_yn="N",
        )
        assert fr.flagid == "MIL_3_00_00-0_371"
        assert fr.flag_type == "Warn"
