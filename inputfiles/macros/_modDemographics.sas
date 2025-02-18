/*-----------------------------------------------------------------------------------*\
|   PROGRAM NAME: _modDemographic.sas                                                 |
|-------------------------------------------------------------------------------------|
|                                                                                     |
|   PURPOSE:  The purpose of this program is to generate an analytic dataset          |
|             characterizing the SCDM Demograhic Table to be used in a SCDM summary   |
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
%macro modDemographic;

  %let covtypes = md;

    %do j=1 %to %sysfunc(countw(&covtypes., "|"));
      %let cov = %scan(&covtypes., &j., "|");

      %local _demtable;
      %do p = 1 %to &numpartitions.;
        %if &numpartitions. gt 1 %then %do;
            %let _demtable = indata.&demtable.&p.;
        %end; /* end of numpartitions check */
        %else %let _demtable = indata.&demtable.;

    /* Retain single record per patid with latest enrollment span */
    /* create temp flag indicating whether enrollment overlaps with dp max date */

        data _last_enroll_patid_&cov.&p.;
        set dplocal.enr_final_&cov.&p.;
          by patid;
          if last.patid;
          _dpMaxenroll = (_enr_end ge &dp_maxdate.);
        run;

    /* merge enrollment with demographcis to add birthdate and calculate age */
        data _agecalc_&cov.&p. (drop=birth_date);
          length agecategory $40;
          merge _last_enroll_patid_&cov.&p. (in=a keep=patid _enr_start _dpMaxenroll)
              &_demtable. (in=b keep=patid birth_date sex where=(birth_date ne .));
          by patid;
          if a and b;

          age=floor((intck('month',Birth_Date, _Enr_Start) - (day(_Enr_Start) < day(Birth_Date))) / 12);
          agecategory = put(age, age_years.);
        run;
        
      data _temp_agecat1_&cov.&p. _temp_agecat2_&cov.&p. _temp_agecat3_&cov.&p. _temp_agecat4_&cov.&p.;
        set _agecalc_&cov.&p.;
        if 0 <= age < 19 then do;
            agecategory='0-18 (Pediatric Populations I)';
            output _temp_agecat1_&cov.&p.;
        end;
        if 0 <= age < 22 then do;
            agecategory='0-21 (Pediatric Populations II)';
            output _temp_agecat2_&cov.&p.;
        end;
        if 0 <= age < 26 then do;
            agecategory='0-<26 (Young Adult Coverage Eligible)';
            output _temp_agecat3_&cov.&p.;
        end;
        if 10 <= age <= 54 and upcase(sex)='F' then do;
            agecategory='10-54 & Sex = F (Childbearing Age)';
            output _temp_agecat4_&cov.&p.;
        end;
    run;
    
    data _agecalc_&cov.&p.;
        set _agecalc_&cov.&p.
            _temp_agecat1_&cov.&p.
            _temp_agecat2_&cov.&p.
            _temp_agecat3_&cov.&p.
            _temp_agecat4_&cov.&p.;
    run;

    /* inner join with age category look-up to attach sort order */
    /* note this extract will be used again for table limited to currently enrolled     */
      proc sql noprint;
        create table _dem_pat_age_&cov.&p. as
            select   a.*
                   , b.SortOrder length=3
                   , upcase("&dp.") as DP length=6
            from   _agecalc_&cov.&p. as a
                 , msoc.age_sort     as b
            where a.agecategory = b.label;
      quit;

      /* Merge DEM extract with ENR extract containing med/drugcov span per PatID */
      /* Save for re-use downstream in module */
      data _dem_patid_enr_&cov.&p.;
          merge &_demtable. (in=a keep=patid sex hispanic race postalcode) dplocal.enr_patid_&cov.&p. (in=b keep=patid);
          by patid;
          if a and b;
      run;

      /* Create subset count of postalcodes */
      proc sql noprint;
        create table _dem_postalcode_ct_&cov.&p. as
        select postalcode
             , count(*) as _count
        from _dem_patid_enr_&cov.&p. (drop=patid sex hispanic race)
      group by postalcode;
      quit;

      /* Load the data from the zip lookup table into a hash table and merge SCDM table on key variable ZIP to assign STATECODE*/
      data _dem_statecodes1_&cov.&p. (drop=rc);
        declare Hash zipstate (); /* declare the name ZIPSTATE for hash */
        rc = zipstate.DefineKey ('postalcode'); /* identify fields to use as keys */
        rc = zipstate.DefineData ('statecode'); /* identify fields to use as data */
        rc = zipstate.DefineDone (); /* complete hash table definition */
        do until (eof1) ; /* loop to read records from lookup file infolder.lkp_dem_zip  */
          set infolder.lkp_dem_zip  end = eof1;
          rc = zipstate.add (); /* add each record to the hash table */
        end;
        do until (eof2) ; /* loop to read records from WORK.ZIP1 */
          set _dem_postalcode_ct_&cov.&p. end = eof2;
          call missing(statecode); /* initialize the variable to fill */
          rc = zipstate.find (); /* lookup each ZIP in hash ZIPSTATE */
          output; /* write record WORK.ZIPSTATE */
        end;
      stop;
      run;

      %end; /* end of partitions (p) loop */

      %mergeDataset(indsn_root=_dem_statecodes1_&cov.);

      proc sql noprint;
        create table _dem_statecodes2_&cov. as
         select case
                  when _statecode ne ' ' then _statecode /* valid zip */
                  when postalcode=' ' then '00' /* missing zip */
                  else '99' /* invalid zip */
                end as StateCode
              , sum(_count) as Count
        from _dem_statecodes1_&cov. (rename=statecode=_statecode)
        group by calculated StateCode;
      quit;

      /* Create dem_geolocct_md dataset                                                    */
      proc sql noprint;
        create table msoc.dem_geolocct_&cov. as
        select upcase("&dp.") as DP length=6
             , StateCode label='Geographic Location'
             , Count label='Enrollee Count' format=comma12.
        from _dem_statecodes2_&cov.
        order by StateCode;
      quit;

      /* Create summary datasets by coverage type */
      %mergeDataset(indsn_root=_dem_pat_age_&cov.);

      proc sql noprint;
        create table msoc.dem_pat_lstagecount_&cov. as
            select  DP
                  , SortOrder
                  , agecategory label='Age Category'
                  , count(*) as count label='Enrollee Count'
        from _dem_pat_age_&cov.
        group by DP, SortOrder, agecategory
        order by Sortorder;
      quit;

      /* Filter dem age extract to retain active        */
      /* Summarize results to create final output table */
      proc sql noprint;
        create table msoc.dem_pat_actagecount_&cov. as
            select  DP
                  , SortOrder
                  , agecategory label='Age Category'
                  , count(*) as count label='Active Enrollee Count'
        from _dem_pat_age_&cov. (where = (_dpMaxenroll))
        group by DP, SortOrder, agecategory
        order by Sortorder;
      quit;

      /** Create catvar datasets by coverage type */
      %mergeDataset(indsn_root=_dem_patid_enr_&cov.);

      %let catvars = hispanic|race|sex;
      %do c=1 %to %sysfunc(countw(&catvars., "|"));
        %let var = %scan(&catvars., &c., "|");

        %create_summary_ct(indsn=_dem_patid_enr_&cov.,
                           outdsn=dem_&var.ct_&cov.,
                           var=&var.,
                           varlabel="%sysfunc(propcase(&var.))",
                           ctlabel="Enrollee Count",
                           fromCnd=%str((keep=&var.)),
                           group=%str(group by DP, &var.));

      %end; /* end of catvar (c) loop */

    %end; /* end of covtype (j) loop */

      proc datasets lib=work mt=data nolist nodetails nowarn;
        delete _: ;
      run;

      proc datasets lib=dplocal mt=data nolist nodetails nowarn;
        delete _dem: ;
      run;

%mend;
