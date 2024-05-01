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
