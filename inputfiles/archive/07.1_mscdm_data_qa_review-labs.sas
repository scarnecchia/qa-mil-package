/*-------------------------------------------------------------------------------------*\
|  PROGRAM NAME:                                                                        |
|     07.1_mscdm_data_qa_review-labs.sas                                                |
|                                                                                       |
|  QA PACKAGE VERSION: 4.0.3                                                            |
|---------------------------------------------------------------------------------------|
|  PURPOSE:                                                                             |
|     The purpose of this program is to perform general Laboratory Result table data    |
|     checks and gather information on data characteristics by resulted lab test.       |
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

/**********************************************************************************/
/* Define hierachy for Laboratory Result Table date selection                     */
/*   Default order of preference: 1-lab_dt 2-result_dt 3-order_dt                 */
/**********************************************************************************/
%let LRT_DT=lab result order;

/*--------------------------------------------------------------------------------*/
/* LEVEL 2 TABLE AND FLAG CREATION                                                */                                              
/*--------------------------------------------------------------------------------*/

/*--------------------------------------------------------------------------------*\
  * Establish a temporary subset of SCDM LAB variables to work with or review 
  * Merge with infolder.lkp_lab_test to assign TestNum and TestID            
  * Create derived variable TestDate based on 3 date fields using the hierarchy 
     defined at the start of the module                               
\*--------------------------------------------------------------------------------*/
%macro date_order (order=%bquote(&lrt_dt.));
  option missing=' '; 
  proc sql noprint;
    create table dplocal._&tabid. as
    select b.testnum
         , b.testid
         , a.*
  %do i=1 %to 3 ;
    %let date=%sysfunc(upcase(%scan(&order, &i.)));
    %let date&i.=%scan(&order., &i.);
        , &date._dt as &date._ym label="&date. Year and Month" format=yymon7. length=4
  %end;
        , case
  %do j=1 %to 3;
    %let date=%scan(&order, &j.);
          when &date._dt ne . then &date._dt 
  %end;
          else .
          end as TestDate format=mmddyy10. length=4 label="Test Date"
    from mscdm.&table. (keep=patid ms_test_name result_type ms_test_sub_category fast_ind 
                             specimen_source pt_loc loinc &date1._dt &date2._dt &date3._dt lab_tm result_tm facility_code order_dept) as a
       left join infolder.lkp_&tabid._test (keep=ms_test_name result_type testnum testid) as b
    on a.ms_test_name=b.ms_test_name and a.result_type=b.result_type
    ;
    create table dplocal.&tabid._testdates_ym as
    select put(testdate,yymmd.) as YearMonth
         , count(*) as count format=comma15.
    from dplocal._&tabid. (keep=testdate)
    group by 1
    ;
  quit;
  option missing=.;
%mend;
%date_order;  /* default hierarchy = Lab Result Order */

%flag_200;

 
/* Create dplocal.lab_pattest_count with frequency of records per unique patid*ms_test_name */
proc sql noprint;
  create table dplocal.lab_pattest_count as
  select patid label=' '
       , ms_test_name label=' '
       , result_type label=' '
       , count(*) as Lab label="Record Count" format=comma15.
  from dplocal._&tabid. (keep=patid ms_test_name result_type)
  group by 1,2,3
  ;
quit;

%macro l2_ds_lab_rec_count (dsout=, varlist=);
  %let nvar=%sysfunc(countw(&varlist., ' '));
  %do l=1 %to &nvar.;
    %let var&l=%scan(&varlist.,&l.);
  %end;
  %let _varlist = %sysfunc(strip(&var1.));
  %do j=2 %to &nvar.;
    %let _varlist = %bquote(&_varlist.%str(, )%sysfunc(strip(&&var&j)));
  %end; 

  proc sql noprint;
    create table msoc.&tabid._l2_&dsout. as
    select ms_test_name
         , result_type
         , ms_test_sub_category 
         , fast_ind
         , specimen_source
         , &_varlist.
         , count(*) as count format=comma15.
    from mscdm.&table. (keep=ms_test_name result_type ms_test_sub_category fast_ind specimen_source &varlist.)
    group by 1,2,3,4,5,&_varlist.
    ;
  quit;
  %remove_labels(msoc,&tabid._l2_&dsout.);
%mend l2_ds_lab_rec_count;

/* Create msoc.lab_l2_record_count*/
%l2_ds_lab_rec_count (dsout=record_count, varlist=loinc);

/* Create msoc.lab_l2_test_units*/
%l2_ds_lab_rec_count (dsout=test_units, varlist=Orig_result_unit std_result_unit ms_result_unit);

/**********************************************************************************/
/* Create msoc.lab_l2_ms_result*/
%l2_ds_lab_rec_count (dsout=temp_ms_result, varlist=loinc orig_result ms_result_c modifier ms_result_n ms_result_unit);

/*create list of all testnum for numeric tests that only have one result_type*/
proc sql noprint; 
  select quote(ms_test_name) into :testlist separated by ',' 
  from (select count(distinct result_type) as typect, testnum, ms_test_name, result_type
  from infolder.lkp_lab_test (where=(characterized='Y'))
  group by testnum, ms_test_name        
  having calculated typect=1)
  where result_type='N'
  ;
quit;

*Remove records for numeric tests with character results due to ranges (e.g. 10|50 MG/DL);
data msoc.lab_l2_ms_result msoc.lab_l2_ms_result_x;
  set msoc.lab_l2_temp_ms_result;
  if result_type = 'N' then output msoc.lab_l2_ms_result;
  else if ms_test_name in (&testlist.) and result_type = 'C' then output msoc.lab_l2_ms_result_x;
  else output msoc.lab_l2_ms_result;
run;

proc datasets lib=msoc nolist nowarn nodetails;
  delete lab_l2_temp_ms_result;
quit;

/**********************************************************************************/
/* Create dplocal.flag_LAB_2_02_xxx_210 */
/* Flag LAB_2_02_xx-x_210: Check for MS_Test_Name values with 0 observations */
proc sql noprint;
  create table dplocal.flag_&tabid._2_02_xxx_210 as
  select strip(upcase("&tabid._2_02_"||testid||"_210")) as FlagID length=21
       , b.ms_test_name     
       , 99999 as count
  from (select * from infolder.lkp_&tabid._test except corr select distinct ms_test_name, result_type from dplocal._&tabid.) as a 
    left join infolder.lkp_&tabid._test (keep=ms_test_name result_type testid) as b
    on a.ms_test_name=b.ms_test_name and a.result_type=b.result_type
  order by flagid
  ;
  create table work.flag_210 as
  select flagid
       , count
  from dplocal.flag_&tabid._2_02_xxx_210
  ;
quit;


/**********************************************************************************/
/* Create Level 2 flags for invalid Result_type based on MS_test_name (CheckID=222) */
%macro flag_222 (checkid=222);
  proc sql noprint;
    create table temp_flags as
    select ms_test_name
         , flagid
         , dataset
         , flag_descr
    from infolder.lkp_all_flags (where=(lowcase(tableid)="&tabid" and checkid="&checkid."))
    ;
  quit;

  %if &sqlobs. gt 0 %then %do;
    proc sql noprint;
      select distinct dataset into :dataset trimmed
      from temp_flags
      ;
    quit;

    proc contents data=&dataset. out=proctemp (keep=name nobs);
    run;

    %let temp_nobs=0;
    proc sql noprint;
      select distinct nobs into :temp_nobs trimmed
      from proctemp
      ;
      drop table proctemp
      ;
    quit;

    %if %eval(&temp_nobs. gt 0) %then %do;
      proc sql noprint;
        create table flag_222 as
        select b.flagid
             , sum(count) as count format=comma15.
        from &dataset. as a left join temp_flags as b
        on lowcase(a.ms_test_name)=lowcase(b.ms_test_name)
        where ms_result_n ne . or ms_result_unit ne ' ' or 
                    modifier ne 'TX'
        group by 1
        ;
      quit;
    %end;
  %end;
%mend;
%flag_222;

%macro lab_flag (checkid=);
  proc sql noprint;
    create table temp_l2_flags as
    select *
    from infolder.lkp_all_flags (where=(lowcase(tableid)=lowcase("&tabid") and checkid="&checkid."))
    ;
  quit;
  %str(%flag_&checkid.);
%mend;

%lab_flag (checkid=226);
%lab_flag (checkid=227);


/**********************************************************************************/
/* Macro to create Level 2 flags for 3-variable cross-checks (checkid=23x, except 232)  */
%macro l2_flags_var3 (checkid=, where=);  
  proc sql noprint;
    select distinct varid
         , variable1
         , variable2
         , variable3
         , dataset
    into :varidlist separated by "~"
       , :var1list separated by "~"
       , :var2list separated by "~"
       , :var3list separated by "~"
       , :dslist separated by "~"
    from infolder.lkp_all_flags (where=(lowcase(tableid)=lowcase("&tabid.") and checkid="&checkid."))
    ;
  quit;
  %let varct=%sysfunc(countw(&varidlist.,~));
  %if &varct ge 1 %then %do;
    %do v=1 %to &varct.;
      %let varid=%qscan(%bquote(&varidlist.),&v.,~);
      %let var1=%scan(&var1list.,&v.,~);
      %let var2=%scan(&var2list.,&v.,~);
      %let var3=%scan(&var3list.,&v.,~);
      %let dataset=%qscan(&dslist.,&v.,~);
      proc sql noprint;
        create table %unquote(dplocal.flag_&tabid._2_&varid._xxx_&checkid.) as
        select a.&var2.
             , a.&var3.
             , a.&var1. 
             , b.flagid as flagid length=21
             , sum(a.count) as count format=comma15.
        from &dataset. (keep=&var2. &var3. &var1. count) a left join infolder.lkp_all_flags (where=(lowcase(tableid)="&tabid" and checkid="&checkid." and varid="&varid.")) b
          on a.&var2.=b.&var2. and a.&var3.=b.&var3.
        where %unquote(&where.)
        group by 1,2,3,4
        having flagid ne ' '
        ;  
        create table %unquote(work.flag_&checkid._&varid.) as
        select flagid
             , count
        from %unquote(dplocal.flag_&tabid._2_&varid._xxx_&checkid.)
        ;
    %end;
    quit;  

    data work.temp;
      set work.flag_&checkid._:;
    run;

    proc datasets lib=work nolist nowarn nodetails;
      delete flag_&checkid._:;
    run;
    quit;

    proc sql noprint;
      create table work.flag_&checkid. as
      select flagid
           , sum(count) as count
      from temp
      group by 1
      ;
    quit;
  %end;
%mend;

/* Create Level 2 flags for null values for required variables based on MS_test_name and result_type (CheckID=230) */
%l2_flags_var3 (checkid=230, where=%nrstr(&var1. is missing));
/* Create Level 2 flags for incorrectly populated values (not null) based on MS_test_name and result_type (CheckID=231) */
%l2_flags_var3 (checkid=231, where=%nrstr(&var1. is not missing));
/* Create Level 2 flags for negative (-) values based on MS_test_name and result_type (CheckID=234) */
%l2_flags_var3 (checkid=234, where=%nrstr(.<&var1.<0));
/* Create Level 2 flags for values of zero (0) based on MS_test_name and result_type (CheckID=235) */
*%flags_l2_var3 (checkid=235, where=%nrstr(&var1.=0));


/**********************************************************************************/
/* Create Level 2 flags for invalid value for 3-variable comparison (CheckID=232) */
%macro flags_232 (checkid=232);  
  %local varidlist;
  proc sql;
    select distinct varid
         , variable1
         , variable2
         , variable3
         , dataset
         , lookup_table 
    into :varidlist separated by "~"
       , :var1list separated by "~"
       , :var2list separated by "~"
       , :var3list separated by "~"
       , :dslist separated by "~"
       , :lkplist separated by "~"
    from infolder.lkp_all_flags (where=(checkid="232"))
    ;
  quit;
  %let varct=%sysfunc(countw(&varidlist.,~));
  %if &varct. ge 1 %then %do;
    %do v=1 %to &varct.;
      %let varid=%qscan(%bquote(&varidlist.),&v.,~);
      %let var1=%scan(&var1list.,&v.,~);
      %let var2=%scan(&var2list.,&v.,~);
      %let var3=%scan(&var3list.,&v.,~);
      %let dataset=%qscan(&dslist.,&v.,~);
      %let lkp=%qscan(&lkplist.,&v.,~);
      proc sql noprint;
        create table work.temp_lkp as
        select distinct testid, &var2., &var3., &var1.
        from infolder.&lkp.
        ;
        create table %unquote(dplocal.flag_&tabid._2_&varid._xxx_&checkid.) (drop=_lkp) as
        select a.&var2.
             , a.&var3.
             , a.&var1. 
             , b.&var1. as _lkp label=" "
             , sum(a.count) as count format=comma15.
             , case when a.&var1. ne _lkp then upcase("&tabid._2_"||"&varid."||"_"||a.testid||"_&checkid.")
                    else " "
               end as FlagID length=21
        from (select c.*, d.testid from &dataset. (keep=&var2. &var3. &var1. count) as c 
                inner join infolder.lkp_&tabid._test (keep=ms_test_name result_type testid characterized where=(characterized='Y')) as d 
                on c.&var2.=d.&var2. and c.&var3.=d.&var3.) as a 
          left join temp_lkp as b
          on a.&var2.=b.&var2. and a.&var3.=b.&var3. and a.&var1.=b.&var1.
        group by 1,2, a.&var1., _lkp, flagid
        having flagid ne ' '
        ;       
        create table %unquote(work.flag_&checkid._&varid.) as
        select flagid
             , count
        from %unquote(dplocal.flag_&tabid._2_&varid._xxx_&checkid.)
        ; 
    %end;
      quit;  
  
    data work.temp;
      set work.flag_&checkid._:;
    run;

    proc datasets lib=work nolist nowarn nodetails;
      delete flag_&checkid._:;
    run;quit;

    proc sql noprint;
      create table work.flag_&checkid. as
      select flagid
           , sum(count) as count
      from temp
      group by 1
      ;
    quit;
  %end;
%mend;
%flags_232;


/**********************************************************************************/
/* Create Level 2 flags for invalid values for 4-variable comparison (CheckID=243)*/
%macro flags_243 (checkid=243);  
%local varidlist;
proc sql noprint;
    select distinct varid
         , variable1
         , variable2
         , variable3
         , variable4
         , dataset
    into :varidlist separated by "~"
       , :var1list separated by "~"
       , :var2list separated by "~"
       , :var3list separated by "~"
       , :var4list separated by "~"
       , :dslist separated by "~"
    from infolder.lkp_all_flags (where=(lowcase(tableid)=lowcase("&tabid.") and checkid="&checkid."))
    ;
  quit;
  %let varct=%sysfunc(countw(&varidlist.,~));
  %do v=1 %to &varct.;
    %let varid=%qscan(%bquote(&varidlist.),&v.,~);
    %let var1=%scan(&var1list.,&v.,~);
    %let var2=%scan(&var2list.,&v.,~);
    %let var3=%scan(&var3list.,&v.,~);
    %let var4=%scan(&var4list.,&v.,~);
    %let dataset=%qscan(&dslist.,&v.,~);
    proc sql noprint;
      create table %unquote(dplocal.flag_&tabid._2_&varid._xxx_&checkid.) as
      select a.&var2.
           , a.&var3.
           , a.&var1. 
           , a.&var4.
           , b.flagid as flagid length=21
           , sum(a.count) as count format=comma15.
      from &dataset. (keep=&var2. &var3. &var1. &var4. count) a left join infolder.lkp_all_flags (where=(lowcase(tableid)="&tabid" and checkid="&checkid." and varid="&varid.")) b
      on a.&var2.=b.&var2. and a.&var3.=b.&var3.
      where &var1. ne " "
      group by 1,2,3,4,5
      having flagid ne ' '
      ;  
      create table %unquote(work.flag_&checkid._&varid.) as
      select flagid
           , count
      from %unquote(dplocal.flag_&tabid._2_&varid._xxx_&checkid.)
      ;
  %end;
    quit;
  data work.temp;
    set work.flag_&checkid._:;
  run;
  proc datasets lib=work nolist nowarn nodetails;
    delete flag_&checkid._:;
  run; quit;
  proc sql noprint;
    create table work.flag_&checkid. as
    select flagid
         , sum(count) as count
    from temp
    group by 1
    ;
  quit;
%mend;
%flags_243;


/**********************************************************************************/
/*  Merge all temporary work flags datasets */
data l2_flags_&tabid.;
  set work._flags work.flag:;
run;

proc sql noprint;
  create table dplocal.l2_flags_&tabid. as
  select b.flagid
       , b.flagtype
       , b.flag_descr
       , b.flagyn
       , b.abortyn 
       , a.count as count label=' ' format=comma15.
  from l2_flags_&tabid. (drop=flag_descr) as a left join infolder.lkp_all_flags as b
    on a.flagid=b.flagid
  where flag_descr ne " "
  ;
quit;

proc datasets lib=work kill nolist nowarn nodetails;
quit;

/********** End of Level 2 ********************************************************/


/*---------------------------------------------------------------------------------------*/
/*  START Level 3 Data                                                                   */
/*---------------------------------------------------------------------------------------*/
%let level=3;
%macro lab_date_dist (order=%bquote(&lrt_dt.));
  %local i j k;
  proc sql noprint;
    create table temp_date_all as
    select ms_test_name  
         , result_type   
  %do i=1 %to 3;
    %let date=%sysfunc(upcase(%scan(&order., &i.)));
    %str(, &date._ym as &date._dt)
  %end;
         , count(*) as n
    from dplocal._&tabid. (keep=ms_test_name result_type lab_ym result_ym order_ym)
    group by 1,2,3,4,5
    ;
  quit;

  %do j=1 %to 3;
    %let date=%sysfunc(upcase(%scan(&order., &j.)));
    proc sql noprint;
      create table dplocal.temp_date as
      select &date._dt
           , sum(n) as n
      from temp_date_all (keep=n &date._dt where=(&date._dt ne .))
      group by 1
      ;
    quit;
    %if &sqlobs. gt 0 %then %do;
      %date_percentiles (libin=dplocal, dsin=temp_date, libout=dplocal, dsout=temp_date_dist_&tabid._&j., vars=&date._dt);
    %end;
  %end;
      
/**********************************************************************************/
/* create msoc.lab_l3_dates_ym */
  proc sql noprint;
    create table msoc.lab_l3_dates_ym as
    select MS_Test_Name 
         , result_type
  %do k=1 %to 3;
    %let date=%sysfunc(upcase(%scan(&order., &k.)));
    %unquote(, put(&date._dt,yymmd.) as YearMonth_&date.)
  %end;
         , sum(n) as count format=comma15.
    from temp_date_all (keep=ms_test_name result_type order_dt lab_dt result_dt n)
    group by 1,2,3,4,5
    ;
    drop table temp_date_all
    ;
  quit;
%mend;
%lab_date_dist;

%set_ds (libin=dplocal, dsin_prefix=temp_date_dist_&tabid., libout=dplocal, dsout=date_dist_&tabid.);


/**********************************************************************************/
/* Create msoc.lab_l3_n_patid_test as count of unique PatID by ms_test_name*result_type */
/* Create msoc.lab_l3_n_patid_test_y as count of unique PatID by ms_test_name*result_type*year */
/* Create msoc.lab_l3_n_patid_test_ym as count of unique PatID by ms_test_name*result_type*year*month */
proc sql;
  create table msoc.&tabid._l3_n_patid_test as
  select ms_test_name
       , result_type
       , count(*) as count label="PatID Count" format=comma15.
  from dplocal.&tabid._pattest_count
  group by 1,2
  ;
  drop table dplocal.&tabid._pattest_count
  ;
  create table msoc.&tabid._l3_n_patid_test_ym as
  select ms_test_name
       , result_type
       , put(testdate,yymmd.) as YearMonth
       , count(unique patid) as count label="PatID Count" format=comma15.
  from dplocal._&tabid. (keep=patid ms_test_name result_type testdate)
  group by 1,2,3
  ;
  create table msoc.&tabid._l3_n_patid_test_y as
  select ms_test_name
       , result_type
       , put(testdate,year4.) as Year
       , count(unique patid) as count label="PatID Count" format=comma15.
  from dplocal._&tabid. (keep=patid ms_test_name result_type testdate)
  group by 1,2,3 
  ; 
  create table msoc.&tabid._l3_n_patid_enrolled_test_y as
  select a.ms_test_name
       , a.result_type
       , put(a.testdate,year4.) as Year
       , count(unique a.PatID) as count label="PatID Count" format=comma15.
  from dplocal._&tabid. (keep=patid ms_test_name result_type testdate) as a right join dplocal.all_match_patid (keep=patid enr lab where=(enr='1' and lab='1')) as b
    on a.patid=b.patid
  group by 1,2,3
  ;
  quit;


/**********************************************************************************/
/* Create msoc.lab_l3_record_lrodt_ptloc_ym */
/* Create msoc.lab_l3_record_lrodt_ym */
proc sql noprint;
  create table msoc.&tabid._l3_record_lrodt_ptloc_ym as
  select ms_test_name
       , result_type
       , ms_test_sub_category
       , fast_ind
       , pt_loc
       , put(testdate,yymmd.) as YearMonth
       , count(*) as count format=comma15.
  from dplocal._&tabid. (keep=patid ms_test_name result_type ms_test_sub_category fast_ind pt_loc testdate) 
  group by 1,2,3,4,5,6
  ;
  create table msoc.&tabid._l3_record_lrodt_ym as
  select ms_test_name
       , result_type
       , ms_test_sub_category
       , fast_ind
       , yearmonth
       , sum(_count) as count format=comma15.
  from msoc.&tabid._l3_record_lrodt_ptloc_ym (drop=pt_loc rename=(count=_count)) 
  group by 1,2,3,4,5
  ;
quit;   


/**********************************************************************************/
/* Create msoc.lab_l3_dates */
/* Create msoc.lab_l3_times */
%macro dt_tm (var=, out=);
proc sql noprint;
     create table msoc.lab_l3_&out. as
     select ms_test_name
          , result_type
          , case
               when lab_&var. ne . then 1
               else 0
            end as Lab&var. label="Lab_&var. populated?" length=3
          , case
               when result_&var. ne . then 1
               else 0
            end as Res&var. label="Result_&var. populated?" length=3
          %if %sysfunc(lowcase(&var.)) = dt %then %do;
          , case
               when order_&var. ne . then 1
               else 0
            end as Ord&var. label="Order_&var. populated?" length=3
          %end;
          , count(*) as count format=comma15.
     from dplocal._&tabid. (keep=ms_test_name result_type lab_&var. result_&var. 
          %if %sysfunc(lowcase(&var.)) = dt %then %do; 
             order_&var. 
          %end; )
     group by ms_test_name, result_type, 
          %if %sysfunc(lowcase(&var.)) = dt %then %do; 
            %unquote(ord&var.), 
          %end;
            lab&var., res&var.
     ;
quit;
%mend;
%dt_tm (var=dt, out=dates);
%dt_tm (var=tm, out=times);


/**********************************************************************************/
/* Establish temporary subset of MSCDM LRT variables for remaining L3 tables */
proc sql noprint;
  drop table dplocal._&tabid.
  ;
  create table dplocal._&tabid. as
  select *
       , case when result_type="N" then input(strip(orig_result),8.)
              else .
         end as orig_result_n length=8
  from mscdm.&table. (keep=PatID MS_Test_Name MS_Test_Sub_Category Result_type
                              Fast_ind Specimen_Source 
                              LOINC Stat Pt_Loc Result_Loc 
                              Orig_Result MS_Result_C MS_Result_N Modifier
                              Orig_Result_Unit Std_Result_Unit MS_Result_Unit
                              modifier_low norm_range_low modifier_high norm_range_high  
                              abn_ind px_codetype)
 
  ;
quit;


/**********************************************************************************/
/* Create msoc.lab_l3_test_resultn_stats_ms as descriptive statistics of MS_result_n by test */
/* Create msoc.lab_l3_test_resultn_stats_orig as descriptive statistics of orig_result_n by test */
%macro mean1 (var=, out=);
  proc means data=dplocal._&tabid. 
             (keep=MS_result_n %if &var.=orig_result_n %then %do; &var. %end; 
                   MS_test_name result_type MS_test_sub_category fast_ind specimen_source pt_loc 
                   modifier orig_result_unit std_result_unit MS_result_unit) noprint nway;
    var &var.;
    class MS_test_name result_type MS_test_sub_category fast_ind specimen_source pt_loc modifier MS_result_unit std_result_unit orig_result_unit / missing;
    where MS_result_n ne . ;
    output out=temp (drop=_type_ rename=_freq_=count)
       mean=Mean stddev=Std min=Min p5=P5 p25=P25 median=Median mode=Mode p75=P75 P95=P95 max=Max /keeplen; 
  run;
  data msoc.&tabid._l3_test_resultn_stats_&out.;
    retain MS_test_name Result_type MS_Test_Sub_Category Fast_Ind Specimen_Source Pt_Loc Orig_Result_Unit Std_Result_unit MS_Result_Unit;
    set temp;
    format mean median std 10.2 count comma15.;
  run;
   
  proc datasets lib=work nolist nowarn nodetails; delete temp; quit;
%mend;
%mean1 (var=ms_result_n, out=ms);
%mean1 (var=orig_result_n, out=orig);


/**********************************************************************************/
/* Create msoc.lab_l3_test_resultc_stats*/
proc sql noprint; 
  create table msoc.lab_l3_test_resultc_stats as
     select ms_test_name 
          , ms_test_sub_category
          , fast_ind  
          , specimen_source
          , Pt_Loc
          , MS_result_C
          , orig_result
          , count(*) as count format=comma15.
     from dplocal._&tabid. (keep=ms_test_name result_type ms_test_sub_category fast_ind specimen_source pt_loc MS_result_c orig_result)
     where result_type="C" and ms_result_c ne " "
     group by 1,2,3,4,5,6,7
     ;
quit;


/**********************************************************************************/
/* Create msoc.lab_l3_stat */
/* Create msoc.lab_l3_result_loc */
/* Create msoc.lab_l3_pt_loc */ 
/* Create msoc.lab_l3_abn_ind */
/* Create msoc.lab_l3_px_codetype*/
%macro msocl3tables (varlist=);
  
    %let nvar=%sysfunc(countw(&varlist., ' '));
    %do i=1 %to &nvar.;
       %let var&i=%scan(&varlist.,&i.);
    %end;
    %let _varlist = %sysfunc(strip(&var1));
    %do j=2 %to &nvar.;
      %let _varlist = %bquote(&_varlist.%str(, )%sysfunc(strip(&&var&j)));
    %end; 

  proc sql noprint;
    create table msoc.lab_l3_&var1. as
    select ms_test_name
         , result_type 
         , &_varlist.
         , count(*) as count format=comma15.
    from dplocal._&tabid. (keep=ms_test_name result_type &varlist.)
    group by ms_test_name, result_type, &_varlist.
    ;
    quit;

%mend;
%msocl3tables (varlist=stat);
%msocl3tables (varlist=ms_test_sub_category fast_ind result_loc);
%msocl3tables (varlist=pt_loc);
%msocl3tables (varlist=abn_ind);
%msocl3tables (varlist=ms_test_sub_category fast_ind px_codetype);


/**********************************************************************************/
/* Create table msoc.lab_l3_range */
proc sql noprint; 
  create table msoc.&tabid._l3_range as
  select  ms_test_name 
        , result_type
        , ms_test_sub_category
        , fast_ind
        , specimen_source
        , modifier_low
        , norm_range_low
        , modifier_high
        , norm_range_high
        , count(*) as count format=comma15.
  from dplocal._&tabid. (keep=ms_test_name result_type result_type ms_test_sub_category fast_ind specimen_source modifier_low norm_range_low modifier_high norm_range_high)
  where result_type='N'   
  group by 1,2,3,4,5,6,7,8,9
  ;
quit;


/**********************************************************************************/
/* MS_Result_N by Range category */
proc sort data=infolder.lkp_lab_result_ranges out=work.range;
  by fmtname;
run;

proc format cntlin=range; 
run;

%macro ranges (var=, var_short=);
  proc sql noprint;
    select count(distinct fmtname) into :nfmt
    from work.range
    ;
    select distinct trim(fmtname) into :fmtlist separated by " "
    from work.range
    ;
    select distinct quote(trim(fmtname)) into :fmtlistc separated by ","
    from work.range
    ;
  quit;
  %do i=1 %to &nfmt.;
    %let fmt=%scan(&fmtlist., &i.);
    proc sql noprint;
      create table work.temp as 
      select ms_test_name
           , ms_test_sub_category
           , fast_ind
           , &var.
           , ms_result_unit
           , put(ms_result_n, &fmt..) as ms_result_range length=25 
           , count(*) as count format=comma15.           
           , min(ms_result_n) as OrderVar
      from dplocal._&tabid. (keep=ms_test_name result_type ms_test_sub_category fast_ind &var. ms_result_n ms_result_unit modifier) 
      where result_type='N' and modifier='EQ' and ms_result_n ne . and compress(ms_test_name||ms_test_sub_category||fast_ind||ms_result_unit,'/ ')="&fmt."        
      group by ms_test_name, ms_test_sub_category, fast_ind, &var., ms_result_unit, ms_result_range 
      order by ms_test_name, ms_test_sub_category, fast_ind, &var., ms_result_unit, ordervar
      ;
    quit;

    %if %unquote(&sqlobs.) ne 0 %then %do;
      proc sql noprint;
        select sum(count), substr(ms_test_name, 1, 6) into :ntest trimmed, :test trimmed
        from work.temp
      ; 
      create table msoc.lab_l3_cat_resultn_&var_short._&test. (drop=ordervar) as
      select *
      from work.temp
      ;
    quit;   
    %end; 
 
  %end;
  proc datasets lib=work nolist;
    delete temp;
  quit;
%mend;
%ranges (var=pt_loc, var_short=ptloc);
%ranges (var=specimen_source, var_short=ss);

/********** End of Level 3 ********************************************************/

/* Clean up temporary or empty datasets and end module */
proc datasets kill lib=work memtype=data nolist nodetails nowarn; 
quit;

proc sql noprint;
    select memname into :ds separated by " "
    from dictionary.tables where libname='DPLOCAL' and substr(memname,1,8)='FLAG_LAB'
    having nobs-delobs=0
    ;
  quit;

proc datasets lib=dplocal memtype=data nolist nodetails nowarn;
  delete _&tabid. &ds.;
quit;

%timestamp(&tabid._end);
%timereport(&&&tabid._start,&&&tabid._end);

*-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-;
*  END of 7.1_mscdm_data_qa_review-labs.sas                                             ;
*-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-;
