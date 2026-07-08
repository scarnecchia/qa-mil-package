# Lookup Data Provenance (NUM-34)

**Last updated:** 2026-07-07

## Purpose

This directory contains deterministic JSON lookup data for the qa-mil Python
package, redesigned from SAS binary lookup tables (`lkp_all_flags`,
`lkp_all_l1`, `lkp_all_saslength`, `lkp_l1_idlength`).

## Source mapping

| JSON file | SAS source | Purpose |
|-----------|-----------|---------|
| `checks.json` | `lkp_all_flags` | Check flag definitions: check_id, level, tabid, varid, flag_descr, flag_type, abort_yn |
| `level1_rules.json` | `lkp_all_l1` | Level 1 variable rules: tabid, variable, varid, vartype, varlength, sortorder, flagcondition |
| `variable_lengths.json` | `lkp_all_saslength` | Expected SAS variable lengths |
| `id_lengths.json` | `lkp_l1_idlength` | ID variable lengths |

## Design decisions

- **Deterministic JSON** instead of YAML for generated metadata: JSON supports
  deterministic sorting and JSON Schema validation.
- **Structural consolidation**: SAS table boundaries are not preserved unless
  useful. Related metadata is consolidated into single files.
- **Provenance** is documented here, not in inline JSON comments.
- **Validation** via typed Pydantic models in `models.py` and the loader in
  `loader.py`.

## Canonical metadata source

`checks.json` is the single source of truth for all implemented check metadata
across all levels (L1, L2, L3). Python check classes own executable logic —
filter conditions, ibis expressions, and table joins — while identity, flag
description, severity, and abort status come from `CheckFlagDef` lookup rows.

### How it works

- Each L2/L3 check class accepts a `flag_def: CheckFlagDef` field at construction.
- The `metadata` property reads `flag_def.flag_descr` for `description` and
  converts `flag_def.flag_type` via `flag_type_to_severity()` for `severity`.
- The `build()` method emits `flag_def.flag_descr`, `flag_def.flag_type`, and
  `flag_def.abort_yn` as literal columns — no hard-coded strings.
- `registry.py` resolves each check's `flag_def` from `checks.json` via
  `get_check_flag(check_id)` at registration time.

### `flag_type_to_severity()` mapping

| `flag_type` in checks.json | `Severity` enum |
|---------------------------|-----------------|
| `"Warn"` | `Severity.WARN` |
| `"Abort"` | `Severity.ABORT` |

This function lives in `checks/base.py` next to the `Severity` enum it returns.

## Parquet-era length semantics

Parquet does not carry SAS fixed-width character metadata. For length
compliance checks (113), we validate observed maximum string length against
expected SAS length metadata. Cases where SAS fixed-length metadata cannot
be exactly reproduced are documented per check.
