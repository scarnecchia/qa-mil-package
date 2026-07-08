"""Tests proving L2/L3 check metadata is driven by checks.json (NUM-54).

Covers three layers:
1. Checks.json completeness — all implemented check IDs are present.
2. Registry ↔ lookup cross-validation — every registered check has a lookup row
   and vice versa; metadata agrees.
3. Behavior tests — flag output values originate from the lookup, not hard-coded
   literals (including a mutation test that proves the connection).
"""

from __future__ import annotations

import json
from pathlib import Path

import pytest

from qa_mil.checks.base import CheckContext, flag_type_to_severity
from qa_mil.checks.level2.checks import DuplicateKeyCheck
from qa_mil.checks.level3.linkage_checks import MotherNotLinkedCheck
from qa_mil.checks.registry import list_checks
from qa_mil.lookups.loader import get_check_flag, load_check_flags
from tests.conftest import write_parquet


def _make_session(table_paths: dict[str, Path]):
    """Create a DuckDB session."""
    from qa_mil.engine.duckdb import DuckDbSession

    return DuckDbSession(table_paths)


# ---------------------------------------------------------------------------
# Checks.json completeness
# ---------------------------------------------------------------------------


class TestChecksJsonCompleteness:
    """Verify all implemented L2/L3 check IDs have active rows in checks.json."""

    EXPECTED_L2_IDS = {"200", "201", "204", "211", "217", "218", "219", "221", "223"}
    EXPECTED_L3_IDS = {"371", "372", "373", "374", "375", "394", "396", "397"}

    def test_level2_ids_present(self) -> None:
        flags = load_check_flags()
        l2_active = {f.check_id for f in flags if f.level == 2 and f.flagyn == "Y"}
        assert self.EXPECTED_L2_IDS.issubset(l2_active)

    def test_level3_ids_present(self) -> None:
        flags = load_check_flags()
        l3_active = {f.check_id for f in flags if f.level == 3 and f.flagyn == "Y"}
        assert self.EXPECTED_L3_IDS.issubset(l3_active)

    def test_no_duplicate_keys(self) -> None:
        flags = load_check_flags()
        seen: set[str] = set()
        for f in flags:
            key = f"{f.tabid}_{f.varid}_{f.check_id}"
            assert key not in seen, f"Duplicate check definition: {key}"
            seen.add(key)

    def test_severity_abort_consistency(self) -> None:
        """Active rows with flag_type='Abort' have abort_yn='Y'; 'Warn' → 'N'."""
        flags = load_check_flags()
        for f in flags:
            if f.flagyn != "Y":
                continue
            if f.flag_type == "Abort":
                assert f.abort_yn == "Y", (
                    f"check_id={f.check_id} has flag_type=Abort but abort_yn={f.abort_yn}"
                )
            elif f.flag_type == "Warn":
                assert f.abort_yn == "N", (
                    f"check_id={f.check_id} has flag_type=Warn but abort_yn={f.abort_yn}"
                )


# ---------------------------------------------------------------------------
# Registry ↔ lookup cross-validation
# ---------------------------------------------------------------------------


class TestRegistryLookupCrossValidation:
    """Every registered L2/L3 check has a lookup row, and vice versa."""

    def test_every_registered_l2l3_check_has_lookup_row(self) -> None:
        checks = list_checks()
        for check in checks:
            if check.metadata.level not in (2, 3):
                continue
            # Should not raise
            flag_def = get_check_flag(check.metadata.check_id, check.metadata.tabid, "00")
            assert flag_def is not None

    def test_every_active_l2l3_lookup_has_factory(self) -> None:
        """Every active L2/L3 lookup row (except check 102) must have a registered check."""
        flags = load_check_flags()
        registered_ids = {c.metadata.check_id for c in list_checks()}
        for f in flags:
            if f.level not in (2, 3):
                continue
            if f.flagyn != "Y":
                continue
            if f.check_id == "102":
                continue
            assert f.check_id in registered_ids, (
                f"Active L{f.level} lookup row check_id={f.check_id} "
                f"has no registered check factory"
            )

    def test_metadata_matches_lookup(self) -> None:
        checks = list_checks()
        for check in checks:
            if check.metadata.level not in (2, 3):
                continue
            flag_def = get_check_flag(check.metadata.check_id, check.metadata.tabid, "00")
            assert check.metadata.description == flag_def.flag_descr
            assert check.metadata.severity == flag_type_to_severity(flag_def.flag_type)
            assert check.metadata.level == flag_def.level
            assert check.metadata.tabid == flag_def.tabid


# ---------------------------------------------------------------------------
# Behavior tests — flag output values originate from the lookup
# ---------------------------------------------------------------------------


class TestLookupDrivenFlagOutput:
    """Prove that emitted flag_descr/flag_type come from checks.json, not literals."""

    def test_level2_check_emits_lookup_flag_descr(self, tmp_path: Path) -> None:
        mil_path = tmp_path / "mil.parquet"
        write_parquet(
            mil_path,
            {
                "MPatID": ["M001", "M001"],
                "CPatID": ["C001", "C001"],
                "ADate": ["2020-01-15", "2020-01-15"],
                "EncounterID": ["E1", "E1"],
                "Birth_Type": [1, 1],
            },
        )
        flag_def = get_check_flag("211")
        check = DuplicateKeyCheck(
            check_id="211", key_columns=("MPatID", "CPatID", "ADate"), flag_def=flag_def
        )
        with _make_session({"mil": mil_path}) as session:
            ctx = CheckContext(session=session, metadata=check.metadata)
            result = session.execute(check.build(ctx))
            assert len(result) >= 1
            assert result["flag_descr"].iloc[0] == flag_def.flag_descr
            assert result["flag_type"].iloc[0] == flag_def.flag_type

    def test_level3_check_emits_lookup_flag_descr(self, tmp_path: Path) -> None:
        mil_path = tmp_path / "mil.parquet"
        write_parquet(
            mil_path,
            {
                "MPatID": ["M001", "M002"],
                "CPatID": [None, "C002"],
                "ADate": ["2020-01-15", "2020-02-20"],
                "EncounterID": ["E1", "E2"],
                "Birth_Type": [1, 1],
            },
        )
        flag_def = get_check_flag("396")
        check = MotherNotLinkedCheck(flag_def=flag_def)
        with _make_session({"mil": mil_path}) as session:
            ctx = CheckContext(session=session, metadata=check.metadata)
            result = session.execute(check.build(ctx))
            assert len(result) >= 1
            assert result["flag_descr"].iloc[0] == flag_def.flag_descr
            assert result["flag_type"].iloc[0] == flag_def.flag_type

    def test_mutated_checks_json_changes_flag_output(
        self, tmp_path: Path, monkeypatch: pytest.MonkeyPatch
    ) -> None:
        """Mutate flag_descr in checks.json via the loader and prove the check emits the new value.

        This exercises the full loader path: monkeypatch the lookup directory, clear the
        lru_cache, call get_check_flag(), instantiate the check, and execute it.
        """
        from qa_mil.lookups import loader as loader_mod

        # Load the real checks.json, mutate one entry, write to temp dir
        real_json = Path(loader_mod.__file__).parent / "checks.json"
        raw = json.loads(real_json.read_text())
        mutated_descr = "MUTATED: duplicate records test description"
        for entry in raw:
            if entry["check_id"] == "211":
                entry["flag_descr"] = mutated_descr
                break

        # Write mutated checks.json to a temp directory
        tmp_lookup = tmp_path / "lookups"
        tmp_lookup.mkdir()
        (tmp_lookup / "checks.json").write_text(json.dumps(raw, indent=2))

        # Point the loader at the temp directory and clear the cache
        monkeypatch.setattr(loader_mod, "_LOOKUP_DIR", tmp_lookup)
        loader_mod._load_check_flags_cached.cache_clear()

        try:
            # Retrieve via get_check_flag — exercises the loader path
            mutated_def = loader_mod.get_check_flag("211")
            assert mutated_def.flag_descr == mutated_descr

            mil_path = tmp_path / "mil.parquet"
            write_parquet(
                mil_path,
                {
                    "MPatID": ["M001", "M001"],
                    "CPatID": ["C001", "C001"],
                    "ADate": ["2020-01-15", "2020-01-15"],
                    "EncounterID": ["E1", "E1"],
                    "Birth_Type": [1, 1],
                },
            )
            check = DuplicateKeyCheck(
                check_id="211",
                key_columns=("MPatID", "CPatID", "ADate"),
                flag_def=mutated_def,
            )
            with _make_session({"mil": mil_path}) as session:
                ctx = CheckContext(session=session, metadata=check.metadata)
                result = session.execute(check.build(ctx))
                assert len(result) >= 1
                assert result["flag_descr"].iloc[0] == mutated_descr
        finally:
            # Restore cache so later tests see the real checks.json
            loader_mod._load_check_flags_cached.cache_clear()


# ---------------------------------------------------------------------------
# Validation tests
# ---------------------------------------------------------------------------


class TestFlagTypeToSeverity:
    """Verify flag_type_to_severity() handles valid and invalid inputs."""

    def test_warn(self) -> None:
        from qa_mil.checks.base import Severity

        assert flag_type_to_severity("Warn") == Severity.WARN

    def test_abort(self) -> None:
        from qa_mil.checks.base import Severity

        assert flag_type_to_severity("Abort") == Severity.ABORT

    def test_invalid_raises(self) -> None:
        with pytest.raises(ValueError, match="flag_type must be"):
            flag_type_to_severity("Error")


class TestCheckFlagDefImmutability:
    """Verify CheckFlagDef is frozen — prevents cache corruption via shared objects."""

    def test_cannot_mutate_flag_descr(self) -> None:
        from pydantic import ValidationError

        from qa_mil.lookups.models import CheckFlagDef

        fd = CheckFlagDef(
            check_id="999",
            level=2,
            tabid="MIL",
            varid="00",
            flag_descr="test",
            flag_type="Warn",
            abort_yn="N",
        )
        with pytest.raises(ValidationError):
            fd.flag_descr = "mutated"  # type: ignore[misc]

    def test_cached_objects_not_corrupted(self) -> None:
        """Mutating a returned CheckFlagDef must not affect later get_check_flag() results."""
        from pydantic import ValidationError

        flag = get_check_flag("211")
        original_descr = flag.flag_descr
        # Attempt mutation (should fail because CheckFlagDef is frozen)
        with pytest.raises(ValidationError):
            flag.flag_descr = "POISONED"  # type: ignore[misc]
        # Verify cache is not corrupted
        flag_again = get_check_flag("211")
        assert flag_again.flag_descr == original_descr


class TestFlagDefValidation:
    """Verify __post_init__ catches mismatched flag_def.check_id."""

    def test_l2_check_rejects_mismatched_flag_def(self) -> None:
        """DuplicateKeyCheck raises when flag_def.check_id != check_id."""
        flag_def_211 = get_check_flag("211")
        with pytest.raises(ValueError, match="flag_def mismatch"):
            DuplicateKeyCheck(
                check_id="217",  # wrong check_id
                key_columns=("MPatID",),
                flag_def=flag_def_211,  # flag_def for 211
            )

    def test_l3_linkage_check_rejects_mismatched_flag_def(self) -> None:
        """MotherNotLinkedCheck raises when flag_def.check_id != '396'."""
        flag_def_394 = get_check_flag("394")
        with pytest.raises(ValueError, match="flag_def mismatch"):
            MotherNotLinkedCheck(flag_def=flag_def_394)  # flag_def for 394

    def test_l3_birth_type_check_rejects_mismatched_flag_def(self) -> None:
        """BirthTypeLinkageCheck raises when flag_def.check_id != str(370+birth_type)."""
        from qa_mil.checks.level3.birth_type import BirthTypeLinkageCheck

        flag_def_372 = get_check_flag("372")
        with pytest.raises(ValueError, match="flag_def mismatch"):
            BirthTypeLinkageCheck(birth_type=1, flag_def=flag_def_372)  # expects 371
