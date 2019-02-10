/*-------------------------------------------------------------------------------------*\
|  PROGRAM NAME:                                                                        |
|     00.3_scdm_sas_log_checker_directory_cc.sas                                        |
|                                                                                       |
|    MA QA PACKAGE VERSION: 2.1.0                                                       |
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

data _null_;
  call symput('datestamp',put(datepart(datetime()),date9.));
run;

%macro logcheck;

	proc sql;
  	 select module into: tabid trimmed
	 	from infolder.control_flow 
		where cc_table ne "X" and execute_flag = "Y";
  quit;

	%if "%upcase(&tabid.)" = "MIL" %then %do;
		 %let dirname = &msoc.;
	%end;
	%else %do;
		 %let dirname = &dplocal.;
	%end;

  %macro getfnames(loc);
  filename _dir_ "%bquote(&loc.)";

  data filenames(keep=memname);
    dirname=dopen( '_dir_' );
    if dirname > 0 then do;
      count=dnum(dirname);
      do i=1 to count;
        memname=dread(dirname,i);
        output filenames;
      end;
    end;
    rc=dclose(dirname);
  run;

  filename _dir_ clear;

  %mend getfnames;
  %getfnames(&dirname);           

  data logs(keep=fname);
    set filenames;
    fname=strip(memname);
    where index(upcase(memname),"&dt_today..LOG");
  run;

  proc sql noprint;
    select count(distinct fname), fname into : fnum, : fname separated by "*"
    from logs
    ;
  quit;

  %put FILENAMES ===========> &fname. ;
  %put NUMBER OF FILES =====> &fnum.  ;

  %do i=1 %to &fnum;
    %let fn = %scan(&fname,&i,*);
    %let fnami=%scan(%scan(&fname,&i,*),1);
    %let fnam&i=%scan(%scan(&fname,&i,*),1);
    %put FN===================> &fn.;
    %put FNAMI================> &fnami.;

    filename onef "&dirname./&fnami..log";

/*Get info from LOGs*/
    data &fnami.(keep=type message logname where=(message ne ''));
      retain noerr 0;
      length string1 message $200. logname type $50.;
      infile onef pad length=len missover end=eof;
      input @01 string1 $varying200. len;
      logname="&fn.";

      if substr(string1,1,4) ='ERRO' then do;
        message=strip(string1);
        type=compress('ERR'||'OR');
        noerr+1;
      end;

      if substr(string1,1,6) = 'WARNIN' then do;
        message=strip(string1);
        type=compress('WARN'||'ING');
        noerr+1;
      end;

      if substr(string1,1,4) = 'NOTE' then do;
        note1=index(string1,'stopped');
        note2=index(string1,'converted');
        note3=index(string1,'uninitialized');
        note4=index(string1,'Division') ;
        note5=index(string1,'Invalid');
        note6=index(string1,'Missing');
        note7=index(string1,'W.D format');
        note8=index(string1,'repeats of BY values');
        note9=index(string1,'Mathematical');
        note10=index(string1,'MERGE statement');
        note11=index(string1,'Character values have');
        note12=index(string1,'disabled');
        note13=index(string1,'No observations');
        note14=index(string1,'Groups are not');
        note15=index(string1,' 0 observations');
      end;

      array v(15) note1-note15;
      do i=1 to 15;
        if v(i) gt 0 then do;
          message=strip(string1);
          type='NOTE';
          noerr+1;
        end;
      end;

      if eof then do;
        if noerr=0 then do;
        message='NO MESSAGES OF CONCERN IN LOG';
        type='NONE';
        end;
      end;
    run;
   %end;

 /*Put all messages together*/
  data logall;
    set &fnam1
    %do j=2 %to &fnum; &&fnam&j %end;;
  run;
  proc sql;
    create table rep as
    select count(message) as message_no, type, logname
    from logall
    group by logname, type
    ;
  quit;
  data rep1;
    set rep;
    if type='NONE' then message_no=.;
  run;

/* create summary report of log messages */
  ods _all_ close;
  options nonumber;
  ods escapechar="^";
  ods pdf file="&dirname./&dpid._scdm_data_qa_logcheck.pdf" style=statdoc;
  title1 "Summary of Log Messages for Directory &dirname.";
  title2 "Report Run Date: &DateStamp.";
  title3 " ";
  options missing=' ';

  proc report data=rep1 nowd headskip headline missing formchar(2)='_' spacing=2 split='~';
    column logname type message_no;
    define logname / order "FILENAME" width=25 left flow;
    define type / order "MESSAGE TYPE" width=30 left flow;
    define message_no / "NUMBER OF REPORTED MESSAGES" width=40 left flow;
    break after logname / skip;
  run;
  title1 "Detailed Breakdown of Log Messages";
  proc report data=logall nowd headskip headline missing formchar(2)='_' spacing=2 split='~';
    column logname type message ;
    define logname / order "FILENAME" width=25 left flow;
    define type / order "MESSAGE TYPE" width=20 left flow;
    define message / "MESSAGE" width=30 left flow;
  run;
  options missing='-';
  title;
  footnote;

  ods pdf close;
  ods listing;

%mend logcheck;
%logcheck;

*-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-;
*  End 00.3_scdm_sas_log_checker_directory_cc.sas                                       ;
*-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-;
