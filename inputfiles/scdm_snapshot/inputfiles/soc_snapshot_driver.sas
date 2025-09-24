/*-----------------------------------------------------------------------------------*\
|   PROGRAM NAME: soc_scdm_data_snapshot.sas                                          |
|-------------------------------------------------------------------------------------|
|                                                                                     |
|   PURPOSE:  The purpose of this program is to generate analytic datasets            |
|             to be used in a SCDM summary report. This program will be               |
|             distributed to all Data Partners (DP) and run on the most current       |
|             production ETL.                                                         |
|                                                                                     |
|-------------------------------------------------------------------------------------|
|                                                                                     |
|   PROGRAM INPUT:  See master program and/or workplan                                |
|                                                                                     |
|   PROGRAM OUTPUT:  See master program and/or workplan                               |
|                                                                                     |
|-------------------------------------------------------------------------------------|
|   CONTACT:                                                                          |
|        Sentinel Coordinating Center                                                 |
|        info@sentinelsystem.org                                                      |
|                                                                                     |
\*-----------------------------------------------------------------------------------*/
*+_+_+_+_+_+_+_+_+_+_+_+_+_+_+_+_+_+_+_+_+_+_+_+_+_+_+_+_+_+_+_+_+_+_+_+_+_+_+_+_+_;
* PLEASE DO NOT EDIT BELOW WITHOUT CONTACTING THE SENTINEL OPERATION CENTER        ;
*+_+_+_+_+_+_+_+_+_+_+_+_+_+_+_+_+_+_+_+_+_+_+_+_+_+_+_+_+_+_+_+_+_+_+_+_+_+_+_+_+_;
%let debug = 0;
proc printto log="&MSOC./soc_scdm_data_snapshot.log" new; run;

%SIGNATURE_BEGIN;
%timestamp(snapshot_start);

%macro snapshotDriver;

%if debug ne 0 %then %do;
  options mprint mlogic mprintnest mlogicnest symbolgen;
%end;

%initPartitions;
%subset_enrtable(inlib=dplocal, indsn=temp_enr);

%bridgeEnrollment;
%modEnrollment;
%modDemographic;
%modDispensing;
%modEncounters;
%modLabResults;
%modVitals;
%modDeath;
%modCOD;
%mil_linkage_rates(inlib=indata, outlib=msoc);

/** Delete dplocal datasets for production runs **/
%if debug ne 0 %then %do;
  proc datasets kill lib=dplocal mt=data nolist nodetails nowarn;
  run;
%end;

%mend;

%snapshotDriver;

/***************************************************************************************/
/* Close signature file                                                                */
/***************************************************************************************/
%timestamp(snapshot_end);
%timereport(&snapshot_start,&snapshot_end);
%SIGNATURE_END;

/***************************************************************************************/
/* Cleanup SAS environment                                                             */
/***************************************************************************************/
proc datasets lib=work kill nodetails nowarn nolist;
run;
quit;
proc printto;
run;
/***************************************************************************************/
/* End of program                                                                      */
/***************************************************************************************/