/*-----------------------------------------------------------------------------------*\
|   PROGRAM NAME: _modVitals.sas                                                      |
|-------------------------------------------------------------------------------------|
|                                                                                     |
|   PURPOSE:  The purpose of this program is to generate an analytic dataset          |
|             characterizing the SCDM Vital Signs Table to be used in a SCDM summary  |
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
%macro modVitals;
  %if &vittable. ne %str( ) %then %do;

    %do p = 1 %to &numpartitions.;
      %if &numpartitions. gt 1 %then %do;
        %let _vittable = indata.&vittable.&p.;
      %end; /* end of numpartitions check */
      %else %let _vittable = indata.&vittable.;

      data _vit_measure_long&p.;
        set &_vittable. (keep=patid measure_date ht wt diastolic systolic rename=(ht=HGT wt=WGT diastolic=DIA systolic=SYS));

        array _ameasure(*) HGT WGT DIA SYS;

        do i=1 to dim(_ameasure);
          measure = vname (_ameasure(i));
          if _ameasure(i) ne . then
            value = _ameasure(i);
          else delete;
          output;
        end;

        drop HGT WGT DIA SYS;

      run;

    %end; /* end of partitions (p) loop 1 */

  %let covtypes = md;

  %do j=1 %to %sysfunc(countw(&covtypes., "|"));
    %let cov = %scan(&covtypes., &j., "|");

    %do p = 1 %to &numpartitions.; /* partitions loop 2 */

    proc sql noprint;
        create table _vit_enr_vitct_&cov.&p. as
        select a.*
             , b._enr_start
             , b._enr_end
        from _vit_measure_long&p. as a, dplocal.enr_final_&cov.&p. as b
        where a.patid=b.patid and (b._enr_start le a.measure_date le b._enr_end);
    quit;

    proc sort data=_vit_enr_vitct_&cov.&p. (keep=patid measure i) out=_vit_pat_vitct_&cov.&p. nodupkey;
      by i measure patid;
    run;

    %end; /* end of partitions (p) loop 2 */

    %mergeDataset(indsn_root=_vit_pat_vitct_&cov.);

    proc sql noprint;
        create table msoc.vit_pat_vitct_&cov. as
        select upcase("&dp.") as DP length=6
            , measure as VS_Type label="Vital Sign Type"
            , i
            , count(*) as Count label="Enrollee Count" format=comma12.
        from _vit_pat_vitct_&cov.
        group by DP, VS_Type, i
        order by i;
    quit;

    data msoc.vit_pat_vitct_&cov.;
      set msoc.vit_pat_vitct_&cov. (drop=i);
    run;

  %end; /* end of covtype (j) loop */

  proc datasets lib=work mt=data nolist nodetails nowarn;
    delete _: ;
  run;

  proc datasets lib=dplocal mt=data nolist nodetails nowarn;
    delete _vit: ;
  run;

%end;
%mend;