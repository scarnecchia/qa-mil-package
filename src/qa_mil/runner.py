"""QA MIL runner — orchestrates check execution end-to-end."""

from __future__ import annotations

from pathlib import Path
from typing import Any

import pyarrow as pa
import yaml

from qa_mil import __version__
from qa_mil.checks.base import CheckContext, OutputScope, Severity
from qa_mil.checks.registry import disabled_checks, level_ordered_groups, required_tables
from qa_mil.config import Config
from qa_mil.engine.base import create_session
from qa_mil.manifest import (
    load_input_manifest,
    validate_etl_consistency,
    validate_required_tables,
    validate_table_paths,
)
from qa_mil.observability import record_counter, span
from qa_mil.outputs.dplocal import write_dplocal_flags
from qa_mil.outputs.msoc import write_msoc_flags


def run(cfg: Config) -> dict[str, Any]:
    """Execute the QA MIL pipeline.

    Args:
        cfg: Validated Config instance.

    Returns a summary dict with outcomes and flag counts.
    """
    with span("qa_mil.run", request_id=cfg.request_id, etl_number=cfg.etl_number):
        # 1. Load and validate manifest
        with span("qa_mil.load_manifest"):
            manifest, manifest_parent = load_input_manifest(cfg.input_manifest)
            validate_etl_consistency(cfg.etl_number, manifest.etl_number)

        # 2. Validate required tables from enabled checks
        with span("qa_mil.validate_required_tables"):
            req_tables = required_tables(
                disabled_ids=cfg.checks.disabled,
                enabled_ids=cfg.checks.enabled,
            )
            validate_required_tables(manifest, req_tables)

        # 3. Resolve table paths
        with span("qa_mil.resolve_paths"):
            resolved_paths = validate_table_paths(manifest, manifest_parent, check_exists=True)

        # 4. Create engine session
        with span("qa_mil.create_engine", backend_name=cfg.backend.name):
            session = create_session(
                resolved_paths,
                backend=cfg.backend.name,
                options=cfg.backend.options,
            )

        # 5. Execute checks
        with span("qa_mil.execute_checks"):
            outcomes = _execute_checks(cfg, session)

        # 6. Write outputs
        with span("qa_mil.write_outputs"):
            output_summary = _write_outputs(cfg, outcomes)

        # 7. Write run manifest
        with span("qa_mil.write_run_manifest"):
            run_manifest_data = _build_run_manifest(cfg, manifest, outcomes, output_summary)
            _write_run_manifest(cfg, run_manifest_data)

        # Close session
        session.close()

        return {
            "request_id": cfg.request_id,
            "outcomes": outcomes,
            "output_summary": output_summary,
            "run_manifest": run_manifest_data,
        }


def _execute_checks(cfg: Config, session: Any) -> list[dict[str, Any]]:
    """Execute enabled checks by level, tracking outcomes.

    Stops on Abort checks with failing rows; continues on Warn.
    """
    outcomes: list[dict[str, Any]] = []

    # Record disabled checks
    for check in disabled_checks(cfg.checks.disabled):
        outcomes.append(
            {
                "check_id": check.metadata.check_id,
                "level": check.metadata.level,
                "severity": check.metadata.severity.value,
                "status": "disabled",
                "flag_count": 0,
            }
        )
        record_counter("qa_mil.checks.disabled", check_id=check.metadata.check_id)

    # Get level-ordered groups
    groups = level_ordered_groups(
        disabled_ids=cfg.checks.disabled,
        enabled_ids=cfg.checks.enabled,
    )

    aborted = False
    for group in groups:
        if aborted:
            # Record remaining checks as skipped
            for check in group:
                outcomes.append(
                    {
                        "check_id": check.metadata.check_id,
                        "level": check.metadata.level,
                        "severity": check.metadata.severity.value,
                        "status": "skipped",
                        "flag_count": 0,
                    }
                )
                record_counter("qa_mil.checks.skipped", check_id=check.metadata.check_id)
            continue

        for check in group:
            if aborted:
                outcomes.append(
                    {
                        "check_id": check.metadata.check_id,
                        "level": check.metadata.level,
                        "severity": check.metadata.severity.value,
                        "status": "skipped",
                        "flag_count": 0,
                    }
                )
                record_counter("qa_mil.checks.skipped", check_id=check.metadata.check_id)
                continue
            with span(
                "qa_mil.check",
                check_id=check.metadata.check_id,
                check_level=check.metadata.level,
                check_severity=check.metadata.severity.value,
                check_output_scope=check.metadata.output_scope.value,
            ):
                ctx = CheckContext(session=session, metadata=check.metadata)
                try:
                    result_expr = check.build(ctx)
                    result_df = session.execute(result_expr)
                    flag_count = len(result_df) if result_df is not None else 0
                    result_arrow = pa.Table.from_pandas(result_df) if flag_count > 0 else None

                    outcomes.append(
                        {
                            "check_id": check.metadata.check_id,
                            "level": check.metadata.level,
                            "severity": check.metadata.severity.value,
                            "status": "completed",
                            "flag_count": flag_count,
                            "result": result_arrow,
                            "output_scope": check.metadata.output_scope.value,
                        }
                    )
                    record_counter("qa_mil.checks.completed", check_id=check.metadata.check_id)
                    record_counter(
                        "qa_mil.flags", value=flag_count, check_id=check.metadata.check_id
                    )

                    if flag_count > 0 and check.metadata.severity == Severity.ABORT:
                        aborted = True

                except Exception as e:
                    outcomes.append(
                        {
                            "check_id": check.metadata.check_id,
                            "level": check.metadata.level,
                            "severity": check.metadata.severity.value,
                            "status": "failed",
                            "flag_count": 0,
                            "error": str(e),
                        }
                    )
                    record_counter("qa_mil.checks.failed", check_id=check.metadata.check_id)

    return outcomes


_FLAG_COLUMNS = {"flagid", "flag_descr", "message", "flag_type", "abort_yn"}


def _project_to_flag_schema(table: pa.Table) -> pa.Table:
    """Project any result table to the standard flag column schema."""
    available = [c for c in _FLAG_COLUMNS if c in table.column_names]
    return table.select(available)


def _write_outputs(cfg: Config, outcomes: list[dict[str, Any]]) -> dict[str, Any]:
    """Write check results to dplocal/msoc outputs.

    Returns summary with paths and flag counts.
    """
    dplocal_tables: list[pa.Table] = []
    msoc_tables: list[pa.Table] = []
    dplocal_count = 0
    msoc_count = 0

    for outcome in outcomes:
        if outcome["status"] != "completed":
            continue
        result: pa.Table | None = outcome.get("result")
        if result is None or len(result) == 0:
            continue

        # Project to standard flag schema for consistent concatenation
        projected = _project_to_flag_schema(result)
        scope = outcome.get("output_scope", "dplocal")
        if scope == OutputScope.DPLOCAL.value:
            dplocal_tables.append(projected)
            dplocal_count += projected.num_rows
        elif scope == OutputScope.MSOC.value:
            msoc_tables.append(projected)
            msoc_count += projected.num_rows

    dplocal_path = write_dplocal_flags(dplocal_tables, cfg.output_dir)
    msoc_path = write_msoc_flags(msoc_tables, cfg.output_dir)

    return {
        "dplocal_flags": str(dplocal_path),
        "msoc_flags": str(msoc_path),
        "dplocal_flag_count": dplocal_count,
        "msoc_flag_count": msoc_count,
    }


def _build_run_manifest(
    cfg: Config,
    manifest: Any,
    outcomes: list[dict[str, Any]],
    output_summary: dict[str, Any],
) -> dict[str, Any]:
    """Build the run manifest data structure."""
    return {
        "package_version": __version__,
        "request": {
            "project_id": cfg.request.project_id,
            "workplan_type": cfg.request.workplan_type,
            "workplan_id": cfg.request.workplan_id,
            "dpid": cfg.request.dpid,
            "version_id": cfg.request.version_id,
        },
        "request_id": cfg.request_id,
        "config": cfg.model_dump(mode="json"),
        "input_manifest": str(cfg.input_manifest),
        "manifest_version": manifest.manifest_version,
        "etl_number": manifest.etl_number,
        "scdm_version": manifest.scdm_version,
        "semantic_profile": manifest.semantic_profile.model_dump(),
        "conversion": manifest.conversion.model_dump() if manifest.conversion else None,
        "check_selection": {
            "disabled": cfg.checks.disabled,
            "enabled": cfg.checks.enabled,
        },
        "check_outcomes": [
            {
                "check_id": o["check_id"],
                "level": o["level"],
                "severity": o["severity"],
                "status": o["status"],
                "flag_count": o["flag_count"],
            }
            for o in outcomes
        ],
        "flag_counts": {
            "dplocal": output_summary["dplocal_flag_count"],
            "msoc": output_summary["msoc_flag_count"],
        },
        "outputs": output_summary,
    }


def _write_run_manifest(cfg: Config, data: dict[str, Any]) -> Path:
    """Write the run manifest YAML."""
    cfg.output_dir.mkdir(parents=True, exist_ok=True)
    path = cfg.output_dir / "run_manifest.yaml"
    with path.open("w") as f:
        yaml.dump(data, f, default_flow_style=False, sort_keys=True)
    return path
