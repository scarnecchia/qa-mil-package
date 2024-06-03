/****************************************************************************************
*                                      SENTINEL PROGRAM
*****************************************************************************************
* NAME: 01.0_cc_test.sas
*
* PURPOSE: Execute tests on the subset of common components (CC) parameters.
*
*   This program is intended to run AFTER a new ETL has been approved to verify that
*   global macro paramaters are set appropriately, including:
*       ETL (Phase B only)
*       ENRTABLE
*       DEMTABLE
*       DISTABLE
*       DIATABLE
*       PROCTABLE
*       ENCTABLE
*       DEATHTABLE (if available at site)
*       CODTABLE (if available at site)
*       LABTABLE(if available at site)
*       VITTABLE(if available at site)
*       IPHARMTABLE(if available at site)
*       ITRANSTABLE(if available at site)
*       MILTABLE (if available at site, Phase B only)
*
*   Further tests include:
*     - Verify consistency between data in INDATA and data in QARESULT
*     - Verify that request folders point to the right places
*     - An exploratory test to the feasibility of using SAS autocall macro
*       libraries in future workplans
*
* MAJOR STEPS:
*   1. Create a _test_group_n SAS dataset for each test group with following variables
*         - test_group: names or types of parameters tested
*         - grade: PASS, FAIL, CHECK
*         - details: Description of test
*         - results: Result of test
*   2. Concatenate the _test_group_n SAS datasets together, saving to MSOC libref
*   3. Report test results grouped by grade in listing and log
*
* KEY DEPENDENCIES/CONSTRAINTS:
*   - SAS datasets, infolder.cars, and infolder.fitness
*   - SAS datasets containing ETL-specific metadata from the QA package
        --> qaresult.qa_cc_metadata, qaresult.all_l1_cont
*   - SAS macros test_sasautos.sas and verify_cc_etl.sas in inputfiles/cc_test
*     subdirectory
*----------------------------------------------------------------------------------------
* CONTACT INFO:
*  Sentinel Coordinating Center
*  info@sentinel.org
*--------------------------------------------------------------------------------------*/

*----------------------------------------------------------------------------------------
* 0- Setup
*---------------------------------------------------------------------------------------;
* Set up log file *;
proc printto log="&MSOC.test_cc.log" new;
run ;

* Close listing *;
ods listing close ;

/* Call macro %signature_begin to begin creation of signature file */
%SIGNATURE_BEGIN;

/* Create a macro deletes a specified dataset if it exists */
%macro ds_exist_delete(lib, ds);
  %if %sysfunc(exist(&lib..&ds.,data)) %then %do;
    proc datasets lib=&lib. nolist nodetails;
      delete &ds.
      ;
    quit;
  %end;
%mend ds_exist_delete;

/* Call macro %ds_exists to clean up DPLOCAL from a prior execution of the program */
%ds_exist_delete(dplocal,cc_request_paths)
%ds_exist_delete(dplocal,compare_table_names)
%ds_exist_delete(dplocal,scdm_l1_cont)
/* Call macro %ds_exists to clean up MSOC from a prior execution of the program */
%ds_exist_delete(msoc,test_cc_results)
%ds_exist_delete(msoc,etl_qa_mismatches)

/* Create a macro that saves existing options and temporarily allows SAS */
/* to continue processing even if errors exist */
%macro _disable_syntax_checks ;
  proc optsave out=_options ;
  run ;
  options NOSYNTAXCHECK ;
  %if &SYSSCP eq WIN %then %do ;
     options NODMSSYNCHK ;
  %end ;
%mend ;
/* Call macro %_disable_syntax_checks */
%_disable_syntax_checks

* Find and delete _test_group files *;
%let _test_group_files = _test_dummy ;
proc sql noprint ;
    select memname into :_test_group_files separated by ' '
    from dictionary.members
    where libname eq 'WORK' and memname like "_TEST_GROUP_%" and memtype eq 'DATA'
 ;
quit ;

proc datasets library=work nolist  ;
     delete &_test_group_files ;
quit ;

/* create local variables DP and _phase from qa metadata */
proc sql noprint;
  select lowcase(value) into :_phase trimmed
  from qaresult.qa_cc_metadata (where=(lowcase(variable)="phase"))
  ;
  select lowcase(value) into :DP trimmed
  from qaresult.qa_cc_metadata (where=(lowcase(variable)="dp"))
  ;
quit;

/* Create proc contents dataset for all SCDM tables */
proc contents noprint data=QADATA._all_ out=dplocal.SCDM_L1_CONT;
run;

*--------------------------------------------------------------------------------------------------
* 1- test_group SCDM TABLE NAMES
*--------------------------------------------------------------------------------------------------;
/* Compare EXPECTED SCDM table names (in QARESULTS) to ACTUAL SCDM table names (in QADATA) */
proc sql noprint;
  create table dplocal.compare_table_names as
  select a.*, b.actual
  from (select variable as table
             , lowcase(value) as expected length=32
   from qaresult.qa_cc_metadata (where=(index (variable, "TABLE") ne 0 and value not in (" ", "NA") and first(value) ne "&"))) as a
     left join (select distinct(lowcase(memname)) as actual length=32
   from dplocal.SCDM_L1_CONT) as b
  on lowcase(a.expected)=lowcase(b.actual)
  ;
quit;

data _test_group_1 ;
     set dplocal.compare_table_names ;
     length test_group $30. grade $5. details $100. results $300. ;
     retain test_group 'SCDM TABLE NAMES'
          grade
          details 'Check if SCDM table names match between QA results and actual tables'
         results
         sp ' ' ;
  if expected = actual then do;
    grade= 'PASS' ;
    results="Expected and actual names match for"||sp||strip(table)||":"||sp||strip(actual)||".";
    output;
  end;
  else if expected ne actual then do;
    grade = 'FAIL' ;
    results="Expected name for"||sp||strip(table)||sp||"is"||sp||strip(expected)||sp||"but"||sp||strip(actual)||sp||"was found.";
    output;
  end;
  keep test_group grade details results ;
run ;

*--------------------------------------------------------------------------------------------------
* 2- test_group verify DPLOCAL and SASPROGRAMS directory locations are correct
*--------------------------------------------------------------------------------------------------;
%macro _test_locations ;
  %local grade msg1 msg2 msg file1 file2 ;

  %let file1 = sasprograms_placeholder.txt ;
  %let file2 = dplocal_placeholder.txt ;

     %if %sysfunc(fileexist("&SASPROGRAMS.&file1")) eq 0 %then %do ;
    %let grade = FAIL ;
    %let msg1 = &file1 was NOT found ;
  %end ;
  %if %sysfunc(fileexist("&DPLOCAL.&file2")) eq 0 %then %do ;
    %let grade = FAIL ;
    %let msg2 = &file2 was NOT found ;
  %end ;

  %if %length(&msg1)=0 and %length(&msg2)=0 %then %do;
    %let grade = PASS ;
    %let msg = &file1 and &file2 were succesfully found ;
  %end;
  %else %if %length(&msg1) > 0 and %length(&msg2) > 0 %then %do;
    %let msg = &msg1 AND &msg2;
  %end;
  %else %if %length(&msg1) > 0 %then %do;
    %let msg = &msg1;
  %end;
  %else %if %length(&msg2) > 0 %then %do;
    %let msg = &msg2;
  %end;

  data _test_group_2;
       length test_group $30. grade $5. details $100. results $300. ;
       retain test_group 'Verify SASPROGRAMS and DPLOCAL'
            grade "&grade"
            details "Check if &file1 and &file2 are in expected directories"
            results "&msg" ;
    keep test_group grade details results ;
     run ;
%mend _test_locations;
%_test_locations


*--------------------------------------------------------------------------------------------------
* 3- test_group verify ETL metadata consistency
*--------------------------------------------------------------------------------------------------;
%inc "&INFOLDER./cc_test/verify_cc_etl.sas" /nosource2 ;
%verify_cc_etl(QAMetaDSN=QARESULT.ALL_L1_CONT, outLIB=work, outDSN=_test_group_4, abort_flag=N, cleanup=Y)


*--------------------------------------------------------------------------------------------------
* 4- Test feasibility of using sasautos macro library in future
*--------------------------------------------------------------------------------------------------;
%let sasautos= %sysfunc(getoption(sasautos));
options sasautos = ("&infolder./cc_test" &sasautos) ;
run ;

%macro _test_sasautos_wrapper ;
   %local grade ;

   %test_sasautos
   %if &syserr eq 0 %then %do ;
        %let grade = *PASS ;
   %end ;
   %else %do ;
        %let grade = *FAIL ;
   %end ;

   data _test_group_4 ;
       length test_group $30. grade $5. details $100. results $300. ;
       retain test_group 'SAS Autocall Macro Library'
            grade "&grade"
            details "Explore feasibility of using SAS autocall macro library in future"
            results "N/A" ;
      keep test_group grade details results ;
   run ;

%mend _test_sasautos_wrapper ;
%_test_sasautos_wrapper ;


*--------------------------------------------------------------------------------------------------
* 5 - test_group SCDM TABLE LABEL (Phase B MIL only for now)
*--------------------------------------------------------------------------------------------------;
%macro check_table_label;

  %if &_phase. = b %then %do;
    %local miltable test_group details results grade actual expected;

    %let test_group=%str(SCDM TABLE LABELS);
    %let details=%str(Check if SCDM MIL table labels match between QA results and actual table);

    proc sql noprint;
      select lowcase(value) into :miltable trimmed
      from qaresult.qa_cc_metadata (where=(lowcase(variable)="miltable"))
      ;
      select distinct lowcase(MEMLABEL) into :actual trimmed
      from qaresult.all_l1_cont (where=(lowcase(memname)="&miltable."))
      ;
      select distinct lowcase(MEMLABEL) into :expected trimmed
      from dplocal.scdm_l1_cont (where=(lowcase(memname)="&miltable."))
      ;
    quit;

    %if "&actual."="&expected." %then %do;
      %let grade=PASS;
      %let results=%str(Expected and actual labels match for MIL table: &actual. );
    %end;
    %else %do;
      %let grade=FAIL;
      %let results=%str(Expected label for MIL table is &expected. but &actual. was found.);
    %end;

    proc sql noprint;
      create table _test_group_5
        (test_group char(30), grade char(5), details char(100), results char(300))
      ;
      insert into _test_group_5
      values ("&test_group.", "&grade.", "&details.", "&results.")
      ;
    quit;

  %end; /* end of if Phase B */
%mend check_table_label;
%check_table_label;

*--------------------------------------------------------------------------------------------------
* 6 - Save results of Common-Components tests and clean up environment
*--------------------------------------------------------------------------------------------------;

* Find _test_group files *;
proc sql noprint ;
    select memname into :_test_group_files separated by ' '
    from dictionary.members
    where libname eq 'WORK' and memname like "_TEST_GROUP_%" and memtype eq 'DATA'
  ;
quit ;
%*put &_test_group_files ;

* Save concatenated test results *;
data msoc.test_cc_results ;
    set &_test_group_files ;
run ;

* Delete _test_group files *;
proc datasets nolist library=work ;
     delete &_test_group_files ;
quit ;

* Restore options *;
proc optload data=_options ;
run ;

* Set up PDF "list" file *;
ods pdf close ;
ods pdf file="&MSOC.test_cc_results.pdf" ;

* Report on tests with grade of FAIL *;
data fail ;
    set msoc.test_cc_results ;
    where grade eq 'FAIL' ;
    msg = upcase('e' !! 'rror:') ;
    drop msg ;
    put msg= test_group= grade= results= ;
run ;

title 'Report on tests with grade of FAIL' ;
proc print data=fail ;
run ;

%macro print_ETL_QA_Mismatches;
  %if %sysfunc(exist(msoc.ETL_QA_Mismatches)) ne 0 %then %do ;
    title3 '  Tables and attributes that FAIL metadata integrity checks';
    title4 '  comparing SCDM and QA data dictionary tables';
    proc print data=msoc.ETL_QA_Mismatches;
    run;
  %end;
%mend;
%print_ETL_QA_Mismatches

* Report on tests with grade of CHECK*;
data check ;
    set msoc.test_cc_results ;
    where grade eq 'CHECK' ;
    msg = upcase('W' !! 'ARNING:') ;
    drop msg ;
    put msg= test_group= grade= results= ;
run ;

title 'Report on tests with grade of CHECK' ;
proc print data=check ;
run ;

* Report on tests with grade of PASS*;
data pass ;
    set msoc.test_cc_results ;
    where grade eq 'PASS' ;
    msg = 'NOTE:' ;
    drop msg ;
    put msg= test_group= grade= results= ;
run ;

title 'Report on tests with grade of PASS' ;
proc print data=pass ;
run ;

* Report on exploratory tests *;
data exploratory ;
    set msoc.test_cc_results ;
    where grade eq: '*' ;
    msg = 'NOTE:' ;
    drop msg ;
    put msg= test_group= grade= results= ;
run ;

title 'Report on exploratory tests' ;
proc print data=exploratory ;
run ;


* Close PDF "list" file *;
ods listing;
ods pdf close;

* Cancel program if any tests FAIL *;
data _null_ ;
     set fail nobs=nobs;
    if nobs gt 0 then do ;
        put '** Processing stopped due to tests with a FAIL grade.  Please edit Common-Components. **' ;
          abort cancel ;
     end ;
run ;

/* create metadata file for cc_utility_macvars.sas to use to derive the
   local path(s) to the individual request package subfolder(s) to be used for future
        PRODUCTION requests for this ETL request, excluding Request ID */
   /* Example: %let _ROOT_DPLOCAL= //sentinel/requests/etl22/PhaseB/requests;  */

%macro ds_root_paths (list=dplocal msoc inputfiles sasprograms);
%let header_mprint = %sysfunc(getoption(mprint));
option nomprint;
  %local r;
  proc sql noprint;
    create table dplocal.cc_request_paths
      (Variable char(32), Value char(255))
    ;
  quit;

  %do r=1 %to %sysfunc(countw(&list.,%str( )));
    %let root=%scan(&list.,&r.);
    %let _root=%soc_clean_paths(%superq(_root_&root),0);
    proc sql noprint;
      insert into dplocal.cc_request_paths
      values ("&root", "&_root")
      ;
    quit;
  %end;
  proc sql noprint;
    insert into dplocal.cc_request_paths
    values ("indata", "&QADATA")
    ;
  quit;
option &header_mprint.;
%mend ds_root_paths;
%ds_root_paths;

/* Call macro %signature_end to create signature file and output to msoc folder */
%SIGNATURE_END;
