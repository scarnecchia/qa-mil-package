/*-----------------------------------------------------------------------------------*\
|   PROGRAM NAME: _modDispensing.sas                                                  |
|-------------------------------------------------------------------------------------|
|                                                                                     |
|   PURPOSE:  The purpose of this program is to generate an analytic dataset          |
|             characterizing the SCDM Dispensing Table to be used in a SCDM summary   |
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
%macro modDispensing;

  %local _distable;
    %do p = 1 %to &numpartitions.;
      %if &numpartitions. gt 1 %then %do;
        %let _distable = indata.&distable.&p.;
    %end; /* end of numpartitions check */
    %else %let _distable = indata.&distable.;

    proc sql noprint;
      create table dplocal._dis_pat_rx_ct&p. as
      select *
           , count(*) as _count
      from &_distable. (keep=patid rxdate)
      where rxdate ne .
      group by patid, rxdate;
    quit;

  %end; /* end of partitions (p) loop 1 */

  %let covtypes = d|md;

  %do j=1 %to %sysfunc(countw(&covtypes., "|"));
    %let cov = %scan(&covtypes., &j., "|");

    %do p = 1 %to &numpartitions.; /* partitions loop 2 */

    proc sql noprint;
      create table _dis_patid_enr_&cov.&p. as
      select a.*
      from dplocal._dis_pat_rx_ct&p. as a, dplocal.enr_final_&cov.&p. as b
      where a.patid=b.patid and (b._enr_start le a.rxdate le b._enr_end);
    quit;

    proc sql noprint;
      create table _dis_pat_rxcount_&cov.&p. as
      select patid
           , sum(_count) as RX_Count
      from _dis_patid_enr_&cov.&p.
      group by patid;
    quit;

    %end; /* end of partitions (p) loop 2 */

    %mergeDataset(indsn_root=_dis_pat_rxcount_&cov.);

    %create_summary_ct(indsn=_dis_pat_rxcount_&cov.,
                       outdsn=dis_pat_rxcount_&cov.,
                       var=rx_count,
                       varlabel="Dispensing Record Count",
                       ctlabel="Enrollee Count",
                       group=%str(group by DP, rx_count),
                       order=%str(order by rx_count));

  %end; /* end of covtype (j) loop */

  proc datasets lib=work mt=data nolist nodetails nowarn;
    delete _: ;
  run;

  proc datasets lib=dplocal mt=data nolist nodetails nowarn;
    delete _dis: ;
  run;

%mend;