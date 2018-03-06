/*-------------------------------------------------------------------------------------*\
|  PROGRAM NAME:                                                                        |
|     05.2_mscdm_data_qa_review-diagnosis.sas                                           |
|                                                                                       |
|  QA PACKAGE VERSION: 4.0.3                                                            |
|---------------------------------------------------------------------------------------|
|  PURPOSE:                                                                             |
|     The purpose of this program is to perform data quality checks on the Diagnosis    |
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
/*try to optimize -- test count vs. no count */
proc sql noprint;
  create table dplocal.temp as
  select *
  from mscdm.&table. (keep=adate dx dx_codetype enctype padmit pdx)
  ;
quit;
%remove_labels(dplocal, temp);

/*-------------------------------------------------------------------------------------*/
/*  START Level 2 Data                                                                 */
/*-------------------------------------------------------------------------------------*/
proc sql noprint;
/* list freq of dx*dx_codetype */
  create table msoc.&tabid._l2_dx_dxtype as
  select *
       , count(*) as count format=comma15.
  from dplocal.temp (keep=dx dx_codetype)
  group by dx, dx_codetype
  ;
  create table msoc.&tabid._l2_enc_dxtype_pdx_ym as
  select put(adate,yymmd.) as YearMonth
       , enctype
       , dx_codetype
       , pdx
       , count(*) as count format=comma15.
  from dplocal.temp (keep=adate enctype dx_codetype pdx)
  group by 1,2,3,4
  ;
quit;

/*-------------------------------------------------------------------------------------*/
/*  START Level 2 Flags                                                                */
/*-------------------------------------------------------------------------------------*/
%level2;


/*-------------------------------------------------------------------------------------*/
/*  START Level 3 Data                                                                 */
/*-------------------------------------------------------------------------------------*/
%let level=3;

proc sql noprint;
  create table dplocal.temp_dates as
  select adate
       , count(*) as n
  from dplocal.temp (keep=adate)
  group by 1
  ;
quit;

%date_percentiles (libin=dplocal, dsin=temp_dates, libout=dplocal, dsout=date_dist_&tabid., vars=adate);

proc sql noprint;
  drop table dplocal.temp_dates
  ;
/* padmit only: list of padmit with # of records */
  create table msoc.&tabid._l3_padmit as
  select padmit 
       , count(*) as count format=comma15.
  from dplocal.temp (keep=padmit)
  group by 1
  ;
  drop table dplocal.temp
  ;
/* patid*encounterid (number of diagnosis per patient-encounter - not necessarily unique) */
  create table dplocal.&tabid._n_patid_encid as
  select patid, encounterid, count(*) as n
  from mscdm.&table. (keep=patid encounterid)
  group by 1,2
  ;
quit;

*level 3 < statistics on number of diagnosis per encounter visit: overall >;
%l2_procmeans_sum(libin=dplocal,dsin=&tabid._n_patid_encid,
                  libout=msoc,  dsout=&tabid._l3_dx_per_enc_stats,
                  keepvars=, vars=n, classvars=,
                  names= n=enc sum=dxs mean=mean std=std min=min p1=p1 p5=p5 p25=p25 median=median p75=p75 p95=p95 p99=p99 max=max,
                  numobs=max);

proc datasets library=msoc nolist nodetails nowarn;
  modify &tabid._l3_dx_per_enc_stats;
  format enc dxs comma15. mean std 10.2  median 10.1;
  informat mean std 10.2  median 10.1;
run;
quit;

proc datasets lib=dplocal nowarn nolist nodetails;
  delete &tabid._n_patid_encid;
quit;

%timestamp(&tabid._end);
%timereport(&&&tabid._start,&&&tabid._end);

*-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-;
*  END 05.2_mscdm_data_qa_review-diagnosis.sas                                          ;
*-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-;
