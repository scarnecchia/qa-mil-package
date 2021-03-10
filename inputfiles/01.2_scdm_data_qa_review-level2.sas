/* Direct log to module log in the msoc folder */
proc printto log=modlog new;
run;quit;
/*-------------------------------------------------------------------------------------*\
|  PROGRAM NAME:                                                                        |
|     01.2_scdm_data_qa_review-level2.sas                                               |
|                                                                                       |
|  MIL QA PACKAGE VERSION: 3.0.0                                                    |
|---------------------------------------------------------------------------------------|
|  PURPOSE:                                                                             |
|     The purpose of the program is to perform critical level 2 data quality checks     |
|     on all applicable tables.                                                         |     
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

/*-------------------------------------------------------------------------------------*/
/*  START Level 2 Macro                                                                */
/*-------------------------------------------------------------------------------------*/
/*  All macros called from level2_abort are found in 00.1_scdm_standard_macros.sas     */
/*-------------------------------------------------------------------------------------*/ 
%macro level2_abort (level=2);
/* Create the list of tables to to include for Level 2 Checks */
  proc sql noprint;
    select module
         , quote(strip(module))
    into :tabidlist separated by ' '
       , :sql_tabidlist separated by ','
    from msoc.control_flow_3 (where=(execute_flag='y' and cc_table ne 'X'))
    ;
  quit;
/*-------------------------------------------------------------------------------------*/
/* 1 - Perform L2 1.intra-table and 2.cross-table datachecks where AbortYN='y' for     */
/*-------------------------------------------------------------------------------------*/
  %do l=1 %to 2;
  /*-----------------------------------------------------------------------------------*/
  /* 1.1 - Create temporary lookup table                                               */
  /*-----------------------------------------------------------------------------------*/
   /*1:indicates no crosstable, and abort=y only*/
    %if &l.=1 %then %do;
      %l2_lkp_table (abortyn=, crosstable=n);
      %l2_ds_nodupkey;
    %end;

    %else %if &l.=2 %then %do;  
      %l2_lkp_table (abortyn=y, crosstable=y);
    %end;

  /*-----------------------------------------------------------------------------------*/
  /* 1.2 - Create a macro variable with list of unique CheckIds from temporary lookup  */
  /*-----------------------------------------------------------------------------------*/
    proc sql noprint;
      select distinct checkid
           , count(distinct checkid) 
      into :checkidlist separated by ' '
         , :checkct trimmed
      from temp_l2_flags
      ; 
    quit; 
 
  /*-----------------------------------------------------------------------------------*/
  /* 1.3 - Loop through each CheckID and output temporary flags datasets by CheckID    */
  /*-----------------------------------------------------------------------------------*/
    %do c=1 %to &checkct.;
      %let checkid=%scan(&checkidlist.,&c.);
      %if (&checkid. ge 217 & &checkid. le 219) | (&checkid. ge 272 & &checkid. le 275) %then %do;
        %str(%flag_217_219_27_);
      %end;
      %else %if &checkid. ge 201 & &checkid. le 208 %then %do;
        %str(%flag_201_208);
      %end;
      %else %do;
        %str(%flag_&checkid.);
      %end;
      data dplocal.flag_l2_&checkid.;
        set flag_l2_&checkid.:;
      run;
     %ISDATA(dataset = dplocal.flag_l2_&checkid.);
     %IF &NOBS. > 0 %then %do;
       data dplocal.flag_l2_&checkid.;
         set dplocal.flag_l2_&checkid.;
          if count > 0;
        run;
     %END;
    %end;
  %end; /* end of loop L */

  /*-----------------------------------------------------------------------------------*/
  /* 1.4 - Combine temporary flags datasets                                            */
  /*-----------------------------------------------------------------------------------*/
    %set_ds (libin=dplocal, dsin_prefix=flag_l2, libout=dplocal, dsout=l2_flags_temp);

    proc datasets lib=work memtype=data kill nolist nowarn nodetails;
    quit;

    proc contents data=dplocal.l2_flags_temp out=_temp;
    run;

    %let ct=0;
    proc sql noprint;
      select nobs into :ct
      from _temp
      ;
      drop table _temp
      ;
    quit;

    %if &ct. ne 0 %then %do;
      proc sql noprint;
        select count(*) into :abort_qa
        from dplocal.l2_flags_temp (where=(lowcase(abortYN)='y'))
        ;
      quit;
      /* For loops 1 and 2, end macro at current loop when first Abort=YN occurs and output 
         finalized L2 flags for DP review */
      %set_ds (libin=dplocal, dsin_prefix=l2_flags_, libout=dplocal, dsout=l2_mstr); 

      %if &abort_qa. ne 0 %then %do;   /*aggregate counts for failed l2 flags*/
        proc sql noprint;
          create table dplocal.all_l2_flags as
          select flagid, abortyn, flagtype, flag_descr, sum(count) as count format=comma15. informat=comma15.
          from dplocal.l2_mstr (where=(lowcase(abortYN)='y'))
          group by 1,2,3,4
          order by 1,3
          ;
        quit;

        %let end_qa=1;
        %let l=999;

        data _null_;      
          putlog 70*'!';
          putlog 'ERR'"OR: The &module. module detected fatal L2 data flags"; 
          putlog "       that require the QA package to abort";
          putlog 70*'!';
        run;

        /* Clean up datasets from DPLOCAL before aborting */
        proc sql noprint;
          select memname into :ds separated by " "
          from dictionary.tables where libname='DPLOCAL'
          having nobs-delobs=0
          ;
        quit;

        proc datasets lib=dplocal nolist nowarn nodetails;
          delete tmp_: l2_nodup_:;
        quit; 
      %end; /*end of loop to abort */
    %end; /* end of loop for if flags exist */

/* Clean up datasets from DPLOCAL before continuing */
  proc datasets lib=dplocal memtype=data nowarn nolist nodetails;
    delete tmp_: ;
  quit;
%mend;
%level2_abort;

%timestamp(&module._end);
%timereport(&&&module._start,&&&module._end);

*-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-;
*  END 01.2-scdm-data-qa-review-level2.sas                                              ;
*-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-;
