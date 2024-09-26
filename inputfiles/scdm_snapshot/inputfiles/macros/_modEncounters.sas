/*-----------------------------------------------------------------------------------*\
|   PROGRAM NAME: _modEncounters.sas                                                  |
|-------------------------------------------------------------------------------------|
|                                                                                     |
|   PURPOSE:  The purpose of this program is to generate an analytic dataset          |
|             characterizing the SCDM Encounters Table to be used in a SCDM summary   |
              report.                                                                 |
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
%macro modEncounters;

  %local _enctable;
  %do p = 1 %to &numpartitions.;
    %if &numpartitions. gt 1 %then %do;
      %let _enctable = indata.&enctable.&p.;
  %end; /* end of numpartitions check */
  %else %let _enctable = indata.&enctable.;

  proc sql noprint;
    create table dplocal._enc_adate_patid_ct&p. as
    select *
         , count(*) as _count
    from &_enctable. (keep=patid ADate)
    where ADate ne .
    group by patid, ADate;
  quit;

  %end; /* end of partitions (p) loop 1 */

  %let covtypes = md;

  %do j=1 %to %sysfunc(countw(&covtypes., "|"));
    %let cov = %scan(&covtypes., &j., "|");

  %do p = 1 %to &numpartitions.; /* partitions loop 2 */

    proc sql noprint;
      create table _enc_patid_enr_&cov.&p. as
      select a.*
      from dplocal._enc_adate_patid_ct&p. as a, dplocal.enr_final_&cov.&p. as b
      where a.patid=b.patid and (b._enr_start le a.adate le b._enr_end);
    quit;

    proc sql noprint;
      create table _dis_pat_enccount_&cov.&p. as
      select patid
           , sum(_count) as Enc_Count
      from _enc_patid_enr_&cov.&p.
      group by patid;
    quit;

    %end; /* end of partitions (p) loop 2 */

    /* Create enc_pat_enccount_md                                                        */
    %mergeDataset(indsn_root=_dis_pat_enccount_&cov.);

    %create_summary_ct(indsn=_dis_pat_enccount_&cov.,
                       outdsn=enc_pat_enccount_&cov.,
                       var=enc_count,
                       varlabel="Encounter Record Count",
                       ctlabel="Enrollee Count",
                       group=%str(group by DP, Enc_Count),
                       order=%str(order by Enc_Count));

  %end; /* end of covtype (j) loop */

  proc datasets lib=work mt=data nolist nodetails nowarn;
    delete _: ;
  run;

  proc datasets lib=dplocal mt=data nolist nodetails nowarn;
    delete _enc: ;
  run;

%mend;