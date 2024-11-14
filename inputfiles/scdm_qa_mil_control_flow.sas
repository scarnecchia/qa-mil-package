/*--------------------------------------------------------------------------------------\
|  PROGRAM NAME:                                                                        |
|     00.0_scdm_control_flow.sas                                                        |
|---------------------------------------------------------------------------------------|
|  PURPOSE:                                                                             |
|     The purpose of this program is to define selective and sequential execution       |
|     of QA MIL modules in the program 00.0_scdm_mil_data_qa_review_master_file.sas.    |
|---------------------------------------------------------------------------------------|
|  MAJOR STEPS PERFORMED BY THE PROGRAM:                                                |
|                                                                                       |
|    0- Perform setup for this macro                                                    |
|    1- Ensure expected ETL number matches with ETL number in MIL table dataset label   |
|    2- Clean up control flow dataset to enable safe and consistent querying            |
|    3- Retrieve modules explicitly chosen to run (i.e. where execute_flag = y)         |
|    4- Ensure that all the necessary modules are run given dependencies                |
|         a) Modules for optional tables are only selected if defined in CC             |
|         b) If any utilization modules are selected, all utilization modules           |
|            will be run                                                                |
|    5- Set up macro variable lists for processing each module                          |
|    6- Loop through and execute each module                                            |
|    7- Call request-level "signature file consolidation" and "log checker" macros      |
|                                                                                       |
|---------------------------------------------------------------------------------------|
|     DEPENDENCIES/CONSTRAINTS/CAUTIONS                                                 |
|       This macro is to be called by 00.0_scdm_data_mil_qa_review_master_file.sas.     |
|       Please refer to the master program for details.                                 |
|                                                                                       |
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
%global end_qa tabid table;

%macro qa_mil_control_flow;
  
    %* overall processing macros;
    %let end_qa=0;

    %* Include standard and utility macros;    
    %include "&INFOLDER.scdm_qa_mil_standard_macros.sas" /nosource2;
    %include "&INFOLDER.scdm_qa_mil_formats.sas" /nosource2;
    %include "&INFOLDER.scdm_sas_log_checker_directory_cc.sas" /nosource2;    
    %include "&INFOLDER.scdm_qasignaturerequest.sas" /nosource2; 

    %*   Checks ETL number and PHASE for consistency with CCR/CCA request;
    %if %unquote(&ETL.&phase) ne %unquote(&_ETL.B) %then %do;
        data _null_;
            putlog 80*'!';
            putlog ' ';
            putlog "==> MASTER_FLOW macro is aborting due to an issue with the expected ETL #/Phase.";
            putlog ' ';
            putlog '==> Ensure that your site is pointing to the correct version of CC for the Phase A ';
            putlog "    SCDM tables used to create the MIL table under review. ";
            putlog ' ';
            putlog 80*'!';
            putlog ' ';
        run;
        %abort cancel 99 ;
    %end ;

    %kill_directory (kill_list=dplocal msoc);
    data msoc.etl_version;
        length DP $6;
        dp=upcase("&dpid.");
        ETL=&ETL.;
    run;

    %* read-in control flow input file ;
    data control_flow;
        infile "&INFOLDER.control_flow.csv" dlm=',' dsd truncover firstobs=2;
        informat module $5. ;
        informat execute_flag $1. ;
        informat sascode $45. ;
        informat cc_table $12.;
        informat seqno best.;
        informat module_cat $10.;
        informat module_util $1. ;
        format module $5. ;
        format execute_flag $1. ;
        format sascode $45. ;
        format cc_table $12.;
        format seqno best. ;
        format module_cat $10.;
        format module_util $1. ;
        input module :$5. execute_flag :$1. sascode :$45. cc_table :$12.
              seqno :8. module_cat :$10. module_util :$1.;
        /* standardize capitalization */
        module = lowcase(module) ;
        execute_flag = lowcase(execute_flag) ;
        unique_id = lowcase(unique_id);

    run;

    proc sort data=control_flow;
        by seqno;
    run;

    %* ensure that the site has populated all expected table names in the master file;
    %macro check_missing_tablenames;
        %local t tabct abortct tablelist;
        %let tabct=0;
        %let abortct=0;

        proc sql noprint;
          select cc_table
               , count(*)
          into :tablelist separated by "*"
             , :tabct trimmed
          from control_flow (where=(lowcase(cc_table) ne 'x' and execute_flag='y'));
        quit;

        %do t=1 %to &tabct.;
            %let table=%scan(&tablelist.,&t.,%str(*));
            %let table=%qleft(%qtrim(&table));
            %if %length(%superq(&table)) = 0 %then %do;
                %let abortct=%eval(&abortct. + 1);
                data _null_;
                    put 70*'!';
                    put ' ';
                    put 'ERR'"OR: SCDM &table. name is expected at the site, but ";
                    put "   is defined by DP. All the SCDM tables defined by SOC in the ";
                    put "   inputfiles/control flow.csv file should be present in the ";
                    put "   directory and named in the master program. ";
                    put ' ';
                    put 70*'!';
                run;
            %end;
        %end;

        %if "&abortct." ne "0" %then %do;
            data _null_;
                put 70*'!';
                put ' ';
                put 'ERR'"OR: MASTER_FLOW macro is aborting because an expected SCDM table ";
                put "   name was not defined by your site for the ETL under review. ";
                put ' ';
                put 70*'!';
           run;
           %abort cancel 99;
        %end;

    %mend check_missing_tablenames;
    %check_missing_tablenames;

    %* ensure that the site has populated expected table names in the master file;
    %macro check_extra_tablenames;
        %local t tabct abortct tablelist;
        %let tabct=0;
        %let abortct=0;

        proc sql noprint;
          select cc_table
               , count(*)
          into :tablelist separated by "*"
             , :tabct trimmed
          from control_flow (where=(lowcase(cc_table) ne 'x' and execute_flag='n' and module_cat ne ""));
        quit;

        %if %eval(&tabct. ge 1) %then %do;
            %do t=1 %to &tabct.;
                %let table=%scan(&tablelist.,&t.,%str(*));
                %let table=%qleft(%qtrim(&table));
                %if %length(%superq(&table)) ne 0 %then %do;
                    %let abortct=%eval(&abortct. + 1);
                    data _null_;
                        put 70*'!';
                        put ' ';
                        put 'ERR'"OR: SCDM &table. name is defined by DP, but not expected";
                        put "   at the site. Only the SCDM tables defined by SOC in the ";
                        put "   inputfiles/control_flow.csv file should be present in the ";
                        put "   directory and named in the master program. ";
                        put ' ';
                        put 70*'!';
                    run;
                %end;
            %end;

            %if "&abortct." ne "0" %then %do;
                data _null_;
                    put 70*'!';
                    put ' ';
                    put 'ERR'"OR: MASTER_FLOW macro is aborting because an unexpected SCDM table";
                    put "   name was defined by your site for the ETL under review.";
                    put ' ';
                    put 70*'!';
                run;
                %abort cancel 99;
            %end;
        %end;
    %mend check_extra_tablenames;
    %check_extra_tablenames;

    %* Create separate control_flow dataset for CC;
    data msoc.cc_control_flow;
        set control_flow;
        where lowcase(cc_table) ne 'x';
    run;

    data msoc.control_flow_3;
         set control_flow(where=(execute_flag = 'y'));
         by seqno;
    run;

    %local nmod module_list sascode_list;
    proc sql noprint;
        select   module
               , sascode
        into  :module_list separated by ' '
            , :sascode_list separated by '~'
        from msoc.control_flow_3 where upcase(cc_table) eq "X"
        order by seqno;
    quit;
    
    %* Loop through and execute each module in sequence;
    %local z module sascode;
    %*Loop through and execute each module in sequence ;
    %do z = 1 %to %sysfunc(countw(&module_list));

         %kill_directory (kill_list=work);

         %if %length(&module_list) > 0 %then %let module = %scan(&module_list., &z.);
         %else %let module = ;

         %if %length(&sascode_list) > 0 %then %let sascode = %scan(&sascode_list., &z.,~);
         %else %let sascode = ;

         %if %sysfunc(lengthc(&module.)) = 3 %then %let tabid=&module.;
         %else %let tabid=;

        %if &end_qa.=0 %then %do;

            data _null_;
                put 75*'-';
                put ' ';
                put "==> Begin Execution of module: &module., sascode: &sascode..sas";
                put "==> This is module &z of &nmod modules selected to execute";
                put ' ';
                put 75*'-';
              run;

            %* Start time of module;
            %let &module.start = %sysfunc(datetime());

            %include "&INFOLDER.&sascode..sas";

            %if %sysevalf(&syscc. gt 4) %then %do ; %* begin-if execute if last module failed;
      
                %* Print out useful debug info and abort ;
                data _null_;
                    put 70*'!';
                    put " ";
                    put "Post-Module Check 1: System error detected. Process will abort.";
                    put "==> Check program log qa_package.log for details.";
                    put " ";
                    put 70*'!';
                run;
            %end ;%* end-if execute if last module bombed ;

            %else %do;
                %let stoptime = %sysfunc(datetime());
                %let stoptimediff = %sysevalf(&stoptime-&&&module.start);
                %let hour = %sysfunc(hour(&stoptimediff));
                %let minute = %sysfunc(minute(&stoptimediff));
                %let second = %sysfunc(ceil(%sysfunc(second(&stoptimediff))));
                /* Create Signature File */
                data signature;
                   DP="&DP.";
                   ReqID="&ReqID.";
                   ProjID="&ProjID.";
                   WPType="&WPType.";
                   WPID="&WPID.";
                   DPID="&DPID.";
                   VerID="&VerID.";
                   QAVer="&QAVer.";
                   SCDMVer="&SCDMVer.";
                   Module="&MODULE.";
                   OSABBR="&sysscp.";
                   OSNAME="&sysscpl.";
                   SASVersion="&sysver.";
                   SASVersionLong="&sysvlong.";
                   RunType="&sysenv.";
                   NCPU="&sysncpu.";
                   StartTime=put(&&&MODULE.START.,e8601dz.);
                   StopTime=put(&stoptime,e8601dz.);
                   Seconds="%sysevalf(&stoptime-&&&module.start)";
                   length RunTime $20;
                   RunTime=cat("&hour", ' h ', 
                                     "&minute", ' m ', 
                                     "&second", ' s');
                   output;
                run;
                proc transpose data=signature out=msoc.&MODULE._signature (rename=(_NAME_=Variable COL1=Value));
                   var _ALL_;
                   attrib _ALL_ label = ' ';
                run;
            %end;
        %end; %* end statemet for end_qa=0;

        %else %do; %* if end_qa =1;
            data _null;
                put 75*'!';
                put ' ';
                put "&module. module has produced data check flags that";
                put "require the QA package to abort. Process will abort after creating a master";
                put "signature file and running the log checker.";
                put ' ';
                put 75*'!';
            run;
            %let z=99;
        %end; %* end statemet for end_qa=0;

    %end; %* end loop z;


    %* If qa did not abort and masking specified in the master program file, call the results masking program      *;
    %if &z.<99
    %then %do;  
        %if "%upcase(&tabid.)" = "MIL" %then %do;
            %move_l3;
        %end;
    %end;

 
    %* Call the SCDM Snapshot program                                                    *;
        %snapshot_run;

    %* If specified in the master program file, call the qa_common_components program      *;
    %if %lowcase(&execute_CC.)=y %then %do;
        %cc_run
    %end;

%mend qa_mil_control_flow;


proc printto log="&msoc.qa_mil_package.log" new;
run;

%qa_mil_control_flow;

proc printto;
run;

%logcheck(logdir=&MSOC, logdir_out=msoc);

*-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-;
*  End scdm_control_flow.sas                                                            ;
*-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-;

