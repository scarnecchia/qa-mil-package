/*--------------------------------------------------------------------------------------\
|  PROGRAM NAME:                                                                        |
|     00.0_scdm_control_flow.sas                                                        |
|                                                                                       |
|  MIL/MIS QA PACKAGE VERSION: 2.1.0                                                    |                                                                    |
|---------------------------------------------------------------------------------------|
|  PURPOSE:                                                                             |
|     The purpose of this program is to define selective and sequential execution       |
|     of QA MIL modules in the program 00.0_scdm_mil_data_qa_review_master_file.sas.    |
|---------------------------------------------------------------------------------------|
|  MAJOR STEPS PERFORMED BY THE PROGRAM:                                                |
|                                                                                       |
|    0- Perform setup for this macro                                                    |
|                                                                                       |
|    1- Ensure expected ETL number matches with ETL number in MIL table dataset label   |
|                                                                                       |
|    2- Clean up control flow dataset to enable safe and consistent querying            |
|                                                                                       |
|    3- Retrieve modules explicitly chosen to run (i.e. where execute_flag = y)         |
|                                                                                       |
|    4- Ensure that all the necessary modules are run given dependencies                |
|         a) Modules for optional tables are only selected if defined in CC             |
|         b) If any utilization modules are selected, all utilization modules           |
|            will be run                                                                |
|                                                                                       |
|    5- Set up macro variable lists for processing each module                          |
|                                                                                       |
|    6- Loop through and execute each module                                            |
|                                                                                       |
|    7- Call request-level "signature file consolidation" and "log checker" macros      |
|                                                                                       |
|---------------------------------------------------------------------------------------|
|     DEPENDENCIES/CONSTRAINTS/CAUTIONS                                                 |
|       This macro is to be called by 00.0_scdm_data_qa_review_master_file.sas.         |
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

%macro MASTER_FLOW ;
/* MASTER FLOW Step 0 - Perform setup for this macro */

   /* Include Macros and Formats */
  %include "&INFOLDER.00.1_scdm_standard_macros.sas" /nosource2;
  %include "&INFOLDER.00.2_scdm_formats.sas" /nosource2;        

  %put &syscc.;

   *Clean work library;
  proc datasets lib=work nolist kill; quit; run;

   /*Initialize end_qa*/
  %let end_qa = 0;

   /* Capture and format run date so that program logs always sort in ascending order */
   /* Note: format date as yymmdd, without any delimiters, for log checker parsing */
  %local dt_today;
  %let dt_today = %sysfunc(putn("&sysdate."d, yymmddn8.));   
  
 /* Setup Log */
  proc sql;
  	 select module into :mi trimmed
	 	 from infolder.control_flow 
		  where cc_table ne "X" and execute_flag = "Y";
  quit;

  %if "&mi." = "mil" %then %let logdir = msoc; 
  %else %let logdir = dplocal;

  filename runlog "%superq(&&logdir)/scdm_data_qa_master_&dt_today..log";

  proc printto log=runlog new;
  run; quit;

/***************************************************************************/
/*   Checks ETL number and PHASE for consistency with CCR/CCA request      */	
/***************************************************************************/
  data _null_;
    putlog 75*'*';
    putlog ' ';
    putlog "=====> Current Production ETL/Phase from CC: &ETL.&phase.";
    putlog ' ';
    putlog "=====> Expected ETL/Phase for this QA review: &ETL.B";
    putlog ' ';
    putlog 75*'*';
    putlog ' ';
  run;

  %if %unquote(&_ETL.&phase) ne %unquote(&ETL.B) %then %do;
    data _null_;
      putlog 80*'!';
      putlog ' ';
      putlog "==> MASTER_FLOW macro is aborting due to an issue with the expected ETL #/Phase.";  
      putlog ' ';
      putlog ' ';
      putlog '==> Ensure that your site is pointing to the correct version of CC for the Phase A ';
      putlog "    SCDM tables used to create the MIL table under review. ";
      putlog ' '; 
      putlog 80*'!';
      putlog ' '; 
    run; 
    %abort cancel 99 ;      
  %end ;

  /*Create ETL Version table*/
  %local ETL_VersionTable;
  %if %sysfunc(exist(&logdir..etl_version,data)) %then %do; /* begin if etl_version ds exists */
    %put ;
    %put ==> An ETL_version table already exists and will be reviewed to;      
    %put ==> ensure that the ETL in the ETL_version table is equal to the expected ETL;
    %put ;              
    proc sql noprint;
      select etl into :ETL_VersionTable trimmed
      from &logdir..etl_version 
      ;
    quit;
    %put ;
    %put ====> CURRENT ETL: &ETL. ;
    %put ====> Expected ETL: &_ETL. ;        
    %put ====> ETL from ETL_Version table in this QA MIL package MSOC folder: &ETL_VersionTable.;        
    %put ;

    %if &ETL.=&ETL_VersionTable. %then %do;
      %put ;        
      %put ==> ETL Versions match and the program will continue;
      %put ==> HOWEVER, unless otherwise specified in the master program, all ;
      %put ==>  existing SAS datasets in the local output directories ('dplocal','msoc');
      %put ==>  will be deleted for data quality assurance purposes ;  
      %put ;        
    %end; 
 
    %else %do; 
      data _null_;
        put 70*'!';              
        put ' ';        
        put 'ERR'"OR: MASTER_FLOW macro is aborting to avoid overwriting existing datasets";
        put "       from a different ETL version";
        put ' ';
        put "==> Check program log &&logdir..scdm_data_qa_master_&dt_today..log for details." ;          
        put ' ';           
        put 70*'!';
      run; 
      %abort cancel 99;
    %end;
  %end;  /* end if etl_version ds exists */       

  %kill_directory (kill_list=dplocal msoc); 

  data &logdir..etl_version;  
    ETL="&ETL.";
  run;   
      
  title 'ETL Version undergoing QA review' ;
  title2 "Job executed on &sysdate at &systime" ;
  proc print data=&logdir..etl_version;
  run;        
  title ; 
 

/***************************************************************************/
/*   Checks (1, 2, 3) prior to Module runs	                                */	
/***************************************************************************/
/*1. Include check to ensure MIL and MIS never queried together 
    during single package run*/
	 proc sql noprint;
		  select count(module)
		       , count(cc_table)
			      , lowcase(cc_table)
		  into :Nmod trimmed, 
		       :Ncctable trimmed,
			      :querytable trimmed			 
	  	from infolder.control_flow
		  where upcase(execute_flag) eq "Y" and upcase(cc_table) ne "X"
    ;
	 quit;

  %if &Nmod. gt 1 | &Ncctable. gt 1 %then %do;
	   data _null_;
      putlog 80*'!';
      putlog ' ';
      putlog "==> MASTER_FLOW macro is aborting...a fatal problem occured in CONTROL_FLOW";      
      putlog "==> The package is querying more than one table";
      putlog ' '; 
      putlog 80*'!';
    run; 
    %abort cancel 99 ;      
  %end ;

/*2.If only 1 table is found include check for MIS variables if MIL table specified*/
 /*If MIS variable is found in MIL table, abort the process*/ 
  %else %do; 
    %if "&querytable." eq "miltable" %then %do;
  	   proc sql noprint;
		      select variable into :mis_vars separated by " "
		      from infolder.lkp_all_l1 a
		      where upcase(a.Tabid) = "MIS" and 15 <= input(varid, 8.0) <= 25
        ;
      quit; 
	     %let misflag = 0; /*initialize*/
	     data _null_;
		      set qadata.&miltable.;
		      if _n_ = 1 then do;
		 	      count = 0;
		        dsid = open("qadata.&miltable.");
		 	  %do i = 1 %to %sysfunc(countw(&mis_vars.));
		 		   %let varname = %scan(&mis_vars., &i.);
		 		     if varnum(dsid,"&varname") > 0 then do;
					       count = count + 1;
				        call symputx("misflag", count);
				      end;
		    %end;
			       rc= close(dsid);
		      end;
	       drop rc dsid;	
	     run;
	     %IF %EVAL(&misflag.) GT 0 %THEN %DO;
	  	    data _null_;
      	   putlog 90*'!';
      	   putlog ' ';
      	   putlog "==> MASTER_FLOW macro is aborting...a fatal problem occured in MIL TABLE";      
      	   putlog "==> The &miltable. contains &misflag. MI support variables";
		        putlog "==> Please include the correct table. QA process is aborting.";
      	   putlog ' '; 
      	   putlog 90*'!';
    	   run; 
        %abort cancel 99 ;  
	     %end;	
    %end; /*end if querytable is MIL*/
  %end; /*end of #2*/	

/*3.include logic to remove MSOC libname assignment from package that runs against MIS*/
  %if "&querytable." eq "mistable" %then %do;
 	  libname msoc clear;
  %end;

/*Create licensed product file*/
  %let comps=base*stat*graph*%nrstr(acc-pc files)*ets*af*iml*connect*oracle*odbc*teradata;
  %put =====> comps = %unquote(&comps);
  %licensed

  %put &syscc.;
  %if %sysevalf(&syscc.>4) %then %do;
    data _null_;
      putlog 80*'!';
      putlog ' ';
      putlog "==> MASTER_FLOW macro is aborting...a fatal problem occured in MASTER_FLOW";      
      putlog "==> Check program log &&&logdir..scdm_data_qa_master_&dt_today..log for details.";
      putlog ' '; 
      putlog 80*'!';
    run; 
    %abort cancel 99 ;      
  %end ;
            
/* MASTER_FLOW Step 2 - Clean up control flow dataset */
  data control_flow ;
    set infolder.control_flow ;
 /* standardize capitalization */
    module = lowcase(module) ;
    execute_flag = lowcase(execute_flag) ;
    module_cat = lowcase(module_cat) ;
    module_util = lowcase(module_util) ;    
  run;   

  proc sort data=control_flow;
    by seqno;
  run;

/* MASTER_FLOW Step 3 - Retrieve modules explicitly chosen to run */
  proc sql noprint;
    create table control_flow_1 as
    select *
    from control_flow
    where lowcase(execute_flag) eq 'y'
    order by seqno 
    ;
  quit;
  
/* MASTER_FLOW Step 4 - Ensure that the necessary modules are run given dependencies */
  %local Core Util;  
  proc sql noprint;  
    select case when max(module_cat= 'core') then 1 else 0 end as Core
         , case when max(module_util= 'y') then 1 else 0 end as Util 
    into :Core
       , :Util            
    from control_flow_1 
    ;
  quit;
  
  data control_flow_2;
    set control_flow;
    by seqno;
    if &Core eq 1 then do;
      if module in ('l1', 'l2', 'l3') then do ;
        if lowcase(execute_flag) eq 'y' then do;
          output;
        end;
      end;
    end;
    if &Util eq 1 then do;
      if module_util = 'y' then do;
        output;
      end;
    end; 
  run;
  
  data &logdir..control_flow_3;
    set control_flow_1
        control_flow_2;
    by seqno;
    if first.seqno;
    retain module_required 'y';
  run;

 /* Redirect listing of control flow info to its own log file */
  options orientation=landscape linesize=max pagesize=75;
  proc printto print="&&&logdir..module_execution_plan_&dt_today..log";
  run;

  title "List of QA Modules that will be executed for this Request -- job executed on &sysdate at &systime";  
  title3 'NOTE: Modules for optional tables are only selected if defined in common-components';
  title4 "NOTE: If any 'utilization modules' are selected, all utilization modules will be selected";
  title5 "NOTE: If any 'core' modules are selected, modules l1_l2 and dates will be selected";

  proc print data=&logdir..control_flow_3;
    var module sascode module_cat module_util cc_table seqno;
  run;
  title;

  /* Reset listing */
  proc printto;
  run;  
  options orientation=portrait linesize=100 pagesize=50;

/* MASTER_FLOW Step 5 - Set up macro variable lists for processing each module */
  %local nmod module_list sascode_list;

  proc sql;
    select module
         , sascode
    into :module_list separated by ' '
       , :sascode_list separated by '~'
    from &logdir..control_flow_3 where upcase(cc_table) eq "X"
    order by seqno 
    ;
  quit;

  %let nmod=&sqlobs.;
  %put &module_list &sascode_list.;

  data _null_;
    put 70*'-';
    put "Note: For module execution details, see module specific log files";          
    put 70*'-';
    run; 


/* MASTER_FLOW Step 6 - Loop through and execute each module in sequence */
  %local z module sascode;
  %do z = 1 %to &nmod.;
    %kill_directory (kill_list=work);
    %let module = %scan(&module_list., &z.);
    %let sascode = %scan(&sascode_list., &z.,~);
    /*%let table = %scan(&table_list, &z, %str( ));*/

    %if %sysfunc(lengthc(&module.)) = 3 %then %let tabid=&module.;
    %else %let tabid=;

    %if &end_qa.=0 %then %do;
      proc printto;
      run;    
      data _null_;
        put 75*'-';
        put ' ';
        put "==> Begin Execution of module: &module., sascode: &sascode..sas";          
        put "==> This is module &z of &nmod modules selected to execute";
        put ' ';            
        put 75*'-'; 
      run; 
      proc printto log="&&&logdir..&module._&dt_today..log" new;
      run;                 
      %SIGNATURE_BEGIN(&module)   
 
      %inc "&INFOLDER.&sascode..sas" /source2 ;            

      %if %sysevalf(&syscc. gt 4) %then %do ; /* begin-if execute if last module failed */ 
     
     /* Reset printto locations -- this method used to circumvent any file lock conflicts */     
        proc printto log=log; 
        run;     
        proc printto print=print;
        run;        

       /* Save useful debug info */        
        %local last_module;
        %let last_module = %upcase(%scan(&module_list, %eval(&z - 0), %str( )));

       /* Run log checker */
        %_disable_syntax_checks;  /* disable syntax checks so that log checker executes*/
        %include "&INFOLDER.00.3_scdm_sas_log_checker_directory_cc.sas" /nosource2;        
        %_enable_syntax_checks ;  /* enable syntax checks for safety*/
        
       /* Print out useful debug info and abort */
        data _null_;
          put 70*'!';
          put " ";
          put 'ERR'"OR: Macro MASTER_FLOW is aborting ...";
          put "==> Check program log &&&logdir..&last_module._&dt_today..log for details.";  
          put " ";
          put 70*'!';
        run;  
      %end ;  /* end-if execute if last module bombed */       

      %else %do;
        %SIGNATURE_END(&module)          
          proc printto;
          run ;    
      %end; 
    %end;

    %else %do; /* if end_qa =1 */     
      %local last_module;
      %let last_module = %upcase(%scan(&module_list, %eval(&z - 1), %str( )));
      data _null;
        put 75*'!';
        put ' ';
        put 'ERR'"OR: The &last_module. module has produced data check flags that";
        put "         require the QA package to abort after creating a master"; 
        put "         signature file and running the log checker.";
        put ' ';
        put 75*'!';
      run;
      %let z=99; 
    %end;
  %end; /* end loop z */

/* MASTER_FLOW Step 7 - Call request level signature file consolidation macro and log checker */
 /* Note: clear log and print files to avoid file lock issues */
  proc printto log=log;
  run;
  proc printto print=print;
  run;

  %if &end_qa.=0 %then %do;
  	 %if "%upcase(&tabid.)" = "MIL" %then %do;
		    %move_l3;
	   %end;
    data _null;
      put 75*'-';
      put ' ';
      put "==> The macro MASTER_FLOW has run the modules selected without any fatal problems detected." ;
      put "==> We will now wrap up by creating a master signature file and running the log checker." ;
      put ' ';
      put 75*'-';
    run;	
  %end;
    
  %local rc1 ;
  *%include "&INFOLDER.00.4_scdm_qasignaturerequest.sas"/nosource2;
  %let rc1 = &syscc. ;
 
  %let syscc = 0 ; /* reset rc to ensure that log checker can run */
  %_disable_syntax_checks ;  /* disable syntax checks so that log checker executes*/
  %local rc2 ;
  %include "&INFOLDER.00.3_scdm_sas_log_checker_directory_cc.sas" /nosource2;      
  %let rc2 = &syscc ;
  %_enable_syntax_checks ;  /* enable syntax checks for safety*/

  %if &rc1 le 4 and &rc2 le 4 and &end_qa eq 0 %then %do ;
    data _null_;
      put 75*'-';
      put ' ';
      put '==> The macro MASTER_FLOW has run the modules selected without any fatal problems detected';
      put '==> and successfully created a master signature file and run the log checker!'; 
      put ' ';
      put 75*'-';
    run;
  %end;

  %else %if &end_qa.=1 %then %do;
    data _null_;
      put 75*'!';
      put ' ';
      putlog 'ERR' "OR: The macro MASTER_FLOW has terminated early due to data check failures";
      put ' ';
      put '==> The macro MASTER_FLOW will now abort ...';
      put "==> Check &logdir..&dpid._scdm_data_qa_logcheck.pdf for details.";
      put ' ';
      put 75*'!';
    run;
    %abort 99;
  %end;

  %else %do ;
     data _null_;
        put 75*'!';
        put ' ';
        put '==> The macro MASTER_FLOW has run the modules selected without any fatal problems detected.';
        put '==> HOWEVER, there was a fatal problem with either the master signature and/or log checker';
        put '==> program(s) that ran after the modules were run.';
        put ' ';
        put '==> The macro MASTER_FLOW will now abort...';
        put "==> Check program log &sasprograms.00.0_scdm_data_qa_review_master_file.log for details.";
        put ' ';
        put 75*'!';
      run;
    %abort 99;
  %end;

  %endmac: 

%mend MASTER_FLOW;

*-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-;
*  End 00.0_scdm_control_flow.sas                                                       ;
*-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-;
