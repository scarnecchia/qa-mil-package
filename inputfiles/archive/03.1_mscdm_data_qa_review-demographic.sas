/*-------------------------------------------------------------------------------------*\
|  PROGRAM NAME:                                                                        |
|     03.1-mscdm-data-qa-review-demographic.sas                                         |
|                                                                                       |
|  QA PACKAGE VERSION: 4.0.3                                                            |
|---------------------------------------------------------------------------------------|
|  PURPOSE:                                                                             |
|     The purpose of this program is to perform data quality checks on the Demographic  |
|     table.                                                                            |
|---------------------------------------------------------------------------------------|
|  PROGRAM INPUT:                                                                       |
|     see 00.0_mscdm_data_qa_review_master_file.sas                                     |
|                                                                                       |
|  PROGRAM OUTPUT:                                                                      |
|     see Workplan PDF                                                                  |
|---------------------------------------------------------------------------------------|
|  CONTACT:                                                                             |
|     Sentinel Coordinating Center                                                      |
|     info@sentinelsystem.org                                                           |
\*-------------------------------------------------------------------------------------*/

*-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-;
*  PLEASE DO NOT EDIT BELOW WITHOUT CONTACTING THE SENTINEL OPERATIONS CENTER           ;
*-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-;

%table_name (n=);
%timestamp(&tabid._start);

/*-------------------------------------------------------------------------------------*/
/*  START Level 2                                                                      */
/*-------------------------------------------------------------------------------------*/
%level2;

/*-------------------------------------------------------------------------------------*/
/*  START Level 3                                                                      */
/*-------------------------------------------------------------------------------------*/
%let level=3;

* birth_date: list with # of records for use in the L3 module (after DP maxdate is created);
proc sql noprint;
  create table dplocal.&tabid._birthd as
  select birth_date, count(*) as n
  from mscdm.&table. (keep=birth_date)
  group by 1
  ;
  create table msoc.&tabid._l3_catvars as
  select sex label=' '
       , hispanic label=' '
       , race label=' '
       , count(*) as count format=comma15.
  from mscdm.&table. (keep=sex hispanic race)
  group by 1,2,3
  ;
quit;

%macro l3_zip;
/* Load the data from the zip lookup table into a hash table and merge with work.zip on key variable ZIP to assign STATECODE*/
  data work.zip1 (drop=rc);
    declare Hash zipstate (); /* declare the name ZIPSTATE for hash */
    rc = zipstate.DefineKey ('zip'); /* identify fields to use as keys */
    rc = zipstate.DefineData ('statecode'); /* identify fields to use as data */
    rc = zipstate.DefineDone (); /* complete hash table definition */
    do until (eof1) ; /* loop to read records from lookup file infolder.dem-lkp-zip  */
      set infolder.lkp_dem_zip  end = eof1;
      rc = zipstate.add (); /* add each record to the hash table */
    end;
    do until (eof2) ; /* loop to read records from WORK.ZIP1 */
      set mscdm.&table. (keep=zip zip_date)  end = eof2;
      call missing(statecode); /* initialize the variable to fill */
      rc = zipstate.find (); /* lookup each ZIP in hash ZIPSTATE */
      output; /* write record WORK.ZIPSTATE */
    end;
    stop;
  run; 

/* delete temporary dataset */
  proc datasets lib=work memtype=data;
    delete zip;
  quit;

/* create masked (pseudo) zip code variable ZIP-masked */
  data work.temp1;
    set work.zip1;
    length z1-z5 $1;
    temp=tranwrd(zip, " ", "_"); *change spaces to underscores;
  %do j=1 %to 5;
    z&j.= substr(temp,&j.,1); *parse zip characters into 5 separate variables;
  %end;
  run;

  data work.temp2;
    set work.temp1;
  %do i=1 %to 5;
    if anydigit(z&i.)=1 then z2_&i.="N"; *convert numeric characters to "N";
    else if z&i="_" then z2_&i.="_"; *keep "-" for spaces;
    else if notdigit(z&i.)=1 then z2_&i.="a"; *convert alpha characters to "a";
  %end;
    drop temp z1-z5;
  run;

  data work.zip;
    length Zip_masked $5;
    set work.temp2;
    zip_masked=z2_1||z2_2||z2_3||z2_4||z2_5; *concatenate 5 characters create to a pseudo zip variable;
    drop z2_1-z2_5;
  run;

  proc datasets lib=work;
    delete temp: zip1;
  quit;

  proc sql noprint;
/* create new variables ZIP-CHECK and ZIP-STATE to characterize ZIP*/
    create table work.zip1 as
    select "&dpid." as DPID length=2
         , "&siteid." as SiteID length=4
         , put(zip_date,year4.) as Year
         , zip_masked 
         , case when zip=' ' then 'Blank'
                when statecode ne ' ' then 'Valid'
                else 'Invalid'
           end as Zip_Check length=7
         , case when calculated zip_check='Blank' then 'Missing'
                when calculated zip_check='Valid' then statecode
                when calculated zip_check='Invalid' then 'Invalid'
           end as Zip_State length=7
    from work.zip
    ;
/* output table to characterize ZIP by year */
    create table msoc.dem_l3_zip_y as
    select *        
         , count(*) as count format=comma15.
    from work.zip1 (keep=dpid siteid year zip_masked)
    group by dpid, siteid, year, zip_masked
    ;
/* output table to characterize the validity of zip values by year*/
    create table msoc.dem_l3_zip_verify_y as
    select *
         , count(*) as count format=comma15.
    from work.zip1 (keep=dpid siteid year zip_check)
    group by dpid, siteid, year, zip_check
    ;
/* output table to characterize distribution of Zip State */
    create table msoc.dem_l3_zip_state as
    select *
         , count(*) as count format=comma15.
    from work.zip1 (keep=dpid siteid zip_state)
    group by dpid, siteid, zip_state
    ;
  quit;
%mend;
%l3_zip;

proc datasets kill lib=work nolist nowarn nodetails;
quit;

%timestamp(&tabid._end);
%timereport(&&&tabid._start,&&&tabid._end);

*-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-;
*  END 03.1-mscdm-data-qa-review-demographic.sas                                        ; 
*-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-;
