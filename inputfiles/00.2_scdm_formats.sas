/*-------------------------------------------------------------------------------------*\
|  PROGRAM NAME:                                                                        |
|     00.2_scdm_formats                                                                 |
|---------------------------------------------------------------------------------------|
|  PURPOSE:                                                                             |
|     The purpose of the program is to store file formats of variables.                 |
|                                                                                       |
|---------------------------------------------------------------------------------------|
|  PROGRAM INPUT:                                                                       |
|     see 00.0_scdm_data_mil_qa_review_master_file.sas                                  |
|                                                                                       |
|  PROGRAM OUTPUT:                                                                      |
|     see Workplan PDF                                                                  |
|---------------------------------------------------------------------------------------|
|  CONTACT:                                                                             |
|     Sentinel Coordinating Center                                                      |
|     info@sentinelsystem.org                                                           |
\*-------------------------------------------------------------------------------------*/

*-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-;
*  PLEASE DO NOT EDIT BELOW WITHOUT CONTACTING THE SENTINEL OPERATIONS CENTER           ;
*-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-;
proc format library=dplocal;
  value agecat_years
  .       = "00. Missing"
  low-<0  = "00. Negative"
  0-<2    = "01. 0-1 yrs"
  2-<5    = "02. 2-4 yrs"
  5-<10   = "03. 5-9 yrs"
  10-<15  = "04. 10-14 yrs"
  15-<19  = "05. 15-18 yrs"
  19-<22  = "06. 19-21 yrs"
  22-<45  = "07. 22-44 yrs"
  45-<65  = "08. 45-64 yrs"
  65-<75  = "09. 65-74 yrs"
  75-high = "10. 75+ yrs"
  ;
  value agecat_days
  .        = "00. Missing"
  low-<0   = "01. < 0 days"
  0-30     = "02. 0-30 days"
  31-60    = "03. 31-60 days"
  61-120   = "04. 61-120 days"
  121-180  = "05. 121-180 days"
  181-270  = "06. 181-270 days"
  271-365  = "07. 271-365 days" 
  366-high = "08. >= 366 days"
  ;
  value $enr_overlap
  'D'='Duplicate'
  'O'='Overlap'
  'S'='Subset'
  ;
run;

/*format for daysdiff*/
proc format library = dplocal;
  value daysfmt
  low--31 = "00:< -30 days"
  -30--11 = "01:-11 through -30 days"
  -10--4 = "02:-4 through -10 days"
  -3--1 = "03:-1 through -3 days"
  0 = "04:0 days"
    1-3 = "05:1 through 3 days"
    4-10 = "06:4 through 10 days"
    11-30 = "07:11 through 30 days"
  31-high = "08:> 30 days";

  value type1fmt
   1 = "MatchMethod"
   2 = "DaysDiff"
   4 = "sex"
   8 = "EncType"
   16 = "AgeGroup"
   32 = "ICD_Ver"
   64 = "YearMonth"
   128 = "Year"
   256 = "Birth_Type"
   512 = "LinkageStatus";

   value type2fmt
   1 = "InfantsLinked"
   2 = "EncType"
   4 = "AgeGroup"
   8 = "ICD_Ver"
   16 = "YearMonth"
   32 = "Year"
   64 = "Birth_Type"
   128 = "LinkageStatus";

run;

*-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-;
*  End 00.2_scdm_formats.sas                                                            ;
*-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-;
