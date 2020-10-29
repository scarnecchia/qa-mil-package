/* Direct log to module log in the msoc folder */
proc printto log=modlog;
run;quit;
/*-------------------------------------------------------------------------------------*\
|  PROGRAM NAME:                                                                        |
|     01.2_scdm_data_qa_review-level2.sas                                               |
|                                                                                       |
|  MIL QA PACKAGE VERSION: 3.0.0                                                    |
|---------------------------------------------------------------------------------------|
|  PURPOSE:                                                                             |
|     The purpose of the program is to perform critical level 2 data quality checks     |
|     on all applicable tables.                                                         |     
|---------------------------------------------------------------------------------------|
|  PROGRAM INPUT:                                                                       |
|     see 00.0_scdm_mil_data_qa_review_master_file.sas                                  |
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

%timestamp(&module._start);
/*********************************************************************************/
/* START ==> %l2_dup                NOT SURE IF STILL NEEDED (JV 10/27/2020)     */
/*********************************************************************************/
/* Intra-table check for two variables                                           */
/*-------------------------------------------------------------------------------*/

%macro l2_dup(l = );
  %global dups;
  %let dups = 0;
  proc sql;
    create table temp2 as
    select * from qadata.&table.
    where 
  %if "%lowcase(&l.)" = "y" %then not missing(cpatid) and not missing(mpatid);
  %else %if "%lowcase(&l.)" = "n" %then not missing(mpatid) and missing(cpatid) ;
  %else %if "%lowcase(%sysfunc(substr(&var1.,1,1)))" = "m" %then not missing(mpatid);
  %else %if "%lowcase(%sysfunc(substr(&var1.,1,1)))" = "c" %then not missing(cpatid);
    ;
  quit;

  proc sort data = temp2 out = dupout nouniquekey;
  %if (&checkid.= 214 | &checkid. = 219 ) %then %do;
    by %do j = 1 %to 3; &&var&j. %end; ;
  %end;
  %else %do;
    by %do j = 1 %to 4; &&var&j. %end; ;
  %end;
  run;
 
  proc sql;
    select count(*) as row into: dups
    from dupout
    ;
  quit;
%mend l2_dup;
/*-------------------------------------------------------------------------------*/
/* END ==> %l2_dup                                                               */
/*-------------------------------------------------------------------------------*/

%macro checkrows(var=);
  %global duprows;
  %let duprows = 0;
  %let m = %eval(&n.-1);
  proc sql noprint;
    create table temp3 as
    select count(distinct &var.) as duprows %do j = 1 %to %eval(&m.); ,&&var&j.. %end;
    from dupout
    group by %do j = 1 %to %eval(&m.-1); &&var&j.., %end; &&var&m..
    order by %do j = 1 %to %eval(&m.-1); &&var&j.., %end; &&var&m.. 
    ;
  quit;

  proc sql noprint;
    select max(duprows) as duprows into: duprows
    from temp3
    ;
  quit;
%mend checkrows;
 
/*********************************************************************************/
/* START ==> %flag_221_226_25 :Mom-Infant Linkage table                          */
/*********************************************************************************/
/* Intra-table check for two variables                                           */
/*-------------------------------------------------------------------------------*/
%macro flag_221_226_254; 
  proc sql noprint;
    create table temp as
    select monotonic ( ) as row, *
    from temp_l2_flags (where=(checkid="&checkid.")) 
    ;
  quit;
  %let ct=&sqlobs.;

  %if &ct. > 0 %then %do;
    %do i=1 %to &ct.;
      proc sql noprint;
        select variable1
             , variable2
             , tableid 
        into :var1 trimmed
           , :var2 trimmed
           , :tabid trimmed
        from temp
        where row=&i.
        ;
      quit;

      %put ===> &var1. &var2. &tabid.;
      %table_name(n=);
 
      %if &checkid. = 221 %then %do;
        data flag_&i.;
          set qadata.&table.;
          length message $300;
          message = "";
          flag_12= 0;
          if not missing(&var1.) & missing(&var2.) then do;
          %if "%lowcase(&var1.)" ne "mpatid" & "%lowcase(&var2.)" ne "mpatid" & "%lowcase(&var1.)" ne "cpatid" %then %do;
            message=cat("MPatID= ",strip(mpatid),": &var1.= ",
            %if %index(%lowcase(&var1.),date) > 0 %then put(&var1., mmddyy10.); %else strip(&var1.);,", but No value found for ","&var2.");
          %end;
          %else %do;
            message = cat("&Var1. = ",strip(&var1.),", but No value found for ","&var2.");
          %end;
            flag_12=1;
          end;
          if flag_12;
        run;
 
        %get_flagid (ntabs=1, nvars=2);
      %end;

      %else %if &checkid.=226 %then %do;
        data flag_&i.;
          set qadata.&table.;
          length message $300;
          message="";
          flag_12=0;
          if not missing(&var1.) & not missing(&var2.) then do;
            if &var2. < &var1. then do;
              message=cat("MPatID= ",strip(mpatid),": ADate= ",put(&var1., mmddyy10.), ",DDate= ", 
              put(&var2., mmddyy10.), " but DDate must be >= ADate");
              flag_12=1;
            end;
          end;
          if flag_12;
        run;
        %get_flagid (ntabs=1, nvars=2);
      %end;

      %else %if &checkid. = 254 %then %do;
        data flag_&i.;
          set qadata.&table.;
          length message $300;
          message = "";
          flag_12= 0;
          if not missing(&var1.) & not missing(&var2.) then do;
            value=round((&var2.-&var1.)/365.25, .01);
            if &var1. > &var2. | Sum(&var2.,-&var1.)/365.25 < 10 then do;
              message = cat("MPatID = ",strip(mpatid)," and CPatID = ",strip(cpatid),": &var1. (", put(&var1.,mmddyy10.), ") must be >= 10 years before &var2.(",
              put(&var2.,mmddyy10.),"). They are only ",value," years apart");
              flag_12 = 1;
            end;
          end;
          if flag_12;
        run;
        %get_flagid (ntabs=1, nvars=2);
      %end;
    %end;
  %end; 
%mend flag_221_226_254;
/*-------------------------------------------------------------------------------*/
/* END ==> %flag_251_252_254                                                     */
/*-------------------------------------------------------------------------------*/

/*********************************************************************************/
/* START ==> %flag_255_258 :Mom-Infant Linkage table                             */
/*********************************************************************************/
* CBirth_Date must be between 3 days before the ADate through DDate; 
* if DDate is null, then CBirth_Date must be between 3 days before, 
*  through 1 day after the Adate;
/*-------------------------------------------------------------------------------*/
%macro flag_255_258;
  %local i;
  proc sql noprint;
    create table temp as
    select monotonic ( ) as row, *
    from temp_l2_flags (where=(checkid="&checkid.")) 
    ;
  quit;

  %let ct=&sqlobs.;
  %if &ct. > 0 %then %do;
    %do i=1 %to &ct.;
      proc sql noprint;
        select variable1
             , variable2
             , variable3
             , tableid 
        into :var1 trimmed
           , :var2 trimmed
           , :var3 trimmed
           , :tabid trimmed
        from temp
        where row=&i.
        ;
      quit;

      %put ===> &var1. &var2. &var3. &tabid.;
      %table_name(n=);

      %if &checkid. = 255 %then %do;
        data flag_&i.;
          set qadata.&table.;
          length message $300;
          message= "";
          flag_12= 0;
          if not missing(&var1.) and not missing(&var2.) then do;
            if not missing(&var3.) then do;
              if &var2. lt &var1.-3 | (&var2. gt &var3.) then do;
                flag_12= 1;
                message=cat("Filled DDate: MPatID= ",strip(mpatid)," and CPatid= ",strip(cpatid),": &var2.(", put(&var2,mmddyy10.), ") must be between 3 days before &var1.(",
                put(&var1,mmddyy10.), ") through &var3.(", put(&var3., mmddyy10.), ")");
              end;
            end;
            else if missing(&var3.) then do;
              if (&var2. lt &var1.-3) | (&var2. gt &var1.+1) then do;
                flag_12= 1;
                message=cat("Null DDate: MPatID= ",strip(mpatid)," and CPatid= ",strip(cpatid),": &var2.(", put(&var2,mmddyy10.), ") must be between 3 days before &var1.(",
                put(&var1,mmddyy10.), ") through 1 day after");
              end;
            end;
          end;
          if flag_12;
        run;
      %end;

      %if &checkid. = 257 %then %do;
        data flag_&i.;
          set qadata.&table.;
          length message $300;
          message = "";
          flag_12= 0;
          if not missing(mpatid) and not missing(cpatid) then do;
            if  missing(&var1.) | missing(&var2.) then do;
              flag_12= 1;
              message=cat("MPatID= ",strip(mpatid)," and CPatid= ",strip(cpatid),": &var1. and &var2. must be filled");
            end;
          end;
          if flag_12;
        run;
      %end;

      %if &checkid. = 258 %then %do;
   /* Flag [TABID]_1_xx_00-0_258: value between min and max (inclusive) */ 
        %date_ranges(variable=&var1., dataset=%if "%upcase(%sysfunc(substr(&var1., 1, 1)))"= "C" %then &inftable.; %else &deltable.;);
        data flag_&i.;
          set qadata.&table.;
          length message $300;
          message = "";
          flag_12= 0;
          if not missing(&var1.) & ((&var1. gt &date_max. | &var1. lt &date_min.)) then do;
            flag_12 = 1;
            message = cat(%if "%upcase(%sysfunc(substr(&var1., 1, 1)))" = "C" %then "CPatID (",strip(cpatid),; %else "MPatID (",strip(mpatid),; 
            ") &var1.(",strip(put(&var1.,mmddyy10.)),") not found in ",
        %if "%upcase(%sysfunc(substr(&var1., 1, 1)))" = "C" %then "Infants table"; %else "Deliveries table";);
          end;
          if flag_12;
        run;
      %end;
      %get_flagid (ntabs=1, nvars=2);
    %end;
  %end;
%mend flag_255_258;
/*-------------------------------------------------------------------------------*/
/* END ==> %flag_255_258                                                         */
/*-------------------------------------------------------------------------------*/

/*********************************************************************************/
/* START ==> %flag_217_219_27_ :Mom-Infant Linkage table                         */
/*********************************************************************************/
/* Duplicate rows for variable combination                                       */
/* Variable differs across rows                                                  */ 
/*-------------------------------------------------------------------------------*/
%macro flag_217_219_27_;
  proc sql noprint;
    create table temp as
    select monotonic ( ) as row, *
    from temp_l2_flags (where=(checkid="&checkid.")) 
    ;
  quit;
  %let ct=&sqlobs.;

  data temp;
    set temp;
  %do i = 1 %to 4;
    variable&i. = tranwrd(variable&i., "NA", " ");
  %end;
  run;

  %global var1 var2 var3 var4 link tabid;
  %if &ct. > 0 %then %do;
    %do i=1 %to &ct.;
      proc sql noprint;
        select variable1
             , variable2
             , variable3
             , variable4
             , _linked
             , tableid 
             , flag_descr
        into :var1 trimmed
           , :var2 trimmed
           , :var3 trimmed
           , :var4 trimmed
           , :link trimmed
           , :tabid trimmed
           , :flagdesc trimmed
        from temp
        where row=&i.
        ;
      quit;
      %put ===> &var1. &var2. &var3. &var4. &link. &tabid.;

      %let variable = %str(&var1. &var2. &var3. &var4.); 
      %let n = %sysfunc(countw(&variable.));
      %put n===>&n.;

      %table_name(n=);
      %l2_dup(l = &link.);

      %if (&checkid.= 214 | &checkid. = 219 ) %then %do;
        %let checkvar = &var4.;
        %put &checkvar.;
        %checkrows(var = &checkvar);
      %end;
 
      data flag_&i.;
      %if (&checkid.= 214 | &checkid. = 219 ) %then %do;
        merge dupout (in = a) temp3 (in = b);
        by %do j = 1 %to %eval(&n.-1); &&var&j.. %end;;
        if a and b and duprows > 1;
      %end;
      %else %do;
        set dupout;
      %end;
        length message $300;
        message = "";
        flag_l2= 0;
      %if (&checkid. = 272 | &checkid. = 273 ) %then %do;
        %if &dups. > 0 %then %do;
          %if "%lowcase(&var1.)"= "clname" %then %do;
        message=cat("Cpatid (",strip(cpatid),"), &var1. (",strip(&var1.),
        "), &var2. (",strip(&var2.),%if &checkid. = 273 %then 
        "), &var3. (",strip(&var3.),"), &var4. (",put(&var4., mmddyy10.),;"): Variable combination appears on > 1 row");
          %end;
          %else %do;
        message=cat("CPatID (",strip(cpatid),"), CBirth_Date (",put(cbirth_date, mmddyy10.),"), Sex (",strip(sex),"): Must appear on only 1 row");
          %end;
        flag_l2= 1;
        %end;
      %end; 

      %if &checkid.= 217 %then %do;
        %if &dups. > 0 %then %do;
        message=cat("MPatID (",strip(mpatid),"), EncounterID (", strip(encounterid),"), ADate (", put(adate, mmddyy10.),"), MBirth_Date (",put(mbirth_date, mmddyy10.),"): Not linked, but variable combination appears on > 1 row");
        flag_l2 = 1;
        %end;
      %end;  
      %if &checkid. = 218 %then %do;
        %if &dups. > 0 %then %do;
          %if "%lowcase(&var1.)" = "mlname" %then %do;
        message=cat("MPatid (",strip(mpatid),"), Cpatid (",strip(cpatid),"), EncounterID (",strip(encounterid),
         "), EncType (",strip(enctype),"), Adate (",put(adate, mmddyy10.),"), Sex (",strip(sex),"), CBirthDate (", 
         put(Cbirth_date, mmddyy10.),"), Match_Method (",strip(matchmethod),"), &var1. (",strip(&var1.),
        "), &var2. (",strip(&var2.),"), &var3. (",strip(&var3.),"), &var4. (",strip(&var4.),"): Linked, but variable combination  appears on > 1 row");
          %end;
          %else %do;
        message=cat("Linked: MPatID (",strip(mpatid),"), CPatID (",strip(cpatid),"), EncounterID (",strip(encounterid),
          "), EncType (",strip(EncType),"), ADate (", put(adate, mmddyy10.),"), Sex (",sex,"), CBirth_Date (",put(CBirth_Date, mmddyy10.),
          "), Match_Method (",strip(matchmethod),"):but variable combination appears on > 1 row");
          %end;
        flag_l2 = 1;
        %end;
      %end; 

      %if &checkid. = 214 | &checkid. = 219 %then %do;  
        %if &dups. > 0 %then %do;      
          %if &duprows. > 1 %then %do;
            %if &checkid. = 214 %then %do;
        message=cat("Encounter (",strip(encounterid),"), EncType (",strip(EncType),"), ADate (",put(adate, mmddyy10.),"), &var1. (",strip(&var1.),
           "), &var2. (",strip(&var2),"): &checkvar. differs across rows");
            %end;
            %else %do;
        message=cat("Linked: &var1. (",strip(&var1.),"), &var2. (",%if %index(%LOWCASE(&var2.),date) %then put(&var2., mmddyy10.); %else strip(&var2.);,
              %if ("%lowcase(&checkid.)" = "mbirth_date" | "%lowcase(&checkid.)" = "adate") %then "), EncType (",strip(EncType),;
              %if "%lowcase(&checkid.)" = "mbirth_date" %then "), ADate (", put(adate, mmddyy10.),;
           "): &checkvar. values differ across rows");  
            %end; 
        flag_l2 = 1;
          %end;
        %end; 
      %end;  
      run;

   /*Match Method*/
      %if (&checkid.= 274 | &checkid. = 275 ) %then %do;
        data flag_&i.;
          set qadata.&table;
        %if "%lowcase(&link.)" = "y" %then 
          if not missing(mpatid) and not missing(cpatid);
        %else %if "%lowcase(&link.)" = "n" %then 
          if missing(mpatid) or missing(cpatid); ;
          length message $300;
          message = "";
          flag_l2 = 0;
          if &checkid.= 274 then do;
            if upcase(strip(MatchMethod)) not in ("RE","SI","LA","BC","OT") then do;
              flag_l2 = 1;
              message=cat("Linked: MPatid (",strip(Mpatid),") and EncounterID (",strip(EncounterID),") has invalid value of MatchMethod (",strip(MatchMethod),")");
            end;
          end;
          if &checkid.= 275 then do;
            if upcase(strip(MatchMethod)) not in ("N1","N2","N3","NA") then do;
              flag_l2 = 1;
              message=cat("non-Linked: MPatid (",strip(Mpatid),") and EncounterID (",strip(EncounterID),") has invalid value of MatchMethod (",strip(MatchMethod),")");
            end;
          end;
          if flag_l2;
        run;
      %end;
      %get_flagid (ntabs=1, nvars=&n.);
    %end;
  %end;
%mend flag_217_219_27_;
/*-------------------------------------------------------------------------------*/
/* END ==> %flag_217_219_27_                                                     */
/*-------------------------------------------------------------------------------*/

/*********************************************************************************/
/* START ==> %flag_274_279                                                       */
/*********************************************************************************/
/* Cross table checks                                                            */ 
/*-------------------------------------------------------------------------------*/
%macro flag_201_208;
  %local i;
  proc sql noprint;
    create table temp as
    select monotonic ( ) as row, *
    from temp_l2_flags (where=(checkid="&checkid.")) 
    ;
  quit;
  %let ct=&sqlobs.;

  %if &ct. > 0 %then %do;
    %do i=1 %to &ct.;
      proc sql noprint;
        select variable1
             , variable2
             , table1
             , table2
        into :var1 trimmed
           , :var2 trimmed
           , :tab1 trimmed
           , :tab2 trimmed
        from temp
        where row=&i.
        ;
      quit;

   /*if variable1 is filled, then that variable must be present in table2*/
    %if &checkid. = 201  %then %do;
 /*DEV-1866*/
      %if "%upcase(&tab2.)" = "DEL" | "%upcase(&tab2.)" = "INF" %then %do;
        %if "%upcase(&tab2.)" = "DEL" %then %let reftable = &deltable.;
        %else %let reftable = &inftable.;
      proc sql noprint;
        create table flag_&i. as
        select distinct a.&var1. %if "%upcase(&tab2.)"="DEL" %then, a.&var2. ;, "E" as IDFileStatus format=$1.
        from  qadata.&&&tab1.table a left join qadata.&reftable. b
        on a.&var1. = b.&var1.
        %if "%upcase(&tab2.)" = "DEL" %then %do;
          and a.EncounterID = b.EncounterID
        %end;
        where not missing (a.&var1.) and b.&var1. is null
        ;
      quit;
      %end;

      %else %do;    
      proc sql noprint;
        create table flag_&i. as
        select distinct a.&var1.
        from qadata.&&&tab1.table a left join indata.&&&tab2.table b
        on a.&var1. = b.&var2.
        where not missing(a.&var1.) and b.&var2. is null
        ;
      quit;
      %end;

      %ISDATA(dataset = flag_&i.);
      data flag_&i.;
        set flag_&i.;
        length message $300;
        length table1 table2 $3;
        table1 = "&tab1.";
        table2 = "&tab2.";
      %if &NOBS. > 0 %then %do;
        %if "%upcase(&tab2.)" = "DEL" %then %do;
        message=cat("&var1. (",strip(&var1.),")/&var2.(",strip(&var2.),") was found in &&&tab1.table but not found in deliveries table");
      %end;
      %else %if "%upcase(&tab2.)" = "INF" %then %do;
        message=cat("&var1. (",strip(&var1.),") was found in &&&tab1.table but not found in Infants table");
      %end;
      %else %do;
        message=cat("&var1. (",strip(&var1.),") not found in &&&tab2.table table");
      %end;
    %end;
    %else %do; 
        message = "";
    %end;
      run;
    %if &NOBS. > 0 %then %do;
      %if "%upcase(&tab2.)" = "DEL" | "%upcase(&tab2.)" = "INF" %then %do;
        %ISDATA(dataset = dplocal.MIL_IDFileStatus_&VAR1.);
        %if &NOBS. = 0 %then %do;
          data dplocal.MIL_IDFileStatus_&VAR1.;
            set flag_&i. (drop = message table1 table2);
        %end;
        %else %do;
          data dplocal.MIL_IDFileStatus_&VAR1.;
            set dplocal.MIL_IDFileStatus_&VAR1. flag_&i. (drop = message table1 table2);
        %end;
          run;

      %end;
    %end;
  %end; /*end of 201*/

  %if &checkid. = 202  %then %do;
 /*if variable1 is filled in table2, then that variable must be present in table2*/
    %if "%upcase(&tab2.)" = "DEL" %then %let reftable = &deltable.; /*DEV-1866*/
    %else %let reftable = &inftable.;
    proc sql noprint;
      create table flag_&i. as
      select distinct a.&var1. %if "%upcase(&tab2.)" = "DEL" %then, a.&var2. ;, "N" as IDFileStatus format=$1.
      from  qadata.&reftable.  a left join qadata.&&&tab1.table b
      on a.&var1. = b.&var1.
      %if "%upcase(&tab2.)" = "DEL" %then %do;
        and a.EncounterID = b.EncounterID
      %end;
      where not missing (a.&var1.) and b.&var1. is null
      ;
    quit;

    %ISDATA(dataset = flag_&i.);

    data flag_&i.;
      set flag_&i.;
      length message $300;
      length table1 table2 $3;
      table1 = "&tab1.";
      table2 = "&tab2.";
      %if &NOBS. > 0 %then %do;
        %if "%upcase(&tab2.)" = "DEL" %then %do;
      message=cat("&var1. (",strip(&var1.),")/&var2.(",strip(&var2.),") was found in deliveries but not found in &&&tab1.table table");
      %end;
      %else %if "%upcase(&tab2.)" = "INF" %then %do;
      message=cat("&var1. (",strip(&var1.),") was found in Infants but not found in &&&tab1.table table");
      %end;     
    %end;
    %else %do; 
      message = "";
    %end;
    run;

    %if &NOBS. > 0 %then %do;
      %ISDATA(dataset = dplocal.MIL_IDFileStatus_&VAR1.);
      %if &NOBS. = 0 %then %do;
        data dplocal.MIL_IDFileStatus_&VAR1.;
          set flag_&i. (drop = message table1 table2);
        run;
      %end;
      %else %do;
        data dplocal.MIL_IDFileStatus_&VAR1.;
          set dplocal.MIL_IDFileStatus_&VAR1. flag_&i. (drop = message table1 table2);
        run;
      %end;    
    %end;
  %end; /*end of 202*/

  %if &checkid. = 203 %then %do;
    proc contents data= qadata.&&&tab1.table out=l2_cont_&tab1. noprint;
    run;

    proc contents data = qadata.&&&tab2.table out = l2_cont_&tab2. noprint;
    run;

    proc sql noprint;
      create table flag_&i. as
      select "&tab1." as table1 length=3
           , "&tab2." as table2 length=3
           , a.length 
           , b.length as comp_length 
      from l2_cont_&tab1. (keep = name type length) a 
         , l2_cont_&tab2. (keep=name type length) b
      where upcase(a.name) = "%upcase(&var1.)"
      and upcase(b.name) = "%upcase(&var2.)"
      ;
    quit;
  
    data flag_&i.;
      set flag_&i.;
      length message $300;
      message = "";
      flag_l2= 0;
      if length ne comp_length then do;
        message = cat("&var1. length differs from &var2. length in &&&tab2.table table");
        flag_l2 = 1;
      end;
      if flag_l2;
      run;
    %end;

    %if &checkid. = 208 %then %do;
      %if "%upcase(&tab2.)" = "DEM" %then %do;
        data dem;
          set indata.&&&tab2.table;
          if upcase(sex) in ('A','U') then sex = 'O';
        run;
        %let scdmtable = dem;
      %end;
      %else %do;
        %let scdmtable = indata.&&&tab2.table;
      %end;
      proc sql;
        create table flag_&i. as 
        select distinct a.&var1., 
        cat(%if ("%lowcase(&var1.)" = "mbirth_date") %then "MPatID (",mpatid,; 
      %else %if ("%lowcase(&var1.)" = "adate" | "%lowcase(&var1.)" = "ddate") %then "EncounterID (",a.encounterid,;
      %else %if ("%lowcase(&var1.)" = "sex" | "%lowcase(&var1.)" = "cbirth_date") %then "CpatID (",a.cpatid,;
      "): &var1. (",%if %index(%lowcase(a.&var1.), date) > 0 %then put(a.&var1., mmddyy10.);
           %else strip(a.&var1.);
      ,") not equal to &&&tab2.table..&var2. (", 
      %if %index(%lowcase(b.&var2.), date) > 0 %then put(b.&var2., mmddyy10.);
           %else strip(b.&var2.);,
      %if "%lowcase(&var1.)" = "mbirth_date"  %then "), when linking Mpatid=&&&tab2.table..patid";
      %else %if ("%lowcase(&var1.)" = "adate" | "%lowcase(&var2.)" = "ddate") %then "), when linking EncounterID=&&&tab2.table..EncounterID";
      %else %if ("%lowcase(&var1.)" = "sex" | "%lowcase(&var1.)" = "cbirth_date") %then "), when linking Cpatid=&&&tab2.table..patid";  
      ) as message length=300,  
       "&tab1." as table1 length=3
      ,"&tab2." as table2 length=3 
        from qadata.&&&tab1.table a, &scdmtable. b 
        where %if "%lowcase(&var1.)" = "mbirth_date" %then a.Mpatid = b.patid; 
     %else %if ("%lowcase(&var1.)" = "adate" | "%lowcase(&var1.)" = "ddate") %then a.encounterid = b.encounterid;
     %else %if ("%lowcase(&var1.)" = "sex" | "%lowcase(&var1.)" = "cbirth_date") %then a.Cpatid = b.patid;
        and a.&var1. ne b.&var2. and not missing(a.&var1.)
        ;
      quit;
      %end;
    %get_flagid (ntabs=2, nvars=2);
    %end;/*end of 203*/
  %end;  
%mend flag_201_208;
/*-------------------------------------------------------------------------------*/
/* END ==> %flag_274_279                                                         */
/*-------------------------------------------------------------------------------*/

/*********************************************************************************/
/* START ==> %flag_221 :Mom-Infant Linkage table                                 */
/*********************************************************************************/
/* Intra-table check, if variable is filled, variable2 must be filled       */
/*-------------------------------------------------------------------------------*/
%macro flag_221;
  %flag_221_226_254
%mend flag_221;
/*-------------------------------------------------------------------------------*/
/* END ==> %flag_221                                                             */
/*-------------------------------------------------------------------------------*/

/*********************************************************************************/
/* START ==> %flag_226 :Mom-Infant Linkage table                                 */
/*********************************************************************************/
/* Intra-table check, if DDate after Adate              */
/*-------------------------------------------------------------------------------*/
%macro flag_226;
  %flag_221_226_254
%mend flag_226;
/*-------------------------------------------------------------------------------*/
/* END ==> %flag_226                                                             */
/*-------------------------------------------------------------------------------*/

/*********************************************************************************/
/* START ==> %flag_254 :Mom-Infant Linkage table                                 */
/*********************************************************************************/
/* MBirth_date must be greater than CBirth_date by 10+ years         */
/*-------------------------------------------------------------------------------*/
%macro flag_254;
  %flag_221_226_254
%mend flag_254;
/*-------------------------------------------------------------------------------*/
/* END ==> %flag_254                                                             */
/*-------------------------------------------------------------------------------*/
/*********************************************************************************/
/* START ==> %flag_255 :Mom-Infant Linkage table                                 */
/*********************************************************************************/
/* CBirth_Date between (Adate-x) and Ddate                                       */
/*-------------------------------------------------------------------------------*/
%macro flag_255;
  %flag_255_258
%mend flag_255;
/*-------------------------------------------------------------------------------*/
/* END ==> %flag_255                                                             */
/*-------------------------------------------------------------------------------*/

/*********************************************************************************/
/* START ==> %flag_257: Mom-Infant Linkage table                                 */
/*********************************************************************************/
/* Support table name                                                            */
/*-------------------------------------------------------------------------------*/
%macro flag_257;
  %flag_255_258
%mend flag_257;
/*-------------------------------------------------------------------------------*/
/* END ==> %flag_257                                                             */
/*-------------------------------------------------------------------------------*/

/*********************************************************************************/
/* START ==> %flag_258 :Mom-Infant Linkage table                                 */
/*********************************************************************************/
/* Min and Max values                      */
/*-------------------------------------------------------------------------------*/
%macro flag_258;
 %flag_255_258;
%mend flag_258;
/*-------------------------------------------------------------------------------*/
/* END ==> %flag_257                                                             */
/*-------------------------------------------------------------------------------*/

/*-------------------------------------------------------------------------------------*/
/*  START Level 2 Macro                                                                */
/*-------------------------------------------------------------------------------------*/
%macro level2_abort (level=2);
/* Create the list of tables to to include for Level 2 Checks */
  proc sql noprint;
    select module
         , quote(strip(module))
    into :tabidlist separated by ' '
       , :sql_tabidlist separated by ','
    from msoc.control_flow_3 (where=(execute_flag='y' and cc_table ne 'X'))
    ;
  quit;
/*-------------------------------------------------------------------------------------*/
/* 1 - Perform L2 1.intra-table and 2.cross-table datachecks where AbortYN='y' for     */
/*-------------------------------------------------------------------------------------*/
  %do l=1 %to 2;
  /*-----------------------------------------------------------------------------------*/
  /* 1.1 - Create temporary lookup table                                               */
  /*-----------------------------------------------------------------------------------*/
   /*1:indicates no crosstable, and abort=y only*/
    %if &l.=1 %then %do;
      %l2_lkp_table (abortyn=, crosstable=n);
      %l2_ds_nodupkey;
    %end;

    %else %if &l.=2 %then %do;  
      %l2_lkp_table (abortyn=y, crosstable=y);
    %end;

  /*-----------------------------------------------------------------------------------*/
  /* 1.2 - Create a macro variable with list of unique CheckIds from temporary lookup  */
  /*-----------------------------------------------------------------------------------*/
    proc sql noprint;
      select distinct checkid
           , count(distinct checkid) 
      into :checkidlist separated by ' '
         , :checkct trimmed
      from temp_l2_flags
      ; 
    quit; 
 
  /*-----------------------------------------------------------------------------------*/
  /* 1.3 - Loop through each CheckID and output temporary flags datasets by CheckID    */
  /*-----------------------------------------------------------------------------------*/
    %do c=1 %to &checkct.;
      %let checkid=%scan(&checkidlist.,&c.);
      %if (&checkid. ge 217 & &checkid. le 219) | (&checkid. ge 272 & &checkid. le 275) %then %do;
        %str(%flag_217_219_27_);
      %end;
      %else %if &checkid. ge 201 & &checkid. le 208 %then %do;
        %str(%flag_201_208);
      %end;
      %else %do;
        %str(%flag_&checkid.);
      %end;
      data dplocal.flag_l2_&checkid.;
        set flag_l2_&checkid.:;
      run;
     %ISDATA(dataset = dplocal.flag_l2_&checkid.);
     %IF &NOBS. > 0 %then %do;
       data dplocal.flag_l2_&checkid.;
         set dplocal.flag_l2_&checkid.;
          if count > 0;
        run;
     %END;
    %end;
  %end; /* end of loop L */

  /*-----------------------------------------------------------------------------------*/
  /* 1.4 - Combine temporary flags datasets                                            */
  /*-----------------------------------------------------------------------------------*/
    %set_ds (libin=dplocal, dsin_prefix=flag_l2, libout=dplocal, dsout=l2_flags_temp);

    proc datasets lib=work memtype=data kill nolist nowarn nodetails;
    quit;

    proc contents data=dplocal.l2_flags_temp out=_temp;
    run;

    %let ct=0;
    proc sql noprint;
      select nobs into :ct
      from _temp
      ;
      drop table _temp
      ;
    quit;

    %if &ct. ne 0 %then %do;
      proc sql noprint;
        select count(*) into :abort_qa
        from dplocal.l2_flags_temp (where=(lowcase(abortYN)='y'))
        ;
      quit;
      /* For loops 1 and 2, end macro at current loop when first Abort=YN occurs and output 
         finalized L2 flags for DP review */
      %set_ds (libin=dplocal, dsin_prefix=l2_flags_, libout=dplocal, dsout=l2_mstr); 

      %if &abort_qa. ne 0 %then %do;   /*aggregate counts for failed l2 flags*/
        proc sql noprint;
          create table dplocal.all_l2_flags as
          select flagid, abortyn, flagtype, flag_descr, sum(count) as count format=comma15. informat=comma15.
          from dplocal.l2_mstr (where=(lowcase(abortYN)='y'))
          group by 1,2,3,4
          order by 1,3
          ;
        quit;

        %let end_qa=1;
        %let l=999;

        data _null_;      
          putlog 70*'!';
          putlog 'ERR'"OR: The &module. module detected fatal L2 data flags"; 
          putlog "       that require the QA package to abort";
          putlog 70*'!';
        run;

        /* Clean up datasets from DPLOCAL before aborting */
        proc sql noprint;
          select memname into :ds separated by " "
          from dictionary.tables where libname='DPLOCAL'
          having nobs-delobs=0
          ;
        quit;

        proc datasets lib=dplocal nolist nowarn nodetails;
          delete tmp_: l2_nodup_:;
        quit; 
      %end; /*end of loop to abort */
    %end; /* end of loop for if flags exist */

/* Clean up datasets from DPLOCAL before continuing */
  proc datasets lib=dplocal memtype=data nowarn nolist nodetails;
    delete tmp_: ;
  quit;
%mend;
%level2_abort;

%timestamp(&module._end);
%timereport(&&&module._start,&&&module._end);

*-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-;
*  END 01.2-scdm-data-qa-review-level2.sas                                              ;
*-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-;
