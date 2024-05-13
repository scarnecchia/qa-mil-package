
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
/*-------------------------------------------------------------------------------*/
/* END ==> %remove_labels                                                        */
/*-------------------------------------------------------------------------------*/

/*********************************************************************************/
/* Module Level Signature File macro for QA                                      */
/*********************************************************************************/
%MACRO SIGNATURE_BEGIN;
  /*Signature file start code*/
  %global snapshot_start snapshot_stop;
  %global start;

  data _NULL_;
    temp=DATETIME();
    call symput("START",temp);
    call symput('STARTDATE',put(datepart(temp),date9.));
    call symput('STARTTIME',put(timepart(temp),time4.));
  run;
%MEND SIGNATURE_BEGIN;

%MACRO SIGNATURE_END;

/*Signature file end code*/
data _NULL_;
   temp=DATETIME();
   seconds=temp-&snapshot_start.;
   hours=int(seconds/3600);
   minutes=int((seconds-hours*3600)/60);
   seconds2=int((seconds-hours*3600-minutes*60));
   call symput("STOP",temp);
   call symput('hours',put(hours,4.0));
   call symput('minutes',put(minutes,2.0));
   call symput('seconds2',put(seconds2,2.0));
   call symput('seconds',put(seconds,12.0));
run;
/*Create signature file*/
data signature;
   DP="&DP.";                                    
   ReqID="&ReqID.";
   ProjID="&ProjID.";
   WPType="&WPType.";
   WPID="&WPID.";
   DPID="&DPID.";
   VerID="&VerID.";
   SnapshotVer="&SnapshotVer."; 
   SCDMVer="&SCDMVer."; 
   OSABBR="&sysscp.";
   OSNAME="&sysscpl.";
   SASVersion="&sysver.";
   SASVersionLong="&sysvlong.";
   RunType="&sysenv.";
   format StartTime StopTime datetime21.2; 
   StartTime=trim(left("&START."));                                
   StopTime=trim(left("&STOP."));
   Seconds=trim(left("&Seconds.")); 
   format RunTime $20.; 
   RunTime=strip("&hours. h &minutes. m &seconds2. s"); 
   output;
run;

proc transpose data=signature out=msoc.snapshot_signature (rename=(_NAME_=Variable COL1=Value));
   var _ALL_;
run;

%remove_labels(msoc,snapshot_signature);
%MEND SIGNATURE_END; 

