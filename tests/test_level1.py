"""Tests for Level 1 checks and JSON lookup metadata (NUM-34)."""

from __future__ import annotations

from pathlib import Path

from qa_mil.checks.base import Severity, make_flagid
from qa_mil.checks.level1.checks import (
    AgeRangeCheck,
    MissingColumnCheck,
    NullValuesCheck,
    TableExistsCheck,
    VariableLengthCheck,
)
from qa_mil.checks.registry import list_checks
from qa_mil.lookups.loader import (
    load_all,
    load_check_flags,
    load_id_lengths,
    load_l1_rules,
    load_variable_lengths,
)
from tests.conftest import make_mil_data, write_parquet

# ---------------------------------------------------------------------------
# Lookup JSON validation
# ---------------------------------------------------------------------------


class TestLookupJSON:
    def test_checks_json_parses(self) -> None:
        flags = load_check_flags()
        assert len(flags) > 0
        assert all(f.check_id for f in flags)

    def test_l1_rules_json_parses(self) -> None:
        rules = load_l1_rules()
        assert len(rules) > 0
        assert all(r.variable for r in rules)

    def test_variable_lengths_json_parses(self) -> None:
        lengths = load_variable_lengths()
        assert len(lengths) > 0

    def test_id_lengths_json_parses(self) -> None:
        lengths = load_id_lengths()
        assert len(lengths) > 0

    def test_load_all(self) -> None:
        data = load_all()
        assert len(data.check_flags) > 0
        assert len(data.l1_rules) > 0

    def test_provenance_readme_exists(self) -> None:
        readme = Path(__file__).parent.parent / "src" / "qa_mil" / "lookups" / "README.md"
        assert readme.exists()

    def test_check_flags_have_valid_severity(self) -> None:
        flags = load_check_flags()
        for f in flags:
            assert f.flag_type in ("Warn", "Abort")

    def test_check_flags_have_valid_abort_yn(self) -> None:
        flags = load_check_flags()
        for f in flags:
            assert f.abort_yn in ("Y", "N")


# ---------------------------------------------------------------------------
# Level 1 registry coverage
# ---------------------------------------------------------------------------


class TestLevel1Registry:
    def test_list_checks_includes_level_1(self) -> None:
        checks = list_checks()
        level1 = [c for c in checks if c.metadata.level == 1]
        assert len(level1) > 0

    def test_list_checks_includes_100_101(self) -> None:
        checks = list_checks()
        ids = {c.metadata.check_id for c in checks}
        assert {"100", "101"}.issubset(ids)

    def test_check_102_not_registered(self) -> None:
        """Check 102 is SAS-only physical sort-order validation, de-scoped for parquet."""
        checks = list_checks()
        ids = {c.metadata.check_id for c in checks}
        assert "102" not in ids

    def test_list_checks_includes_110_111_112_113(self) -> None:
        checks = list_checks()
        ids = {c.metadata.check_id for c in checks}
        assert {"110", "111", "112", "113"}.issubset(ids)

    def test_list_checks_includes_120_126(self) -> None:
        checks = list_checks()
        ids = {c.metadata.check_id for c in checks}
        assert {"120", "126"}.issubset(ids)

    def test_table_checks_are_abort(self) -> None:
        checks = list_checks()
        table_checks = [c for c in checks if c.metadata.check_id in ("100", "101")]
        for check in table_checks:
            assert check.metadata.severity == Severity.ABORT

    def test_check_130_not_registered(self) -> None:
        """Check 130 is inactive/not applicable — should not be registered."""
        checks = list_checks()
        ids = {c.metadata.check_id for c in checks}
        assert "130" not in ids


# ---------------------------------------------------------------------------
# Level 1 check behavior with engine
# ---------------------------------------------------------------------------


def _make_session(mil_path: Path):
    """Create a DuckDB session with a MIL parquet file."""
    from qa_mil.engine.duckdb import DuckDbSession

    return DuckDbSession({"mil": mil_path})


class TestLevel1CheckBehavior:
    def test_table_exists_check_no_flags_when_present(self, tmp_path: Path) -> None:
        mil_path = tmp_path / "mil.parquet"
        write_parquet(mil_path, make_mil_data())
        with _make_session(mil_path) as session:
            from qa_mil.checks.base import CheckContext

            ctx = CheckContext(session=session, metadata=TableExistsCheck().metadata)
            result = session.execute(TableExistsCheck().build(ctx))
            assert len(result) == 0  # No flags — table exists

    def test_missing_column_check_flags_absent_variable(self, tmp_path: Path) -> None:
        """Check 110 flags when a required SCDM variable is missing."""
        mil_path = tmp_path / "mil.parquet"
        # Create a table without EncounterID
        write_parquet(
            mil_path,
            {
                "MPatID": ["M001"],
                "CPatID": ["C001"],
                "ADate": ["2020-01-15"],
                "Birth_Type": [1],
            },
        )
        with _make_session(mil_path) as session:
            from qa_mil.checks.base import CheckContext

            check = MissingColumnCheck(variable="EncounterID", varid="04")
            ctx = CheckContext(session=session, metadata=check.metadata)
            result = session.execute(check.build(ctx))
            assert len(result) == 1  # Flag row for missing variable
            assert "110" in result["flagid"].iloc[0]

    def test_missing_column_check_no_flags_when_present(self, tmp_path: Path) -> None:
        mil_path = tmp_path / "mil.parquet"
        write_parquet(mil_path, make_mil_data())
        with _make_session(mil_path) as session:
            from qa_mil.checks.base import CheckContext

            check = MissingColumnCheck(variable="MPatID", varid="01")
            ctx = CheckContext(session=session, metadata=check.metadata)
            result = session.execute(check.build(ctx))
            assert len(result) == 0  # No flags — variable exists

    def test_null_values_check_flags_nulls(self, tmp_path: Path) -> None:
        """Check 120 flags rows where a variable has null values."""
        mil_path = tmp_path / "mil.parquet"
        write_parquet(
            mil_path,
            {
                "MPatID": ["M001", None, "M003"],
                "CPatID": ["C001", "C002", "C003"],
                "ADate": ["2020-01-15", "2020-02-20", "2020-03-10"],
                "EncounterID": ["E1", "E2", "E3"],
                "Birth_Type": [1, 2, 1],
            },
        )
        with _make_session(mil_path) as session:
            from qa_mil.checks.base import CheckContext

            check = NullValuesCheck(variable="MPatID", varid="01")
            ctx = CheckContext(session=session, metadata=check.metadata)
            result = session.execute(check.build(ctx))
            assert len(result) == 1  # One null MPatID
            assert "120" in result["flagid"].iloc[0]

    def test_age_range_check_flags_out_of_range(self, tmp_path: Path) -> None:
        """Check 126 flags age values outside 10-54."""
        mil_path = tmp_path / "mil.parquet"
        write_parquet(
            mil_path,
            {
                "MPatID": ["M001", "M002", "M003"],
                "CPatID": ["C001", "C002", "C003"],
                "ADate": ["2020-01-15", "2020-02-20", "2020-03-10"],
                "EncounterID": ["E1", "E2", "E3"],
                "Birth_Type": [1, 2, 1],
                "Age": [25, 5, 60],  # 5 and 60 are out of range
            },
        )
        with _make_session(mil_path) as session:
            from qa_mil.checks.base import CheckContext

            check = AgeRangeCheck()
            ctx = CheckContext(session=session, metadata=check.metadata)
            result = session.execute(check.build(ctx))
            assert len(result) == 2  # 5 and 60 flagged
            assert "126" in result["flagid"].iloc[0]

    def test_variable_length_check_flags_excessive_string(self, tmp_path: Path) -> None:
        """Check 113 flags string values exceeding expected SAS length."""
        mil_path = tmp_path / "mil.parquet"
        write_parquet(
            mil_path,
            {
                "MPatID": ["short", "this_is_a_very_long_id_exceeding_20_chars"],
                "CPatID": ["C001", "C002"],
                "ADate": ["2020-01-15", "2020-02-20"],
                "EncounterID": ["E1", "E2"],
                "Birth_Type": [1, 2],
            },
        )
        with _make_session(mil_path) as session:
            from qa_mil.checks.base import CheckContext

            check = VariableLengthCheck(variable="MPatID", varid="01", expected_length=20)
            ctx = CheckContext(session=session, metadata=check.metadata)
            result = session.execute(check.build(ctx))
            assert len(result) == 1  # Long MPatID flagged
            assert "113" in result["flagid"].iloc[0]

    def test_variable_length_check_skips_numeric(self, tmp_path: Path) -> None:
        """Check 113 should not apply to numeric columns."""
        mil_path = tmp_path / "mil.parquet"
        write_parquet(mil_path, make_mil_data())
        with _make_session(mil_path) as session:
            from qa_mil.checks.base import CheckContext

            check = VariableLengthCheck(variable="Birth_Type", varid="05", expected_length=8)
            ctx = CheckContext(session=session, metadata=check.metadata)
            result = session.execute(check.build(ctx))
            assert len(result) == 0  # No flags — numeric column

    def test_table_populated_check_flags_empty_table(self, tmp_path: Path) -> None:
        """Check 101 must emit an Abort flag when the MIL table has zero rows."""
        from qa_mil.checks.level1.checks import TablePopulatedCheck

        mil_path = tmp_path / "mil.parquet"
        # Write an empty parquet (schema but no rows)
        write_parquet(
            mil_path,
            {"MPatID": [], "CPatID": [], "ADate": [], "EncounterID": [], "Birth_Type": []},
        )
        with _make_session(mil_path) as session:
            from qa_mil.checks.base import CheckContext

            check = TablePopulatedCheck()
            ctx = CheckContext(session=session, metadata=check.metadata)
            result = session.execute(check.build(ctx))
            assert len(result) == 1  # Single flag row
            assert result["flagid"].iloc[0] == "MIL_1_00_00-0_101"
            assert result["flag_type"].iloc[0] == "Abort"
            assert result["abort_yn"].iloc[0] == "Y"

    def test_table_populated_check_no_flags_when_populated(self, tmp_path: Path) -> None:
        """Check 101 must NOT emit any flag when the MIL table has data."""
        from qa_mil.checks.level1.checks import TablePopulatedCheck

        mil_path = tmp_path / "mil.parquet"
        write_parquet(mil_path, make_mil_data())
        with _make_session(mil_path) as session:
            from qa_mil.checks.base import CheckContext

            check = TablePopulatedCheck()
            ctx = CheckContext(session=session, metadata=check.metadata)
            result = session.execute(check.build(ctx))
            assert len(result) == 0  # No flags — table is populated

    def test_flagid_format_for_level1(self) -> None:
        """FlagID format: {TABID}_1_{varid}_00-0_{checknum}"""
        # Table-level check
        assert make_flagid("MIL", 1, "00", 100) == "MIL_1_00_00-0_100"
        # Variable-level check
        assert make_flagid("MIL", 1, "01", 110) == "MIL_1_01_00-0_110"
