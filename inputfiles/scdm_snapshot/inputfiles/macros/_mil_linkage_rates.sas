/*-----------------------------------------------------------------------------------*\
|   PROGRAM NAME: _mil_linkage_rates.sas                                          |
|-------------------------------------------------------------------------------------|
|                                                                                     |
|   PURPOSE:  The purpose of this program is to generate an analytic dataset          |
|             characterizing the QA MIL Package to be used in a SCDM summary report.  |
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
%macro mil_linkage_rates(inlib=, outlib=);
  %if &miltable. ne %str( ) %then %do;

    %local _miltable;
    %do p = 1 %to &numpartitions.;
      %if &numpartitions. gt 1 %then %do;
        %let _miltable = &inlib..&miltable.&p.;
      %end; /* end of numpartitions check */
      %else %let _miltable = &inlib..&miltable.;

  %ms_delpatients(  datafile=&_miltable.
                  , ptsfile= &PTSTOEXCLUDE.
                  , outfile= dplocal.mil_exclude&p.
                  , patvar= mpatid);
  %ms_delpatients(  datafile=dplocal.mil_exclude&p.
                  , ptsfile= &PTSTOEXCLUDE.
                  , outfile= dplocal.mil_exclude&p.
                  , patvar= cpatid);

  %end; /* end of partitions (p) loop */

  %mergeDataset(inlib=dplocal, indsn_root=mil_exclude);


  /* InfantsLinked: This is the count of distinct populated CPatIDs per MPatID/EncounterID*/
  proc sql noprint;
    create table dplocal.mil_linkedcpatid as
      select mpatid
           , encounterid
           , enctype
           /* collapse multiple births (5+) due to PHI small cell count */
           , put(birth_type, b_typfmt.)as birth_type
           , put(age,m_agefmt.) as agegroup
           , put(year(adate),4.) as year
           , count(distinct(cpatid)) as InfantsLinked length=3
    from dplocal.mil_exclude (keep = mpatid encounterid age adate enctype birth_type cpatid)
    where not missing(mpatid)
    group by 1, 2, 3, 4, 5, 6
    ;
    drop table dplocal.mil_exclude
    ;
  quit;

 /* calculate overall linkage rate */
    proc sql noprint;
      create table dplocal.temp_mil_linkage_all as
        select 1 as tablesort
           , "overall" as value format = $50.
             , "overall" as variable
           , count(*) as deliveries format=comma18.
           , sum(case when infantsLinked > 0 then 1 else 0 end) as infantsLinked format=comma18.
           , calculated infantsLinked / calculated deliveries as linkageRate format=percent6.2
    from dplocal.mil_linkedcpatid
    ;
  quit;

  /* calculate linkage rate by mother's agegroup */
    %macro linkagert(sort,var);
      proc sql noprint;
        create table dplocal.temp_mil_&var. as
          select &sort. as tablesort
               , "&var." as variable
               , &var. as value format = $50.
             , count(*) as deliveries format=comma18.
             , sum(case when infantsLinked > 0 then 1 else 0 end) as infantsLinked format=comma18.
             , calculated infantsLinked / calculated deliveries as
                 linkageRate format=percent6.2
      from dplocal.mil_linkedcpatid
      group by &var.
        order by &var.
      ;
    quit;
  %mend;
  %linkagert(2,agegroup);
  %linkagert(3,enctype);
  %linkagert(4,year);
  %linkagert(5,birth_type);

  data &outlib..mil_linkage_rates (drop = tablesort);
    length dp $6 variable $12 value $50;
    set dplocal.temp_mil_:;
      by tablesort;
      dp = upcase("&dp.");
      label variable = "Variable"
            value = "Value"
            deliveries = "Delivery Count"
            infantsLinked = "Linked Infant Count"
            linkageRate = "Linkage Rate";
  run;

  proc datasets nolist nowarn lib=dplocal;
    delete temp_mil_: mil_linkedcpatid;
  quit;

  %end;
%mend;