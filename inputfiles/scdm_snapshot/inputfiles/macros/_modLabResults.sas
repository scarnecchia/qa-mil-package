/*-----------------------------------------------------------------------------------*\
|   PROGRAM NAME: _modLabResults.sas                                                  |
|-------------------------------------------------------------------------------------|
|                                                                                     |
|   PURPOSE:  The purpose of this program is to generate an analytic dataset          |
|             characterizing the SCDM Lab Results Table to be used in a SCDM summary  |
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
%macro modLabResults;
  %if &labtable. ne %str( ) %then %do;

    %local _labtable;
    %do p = 1 %to &numpartitions.;
      %if &numpartitions. gt 1 %then %do;
        %let _labtable = indata.&labtable.&p.;
      %end; /* end of numpartitions check */
      %else %let _labtable = indata.&labtable.;

      data dplocal._lab_testdate_patid_tmp&p. (keep=patid TestDate);
        set &_labtable. (keep=patid lab_dt result_dt order_dt);
        format TestDate mmddyy10.;
        if not missing(lab_dt) then TestDate=lab_dt;
          else if not missing(result_dt) then TestDate=result_dt;
          else if not missing(order_dt) then TestDate=order_dt;
          else delete;
        output ;
      run;

      proc sql noprint;
        create table dplocal._lab_testdate_patid&p. as
        select patid
            ,  TestDate
            ,  count(*) as _count
        from dplocal._lab_testdate_patid_tmp&p.
        group by patid, TestDate;

        drop table dplocal._lab_testdate_patid_tmp&p.;
      quit;

    %end; /* end of partitions (p) loop 1 */

  %let covtypes = md;

  %do j=1 %to %sysfunc(countw(&covtypes., "|"));
    %let cov = %scan(&covtypes., &j., "|");

    %do p = 1 %to &numpartitions.; /* partitions loop 2 */

    proc sql noprint;
      create table _lab_pat_enr_testdt_&cov.&p. as
      select a.*
           , b._enr_start
           , b._enr_end
      from dplocal._lab_testdate_patid&p. as a, dplocal.enr_final_&cov.&p. as b
      where a.patid=b.patid and (b._enr_start le a.TestDate le b._enr_end)
      order by a.patid, a.TestDate, b._enr_start, b._enr_end;
    quit;

    proc sql noprint;
      create table _lab_pat_testct_&cov.&p. as
      select patid
           , sum(_count) as Lab_Count
      from _lab_pat_enr_testdt_&cov.&p. (keep=patid _count)
      group by patid;
    quit;

    %end; /* end of partitions (p) loop 2 */

    /* Create enc_pat_enccount_md                                                        */
    %mergeDataset(indsn_root=_lab_pat_testct_&cov.);

    %create_summary_ct(indsn=_lab_pat_testct_&cov.,
                       outdsn=lab_pat_testcount_&cov.,
                       var=lab_count,
                       varlabel="Lab Record Count",
                       ctlabel="Enrollee Count",
                       group=%str(group by DP, Lab_Count),
                       order=%str(order by Lab_Count));

  %end; /* end of covtype (j) loop */

  proc datasets lib=work mt=data nolist nodetails nowarn;
    delete _: ;
  run;

  proc datasets lib=dplocal mt=data nolist nodetails nowarn;
    delete _lab: ;
  run;

  %end;
%mend;