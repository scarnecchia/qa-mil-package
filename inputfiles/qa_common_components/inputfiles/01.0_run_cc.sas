/****************************************************************************************
*                                      SENTINEL PROGRAM
*****************************************************************************************
* NAME: 01.0_run_cc.sas
*
* PURPOSE: The run_cc program is used to execute the Common Components (CC) for an ETL
*          process 
*
* MAJOR STEPS:
*   1. Execute Common Components code
*   2. Clean up work directory
*
* KEY DEPENDENCIES/CONSTRAINTS:
*   - SAS datasets , infolder.cars, and infolder.fitness
*   - SAS datasets containing ETL-specific metadata from the QA package
*       --> qaresult.qa_cc_metadata, qaresult.all_l1_cont
*   - SAS macros test_sasautos.sas and verify_cc_etl.sas in inputfiles/cc_test
*     subdirectory
*
*----------------------------------------------------------------------------------------
* CONTACT INFO:
*  Sentinel Coordinating Center
*  info@sentinel.org
*--------------------------------------------------------------------------------------*/
/* Check for existence of partitioning macrovariables and set if they exist */
%macro macVarExists(name);
  %let exist = 0;
  proc sql noprint;
    select count(*) into :exist 
    from qaresult.qa_cc_metadata (where=(lowcase(variable)=lowcase("&name.")))
    ;
  quit;
  %if &exist. %then %do;
    %global &name;
    proc sql noprint;
      select value into :%superq(name) trimmed
      from qaresult.qa_cc_metadata (where=(lowcase(variable)=lowcase("&name.")))
    ;
  quit;
  %end;
%mend;

%macVarExists(sascmd);
%macVarExists(sasconnect);
%macVarExists(sasgrid);
%macVarExists(gridsrv);
%macVarExists(numpartitions);
%macVarExists(partable);

/* Condition for partitionedData */
%global partitionedData;
%macro partition_test;

  %put =====> MACRO CALLED: partition_test;

  %if ^%symexist(NUMPARTITIONS) or %str("&numpartitions.") eq %str("") or %str("&numpartitions.") le %str("1") %then %do;
    %let partitionedData = N;
  %end;
  %else %do;
    %let partitionedData = Y;
  %end;

%mend;

%partition_test;

%macro run_cc;

    %put =====> MACRO CALLED: run_cc;

  %*-------------------------------------------------------------------------------------------- *;
    %* 1- Execute Common Components                                                                *;
    %*-------------------------------------------------------------------------------------------- *;

    %*  Compile CC test macros                                                                     *;
    %inc "&INFOLDER./cc_test/verify_cc_etl.sas" /nosource2 ;
    %inc "&INFOLDER./cc_test/cc_signature_file.sas" /nosource2 ;

  %* execute main CC program - note this program generates its own log and saves to MSOC         *;
    %include "&infolder./cc_test/01.0_cc_test.sas" /nosource2;

  %* reroute to default                                                                          *;
    proc printto; run;

    %put NOTE: ********END OF MACRO: run_cc******** ;

%mend run_cc;

%run_cc;


*** ----------------------------------- END PROGRAM ---------------------------------------------- ***;
