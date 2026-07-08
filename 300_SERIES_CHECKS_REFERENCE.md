# 300 Series Checks Reference

> All 300 series checks are **Level 3 Suspect Linkage** checks implemented in the Mother-Infant Linkage (MIL) QA package. Every check is a **Warning** (non-aborting).

## Source File

All checks are implemented in a single file:

- **`inputfiles/scdm_data_qa_mil_review-level3.sas`** (lines 91-215)
- **Macro**: `%suplinkage`
- **Enabled via**: `inputfiles/control_flow.csv` line 5 (`l3,Y,scdm_data_qa_mil_review-level3,X,4,Level 3,N`)

The macro iterates over all tables listed in `msoc.control_flow_3` where `cc_table ne 'X'`.

---

## Checks Summary

| Check | Flag ID Pattern | Description | Lines |
|-------|----------------|-------------|-------|
| 371 | `{TABID}_3_00_00-0_371` | Birth_Type=1 inconsistent with linkage count | 110-157 |
| 372 | `{TABID}_3_00_00-0_372` | Birth_Type=2 inconsistent with linkage count | 110-157 |
| 373 | `{TABID}_3_00_00-0_373` | Birth_Type=3 inconsistent with linkage count | 110-157 |
| 374 | `{TABID}_3_00_00-0_374` | Birth_Type=4 inconsistent with linkage count | 110-157 |
| 375 | `{TABID}_3_00_00-0_375` | Birth_Type=5 inconsistent with linkage count | 110-157 |
| 394 | `{TABID}_3_00_00-0_394` | Birth_Type 2-8 with no CPatIDs linked | 159-176 |
| 396 | `{TABID}_3_00_00-0_396` | MPatID not linked to CPatID (mother without infant) | 178-195 |
| 397 | `{TABID}_3_00_00-0_397` | CPatID not linked to MPatID (infant without mother) | 197-213 |

All checks: `FlagType = "Warn"`, `AbortYN = "N"`

---

## Detailed Check Descriptions

### Checks 371-375: Birth_Type Linkage Consistency

**Lines 110-157** | Dynamic loop generating checks for Birth_Type values 1-5

**What it does**: For each Birth_Type value (1 through 5), counts the number of distinct `CPatID` records grouped by `MPatID`, `ADate`, `EncounterID`, and `Birth_Type`. If the count of linked infant records does not match the `Birth_Type` value, the check flags the record.

**Condition**: `crows ne birth_type` (where `crows` = count of distinct CPatIDs)

**Flag Description**: "Birth_Type ({value}) not consistent with number of linkages; confirmation required"

**Message**: "MPatID ({mpatid}), EncounterID ({encounterid}), Adate ({adate}), Birth_type ({birth_type}): Birth_Type value not consistent with number of linkages; confirmation required"

**Output Dataset**: `dplocal.flag_l3_37{b}_{TABID}`

**Source Code**:
```sas
proc sql;
  create table linkage&b. as
  select count(distinct cpatid) as crows, mpatid, adate, encounterid, birth_type
  from qadata.&&&tabid.table
  where birth_type=&bt. and not missing(cpatid) and not missing(mpatid)
  group by mpatid, adate, encounterid, birth_type
  order by mpatid, adate, encounterid, birth_type
  ;
quit;

data flag_&b._&a.;
  set linkage&b.;
  length message $300 flag_descr $255;
  length flagid $21;
  length FlagType $4 AbortYN $1;
  flag_descr = cat("Birth_Type (",birth_type,") not consistent with number of linkages; confirmation required");
  flagid = cats("%upcase(&tabid.)_",&level.,"_00_00-0_37&b.");
  FlagType = "Warn";
  AbortYN = "N";
  flag_l3 = 0;
  if crows ne birth_type then do;
    message = cat("MPatID (",mpatid,"), EncounterID (",encounterid,"), Adate (",put(adate, mmddyy10.),
     "), Birth_type (",birth_type,"):Birth_Type value not consistent with number of linkages; confirmation required");
  flag_l3 = 1;
  end;
  if flag_l3;
run;
```

---

### Check 394: Birth_Type 2-8 with No Linkages

**Lines 159-176**

**What it does**: Identifies records where `Birth_Type` is between 2 and 8 (indicating multiple births or specific birth classifications) but no `CPatID` is linked. These are "orphaned" mother records that should have linked infant records but don't.

**Condition**: `2 <= birth_type <= 8 and missing(Cpatid)`

**Flag Description**: "Birth_Type= 2-8 and no CPatIDs are linked"

**Message**: "MPatid ({mpatid}), EncounterID ({encounterid}), Adate ({adate}), Birth_Type ({birth_type}): No linkages were found; confirmation required"

**Output Dataset**: `dplocal.flag_l3_394_{TABID}`

**Source Code**:
```sas
proc sql;
  create table %str(dplocal.flag_l3_394_&tabid.) as
  select cats("%upcase(&tabid.)_",&level.,"_00_00-0_394") as flagid length =21
       , cat("MPatid (",mpatid,"), EncounterID (", Encounterid,"), Adate (",put(adate, mmddyy10.),
         "), Birth_Type (",birth_type,"): No linkages were found; confirmation required")
         as message length=300
       , cat("Birth_Type= 2-8 and no CPatIDs are linked") as flag_descr length = 255
       , "Warn" as Flagtype length = 4
       , "N" as abortyn length = 1
       , count(*) as count
  from qadata.&&&tabid.table
  where 2 <= birth_type <= 8 and missing(Cpatid)
  group by calculated flagid, calculated message, calculated flag_descr, flagtype, calculated abortyn
  ;
quit;
```

---

### Check 396: Mother Not Linked to Infant

**Lines 178-195**

**What it does**: Identifies records where a `MPatID` (mother) exists but no `CPatID` (child) is linked. Flags mothers in the MIL table who have no associated infant record.

**Condition**: `missing(Cpatid) and not missing(mpatid)`

**Flag Description**: "MPatID not linked to CPatID"

**Message**: "MPatid ({mpatid}), EncounterID ({encounterid}), Adate ({adate}): No linkage to infant was found; confirmation required"

**Output Dataset**: `dplocal.flag_l3_396_{TABID}`

**Source Code**:
```sas
proc sql;
  create table %str(dplocal.flag_l3_396_&tabid.) as
  select cats("%upcase(&tabid.)_",&level.,"_00_00-0_396") as flagid length =21
       , cat("MPatid (",mpatid,"), EncounterID (", Encounterid,"), Adate (",put(adate, mmddyy10.),
         "): No linkage to infant was found; confirmation required")
         as message length = 300
       , cat("MPatID not linked to CPatID") as flag_descr length = 255
       , "Warn" as Flagtype length = 4
       , "N" as abortyn length = 1
       , count(*) as count
  from qadata.&&&tabid.table
  where missing(Cpatid) and not missing(mpatid)
  group by calculated flagid, calculated message, calculated flag_descr, flagtype, calculated abortyn
  ;
quit;
```

---

### Check 397: Infant Not Linked to Mother

**Lines 197-213**

**What it does**: Identifies records where a `CPatID` (child/infant) exists but no `MPatID` (mother) is linked. Flags infants in the MIL table who have no associated mother record.

**Condition**: `not missing(Cpatid) and missing(mpatid)`

**Flag Description**: "CPatID not linked to MPatID"

**Message**: "CPatid ({cpatid}), CBirth_Date ({cbirth_date}): No linkage to mother/delivery was found; confirmation required"

**Output Dataset**: `dplocal.flag_l3_397_{TABID}`

**Source Code**:
```sas
proc sql;
  create table %str(dplocal.flag_l3_397_&tabid.) as
  select cats("%upcase(&tabid.)_",&level.,"_00_00-0_397") as flagid length =21
       , cat("CPatid (",Cpatid,"), CBirth_Date (",put(CBirth_Date, mmddyy10.),
         "): No linkage to mother/delivery was found; confirmation required")
         as message length = 300
       , cat("CPatID not linked to MPatID") as flag_descr length = 255
       , "Warn" as Flagtype length = 4
       , "N" as abortyn length = 1
       , count(*) as count
  from qadata.&&&tabid.table
  where not missing(Cpatid) and missing(mpatid)
  group by calculated flagid, calculated message, calculated flag_descr, flagtype, calculated abortyn
  ;
quit;
```

---

## Observations

- **No check 370** exists. The 371-375 range is generated dynamically from the birth_types list `(1 2 3 4 5)`.
- **Gap between 375 and 394**: Check numbers 376-393 are not implemented in this package.
- **Check 395 does not exist** in this codebase.
- All checks run against every table in `msoc.control_flow_3` where `cc_table ne 'X'`.
- Output datasets follow the naming convention `dplocal.flag_l3_{checknum}_{TABID}`.
- The `lkp_all_flags.sas7bdat` lookup table likely contains flag definitions for these checks but is a binary SAS dataset and cannot be read as text.
