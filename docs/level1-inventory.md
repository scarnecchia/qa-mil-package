# Level 1 Check Inventory (NUM-34)

**Status:** Complete
**Source:** `inputfiles/scdm_data_qa_mil_review-level1.sas`
**Last updated:** 2026-07-07

## Table-level checks (varid = "00")

| Check | Description | Severity | FlagID Pattern | SAS Lines |
|-------|-------------|----------|----------------|-----------|
| 100 | Table exists | Abort | `{TABID}_1_00_00-0_100` | 38–50 |
| 101 | Table populated | Abort | `{TABID}_1_00_00-0_101` | 53–95 |
| 102 | Table sort order correct | Abort | `{TABID}_1_00_00-0_102` | 100–153 |

- Check 100 aborts if a table from the control flow cannot be found.
- Check 101 aborts if a table has zero rows.
- Check 102 only runs for the first table in the list (j=1) and uses
  `lkp_all_l1.sortorder` to verify sort order.

## Variable-level checks (varid = variable-specific)

| Check | Description | Severity | FlagID Pattern | SAS Lines |
|-------|-------------|----------|----------------|-----------|
| 110 | Required column missing | Warn | `{TABID}_1_{varid}_00-0_110` | 297–304 |
| 111 | Variable not populated | Warn | `{TABID}_1_{varid}_00-0_111` | 450–463 |
| 112 | Variable type mismatch | Warn | `{TABID}_1_{varid}_00-0_112` | 306–313 |
| 113 | Variable length mismatch | Warn | `{TABID}_1_{varid}_00-0_113` | 314–321 |
| 120 | Variable has null values | Warn | `{TABID}_1_{varid}_00-0_120` | 465–468 |
| 121 | Invalid data/value-format | Warn | `{TABID}_1_{varid}_00-0_121` | 526–536 |
| 122 | Leading spaces in char var | Warn | `{TABID}_1_{varid}_00-0_122` | 540–543 |
| 126 | Age range (10–54 inclusive) | Warn | `{TABID}_1_{varid}_00-0_126` | 545–548 |
| 131 | Date within DP min/max range | Warn | `{TABID}_1_{varid}_00-0_131` | 550–553 |
| 133 | Name format (alpha/hyphen/apostrophe) | Warn | `{TABID}_1_{varid}_00-0_133` | 556–566 |

## Inactive check

| Check | Status | Reason |
|-------|--------|--------|
| 130 | **Not applicable** | Referenced in SAS metadata join logic (line 492) alongside 121, 122, 126, 131, 133, but no explicit branch handler exists in `l1_value_12x_13x`. The check is metadata-driven but inactive because no condition is set for checkid=130. Documented as not applicable for the Python port. |

## Metadata dependencies

- `lkp_all_flags`: Check-level metadata (flagid, flag_descr, flagtype, abortyn, flagyn, variable1)
- `lkp_all_l1`: Variable-level metadata (tabid, variable, varid, vartype, varlength, sortorder, flagcondition, validvaluetype)
- `lkp_all_saslength`: SAS variable lengths for length compliance (113)
- `lkp_l1_idlength`: ID variable lengths

## Fatal vs reportable distinction

- **Fatal input validation**: When an enabled check requires a table that is absent
  from the manifest or unreadable, `qa-mil` fails fast before checks execute.
- **Reportable Level 1 flags**: When lookup metadata indicates SAS would produce
  QA flags for expected SCDM tables (e.g., check 100 for a missing expected table),
  this is a reportable flag, not a crash. The distinction is implemented in the
  runner: required-table validation is fatal; check 100 flag emission is reportable.

## Parquet-era length semantics

Parquet does not carry SAS fixed-width character metadata. For checks 112/113:
- Type compliance uses Arrow/parquet schema types.
- Length compliance validates observed maximum string length against expected
  SAS length metadata from `lkp_all_l1.varlength`.
- Cases where SAS fixed-length metadata cannot be reproduced are documented
  per check.
