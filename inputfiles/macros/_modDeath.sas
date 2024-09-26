/*-----------------------------------------------------------------------------------*\
|   PROGRAM NAME: _modDeath.sas                                                       |
|-------------------------------------------------------------------------------------|
|                                                                                     |
|   PURPOSE:  The purpose of this program is to generate an analytic dataset          |
|             characterizing the SCDM Death Table to be used in a SCDM summary report.|
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
%macro modDeath;
  %if &deathtable. ne %str( ) %then %do;

  %let covtypes = m|md;

  %do j=1 %to %sysfunc(countw(&covtypes., "|"));
    %let cov = %scan(&covtypes., &j., "|");

    %local _deathtable;
      %do p = 1 %to &numpartitions.;
        %if &numpartitions. gt 1 %then %do;
        %let _deathtable = indata.&deathtable.&p.;
      %end; /* end of numpartitions check */
      %else %let _deathtable = indata.&deathtable.;

    proc sql noprint;
      create table _dth_enr_&cov.&p. as
      select a.*
      from &_deathtable. (keep=patid) as a, dplocal.enr_patid_&cov.&p. as b
      where a.patid=b.patid;
    quit;

    %end; /* end of partitions (p) loop */

    /* Create dth_dthct_md                                                              */
    %mergeDataset(indsn_root=_dth_enr_&cov.);

    proc sql noprint;
      create table msoc.dth_dthct_&cov. as
      select upcase("&dp.") as DP length=6
           , count(*) as Count label='Death Record Count' format=comma12.
      from _dth_enr_&cov.;
    quit;

  %end; /* end of covtype (j) loop */

  proc datasets lib=work mt=data nolist nodetails nowarn;
    delete _: ;
  run;

  proc datasets lib=dplocal mt=data nolist nodetails nowarn;
    delete _dth: ;
  run;
  %end;
%mend;