# Level 2 Check Inventory (NUM-39)

**Status:** Complete
**Source:** `inputfiles/scdm_data_qa_mil_review-level2.sas`, `inputfiles/scdm_qa_mil_standard_macros.sas`
**Last updated:** 2026-07-07

## Overview

Level 2 checks are metadata-driven data quality checks executed in two passes:
1. **Pass 1**: Intra-table checks (all severity levels, no cross-table)
2. **Pass 2**: Cross-table checks with AbortYN='y' only

Checks are dispatched from `temp_l2_flags` lookup table with macro dispatch:
- Checks 217–219, 272–275: shared macro `%flag_217_219_27_`
- Checks 201–203: shared macro `%flag_201_203`
- All others: individual macro `%flag_&checkid.`

## Check inventory

### Enrollment/date family (200–207)

| Check | Description | Severity | Tables | Scope | Key Columns | Source Lines |
|-------|-------------|----------|--------|-------|-------------|-------------|
| 200 | Test dates outside active enrollment | Abort | MIL, ENR | dplocal | PatID, testdate, enr_start, enr_end | std_macros:1708–1748 |
| 201 | Date range/validity check | Warn | MIL | dplocal | date variables | std_macros:1756, 2798+ |
| 202 | Date range/validity check | Warn | MIL | dplocal | date variables | std_macros:1766, 2798+ |
| 203 | Cross-table variable length compliance | Warn | MIL | dplocal | variable1, dp_length | std_macros:1776–1820 |
| 204 | Date/range check | Warn | MIL | dplocal | date variables | std_macros:1821–1860 |
| 205 | Date/range check | Warn | MIL | dplocal | date variables | std_macros:1861–1870 |
| 206 | Date/range check | Warn | MIL | dplocal | date variables | std_macros:1871–1880 |
| 207 | Date/range check | Warn | MIL | dplocal | date variables | std_macros:1881–1962 |
| 208 | Cross-table data check | Warn | MIL | dplocal | variable checks | std_macros:3002+ |

### Duplicate/key family (211, 215–216, 217–219)

| Check | Description | Severity | Tables | Scope | Key Columns | Source Lines |
|-------|-------------|----------|--------|-------|-------------|-------------|
| 211 | Duplicate record/key check | Warn | MIL | dplocal | key variables | std_macros:1963–2003 |
| 215 | Duplicate/unique check | Warn | MIL | dplocal | key variables | std_macros:2004–2047 |
| 216 | Duplicate/unique check | Warn | MIL | dplocal | key variables | std_macros:2048–2090 |
| 217 | Duplicate key in table | Abort | MIL | dplocal | key variables | std_macros:3073+ |
| 218 | Duplicate key in table | Abort | MIL | dplocal | key variables | std_macros:3073+ |
| 219 | Duplicate key in table | Abort | MIL | dplocal | key variables | std_macros:3073+ |

### Cross-table consistency family (221, 223, 226–229, 254, 255, 257, 280)

| Check | Description | Severity | Tables | Scope | Key Columns | Source Lines |
|-------|-------------|----------|--------|-------|-------------|-------------|
| 221 | Cross-table consistency | Warn | MIL | dplocal | linkage IDs | std_macros:3335+ |
| 223 | Cross-table consistency | Warn | MIL | dplocal | linkage IDs | std_macros:2091–2150 |
| 226 | Cross-table consistency | Warn | MIL | dplocal | variable checks | std_macros:2151–2167 |
| 227 | Cross-table consistency | Warn | MIL | dplocal | variable checks | std_macros:2168–2179 |
| 228 | Cross-table consistency | Warn | MIL | dplocal | variable checks | std_macros:2180–2191 |
| 229 | Cross-table consistency | Warn | MIL | dplocal | variable checks | std_macros:2192+ |
| 254 | Cross-table consistency | Warn | MIL | dplocal | linkage IDs | std_macros:3347+ |
| 255 | Cross-table consistency | Warn | MIL | dplocal | linkage IDs | std_macros:3459+ |
| 257 | Cross-table consistency | Warn | MIL | dplocal | linkage IDs | std_macros:3471+ |
| 280 | Cross-table consistency | Warn | MIL | dplocal | linkage IDs | std_macros:3359+ |

### Cross-table enrollment/linkage family (272–275)

| Check | Description | Severity | Tables | Scope | Key Columns | Source Lines |
|-------|-------------|----------|--------|-------|-------------|-------------|
| 272 | Cross-table enrollment check | Abort | MIL, ENR | dplocal | PatID, dates | std_macros:3073+ |
| 273 | Cross-table enrollment check | Abort | MIL, ENR | dplocal | PatID, dates | std_macros:3073+ |
| 274 | Cross-table enrollment check | Abort | MIL, ENR | dplocal | PatID, dates | std_macros:3073+ |
| 275 | Cross-table enrollment check | Abort | MIL, ENR | dplocal | PatID, dates | std_macros:3073+ |

## Family grouping for implementation

| Family | Checks | Key behavior |
|--------|--------|-------------|
| Duplicate/key | 211, 215, 216, 217, 218, 219 | Intra-table duplicate detection |
| Date/range/value-domain | 201, 202, 203, 204, 205, 206, 207, 208 | Date validity and range checks |
| Cross-table consistency | 221, 223, 226, 227, 228, 229, 254, 255, 257, 280 | MIL × reference table consistency |
| Enrollment/eligibility | 200, 272, 273, 274, 275 | MIL dates vs enrollment intervals |

## Abort behavior

Abort checks (AbortYN='y') cause the entire QA program to stop:
- **Pass 1**: Intra-table abort checks (217, 218, 219) run first
- **Pass 2**: Cross-table abort checks (200, 272–275) run second
- If any abort flag is found in either pass, subsequent checks are skipped

## Metadata-driven vs custom expression

Most Level 2 checks are metadata-driven from `temp_l2_flags` lookup table, which is
built from `lkp_all_flags` filtered by level=2. The check logic is implemented in
shared macros (`l2_flags_200_207`, `l2_flags_201_202`, `l2_flags_217_219_27_`) that
read variable names, conditions, and table references from the lookup.

## Null/boundary cases to test

- Null linkage IDs (MPatID, CPatID) in duplicate checks
- Null date values in date/range checks
- Missing enrollment records in enrollment checks
- Duplicate keys with null components
- Date boundary values (exactly on min/max dates)
- Zero-row enrollment tables
