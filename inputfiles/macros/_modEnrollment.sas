/*-----------------------------------------------------------------------------------*\
|   PROGRAM NAME: _modEnrollment.sas                                                  |
|-------------------------------------------------------------------------------------|
|                                                                                     |
|   PURPOSE:  The purpose of this program is to generate an analytic dataset          |
|             characterizing the SCDM Enrollment Table to be used in a SCDM summary   |
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
%macro modEnrollment;
    %let covtypes = md;

      %do j=1 %to %sysfunc(countw(&covtypes., "|"));
        %let cov = %scan(&covtypes., &j., "|");

      %do p = 1 %to &numpartitions.;

        /* calculate length of enrollment per PatID */

        proc sql noprint;
            create table _enr_loe_by_patid_&cov.&p. as
            select *
                 , _enr_end - _enr_start + 1 as LOE
            from dplocal.enr_final_&cov.&p.
        quit;

        data _enr_year_&cov.&p.(keep=year) ;
          set _enr_loe_by_patid_&cov.&p.;
          length year 3 ;
          t_start = year(_enr_start);
          t_end = year(_enr_end);
          do t_y = t_start to t_end ;
            year=t_y;
            output _enr_year_&cov.&p.;
          end;
          drop t_: ;
        run;

        proc sql;
          create table _enr_pat_covlength_&cov.&p. as
          select patid
               , sum(LOE) as tLOE
          from _enr_loe_by_patid_&cov.&p.
          group by patid;
        quit;

        data _enr_active_enroll_patid_&cov.&p.;
          set _enr_loe_by_patid_&cov.&p.;
          by patid;
            if last.patid and _enr_end ge &dp_maxdate.;
        run;

        proc sort data=dplocal.enr_final_&cov.&p. out=_enr_startend_&cov.&p.;
          by patid _Enr_start _Enr_end;
        run;

        proc sql noprint;
          create table _enr_pat_start_&cov.&p. as
          select *
               , count(*) as _count
          from _enr_startend_&cov.&p.
          group by patid, _Enr_start;
        quit;

        proc sql noprint;
          create table _enr_pat_count_&cov.&p. as
          select patid
               , sum(_count) as Enr_Count
          from _enr_pat_start_&cov.&p.
        group by patid;
        quit;

      %end; /* end of partition loop */

        /* Number of PatIDs with at least one day of coverage by year. */
        %mergeDataset(indsn_root=_enr_year_&cov.);

        %create_summary_ct(indsn=_enr_year_&cov.,
                           outdsn=enr_patid_count_&cov._y,
                           var=Year,
                           varlabel="Year",
                           ctlabel="PatID Count by Year",
                           group=%str(group by DP, year));

        /* Number of PatIDs with at least one day of coverage.*/
        %mergeDataset(indsn_root=_enr_loe_by_patid_&cov.);

        proc sql noprint;
          create table msoc.enr_patid_ct_&cov. as
          select upcase("&dp.") as DP length=6
               , count(distinct(Patid)) as Count format=comma16.  label="Total PatID Count"
          from _enr_loe_by_patid_&cov.;
        quit;

        /* Create enr_rec_covlength_* dataset                                                  */
        %create_summary_ct(indsn=_enr_loe_by_patid_&cov.,
                           outdsn=enr_rec_covlength_&cov.,
                           var=LOE,
                           varlabel="Length of Enrollment (days)",
                           ctlabel="Record Count",
                           group=%str(group by DP, loe),
                           order=%str(order by loe));

        /* Create enr_pat_covlength_* dataset                                                  */
        %mergeDataset(indsn_root=_enr_pat_covlength_&cov.);

        %create_summary_ct(indsn=_enr_pat_covlength_&cov.,
                           outdsn=enr_pat_covlength_&cov.,
                           var=tLOE,
                           varlabel="Total Length of Enrollment (days)",
                           ctlabel="Enrollee Count",
                           group=%str(group by DP, tloe),
                           order=%str(order by tloe));

        /* Create enr_active_patid_ct_* dataset                                             */
        %mergeDataset(indsn_root=_enr_active_enroll_patid_&cov.);

        %create_summary_ct(indsn=_enr_active_enroll_patid_&cov.,
                           outdsn=enr_active_patid_ct_&cov.,
                           var=%str("&DP_MaxDate."),
                           varlabel="DP Max Date",
                           ctlabel="Active Enrollee Count");

        /* Create enr_pat_enrcount_* dataset                                                */
        %mergeDataset(indsn_root=_enr_pat_count_&cov.);

        %create_summary_ct(indsn=_enr_pat_count_&cov.,
                           outdsn=enr_pat_enrcount_&cov.,
                           var=Enr_Count,
                           varlabel="Enrollment Record Count",
                           ctlabel="Enrollee Count",
                           group=%str(group by DP, Enr_Count),
                           order=%str(order by Enr_Count));

      %end; /* end of covtype (j) loop */

      proc datasets lib=work mt=data nolist nodetails nowarn;
        delete _: ;
      run;

      proc datasets lib=dplocal mt=data nolist nodetails nowarn;
        delete _enr: ;
      run;
%mend;