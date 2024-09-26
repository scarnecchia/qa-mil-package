/*********************************************************************************/
/* START ==> %remove_labels                                                      */
/*********************************************************************************/
/*  Used to delete all variable labels from any dataset                          */
/*-------------------------------------------------------------------------------*/
%macro remove_labels(lib, ds);
  proc datasets nolist lib=&lib. memtype=data;
    modify &ds.;
    attrib _all_ label=' ';
  quit;
%mend remove_labels;

/*********************************************************************************/
/* START ==> %kill_directory                                                     */
/*********************************************************************************/
/*  Deletes all existing SAS datasets if {dir}=y in Master program               */
/*-------------------------------------------------------------------------------*/
%macro kill_directory (kill_list=);
  %local k;
  %do k=1 %to %sysfunc(countw(&kill_list.));
    %let dir=%scan(&kill_list.,&k.);
    %let kill=&&kill_dir_&dir.;
    %put &kill;
    %if %lowcase(&kill.)=%str(y) %then %do;
      proc datasets kill lib=&dir. memtype=data nowarn nolist nodetails;
      quit;
    %end;
  %end;
%mend kill_directory;
/*-------------------------------------------------------------------------------*/
/* END ==> %kill_directory                                                       */
/*-------------------------------------------------------------------------------*/


/*********************************************************************************/
/* START ==> %timestamp                                                          */
/*********************************************************************************/
/*  Used to record module execution date and time                                */
/*-------------------------------------------------------------------------------*/
%macro timestamp(parm);
  %put ** &parm. date: %sysfunc(putn(%sysfunc(today()),worddate.));
  %put ** &parm. time: %sysfunc(putn(%sysfunc(time()),tod.));
  %put;
  %** if a parm is passed, then save the time;
  %if &parm ne %then %do;
    %** set as global parm;
    %global &parm;
    %** set value to current time;
    %let &parm=%sysfunc(datetime());
  %end;
%mend timestamp;
/*-------------------------------------------------------------------------------*/
/* END ==> %timestamp                                                            */
/*-------------------------------------------------------------------------------*/

/*********************************************************************************/
/* START ==> %timereport                                                         */
/*********************************************************************************/
/*  Used to calculate duration of module execution                               */
/*-------------------------------------------------------------------------------*/
%macro timereport(start,end);
   data _null_;
     temp=datetime();
     seconds=&end.-&start.;
     hours=int(seconds/3600);
     minutes=int((seconds-hours*3600)/60);
     seconds2=int((seconds-hours*3600-minutes*60));
     call symput('hours',put(hours,4.0));
     call symput('minutes',put(minutes,2.0));
     call symput('seconds',put(seconds2,2.0));
   run;

  data _null_;
    putlog 70*'=';
    putlog " Total run time was &hours. h &minutes. m &seconds. s";
    putlog 70*'=';
  run;
%mend timereport;
/*-------------------------------------------------------------------------------*/
/* END ==> %timereport                                                           */
/*-------------------------------------------------------------------------------*/
