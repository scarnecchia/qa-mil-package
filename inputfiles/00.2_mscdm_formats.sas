/*-------------------------------------------------------------------------------------*\
|  PROGRAM NAME:                                                                        |
|     00.2_mscdm_formats.sas                                                            |
|                                                                                       |
|  QA PACKAGE VERSION: 4.0.3                                                            |
|---------------------------------------------------------------------------------------|
|  PURPOSE:                                                                             |
|     The purpose of the program is to store file formats of variables.                 |
|                                                                                       |
|---------------------------------------------------------------------------------------|
|  PROGRAM INPUT:                                                                       |
|     see 00.0_mscdm_data_qa_review_master_file.sas                                     |
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
%macro create_l1_formats;
  proc sql noprint;
    create table temp as
    select monotonic ( ) as row, max(varlength) as length, * from infolder.lkp_all_l1 (where=(validvaluetype="list_values"))
    where lowcase(variable) ne "ms_result_c"
    ;
  quit;
  %let rowct=&sqlobs.;

  %do i=1 %to &rowct.;
    proc sql;
      select countw(validvalue,'|'), length into :varct trimmed, :length trimmed
      from temp
      where row=&i.
      ;
    quit;

    data temp_&i. (keep=fmtname start); 
      length fmtname $25 start $&length.;      
      set temp (where=(row=&i.));
      start= ' '; 
      fmtname=lowcase(compress('$'||tabid||variable)); 
      output;
      ct+1;
      ct=1;
      do while (ct le &varct.);
        start=scan(validvalue,ct,'|'); 
        fmtname=lowcase(compress('$'||tabid||variable)); 
        output;
        ct+1;
      end;
    run;
  %end;

  data formats;
    set temp_:;
    label='*';
  run;

  proc datasets lib=work;
    delete temp:;
  quit;

  proc format library=dplocal cntlin=formats;
  run; 

%mend;
%create_l1_formats;

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
  value $enr_overlap
  'D'='Duplicate'
  'O'='Overlap'
  'S'='Subset'
  ;
run;

*-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-;
*  End 00.2_mscdm_formats.sas                                                           ;
*-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-;
