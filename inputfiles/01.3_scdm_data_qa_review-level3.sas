/* Direct log to module log in the msoc folder */
proc printto log=modlog new;
run;quit;
/*-------------------------------------------------------------------------------------*\
|  PROGRAM NAME: 01.3_scdm_data_qa_review-level3.sas                                    |
|                                                                                       |
|  MIL QA PACKAGE VERSION: 3.0.0                                                        |
|---------------------------------------------------------------------------------------|
|  PURPOSE:                                                                             |
|     The purpose of the program is to create cross-table level 3 output datasets for   |
|     all SCDM tables                                                                   |
|---------------------------------------------------------------------------------------|
|  PROGRAM INPUT:                                                                       |
|     see 00.0_scdm_mil_data_qa_review_master_file.sas                                  |
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
%timestamp(&module._start);

/*---------------------------------------------------------------------------------*/
/* Combine temporary flags datasets                                                */
/*---------------------------------------------------------------------------------*/
%macro l2_flags_final;
  data temp_flag;
    set dplocal.l2_mstr:;
  run;

  %ISDATA(dataset = temp_flag);
  %if &nobs. > 0 %then %do; /* if temp flag not empty */
    proc sql noprint;
      create table all_l1_l2_flags as
      select flagid, abortyn, flagtype, flag_descr, count as count format=comma15. informat=comma15.
      from temp_flag (where=(count gt 0))

    %if %sysfunc(exist(dplocal.all_l1_flags,data)) %then %do; /*if dplocal.all_l1_flags exists*/
      %str(union all 
           select flagid, abortyn, flagtype, flag_descr, count as count format=comma15. informat=comma15.
           from dplocal.all_l1_flags)
    %end; /* END if dplocal.all_l1_flags exists */
      ;
      create table dplocal.all_l1_l2_flags as
      select flagid
           , abortyn
           , flagtype
           , flag_descr
           , sum(count) as count format=comma15. informat=comma15.
      from all_l1_l2_flags
      group by 1,2,3,4
      order by 1,3
      ;
      drop table temp_flag, all_l1_l2_flags
      ;
    quit;
  %end; /* END if temp flag not empty */

  %else %do; /* if temp flag empty */
    %ISDATA(dataset = dplocal.all_l1_flags);
    %if &nobs. > 0 %then %do; /*if dplocal.all_l1_flags not empty*/
      proc sql noprint;
        create table all_l1_l2_flags as
        select flagid
             , abortyn
             , flagtype
             , flag_descr
             , count as count format=comma15. informat=comma15.
        from dplocal.all_l1_flags
       ;
       create table dplocal.all_l1_l2_flags as
       select flagid, abortyn, flagtype, flag_descr, sum(count) as count format=comma15. informat=comma15.
       from all_l1_l2_flags
       group by 1,2,3,4
       order by 1,3
       ;
       drop table  all_l1_l2_flags
       ;
     quit;
   %END; /* END if temp flag empty */
 %END; /*END if dplocal.all_l1_flags not empty*/

  proc datasets lib=dplocal nolist nodetails nowarn;
    delete l2_flags_:;
  quit;

%mend l2_flags_final;


/**********************************************************************************/
/*  SUSPECT LINKAGES                                                              */
/*    Evaluating linkages and producing a detail report for the Data Partner and  */
/*    an aggregate file for the SOC.                                              */
/*    NOTE--> there are no abort rules for these checks.                          */  
/**********************************************************************************/
%macro suplinkage;
  %let birth_types = %str(1 2 3 4 5);
  %let level = 3;

  proc sql noprint;
    select module
         , count(*) 
    into :tabidlist separated by ' '
       , :tabct trimmed
    from msoc.control_flow_3 (where=(/*execute_flag='y' and */cc_table ne 'X'))
    ;
  quit;

 /*Birth_Type= 1-5 and number of linked records per  MPatID/ADate combination differs */
  %put &tabidlist.;
  %do a=1 %to &tabct.;
    %let tabid=%scan(&tabidlist.,&a.);
    %do b=1 %to %sysfunc(countw(&birth_types.));
      %let bt = %scan(&birth_types,&b.);
      proc sql;
        create table linkage&b. as
        select count(distinct cpatid) as crows, mpatid, adate, encounterid, birth_type
        from qadata.&&&tabid.table
        where birth_type=&bt. and not missing(cpatid) and not missing(mpatid) /*Linked Record*/
        group by mpatid, adate, encounterid, birth_type
        order by mpatid, adate, encounterid, birth_type
        ;
      quit;

      data flag_&b._&a.;
        set linkage&b.;
        length message $300 flag_descr $255;
        length flagid $21;
        length FlagType $4 AbortYN $1;
        flag_descr = cat("Birth_Type (",birth_type,") not consistent with number of linkages; confirmation required");
        flagid = cats("%upcase(&tabid.)_",&level.,"_00_00-0_37&b.");
        FlagType = "Warn";
        AbortYN = "N";
        flag_l3 = 0;
        if crows ne birth_type then do;
          message = cat("MPatID (",mpatid,"), EncounterID (",encounterid,"), Adate (",put(adate, mmddyy10.),
           "), Birth_type (",birth_type,"):Birth_Type value not consistent with number of linkages; confirmation required");
        flag_l3 = 1;
        end;
        if flag_l3;
      run;
  
      %ISDATA(dataset = flag_&b._&a.);
      %if &nobs. > 0 %then %do;
        proc sql;
          create table %str(dplocal.flag_l3_37&b._&tabid.) as
          select flagid, message, flag_descr, flagtype, abortyn, count(*) as count 
          from  flag_&b._&a.
          group by flagid, message, flag_descr, flagtype, abortyn
          ;
          drop table flag_&b._&a.
          ;
        quit;
      %end;
    %end; /* end b loop */
  %end; /* end a loop */
 
  /*QA for Birth_Type= 2-8 and no CPatIDs are linked*/
  %do a=1 %to &tabct.;
    %let tabid=%scan(&tabidlist.,&a.);
    proc sql;
      create table %str(dplocal.flag_l3_394_&tabid.) as
      select cats("%upcase(&tabid.)_",&level.,"_00_00-0_394") as flagid length =21
           , cat("MPatid (",mpatid,"), EncounterID (", Encounterid,"), Adate (",put(adate, mmddyy10.),"), Birth_Type (",birth_type,"): No linkages were found; confirmation required")
             as message length=300
           , cat("Birth_Type= 2-8 and no CPatIDs are linked") as flag_descr length = 255
           , "Warn" as Flagtype length = 4
           , "N" as abortyn length = 1
           , count(*) as count
      from qadata.&&&tabid.table
      where 2 <= birth_type <= 8 and missing(Cpatid)
      group by calculated flagid, calculated message, calculated flag_descr, flagtype, calculated abortyn
      ;
     quit;
  %end; /* end a loop */

 /*MPatID not linked to CPatID OR CPatID not linked to MPatID*/
  %do a=1 %to &tabct.;
    %let tabid=%scan(&tabidlist.,&a.);
    proc sql;
      create table %str(dplocal.flag_l3_396_&tabid.) as
      select cats("%upcase(&tabid.)_",&level.,"_00_00-0_396") as flagid length =21
           , cat("MPatid (",mpatid,"), EncounterID (", Encounterid,"), Adate (",put(adate, mmddyy10.),"): No linkage to infant was found; confirmation required")
             as message length = 300
           , cat("MPatID not linked to CPatID") as flag_descr length = 255
           , "Warn" as Flagtype length = 4
           , "N" as abortyn length = 1
           , count(*) as count
      from qadata.&&&tabid.table
      where missing(Cpatid) and not missing(mpatid)
      group by calculated flagid, calculated message, calculated flag_descr, flagtype, calculated abortyn
      ;
    quit;
  %end; /* end a loop */

  %do a=1 %to &tabct.;
    %let tabid=%scan(&tabidlist.,&a.);
    proc sql;
      create table %str(dplocal.flag_l3_397_&tabid.) as
      select cats("%upcase(&tabid.)_",&level.,"_00_00-0_397") as flagid length =21
           , cat("CPatid (",Cpatid,"), CBirth_Date (",put(CBirth_Date, mmddyy10.),"): No linkage to mother/delivery was found; confirmation required")
             as message length = 300
           , cat("CPatID not linked to MPatID") as flag_descr length = 255
           , "Warn" as Flagtype length = 4
           , "N" as abortyn length = 1
           , count(*) as count
      from qadata.&&&tabid.table
      where not missing(Cpatid) and missing(mpatid)
      group by calculated flagid, calculated message, calculated flag_descr, flagtype, calculated abortyn
      ;
    quit;
  %end; /*end a loop */
  /* REMOVED ALL MIS CHECKS v3.0.0*/
%mend suplinkage;

%macro level3();
  /* aggregated l1 l2 flags */
  %l2_flags_final;

  /* suspect linkage */
  %suplinkage;

  %set_ds (libin=dplocal, dsin_prefix=flag_l3_, libout=dplocal, dsout=all_l3_flags_mstr); 

  /* aggregate linkage files */
  proc sql noprint;
    create table dplocal.all_l3_flags as
    select flagid, abortyn, flagtype, flag_descr, sum(count) as count format=comma15. informat=comma15.
    from dplocal.all_l3_flags_mstr
    group by 1,2,3,4
    order by 1,3
    ;
  quit;
%mend level3;
%level3; 

/*---------------------------------------------------------------------------------*/
/* Create level 3 aggregate dataset                                                */
/*---------------------------------------------------------------------------------*/
%macro createl3table();
  /* set maximum number of variables in summary stratifications */
  %local stratmax;
  %let stratmax = 3;
  /*Run macro twice 1) to create all aggregate table 
                    2) to create aggregate table for deliveries only*/
  %macro tables(where= , sort= , num= , outfile= , extravar=, types= );
    /*total number of _type_ generated*/
    %let Ntotal = %sysfunc(countw(&types.));

   /*sort MIL table*/
    proc sort data = qadata.&&&tabid.table (where = (&where.)) out = mi&num. &sort.;
      by mpatid encounterid;
    run;
 
    /*InfantsLinked: This is the count of distinct populated CPatIDs per MPatID/EncounterID*/  
    %if %eval(&num.) = 2 %then %do;
      proc sql;
        create table linkedcpatid as
        select mpatid, encounterid, count(distinct(cpatid)) as InfantsLinked length=3
        from qadata.&&&tabid.table 
        where not missing(mpatid)
        group by 1, 2
        order by 1, 2
        ;
      quit;
    %end;
   
    data l3_temp&num.;
    %if %eval(&num.) = 1 %then %do;
      set mi&num.;
      by mpatid encounterid;
    %end;
    %else %do;
      merge mi&num.(in = a) linkedcpatid;
      by mpatid encounterid;
      if a;
      if InfantsLinked = . then InfantsLinked = 0;
    %end;
    length LinkageStatus $1 Year $4 YearMonth $7 ICD_Ver $1 AgeGroup $9;
    %if %eval(&num.) = 1 %then %do; /*all*/
      if not missing(mpatid) and not missing(cpatid) then LinkageStatus = "L";
      if not missing(mpatid) and missing(cpatid) then LinkageStatus  = "M";
      if missing(mpatid) and not missing(cpatid) then LinkageStatus = "C";
    %end;
    %if %eval(&num.) = 2 %then %do; /*deliveries only*/
      if InfantsLinked >= 1 then LinkageStatus = "L";
      if InfantsLinked = 0 then LinkageStatus = "M";
    %end;
    /*YEAR*/
    if ADate ne . then do;
      Year= put(year(adate), 4.);
      YearMonth= cat(put(year(adate),4.),"-",put(month(adate),z2.));
    end;
    %if %eval(&num.) = 1 %then %do; /*all*/
      else if Adate eq . and CBirth_date ne . then do;
        Year= put(year(Cbirth_date), 4.);
        YearMonth= cat(put(year(CBirth_date),4.),"-",put(month(Cbirth_date),z2.));
      end;
    %end;
    /*ICD 9 VERSION*/
    %if %eval(&num.) = 1 %then %do; /*all*/
      icd_date = COALESCE(ddate, adate, CBirth_date);
    %end;
    %if %eval(&num.) = 2 %then %do;  /*deliveries only*/
      icd_date = adate;
    %end;
    if icd_date le "30Sep2015"d then ICD_Ver = "9";
      else if icd_date ge "01Oct2015"d then ICD_Ver = "0";
    patient  = 1;
   /*Agegroup*/
    if  not missing(mpatid) then do;
      if age >= 10 & age <= 19 then Agegroup = "10-19";
        else if age >= 20 & age <= 44 then Agegroup = "20-44";
          else if age >= 45 & age <= 54 then Agegroup = "45-54";
            else Agegroup = "Other";
    end;
      else Agegroup = "Infants";
    %if &num. = 1 %then %do;
     /*Days diff*/
      length daysdiff $25;
      if not missing(CBirth_date) and not missing(Adate) then do;
        diff = CBirth_date - Adate;
        daysdiff = put(diff, daysfmt.);
      end;
        else daysdiff = "09:NA";
    %end;
    drop icd_date;
  run;

  /*summarize across all vars*/
  proc means data = l3_temp&num. MISSING noprint;
    class LinkageStatus Birth_Type Year YearMonth ICD_Ver AgeGroup EncType &extravar.;
    var patient;
    output out = l3_temp_summ(drop = _freq_)sum(patient)=count;
  run;
  
  /*Algorithm to associate _type_ to variables used for stratification*/ 
  data typedesc;
    array x[&Ntotal.] (&types.);
    length p1-p&Ntotal. 8.;       
    n=dim(x);
    sumtype = 0;
    %do k = 1 %to &Ntotal.;
      ncomb=comb(n,&k.);
      do j=1 to ncomb;
        call allcomb(j, &k., of x[*]);
        %do m = 1 %to &k.;
          p&m. = x&m.;
          sumtype = sumtype+p&m.;
        %end;
        output;
        sumtype = 0;
      end;
    %end;
    drop j n x: ncomb;
  run;

  data typedesc1 (keep = sumtype level level_desc);
    set typedesc;
    length level $4 level_desc $200;
    %do i= 1 %to &Ntotal.;
      if not missing(p&i.) then do;
        level_desc = cat(strip(put(p&i., type&num.fmt.)),"    ",level_desc);
      end;
    %end;
    if DIVIDE(sumtype, 100) < 1 then level = strip(put(sumtype, z3.));
      else level = strip(put(sumtype, BEST4.));
    if countw(level_desc,"") le %eval(&stratmax.);
  run;

  proc sql;
    insert into typedesc1
      set sumtype = 0, level = '000', level_desc='Overall'
    ;
  quit;

  proc sql noprint;
    create table msoc.&outfile. (drop = _type_) as
      select b.level, b.level_desc, a.*
    from  l3_temp_summ a, typedesc1 b
    where a._type_ = b.sumtype
    order by a._type_, b.level, b.level_desc;
  quit;

  proc sort data = msoc.&outfile.;
    by level level_desc LinkageStatus Birth_Type Year YearMonth ICD_Ver AgeGroup EncType &extravar.;
  run;
  %mend tables;

  %tables(where=1, sort=, num=1, outfile=l3_mil_aggregate, extravar=sex DaysDiff MatchMethod, 
          types= %str(1 2 4 8 16 32 64 128 256 512)); /*all aggregate table*/
  %tables(where=%str(not missing(mpatid)), sort= nodupkey, num=2, outfile=l3_mil_aggregate_deliv, 
          extravar= InfantsLinked, types= %str(1 2 4 8 16 32 64 128));/*deliveries only*/
  
%mend createl3table;
%createl3table;

/*---------------------------------------------------------------------------------*/
/* Add DP to all datasets in MSOC folder, except signature files                   */
/*---------------------------------------------------------------------------------*/
%add_dpid_all_ds (libin=msoc, libout=msoc);

/*---------------------------------------------------------------------------------*/
/* Create metadata file for use with QA Common Components (CC) package             */
/*---------------------------------------------------------------------------------*/
%macro cc_metadata;
  %let mi =mil;
    %if %lowcase(&ccbypass.) = n %then %do;
      %copy_rename_ds(libin=qaresult, dsin=minmax_dates, libout=msoc, dsout=minmax_dates)
      %copy_rename_ds(libin=qaresult, dsin=all_l1_cont, libout=work, dsout=temp_cont_a)
      %copy_rename_ds(libin=dplocal, dsin=all_l1_cont, libout=dplocal, dsout=mil_l1_cont)
        
      data dplocal.all_l1_cont;
        set temp_cont_a (drop=dp) dplocal.mil_l1_cont ;
      run;
      
    %end; /* END if CC was not bypassed */
    %else %do;
      data msoc.cc_status;
        %add_dpid_ds
        ccbypass="&ccbypass.";
      run;
    %end;

    %local c i n;
    %let macro_var_list=%upcase(DP|ETL|Phase|SCDMVer|dp_mindate|dp_maxdate|
                              enrtable|demtable|distable|enctable|diatable|proctable|
                              factable|pvdtable|deathtable|codtable|labtable|vittable|
                              ipharmtable|itranstable|pretable|miltable);
    proc sql noprint;
      create table msoc.qa_cc_metadata (Variable char(32), Value char(255))
      ;  
      insert into msoc.qa_cc_metadata
    %do i=1 %to %sysfunc(countw(&macro_var_list.));
      %let var=%scan(&macro_var_list.,&i.,|);
      %if %sysfunc(index(&var.,DP_))=1 %then %do;
      %let n=%sysfunc(putn(%superq(&var.),best12.));
      %let c=%sysfunc(putn(&n.,date9.));
      %let value=&c.;
    %end;
    %else %do;
      %let value = %superq(&var.);
    %end;
      values ("&var.", "&value.")
    %end;
      ; 
    quit;
%mend cc_metadata;
%cc_metadata

/*---------------------------------------------------------------------------------*/
/* Move specific files from DPLOCAL to MSOC                                        */
/*---------------------------------------------------------------------------------*/
%macro move_files;
   
    proc sql;
      select memname
           , count(memname) 
      into :filelist separated by ' '
         , :filect trimmed
      from dictionary.tables 
      where libname="DPLOCAL" and (index(memname, "MSTR")=0 and memname ne "ALL_L1_FLAGS" and memname ne "ALL_L1_FLAGS_MSTR"
         and memname ne "L2_MSTR" and memname ne "ALL_L3_FLAGS_MSTR" and memname ne "ALL_L2_FLAGS")  
      ;
    quit;

    %do i=1 %to &filect.;
      %let file=%scan(&filelist.,&i.);
      proc sql noprint;
        create table msoc.&file. as
        select %add_dpid_sql
             , *
        from dplocal.&file.
        ;
        drop table dplocal.&file.
        ;
      quit;

      %if %index(upcase(&file.), SIGNATURE) > 0 %then %do;
        data msoc.&file.;
          set msoc.&file. (drop = DP);
        run;
      %end;
    %end;

%mend;
%move_files;

/* Clean up datasets from DPLOCAL */
proc sql noprint;
  select memname into :ds separated by " "
  from dictionary.tables where libname='DPLOCAL'
  having nobs-delobs=0
  ;
quit;

/* Delete unnecessary DPLOCAL datasets */
proc datasets lib=dplocal nolist nowarn nodetails;
  delete l2_nodup_: ;
quit;

%timestamp(&module._end);
%timereport(&&&module._start,&&&module._end);

*-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-;
* END 01.3_scdm_data_qa_review_level3.sas                                               ;
*-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-;
