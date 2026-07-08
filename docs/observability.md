# Observability (NUM-49)

**Status:** Implemented
**Last updated:** 2026-07-07

## Overview

The qa-mil Python package includes first-class OpenTelemetry observability.
Telemetry is built in from the walking skeleton onward, not bolted on later.

## Configuration

Telemetry is environment-driven with safe local defaults.

### Environment variables

| Variable | Values | Default | Description |
|----------|--------|---------|-------------|
| `OTEL_EXPORTER_TYPE` | `none`, `console`, `otlp` | `none` | Exporter type |
| `OTEL_EXPORTER_OTLP_ENDPOINT` | URL | `http://localhost:4318` | OTLP collector endpoint |

- **`none`** (default): No-op exporter. No telemetry is sent anywhere.
  Safe for local development and CI.
- **`console`**: Prints spans and metrics to console. Useful for debugging.
- **`otlp`**: Sends telemetry to an OTLP collector. For deployed use.

### Initialization

Observability is initialized early in CLI/runtime entrypoints via
`init_observability()` in `src/qa_mil/observability.py`.

## Spans

Spans are emitted for major pipeline phases:

- `qa_mil.run` — Full pipeline execution
- `qa_mil.load_manifest` — Config/manifest loading
- `qa_mil.validate_required_tables` — Required table validation
- `qa_mil.resolve_paths` — Path resolution
- `qa_mil.create_engine` — Engine session creation
- `qa_mil.execute_checks` — Check execution
- `qa_mil.check` — Per-check execution
- `qa_mil.write_outputs` — Output writing
- `qa_mil.write_run_manifest` — Run manifest emission

## Metrics

Counters are recorded for:

- `qa_mil.checks.completed` — Check completed
- `qa_mil.checks.disabled` — Check disabled
- `qa_mil.checks.skipped` — Check skipped
- `qa_mil.checks.failed` — Check failed
- `qa_mil.flags` — Flag count per check

## Safe attributes

The following attributes are safe to emit as span attributes and metric labels:

- `qa_mil.request_id` — Derived request ID
- `qa_mil.project_id`, `qa_mil.workplan_id`, `qa_mil.dpid`, `qa_mil.version_id`
- `qa_mil.backend_name` — Backend (duckdb/spark)
- `qa_mil.manifest_version`, `qa_mil.scdm_version`
- `qa_mil.check_id`, `qa_mil.check_level`, `qa_mil.check_severity`
- `qa_mil.check_output_scope`, `qa_mil.check_tables`
- `qa_mil.check_status`, `qa_mil.flag_count`, `qa_mil.outcome`
- `qa_mil.etl_number`

## Privacy constraints

**Never** emit the following as span attributes, metric labels, or log records:

- Patient identifiers (MPatID, CPatID, PatID)
- Encounter IDs
- Source cell values
- Row-level messages
- Any PHI/PII

The `SAFE_ATTRIBUTE_KEYS` set in `observability.py` enforces this by only
allowing known-safe attribute keys. The `assert_no_sensitive_data()` test
helper verifies that known sensitive values do not appear in telemetry.

## Testing

Observability tests use in-memory/no-op exporters and require no live collector:

- `tests/test_observability.py` — Tests span emission, metric recording,
  safe attribute filtering, and no-PHI verification.

## Captured-SAS parity deferral

Full captured-SAS parity testing (NUM-49) requires SAS expected outputs or a
SAS environment, which are not currently available. The parity harness
(NUM-33) supports synthetic/golden comparison now and is ready for captured
SAS outputs when they become available.

When SAS outputs become available:
1. Add captured outputs to `tests/fixtures/parity/`
2. Run full Python check suite against corresponding parquet inputs
3. Compare dplocal/msoc outputs against captured SAS through the harness
4. Resolve parity gaps or document stakeholder acceptance
