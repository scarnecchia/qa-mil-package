/* Direct log to module log in the msoc folder */
proc printto log=modlog new;
run;quit;
/*-------------------------------------------------------------------------------------*\
|  PROGRAM NAME:                                                                        |
|     01.1_scdm_data_qa_review-level1.sas                                               |
|                                                                                       |
|  MIL QA PACKAGE VERSION: 3.0.0                                                    |
|---------------------------------------------------------------------------------------|
|  PURPOSE:                                                                             |
|     The purpose of this program is to perform Level 1 data checks on MIL OR MIS       |
|     tables.                                                                           |                                              
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

%macro l1_table;
  %let newtablidlist = &tabidlist. del inf;
  %let numtables = %sysfunc(countw(&newtablidlist.));
  %do j = 1 %to &numtables.;
    %let tabid=%scan(&newtablidlist.,&j.);
    %table_name (n= );
    %if &j. = 1 %then %do;
      %ds_exist_delete (lib=dplocal, ds=l1_cont_&tabid.);
      %ds_exist_delete (lib=dplocal, ds=l1_scdm_comp_&tabid.);
      %ds_exist_delete (lib=dplocal, ds=l1_record_count_&tabid.);
      %ds_exist_delete (lib=dplocal, ds=l1_flags_&tabid.);
    %end;
/*************************************************************************************/
/** 100 - Confirm that the table exists                                             **/
/*************************************************************************************/
    %let memtype=null;

    %if %sysfunc(exist(qadata.&&table.,data)) %then %let memtype=data;
    %else %if %sysfunc(exist(qadata.&&table.,view)) %then %let memtype=view;

    %if &memtype.=null %then %do;
      %let abort_loop= 1;
      %let abort_table=%eval(&abort_table.+1);
      %abort_table (checkid=100, 
                  logmsg=%nrstr(The %sysfunc(upcase(&table.)) table cannot be found!) );
    %end;

    %if %eval(&abort_loop.= 0) %then %do; *if no abend, run check 101;
/*************************************************************************************/
/** 101 - Confirm that the table is populated                                       **/  
/*************************************************************************************/
    %local dsid numobs rc;
    %let numobs=0;
    %let dsid=%sysfunc(open(qadata.&table.));
    %if &memtype.=data %then %let numobs=%sysfunc(attrn(&dsid.,nlobs));

    %else %do;
      data _null_;
        dsid = open("qadata.&table.", 'is');
        do while (fetch(dsid, 'noset') = 0);
          n + 1;
        end;
        call symput('numobs',n);
        rc = close(dsid);
        stop;
      run;
    %end;

    %let nobs=%sysfunc(putn(&numobs.,comma18.));
      data _null_;
        put 70*'=';
        put "===>  Number of observations in the &tabid. table: &nobs." ;
        put 70*'=';
      run;

      data DPLOCAL.nobs_&tabid.;
        TabID=upcase("&tabid.");   
        MemType="&memtype.";
        Count_Obs=input(&numobs.,comma18.);
      run;

      %if &numobs. lt 1 %then %do;  
        %let abort_table=%eval(&abort_table.+1);
        %let abort_loop = 1;
        %abort_table (checkid=101, 
                   logmsg=%nrstr(The %sysfunc(upcase(&table.)) table contains &numobs. records)
                   );
      %end;
    %end; /* end abort_loop=0 condition */
 
    %if %eval(&j) = 1 %then %do;

      %if %eval(&abort_loop.= 0) %then %do; /*if no abend, run check 102 */
/*************************************************************************************/
/** 102 - Confirm correct table sort order                                          **/  
/*************************************************************************************/
        %local sortvarlist sortOrderFlag;

        proc sql noprint;
          select variable
            into :sortvarlist separated by " "
          from infolder.lkp_all_l1 (where=(lowcase(tabid) = "&tabid." and 
                                            not missing(sortorder)))
          order by sortorder;
          ;
        quit;

        * redirect log output of sort test in temp log file to be parsed;
        filename sortlog "&dplocal.&tabid._sortchk.log";
        proc printto log = sortlog new;
        run;

        proc sort data = qadata.&table(keep=&sortvarlist.) presorted out= _null_;
          by &sortvarlist.;
        run; 

        * return log to default module log;
        proc printto log = modlog; run;

        %let sortOrderFlag= 0;
        /* pull NOTES from temp log file to see if sort was verified */
        data _null_;
          length lines $80;
          infile sortlog dlm='|';
          input lines $;
          if lowcase(substr(lines,1,5)) = "note:";
          if find(lowcase(lines),"input data set is not in sorted order") then
            call symput('sortOrderFlag','1');
        run;      

        /* if sort order is verified then delete temp log output */
        %if %eval(&sortOrderFlag.) = 0 %then %do;
          %let rc=%sysfunc(fdelete(sortlog));
        %end;

        /* if sort order not verified then retain log file and abort_table */
        %if %eval(&sortOrderFlag) > 0 %then %do;
          %let abort_table=%eval(&abort_table.+1);
          %abort_table (checkid=102, 
                 logmsg=%nrstr(The %sysfunc(upcase(&table.)) table is not sorted correctly!)
                   );
        %end;
      %end; /* end abort_loop=0 condition to run check 102 */
    %end; /* end j=1 condition */
  %end; /* end j loop */
%mend l1_table;

/***************************************************************************************/
/* Check ETL number in dataset label                                                   */
/***************************************************************************************/
%macro etlcheck;
 /* Check ETL number from a dataset and check it against common components */
  %global ETLdata;
  %let ETLdata = ;
  %let tabid=%scan(&tabidlist.,&a.);
  %IF %SYSFUNC(EXIST(qadata.&&&tabid.table)) %THEN %DO;
    proc contents data = qadata.&&&tabid.table noprint out = etlnum (keep = memlabel);
    run;

    data etlnum;
      set etlnum;
      if _N_ = 1;
      if not missing(memlabel) and upcase(substr(strip(memlabel),1,3)) = "ETL" then 
      call symputx("etldata", substr(strip(memlabel),4));
    run;
   
    %put =====>&etldata.;

    data _null_;
      putlog 80*'*';
      putlog ' ';
      putlog "=====> ETL from &&&tabid.table: &ETLdata.";
      putlog ' ';
      putlog "=====> Expected ETL for this QA review: &ETL.";
      putlog ' ';
      putlog 80*'*';
      putlog ' ';
    run;

  %if "&ETLdata." = "" | %sysevalf(&ETLdata.-&ETL. ne 0) %then %do;
      data _null_;
        putlog 80*'!';
        putlog 'ERR'"OR: ";
        putlog "==> MASTER_FLOW macro is aborting due to an issue with the expected ETL number";
        putlog "    specified in the MIL table label";
        putlog ' ';
        putlog ' ';
        putlog "==> The Expected ETL should equal the current production ETL";
        putlog ' ';
        putlog "==> Ensure that ETL label in &&&tabid.table is filled and ";
        putlog "    and matches with the production ETL";
        putlog ' '; 
        putlog 80*'!';
        putlog ' '; 
      run;   
      %let abort_table=1;
    %end ;
    %else %do;
      data msoc.etl_version;  
        length ETL_: 8.;
        ETL_CC=&ETL.;
        ETL_&tabid. = &etldata.;
      run; 
    %end;
  %end;
%mend etlcheck;
      
/***************************************************************************************/
/* Variable-level L1 checks by table                                                   */
/***************************************************************************************/
%macro l1_variable;
  %let tabid=%scan(&tabidlist.,&b.);
  %table_name (n=);
/* Create a temporary Level 1 flags dataset */
  proc sql noprint;
    create table _flags as
    select *
    from infolder.lkp_all_flags (where=(lowcase(tableid)=lowcase("&tabid.") and level='1'))
    ;
  quit;
        
/* Create proc contents file and output to dplocal */
  proc contents data=qadata.&table. out=l1_cont_temp noprint;
  run;

  %table_size (libin=QADATA, dsin=&table., libout=work, dsout=l1_size_temp);  

  data DPLOCAL.l1_cont_temp;
    length TABID $3;
    set l1_cont_temp;
    tabid=upcase("&tabid.");
  run;

  data dplocal.l1_cont_&tabid.;
    merge dplocal.l1_cont_temp l1_size_temp;
    by tabid memname;
  run; 

  proc sql noprint;
    drop table dplocal.l1_cont_temp, l1_size_temp
    ;
    select put(count_obs,18.) into :nobs trimmed
    from DPLOCAL.all_l1_nobs (where=(lowcase(tabid)=lowcase("&tabid.")))
    ;
  quit;

/* Create table to check for SCDM variable-level compliance based on proc contents output */
  proc sql noprint;
    create table DPLOCAL.l1_scdm_comp_&tabid. as
    select upcase("&tabid.") as TabID length=3
         , coalesce (a.variable,b.name) as var label="Variable Name"
         , a.varid label="qadata Variable ID"
         , case when a.varid ne " " then "Y"
                else "N"
           end as MS_var label="Variable expected?"
         , case when length=. then "N"
                else "Y"
           end as DP_var label="Variable present?" 
         , a.vartype as MS_type label="Expected variable type"
         , case when b.type=2 then 'C'
                when b.type=1 then 'N'
                else ' '
           end as DP_type label="Actual variable type" length=1
         , a.varlength as MS_length label="Expected variable length" length=3
         , b.length as DP_length label="Actual variable length" length=3
    from infolder.lkp_all_l1 (where=(lowcase(tabid)=lowcase("&tabid."))) as a 
      full join DPLOCAL.l1_cont_&tabid. (keep=name type length nobs) b
      on upcase(a.variable)=upcase(b.name)
    order by a.varid
    ;
  quit;

/*************************************************************************************/
/** 110, 112, 113 - Confirm that the variable attributes comply with SCDM           **/  
/*************************************************************************************/
  /* Create temporary flag dataset for checks 110,112,113 */
  /*initialize flags*/
  %let flag110 = 0;
  %let flag112 = 0;
  %let flag113 = 0;
  
  data DPLOCAL.temp_flag_11x_&tabid.;
    length FlagID Variable $21 Value $8;
    set DPLOCAL.l1_scdm_comp_&tabid. (where=(ms_var="Y")) ; /* Exclude non-SCDM variables */ 
    retain FlagID Variable Value count;
    Variable=var;
  /* 110: Check if any required columns missing from table*/
    if dp_type=' ' then do;
      flagid=strip(upcase("&tabid._&level._"||varid||"_00-0_110"));
      count=99999;
      Value='NA';
      call symputx("flag110",1);
      output;
    end;    
    else do; /* Exclude missing SCDM variables from the remainder of the L1 checks */
   /* 112: Check SCDM compliance for variable type */    
      if ms_type ne dp_type then do;
        flagid=strip(upcase("&tabid._&level._"||varid||"_00-0_112"));
        count=1;
        Value=dp_type;
        call symputx("flag112",1);
        output;
      end;
  /* 113: Check SCDM compliance for variable length */
      if ms_length ne 0 and ms_length ne dp_length then do;
        flagid=strip(upcase("&tabid._&level._"||varid||"_00-0_113"));
        count=99999;
        value=put(dp_length,3.);
        call symputx("flag113",1);
        output;
      end;          
    end;
    label variable=' ';
    keep flagid variable value count;
  run;

  
  proc sql noprint;
    create table _lkp1 as
    select b.*
         , case when (a.dp_var="N") or (a.dp_length = .) OR 
                     (a.ms_type ne a.dp_type) then 'y1'
                when (a.ms_length ne 0) AND 
                     (a.ms_length ne a.dp_length) then 'y2'
                else 'n' 
           end as exclude length=2  
    from DPLOCAL.l1_scdm_comp_&tabid. (where=(ms_var="Y")) as a 
      left join infolder.lkp_all_l1 (where=(lowcase(tabid)=lowcase("&tabid."))) as b
    on a.var=b.variable
    order by b.varid
    ;
    quit;

    /* ascertain checks for l1_value macro */
    proc sql noprint;
      create table _lkp as
        select *, monotonic ( ) as row
      from _lkp1
      ; 
      drop table _lkp1
      ;
      select count(*) into :varct from _lkp
      ;
    quit;
 
%mend l1_variable;


/***************************************************************************************/
/* 3 - Value-level L1 checks                                                           */
/***************************************************************************************/
%macro l1_value;
/* SCDM v8.0.0 determine if valid var type = special_missing and 
   add condition to check special missing values*/
  %local i;
  proc sql noprint;
    select varid
         , variable
         , exclude
         , case when lowcase(ValidValueType) = "special_missing" then cat(trim(variable), " > .") 
            else cat("not missing(", trim(variable),")") end 
    into :varid trimmed
       , :var trimmed
       , :exc trimmed
       , :kcond trimmed
    from _lkp where row=&c.
    ;
  quit;
  %if &exc. ne y1 %then %do;
  /* initialize variable for count of populated (non-null) values */
    %let popobs = 0;
  /* initialize variable for count of non-null, non-special missing values */ 
    %let nomiss=0;
  /* initialize variable for count of special missing values */
    %let spmiss=0;
  /* initialize variable for count of null values */
    %let miss=0;
    %let flagct=0;
    %let nodata=0;

    proc sql noprint;
      create table dplocal._&varid._&tabid. as
        select *
      from qadata.&table. (keep= mpatid cpatid &var.)
      where &kcond.
      ;
    quit;
    /* obtain the count of populated obs */
    %let popobs = &sqlobs;

    proc sql noprint;
      /* get count of non-missing, non-special missing values */
      select count(*) format=18. into :nomiss
      from dplocal._&varid._&tabid.
      where not missing(&var.)
      ;
    quit;
    /* if special missing condition than get count of special missing values */
    %let spmiss = %sysevalf(&popobs.-&nomiss.); 

    %remove_labels(dplocal, _&varid._&tabid.);

    proc sql noprint;
      create table dplocal.temp_l1_recct_&varid. as
      select upcase("&tabid.") as TabID length=3
          , "&varid" as VarID length=2
          , "&var." as Variable length=21
          , count_obs label= "Count of Table Records" format=comma18.
          , input("&nomiss.",18.) as count_nomiss 
                label="Non-Missing Value Count" format=comma18. 
          , input("&spmiss.",18.) as count_spmiss 
                label="Special Missing Value Count" format=comma18.
          , count_obs - sum(calculated count_nomiss, calculated count_spmiss) as count_null
                label="Null Value Count" format=comma18.
      from dplocal.all_l1_nobs
      where lowcase(tabid)="&tabid."
      ;
      select put(count_null,15.) into :miss trimmed
      from dplocal.temp_l1_recct_&varid.
      ;
    quit;

    /* obtain flaglist for checkID in (111 120)*/
    proc sql noprint;
      create table _flags1 as
        select *
      from _flags (where=(varid="&varid."))
      order by checkid
      ;
      select checkid
        , abortyn
        , count(checkid) 
      into :flagslist separated by ' '
        , :abortlist separated by ' '
        , :flagct trimmed
      from _flags1 (where=(checkid in ("111","120")))
      ;
    quit;
  
  /* CheckID 111 - variable is not populated and 
     CheckID 120 - variable contains null values */
    %if &miss. ne 0 and &flagct. ne 0 %then %do;
      %let count=0;
      %do i=1 %to &flagct.;
        %let checkid=%scan(&flagslist.,&i.);
        %let abort=%scan(&abortlist.,&i.);
      /* 111 - variable is not populated */
        %if &checkid.=111 %then %do;   
          %if %sysevalf(&popobs.)=0 %then %do;
            %let count=99999;
            %let i=999; /* end loop if CheckID 111 is flagged to avoid redundant 111 and 120 flag */
            %let nodata=1;
          %end;
        %end;
      /* 120 - Variable contains null values */
        %else %if &checkid.=120 %then %do;
          %let count=%sysevalf(&miss.);
        %end;
        proc sql noprint;
          create table DPLOCAL.temp_flag_&tabid._&varid._&varid. as 
            select flagid length=21
              , variable1 as Variable length=21
              , '_null_' as Value
              , input("&count.",comma18.) as count format=comma18.
          from _flags1 (where=(checkid="&checkid."))
          ;
        quit;
      %end; /* End of loop i */
    %end; /* End miss ne 0 and flagct ne 0 condition */
  /* Excludes SCDM variables that are the wrong LENGTH or not pooulated (111),
     in addition to missing or wrong type, from the remainder of the L1 checks */   
    proc sql noprint;
      create table lkp_temp as
        select a.vartype
          , a.varlength
          , a.validvaluetype
          , a.flagcondition
          , b.checkid
          , b.flagid
          , monotonic ( ) as row
      from _lkp (where=(variable="&var.")) as a 
      inner join _flags (where=(checkid in ('121','122','126','130','131','133'))) as b
      on lowcase(a.variable)=lowcase(b.variable1)
      ;
    quit;
    %let checkct=&sqlobs.;
    %if %sysevalf(&exc. ne n or &nodata.=1) %then %do;
      %let checkct=0;
    %end;
  %end; /* End exc ne y1 condition */
%mend l1_value;

/*************************************************************************************/
/** 121,122,130-133 - Confirm that values comply with SCDM                          **/  
/*************************************************************************************/
%macro l1_value_12x_13x;
  proc sql noprint; 
    select vartype
         , varlength
         , flagcondition
         , flagid
         , checkid
    into :vtype
       , :vlength trimmed
       , :cond trimmed
       , :flagid trimmed
       , :checkid trimmed
    from lkp_temp
    where row=&d.
    ;
  quit;

  %let upvar=%upcase(&var.);

   /* Flag [TABID]_1_xx_00-0_121: Check variables values for invalid data */
  %if &checkid.=121 %then %do;
    proc sql noprint;
      create table DPLOCAL.temp_flag_&checkid._&varid. as
      select "&flagid." as FlagID length=21
           , strip("&var.") as Variable length=21
           , &var. as Value
      from DPLOCAL._&varid._&tabid. (where=(%unquote(&cond.)))
      ;
    quit; 
    %let recs=&sqlobs.;
  %end;

  %else %do;
  /* Flag [TABID]_1_xx_00-0_122: Check character variable of >1 in length values for leading spaces */ 
    %if &checkid.=122 %then %do;
      %let condition=%str( first(&var.)=' ' );
      %let value=%str(&var.);
    %end; 
  /* Flag [TABID]_1_xx_00-0_123: Age value if filled, must be between 10 and 54 inclusive */ 
    %if &checkid.=126 %then %do;
      %let condition=%str(&var. lt 10 | &var gt 54 );
      %let value=%str(&var.);
    %end;  
  /* Flag [TABID]_1_xx_00-0_131: Check the value must be valid between the DP's min and max dates*/
    %else %if &checkid.=131 %then %do;
      %let condition=%str(&var. lt &DP_mindate. | &var. gt &DP_maxdate.);
     %let value= put(&var.,mmddyy10.);
    %end;
 
 /* Flag [TABID]_1_xx_00-0_133: Check that value must only contain alpha, hyphen or apostrophe */
    %else %if &checkid.=133 %then %do;
      %let newvar = %SYSFUNC(COMPRESS(%LOWCASE(&VAR.), "abcdefghijklmnopqrstuvwxyz"));
      %if %length(&newvar.) > 0 %then %do;
        %let condition=%str(notalpha(strip(&var.)) gt 0  | (anyalpha(strip(&var.)) gt 0 & index(strip(&newvar.), "-") eq 0 & index(strip(&newvar.), "'") eq 0
                & index(strip(&newvar.), ".") eq 0));
      %end;
      %else %do;
        %let condition=%str(notalpha(strip(&var.)) gt 0);
      %end;
      %let value=%str(&var. );
    %end;
 
    proc sql noprint;
      create table DPLOCAL.temp_flag_&checkid._&varid. as
            select distinct "&flagid." as FlagID length=21
                 , strip("&var.") as Variable length=21
                 , &value. as Value
                 , %if "%upcase(%sysfunc(substr(&var., 1, 1)))"="C" %then CPatID;
                   %else %if "%upcase(%sysfunc(substr(&var.,1,1)))"="M" & "%lowcase(&var.)" ne "matchmethod" %then MPatID;
                   %else MPatID, CPatID;
      from DPLOCAL._&varid._&tabid.(where=(&condition.))
      ;
    quit;
    %let recs=&sqlobs.;
  %end;

  %if &recs.=0 %then %do;
    proc sql noprint;
      drop table DPLOCAL.temp_flag_&checkid._&varid.
      ;
    quit;
  %end;
%mend l1_value_12x_13x; 

%macro level_1 (level=1);
  %let abort_table=0;
  %let abort_qa=0;
  %local a b c d y viewlist memtype;
  %local tabct varct checkct flagct;
  %local var varid exc;

/* Create the list of tables to loop through for Level 1 Checks, using infolder.control_flow */
  proc sql noprint;
    select module
       , count(*) 
    into :tabidlist separated by ' '
       , :tabct trimmed
    from msoc.control_flow_3 (where=(/*execute_flag='y' and */cc_table ne 'X'))
    ;
  quit; 

  %do a=1 %to &tabct.;
    %let abort_loop = 0; /* initialize / reset abort_loop */
    %l1_table;
    %etlcheck;
  %end; /* End of loop A */

  %set_ds (libin=dplocal, dsin_prefix=nobs_, libout=dplocal, dsout=all_l1_nobs);

  %if &abort_table. ne 0 %then %do;
    %set_ds (libin=dplocal, dsin_prefix=flags_l1_, libout=dplocal, dsout=all_l1_flags);
  %end;

  %else %do;
    %do b=1 %to &tabct.;
      %l1_variable;
        %do c=1 %to &varct.;
          %let checkct=0;
          %l1_value;
          %if &checkct. ne 0 %then %do;
            %do d=1 %to &checkct.; /* start of loop d - by checkid */
              %l1_value_12x_13x;
            %end; /* end of loop d - by checkid*/
          %end;
          proc datasets lib=dplocal nolist nowarn nodetails;
            delete _&varid._&tabid.;
          quit;
        %end; /* end of loop c - by variable */
      /* Combine Level 1 temporary datasets into one dataset for each table */  
        %set_ds(libin=dplocal, dsin_prefix=temp_l1_recct_, 
                libout=dplocal, dsout=l1_record_count_&tabid.);
    %end;/* end of loop b - by table */
  %end; /* end of else condition */

/***************************************************************************************/
/* 3 - Combine like-named datasets by table into one dataset                           */
/***************************************************************************************/  
  %set_ds (libin=dplocal, dsin_prefix=l1_record_count_, libout=dplocal, dsout=all_l1_record_count);
  %set_ds (libin=dplocal, dsin_prefix=l1_cont_, libout=dplocal, dsout=all_l1_cont);
  %set_ds (libin=dplocal, dsin_prefix=l1_scdm_comp_, libout=dplocal, dsout=all_l1_scdm_comp);
 
 /*table abort*/
  %if &abort_table. eq 0 %then %do;
    %set_ds_varlength (libin=dplocal, dsin_prefix=temp_flag_, libout=dplocal, dsout=temp_flags, lengthvar=Value);

    proc contents data=DPLOCAL.temp_flags out=proctemp (keep=nobs);
    run;

    %let temp_nobs=0;
    proc sql noprint;
      select distinct nobs into :temp_nobs trimmed
      from proctemp
      ;
    quit;

    %if %eval(&temp_nobs. gt 0) %then %do;

    /*Save the patient-level file*/
    proc sql noprint;
      create table DPLOCAL.all_l1_flags_mstr as
      select distinct b.flagid
           , b.flag_descr
           , b.flagtype
           , b.abortYN           
           , b.variable1
           , a.value
           , a.Mpatid 
           , a.CPatid          
      from DPLOCAL.temp_flags as a left join infolder.lkp_all_flags (where=(level='1' and lowcase(flagYN)='y')) as b
        on lowcase(a.flagid)=lowcase(b.flagid)
      order by flagid
      ;
    quit;

   /*Summarize temp_flags*/
    proc sql noprint;
      create table temp_flags as
      select flagid, variable, value, count(*) as count
      from DPLOCAL.temp_flags
      group by flagid, variable, value
      ;
    quit;

    proc sql noprint;
      create table DPLOCAL.all_l1_flags as
      select distinct b.flagid
           , b.flag_descr
           , b.flagtype
           , b.abortYN           
           , b.variable1
           , a.value           
           , case when a.count=99999 then a.count
                  else sum(a.count) 
             end as count format=comma18.
      from temp_flags (where=(count>=1)) as a left join infolder.lkp_all_flags (where=(level='1' and lowcase(flagYN)='y')) as b
        on lowcase(a.flagid)=lowcase(b.flagid)
      group by 1,2,3,4,5,6
      order by 3,4 desc,1
      ;
      drop table DPLOCAL.temp_flags
      ;
    quit;
    %end; /*end of temps*/
  %end; /*end of table abort*/
  %if &abort_table. ne 0 %then %do;
   /* Delete unnecessary DPLOCAL datasets */
    proc datasets lib=dplocal nolist nowarn nodetails;
      delete temp_flag_11: ;
    run; quit;
  %end;

  %if %sysfunc(exist(DPLOCAL.all_l1_flags)) %then %do;
    proc sql noprint;
      select count(*) into :abort_qa 
      from DPLOCAL.all_l1_flags (where=(lowcase(abortYN)='y'))
      ;
    quit;
  %end;

  proc datasets kill memtype=data lib=work nolist nowarn nodetails;
  run; quit;

/***************************************************************************************/
/* Evaluate flags dataset to determine if qa package should end due to L1 failure      */
/***************************************************************************************/
  %put ==> Abort_qa: &abort_qa.;

  %if &abort_table. ne 0 or &abort_qa. ne 0 %then %do;
 /* process will abort with level 1 err.or */
    %let end_qa=1;
    %let l=999;

    proc datasets lib=dplocal nolist nowarn nodetails;
      delete _:;
    quit;
    data _null_;      
      putlog 70*'!';
      putlog 'ERR'"OR: The &module. module detected fatal L1 data flags"; 
      putlog "       that require the QA package to abort";
      putlog 70*'!';
    run;
  %end;
%mend level_1;
%level_1();

%timestamp(&module._end);
%timereport(&&&module._start,&&&module._end);

*-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-;
*  END 01.1-scdm-data-qa-review-level1.sas                                              ;
*-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-;
