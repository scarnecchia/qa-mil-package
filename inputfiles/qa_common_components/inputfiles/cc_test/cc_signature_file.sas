/****************************************************************************************
*                                      SENTINEL MACROS
*****************************************************************************************
*   SAS macros for creating a package signature file containing runtime metadata for
*   documentation and troubleshooting
*
*   List of macros included in module:
*     - REMOVE_LABELS: Used to delete all variable labels from any dataset
*     - SIGNATURE_BEGIN: begins creation of signature file
*     - SIGNATURE_END: ends creation of signature file
*----------------------------------------------------------------------
* CONTACT INFO:
* Sentinel Coordinating Center
* info@sentinelsystem.org
*------------------------------------------------------------------------------*/

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

%MACRO SIGNATURE_BEGIN;   /*Signature file start code*/
%global cc_start cc_stop;
data _NULL_;
   temp=DATETIME();
   call symput("CC_START",temp);
   call symput('STARTDATE',put(datepart(temp),date9.));
   call symput('STARTTIME',put(timepart(temp),time4.));
run;
%MEND SIGNATURE_BEGIN;

%MACRO SIGNATURE_END;   /*Signature file end code*/
data _NULL_;
   temp=DATETIME();
   seconds=temp-&cc_start.;
   hours=int(seconds/3600);
   minutes=int((seconds-hours*3600)/60);
   seconds2=int((seconds-hours*3600-minutes*60));
   call symput("CC_STOP",temp);
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
   CCVer="&CCVer.";
   SCDMVer="&SCDMVer.";
   OSABBR="&sysscp.";
   OSNAME="&sysscpl.";
   SASVersion="&sysver.";
   SASVersionLong="&sysvlong.";
   RunType="&sysenv.";
   NCPU="&sysncpu.";
   format StartTime StopTime datetime21.2;
   StartTime=trim(left("&CC_START."));
   StopTime=trim(left("&CC_STOP."));
   Seconds=trim(left("&Seconds."));
   format RunTime $20.;
   RunTime=strip("&hours. h &minutes. m &seconds2. s");
   output;
run;

proc transpose data=signature out=msoc.cc_signature (rename=(_NAME_=Variable COL1=Value));
   var _ALL_;
run;
%remove_labels(msoc,cc_signature);
%MEND SIGNATURE_END;
