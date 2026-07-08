"""Tests for the runner — Warn/Abort behavior, disabled checks, run manifest (NUM-32)."""

from __future__ import annotations

from pathlib import Path
from typing import Any

import yaml
from typer.testing import CliRunner

from qa_mil.checks.base import (
    CheckContext,
    CheckMetadata,
    OutputScope,
    Severity,
    make_flagid,
)
from qa_mil.checks.registry import _register
from qa_mil.config import load_config
from qa_mil.runner import run as run_pipeline
from tests.conftest import (
    make_config_yaml,
    make_full_fixture,
    make_manifest_yaml,
    make_mil_data,
    write_parquet,
)

runner = CliRunner()


# ---------------------------------------------------------------------------
# Fake checks for Warn/Abort testing
# ---------------------------------------------------------------------------


class FakeWarnCheck:
    """Fake check that always emits 2 flag rows."""

    def __init__(self, check_id: str = "999") -> None:
        self._check_id = check_id

    @property
    def metadata(self) -> CheckMetadata:
        return CheckMetadata(
            check_id=self._check_id,
            level=9,
            severity=Severity.WARN,
            tables=frozenset({"mil"}),
            output_scope=OutputScope.DPLOCAL,
            description="Fake warn check",
            tabid="MIL",
        )

    def build(self, ctx: CheckContext) -> Any:
        return (
            ctx.session.table("mil")
            .limit(2)
            .mutate(
                flagid=ibis_literal(make_flagid("MIL", 9, "00", self._check_id)),
                flag_descr=ibis_literal("fake warn"),
                message=ibis_literal(""),
                flag_type=ibis_literal("Warn"),
                abort_yn=ibis_literal("N"),
            )
        )


class FakeAbortCheck:
    """Fake check that always emits 1 flag row with Abort severity."""

    def __init__(self, check_id: str = "998") -> None:
        self._check_id = check_id

    @property
    def metadata(self) -> CheckMetadata:
        return CheckMetadata(
            check_id=self._check_id,
            level=9,
            severity=Severity.ABORT,
            tables=frozenset({"mil"}),
            output_scope=OutputScope.DPLOCAL,
            description="Fake abort check",
            tabid="MIL",
        )

    def build(self, ctx: CheckContext) -> Any:
        return (
            ctx.session.table("mil")
            .limit(1)
            .mutate(
                flagid=ibis_literal(make_flagid("MIL", 9, "00", self._check_id)),
                flag_descr=ibis_literal("fake abort"),
                message=ibis_literal(""),
                flag_type=ibis_literal("Abort"),
                abort_yn=ibis_literal("Y"),
            )
        )


def ibis_literal(val: str) -> Any:
    """Create an ibis literal — avoids importing ibis at test module level."""
    import ibis

    return ibis.literal(val)


# ---------------------------------------------------------------------------
# Runner integration tests
# ---------------------------------------------------------------------------


class TestRunnerWalkingSkeleton:
    def test_run_produces_outputs(self, tmp_path: Path) -> None:
        """Full run with 371-375 produces dplocal flags and run manifest."""
        setup = make_full_fixture(tmp_path)
        config_path = setup["config"]
        cfg = load_config(config_path)

        result = run_pipeline(cfg)

        # Output files exist
        assert (cfg.output_dir / "dplocal" / "flags.parquet").exists()
        assert (cfg.output_dir / "msoc" / "flags.parquet").exists()
        assert (cfg.output_dir / "run_manifest.yaml").exists()

        # Run manifest has outcomes
        rm = result["run_manifest"]
        assert rm["request_id"] == "soc_qmr_wp001_nsdp_v01"
        assert len(rm["check_outcomes"]) > 0  # Level 1 + Level 3 checks

        completed = [o for o in rm["check_outcomes"] if o["status"] == "completed"]
        assert len(completed) > 0  # At least some checks completed

    def test_run_manifest_has_flag_counts(self, tmp_path: Path) -> None:
        setup = make_full_fixture(tmp_path)
        config_path = setup["config"]
        cfg = load_config(config_path)

        result = run_pipeline(cfg)
        rm = result["run_manifest"]
        assert "dplocal" in rm["flag_counts"]
        assert "msoc" in rm["flag_counts"]

    def test_disabled_checks_recorded(self, tmp_path: Path) -> None:
        setup = make_full_fixture(tmp_path)
        config_path = make_config_yaml(tmp_path, setup["manifest"], disabled=["371"])
        cfg = load_config(config_path)

        result = run_pipeline(cfg)
        rm = result["run_manifest"]
        disabled_outcomes = [o for o in rm["check_outcomes"] if o["status"] == "disabled"]
        assert any(o["check_id"] == "371" for o in disabled_outcomes)
        completed = [o for o in rm["check_outcomes"] if o["status"] == "completed"]
        assert all(o["check_id"] != "371" for o in completed)

    def test_run_manifest_yaml_round_trip(self, tmp_path: Path) -> None:
        setup = make_full_fixture(tmp_path)
        config_path = setup["config"]
        cfg = load_config(config_path)

        run_pipeline(cfg)
        rm_path = cfg.output_dir / "run_manifest.yaml"
        with rm_path.open() as f:
            loaded = yaml.safe_load(f)
        assert loaded["request_id"] == "soc_qmr_wp001_nsdp_v01"
        assert len(loaded["check_outcomes"]) > 0  # Level 1 + Level 3 checks

    def test_dplocal_preserves_patient_columns(self, tmp_path: Path) -> None:
        """dplocal output must retain patient/detail columns, not just flag columns."""
        import pyarrow.parquet as pq

        setup = make_full_fixture(tmp_path)
        config_path = setup["config"]
        cfg = load_config(config_path)

        run_pipeline(cfg)
        dplocal_path = cfg.output_dir / "dplocal" / "flags.parquet"
        table = pq.read_table(dplocal_path)

        # Flag columns should always be present
        assert "flagid" in table.column_names

        # If any check produced rows with patient columns, they should be preserved.
        # The null-values check (120) on MPatID includes the MPatID column in its
        # result; check that it survives to dplocal output.
        # (At least one of the standard patient columns should appear.)
        patient_cols = {"MPatID", "CPatID", "EncounterID", "ADate", "Birth_Type", "Age"}
        present_patient_cols = patient_cols & set(table.column_names)
        assert len(present_patient_cols) > 0, (
            f"dplocal output has no patient columns. Available: {table.column_names}"
        )


# ---------------------------------------------------------------------------
# Warn/Abort behavior with fake checks
# ---------------------------------------------------------------------------


class TestWarnAbortBehavior:
    def test_failed_check_stops_subsequent(self, tmp_path: Path) -> None:
        """A check that raises must stop subsequent checks (fail closed)."""
        from qa_mil.checks.registry import _registry as reg_list

        original = list(reg_list)
        try:
            reg_list.clear()

            class FailingCheck:
                @property
                def metadata(self) -> CheckMetadata:
                    return CheckMetadata(
                        check_id="F001",
                        level=9,
                        severity=Severity.WARN,
                        tables=frozenset({"mil"}),
                        output_scope=OutputScope.DPLOCAL,
                        description="Always fails",
                        tabid="MIL",
                    )

                def build(self, ctx: CheckContext) -> Any:
                    raise RuntimeError("intentional failure")

            _register(FailingCheck())
            _register(FakeWarnCheck("W001"))

            mil_path = tmp_path / "mil.parquet"
            write_parquet(mil_path, make_mil_data())
            manifest_path = make_manifest_yaml(tmp_path, {"mil": mil_path})
            config_path = make_config_yaml(tmp_path, manifest_path)
            cfg = load_config(config_path)

            result = run_pipeline(cfg)
            rm = result["run_manifest"]
            outcomes = rm["check_outcomes"]

            # F001 should be failed
            f001 = next(o for o in outcomes if o["check_id"] == "F001")
            assert f001["status"] == "failed"

            # W001 should be skipped (not completed)
            w001 = next(o for o in outcomes if o["check_id"] == "W001")
            assert w001["status"] == "skipped"

            # Run status should be failed
            assert result["run_status"] == "failed"

            # Output files should NOT be written (no potentially-invalid artifacts)
            assert not (cfg.output_dir / "dplocal" / "flags.parquet").exists()

            # Run manifest should still be written (for diagnostics)
            assert (cfg.output_dir / "run_manifest.yaml").exists()
        finally:
            reg_list.clear()
            reg_list.extend(original)

    def test_warn_check_continues(self, tmp_path: Path) -> None:
        """Warn check with rows should allow subsequent checks to run."""
        from qa_mil.checks.registry import _registry as reg_list

        # Save and restore registry
        original = list(reg_list)
        try:
            reg_list.clear()
            _register(FakeWarnCheck("W001"))
            _register(FakeWarnCheck("W002"))

            mil_path = tmp_path / "mil.parquet"
            write_parquet(mil_path, make_mil_data())
            manifest_path = make_manifest_yaml(tmp_path, {"mil": mil_path})
            config_path = make_config_yaml(tmp_path, manifest_path)
            cfg = load_config(config_path)

            result = run_pipeline(cfg)
            rm = result["run_manifest"]
            completed = [o for o in rm["check_outcomes"] if o["status"] == "completed"]
            assert len(completed) == 2  # Both ran
        finally:
            reg_list.clear()
            reg_list.extend(original)

    def test_abort_check_stops_subsequent(self, tmp_path: Path) -> None:
        """Abort check with rows should skip subsequent checks."""
        from qa_mil.checks.registry import _registry as reg_list

        original = list(reg_list)
        try:
            reg_list.clear()
            _register(FakeAbortCheck("A001"))
            _register(FakeWarnCheck("W001"))

            mil_path = tmp_path / "mil.parquet"
            write_parquet(mil_path, make_mil_data())
            manifest_path = make_manifest_yaml(tmp_path, {"mil": mil_path})
            config_path = make_config_yaml(tmp_path, manifest_path)
            cfg = load_config(config_path)

            result = run_pipeline(cfg)
            rm = result["run_manifest"]
            outcomes = rm["check_outcomes"]

            # A001 should be completed with flags
            a001 = next(o for o in outcomes if o["check_id"] == "A001")
            assert a001["status"] == "completed"
            assert a001["flag_count"] > 0

            # W001 should be skipped
            w001 = next(o for o in outcomes if o["check_id"] == "W001")
            assert w001["status"] == "skipped"
        finally:
            reg_list.clear()
            reg_list.extend(original)


# ---------------------------------------------------------------------------
# CLI list-checks
# ---------------------------------------------------------------------------


class TestListChecksCLI:
    def test_list_checks_command(self) -> None:
        from qa_mil.cli import app

        result = runner.invoke(app, ["list-checks"])
        assert result.exit_code == 0
        assert "371" in result.stdout
        assert "372" in result.stdout
        assert "375" in result.stdout
        assert "Warn" in result.stdout
        assert "dplocal" in result.stdout
