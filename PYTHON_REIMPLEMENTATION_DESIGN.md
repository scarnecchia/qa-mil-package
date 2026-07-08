# QA MIL package: Python re-implementation design

Design summary for re-implementing the QA MIL package in Python, supporting SAS and parquet
data larger than memory, with optional PySpark execution.

**Status:** Draft for discussion
**Date:** 2026-07-07

## Scope

In scope:

- The core QA review pipeline: master orchestration, control flow, and the Level 1, 2, and 3
  checks (currently `00.0_scdm_mil_data_qa_review_master_file.sas`, `scdm_qa_mil_control_flow.sas`,
  the three `scdm_data_qa_mil_review-level*.sas` programs, and the check macros in
  `scdm_qa_mil_standard_macros.sas`).
- The lookup tables that parameterize checks (`lkp_all_flags`, `lkp_all_l1`,
  `lkp_all_saslength`, `lkp_l1_idlength`).
- Output generation preserving the `dplocal` (patient-level) / `msoc` (aggregate) split and the
  existing `flagid` scheme.

Out of scope (deferred):

- **SCDM Snapshot** (`inputfiles/scdm_snapshot/`) and **QA Common Components**
  (`inputfiles/qa_common_components/`). These will be revisited separately. The architecture
  below leaves room for them as sibling packages sharing the engine and output layers.
- **Data ingest / format conversion.** A separate conversion program is assumed to already
  exist. This package consumes parquet only; sas7bdat-to-parquet conversion happens upstream.
  The package's input contract is a directory of parquet datasets plus a manifest (see below).

## Current-state summary

The existing package is SAS 9.4, roughly 10.8K lines across 41 files (about half of that in the
two deferred sub-packages). Key structural facts that shape the re-design:

- Execution is already table-driven: `control_flow.csv` lists modules with execute flags and
  sequence numbers; an orchestrator macro loops them in order.
- Checks are organized in three levels:
  - **Level 1** (5 check families: 100, 101, 102, 111, 120) — structural and existence checks:
    table exists, is populated, complies with SCDM variable definitions and lengths.
  - **Level 2** (~26 `flag_2xx` macros, 200–280 series) — duplicates, ranges, cross-table and
    enrollment-overlap checks.
  - **Level 3** (8 checks: 371–375, 394, 396, 397) — suspect-linkage checks on mother-infant
    relationships. All warnings, non-aborting. Documented in `300_SERIES_CHECKS_REFERENCE.md`.
- Check *logic* lives in imperative SAS macros while check *metadata* lives in binary
  `.sas7bdat` lookup tables. Neither is diffable or reviewable in isolation.
- Flag records carry `flagid` (`{TABID}_{level}_00_00-0_{checknum}`), `message`, `flag_descr`,
  `FlagType` (Warn/abort), and `AbortYN`. Downstream processes depend on this schema.
- The performance analysis in this repo (`PERFORMANCE_OPTIMIZATION_REPORT.md`) identified a
  row-by-row SQL lookup antipattern (12 instances generating 1,200–2,400 redundant queries per
  run). This is an artifact of the macro implementation, not the check semantics.

## Design decisions

### 1. Checks are decoupled from the execution engine

This is the load-bearing decision. The SAS package entangles what a check is (e.g., "count
distinct CPatIDs per MPatID/ADate/EncounterID; flag where the count differs from Birth_Type")
with how it runs (PROC SQL against a libname). The Python package separates them:

- Checks are defined once as engine-agnostic relational expressions.
- A pluggable backend executes them: a fast single-node engine by default, Spark when data or
  infrastructure demands it.

**Recommendation: Ibis as the expression layer, DuckDB as the default backend, PySpark as the
opt-in cluster backend.**

Why Ibis rather than two parallel implementations (Polars + PySpark) or pure PySpark:

- One codepath. A check written as an Ibis expression compiles to DuckDB SQL locally or a
  Spark plan on a cluster. Two implementations of 40 checks means two sets of semantics to
  keep in parity.
- DuckDB handles larger-than-memory workloads natively (lazy parquet scans, disk spill) and
  substantially outperforms local-mode Spark for single-node work — which is the common case
  for a site QA run. Pure PySpark would impose JVM startup and shuffle overhead on every
  small run.
- The QA checks are plain relational operations (filters, group-bys, joins, counts). This is
  exactly the subset Ibis supports well across backends; the risk of hitting backend-specific
  gaps is low.

Tradeoff acknowledged: Ibis is an additional dependency layer with occasional backend quirks.
If the organization later commits fully to Spark infrastructure, the engine module is the only
part that changes.

### 2. Parquet is the only input format

The package reads parquet exclusively. The upstream conversion program is responsible for
producing parquet from sas7bdat and for resolving SAS-specific semantics (formats, lengths,
missing-value representations) at that boundary.

Input contract:

- A directory of parquet datasets, one per SCDM table, named per a documented convention.
- A **run manifest** (JSON or YAML) accompanying the data: source ETL number, SCDM version,
  table names, row counts, and conversion provenance. The package validates the manifest
  before running — the equivalent of the current ETL-number-vs-dataset-label check in
  `%qa_mil_control_flow`, done up front with a clear error message.

### 3. Checks form a declarative registry

Each check is a small class implementing a common protocol:

- Identity: check number, level, flagid pattern.
- Severity: warn or abort (`FlagType`, `AbortYN`).
- Applicability: which SCDM tables it runs against.
- Logic: a `build(tables, params) -> ibis.Table` method returning flag rows in the standard
  flag schema.

Supporting decisions:

- A registry plus a runner replaces `control_flow.csv` dispatch and the master-file macro
  loop. The runner discovers checks, filters by configuration, executes them (checks within a
  level parallelize trivially since they are independent), and collects results.
- Parameterized check families collapse: checks 371–375 are one class parameterized by
  Birth_Type value, mirroring the existing SAS loop rather than five copies.
- The binary lookup tables (`lkp_all_flags`, `lkp_all_saslength`, etc.) become versioned YAML
  or CSV files in the package, loaded through typed models. Check metadata becomes reviewable
  in a pull request diff.
- The row-by-row lookup antipattern from the SAS implementation is designed out: lookups are
  a single join against the lookup table, not a query per row. Port check intent, not macro
  mechanics.
- The existing `flagid` scheme and flag record schema are preserved exactly, for continuity
  with historical QA output and downstream consumers.

### 4. Configuration replaces header editing

The current workflow — open the master SAS file, edit sections 1 and 2 of the header, run in
batch — becomes:

- A CLI (Typer): `qa-mil run --config site_config.yaml`, plus `qa-mil validate-config` and
  `qa-mil list-checks`.
- Typed configuration (pydantic-settings): data paths, ETL number, request ID tokens, backend
  selection, per-check or per-level enable/disable. Configuration errors surface immediately
  with actionable messages instead of failing hours into a SAS log.

### 5. Outputs preserve the privacy split

- Patient-level flag detail (current `dplocal.*`) and aggregate results (current `msoc.*`) go
  through separate writer modules. The separation is architectural, not conventional: the
  aggregate writer cannot receive patient-level columns, making identifier leakage into
  shareable output structurally difficult.
- Result tables are written as parquet (with CSV export where downstream tooling requires it).
- Each run emits a manifest: package version, configuration, input manifest, check results
  summary, timing. This subsumes the current signature-file and log-checker roles.

## Package skeleton

```
qa-mil/
├── pyproject.toml            # uv-managed; hatchling build backend
├── src/qa_mil/
│   ├── cli.py                # Typer entry point
│   ├── config.py             # pydantic-settings models
│   ├── manifest.py           # input-manifest validation, run-manifest emission
│   ├── engine/               # backend selection (duckdb | spark), session management
│   ├── checks/
│   │   ├── base.py           # Check protocol, flag-record schema
│   │   ├── registry.py       # discovery, filtering, execution ordering
│   │   ├── level1/
│   │   ├── level2/
│   │   └── level3/
│   ├── lookups/              # YAML/CSV metadata (replaces lkp_*.sas7bdat)
│   ├── outputs/              # dplocal-equivalent and msoc-equivalent writers
│   └── run.py                # orchestrator
└── tests/
    ├── unit/
    ├── parity/               # golden-output comparisons vs SAS package
    └── fixtures/             # synthetic SCDM data
```

Tooling: uv for dependency and environment management, ruff for lint and format, pyright for
type checking, pytest for tests, pre-commit hooks, CI running the suite against both backends.

## Verification strategy

This is a validated QA tool in a regulatory-adjacent pipeline. The dominant risk is not
architecture; it is silent behavioural drift from the SAS implementation — missing-value
semantics, date handling, count-distinct edge cases.

- **Parity harness as the acceptance gate.** Run the SAS package and the Python package
  against the same synthetic SCDM data (the Medicare SynPUFs in SCDM format), diff the flag
  tables. A check is "done" when its output matches, or when every difference is explained
  and accepted in writing.
- **Property-based tests** (Hypothesis) on the semantics most likely to drift: nulls in
  group-by keys, duplicate encounters, Birth_Type boundary values, date edge cases.
- **Both backends in CI.** Every check runs against DuckDB and Spark in the test suite, so
  backend divergence is caught at merge time rather than at a site.

## Migration order

1. **Walking skeleton.** Config, manifest validation, engine module, one Level 3 check (371)
   end-to-end on DuckDB, parity harness proving it against SAS output. This de-risks every
   architectural decision before volume porting starts.
2. **Level 1.** Small (5 check families) and lookup-driven; exercises the lookup-table
   migration.
3. **Level 2.** The bulk of the work (~26 checks). Grind through with the parity harness as
   the per-check gate.
4. **Remaining Level 3 checks** (372–375 fall out of 371; then 394, 396, 397).
5. **Spark backend.** Last, deliberately: by this point it is a backend flag plus a CI matrix
   entry, not a rewrite.

## Deferred items

- SCDM Snapshot and QA Common Components re-implementation (owner has separate thoughts;
  revisit after the core package is proven).
- The sas7bdat-to-parquet conversion layer (assumed to exist as a separate program; its
  contract with this package is the input manifest described above).
- Report rendering (HTML summaries of run results) — useful, but not required for parity with
  the current package.
