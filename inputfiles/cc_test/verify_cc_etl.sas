/****************************************************************************************
*                                    SENTINEL MACRO
*****************************************************************************************
* NAME: verify_cc_etl.sas
*
* PURPOSE: The purpose of this macro is to verify that the Common-Components (CC) ETL
*          setup is correct. It does this by comparing the metadata of the SCDM data
*          included in the CC package to the metadata created by the QA-approved SCDM
*          tables currently residing in the QADATA library. If a mismatch occurs,
*          it may indicate a data integrity problem, and the macro generates a report
*          with the details. The macro also creates a permanent dataset to store the
*          overall status of the check (PASS/CHECK/FAIL) and prints any non-passing
*          results to the log and listing. The macro can also be set to abort if
*          any FAIL grades are generated.
*
* MAJOR STEPS:
*   1. For each SCDM table specified in CC and residing in the QADATA library
*       a. Compare data dictionary data (e.g. results from 'proc contents' procedure)
*          generated from QA package and QADATA library
*       b. Check result of comparison and gather details if differences found
*           i.  use SYSINFO macro variable to check return code to determine
                PASS/CHECK/FAIL grade
*           ii. if differences found, generate a report to the listing
*   2. Create permanent dataset to store overall PASS/CHECK/FAIL status
*   3. Print non-passing grade results to the log and listing
*   4. Abort if any FAIL grade generated (optional)
*
* KEY DEPENDENCIES/CONSTRAINTS/CAVEATS:
*   - Will only work for QA results from QA package v5.0.0 or higher
*--------------------------------------------------------------------------------------------------
* PARAMETERS:
*   outLIB     ... Name of output SAS libref to write out datasets to (default: MSOC)
*   outDSN     ... Name of output SAS dataset for overall PASS/CHECK/FAIL grade
*                  (default: VERIFY_CC_ETL)
*   abort_flag ... Y/N flag that aborts processing if overall grade is FAIL (default: Y)
*   cleanup    ... Y/N flag to clean up intermediate temporary datasets (default: Y)
*--------------------------------------------------------------------------------------------------
* CONTACT INFO:
*  Sentinel Coordinating Center
*  info@sentinel.org
*--------------------------------------------------------------------------------------------------
* HISTORY:
*  Create date (mm/dd/yy): 01/28/2014 (formerly standalone CC test package, last version was 2.0.1)
*  Last modified date (mm/dd/yy): 1/31/2019
*------------------------------------------------------------------------------------------------*/

%macro VERIFY_CC_ETL(QAMetaDSN=, outLIB=MSOC, outDSN=VERIFY_CC_ETL, abort_flag=Y, cleanup=Y) ;
 /*-------------------------------------*/
 /* 0-Setup Tasks                       */
 /*-------------------------------------*/

  /* Check parameters */
  %put ;
  %put -- Local macro parameters -- ;
  %put ;
  %put outLIB: &outLIB ;
  %put outDSN: &outDSN ;
  %put abort_flag: &abort_flag ;
  %put cleanup: &cleanup ;
  %put ;

  %local abort ;                      /* var for triggering SAS program abort cancel statement */
  %local cannot_verify_etl;           /* var for triggering SAS program to skip detailed verification steps */

  %if %length(&QAMetaDSN) eq 0 %then %do;
     %put macro is aborting ... QA Metadata file is not specified.;
     %let abort = 1 ;
  %end;

  %if (%sysfunc(libref(&outLIB))) ne 0 %then %do ;  /* 0 means assigned */
     %put macro is aborting ... %sysfunc(sysmsg()) ;
     %let abort = 1 ;
  %end ;

  %if %length(&outDSN) = 0 %then %do  ;
     %put macro is aborting ... outDSN is missing ;
     %let abort = 1 ;
  %end ;

  %if %length(&abort_flag) eq 0 or %upcase(&abort_flag) ne Y  and %upcase(&abort_flag) ne N %then %do ;
     %put macro is aborting ... abort_flag must be either Y or N ;
     %let abort = 1 ;
  %end ;

  %if %length(&cleanup) eq 0 or %upcase(&cleanup) ne Y  and %upcase(&cleanup) ne N %then %do ;
     %put macro is aborting ... cleanup must be either Y or N ;
     %let abort = 1 ;
  %end ;

  %if &abort eq 1 %then %do ;
     %abort cancel ;
  %end ;

  /* local macro variables for PASS/CHECK/FAIL dataset */
  %local test_group grade details results failed_tbls ;
  %let test_group = Verify ETL consistency ;
  %let details = Check if dictionary tables match between SCDM and QA metadata ;
  %let grade = PASS ;
  %let results = Dictionary tables match ;

  %if %sysfunc(exist(&QAMetaDSN)) eq 0 %then %do;
    %let cannot_verify_etl = 1 ;
    %let grade = FAIL;
    %let results = ETL consistency cannot be verified because the specified QA Metadata file &QAMetaDSN does not exist.;

    /* Create final grade dateset */
    data &outLIb..&outDSN ;
      length test_group $30. grade $5. details $100. results $300. ;
      test_group = "&test_group" ;
      grade = "&grade" ;
      details = "&details" ;
      results = "&results" ;
    run ;

    %put %upcase(e)%upcase(rror):;
    %put &=grade;
    %put &=details;
    %put &results;
  %end;

  %if &cannot_verify_etl ne 1 %then %do;  /* BEGIN if cannot_verify_etl ne 1 */

  /* Delete msoc.ETL_QA_Mismatches if it exists */
    proc datasets nodetails noprint lib=msoc ;
      delete ETL_QA_Mismatches ;
    quit;

  /* For the SCDM metadata, filter for just SCDM tables and split out header-level
     (i.e. memname) and detail-level (i.e. memname name) attributes */
    %local SCDM_tbls QA_tbls;
    proc sql noprint;
      select quote(strip(expected)) into :SCDM_tbls separated by ","
      from dplocal.compare_table_names
      ;
    quit;

    data SCDM_L1_CONT_H (keep=memname memtype nobs crdate modate crdate_n modate_n)
         SCDM_L1_CONT_D (keep=memname name type length format formatl formatd);
      set dplocal.SCDM_L1_CONT (rename=(crdate=crdate_n modate=modate_n));
      memname = lowcase(memname);
      memtype = lowcase(memtype);
      name = lowcase(name);
      crdate = put(crdate_n, datetime.);
      modate = put(modate_n, datetime.);
      if memname in (&SCDM_tbls.);
    run;

    proc sort data=SCDM_L1_CONT_D;
      by memname name;
    run;

    proc sort nodupkey data=SCDM_L1_CONT_H;
      by memname;
    run;

  /* For CC QA metadata, split out header-level (i.e. memname) and */
  /* detail-level (i.e. memname name) attributes */
    data QA_L1_CONT_H (keep=memname memtype nobs crdate modate crdate_n modate_n)
         QA_L1_CONT_D (keep=memname name type length format formatl formatd);
      set &QAMetaDSN (rename=(crdate=crdate_n modate=modate_n));
      memname = lowcase(memname);
      memtype = lowcase(memtype);
      name = lowcase(name);
      crdate = put(crdate_n, datetime.);
      modate = put(modate_n, datetime.);
    run;

    proc sort data=QA_L1_CONT_D;
      by memname name;
    run;

    proc sort nodupkey data=QA_L1_CONT_H;
      by memname;
    run;

/*----------------------------------------*/
/* 1-Compare SCDM with QA                 */
/*----------------------------------------*/
/* Define compare attribute macro This macro compares SCDM and QA variables and outputs */
/* differences in a transposed format of one row per comparison: variable &var QA_&var */

    %macro compare_attribute(var,type);
      %let type = %upcase(&type);
      if &var ne QA_&var then do;
        variable = lowcase("&var");
      %if &type eq C %then %do;
        SCDM_value = strip(&var);
        QA_value =  strip(QA_&var);
      %end;
      %else %if &type eq N %then %do;
        SCDM_value = strip(put(&var, 32.));
        QA_value =  strip(put(QA_&var, 32.));
      %end;
        output;
      end;
    %mend;

 /* Compare HEADER-LEVEL attributes */
    data compare_header (keep=sources memname variable SCDM_value QA_value);
      length sources $12;
      merge SCDM_L1_CONT_H (in=a)
            QA_L1_CONT_H (in=b rename=(memtype=QA_memtype nobs=QA_nobs
                                       crdate=QA_crdate modate=QA_modate
                                       crdate_n=QA_crdate_n modate_n=QA_modate_n));
      by memname;
      if (a & b) then sources = 'SCDM and QA';
      else if a then sources = 'SCDM Only';
      else if b then sources = 'QA Only';
      length variable $32.  SCDM_value QA_value $32.;
      if (a & b) then do;
        %compare_attribute(memtype,C);
        %compare_attribute(nobs,N);
     /* Ignore daylight times savings switches of exactly 1 hour or 3600 seconds */
        if abs(crdate_n - QA_crdate_n) ne 3600 then do;
          %compare_attribute(crdate,C);
        end;
        if abs(modate_n - QA_modate_n) ne 3600 then do;
          %compare_attribute(modate,C);
        end;
      end;
      else if a then do;
        variable= 'memtype'; SCDM_value= strip(memtype)        ; output;
        variable= 'nobs'   ; SCDM_value= strip(put(nobs, 32.)) ; output;
        variable= 'crdate' ; SCDM_value= strip(crdate)         ; output;
        variable= 'modate' ; SCDM_value= strip(modate)         ; output;
      end;
      else if b then do;
        variable= 'memtype'; QA_value= strip(QA_memtype)        ; output;
        variable= 'nobs'   ; QA_value= strip(put(QA_nobs, 32.)) ; output;
        variable= 'crdate' ; QA_value= strip(QA_crdate)         ; output;
        variable= 'modate' ; QA_value= strip(QA_modate)         ; output;
      end;
    run;

 /* Derive list of tables that are only in SCDM or QA */
 /* so that we may exclude these tables from detail comparisons */
    %local tbls_only_scdm_or_qa;
    %let tbls_only_scdm_or_qa = '';
    proc sql noprint;
      select distinct quote(strip(memname)) into :tbls_only_scdm_or_qa separated by ", "
      from compare_header
      where sources ne 'SCDM and QA'
      ;
    quit;

 /* Compare DETAIL-LEVEL attributes */
    data compare_detail (keep=sources memname variable SCDM_value QA_value);
      length sources $12;
      merge SCDM_L1_CONT_D (in=a)
            QA_L1_CONT_D (in=b rename=(type=QA_type length=QA_length format=QA_format
                                       formatl=QA_formatl formatd=QA_formatd));
      by memname name;
      if (a & b) then sources = 'SCDM and QA';
      else if a then sources = 'SCDM Only';
      else if b then sources = 'QA Only';
      length variable $32.  SCDM_value QA_value $32.;
      if memname NOT in (&tbls_only_scdm_or_qa) then do;
        %compare_attribute(type,N);
        %compare_attribute(length,N);
        %compare_attribute(format,C);
        %compare_attribute(formatl,N);
        %compare_attribute(formatd,N);
      end;
    run;

 /* Combine differences files */
    data ETL_QA_Mismatches;
      set compare_header
      compare_detail;
    run;

 /* Derive distinct list of tables with differences */
    %local tbls_diff;
    proc sql noprint;
      select distinct strip(memname) into :tbls_diff separated by " "
      from ETL_QA_Mismatches
      ;
    quit;
    %if %length(&tbls_diff) > 0 %then %do;
      %let grade = FAIL;
      %let results = Data dictionary tables between SCDM and QA do NOT match for these tables: ;
      %let failed_tbls = &tbls_diff ;

      data msoc.ETL_QA_Mismatches;
        set ETL_QA_Mismatches;
      run;
    %end;

 /* Clean up intermediate temporary datasets */
    %if &cleanup eq Y %then %do ;
      proc datasets nolist library=WORK ;
        delete compare_: SCDM_L1_CONT_: QA_L1_CONT_: ETL_QA_Mismatches;
      quit ;
    %end ;

 /*--------------------------------------*/
 /* 2- Compile final results             */
 /*--------------------------------------*/
    data &outLIb..&outDSN ;
      length test_group $30. grade $5. details $100. results $300. ;
      test_group = "&test_group" ;
      grade = "&grade" ;
      details = "&details" ;
      results = "&results &failed_tbls" ;
    run ;

 /*------------------------------------------------------------*/
 /* 3- If grade not PASS print out results to log              */
 /*------------------------------------------------------------*/
    data check_fail ;
      length msg $15 ;
      set &outLIb..&outDSN  ;
	     where grade ne 'PASS' ;
	     if grade eq 'FAIL' then do ;
	       msg = upcase('e' !! 'rror: ') ;
	     end ;
	     else if grade eq 'CHECK' then do ;
        msg = upcase('w' !! 'arning: ') ;
      end ;
	     put msg= test_group= grade= results= ;
	     drop msg ;
    run ;

  /* Clean up intermediate temporary datasets */
    %if &cleanup eq Y %then %do ;
      proc datasets nolist library=WORK ;
        delete check_fail ;
      quit;
    %end ;
  %end; /* END if cannot_verify_etl ne 1 */

 /*----------------------------------------------------*/
 /* 4- If FAIL, abort program (optional)               */
 /*----------------------------------------------------*/
  %if &abort_flag eq Y and &grade eq FAIL %then %do ;
     %abort cancel ;
  %end ;

%mend VERIFY_CC_ETL ;
