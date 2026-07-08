"""Tests for Level 2 checks: duplicate/key, date/range, cross-table, enrollment (NUM-40-43)."""

from __future__ import annotations

from pathlib import Path

from qa_mil.checks.base import CheckContext, Severity, flag_type_to_severity
from qa_mil.checks.level2.checks import (
    CrossTableConsistencyCheck,
    DateRangeCheck,
    DuplicateKeyCheck,
    EnrollmentCoverageCheck,
    ValueDomainCheck,
)
from qa_mil.checks.registry import list_checks
from qa_mil.lookups.loader import get_check_flag
from tests.conftest import write_parquet


def _make_session(table_paths: dict[str, Path]):
    """Create a DuckDB session."""
    from qa_mil.engine.duckdb import DuckDbSession

    return DuckDbSession(table_paths)


# ---------------------------------------------------------------------------
# Registry coverage
# ---------------------------------------------------------------------------


class TestLevel2Registry:
    def test_level2_checks_registered(self) -> None:
        checks = list_checks()
        level2 = [c for c in checks if c.metadata.level == 2]
        assert len(level2) >= 9  # At least 9 Level 2 checks

    def test_level2_check_ids(self) -> None:
        checks = list_checks()
        ids = {c.metadata.check_id for c in checks if c.metadata.level == 2}
        assert {"211", "217", "218", "219", "201", "204", "221", "223", "200"}.issubset(ids)

    def test_level2_has_abort_checks(self) -> None:
        checks = list_checks()
        level2_abort = [
            c for c in checks if c.metadata.level == 2 and c.metadata.severity == Severity.ABORT
        ]
        assert len(level2_abort) > 0


# ---------------------------------------------------------------------------
# NUM-40: Duplicate/key family
# ---------------------------------------------------------------------------


class TestDuplicateKeyCheck:
    def test_flags_duplicate_keys(self, tmp_path: Path) -> None:
        mil_path = tmp_path / "mil.parquet"
        write_parquet(
            mil_path,
            {
                "MPatID": ["M001", "M001", "M002"],
                "CPatID": ["C001", "C001", "C003"],
                "ADate": ["2020-01-15", "2020-01-15", "2020-02-20"],
                "EncounterID": ["E1", "E1", "E2"],
                "Birth_Type": [1, 1, 2],
            },
        )
        with _make_session({"mil": mil_path}) as session:
            check = DuplicateKeyCheck(
                check_id="211",
                key_columns=("MPatID", "CPatID", "ADate"),
                flag_def=get_check_flag("211"),
            )
            ctx = CheckContext(session=session, metadata=check.metadata)
            result = session.execute(check.build(ctx))
            assert len(result) >= 2  # At least the duplicate rows flagged
            assert "211" in result["flagid"].iloc[0]

    def test_no_flags_when_unique(self, tmp_path: Path) -> None:
        mil_path = tmp_path / "mil.parquet"
        write_parquet(
            mil_path,
            {
                "MPatID": ["M001", "M002"],
                "CPatID": ["C001", "C002"],
                "ADate": ["2020-01-15", "2020-02-20"],
                "EncounterID": ["E1", "E2"],
                "Birth_Type": [1, 2],
            },
        )
        with _make_session({"mil": mil_path}) as session:
            check = DuplicateKeyCheck(
                check_id="211", key_columns=("MPatID", "CPatID"), flag_def=get_check_flag("211")
            )
            ctx = CheckContext(session=session, metadata=check.metadata)
            result = session.execute(check.build(ctx))
            assert len(result) == 0


# ---------------------------------------------------------------------------
# NUM-41: Date/range/value-domain family
# ---------------------------------------------------------------------------


class TestDateRangeCheck:
    def test_flags_out_of_range_dates(self, tmp_path: Path) -> None:
        mil_path = tmp_path / "mil.parquet"
        write_parquet(
            mil_path,
            {
                "MPatID": ["M001", "M002", "M003"],
                "CPatID": ["C001", "C002", "C003"],
                "ADate": ["2005-01-15", "2020-03-20", "2030-06-10"],  # 2005 and 2030 out of range
                "EncounterID": ["E1", "E2", "E3"],
                "Birth_Type": [1, 2, 1],
            },
        )
        with _make_session({"mil": mil_path}) as session:
            check = DateRangeCheck(
                check_id="201",
                date_column="ADate",
                flag_def=get_check_flag("201"),
                min_date="2010-01-01",
                max_date="2025-12-31",
            )
            ctx = CheckContext(session=session, metadata=check.metadata)
            result = session.execute(check.build(ctx))
            assert len(result) == 2  # 2005 and 2030 flagged
            assert "201" in result["flagid"].iloc[0]

    def test_no_flags_when_in_range(self, tmp_path: Path) -> None:
        from tests.conftest import make_mil_data

        mil_path = tmp_path / "mil.parquet"
        write_parquet(mil_path, make_mil_data())
        with _make_session({"mil": mil_path}) as session:
            check = DateRangeCheck(
                check_id="201",
                date_column="ADate",
                flag_def=get_check_flag("201"),
                min_date="2010-01-01",
                max_date="2025-12-31",
            )
            ctx = CheckContext(session=session, metadata=check.metadata)
            result = session.execute(check.build(ctx))
            assert len(result) == 0  # All dates in default fixture are in range


class TestValueDomainCheck:
    def test_flags_invalid_birth_type(self, tmp_path: Path) -> None:
        mil_path = tmp_path / "mil.parquet"
        write_parquet(
            mil_path,
            {
                "MPatID": ["M001", "M002"],
                "CPatID": ["C001", "C002"],
                "ADate": ["2020-01-15", "2020-02-20"],
                "EncounterID": ["E1", "E2"],
                "Birth_Type": [1, 99],  # 99 is invalid
            },
        )
        with _make_session({"mil": mil_path}) as session:
            check = ValueDomainCheck(
                check_id="204",
                variable="Birth_Type",
                allowed_values=(1, 2, 3, 4, 5, 6, 7, 8),
                flag_def=get_check_flag("204"),
            )
            ctx = CheckContext(session=session, metadata=check.metadata)
            result = session.execute(check.build(ctx))
            assert len(result) == 1  # Birth_Type=99 flagged
            assert "204" in result["flagid"].iloc[0]


# ---------------------------------------------------------------------------
# NUM-42: Cross-table consistency family
# ---------------------------------------------------------------------------


class TestCrossTableConsistency:
    def test_flags_records_not_in_reference(self, tmp_path: Path) -> None:
        mil_path = tmp_path / "mil.parquet"
        enr_path = tmp_path / "enr.parquet"
        write_parquet(
            mil_path,
            {
                "MPatID": ["M001", "M002", "M003"],  # M003 not in enrollment
                "CPatID": ["C001", "C002", "C003"],
                "ADate": ["2020-01-15", "2020-02-20", "2020-03-10"],
                "EncounterID": ["E1", "E2", "E3"],
                "Birth_Type": [1, 2, 1],
            },
        )
        write_parquet(
            enr_path,
            {
                "MPatID": ["M001", "M002"],  # M003 missing
                "EnrStart": ["2020-01-01", "2020-01-01"],
                "EnrEnd": ["2020-12-31", "2020-12-31"],
            },
        )
        with _make_session({"mil": mil_path, "enr": enr_path}) as session:
            check = CrossTableConsistencyCheck(
                check_id="221",
                reference_table="enr",
                join_column="MPatID",
                flag_def=get_check_flag("221"),
            )
            ctx = CheckContext(session=session, metadata=check.metadata)
            result = session.execute(check.build(ctx))
            assert len(result) == 1  # M003 flagged
            assert "221" in result["flagid"].iloc[0]

    def test_no_flags_when_all_present(self, tmp_path: Path) -> None:
        mil_path = tmp_path / "mil.parquet"
        enr_path = tmp_path / "enr.parquet"
        write_parquet(
            mil_path,
            {
                "MPatID": ["M001", "M002"],
                "CPatID": ["C001", "C002"],
                "ADate": ["2020-01-15", "2020-02-20"],
                "EncounterID": ["E1", "E2"],
                "Birth_Type": [1, 2],
            },
        )
        write_parquet(
            enr_path,
            {
                "MPatID": ["M001", "M002"],
                "EnrStart": ["2020-01-01", "2020-01-01"],
                "EnrEnd": ["2020-12-31", "2020-12-31"],
            },
        )
        with _make_session({"mil": mil_path, "enr": enr_path}) as session:
            check = CrossTableConsistencyCheck(
                check_id="221",
                reference_table="enr",
                join_column="MPatID",
                flag_def=get_check_flag("221"),
            )
            ctx = CheckContext(session=session, metadata=check.metadata)
            result = session.execute(check.build(ctx))
            assert len(result) == 0


# ---------------------------------------------------------------------------
# NUM-43: Enrollment/eligibility family
# ---------------------------------------------------------------------------


class TestEnrollmentCoverage:
    def test_flags_date_outside_enrollment(self, tmp_path: Path) -> None:
        mil_path = tmp_path / "mil.parquet"
        enr_path = tmp_path / "enr.parquet"
        write_parquet(
            mil_path,
            {
                "MPatID": ["M001", "M002"],
                "CPatID": ["C001", "C002"],
                "ADate": ["2020-06-15", "2021-06-15"],  # M002 outside enrollment
                "EncounterID": ["E1", "E2"],
                "Birth_Type": [1, 2],
            },
        )
        write_parquet(
            enr_path,
            {
                "MPatID": ["M001", "M002"],
                "EnrStart": ["2020-01-01", "2020-01-01"],
                "EnrEnd": ["2020-12-31", "2020-12-31"],  # M002 date 2021-06-15 is outside
            },
        )
        with _make_session({"mil": mil_path, "enr": enr_path}) as session:
            check = EnrollmentCoverageCheck(
                check_id="200", date_column="ADate", flag_def=get_check_flag("200")
            )
            ctx = CheckContext(session=session, metadata=check.metadata)
            result = session.execute(check.build(ctx))
            assert len(result) >= 1  # M002 flagged
            assert "200" in result["flagid"].iloc[0]

    def test_no_flags_when_date_within_enrollment(self, tmp_path: Path) -> None:
        mil_path = tmp_path / "mil.parquet"
        enr_path = tmp_path / "enr.parquet"
        write_parquet(
            mil_path,
            {
                "MPatID": ["M001"],
                "CPatID": ["C001"],
                "ADate": ["2020-06-15"],
                "EncounterID": ["E1"],
                "Birth_Type": [1],
            },
        )
        write_parquet(
            enr_path,
            {
                "MPatID": ["M001"],
                "EnrStart": ["2020-01-01"],
                "EnrEnd": ["2020-12-31"],
            },
        )
        with _make_session({"mil": mil_path, "enr": enr_path}) as session:
            check = EnrollmentCoverageCheck(
                check_id="200", date_column="ADate", flag_def=get_check_flag("200")
            )
            ctx = CheckContext(session=session, metadata=check.metadata)
            result = session.execute(check.build(ctx))
            assert len(result) == 0


# ---------------------------------------------------------------------------
# Lookup-driven metadata validation
# ---------------------------------------------------------------------------


class TestLookupDrivenMetadata:
    """Verify that L2 check metadata is driven by checks.json, not hard-coded."""

    def test_registered_l2_metadata_matches_lookup(self) -> None:
        checks = list_checks()
        for check in checks:
            if check.metadata.level != 2:
                continue
            flag_def = getattr(check, "flag_def", None)
            assert flag_def is not None
            assert check.metadata.description == flag_def.flag_descr
            assert check.metadata.severity == flag_type_to_severity(flag_def.flag_type)
