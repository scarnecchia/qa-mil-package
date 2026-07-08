"""Tests for Level 3 checks 394, 396, 397 (NUM-45)."""

from __future__ import annotations

from pathlib import Path

from qa_mil.checks.base import CheckContext
from qa_mil.checks.level3.linkage_checks import (
    BirthTypeNoLinkageCheck,
    InfantNotLinkedCheck,
    MotherNotLinkedCheck,
)
from qa_mil.checks.registry import list_checks
from tests.conftest import write_parquet


def _make_session(mil_path: Path):
    from qa_mil.engine.duckdb import DuckDbSession

    return DuckDbSession({"mil": mil_path})


class TestLevel3Registry:
    def test_checks_394_396_397_registered(self) -> None:
        checks = list_checks()
        ids = {c.metadata.check_id for c in checks}
        assert "394" in ids
        assert "396" in ids
        assert "397" in ids

    def test_all_level3_checks_present(self) -> None:
        checks = list_checks()
        level3 = [c for c in checks if c.metadata.level == 3]
        ids = {c.metadata.check_id for c in level3}
        assert {"371", "372", "373", "374", "375", "394", "396", "397"}.issubset(ids)

    def test_no_nonexistent_checks(self) -> None:
        checks = list_checks()
        ids = {c.metadata.check_id for c in checks}
        assert "370" not in ids
        assert "395" not in ids


class TestCheck394:
    def test_flags_birth_type_2_8_without_cpatid(self, tmp_path: Path) -> None:
        mil_path = tmp_path / "mil.parquet"
        write_parquet(
            mil_path,
            {
                "MPatID": ["M001", "M002", "M003"],
                "CPatID": [None, "C002", None],  # M001 and M003 missing CPatID
                "ADate": ["2020-01-15", "2020-02-20", "2020-03-10"],
                "EncounterID": ["E1", "E2", "E3"],
                "Birth_Type": [2, 1, 5],  # 2 and 5 are in range 2-8
            },
        )
        with _make_session(mil_path) as session:
            check = BirthTypeNoLinkageCheck()
            ctx = CheckContext(session=session, metadata=check.metadata)
            result = session.execute(check.build(ctx))
            assert len(result) == 2  # M001 (BT=2) and M003 (BT=5)
            assert "394" in result["flagid"].iloc[0]

    def test_no_flags_when_cpatid_present(self, tmp_path: Path) -> None:
        mil_path = tmp_path / "mil.parquet"
        write_parquet(
            mil_path,
            {
                "MPatID": ["M001"],
                "CPatID": ["C001"],
                "ADate": ["2020-01-15"],
                "EncounterID": ["E1"],
                "Birth_Type": [3],
            },
        )
        with _make_session(mil_path) as session:
            check = BirthTypeNoLinkageCheck()
            ctx = CheckContext(session=session, metadata=check.metadata)
            result = session.execute(check.build(ctx))
            assert len(result) == 0

    def test_no_flags_for_birth_type_1(self, tmp_path: Path) -> None:
        mil_path = tmp_path / "mil.parquet"
        write_parquet(
            mil_path,
            {
                "MPatID": ["M001"],
                "CPatID": [None],
                "ADate": ["2020-01-15"],
                "EncounterID": ["E1"],
                "Birth_Type": [1],  # BT=1 is not in 2-8 range
            },
        )
        with _make_session(mil_path) as session:
            check = BirthTypeNoLinkageCheck()
            ctx = CheckContext(session=session, metadata=check.metadata)
            result = session.execute(check.build(ctx))
            assert len(result) == 0


class TestCheck396:
    def test_flags_mother_without_infant(self, tmp_path: Path) -> None:
        mil_path = tmp_path / "mil.parquet"
        write_parquet(
            mil_path,
            {
                "MPatID": ["M001", "M002", None],
                "CPatID": [None, "C002", "C003"],  # M001 has no infant
                "ADate": ["2020-01-15", "2020-02-20", "2020-03-10"],
                "EncounterID": ["E1", "E2", "E3"],
                "Birth_Type": [1, 2, 1],
            },
        )
        with _make_session(mil_path) as session:
            check = MotherNotLinkedCheck()
            ctx = CheckContext(session=session, metadata=check.metadata)
            result = session.execute(check.build(ctx))
            assert len(result) == 1  # M001 flagged
            assert "396" in result["flagid"].iloc[0]

    def test_no_flags_when_linked(self, tmp_path: Path) -> None:
        mil_path = tmp_path / "mil.parquet"
        write_parquet(
            mil_path,
            {
                "MPatID": ["M001"],
                "CPatID": ["C001"],
                "ADate": ["2020-01-15"],
                "EncounterID": ["E1"],
                "Birth_Type": [1],
            },
        )
        with _make_session(mil_path) as session:
            check = MotherNotLinkedCheck()
            ctx = CheckContext(session=session, metadata=check.metadata)
            result = session.execute(check.build(ctx))
            assert len(result) == 0


class TestCheck397:
    def test_flags_infant_without_mother(self, tmp_path: Path) -> None:
        mil_path = tmp_path / "mil.parquet"
        write_parquet(
            mil_path,
            {
                "MPatID": ["M001", None],  # Row 2 has no mother
                "CPatID": ["C001", "C002"],
                "ADate": ["2020-01-15", "2020-02-20"],
                "EncounterID": ["E1", "E2"],
                "Birth_Type": [1, 1],
            },
        )
        with _make_session(mil_path) as session:
            check = InfantNotLinkedCheck()
            ctx = CheckContext(session=session, metadata=check.metadata)
            result = session.execute(check.build(ctx))
            assert len(result) == 1  # C002 flagged
            assert "397" in result["flagid"].iloc[0]

    def test_no_flags_when_linked(self, tmp_path: Path) -> None:
        mil_path = tmp_path / "mil.parquet"
        write_parquet(
            mil_path,
            {
                "MPatID": ["M001"],
                "CPatID": ["C001"],
                "ADate": ["2020-01-15"],
                "EncounterID": ["E1"],
                "Birth_Type": [1],
            },
        )
        with _make_session(mil_path) as session:
            check = InfantNotLinkedCheck()
            ctx = CheckContext(session=session, metadata=check.metadata)
            result = session.execute(check.build(ctx))
            assert len(result) == 0


class TestLevel3FlagIDs:
    def test_flagid_format(self) -> None:
        from qa_mil.checks.base import make_flagid

        assert make_flagid("MIL", 3, "00", 394) == "MIL_3_00_00-0_394"
        assert make_flagid("MIL", 3, "00", 396) == "MIL_3_00_00-0_396"
        assert make_flagid("MIL", 3, "00", 397) == "MIL_3_00_00-0_397"
