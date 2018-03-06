/*-------------------------------------------------------------------------------------*\
|  PROGRAM NAME:                                                                        |
|     06.1_mscdm_data_qa_review-death.sas                                               |
|                                                                                       |
|  QA PACKAGE VERSION: 4.0.3                                                            |
|---------------------------------------------------------------------------------------|
|  PURPOSE:                                                                             |
|     The purpose of this program is to perform data quality checks on the Death table. |
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
/*  START Level 2 Flags                                                                */
/*-------------------------------------------------------------------------------------*/
%level2;

/*-------------------------------------------------------------------------------------*/
/*  START Level 3                                                                      */
/*-------------------------------------------------------------------------------------*/

proc sql noprint;
  create table dplocal.temp as 
  select deathdt
       , count(*) as n
  from mscdm.&table.
  group by 1
  ;
quit;

%date_percentiles (libin=dplocal, dsin=temp, libout=dplocal, dsout=date_dist_&tabid., vars=deathdt);

proc sql noprint;
*level 3 < distribution of deaths per deathdt per year-month >;
  create table msoc.&tabid._l3_dthdt_ym as
  select put(deathdt,yymmd.) as YearMonth length=7
       , sum(n) as count format=comma15.
  from dplocal.temp
  group by yearmonth
  ;
  drop table dplocal.temp
  ;
  create table msoc.&tabid._l3_catvars as
  select *, count(*) as count format=comma15.
  from mscdm.&table (keep=dtimpute source confidence)
  group by dtimpute, source, confidence
  ;
quit;

%timestamp(&tabid._end);
%timereport(&&&tabid._start,&&&tabid._end);

*-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-;
*  END 6.1_mscdm_data_qa_review-death.sas                                               ;
*-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-;
