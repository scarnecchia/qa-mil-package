/*-------------------------------------------------------------------------------------*\
|  PROGRAM NAME:                                                                        |
|     scdm_sas_log_checker_directory_cc.sas                                             |
|                                                                                       |
|---------------------------------------------------------------------------------------|
|  PURPOSE:                                                                             |
|     The purpose of the program is to pull SAS LOG files from a user-specified         |
|     directory, check each SAS LOG for messages of interest, and produce both summary  |
|     and detailed reports for each LOG file.                                           |
|---------------------------------------------------------------------------------------|
|  PROGRAM INPUT:                                                                       |
|     NA                                                                                |
|                                                                                       |
|  PROGRAM OUTPUT:                                                                      |
|     A single report in .pdf file format output to the specified directory             |
|---------------------------------------------------------------------------------------|
|  CONTACT:                                                                             |
|     Sentinel Coordinating Center                                                      |
|     info@sentinelsystem.org                                                           |
\*-------------------------------------------------------------------------------------*/

*-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-;
*  PLEASE DO NOT EDIT BELOW WITHOUT CONTACTING THE SENTINEL OPERATIONS CENTER           ;
*-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-;

%macro logcheck(logdir=, logdir_out=, logname=, keywords=);

  /*-----------------------------------------------------------------------------------------------------------
    Identify log(s) to read in
    -----------------------------------------------------------------------------------------------------------*/
    
    %let num_logs = 0;
    
    /* Search directory for all log files if no log file is specified */
    %if "&logname" = "%str()" %then %do;
       data _logfiles;
          keep file_name;
          length filref $8 file_name $80; 
          rc = filename(filref, "&logdir"); 
          if rc = 0 then do; 
             dir_id = dopen(filref); 
             rc = filename(filref);  
          end; 
          else do; 
             length msg $200.; 
             msg = sysmsg(); 
             put msg=; 
             dir_id = .; 
             putlog 'ERROR: (Sentinel) Unable to open directory.';
             abort cancel;
          end;
          n_files = dnum(dir_id);
          num_logs=0;
          do i = 1 to n_files; 
             file_name = dread(dir_id, i); 
             file_id = mopen(dir_id, file_name); 
             if file_id > 0 and reverse(compress(file_name)) =: 'gol.' 
              and index(file_name,"log_checker") = 0 then do;
                num_logs=num_logs+1;
                output;
             end;
          end;
          rc = dclose(dir_id);
          call symputx('num_logs',strip(put(num_logs,5.)));
       run;
    
       proc sql noprint;
       select strip(file_name) into :logname separated by ' '
          from _logfiles;
       quit;
    %end;
    %else %do;
      %let num_logs = %sysfunc(countw("&logname",' '));
    %end;
    
  /*-----------------------------------------------------------------------------------------------------------
    If there are no files found abort and put error in the log
    -----------------------------------------------------------------------------------------------------------*/ 
    %if %eval(&num_logs = 0) %then %do;
       data _null_;
         put "ERROR: (Sentinel) No logs located in the specified folder &logdir.";
         abort;
       run;
    %end;  
    
  /*-----------------------------------------------------------------------------------------------------------
    Notes that indicate an issue with the program
    -----------------------------------------------------------------------------------------------------------*/
    %let notes = stopped|converted|uninitialized|division|invalid|missing values|w.d format|repeats of by values|merge statement|;
  %let notes = &notes.mathematical|character values have|disabled|groups are not|will be overwritten|limit set by errors= option reached;
  %if "&keywords." ne "" %then %do;
    %let notes = &notes.|&keywords.;
  %end;

  %let num_notes = %sysfunc(countw(&notes.,"|"));
  %do n = 1 %to &num_notes.;
    %let note&n. =%sysfunc(scan(&notes.,&n.,'|'));
  %end;

  /*-----------------------------------------------------------------------------------------------------------
    Loop through all logs looking for errors, warnings, and notes
    -----------------------------------------------------------------------------------------------------------*/

  %let ls_plus = %eval(%sysfunc(getoption(LS))+10); 
  
    %do f = 1 %to &num_logs.;
        %let logfile = %scan(&logname,&f.,' ');
        data _input_log&f. (keep = logline_number logline logname macro level description);       
        length firstword secondword logline $&ls_plus logname $50 level 3 macro $250 description $25 logline_number 8;      
          infile "&logdir.&logfile.";
      retain macro description;
      input;
          logline_number + 1;
      logname = "&logfile.";
      logline = _infile_;
      firstword = strip(lowcase(scan(_infile_,1,' ')));
      secondword = strip(lowcase(scan(_infile_,2,' ')));
      
      if length(firstword) < 4 then delete;  /*These lines do not contain Errors, Warnings or Notes */
      else if substr(firstword,1,4) not in ("note", "erro", "warn", "mpri") then delete; 

          /*macro available when mprint option on*/
          if substr(firstword,1,6)='mprint' then do;
            macro = substr(firstword, 8,length(firstword)-9);
          end;

      if index(firstword,"warning") and index(secondword,"sentinel") then do;
          description = "Sentinel Warning";
      level = 4;
      end;
      else if index(firstword,"error") and index(secondword,"sentinel") then do;
        description = "Sentinel Error";
      level = 2;
      end;      
      else if prxmatch("/\berror\b|\berror:\b:/oi",firstword) > 0 then do;      
        description = "SAS Error";
      level = 1;
      end;      
      else if prxmatch("/\bwarning\b|\bwarning:\b:/oi",firstword) > 0 then do;      
        description = "SAS Warning";
      level = 3;
      end;
      else if prxmatch("/\bnote\b|\bnote:\b:/oi",firstword) > 0 then do;
        description = "SAS Note";
      end;

      if description = "SAS Note" then do;
        %do n = 1 %to &num_notes.;
        if index(lowcase(logline),"&&note&n..") > 0 and index(lowcase(logline),"data step stopped due to looping") = 0 
                %if "&&note&n.." = "invalid" %then %do;
                    and index(lowcase(logline),"'invalid'") = 0 and index(lowcase(logline),'"invalid"') = 0 and index(lowcase(logline),"(invalid)") = 0 
                %end;
                then level = 5;
      %end;
      end;

      if level in (1, 2, 3, 4, 5) then output;
       run;
  
  %end;
  options mprint symbolgen macrogen;
  /*-----------------------------------------------------------------------------------------------------------
    Save final dataset to logdir_out folder
    -----------------------------------------------------------------------------------------------------------*/  
  data _log_checker;
    set _input_log:;
  run;
  
  /*-----------------------------------------------------------------------------------------------------------
    Sort log checker dataset by level, logname, logline_number
    -----------------------------------------------------------------------------------------------------------*/ 
  proc sort data = _log_checker;
    by level logname logline_number;
  run; 

  ods _all_ close;
  ods pdf file="&msoc./&dpid._scdm_data_qa_mil_logcheck.pdf" style=statdoc;
  title1 "Summary of Log Messages";
  title2 " ";

  proc print data = _log_checker noobs;
    var description logline logname macro;
  run;

  title1;
  title2;

  ods pdf close;
  ods listing;
  
  proc datasets noprint lib = work;
    delete _input_log:;
  quit;

%mend logcheck;

*-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-;
*  End scdm_sas_log_checker_directory_cc.sas                                            ;
*-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-;
