/*-----------------------------------------------------------------------------------*\
|   PROGRAM NAME: soc_scdm_data_snapshot.sas                                          |
|-------------------------------------------------------------------------------------|
|                                                                                     |
|   PURPOSE:  The purpose of this program is to generate analytic datasets            |
|             to be used in a SCDM summary report. This program will be               |
|             distributed to all Data Partners (DP) and run on the most current       |
|             production ETL.                                                         |
|                                                                                     |
|-------------------------------------------------------------------------------------|
|                                                                                     |
|   PROGRAM INPUT:  See master program and/or workplan                                |
|                                                                                     |
|   PROGRAM OUTPUT:  See master program and/or workplan                               |
|                                                                                     |
|-------------------------------------------------------------------------------------|
|   CONTACT:                                                                          |
|        Sentinel Coordinating Center                                                 |
|        info@sentinelsystem.org                                                      |
|                                                                                     |
\*-----------------------------------------------------------------------------------*/

*+_+_+_+_+_+_+_+_+_+_+_+_+_+_+_+_+_+_+_+_+_+_+_+_+_+_+_+_+_+_+_+_+_+_+_+_+_+_+_+_+_;
* PLEASE DO NOT EDIT BELOW WITHOUT CONTACTING THE SENTINEL OPERATION CENTER        ;
*+_+_+_+_+_+_+_+_+_+_+_+_+_+_+_+_+_+_+_+_+_+_+_+_+_+_+_+_+_+_+_+_+_+_+_+_+_+_+_+_+_;
proc printto log="&MSOC./soc_scdm_data_snapshot.log" new; run;

%SIGNATURE_BEGIN;
%timestamp(snapshot_start);

/* import ptstoexclude if in cport format */
%importfiles(var=&ptstoexclude.);

/***************************************************************************************/
/* Create temporary enrollment extracts for medcov=Y/drugcov=Y and drugcov=Y           */
/***************************************************************************************/
proc sort data=indata.&enrtable. (drop=chart where=(enr_start ne . and enr_end ne . and (enr_start le enr_end)))
 out=temp_enr ;  * noduprec dupout=dup_enr_md;
 by patid enr_start enr_end;
run;
/* limit enrollment obs to exclude specified patid values */
%ms_delpatients(datafile=temp_enr,
                ptsfile=&PTSTOEXCLUDE.,
                Outfile=temp_enr);

data dplocal.temp_enr_md
     dplocal.temp_enr_d (drop=medcov)
     dplocal.temp_enr_m (drop=drugcov) ;
  set temp_enr (where=(drugcov='Y' or medcov='Y'));
  retain flag 'n';
  if medcov='Y' then do;
    output dplocal.temp_enr_m;
  /* create temporary enrollment extract having medcov= Y and drug_cov=Y */
    if drugcov='Y' then output dplocal.temp_enr_md;
 /* create temporary enrollment extract having medcov= Y and drug_cov=N or U */
  end;
  /* create temporary enrollment extract having drug_cov=Y */
  if drugcov='Y' then output dplocal.temp_enr_d;
run;

proc datasets kill lib=work mt=data nowarn nolist nodetails; run; quit;

%macro clean_enroll;
  %local poplist pop i ;
  %let poplist=d md m; /* add m */
  %do i=1 %to %sysfunc(countw(&poplist.));
    %let pop=%scan(&poplist, &i.);
    data temp_enr dplocal.enr_rec_dups_&pop. ;
      set dplocal.temp_enr_&pop.;
      format lag_start lag_end mmddyy10.;
      by patid;
      lag_start=lag(enr_start);
      lag_end=lag(enr_end);
      if first.patid then do;
        lag_start=.;
        lag_end=.;
      end;
  /* output duplicate and subset enrollment records to dplocal file*/
      else if (enr_start ge lag_start) and (enr_end le lag_end) then do;
        flag='y';
        output dplocal.enr_rec_dups_&pop.;
      end;
  /* output remaining records to a temporary file*/
      if flag='n' then output temp_enr;
      drop lag_start lag_end flag;
    run;

  /* delete temporary dplocal file */
    proc datasets lib=dplocal nolist nodetails;
      delete %str(temp_enr_&pop.);
    run;
    quit;

    data dplocal.temp_enr;
      set temp_enr;
      format lag_end mmddyy10.;
      by patid;
      lag_end=lag(enr_end);
      if first.patid then do;
        enr_period=1;
        span_period=1;
      end;
      /* Identify consecutive or overlapping records by patid by assigning the same enrollment period ID */
      /* Identify SCDM compliant (disjointed) records by patid by assigning a unique enrollment period ID */
      else
        do;
          if enr_start gt (lag_end+1) then enr_period + 1;
          if enr_start gt (lag_end+46) then span_period + 1;
        end;
      drop lag_end ;
    run;

    proc sql noprint;
      drop table temp_enr
      ;
      create table temp_enr as
      select patid
           , min(enr_start) as _enr_start format=mmddyy10.
           , max(enr_end) as _enr_end     format=mmddyy10.
      from dplocal.temp_enr
/*      group by patid, enr_period*/
      group by patid, span_period
      ;
      create table dplocal.enr_overlap_by_patid_&pop. (drop=enr_period) as
      select patid
           , enr_start as enr_start format=mmddyy10.
           , enr_end as enr_end format=mmddyy10.
           , enr_period
      from dplocal.temp_enr
      group by patid, enr_period
      having count(*) gt 1
      ;
/* enroll spanned */
      create table dplocal.enroll_spanned_rec_by_patid_&pop. (drop=span_period) as
      select patid
           , enr_start as enr_start format=mmddyy10.
           , enr_end as enr_end format=mmddyy10.
           , span_period
      from dplocal.temp_enr
      group by patid, span_period
      having count(*) gt 1
      ;
      drop table dplocal.temp_enr
      ;
      create table enr_rec_by_patid_&pop. as
      select *
           , _enr_end - _enr_start + 1 as LOE
      from temp_enr
      ;
      drop table temp_enr
      ;
      quit;
    %end;
%mend;
%clean_enroll;

data year(keep=year) ;
 set enr_rec_by_patid_md;
 length year 3 ;
 t_start = year(_enr_start);
 t_end = year(_enr_end);
 do t_y = t_start to t_end ;
   year=t_y;
   output year;
 end;
 drop t_: ;
 run;

/* Number of PatIDs with at least one day of medical and drug coverage by year. */
proc sql;
  create table msoc.enr_patid_count_md_y as
  select upcase("&dp.") as DP length=6
      , Year /*format=year4.*/
      , count(*) as Count format=comma15. label="PatID Count by Year"
  from year
  group by year
  ;
quit;

/* Number of PatIDs with at least one day of medical and drug coverage.*/
proc sql;
  create table msoc.enr_patid_ct_md as
 select upcase("&dp.") as DP length=6
      , count(distinct(Patid)) as Count format=comma16.  label="Total PatID Count"
 from enr_rec_by_patid_md ;
;quit;



/***************************************************************************************/
/*1. Create enr_rec_covlength_md dataset                                                    */
/***************************************************************************************/
proc sql;
 create table msoc.enr_rec_covlength_md as
 select upcase("&dp.") as DP length=6
      , LOE format=comma12. label='Length of Enrollment (days)'
      , count(*) as count format=comma16. label='Record Count'
 from enr_rec_by_patid_md
 group by loe
 order by loe
 ;
quit;



/***************************************************************************************/
/*2. Create enr_pat_covlength_md dataset                                               */
/***************************************************************************************/
proc sql;
  create table enr_pat_covlength_md as
  select patid
       , sum(LOE) as tLOE
  from enr_rec_by_patid_md
  group by patid
  ;
  create table msoc.enr_pat_covlength_md as
  select upcase("&dp.") as DP length=6
       , tLOE format=comma12. label='Total Length of Enrollment (days)'
       , count(*) as count format=comma16. label='Enrollee Count'
  from enr_pat_covlength_md
  group by tLOE
  order by tLOE
  ;
  drop table enr_pat_covlength_md
  ;
quit;



/***************************************************************************************/
/*3. Create enr_active_patid_ct_md dataset                                             */
/***************************************************************************************/
data active_enroll_patid;
  set enr_rec_by_patid_md;
  by patid;
  if last.patid and _enr_end ge &dp_maxdate.;
run;

proc sql noprint;
  create table msoc.enr_active_patid_ct_md as
  select upcase("&dp.") as DP length=6
       , &dp_maxdate. as DP_MaxDate format=mmddyy10.
       , count(*) as count label='Active Enrollee Count'
  from active_enroll_patid
 ;
quit;



/***************************************************************************************/
/*4. Create dem_pat_lstagecount_md dataset                                             */
/***************************************************************************************/

    /* macro to pull from demographic using scdm version dependent logic */
    %macro scdm_v7_v8_zip;
        %local zipvar sortby;
        %if %symexist(scdmver)=0 %then %do;
            %global scdmver;
            %let scdmver=7.0.0;
        %end;

        %global ver;
        %let ver=%substr(&scdmver,1,1);

        %if &ver = 7 %then %do;
            %let zipvar=zip;
            %let sortby=order by patid;
        %end;
        %else %let zipvar=postalcode;

        proc sql;
            create table dplocal.dem_patid as
                select  patid
                      , birth_date
                      , sex
                      , race
                      , hispanic
                      , &zipvar. as postalcode length=5
            from indata.&demtable. (keep=patid birth_date sex race hispanic &zipvar.)
            %str(&sortby.);
        quit;
    %mend;
    %scdm_v7_v8_zip;

    /* Retain single record per patid with latest enrollment span */
    /* create temp flag indicating whether enrollment overlaps with dp max date */
    data work._last_enroll_patid;
        set enr_rec_by_patid_md;
        by patid;
        if last.patid;
        _dpMaxenroll = (_enr_end ge &dp_maxdate.);
    run;

    /* merge enrollment with demographcis to add birthdate and calculate age */
    data work._enr_agecalc (drop=birth_date);
        merge work._last_enroll_patid (in    = a
                                       keep  = patid _enr_start _dpMaxenroll)
              dplocal.dem_patid       (in    = b
                                       keep  = patid birth_date
                                       where = (birth_date ne .));
        by patid;
        if a and b;

        Age=floor((intck('month',Birth_Date, _Enr_Start) - (day(_Enr_Start) < day(Birth_Date))) / 12);
        agecategory = put(age, age_years.);
    run;

    /* inner join with age category look-up to attach sort order */
    /* note this extract will be used again for table limited to currently enrolled     */
    proc sql noprint;
        create table work.dem_pat_age_md as
            select   a.*
                   , b.SortOrder length=3
                   , upcase("&dp.") as DP length=6
            from   work._enr_agecalc as a
                 , msoc.age_sort     as b
            where a.agecategory = b.label;
    quit;

    /* Summarize results to create final output table */
    proc sql;
        create table msoc.dem_pat_lstagecount_md as
            select  DP
                  , SortOrder
                  , agecategory            label='Age Category'
                  , count(*)    as count   label='Enrollee Count'
        from work.dem_pat_age_md
        group by DP, SortOrder, agecategory
        order by Sortorder;

        /* clean work directory */
        drop table work._last_enroll_patid;
        drop table work._enr_agecalc;

    quit;



/***************************************************************************************/
/*5. Create dem_pat_actagecount_md dataset                                             */
/***************************************************************************************/

    /* Filter dem age extract to retain active        */
    /* Summarize results to create final output table */
    proc sql;
        create table msoc.dem_pat_actagecount_md as
            select  DP
                  , SortOrder
                  , agecategory       label='Age Category'
                  , count(*) as count label='Active Enrollee Count'
        from work.dem_pat_age_md (where = (_dpMaxenroll))
        group by DP, SortOrder, agecategory
        order by Sortorder;

        /* clean work */
        drop table work.dem_pat_age_md;

    quit;
*** ---------------------------------------------------------------------------------------------- ***;

/* Create temporary extract of enrolled (MD) with one enrollment span per PatID */
/* Save for DEM, COD, and DTH "md" tables */
proc sort data=enr_rec_by_patid_md (keep=patid) out=dplocal.enr_patid_md nodupkey;
  by patid;
run;



/***************************************************************************************/
/*6. Create dem_sexct_md dataset                                                       */
/***************************************************************************************/
/* Merge DEM extract with ENR extract containing med/drugcov span per PatID */
/* Save for re-use for other DEM table */
data dplocal.dem_patid_enr;
  merge dplocal.dem_patid (in=a drop=birth_date) dplocal.enr_patid_md (in=b keep=patid);
  by patid;
  if a and b;
run;

proc sql noprint;
  create table msoc.dem_sexct_md as
  select upcase("&dp.") as DP length=6
       , sex label='Sex Category'
       , count(*) as Count label='Enrollee Count' format=comma12.
  from dplocal.dem_patid_enr (drop=patid postalcode hispanic race)
  group by 1,2
  ;
quit;



/***************************************************************************************/
/*7. Create dem_hispanicct_md dataset                                                       */
/***************************************************************************************/
proc sql noprint;
  create table msoc.dem_hispanicct_md as
  select upcase("&dp.") as DP length=6
       , Hispanic label='Hispanic Status'
       , count(*) as Count label='Enrollee Count' format=comma12.
  from dplocal.dem_patid_enr (drop=patid postalcode sex race)
  group by 1,2
  ;
quit;



/***************************************************************************************/
/*8. Create dem_racect_md dataset                                                       */
/***************************************************************************************/
proc sql noprint;
  create table msoc.dem_racect_md as
  select upcase("&dp.") as DP length=6
       , Race label='Race Category'
       , count(*) as Count label='Enrollee Count' format=comma12.
  from dplocal.dem_patid_enr (drop=patid postalcode sex Hispanic)
  group by 1,2
  ;
quit;



/***************************************************************************************/
/*9. Create dem_geolocct_md dataset                                                    */
/***************************************************************************************/
proc sql noprint;
  create table temp_dem as
  select postalcode
       , count(*) as _count
  from dplocal.dem_patid_enr (drop=patid sex hispanic race)
  group by 1
  ;
quit;

/* Load the data from the zip lookup table into a hash table and merge SCDM table on key variable ZIP to assign STATECODE*/
data dplocal.dem_zip (drop=rc);
  declare Hash zipstate (); /* declare the name ZIPSTATE for hash */
  rc = zipstate.DefineKey ('postalcode'); /* identify fields to use as keys */
  rc = zipstate.DefineData ('statecode'); /* identify fields to use as data */
  rc = zipstate.DefineDone (); /* complete hash table definition */
  do until (eof1) ; /* loop to read records from lookup file infolder.lkp_dem_zip  */
    set infolder.lkp_dem_zip  end = eof1;
    rc = zipstate.add (); /* add each record to the hash table */
  end;
  do until (eof2) ; /* loop to read records from WORK.ZIP1 */
    set temp_dem end = eof2;
    call missing(statecode); /* initialize the variable to fill */
    rc = zipstate.find (); /* lookup each ZIP in hash ZIPSTATE */
    output; /* write record WORK.ZIPSTATE */
  end;
  stop;
run;

proc sql noprint;
  drop table temp_dem
  ;
  create table temp_zip as
  select case when _statecode ne ' ' then _statecode /* valid zip */
              when postalcode=' ' then '00' /* missing zip */
              else '99' /* invalid zip */
         end as StateCode
       , sum(_count) as Count
  from dplocal.dem_zip (rename=statecode=_statecode)
  group by calculated StateCode
  ;
  drop table dplocal.dem_zip
  ;
  create table msoc.dem_geolocct_md as
    select upcase("&dp.") as DP length=6
         , StateCode label='Geographic Location'
         , Count label='Enrollee Count' format=comma12.
    from temp_zip
    order by StateCode
    ;
    drop table temp_zip
    ;
  quit;

  proc datasets lib=dplocal mt=data nolist nodetails nowarn;
    delete dem_: ;
  run;



/***************************************************************************************/
/*10. Create dis_pat_rxcount_md and 8. dis_pat_rxcount_d                                */
/***************************************************************************************/
%macro rx_enr_patid;

  proc sort data=indata.&distable. (keep=patid rxdate where=(rxdate ne .)) out=temp_dis;
    by patid rxdate;
  run;

  proc sql;
    create table dplocal.temp_dis as
    select *
        , count(*) as _count
    from temp_dis
    group by patid, rxdate
    ;
    drop table temp_dis
    ;
  quit;

  %let poplist=d md;
  %do i=1 %to %sysfunc(countw(&poplist.));
    %let pop=%scan(&poplist., &i.);

    proc sql noprint;
      create table temp_dis as
      select a.*
      from dplocal.temp_dis as a, enr_rec_by_patid_&pop. (drop=loe) as b
      where a.patid=b.patid
      having b._enr_start le a.rxdate le b._enr_end
      ;
      create table dis_pat_rxcount as
      select patid
           , sum(_count) as RX_Count
      from temp_dis
      group by patid
      ;
      drop table temp_dis
      ;
      create table msoc.dis_pat_rxcount_&pop. as
      select upcase("&dp.") as DP length=6
           , rx_count label='Dispensing Record Count' format=comma12.
           , count(*) as Count label='Enrollee Count' format=comma12.
      from dis_pat_rxcount
      group by rx_count
      order by rx_count
      ;
      drop table dis_pat_rxcount
      ;
    quit;
  %end;
  proc datasets lib=dplocal mt=data nolist nodetails nowarn;
    delete temp:;
  run;
%mend;
%rx_enr_patid;



/***************************************************************************************/
/*11. Create enc_pat_enccount_md                                                        */
/***************************************************************************************/
  proc sort data=indata.&enctable. (keep=patid ADate where=(ADate ne .)) out=temp_enc;
    by patid ADate;
  run;

  proc sql noprint;
    create table dplocal.enc_adate_patid as
    select *
        , count(*) as _count
    from temp_enc
    group by patid, ADate
    ;
    drop table temp_enc
    ;
    create table temp_enc_merge as
    select a.*
    from dplocal.enc_adate_patid as a, enr_rec_by_patid_md (drop=loe) as b
    where a.patid=b.patid
    having b._enr_start le a.adate le b._enr_end
    ;
    create table enc_pat_enccount as
    select patid
         , sum(_count) as Enc_Count
    from temp_enc_merge
    group by patid
    ;
    drop table temp_enc_merge
    ;
    create table msoc.enc_pat_enccount_md as
    select upcase("&dp.") as DP length=6
         , Enc_Count label='Encounter Record Count' format=comma12.
         , count(*) as Count label='Enrollee Count' format=comma12.
    from enc_pat_enccount
    group by Enc_Count
    order by Enc_Count
    ;
    drop table enc_pat_enccount, dplocal.enc_adate_patid
    ;
  quit;



/***************************************************************************************/
/*12. Create lab_pat_testcount_md                                                      */
/***************************************************************************************/
/*Leverage code from the QA package LAB module*/
%macro lab_pat_testcount_md (order=%str(lab result order));
  %if &labtable. ne %str( ) %then %do;
  %local i j;
  proc sql noprint;
    create table dplocal.temp_lab as
    select *
  %do i=1 %to 3 ;
    %let date=%sysfunc(upcase(%scan(&order, &i.)));
    %let date&i.=%scan(&order., &i.);
/*     , &date._dt as &date._ym format=yymon7. length=4*/
  %end;
       , case
  %do j=1 %to 3;
    %let date=%scan(&order, &j.);
         when &date._dt ne . then &date._dt
  %end;
         else .
         end as TestDate format=mmddyy10. length=4
    from indata.&labtable. (keep=patid &date1._dt &date2._dt &date3._dt)
    ;
  quit;

  proc sort data=dplocal.temp_lab (keep=patid TestDate where=(TestDate ne .)) out=temp_lab;
    by patid TestDate;
  run;

  proc sql;
    drop table dplocal.temp_lab
    ;
    create table lab_testdate_patid as
    select *
         , count(*) as _count
    from temp_lab
    group by patid, TestDate
    ;
    drop table temp_lab
    ;
    create table temp_lab_merge as
    select a.*
         , b._enr_start
         , b._enr_end
    from lab_testdate_patid as a, enr_rec_by_patid_md (drop=loe) as b
    where a.patid=b.patid
    having b._enr_start le a.TestDate le b._enr_end
    order by a.patid, a.TestDate, b._enr_start, b._enr_end
    ;
    create table lab_pat_testcount as
    select patid
         , sum(_count) as Lab_Count
    from temp_lab_merge
    group by patid
    ;
    drop table temp_lab_merge
    ;
    create table msoc.lab_pat_testcount_md as
    select upcase("&dp.") as DP length=6
         , Lab_Count label='Lab Record Count' format=comma12.
         , count(*) as Count label='Enrollee Count' format=comma12.
    from lab_pat_testcount
    group by Lab_Count
    order by Lab_Count
    ;
    drop table lab_pat_testcount
    ;
  quit;

  proc datasets lib=dplocal mt=data nolist nodetails nowarn;
    delete temp:;
  run;
  %end;
%mend;
%lab_pat_testcount_md;



/***************************************************************************************/
/*13. Create vit_pat_vitct_md                                                          */
/***************************************************************************************/
%macro vit_pat_vitct_md;
  %if &vittable. ne %str( ) %then %do;
    proc sql;
      create table dplocal.temp_vit (drop=ht wt diastolic systolic) as
      select *
           , case when ht ne .  then '1' else '0' end as HGT format=$1. length=1 label="HGT"
           , case when wt ne .  then '1' else '0' end as WGT format=$1. length=1 label="WGT"
           , case when systolic ne .  then '1' else '0' end as SYS format=$1. length=1 label="SYS"
           , case when diastolic ne .  then '1' else '0' end as DIA format=$1. length=1 label="DIA"
      from indata.&VITTABLE. (keep=patid measure_date ht wt diastolic systolic)
      ;
    quit;

    data temp_vit;
      set dplocal.temp_vit;
      if HGT='0' and WGT='0' and SYS='0' and DIA='0' then delete;
    run;

    proc sql;
      drop table dplocal.temp_vit
      ;
    quit;

    data dplocal.temp_vit_hgt(keep=patid measure_date HGT)
         dplocal.temp_vit_wgt(keep=patid measure_date WGT)
         dplocal.temp_vit_sys(keep=patid measure_date SYS)
         dplocal.temp_vit_dia(keep=patid measure_date DIA);
      set temp_vit;
      if HGT='1' then output dplocal.temp_vit_hgt;
      if WGT='1' then output dplocal.temp_vit_wgt;
      if SYS='1' then output dplocal.temp_vit_sys;
      if DIA='1' then output dplocal.temp_vit_dia;
    run;

    proc sql;
      drop table temp_vit
      ;
    quit;

    %let measurelist=HGT WGT SYS DIA;

    %do l=1 %to %sysfunc(countw(&measurelist.));
      %let measure=%scan(&measurelist., &l.);

      proc sort data=dplocal.temp_vit_&measure. out=temp_vit nodupkey;
        by patid measure_date;
      run;

      proc sql noprint;
        drop table dplocal.temp_vit_&measure.
        ;
        create table dplocal.temp_vit as
        select a.*
             , b._enr_start
             , b._enr_end
        from temp_vit as a, enr_rec_by_patid_md (drop=loe) as b
        where a.patid=b.patid
        having b._enr_start le a.measure_date le b._enr_end
        order by a.patid, a.measure_date, b._enr_start, b._enr_end
        ;
      quit;

      proc sort data=dplocal.temp_vit out=temp_vit_patid nodupkey;
        by patid;
      run;

      proc sql noprint;
        drop table dplocal.temp_vit
        ;
        create table temp_vit_count_&l. as
        select &l. as sortorder
             , "&measure." as VS_type
             , count(*) as _count
        from temp_vit_patid
        ;
        drop table temp_vit_patid
        ;
      quit;
    %end;

    data dplocal.temp_vit_stack;
      set temp_vit_count_:;
    run;

    proc sql;
      create table msoc.vit_pat_vitct_md as
      select upcase("&dp.") as DP length=6
           , VS_type label='Vital Sign' format=$12.
           , _count as Count label='Enrollee Count' format=comma12.
      from dplocal.temp_vit_stack
      group by VS_type
      order by sortorder
      ;
      drop table dplocal.temp_vit_stack
      ;
    quit;
  %end;

  proc datasets lib=dplocal mt=data nolist nodetails nowarn;
    delete temp:;
  run;

%mend;
%vit_pat_vitct_md;



/***************************************************************************************/
/*14. Create enr_pat_enrcount_md                                                       */
/***************************************************************************************/
proc sort data=enr_rec_by_patid_md out=temp_enr_startend;
  by patid _Enr_start _Enr_end;
run;

proc sql;
  create table enr_pat_start as
  select *
      , count(*) as _count
  from temp_enr_startend
  group by patid, _Enr_start
  ;
  drop table temp_enr_startend
  ;
  create table enr_pat_count as
  select patid
       , sum(_count) as Enr_Count
  from enr_pat_start
  group by patid
  ;
  drop table enr_pat_start
  ;
  create table msoc.enr_pat_enrcount_md as
  select upcase("&dp.") as DP length=6
       , Enr_Count label='Enrollment Record Count' format=comma12.
       , count(*) as Count label='Enrollee Count' format=comma12.
  from enr_pat_count
  group by Enr_Count
  order by Enr_Count
  ;
  drop table enr_pat_count
  ;
quit;

proc datasets lib=dplocal mt=data nolist nodetails nowarn;
  delete temp:;
run;



/***************************************************************************************/
/*15. Create dth_dthct_md                                                              */
/***************************************************************************************/
%macro dth_dthct_md;
  %if &deathtable. ne %str( ) %then %do;
    proc sort data=indata.&DeathTable.(keep=patid) out=dplocal.dth_by_patid;
      by patid;
    run;

    proc sql noprint;
      create table temp_dea_merge as
      select a.*
      from dplocal.dth_by_patid  as a, dplocal.enr_patid_md as b
      where a.patid=b.patid
      ;
      create table msoc.dth_dthct_md as
      select upcase("&dp.") as DP length=6
           , count(*) as Count label='Death Record Count' format=comma12.
      from temp_dea_merge
      ;
      drop table temp_dea_merge
      ;
    quit;
  %end;
%mend;
%dth_dthct_md;



/***************************************************************************************/
/*16. Create dth_dthct_m                                                               */
/***************************************************************************************/
%macro dth_dthct_m;
  %if &deathtable. ne %str( ) %then %do;
    proc sql;
      create table dplocal.enr_patid_m as
      select distinct patid
      from enr_rec_by_patid_m
      ;
      create table temp_dea_merge as
      select a.*
      from dplocal.dth_by_patid as a, dplocal.enr_patid_m as b
      where a.patid=b.patid
      ;
      create table msoc.dth_dthct_m as
      select upcase("&dp.") as DP length=6
           , count(*) as Count label='Death Record Count' format=comma12.
      from temp_dea_merge
      ;
      drop table temp_dea_merge, dplocal.dth_by_patid
      ;
    quit;
  %end;
%mend;
%dth_dthct_m;



/***************************************************************************************/
/*17. Create cod_pat_codct_md                                                          */
/***************************************************************************************/
%macro cod_pat_codct_md;
  %if &codtable. ne %str( ) %then %do;
    proc sql noprint;
      create table dplocal.cod_by_patid as
      select *
          , count(*) as _count
      from indata.&CODTable.(keep=patid)
      group by patid
      order by patid
      ;
      create table temp_cod_merge as
      select a.*
      from dplocal.cod_by_patid as a, dplocal.enr_patid_md as b
      where a.patid=b.patid
      ;
      create table cod_pat_codcount as
      select patid
           , sum(_count) as COD_Count
      from temp_cod_merge
      group by patid
      ;
      drop table temp_cod_merge
      ;
      create table msoc.cod_pat_codct_md as
      select upcase("&dp.") as DP length=6
           , put(COD_Count, rec_ct.) as COD_Count label='COD Record Count'
           , count(*) as Count label='Enrollee Count' format=comma12.
      from cod_pat_codcount
      group by COD_Count
      order by COD_Count
      ;
      drop table cod_pat_codcount
      ;
    quit;
  %end;
%mend;
%cod_pat_codct_md;



/***************************************************************************************/
/*18. Create cod_pat_codct_m                                                           */
/***************************************************************************************/
%macro cod_pat_codct_m;
  %if &codtable. ne %str( ) %then %do;
    proc sql noprint;
      create table temp_cod_merge as
      select a.*
      from dplocal.cod_by_patid as a, dplocal.enr_patid_m as b
      where a.patid=b.patid
      ;
      create table cod_pat_codcount as
      select patid
           , sum(_count) as COD_Count
      from temp_cod_merge
      group by patid
      ;
      drop table temp_cod_merge
       ;
      create table msoc.cod_pat_codct_m as
      select upcase("&dp.") as DP length=6
           , put(COD_Count, rec_ct.) as COD_Count label='COD Record Count'
           , count(*) as Count label='Enrollee Count' format=comma12.
      from cod_pat_codcount
      group by COD_Count
      order by COD_Count
      ;
      drop table cod_pat_codcount, dplocal.cod_by_patid
      ;
    quit;
  %end;
%mend;
%cod_pat_codct_m;


/***************************************************************************************/
/*19. Create mil linkage rates                                                         */
/***************************************************************************************/
%mil_linkage_rates(inlib=indata, outlib=msoc);

/***************************************************************************************/
/* Close signature file                                                                */
/***************************************************************************************/
%timestamp(snapshot_end);
%timereport(&snapshot_start,&snapshot_end);
%SIGNATURE_END;


/***************************************************************************************/
/* Cleanup SAS environment                                                             */
/***************************************************************************************/
proc datasets lib=work kill nodetails nowarn nolist;
run;
quit;
proc printto;
run;
/***************************************************************************************/
/* End of program                                                                      */
/***************************************************************************************/
