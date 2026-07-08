# QA MIL Python Re-implementation Design

## Summary

This design ports the existing SAS-based QA MIL package to Python, keeping its check
logic, flag formats, and outputs identical while replacing the execution engine. Checks are
rewritten as declarative Ibis expressions rather than imperative SAS macros, which lets a
single check implementation run unmodified against either a local DuckDB backend (the
default, for single-node runs including datasets larger than memory) or a Spark backend (for
cluster execution) — backend choice is a config setting, not a code fork. Binary SAS lookup
tables become versioned YAML, and the row-by-row lookup pattern in the current SAS
implementation is replaced with joins.

The port proceeds in phases: scaffolding, configuration/manifest handling, the engine layer,
a walking-skeleton check to prove the full pipeline end-to-end, a SAS parity test harness,
and then the remaining Level 1, 2, and 3 checks ported in bulk against that harness, finishing
with the Spark backend. Every ported check must reproduce the SAS package's flag output
row-for-row on shared fixture data (modulo documented type mappings), which is why the parity
harness is built early and gates all subsequent porting work rather than being left to the
end.

## Definition of Done

- A Python package (`qa-mil`) reproduces the core QA MIL pipeline — Level 1, Level 2, and
  Level 3 checks — against SCDM data in parquet format.
- Flag output matches the existing SAS package on synthetic SCDM data, preserving the
  `flagid` scheme, the flag record schema, and the `dplocal` (patient-level) / `msoc`
  (aggregate) output split.
- A full run completes on a single node against data larger than available memory, and the
  same run executes on a Spark cluster by changing configuration only.
- Runs are configured entirely through a CLI and config file; no per-run code editing.
- Explicitly excluded: SCDM Snapshot, QA Common Components, and sas7bdat ingest (a separate
  upstream conversion program produces the parquet inputs).

## Acceptance Criteria

### qa-mil-python-port.AC1: Configuration and run setup

- **qa-mil-python-port.AC1.1 Success:** A valid config file plus a valid input manifest
  starts a run without prompting or code edits.
- **qa-mil-python-port.AC1.2 Failure:** An ETL number in the config that does not match the
  input manifest fails before any check executes, with an error naming both values.
- **qa-mil-python-port.AC1.3 Failure:** A parquet table required by the enabled checks but
  absent from the input directory fails fast with an error naming the missing table.
- **qa-mil-python-port.AC1.4 Success:** `qa-mil list-checks` lists every registered check
  with its id, level, severity, and applicable tables.
- **qa-mil-python-port.AC1.5 Edge:** A check disabled in config is excluded from the run and
  the exclusion is recorded in the run manifest.

### qa-mil-python-port.AC2: Check correctness and SAS parity

- **qa-mil-python-port.AC2.1 Success:** Each ported check's flag output matches the SAS
  package's output on the parity fixture data, row for row, modulo documented type mappings
  (SAS dates/lengths to Arrow types).
- **qa-mil-python-port.AC2.2 Success:** Generated flagids match the existing format
  `{TABID}_{level}_00_00-0_{checknum}` exactly.
- **qa-mil-python-port.AC2.3 Success:** A failing abort-type check halts the run and reports
  the abort; failing warn-type checks are recorded and the run continues.
- **qa-mil-python-port.AC2.4 Edge:** Null values in group-by keys and check predicates
  produce the same flag decisions as SAS missing-value semantics, verified by targeted
  fixtures for at least: null CPatID/MPatID in linkage counts, null dates in range checks,
  and null values in duplicate detection.

### qa-mil-python-port.AC3: Engine and scale

- **qa-mil-python-port.AC3.1 Success:** A full run completes on the DuckDB backend against a
  dataset larger than the machine's available RAM.
- **qa-mil-python-port.AC3.2 Success:** The same run on the Spark backend produces flag
  tables identical to the DuckDB run.
- **qa-mil-python-port.AC3.3 Success:** Backend selection is a config value; no check code
  differs between backends.

### qa-mil-python-port.AC4: Outputs and provenance

- **qa-mil-python-port.AC4.1 Success:** Patient-level flag detail is written only to the
  dplocal-equivalent output; aggregate results only to the msoc-equivalent output.
- **qa-mil-python-port.AC4.2 Failure:** The aggregate writer rejects any result table
  containing patient-level identifier columns (MPatID, CPatID, PatID, EncounterID) with an
  error, verified by test.
- **qa-mil-python-port.AC4.3 Success:** Every run emits a run manifest containing package
  version, resolved configuration, input-manifest reference, and per-check outcome summary.

## Glossary

- **SCDM (Sentinel Common Data Model)**: The standardized data model FDA Sentinel sites
  transform their claims/EHR data into; this package validates data conforming to it.
- **MIL (Mother-Infant Linkage)**: The SCDM data domain linking mother and infant records
  (e.g., via `MPatID`/`CPatID`), which this QA package checks for data quality issues.
- **QA MIL package**: The existing SAS program that runs data quality checks against MIL
  data; this design re-implements it in Python.
- **Level 1 / Level 2 / Level 3 checks**: The three tiers of QA checks in the SAS package,
  increasing in complexity — structural/existence checks (L1), value and cross-record checks
  (L2), and linkage-specific checks (L3, e.g., checks 371–397).
- **flagid**: The identifier format for a raised check (`{TABID}_{level}_00_00-0_{checknum}`),
  preserved exactly from the SAS package because downstream QA review depends on it.
- **dplocal**: The SAS package's patient-level output — per-record flag detail, as opposed to
  aggregate results.
- **msoc**: The SAS package's aggregate (summary) output, as opposed to per-patient detail.
- **Abort vs. Warn (severity)**: A check outcome classification; an Abort-type check failure
  halts the run, while a Warn-type failure is recorded and the run continues.
- **ETL number**: A run identifier tied to a specific data extraction cycle at a Sentinel
  site; used to cross-check that the config and input data manifest refer to the same run.
- **Parity fixture / parity harness**: Synthetic SCDM test data plus captured SAS output used
  to verify the Python port produces identical flags; the harness is the automated comparison
  tool.
- **Ibis**: A Python dataframe/expression library that compiles the same relational
  expression to different backends (DuckDB, Spark, SQL engines) — used here so one check
  implementation runs on multiple engines.
- **DuckDB**: An embedded, single-node analytical database engine; the default backend, used
  for local runs including larger-than-memory data via disk spill.
- **Spark (PySpark)**: A distributed data-processing engine; the opt-in backend for
  cluster-scale runs.
- **Parquet**: A columnar binary file format; the input/output data format this package
  consumes and produces (replacing SAS's `sas7bdat` format).
- **sas7bdat**: SAS's native binary dataset file format; explicitly out of scope for this
  package, which only consumes parquet produced by an upstream conversion tool.
- **Input manifest**: A YAML file (produced by the upstream sas7bdat→parquet conversion
  program) describing the ETL number, SCDM version, and table paths/row counts for a run —
  the contract between that conversion tool and this package.
- **Run manifest**: A record this package emits per run, capturing package version, resolved
  config, the input-manifest reference, and per-check outcomes — for provenance and audit.
- **Lookup tables (`lkp_*`)**: SAS binary reference tables (e.g., `lkp_all_flags`,
  `lkp_all_l1`) holding check metadata; converted to versioned YAML in this design.
- **Hypothesis**: A Python property-based testing library, used here to generate edge cases
  (e.g., null/boundary values) for check logic beyond the fixed parity fixtures.
- **Protocol (Python typing)**: A structural typing construct (`typing.Protocol`) used here to
  define the `Check` interface that every check class must implement.
- **pydantic-settings**: A Python library for typed, validated configuration models loaded
  from files/environment variables; used for this package's config layer.
- **Typer**: A Python library for building CLI applications; used for the `qa-mil` command
  line entry point.
- **uv**: A Python package/project manager; used to manage dependencies and run commands for
  this package.

## Architecture

The package separates check definition from check execution. Checks are engine-agnostic
relational expressions (Ibis); a pluggable backend executes them — DuckDB by default for
single-node runs (lazy parquet scans, disk spill for larger-than-memory data), PySpark
opt-in for cluster execution. One codepath serves both.

Data flow:

```
parquet inputs + input manifest
        │
        ▼
manifest validation (ETL number, SCDM version, required tables)
        │
        ▼
engine session (DuckDB | Spark) — registers parquet tables lazily
        │
        ▼
check runner — discovers registered checks, filters by config,
executes per level (L1 → L2 → L3), collects flag tables
        │
        ├──► dplocal writer  (patient-level flag detail)
        ├──► msoc writer     (aggregate results)
        └──► run manifest    (provenance + per-check summary)
```

### Input contract

The package consumes a directory of parquet datasets (one per SCDM table) plus an input
manifest produced by the upstream conversion program:

```yaml
# input_manifest.yaml — produced by the sas7bdat→parquet conversion program
etl_number: 12
scdm_version: "8.2.0"
tables:
  mil:
    path: mil.parquet
    row_count: 1483920
  enr:
    path: enr.parquet
    row_count: 98214550
conversion:
  tool: scdm-convert
  version: "1.4.0"
  completed_at: "2026-07-01T14:22:00Z"
```

This manifest is the contract with the conversion program. SAS-specific semantics (formats,
lengths, missing-value representations) are resolved upstream; this package never reads
sas7bdat.

### Check contract

Every check implements one protocol and returns flag rows in one schema. This is the
package's central internal contract:

```python
class Check(Protocol):
    check_id: str            # e.g. "371"
    level: int               # 1, 2, or 3
    severity: Severity       # WARN or ABORT
    tables: frozenset[str]   # SCDM table ids this check applies to

    def build(self, tables: TableSet, params: CheckParams) -> ibis.Table:
        """Return flag rows conforming to FLAG_SCHEMA."""

FLAG_SCHEMA = ibis.schema({
    "flagid": "string",      # {TABID}_{level}_00_00-0_{checknum}
    "flag_descr": "string",
    "message": "string",
    "flag_type": "string",   # "Warn" | "Abort"
    "abort_yn": "string",    # "Y" | "N"
    # plus check-specific key columns carried for dplocal detail
})
```

Parameterized families collapse into one class: checks 371–375 are a single check
parameterized by Birth_Type, mirroring the existing SAS loop.

### Check metadata

The binary lookup tables (`lkp_all_flags`, `lkp_all_l1`, `lkp_all_saslength`,
`lkp_l1_idlength`) become versioned YAML in `src/qa_mil/lookups/`, loaded through typed
models. Check metadata becomes diffable and reviewable. Lookups are applied as joins, never
per-row queries — the row-by-row lookup antipattern documented in
`PERFORMANCE_OPTIMIZATION_REPORT.md` (12 instances, 1,200–2,400 redundant queries per run)
is designed out, not ported.

### Module layout

```
qa-mil/
├── pyproject.toml            # uv-managed; hatchling build backend
├── src/qa_mil/
│   ├── cli.py                # Typer entry point: run, validate-config, list-checks
│   ├── config.py             # pydantic-settings models
│   ├── manifest.py           # input-manifest validation, run-manifest emission
│   ├── engine/               # backend protocol, duckdb.py, spark.py
│   ├── checks/
│   │   ├── base.py           # Check protocol, FLAG_SCHEMA
│   │   ├── registry.py       # discovery, filtering, level ordering
│   │   ├── level1/
│   │   ├── level2/
│   │   └── level3/
│   ├── lookups/              # YAML metadata (replaces lkp_*.sas7bdat)
│   ├── outputs/              # dplocal writer, msoc writer (separated by construction)
│   └── run.py                # orchestrator
└── tests/
    ├── unit/
    ├── parity/               # golden-output comparisons vs SAS package
    └── fixtures/             # synthetic SCDM data
```

Tooling: uv, ruff, pyright, pytest (with Hypothesis for property tests), pre-commit, CI
running the test suite against both backends.

## Existing Patterns

This is a re-implementation, not a greenfield design; the SAS package's own structure
motivates the Python patterns:

- `inputfiles/control_flow.csv` plus the `%qa_mil_control_flow` macro already implement
  table-driven dispatch. The check registry and runner are the same idea with checks as
  first-class objects instead of `%include`d programs.
- Check metadata already lives outside check logic (the `lkp_*.sas7bdat` tables); the YAML
  lookups preserve that separation in a reviewable format.
- The `flagid` scheme, flag record fields (`flagid`, `flag_descr`, `message`, `FlagType`,
  `AbortYN`), and the dplocal/msoc output split are preserved exactly — downstream QA review
  processes depend on them.
- The ETL-number validation in `%qa_mil_control_flow` (checked against the MIL dataset
  label) becomes manifest validation, moved to the front of the run.

Divergences, with justification:

- Check logic moves from imperative macros (`scdm_qa_mil_standard_macros.sas`, 3,502 lines)
  to declarative expression-building classes: testable in isolation, portable across
  backends.
- Row-by-row lookup queries become joins (see Architecture); this is a known performance
  defect in the SAS implementation, not a semantic feature.
- Per-run configuration moves from editing the master file header to a config file; header
  editing is the largest operational failure mode at sites (typos discovered hours into a
  batch run).

## Implementation Phases

<!-- START_PHASE_1 -->
### Phase 1: Project scaffolding

**Goal:** Installable, CI-verified package skeleton.

**Components:**
- `pyproject.toml` with uv-managed dependencies (ibis-framework[duckdb], typer,
  pydantic-settings, pyarrow)
- `src/qa_mil/` package skeleton with empty modules per the layout above
- ruff, pyright, pytest, pre-commit configuration
- CI pipeline running lint, typecheck, and tests

**Dependencies:** None (first phase).

**Done when:** `uv sync` succeeds; `uv run qa-mil --help` prints usage; lint, typecheck, and
an initial trivial test pass in CI.
<!-- END_PHASE_1 -->

<!-- START_PHASE_2 -->
### Phase 2: Configuration and manifests

**Goal:** Typed configuration, input-manifest validation, run-manifest emission.

**Components:**
- Config models in `src/qa_mil/config.py` — paths, ETL number, request tokens, backend
  selection, check enable/disable
- Manifest models and validation in `src/qa_mil/manifest.py` — input-manifest schema
  (contract above), ETL/version cross-checks, required-table presence
- CLI commands `validate-config` and the config-loading path of `run` in `src/qa_mil/cli.py`

**Covers:** qa-mil-python-port.AC1.1, AC1.2, AC1.3, AC4.3 (manifest emission structure).

**Dependencies:** Phase 1.

**Done when:** Tests verify each covered AC: valid config+manifest loads; ETL mismatch and
missing tables fail fast with the specified errors; run-manifest model round-trips.
<!-- END_PHASE_2 -->

<!-- START_PHASE_3 -->
### Phase 3: Engine layer

**Goal:** Backend abstraction over DuckDB with lazy parquet table registration.

**Components:**
- Backend protocol and session management in `src/qa_mil/engine/`
- DuckDB backend in `src/qa_mil/engine/duckdb.py` — registers manifest tables as lazy Ibis
  tables, configures spill directory and memory limits

**Covers:** groundwork for qa-mil-python-port.AC3.1 (verified at scale in Phase 8).

**Dependencies:** Phase 2 (manifest provides table paths).

**Done when:** Tables from a fixture manifest are queryable via Ibis expressions; engine
unit tests pass; a synthetic dataset larger than a small configured memory limit completes
an aggregation (spill smoke test).
<!-- END_PHASE_3 -->

<!-- START_PHASE_4 -->
### Phase 4: Check framework and walking skeleton (check 371)

**Goal:** The full vertical slice — registry, runner, outputs — proven with one real check.

**Components:**
- Check protocol and FLAG_SCHEMA in `src/qa_mil/checks/base.py`
- Registry and level-ordered runner in `src/qa_mil/checks/registry.py` and
  `src/qa_mil/run.py`
- dplocal and msoc writers in `src/qa_mil/outputs/` with the identifier-column guard on the
  msoc writer
- Birth_Type linkage check (371–375 as one parameterized class) in
  `src/qa_mil/checks/level3/`

**Covers:** qa-mil-python-port.AC1.4, AC1.5, AC2.2, AC2.3, AC4.1, AC4.2.

**Dependencies:** Phase 3.

**Done when:** `qa-mil run` executes check 371 end-to-end on synthetic fixture data,
producing dplocal flag detail, msoc aggregates, and a run manifest; tests verify each
covered AC, including the msoc identifier-column rejection.
<!-- END_PHASE_4 -->

<!-- START_PHASE_5 -->
### Phase 5: SAS parity harness

**Goal:** The acceptance gate every subsequent check ports through.

**Components:**
- Parity fixtures in `tests/fixtures/` — synthetic SCDM MIL data (Medicare SynPUF-derived
  or generated), plus captured SAS package output for the same data
- Comparison harness in `tests/parity/` — normalizes type mappings (SAS dates, lengths,
  missing values → Arrow), diffs flag tables, reports row-level differences
- Hypothesis property tests for drift-prone semantics: nulls in group-by keys, duplicate
  encounters, Birth_Type boundary values

**Covers:** qa-mil-python-port.AC2.1 and AC2.4 for check 371; establishes the mechanism for
all later checks.

**Dependencies:** Phase 4.

**Done when:** Check 371 output matches SAS output on the parity fixture; null-semantics
property tests pass; the harness reports a deliberately introduced discrepancy (negative
test of the harness itself).
<!-- END_PHASE_5 -->

<!-- START_PHASE_6 -->
### Phase 6: Level 1 checks and lookup migration

**Goal:** All Level 1 structural checks ported; binary lookups replaced.

**Components:**
- YAML lookups in `src/qa_mil/lookups/` converted from `lkp_all_flags`, `lkp_all_l1`,
  `lkp_all_saslength`, `lkp_l1_idlength`, with typed loader models
- Level 1 check families (100, 101, 102, 111, 120) in `src/qa_mil/checks/level1/` — table
  exists, table populated, SCDM variable compliance, variable lengths

**Covers:** qa-mil-python-port.AC2.1 for Level 1 checks.

**Dependencies:** Phase 5 (parity harness is the per-check gate).

**Done when:** Each Level 1 check passes parity against SAS output; lookup YAML round-trips
against the original sas7bdat contents (one-time migration verification test).
<!-- END_PHASE_6 -->

<!-- START_PHASE_7 -->
### Phase 7: Level 2 checks

**Goal:** The ~26 `flag_2xx` checks (200–280 series) ported. The bulk of the porting work.

**Components:**
- Level 2 checks in `src/qa_mil/checks/level2/` — duplicates, ranges, cross-table and
  enrollment-overlap checks, grouped into modules by check family
- Extensions to parity fixtures covering cross-table cases (MIL × enrollment, MIL × source
  tables)

**Covers:** qa-mil-python-port.AC2.1 and AC2.3 for Level 2 checks (including abort-type
behaviour, which first appears in this series).

**Dependencies:** Phase 6.

**Done when:** Every Level 2 check passes parity against SAS output; abort-path test
verifies a failing abort check halts the run.
<!-- END_PHASE_7 -->

<!-- START_PHASE_8 -->
### Phase 8: Remaining Level 3 checks and Spark backend

**Goal:** Complete check coverage; second backend proven; scale verified.

**Components:**
- Checks 394, 396, 397 in `src/qa_mil/checks/level3/` (372–375 already exist via the Phase 4
  parameterized class)
- Spark backend in `src/qa_mil/engine/spark.py`
- CI matrix running the full check suite against both backends
- Larger-than-memory verification run against a generated dataset exceeding available RAM

**Covers:** qa-mil-python-port.AC2.1 (remaining L3 checks), AC3.1, AC3.2, AC3.3.

**Dependencies:** Phase 7.

**Done when:** All checks pass parity on both backends with identical flag tables; the
larger-than-memory run completes on DuckDB; backend selection is exercised via config alone
in tests.
<!-- END_PHASE_8 -->

## Additional Considerations

**Parity tolerance policy.** "Matches SAS output" needs a written policy before Phase 5:
exact match on flag decisions and flagids; documented, reviewed mappings for type-level
differences (SAS dates vs Arrow date32, trailing-blank padding from fixed SAS lengths,
numeric missing vs null). Every accepted difference is recorded in the parity harness
config, not waved through ad hoc.

**Message-text fidelity.** SAS `cat()`/`put()` formatting in flag messages (e.g., mmddyy10.
dates) must be reproduced exactly if downstream tooling parses messages; if nothing parses
them, message format can be declared cosmetic in the parity policy. Resolve this with the
SOC before Phase 5 — it determines how strict the harness's message comparison is.

**Ibis backend gaps.** If a check's expression hits an operation one backend lacks, the
fallback is embedded SQL for that check with a per-backend dialect — contained in the
check class, invisible to the runner. Expected to be rare given the relational simplicity
of the checks; any occurrence gets a test on both backends.

**Deferred work.** SCDM Snapshot and QA Common Components will be designed separately as
sibling packages sharing the engine and output layers. The sas7bdat→parquet conversion
program owns SAS semantics; its contract with this package is the input manifest. HTML
report rendering is deferred — parquet/CSV outputs are the deliverable for parity with the
current package.

**Supersedes:** `PYTHON_REIMPLEMENTATION_DESIGN.md` (repo root), the pre-PRD summary of the
same design.
