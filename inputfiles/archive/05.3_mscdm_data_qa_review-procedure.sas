/*-------------------------------------------------------------------------------------*\
|  PROGRAM NAME:                                                                        |
|     05.3-mscdm-data-qa-review-procedure.sas                                           |
|                                                                                       |
|  QA PACKAGE VERSION: 4.0.3                                                            |                                                                   |
|---------------------------------------------------------------------------------------|
|  PURPOSE:                                                                             |
|     The purpose of this program is to perform data quality checks on the Procedure    |
|     table.                                                                            |
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
%let level=2;

proc sql noprint;
  create table dplocal.temp as
  select *
       , count(*) as n 
  from mscdm.&table. (keep=adate enctype px px_codetype)
  group by 1,2,3,4
  ;
quit;
%remove_labels(dplocal, temp);

proc sql noprint;
/* list freq of px*px_codetype */
  create table msoc.&tabid._l2_px_pxtype as
  select px label=' '
       , px_codetype label=' '
       , sum(n) as count format=comma15.
  from dplocal.temp (keep=px px_codetype n) 
  group by 1,2  
  ;
quit;

/*-------------------------------------------------------------------------------------*/
/*  START Level 2 Flags                                                                */
/*-------------------------------------------------------------------------------------*/
%level2;

/*-------------------------------------------------------------------------------------*/
/*  START Level 3                                                                      */
/*-------------------------------------------------------------------------------------*/
%let level=3;

proc sql noprint;
  create table dplocal.temp_dates as
  select adate
       , sum(n) as n
  from dplocal.temp (keep=adate n)
  group by 1
  ;
quit;
%date_percentiles (libin=dplocal, dsin=temp_dates, libout=dplocal, dsout=date_dist_&tabid., vars=adate);

proc sql noprint;
  drop table dplocal.temp_dates
  ;
  create table msoc.&tabid._l3_enctype_pxtype_ym as
  select put(adate,yymmd.) as YearMonth
       , enctype label=' '
       , px_codetype label=' '
       , count(*) as count format=comma15.
  from dplocal.temp (keep=adate enctype px_codetype)
  group by 1,2,3
  ;
  drop table dplocal.temp
  ;
quit;

/* patid*encounterid (number of procedures per patient-encounter - unique by px_codetype and px) */
proc sql noprint;
  create table dplocal.&tabid._n_patid_encid as
  select patid, encounterid, count(*) as n
  from mscdm.&table. (keep=patid encounterid)
  group by 1,2
  ;
quit;

*level 3 < statistics on number of procedures per encounter visit: overall >;
%l2_procmeans_sum(libin=dplocal,dsin=&tabid._n_patid_encid,
                  libout=msoc,  dsout=&tabid._l3_px_per_enc_stats,
                  keepvars=, vars=n, classvars=,
                  names= n=enc sum=pxs mean=mean std=std min=min p1=p1 p5=p5 p25=p25 median=median p75=p75 p95=p95 p99=p99 max=max,
                  numobs=max);

proc datasets lib=dplocal nowarn nolist nodetails;
  delete &tabid._n_patid_encid;
quit;

proc datasets library=msoc nolist nodetails nowarn;
  modify &tabid._l3_px_per_enc_stats;
  format enc pxs comma15. mean std 10.2 median 10.1;
  informat mean std 10.2 median 10.1;
run;
quit;

%timestamp(&tabid._end);
%timereport(&&&tabid._start,&&&tabid._end);

*-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-;
*  END 05.3-mscdm-data-qa-review-procedure.sas                                          ; 
*-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-;
