# Parity Policy (NUM-37)

**Status:** Approved
**Last updated:** 2026-07-07

## Purpose

This document defines which aspects of the Python QA MIL port must match SAS
exactly and which are flexible. It governs the parity harness comparison
behavior.

## Strict fields (must match)

The following must match SAS output exactly:

- **`flagid`**: Exact format `{TABID}_{level}_{varid}_00-0_{checknum}`.
- **Flag emission**: A row must be flagged if and only if SAS flags it.
- **Keyed entities**: The set of keyed entities (e.g., patient/encounter
  combinations) that trigger a flag must match.
- **Severity**: `Warn` vs `Abort` classification must match.
- **Routing**: dplocal vs msoc output destination must match.
- **Aggregate values**: Count and numeric aggregate outputs must match.

## Non-failing fields (informational by default)

The following do NOT cause parity test failures:

- **Message text**: Human-readable message text may differ in wording, variable
  formatting, or ordering. Only the semantic content should be similar.

## Accepted normalizations

The harness applies the following documented normalizations before comparison:

- **Column name canonicalization**: SAS-style names like `FlagType` →
  `flag_type`, `AbortYN` → `abort_yn`.
- **Date/datetime normalization**: Dates and datetimes are compared in a
  canonical representation determined by the semantic profile (e.g., ISO date
  strings).
- **Null/missing normalization**: SAS missing values (`.`, `.A`–`.Z`) and
  Python null are treated as equivalent missing.
- **Fixed-width character trimming**: SAS padded strings are trimmed for
  comparison when the semantic profile declares `character_padding: trimmed`.
- **Stable row sorting**: Rows are sorted by all columns for deterministic
  comparison regardless of input order.

Normalizations are encoded in the harness code (`tests/parity/canonicalize.py`),
not applied ad hoc per test.

## Rule: harness encodes policy

Accepted normalizations are implemented in harness helper code, not waived per
test. If a new normalization is needed, it must be:
1. Documented in this file.
2. Implemented in `tests/parity/canonicalize.py`.
3. Tested with positive and negative cases.

## Captured SAS parity deferral

Full captured-SAS comparison is deferred to NUM-49. The harness built in
NUM-33 supports synthetic/golden comparison now and is ready for captured SAS
outputs when they become available.
