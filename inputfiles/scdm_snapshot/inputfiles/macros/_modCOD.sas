/*-----------------------------------------------------------------------------------*\
|   PROGRAM NAME: _modCOD.sas                                                         |
|-------------------------------------------------------------------------------------|
|                                                                                     |
|   PURPOSE:  The purpose of this program is to generate an analytic dataset          |
|             characterizing the SCDM COD Table to be used in a SCDM summary report.  |
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
%macro modCOD;
  %if &codtable. ne %str( ) %then %do;

  %local _codtable;
  %do p = 1 %to &numpartitions.;
    %if &numpartitions. gt 1 %then %do;
      %let _codtable = indata.&codtable.&p.;
    %end; /* end of numpartitions check */
  %else %let _codtable = indata.&codtable.;

  proc sql noprint;
    create table dplocal._cod_by_patid&p. as
    select *
        , count(*) as _count
    from &_codtable. (keep=patid)
    group by patid
    order by patid;
  quit;

  %end; /* end of partitions (p) loop 1 */

  %let covtypes = m|md;

  %do j=1 %to %sysfunc(countw(&covtypes., "|"));
    %let cov = %scan(&covtypes., &j., "|");

    %do p = 1 %to &numpartitions.; /* partitions loop 2 */

      proc sql noprint;
        create table _cod_enr_&cov.&p. as
        select a.*
        from dplocal._cod_by_patid&p. as a, dplocal.enr_patid_&cov.&p. as b
        where a.patid=b.patid;
      quit;

      proc sql noprint;
        create table _cod_pat_codct_&cov.&p. as
        select patid
             , sum(_count) as COD_Count
        from _cod_enr_&cov.&p.
        group by patid;
      quit;

    %end; /* end of partitions (p) loop 2 */

    /* Create cod_pat_codct_*                                                              */
    %mergeDataset(indsn_root=_cod_pat_codct_&cov.);

    %create_summary_ct(indsn=_cod_pat_codct_&cov.,
                       outdsn=cod_pat_codct_&cov.,
                       var=%str(put(COD_Count, %str(rec_ct.)) as COD_Count),
                       varlabel="COD Record Count",
                       ctlabel="Enrollee Count",
                       group=%str(group by DP, COD_Count),
                       order=%str(order by COD_Count));

  %end; /* end of covtype (j) loop */

  proc datasets lib=work mt=data nolist nodetails nowarn;
    delete _: ;
  run;

  proc datasets lib=dplocal mt=data nolist nodetails nowarn;
    delete _cod: ;
  run;
  %end;
%mend;