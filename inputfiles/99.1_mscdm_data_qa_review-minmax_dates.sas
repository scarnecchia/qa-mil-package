/*-------------------------------------------------------------------------------------*\
|  PROGRAM NAME:                                                                        |
|     99.1_mscdm_data_qa_review_minmax_dates.sas                                        |
|                                                                                       |
|  QA PACKAGE VERSION: 4.0.3                                                            |
|---------------------------------------------------------------------------------------|
|  PURPOSE: The purpose of the program is create tables with min/max dates of each SCDM |
|     table and calculate a "DP min/max."                                               |
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
* PLEASE DO NOT EDIT BELOW WITHOUT CONTACTING THE SENTINEL OPERATIONS CENTER       ;
*-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-;

%macro Call_MinMax_Dates ;
  /* Call macro to create Min/Max dates for ETL under QA review */
  %MS_MIN_MAX_DATES;

  %if %sysevalf(&syscc le 4) %then %do ;  /* Only execute if no errors detected */
    /* Save existing macro values for DP min/max dates before updating */
    %global DP_MinDate_Old DP_MaxDate_Old ;
    %let DP_MinDate_Old = &DP_MinDate ;
    %let DP_MaxDate_Old = &DP_MaxDate ;

    %put ;
    %put DP Min/Max Dates for ETL currently defined in Common-Components as the production ETL ;
    %put *** DP_MinDate_Old: %sysfunc(putn(&DP_MinDate_Old, date9.)) ;
    %put *** DP_MaxDate_Old: %sysfunc(putn(&DP_MaxDate_Old, date9.)) ;
    %put ;

    /* Update existing macro values for DP min/max dates */
    proc sql noprint ;
      select DP_MinDate format=best12., DP_MaxDate format=best12. 
                into 
             :DP_MinDate, :DP_MaxDate
         from msoc.MinMax_Dates    
      ;
    quit ;  

    %put ;
    %put DP Min/Max Dates for ETL under QA review ;
    %put *** DP_MinDate: %sysfunc(putn(&DP_MinDate, date9.)) ;
    %put *** DP_MaxDate: %sysfunc(putn(&DP_MaxDate, date9.)) ;
    %put ;
  %end ;

%mend Call_MinMax_Dates ;
%Call_MinMax_Dates

*-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-;
* END 99.1_mscdm_data_qa_review_minmax_dates.sas                                        ;
*-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-;
