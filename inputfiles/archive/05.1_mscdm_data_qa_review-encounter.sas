/*-------------------------------------------------------------------------------------*\
|  PROGRAM NAME:                                                                        |
|     05.1_mscdm_data_qa_review-encounter.sas                                           |
|                                                                                       |
|  QA PACKAGE VERSION: 4.0.3                                                            |
|---------------------------------------------------------------------------------------|
|  PURPOSE:                                                                             |
|     The purpose of this program is to perform data quality checks on the              |
|              Encounter table.                                                         |
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
/*  START Level 2 Data                                                                 */
/*-------------------------------------------------------------------------------------*/
proc sql noprint;
  create table msoc.&tabid._l2_enctype_admit_dc as
  select enctype
       , admitting_source
       , discharge_disposition
       , discharge_status
       , count(*) as count format=comma15.
  from mscdm.&table. (keep=enctype admitting_source discharge_disposition discharge_status)
  group by 1,2,3,4
  ;
  create table dplocal.l2_temp as
  select enctype
       , adate
       , ddate
       , drg
       , drg_type
       , count(*) as n
  from mscdm.&table. (keep=enctype adate ddate drg drg_type)
  group by 1,2,3,4,5
  ;
quit;
%remove_labels(msoc,&tabid._l2_enctype_admit_dc);
%remove_labels(dplocal,l2_temp);

proc sql noprint;
  create table dplocal.&tabid._enctype_dates as
  select enctype, adate, ddate
       , sum(n) as n 
  from dplocal.l2_temp (keep=enctype adate ddate n)
  group by 1,2,3
  ;
  create table dplocal.&tabid._enctype_drg (rename=(_adate=adate)) as
  select enctype
       , put(adate,yymmd.) as YearMonth
       , drg
       , drg_type
       , case when . lt adate lt '01oct2007'd then '30sep2007'd 
              when adate ge '01oct2007'd then '01oct2007'd
              else .
         end as _adate
       , sum(n) as count format=comma15.
  from dplocal.l2_temp (keep=enctype adate drg drg_type n)
  group by 1,2,3,4,5
  ;
  drop table dplocal.l2_temp
;
quit;

proc sql noprint;
  create table msoc.&tabid._l2_enctype_drg_drgtype as
  select enctype, drg, drg_type, sum(count) as count format=comma15.
  from dplocal.&tabid._enctype_drg (drop=yearmonth)
  group by 1,2,3
  ;
  create table msoc.&tabid._l2_enctype_drgtype_ym as
  select enctype, drg_type label=' ', yearmonth, sum(count) as count format=comma15.
  from dplocal.&tabid._enctype_drg (keep=yearmonth enctype drg_type count)
  group by 1,2,3
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
  create table dplocal.temp_adate as
  select adate
       , sum(n) as n
  from dplocal.&tabid._enctype_dates (keep=adate n)
  group by 1
  ;
quit;
%date_percentiles (libin=dplocal, dsin=temp_adate, libout=dplocal, dsout=temp_date_dist_&tabid._1, vars=adate);

proc sql noprint;
  drop table dplocal.temp_adate
  ;
  create table dplocal.temp_ddate as
  select ddate
       , sum(n) as n
  from dplocal.&tabid._enctype_dates (keep=ddate n)
  group by 1
  ;
quit;
%date_percentiles (libin=dplocal, dsin=temp_ddate, libout=dplocal, dsout=temp_date_dist_&tabid._2, vars=ddate);
%set_ds (libin=dplocal, dsin_prefix=temp_date_dist_&tabid., libout=dplocal, dsout=date_dist_&tabid.);

proc sql noprint;
  drop table dplocal.temp_ddate
  ;
 /* <create table msoc.enc_l3_enctype_ddate_ym> */
  create table msoc.&tabid._l3_enctype_ddate_ym as
  select enctype
       , put(ddate,yymmd.) as YearMonth
       , sum(n) as count format=comma15.
  from dplocal.&tabid._enctype_dates (drop=adate)
  group by 1,2
  ;
/* <create table msoc.&tabid._l3_enctype_los_ym> */
  create table msoc.&tabid._l3_enctype_los_ym as
  select enctype
       , put(adate,yymmd.) as YearMonth
       , case when ddate ne . then ddate-adate+1
              else .
         end as LOS label="Length of Stay"
       , sum(n) as count format=comma15.
  from dplocal.&tabid._enctype_dates
  group by 1,2,3
  ;
  drop table dplocal.&tabid._enctype_dates
  ;
quit;

proc sql noprint;
/* <create table msoc.enc_l3_enctype_adate_ym> */
  create table msoc.&tabid._l3_enctype_adate_ym as
  select enctype
       , yearmonth
       , sum(count) as count format=comma15.
  from dplocal.&tabid._enctype_drg (keep=enctype yearmonth count)
  group by 1,2
  ;
/* <create table msoc.&tabid._l3_drg_type_y> */
  create table msoc.&tabid._l3_drgtype_y as
  select drg_type
       , substr(yearmonth,1,4) as Year
       , sum(count) as count format=comma15.
  from dplocal.&tabid._enctype_drg (drop=drg adate)
  group by 1,2
  ;
  drop table dplocal.&tabid._enctype_drg
  ;
quit;

proc sql noprint;
/* <create table msoc.&tabid._l3_facloc> */
  create table msoc.&tabid._l3_facloc as
  select facility_location label=' ', count(*) as count format=comma15.
  from mscdm.&table. (keep=facility_location)
  group by 1
  ;
/* <create table msoc.&tabid._l3_enctype_los> */
  create table msoc.&tabid._l3_enctype_los as
  select enctype
       , los
       , sum(count) as count format=comma15.
  from msoc.&tabid._l3_enctype_los_ym (drop=yearmonth)
  group by 1,2
  ;
quit;

proc sql noprint;
  create table dplocal.&tabid._for_enc as
  select patid
       , encounterid
       , enctype
       , put(adate,yymmd.) as YearMonth
       , count(*) as n
  from mscdm.&table. (keep=patid encounterid enctype adate)
  group by 1,2,3,4
  ;
quit;
%remove_labels(dplocal,&tabid._for_enc);

/* number of encounters per member by enctype by year-month */
proc sql noprint;
  create table dplocal.&tabid._enc_pat_ym as
  select patid, enctype, yearmonth, sum(n) as n
  from dplocal.&tabid._for_enc 
  group by 1,2,3
  ; 
  drop table dplocal.&tabid._for_enc
  ;
quit;

/*level 3 <number of encounters per member by enctype by year-month (mean, median, min, max) */
%l2_procmeans_sum (libin=dplocal,
                   dsin=&tabid._enc_pat_ym,
                   libout=msoc,   
                   dsout=&tabid._l3_enctype_pt_ym_stats,
                   keepvars=,
                   vars=n,
                   classvars=enctype yearmonth,
                   names=n=members sum=records mean=mean std=std min=min p1=p1 p5=p5 p25=p25 median=median p75=p75 p95=p95 p99=p99 max=max,
                   numobs=max);
                 
/* number of encounters per member by year-month */                 
proc sql noprint;
  create table dplocal.&tabid._pat_ym as
  select patid, yearmonth, sum(n) as n
  from dplocal.&tabid._enc_pat_ym
  group by 1,2
  ;
  drop table dplocal.&tabid._enc_pat_ym
  ;
  quit;
  
/*level 3 <number of encounters per member by year-month (mean, median, min, max)*/
%l2_procmeans_sum (libin=dplocal,
                   dsin=&tabid._pat_ym,
                   libout=msoc,
                   dsout=&tabid._l3_pt_ym_stats,
                   keepvars=,
                   vars=n,
                   classvars=yearmonth,
                   names=n=members sum=records mean=mean std=std min=min p1=p1 p5=p5 p25=p25 median=median p75=p75 p95=p95 p99=p99 max=max,
                   numobs=max);
                   
proc datasets lib=dplocal nowarn nolist nodetails;
  delete &tabid._pat_ym;
quit;

proc datasets library=msoc nolist nodetails nowarn;
  modify &tabid._l3_enctype_pt_ym_stats;
  format members records comma15. mean std 10.2 median 10.1;
  informat mean std 10.2 median 10.1;
  run;
  modify &tabid._l3_pt_ym_stats;
  format members records comma15. mean std 10.2 median 10.1;
  informat mean std 10.2 median 10.1;
  run;
quit;


%timestamp(&tabid._end);
%timereport(&&&tabid._start,&&&tabid._end);

*-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-;
*  END 05.1_mscdm_data_qa_review-encounter.sas                                          ;
*-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-;
