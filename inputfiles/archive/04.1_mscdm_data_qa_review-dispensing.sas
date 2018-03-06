/*-------------------------------------------------------------------------------------*\
|  PROGRAM NAME:                                                                        |
|     04.1-mscdm-data-qa-review-dispensing.sas                                          |
|                                                                                       |
|  QA PACKAGE VERSION: 4.0.3                                                            |
|---------------------------------------------------------------------------------------|
|  PURPOSE:                                                                             |
|     The purpose of this program is to perform data quality checks on the Dispensing   |
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
* list of NDCs without # of record;
proc sql;
  create table dplocal.temp as
  select rxdate 
       , ndc
       , count(*) as n
  from mscdm.&table. (keep=rxdate ndc)
  group by 1,2
  ;
  create table msoc.&tabid._l2_ndc as
  select distinct ndc label=' '
  from dplocal.temp (keep=ndc)
  ;
quit;
%remove_labels(dplocal, temp);

/*-------------------------------------------------------------------------------------*/
/*  START Level 2 Flags                                                                */
/*-------------------------------------------------------------------------------------*/;
%level2;


/*-------------------------------------------------------------------------------------*/
/*  START Level 3                                                                      */
/*-------------------------------------------------------------------------------------*/
%let level=3;
proc sql noprint;
  create table dplocal.temp_dates as
  select rxdate
       , sum(n) as n
  from dplocal.temp (keep=rxdate n)
  group by 1
  ;
quit;

%date_percentiles (libin=dplocal, dsin=temp_dates, libout=dplocal, dsout=date_dist_&tabid., vars=rxdate);

proc sql noprint;
  drop table dplocal.temp_dates, dplocal.temp
  ;
* list of patids-rxdate with # of records;
  create table dplocal.temp as
  select patid
       , put(rxdate,yymmd.) as YearMonth
       , count(*) as n
  from mscdm.&table. (keep=patid rxdate)
  group by 1,2
  ;
quit;
%remove_labels(dplocal, temp);

proc sql noprint;
  /* < distribution of rx per year-month > */
  create table msoc.&tabid._l3_rxdate_ym as
  select yearmonth
       , sum(n) as count format=comma15.
  from dplocal.temp (keep=yearmonth n)
  group by 1
  ;
/* < number of prescriptions per patid per year > */
  create table dplocal.temp1 as
  select patid
       , substr(Yearmonth,1,4) as Year
       , sum(n) as n
  from dplocal.temp
  group by 1,2
  ;
  drop table dplocal.temp
  ;
quit;

/*< Distribution of number of prescriptions per patid per year > */
proc means nolabels nonobs data=dplocal.temp1 missing StackODSOutput n sum mean std min p1 P5 P25 median P75 P95 p99 max; 
  var n;
  class year;
  ods output summary=msoc.&tabid._l3_rx_pt_y_stats (drop=_: variable rename=(n=n_ptyr sum=n_rx stddev=Std));
run;

proc datasets library=msoc nolist nodetails nowarn;
  modify &tabid._l3_rx_pt_y_stats;
  format n_: comma15. mean std 10.2 p: min max median 10.1;
  informat mean std 10.2 p: min max median 10.1;
quit;

proc datasets lib=dplocal memtype=data nolist nodetails nowarn;
  delete temp1;
quit;

proc sql noprint;
  create table dplocal.temp_rx as 
  select rxsup label=' '
       , rxamt label=' '
       , count(*) as n
  from mscdm.&table. (keep=rxsup rxamt)
  group by 1,2
  ; 
* list of rxsups with # of record;
  create table msoc.&tabid._l3_rxsup as
  select rxsup
       , sum(n) as count format=comma15.
  from dplocal.temp_rx (keep=rxsup n)
  group by 1
 ;
* list of rxamts with # of record;
  create table msoc.&tabid._l3_rxamt as
  select rxamt
       , sum(n) as count format=comma15.
  from dplocal.temp_rx (keep=rxamt n)
  group by 1
  ;
  drop table dplocal.temp_rx
  ;
quit;


%timestamp(&tabid._end);
%timereport(&&&tabid._start,&&&tabid._end);

*-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-;
*  END 04.1-mscdm-data-qa-review-dispensing.sas                                         ; 
*-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-;
