# Input Manifest Contract (NUM-38)

**Status:** Approved
**Version:** 1.0
**Last updated:** 2026-07-07

## Purpose

This document specifies the versioned parquet input-manifest contract between the
upstream sas7bdat-to-parquet conversion program and the `qa-mil` Python package.

## Design decisions

### Manifest ownership and requiredness

- The manifest lists **produced tables only** — tables that the upstream conversion
  successfully produced as parquet.
- `qa-mil` determines which tables are **required** from the enabled checks.
- If an enabled check requires a table absent from the manifest or unavailable at its
  path, `qa-mil` fails fast and names the missing table and dependent check(s).

### Manifest versioning

Every manifest must include `manifest_version` so the contract can evolve safely.
The current supported version is `"1.0"`.

### Paths

Absolute paths are required for operational use and must be supported.

Path resolution rule:

- Absolute table paths are used unchanged.
- Relative table paths are resolved relative to the **input manifest file's parent
  directory**, not the current working directory.

### Semantic profile

Every manifest must include a `semantic_profile` declaring the upstream conversion
semantics consumed by `qa-mil`:

| Field | Purpose | Example values |
|---|---|---|
| `name` | Profile identifier | `qa-mil-parquet-v1` |
| `sas_date` | How SAS dates are represented in parquet | `date32` |
| `sas_datetime` | How SAS datetimes are represented | `timestamp_us` |
| `character_padding` | Character padding/trimming policy | `trimmed`, `padded` |
| `numeric_missing` | Numeric missing value representation | `null` |
| `special_missing` | Special missing value representation | `null` |

### Checksums

Checksums are **optional** for the initial contract. Per-table checksum fields may be
added in a future audit/provenance hardening effort.

### Conversion metadata

Optional provenance metadata (`conversion`) records the upstream tool, version, and
completion timestamp. It is carried into the run manifest if present but does not
affect validation.

## Example manifest

```yaml
manifest_version: "1.0"
etl_number: 12
scdm_version: "8.2.0"

semantic_profile:
  name: "qa-mil-parquet-v1"
  sas_date: "date32"
  sas_datetime: "timestamp_us"
  character_padding: "trimmed"
  numeric_missing: "null"
  special_missing: "null"

tables:
  mil:
    path: /data/site/run_12/mil.parquet
    row_count: 1483920
  enr:
    path: enr.parquet
    row_count: 98214550

conversion:
  tool: scdm-convert
  version: "1.4.0"
  completed_at: "2026-07-01T14:22:00Z"
```

## Validation rules enforced by qa-mil

1. `manifest_version` is present and supported.
2. `semantic_profile` is present with all required fields.
3. `etl_number` is present and matches the config's `etl_number`.
4. Each listed table path is resolved (absolute or manifest-relative) and exists.
5. Required tables derived from enabled checks are present in the manifest.
