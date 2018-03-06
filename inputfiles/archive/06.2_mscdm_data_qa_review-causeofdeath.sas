/*-------------------------------------------------------------------------------------*\
|  PROGRAM NAME:                                                                        |
|     06.2_mscdm_data_qa_review-causeofdeath.sas                                        |
|                                                                                       |
|  QA PACKAGE VERSION: 4.0.3                                                            |                                                                    |
|---------------------------------------------------------------------------------------|
|  PURPOSE:                                                                             |
|     The purpose of this program is to perform data quality checks on the Cause of     |
|     Death table.                                                                      |
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
%table_name (n=);
%timestamp(&tabid._start);

/*-------------------------------------------------------------------------------------*/
/*  START Level 2                                                                      */
/*-------------------------------------------------------------------------------------*/
%level2;


/*-------------------------------------------------------------------------------------*/
/*  START Level 3 Datasets                                                             */
/*-------------------------------------------------------------------------------------*/
proc sql noprint;
  create table msoc.&tabid._l3_catvars as
  select *, count(*) as count format=comma15.
  from mscdm.&table. (keep=causetype source confidence)
  group by causetype, source, confidence
  ;
quit;
%remove_labels(msoc,&tabid._l3_catvars)

%timestamp(&tabid._end);
%timereport(&&&tabid._start,&&&tabid._end);

*-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-;
*  END 6.2_mscdm_data_qa_review-causeofdeath.sas                                        ;
*-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-;
