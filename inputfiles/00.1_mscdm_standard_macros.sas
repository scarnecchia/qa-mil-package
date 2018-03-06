/*-------------------------------------------------------------------------------------*\
|  PROGRAM NAME: 00.1_mscdm_standard_macros.sas                                         |
|                                                                                       |
|  QA PACKAGE VERSION: 4.0.3                                                            |
|---------------------------------------------------------------------------------------|
|  PURPOSE:                                                                             |
|     The purpose of the program is to store macros used repeatedly in QA programs      |
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
               
/*********************************************************************************/
/* START ==> %licensed                                                           */
/*********************************************************************************/
/*  Used in Control Flow to determine available SAS products at DP site          */

/*-------------------------------------------------------------------------------*/
%macro licensed;
  proc setinit;
  run;
  data licensed;
    %do a=1 %to %sysfunc(countw(&comps.)); 
      %if %sysprod(%scan(&comps.,&a.))=1 %then %upcase(%scan(&comps.,&a.))=1;
      %else %if %sysprod(%scan(&comps.,&a.))=-1 %then %upcase(%scan(&comps.,&a.))=-1;
      %else %if %sysprod(%scan(&comps.,&a.))=0 %then %upcase(%scan(&comps.,&a.))=0;;
    %end;
    output;
  run;
  proc transpose data=licensed out=_licensed (rename=(_NAME_=Component COL1=Value));
    var _all_;
  run;
  data dplocal.&prefix.licensed (keep=Site Component Status);
    length Site $6;
    set _licensed;
    length Status $25;
    if value=1 then Status="Licensed";
    else if value=0 then Status="Not licensed";
    else if value=-1 then Status="Invalid product";
    else Status="Other invalid product";
    Site="&DPID.&SITEID.";
    label component=' ';
  run;
  proc datasets lib=work nodetails nolist;
    delete licensed _licensed;
  quit;
%mend licensed;
/*-------------------------------------------------------------------------------*/
/* END ==> %licensed                                                             */
/*-------------------------------------------------------------------------------*/

/*********************************************************************************/
/* START ==> %ISDATA                                                             */
/*********************************************************************************/
/*  Macro to determine whether a dataset is empty or not;                        */
/*-------------------------------------------------------------------------------*/
%MACRO ISDATA(dataset=);

%PUT =====> MACRO CALLED: ms_macros v1.0 => ISDATA;

	%GLOBAL NOBS;
	%let NOBS=0;
	%if %sysfunc(exist(&dataset.))=1 and %LENGTH(&dataset.) ne 0 %then %do;
		data _null_;
		dsid=open("&dataset.");
		call symputx("NOBS",attrn(dsid,"NLOBS"));
		run;
	%end;	
%PUT &NOBS.;

%put NOTE: ********END OF MACRO: ms_macros v1.0 => ISDATA ********;

%MEND ISDATA;
/*-------------------------------------------------------------------------------*/
/* END ==> %ISDATA                                                    		     */
/*-------------------------------------------------------------------------------*/


/*********************************************************************************/
/* START ==> %minmaxdate                                                             */
/*********************************************************************************/
/** Min and Max dates for a dataset**/  
/*************************************************************************************/
%macro minmaxdate(variable=,dataset=);
 %global mindate maxdate;
	proc sql noprint;
		 select min(&&variable.) as mindate, 
		 		max(&&variable.) as maxdate 
		into :mindate,
			 :maxdate
		 from ds.&&dataset.;
	quit;
%mend minmaxdate;
/*-------------------------------------------------------------------------------*/
/* END ==> %minmaxdate                                                    		     */
/*-------------------------------------------------------------------------------*/

/*********************************************************************************/
/* START ==> %kill_directory                                                     */
/*********************************************************************************/
/*  Deletes all existing SAS datasets if {dir}=y in Master program               */
/*-------------------------------------------------------------------------------*/
%macro kill_directory (kill_list=);
  %do k=1 %to %sysfunc(countw(&kill_list.));
    %let dir=%scan(&kill_list.,&k.);
    %let kill=&&kill_dir_&dir.;
    %put &kill;
    %if %lowcase(&kill.)=%str(y) %then %do;
      proc datasets kill lib=&dir. memtype=data nowarn nolist nodetails;
      quit;
    %end;
  %end;
%mend kill_directory;
/*-------------------------------------------------------------------------------*/
/* END ==> %kill_directory                                                       */
/*-------------------------------------------------------------------------------*/

/*********************************************************************************/
/* START ==> %ods_printlog_start                                                 */
/*********************************************************************************/
/*  Used in all modules to start printing log to .pdf file output to DPLOCAL     */
/*-------------------------------------------------------------------------------*/
%macro ods_printlog_start;
  ods _all_ close;
  ods escapechar="^";
  options orientation=portrait 
          leftmargin=%str(.75in) rightmargin=%str(.75in) 
          topmargin=%str(.75in) bottommargin=%str(.75in);
  ods pdf file="&DPLOCAL.&PREFIX.&msdpid._&module..pdf" style=sasweb startpage=now;
%mend ods_printlog_start;
/*-------------------------------------------------------------------------------*/
/* END ==> %ods_printlog_start                                                   */
/*-------------------------------------------------------------------------------*/

/*********************************************************************************/
/* START ==> %ods_printlog_end                                                   */
/*********************************************************************************/
/*  Used in all modules end printing log to .pdf file to dplocal                 */
/*-------------------------------------------------------------------------------*/
%macro ods_printlog_end;
  run;
  ods pdf close;
  ods listing;
%mend ods_printlog_end;
/*-------------------------------------------------------------------------------*/
/* END ==> %ods_printlog_end                                                     */
/*-------------------------------------------------------------------------------*/


/*********************************************************************************/
/* START ==> %timestamp                                                          */
/*********************************************************************************/
/*  Used to record module execution date and time                                */
/*-------------------------------------------------------------------------------*/
%macro timestamp(parm);
  %put ** &parm. date: %sysfunc(putn(%sysfunc(today()),worddate.));
  %put ** &parm. time: %sysfunc(putn(%sysfunc(time()),tod.));
  %put;
  %** if a parm is passed, then save the time;
  %if &parm ne %then %do;
    %** set as global parm;
    %global &parm;
    %** set value to current time;
    %let &parm=%sysfunc(datetime());
  %end;
%mend timestamp;
/*-------------------------------------------------------------------------------*/
/* END ==> %timestamp                                                            */
/*-------------------------------------------------------------------------------*/

/*********************************************************************************/
/* START ==> %timereport                                                         */
/*********************************************************************************/
/*  Used to calculate duration of module execution                               */
/*-------------------------------------------------------------------------------*/
%macro timereport(start,end);
   data _null_;
     temp=datetime();
     seconds=&end.-&start.;
     hours=int(seconds/3600);
     minutes=int((seconds-hours*3600)/60);
     seconds2=int((seconds-hours*3600-minutes*60));
     call symput('hours',put(hours,4.0));
     call symput('minutes',put(minutes,2.0));
     call symput('seconds',put(seconds2,2.0));
   run;

  data _null_;
    putlog 70*'=';
    putlog " Total run time was &hours. h &minutes. m &seconds. s";
    putlog 70*'=';
  run;
%mend timereport;
/*-------------------------------------------------------------------------------*/
/* END ==> %timereport                                                           */
/*-------------------------------------------------------------------------------*/

/*********************************************************************************/
/* START ==> %table_name                                                         */
/*********************************************************************************/
/*  Used in all modules to create &TABLE(n) based on &TABID(n)                   */
/*-------------------------------------------------------------------------------*/
%macro table_name (n= ); /*Optional-leave blank for tabid, put n if tabid[n]*/ 
  %let temp=&&tabid&n.;
  %let temp2=%bquote(&)&temp.table;
  %let table=%unquote(&temp2);
%mend table_name;
/*-------------------------------------------------------------------------------*/
/* END ==> %table_name                                                           */
/*-------------------------------------------------------------------------------*/

/*********************************************************************************/
/* START ==> %add_dpids_ds                                                       */
/*********************************************************************************/
/*  Used in all modules to add DPID and SITEID variables in a data step          */
/*-------------------------------------------------------------------------------*/
%macro add_dpids_ds;
    length DPID $2. SiteID $4.;
    retain DPID "&dpid." SiteID "&siteid.";
%mend add_dpids_ds;
/*-------------------------------------------------------------------------------*/
/* END ==> %add_dpids_ds                                                         */
/*-------------------------------------------------------------------------------*/

/*********************************************************************************/
/* START ==> %add_dpids_sql                                                      */
/*********************************************************************************/
/*  Used in all modules to add DPID and SITEID variables in proc sql             */
/*-------------------------------------------------------------------------------*/
%macro add_dpids_sql;
    "&dpid." as DPID length=2
  , "&siteid." as SiteID length=4
%mend add_dpids_sql;
/*-------------------------------------------------------------------------------*/
/* END ==> %add_dpids_sql                                                        */
/*-------------------------------------------------------------------------------*/


/*********************************************************************************/
/* START ==> %add_dpids_all_ds                                                   */
/*********************************************************************************/
/*  Used in L3 to to add DPID and SITEID to all datasets in specified library    */
/*-------------------------------------------------------------------------------*/
%macro add_dpids_all_ds (libin=, libout=);
%local rc ct dsout lib i;
%let lib=%upcase(&libin.);
  proc sql noprint;
    create table temp as
    select monotonic ( ) as row, memname
    from dictionary.tables
    where libname="&lib."
    ;
  quit;
  %let ct=&sqlobs.;

  %do i=1 %to &ct.;
    proc sql noprint;
      select memname into :ds trimmed
      from temp
      where row=&i.;
    quit;
    %if %index(%sysfunc(lowcase(&ds.)), _signature) lt 1 %then %do; /* Exclude signature files */
      %let dsid = %sysfunc(open(&libin..&ds.)); /* assign and open dataset */
      %let dpid_exist = %qsysfunc(varnum(&dsid.,dpid));  /* populate dpid_exist as variable number */
      %let rc = %qsysfunc(close(&dsid.)); /* close dataset */
      %if &dpid_exist = 0 %then %do;    /* Add DPID and SITEID if they do not exist in the dataset */ 
        data &libout..&ds.;
          %add_dpids_ds
          set &libin..&ds.; 
        run;
      %end;
    %end;
  %end;
%mend add_dpids_all_ds;
/*-------------------------------------------------------------------------------*/
/* END ==> %add_dpids_all_ds                                                     */
/*-------------------------------------------------------------------------------*/


/*********************************************************************************/
/* START ==> %remove_labels                                                      */
/*********************************************************************************/
/*  Used to delete all variable labels from any dataset                          */
/*-------------------------------------------------------------------------------*/
%macro remove_labels(lib, ds);
  proc datasets nolist lib=&lib. memtype=data;
    modify &ds.; 
    attrib _all_ label=' '; 
  quit;
%mend remove_labels;
/*-------------------------------------------------------------------------------*/
/* END ==> %remove_labels                                                        */
/*-------------------------------------------------------------------------------*/


/*********************************************************************************/
/* START ==> %ds_exist_delete                                                    */
/*********************************************************************************/
/*  Used in all table modules to delete a specified dataset if it exists         */
/*-------------------------------------------------------------------------------*/
%macro ds_exist_delete (lib=, ds=);
  %if %sysfunc(exist(&lib..&ds.,data)) %then %do;
    proc datasets lib=&lib. nolist nodetails;
      delete &ds.
      ;
    quit;
  %end;
%mend ds_exist_delete;
/*-------------------------------------------------------------------------------*/
/* END ==> %ds_exist_delete                                                      */
/*-------------------------------------------------------------------------------*/

/*********************************************************************************/
/* START ==> %set_ds                                                             */
/*********************************************************************************/
/*  Used in all table modules to combine datasets based on the specified prefix  */
/*-------------------------------------------------------------------------------*/
%macro set_ds (libin=, dsin_prefix=, libout=, dsout=);
  %let prect=%sysfunc(lengthc(%sysfunc(strip(%str(&dsin_prefix.)))));
  %let libin=%upcase(&libin.);
  %let dsin_pre=%upcase(&dsin_prefix.);
  proc sql noprint;
    select memname, count(memname) into :mem separated by " ", :exist trimmed
    from dictionary.members
    where libname="&libin." and memtype='DATA' and %str(substr(memname,1,&prect.))="&dsin_pre."
    ;
  quit;

  %if &exist. > 0 %then %do;
    data &libout..&dsout.;
      set &libin..&dsin_prefix.:;
      format coun: comma15.;
    run;
    proc datasets lib=&libin. nowarn nolist nodetails;
      delete &dsin_prefix.:;
    quit;
  %end;
%mend;
/*-------------------------------------------------------------------------------*/
/* END ==> %set_ds                                                               */
/*-------------------------------------------------------------------------------*/

/*********************************************************************************/
/*  Used in all table modules to combine datasets based on the specified prefix  */
/*  but change column length of variable to the max length of all tables         */
/*-------------------------------------------------------------------------------*/

%macro set_ds_varlength (libin=, dsin_prefix=, libout=, dsout=, lengthvar=);
  %local prect libin dsin_pre vname i j vlen max;
  %let prect=%sysfunc(lengthc(%sysfunc(strip(%str(&dsin_prefix.)))));
  %let libin=%upcase(&libin.);
  %let dsin_pre=%upcase(&dsin_prefix.);
  %let vname=%upcase(&lengthvar.);

  proc sql noprint;
    select upcase(memname), count(memname) into :mem separated by " ", :exist trimmed
    from dictionary.members
    where libname="&libin." and memtype='DATA' and %str(substr(memname,1,&prect.))="&dsin_pre."
    ;
  quit;

  %if &exist. > 0 %then %do;
    %let max=0;
    %do i=1 %to &exist.;
      %let ds=%scan(&mem.,&i.);
      %let numobs=0;
      proc sql noprint;
        select NOBS into :numobs trimmed
        from dictionary.tables
        where libname="&libin." and memname="&ds."
        ;
      quit;
      %if &numobs. ne 0 %then %do;
        %let vlen=0;
        proc sql noprint;
          select length into :vlen trimmed
          from dictionary.columns
          where libname="&libin." and memname="&ds." and upcase(name)="&vname."
          ;
        quit;
        %put length=***&vlen;
        %if %eval(&vlen. gt &max.) %then %let max=&vlen.;
        %put ***max=&max.;
      %end; /* End if dasaset has nobs */
    %end; /* End loop i */

    %if &max. ne 0 %then %do;
      %do j=1 %to &exist.;
        %let ds=%scan(&mem.,&j.);
        data &libin..&ds. (drop=temp);
          length Value %str($&max.);
          set &libin..&ds. (rename=(value=temp));
          value=temp;
        run;
      %end; /* End loop j */
      
      data &libout..&dsout.;
        set &libin..&dsin_prefix.:;
        format coun: comma15.;
      run;
    %end; /* End if max ne 0 */
    proc datasets lib=&libin. nowarn nolist nodetails;
      delete &dsin_prefix.:;
    quit;
  %end; /* End if datasets exists */
%mend;
/*-------------------------------------------------------------------------------*/
/* END ==> %set_ds_varlength;                                                    */
/*-------------------------------------------------------------------------------*/


/*********************************************************************************/
/* START ==> %abort_table                                                        */
/*********************************************************************************/
/*  Used in L1 module to abort QA for table-level failures                       */
/*-------------------------------------------------------------------------------*/
%macro abort_table (checkid=, logmsg=);
  proc sql noprint;
    create table DPLOCAL.&PREFIX.flags_l1_&tabid. as
    select upcase(flagid) as flagid
         , flag_descr
         , flagtype
         , abortYN
         , 99999 as count
    from infolder.lkp_all_flags (where=(lowcase(tableid)=lowcase("&tabid.") and checkid="&checkid."))
    ;
  quit;
  data _null_;
    put 70*'!';
    put 'ERR'"OR: %unquote(&logmsg.)"; 
    put 70*'!';
  run; 
  %let abort_table=1;
%mend abort_table;
/*-------------------------------------------------------------------------------*/
/*  END ==> %abort_table                                                         */
/*-------------------------------------------------------------------------------*/


/*********************************************************************************/
/* START ==> %get_flagid                                                         */
/*********************************************************************************/
/*  Used in L2 and table modules to add flagid, etc. to the flags dataset        */
/*-------------------------------------------------------------------------------*/
%macro get_flagid (ntabs=, nvars=); 
  proc contents data=flag_&i. out=proctemp (keep=name nobs);
  run;

  %let temp_nobs=0;
  proc sql noprint;
    select distinct nobs into :temp_nobs trimmed
    from proctemp
    ;
  quit;

  %if %eval(&temp_nobs. gt 0) %then %do;
    proc sql noprint;
      select count(name) into :countyn trimmed
      from proctemp
      where lowcase(substr(name,1,5))='count'
      ;
    quit;
    %if &countyn. %then %do;
      proc sql noprint;
        select name into :countvar trimmed
        from proctemp
        where lowcase(substr(name,1,5))='count'
        ;
      quit;
    %end;
    proc sql noprint;
      drop table proctemp
      ;
      create table %str(flag_l2_&checkid._&tabid._&i.) as
      select b.flagid
           , a.message
		   , %if &checkid. = 203 %then a.message as flag_descr length=255; %else b.flag_descr;
           , b.flagtype
           , b.abortyn 
    %if %eval(&countyn.) %then %do;
      %str(, sum(a.&countvar.) as count)           
    %end;
    %else %do;
      %str(, count(*) as count)
    %end;
      from %str((select *, "&checkid." as checkid from flag_&i.) as a )
    %if %eval(&ntabs.=1) %then %do;  
      %str( , temp_l2_flags %(where=%(checkid="&checkid." and lowcase(tableid)=lowcase("&tabid.") )
      %if %eval(&nvars. gt 0) %then %do;  
        %str( and lowcase(variable1)=lowcase("&var1.") )
      %end;
      %if %eval(&nvars.=2) %then %do;
        %str( and lowcase(variable2)=lowcase("&var2.") )
      %end;
      %str( %)%) as b where a.checkid=b.checkid)  
    %end;

    %else %if %eval(&ntabs.=2) %then %do; 
      %str( left join temp_l2_flags %(where=%(checkid="&checkid." )
      %if %eval(&nvars. gt 0) %then %do;
        %str( and lowcase(variable1)=lowcase("&var1.") )
      %end;
      %if %eval(&nvars.=2) %then %do;
        %str( and lowcase(variable2)=lowcase("&var2.") )
      %end;
      %str( %)%) as b on a.table1=b.table1 and a.table2=b.table2 )
    %end;
	%if &checkid. = 219 %then %do;
		%str( and  lowcase(variable4)=lowcase("&var4."))
	%end;
    %str(group by 1,2,3,4,5)
      ;
      drop table flag_&i.
      ;
    quit;

  %end;

  %else %do;
    proc datasets lib=work nolist nodetails nowarn;
      delete flag_&i.;
    quit;
  %end;
%mend get_flagid;
/*-------------------------------------------------------------------------------*/
/*  END ==> %get_flagid                                                          */
/*-------------------------------------------------------------------------------*/


/*********************************************************************************/
/*  START ==> %obs_n_by_counttype                                                */
/*********************************************************************************/
%macro obs_n_by_counttype;
  proc sql noprint;
    create table temp_obs_n_&checkid. as
    select "&checkid." as CheckID
         , "Unique PatID" as count_type length=15
         , count(distinct patid) as count
    from flag union all 
    select "&checkid." as CheckID
         , "Records" as count_type length=15
         ,  count(*) as count
    from flag
    ;
    quit;
%mend obs_n_by_counttype;
/*-------------------------------------------------------------------------------*/
/* END ==> %obs_n_by_counttype                                                   */
/*-------------------------------------------------------------------------------*/


/*********************************************************************************/
/* START ==> %l2_lkp_table                                                       */
/*********************************************************************************/
%macro l2_lkp_table (abortyn= , flagtype= , crosstable= , dsout=temp_l2_flags);
   proc sql noprint;
    create table &dsout. as
    select *      
         , substr(tableid,1,3) as Table1
         , substr(tableid,5,3) as Table2
    from infolder.lkp_all_flags
    where level="&level." 
    %if %lowcase(&abortyn.) ne %str( ) %then %do;
      %str( and lowcase(abortyn)=lowcase("&abortyn.") )
    %end;
    %if %lowcase(&crosstable.) ne %str( ) %then %do;
      %if %lowcase(&crosstable.)= %str(n) %then %do;
        %str( and calculated table2 =' ' )
      %end;
      %else %if %lowcase(&crosstable.)= %str(y) %then %do;
        %str( and calculated table2 ne ' ' )
      %end;
    %end;
    having lowcase(table1) in (&sql_tabidlist.) 
    order by checkid, table2, table1
    ;
  quit;
%mend l2_lkp_table;
/*-------------------------------------------------------------------------------*/
/* END ==> %l2_lkp_table                                                         */
/*-------------------------------------------------------------------------------*/


/*********************************************************************************/
/* START ==> %l2_ds_nodupkey                                                     */
/*********************************************************************************/
%macro  l2_ds_nodupkey;
  %local a keyct;
  %do a=1 %to %sysfunc(countw(&tabidlist.));
    %let tabid=%scan(&tabidlist.,&a.);
    proc sql noprint;
      select variable
           , variable 
      into :keyvarlist separated by ' '
         , :group separated by ','
      from (select * from infolder.lkp_all_l1 (where=(lowcase(tabid)="&tabid.")))
      where upcase(keyvar)='K'
      ; 
    quit;
    %let keyct=&sqlobs.;
    %put *** keyct=&keyct.;
    %table_name (n=);

    %if &keyct. ne 0 %then %do;
      %let dupct=0;
      %let rows=0;
      %let dups=0;
      %if &keyct.=1 %then %do; /* use existing DPLOCAL.&PREFIX._01_&tabid (patid) tables for check */
        proc sql noprint;
          select sum(count), count(distinct count) into :dups trimmed, :rows trimmed
          from DPLOCAL._01_&tabid. (keep=count where=(count > 1))
          ;
        quit;
        %if &dups. ne . %then %let dupct=%eval(&dups.-&rows.);
      %end;

      %else %if &keyct.>1 %then %do;
        %if %lowcase(&tabid.)=enr %then %do;
          proc sql noprint;
            select put(count_obs,best12.) into :nobs trimmed
            from DPLOCAL.all_l1_nobs (where=(lowcase(tabid)=lowcase("&tabid.")))
            ;
            create table DPLOCAL.l2_nodup_enr as
            select *
                 , count(*)
            from mscdm.&table. (keep=&keyvarlist.)
            group by &group.
            ;
          quit;
          %let dupct=%eval(&nobs.-&sqlobs.);
        %end;
        %else %do;
          proc sql noprint;
            create table temp as
            select count(*) as dups
            from mscdm.&table. (keep=&keyvarlist.)
            group by &group.
            having calculated dups > 1
            ;
          quit;
          %let rows=&sqlobs.;
          %put ****&rows.;
          %if &rows. ne 0 %then %do;
            proc sql noprint;
              select sum(dups-1) into :dupct trimmed
              from temp 
              ;
            quit;
            %put ****&dupct.;
          %end;
        %end;
      %end;
      %put **** Number of duplicate rows in the &tabid. table: &dupct.;

      data nobs_dup_&tabid.;
        length TabID $3 count_Dup 8;
        tabid=upcase("&tabid.");
        count_dup=input(&dupct.,best12.);
        format count_dup comma15.;
      run;
    %end;
  %end;
  %set_ds (libin=work, dsin_prefix=nobs_dup_, libout=dplocal, dsout=all_l2_nobs_dup);
%mend l2_ds_nodupkey;
/*-------------------------------------------------------------------------------*/
/* END ==> %l2_ds_nodupkey                                                       */
/*-------------------------------------------------------------------------------*/


/*********************************************************************************/
/* START ==> %l2_ds_enr_overlap                                                  */
/*********************************************************************************/
/* Overlapping (including subset or duplicate date ranges) enrollment span(s) across records */
/* Note: Excludes previously flagged dup records by key variables to avoid double-counts */
/*-------------------------------------------------------------------------------*/
%macro  l2_ds_enr_overlap;
  data enr_overlap_1 enr_temp_dates temp1 (drop=lag_: enr_rec_flag);
    set dplocal.l2_nodup_enr;
    length enr_rec_flag $1.;
    by patid;
    enr_rec_flag=' ';
    lag_start=lag(enr_start);
    lag_end=lag(enr_end);
  /*exclude records with invalid dates from this check, but save for future checks */
    if enr_end lt enr_start then output enr_temp_dates;
    else if first.patid then do;
      lag_start=.;
      lag_end=.;
      output temp1;
    end;
  /* output duplicate and subset enrollment date ranges to temporary file*/
    else if (enr_start le lag_start) and (enr_end ge lag_end) then do;
      if enr_start=lag_start and enr_end=lag_end then do;
        enr_rec_flag='D';  
        output enr_overlap_1;
      end;
      else if enr_start le lag_end and enr_end le lag_end then do;
        enr_rec_flag='S';
        output enr_overlap_1;
      end;
    end;
    else output temp1;
    format lag_: mmddyy10.;
  run;

  data enr_temp_2 enr_overlap_2;
    set temp1; 
    length enr_rec_flag $1.;
    by patid;
    enr_rec_flag=' ';
    lag_start=lag(enr_start);
    lag_end=lag(enr_end);
    if first.patid then do;
      lag_start=.;
      lag_end=.;
      output enr_temp_2;
    end;
    else if (enr_start le lag_end) or (enr_end le lag_end) then do;
      enr_rec_flag='O';
      output enr_overlap_2;
    end;
    else output enr_temp_2;
    format lag_: mmddyy10.;
  run;

  data dplocal.enr_overlap_patid_dates (drop=enr_rec_flag);
    set enr_overlap_:;
    length DateConflict $12;
    dateconflict=put(enr_rec_flag,$enr_overlap.);
  run;

  %let recct=0;
  proc sql noprint;
    select count(*) into :recct trimmed
    from dplocal.enr_overlap_patid_dates
    ;
  quit;

  %if &recct.=0 %then %do;
    proc format cntlout=temp_fmt lib=dplocal;
      select $enr_overlap;
    run; 

    data dplocal.enr_l2_overlap (drop=label);
      set temp_fmt (keep=label);
      length DateConflict $12 CountType $15;
      dateconflict=label;
      count=0;
      CountType="Unique PatID";
      output;
      CountType="Records";
      output;
    run;
  %end;

/* recreate dataset dplocal.l2_nodup_enr */
  data dplocal.l2_nodup_enr;
    set enr_temp_:;
  run;

/* Rename temporary dataset with invalid dates for use later */
  data dplocal.enr_invalid_dates;
    set enr_temp_dates;
  run;

  proc sort data=dplocal.l2_nodup_enr (drop=lag: enr_rec_flag);
    by patid enr_start enr_end medcov drugcov chart;
  run;

  proc datasets lib=work nolist nodetails nowarn;
    delete enr_overlap_: enr_temp_: temp1;
  quit;
%mend l2_ds_enr_overlap;
/*-------------------------------------------------------------------------------*/
/* END ==> %l2_ds_enr_overlap                                                    */
/*-------------------------------------------------------------------------------*/


/*********************************************************************************/
/* START ==> %l2_ds_crosstable                                                   */
/*********************************************************************************/
/*  Create cross table dataset to be used in L2 module                           */
/*-------------------------------------------------------------------------------*/
%macro  l2_ds_crosstable;
/* create temp lookup to get a list of distinct cross-table variables  */
  proc sql noprint;
    create table tmp_lkp as
    select tabid, variable, varid, varlength
    from infolder.lkp_all_l1 
    where lowcase(tabid) in (&sql_tabidlist.) and crossvar='X'
    order by variable, tabid
    ;
    select distinct variable
         , count(distinct variable) 
    into :varlist separated by " "
       , :varct trimmed
    from tmp_lkp
    ;
  quit;

  /* loop through each variable */
  %if &varct. >0 %then %do;
    %do a=1 %to &varct.;
      %let var=%scan(&varlist.,&a.);


       proc sql noprint;
         select varid
              , tabid
              , count(*) 
         into :varidlist separated by ' '
            , :tablist separated by ' '
            , :tabct trimmed
         from tmp_lkp (where=(variable="&var."))
         ;
       quit; 

    /* loop through each table containing variable of interest */
      %do b=1 %to &tabct.;
        %let tabid=%scan(&tablist.,&b.);
        %let varid=%scan(&varidlist.,&b.);
        %table_name (n=);
        %local rc dsid varexist ds lib;
    /* check and use existing datasets if variable exists, otherwise create new extracts from mscdm.{table} */
        %if %sysfunc(exist(DPLOCAL._&varid._&tabid.)) %then %do;
          %let varexist=1;
          %let ds=%str(DPLOCAL._&varid._&tabid.);
          %let lib=dplocal;
        %end;
        %else %do;
          %let varexist=0;
          %let ds=%str(mscdm.&table.);
          %let lib=mscdm;
        %end;

        %if varexist=0 %then %do;
          proc sql noprint;
            create table DPLOCAL._&varid._&tabid. as
            select &var. label=' '
                 , count(*) as count format=comma15.
            from &ds. (keep=&var.)
            where not missing(&var.)
            group by &var.
            ;
          quit;
        %end;

        proc sql noprint;
          create table DPLOCAL.&PREFIX.tmp_length_&var._&tabid. as
          select "&tabid." as TabID length=3
               , "&var." as Variable length=21
               , lengthn(&var.) as ValueLength length=3
               , sum(count) as count
          from DPLOCAL._&varid._&tabid. 
          group by valuelength
          ;
        quit;

        %if %lowcase(&var.)=enctype %then %do;
          proc sql noprint;
            create table DPLOCAL.&PREFIX.tmp_&var._&tabid. as
            select &var.
                 , count as %upcase(&tabid.) format=comma15.
            from DPLOCAL._&varid._&tabid.
            ;
            drop table DPLOCAL._&varid._&tabid.
            ;
          quit;
        %end;
        %else %do;
          proc sql noprint;
            create table DPLOCAL.&PREFIX.tmp_&var._&tabid. as
            select &var.
                 , '1' as %upcase(&tabid.) length=1
            from DPLOCAL._&varid._&tabid. (keep=&var.)
            ;
            drop table DPLOCAL._&varid._&tabid.
            ;
          quit;
        %end;
      %end; /*end loop b*/

   /* finish below to create temporary varmatch by var tables */
      proc sql noprint;
        create table DPLOCAL.&PREFIX.tmp_lkp_&var. as
        select distinct substr(tableid,1,3) as TabID1
             , substr(tableid,5,3) as TabID2
             , count(distinct calculated tabid1) as tablecount
        from infolder.lkp_all_flags (where=(variable1="&var." and checkid in ("201","202")))
        group by 2
        ;
        select distinct tabid2, count(distinct tabid2) into :baselist separated by " ", :basect trimmed
        from DPLOCAL.&PREFIX.tmp_lkp_&var.
        where lowcase(tabid1) in (&sql_tabidlist.)
        ;
      quit;

      %do c=1 %to &basect.; /* one loop per unique Table2 'base' variable */
        %let base=%scan(&baselist.,&c.);
        proc sql noprint;
          select tabid1
               , tabid1
               , count(tabid1) 
          into :tab1list separated by ','
             , :var1list separated by ' '
             , :tab1ct trimmed
          from dplocal.tmp_lkp_&var. (where=(tabid2="&base." and lowcase(tabid1) in (&sql_tabidlist.)))
          ;
        quit;
   /* for a base that is only used once (e.g. COD-DTH match), skip merge step */     
        %if &tabct.=1 %then %do; 
          %local skip;
          proc sql noprint;
            select count (*) into skip trimmed
            from dplocal.tmp_lkp_&var. (where=(tabid1 in ("&base.", strip("&tab1list."))
            ;
          quit;
          %if &skip.=2 %then %let c=%eval(&c.+1);
        %end; 
   /* merge tables by 'base' comparison table (e.g. ENR) */
        %else %do;
          data dplocal.all_match_&var.;
            merge dplocal.tmp_&var._&base. 
          %do t=1 %to &tab1ct.;
            %let tab1=%scan(%bquote(&tab1list.),&t.,%str(,));
              dplocal.tmp_&var._&tab1.
          %end; ;
            by &var.;
          %if %lowcase(&var.)=enctype %then %do;
            /* replace missing '.' values with 0 for all columns */
            %str(array changen _numeric_;
                do over changen;
                if changen=. then changen=0;
              end;)
          %end;
          %else %do;
            /* replace blank ' ' values with '0' for all columns */
            %str(array changec _character_;
                do over changec;
                if changec=' ' then changec='0';
              end;)
          %end;
            format _numeric_ comma15.;
          run;

          %if %lowcase(&var.)=enctype %then %do;
            proc datasets lib=dplocal nolist nowarn nodetails;
              change all_match_&var.=all_l2_&var._match;
            quit;
          %end;
          %else %do;
            proc sql noprint;
              create table dplocal.all_l2_&var._match as
              select &base.
                   , &tab1list.
                   , count(&var.) as count format=comma15.
              from dplocal.all_match_&var.
              group by &base.,&tab1list.
              ;
            quit;
          %end;
        %end;
      %end; /* end loop c */
    %end; /* end loop a */

    proc datasets lib=work memtype=data nolist nodetails nowarn;
      delete tmp_:;
    quit;

  %end; /* end varct > 0 loop*/
  %set_ds (libin=dplocal, dsin_prefix=tmp_length_, libout=dplocal, dsout=all_l2_crosstab_length_value);

  proc datasets lib=dplocal memtype=data nolist nodetails nowarn;
    delete tmp:;
  quit;
%mend l2_ds_crosstable;
/*-------------------------------------------------------------------------------*/
/* END ==> %l2_ds_crosstable                                                     */
/*-------------------------------------------------------------------------------*/


/*********************************************************************************/
/* START ==> %l2_flags_200_207                                                   */
/*********************************************************************************/
%macro l2_flags_200_207;
  %local covtype;
  %if &tabid.=dis %then %let covtype=drugcov;
  %else %let covtype=medcov;

  proc sql noprint;
    create table dplocal._temp as
    select *, count(*) as count
    from &dsin. (keep=patid &datevar.)
    group by 1,2
    ;  
  quit;

  %remove_labels(dplocal,_temp);

  proc sql noprint;
    create table dplocal._&checkid._&tabid. as
    select a.*
    from dplocal._temp as a 
      right join (select distinct patid   
                  from dplocal._temp  
                    except all 
                  select patid 
                  from dplocal.all_match_patid (keep=patid enr &tabid. where=(enr='0' or &tabid.='0'))) as b
    on a.patid=b.patid
    order by a.patid, &datevar.
    ;
    drop table dplocal._temp
    ;
    create table dplocal.tmp_enr as
    select patid
         , enr_start
         , enr_end
    from dplocal.l2_nodup_enr (keep=patid enr_start enr_end &covtype. where=(&covtype.='Y' and enr_start le enr_end))
    ;
  quit;

%mend l2_flags_200_207;
/*-------------------------------------------------------------------------------*/
/* END ==> %l2_flags_200_207                                                     */
/*-------------------------------------------------------------------------------*/

/*********************************************************************************/
/* START ==> %l2_flags_201_202                                                   */
/*********************************************************************************/
%macro l2_flags_201_202;
  proc sql noprint;
    select distinct variable1
         , count(distinct variable1) 
    into :varlist separated by " "
       , :varct trimmed
    from temp_l2_flags (where=(checkid="&checkid."))
    ;
  quit;

  %if &varct. ne 0 %then %do;
    %do v=1 %to &varct.;
      %let var1=%scan(&varlist.,&v.);
      proc sql noprint;
        create table temp as
        select monotonic( ) as row, *
        from temp_l2_flags (where=(checkid="&checkid." and variable1="&var1."))
        ;
      quit;
      %let ct=&sqlobs.;
      %do i=1 %to &ct.;
        proc sql noprint;
          select table1
               , table2
          into :tabid1 trimmed
             , :tabid2 trimmed
          from temp
          where row=&i.
          ;
        quit;
        %if %lowcase(&var1.) ne enctype %then %do;
          proc sql noprint;
            create table flag_&i. as
            select "&tabid1." as table1
                 , "&tabid2." as table2
                 , sum(count) as count
            from dplocal.all_l2_&var1._match
            %if &checkid.=201 %then %do;
              %str(where &tabid1.='1' and &tabid2.='0' and count>0)
            %end;
            %else %if &checkid.=202 %then %do;
              %str(where &tabid1.='0' and &tabid2.='1' and count>0)
            %end;
            group by 1,2
            ;
          quit;
        %end;
        %else %do;
          proc sql noprint;
            create table flag_&i. as
            select "&tabid1." as table1
                 , "&tabid2." as table2
                 , count(*) as count
            from dplocal.all_l2_&var1._match
            %if &checkid.=201 %then %do;
              %str(where &tabid1.>0 and &tabid2.=0)
            %end;
            %else %if &checkid.=202 %then %do;
              %str(where &tabid1.=0 and &tabid2.>0)
            %end;
            group by 1,2
            ;
          quit;
        %end;
        %get_flagid (ntabs=2, nvars=1);
      %end;
    %end;
  %end;
%mend l2_flags_201_202;
/*-------------------------------------------------------------------------------*/
/* END ==> %l2_flags_201_202                                                     */
/*-------------------------------------------------------------------------------*/

/*********************************************************************************/
/* START ==> %l2_flags_205_206                                                   */
/*********************************************************************************/
/* Used to create dataset to check invalid cross-table date relationships        */
/*-------------------------------------------------------------------------------*/
%macro l2_flags_205_206;
  proc sql noprint;
    create table temp as
    select monotonic( ) as row, *
    from temp_l2_flags (where=(checkid="&checkid"))
    ;
  quit;
  %let ct=&sqlobs.;
  %if &ct. ne 0 %then %do;
    %do i=1 %to &ct.;
      proc sql noprint;
        select table1
             , table2
             , variable1
             , variable2
        into :tabid1 trimmed
           , :tabid2 trimmed
           , :var1 trimmed
           , :var2 trimmed
        from temp
        where row=&i.
        ;
      quit;

      %if &checkid.=205 %then %let comp=gt;
      %else %if &checkid.=206 %then %let comp=lt;
      %table_name (n=1);
      %let table1=&table;
      %table_name (n=2);
      %let table2=&table;
      proc sql noprint;
        create table flag_&i. as
        select "&var1." as variable1 length=21
             , "&var2." as variable2 length=21
             , "&tabid1." as table1 
             , "&tabid2." as table2
        from mscdm.&table1. (keep=patid &var1. where=(&var1. ne .)) as a full join
        %if %lowcase(&tabid2.) = %str(enr) %then %do;
          %str(dplocal.l2_nodup_enr (keep=patid &var2.))
        %end;
        %else %do;
          %str(mscdm.&table2. (keep=patid &var2. where=(&var2. ne .)) )
        %end;
        as b
        on a.patid=b.patid
        where %str(a.&var1. &comp. b.&var2.)
        ;
      quit;
      %get_flagid (ntabs=2,nvars=2);
    %end;
  %end;
%mend l2_flags_205_206;
/*-------------------------------------------------------------------------------*/
/* END ==> %l2_flags_205_206                                                     */
/*-------------------------------------------------------------------------------*/

/*********************************************************************************/
/* START ==> l2_flags_223_228_229                                                */
/*********************************************************************************/
/* Create L2 flags for invalid value for 2-variable comp  (checkid=223,228,229)  */
/*-------------------------------------------------------------------------------*/
%macro l2_flags_223_228_229;  
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
             , dataset
             , lookup_table
        into :var1 trimmed
           , :var2 trimmed
           , :ds trimmed
           , :lkp trimmed
        from temp
        where row=&i.
        ;
        select flagcondition into :where trimmed
        from infolder.&lkp.
        where lowcase(variable1)=lowcase("&var1.") and lowcase(variable2)=lowcase("&var2.")
        ;
      quit;

      data flag_&i.;
        set &ds.;
        where %str(&where.);
      run;
 
      %get_flagid (ntabs=1, nvars=2);
    %end;
  %end;
%mend l2_flags_223_228_229;
/*-------------------------------------------------------------------------------*/

/*********************************************************************************/
/* START ==> %l2_flags_226_227                                                   */
/*********************************************************************************/
/* Checkid 226 - Intra-table check for invalid date relationships                */
/*-------------------------------------------------------------------------------*/
%macro l2_flags_226_227;
  proc sql noprint;
    create table temp as
    select monotonic( ) as row, *
    from temp_l2_flags (where=(checkid="&checkid"))
    ;
  quit;
  %let ct=&sqlobs.;
  %if &ct. ne 0 %then %do;
    %if &checkid.=226 %then %let comp=gt;
    %else %if &checkid.=227 %then %let comp=lt;

    %do i=1 %to &ct.;
      proc sql noprint;
        select tableid
             , variable1
             , variable2
        into :tabid trimmed
           , :var1 trimmed
           , :var2 trimmed
        from temp
        where row=&i.
        ;
      quit;
      %table_name (n= );

      proc sql noprint;
        create table flag_&i. as
        select *
        from
        %if %lowcase(&tabid.) = %str(enr) %then %do;
          %str(dplocal.enr_invalid_dates (keep=&var1. &var2.))
        %end;
        %else %do;
          %str(mscdm.&table. (keep=&var1. &var2. where=(&var1. ne . and &var2. ne . and &var1. &comp. &var2.)))
        %end;
        ;
      quit;
      %get_flagid (ntabs=1, nvars=2);
    %end;
    /*%set_ds (libin=work, dsin_prefix=flag_&checkid., libout=work, dsout=flags_l2_&checkid.);*/
  %end;
%mend l2_flags_226_227;
/*-------------------------------------------------------------------------------*/
/* END ==> %l2_flags_226_227                                                     */
/*-------------------------------------------------------------------------------*/

/*********************************************************************************/
/* START ==> %flag_200                                                           */
/*********************************************************************************/
/* Create L2 flags for for all test dates by PatID outside active enrollment     */
/*-------------------------------------------------------------------------------*/
%macro flag_200 (checkid=200);
  %local dsin datevar;
  %let datevar=testdate;
  %let dsin=dplocal._&tabid.;

  %l2_flags_200_207;

  proc sql;
    create table dplocal.temp_&tabid._enr as
    select distinct a.patid
       , case when enr_start le &datevar. le enr_end then 1
              when (&datevar. lt enr_start) or (&datevar. gt enr_end) then 0
              else .
         end as _validdt length=3
       , max(calculated _validdt) as _valid length=3
    from dplocal._&checkid._&tabid. as a left join dplocal.tmp_enr as e
    on a.patid=e.patid
    group by a.patid
    having _valid=0
    ;
    create table dplocal.&tabid._&checkid. as
    select patid, sum(count) as count label="Record Count"
    from dplocal._&checkid._&tabid.
    group by 1
    ;
    drop table dplocal._&checkid._&tabid.
    ;
    create table flag_l2_&checkid._&tabid. as
    select b.flagid
         , b.flag_descr
         , b.flagtype
         , b.abortyn 
         , a.count
    from (select "&checkid." as checkid, count(distinct patid) as count from dplocal.temp_&tabid._enr) a,  
          infolder.lkp_all_flags (where=(checkid="&checkid.")) b
    where a.checkid=b.checkid
    ;
    drop table dplocal.temp_&tabid._enr
    ;
  quit;
%mend flag_200;
/*-------------------------------------------------------------------------------*/
/* END ==> %flag_200                                                             */
/*-------------------------------------------------------------------------------*/

/*********************************************************************************/
/* START ==> %flag_201                                                           */
/*********************************************************************************/
%macro flag_201;
  %l2_flags_201_202;
%mend flag_201;
/*-------------------------------------------------------------------------------*/
/* END ==> %flag_201                                                             */
/*-------------------------------------------------------------------------------*/

/*********************************************************************************/
/* START ==> %flag_202                                                           */
/*********************************************************************************/
%macro flag_202;
  %l2_flags_201_202;
%mend flag_202;
/*-------------------------------------------------------------------------------*/
/* END ==> %flag_202                                                             */
/*-------------------------------------------------------------------------------*/

/*********************************************************************************/
/* START ==> %flag_203                                                           */
/*********************************************************************************/
%macro flag_203;
  proc sql noprint;
    create table tmp1 as
    select a.*, b.dp_length as VarLength1 label=' '
    from temp_l2_flags (drop=variable2--variable4 test: data: look: ms: result_type 
                        where=(checkid="&checkid")) as a 
      left join dplocal.all_l1_scdm_comp (keep=TabID var dp_length) as b
    on lowcase(a.table1)=lowcase(b.TabID) and lowcase(a.variable1)=lowcase(b.var)
    order by variable1, table2, table1
    ;
    create table tmp2 as
    select a.flagid, b.dp_length as VarLength2 label=' '
    from temp_l2_flags (drop=variable2--variable4 test: data: look: ms: result_type 
                        where=(checkid="&checkid")) as a 
      left join dplocal.all_l1_scdm_comp (keep=TabID var dp_length) as b
    on lowcase(a.table2)=lowcase(b.TabID) and lowcase(a.variable1)=lowcase(b.var)
    order by variable1, table2, table1
    ;
    create table tmp3 as 
    select a.*, b.VarLength2
    from tmp1 as a full join tmp2 as b
    on a.flagid=b.flagid
    ;
    create table flag_l2_&checkid. /*(keep=flag: abort:) */ as
    select *, 99999 as count
    from tmp3 (where=(VarLength1 ne VarLength2))
    ;
    create table dplocal.all_l2_crosstab_length_var as
    select table1 as TabID1 length=3, table2 as TabID2 length=3, variable1 as Variable,  VarLength1,  VarLength2
    from tmp3
    order by 3,1,2
    ;
  quit;

  proc datasets lib=work nolist nowarn nodetails memtype=data;
    delete tmp:;
  quit;
%mend flag_203;
/*-------------------------------------------------------------------------------*/
/* END ==> %flag_203                                                             */
/*-------------------------------------------------------------------------------*/

/*********************************************************************************/
/* START ==> %flag_204                                                           */
/*********************************************************************************/
%macro flag_204;
  proc sql noprint;
    create table tmp1 as
    select a.*, b.valuelength as Length1 label=' '
    from temp_l2_flags (drop=variable2--variable4 test: data: look: ms: result_type 
                        where=(checkid="&checkid")) as a          
      left join dplocal.all_l2_crosstab_length_value (keep=TabID variable valuelength) as b
    on lowcase(a.table1)=lowcase(b.TabID) and lowcase(a.variable1)=lowcase(b.variable)
    order by variable1, table2, table1
    ;
    create table tmp2 as
    select a.flagid, b.valuelength as Length2 label=' '
    from temp_l2_flags (drop=variable2--variable4 test: data: look: ms: result_type    
                        where=(checkid="&checkid")) as a 
      left join dplocal.all_l2_crosstab_length_value (keep=TabID variable valuelength) as b
    on lowcase(a.table2)=lowcase(b.TabID) and lowcase(a.variable1)=lowcase(b.variable)
    order by variable1, table2, table1
    ;
    create table tmp3 as 
    select a.*, b.Length2
    from tmp1 as a full join tmp2 as b
    on a.flagid=b.flagid
    ;
    create table flag_l2_&checkid. (keep=flag: abort:) as
    select *, 99999 as count
    from tmp3 (where=(Length1 ne Length2))
    ;
  quit;

  proc datasets lib=work nolist nowarn nodetails memtype=data;
    delete tmp:;
  quit;
%mend flag_204;
/*-------------------------------------------------------------------------------*/
/* END ==> %flag_204                                                             */
/*-------------------------------------------------------------------------------*/

/*********************************************************************************/
/* START ==> %flag_205                                                           */
/*********************************************************************************/
%macro flag_205;
  %l2_flags_205_206;
%mend;
/*-------------------------------------------------------------------------------*/
/* END ==> %flag_205                                                             */
/*-------------------------------------------------------------------------------*/

/*********************************************************************************/
/* START ==> %flag_206                                                           */
/*********************************************************************************/
%macro flag_206;
  %l2_flags_205_206;
%mend;
/*-------------------------------------------------------------------------------*/
/* END ==> %flag_206                                                             */
/*-------------------------------------------------------------------------------*/

/*********************************************************************************/
/* START ==> %flag_207                                                           */
/*********************************************************************************/
%macro flag_207;
  proc sql noprint;
    create table temp as
    select monotonic( ) as row, *
    from temp_l2_flags (where=(checkid="&checkid"))
    ;
  quit;
  %let ct=&sqlobs.;

  %if &ct. ne 0 %then %do;
    %do i=1 %to &ct.;
      proc sql noprint;
        select table1
             , variable1
          into :tabid trimmed
             , :datevar trimmed
        from temp
        where row=&i.
        ;
      quit;

      %table_name (n= );
      %let dsin=mscdm.&table.;

      %l2_flags_200_207;

      proc sql;
        create table dplocal._tmp as
        select a.patid
             , a.&datevar.  
             , a.count as temp_count
             , b.total_patid
        from dplocal._&checkid._&tabid. as a, (select patid, sum(count) as total_patid from dplocal._&checkid._&tabid. group by 1) as b
        where a.patid=b.patid
        ;
        drop table dplocal._&checkid._&tabid.
        ;
        create table dplocal._tmp1 as
        select a.*
             , b.enr_start
             , b.enr_end
             , case when enr_start le &datevar. le enr_end then 1
               when (&datevar. lt enr_start) or (&datevar. gt enr_end) then 0
               else .
               end as _validdt length=3
             , max(calculated _validdt) as _valid length=3
        from dplocal._tmp as a left join dplocal.tmp_enr as b
        on a.patid = b.patid 
        group by a.patid
        having _valid=0
        ;
        drop table dplocal._tmp, dplocal.tmp_enr
        ;
        create table dplocal.&tabid._&datevar._&checkid. as
        select distinct patid, total_patid as count label="Record Count"
        from dplocal._tmp1
        ;
        drop table dplocal._tmp1
        ;
        create table flag_l2_&checkid._&tabid. as
        select b.flagid
             , b.flag_descr
             , b.flagtype
             , b.abortyn 
             , sum(a.count) as count
        from (select "&checkid." as checkid, count from dplocal.&tabid._&datevar._&checkid.) a, temp (where=(row=&i.)) b
        where a.checkid=b.checkid
        group by 1,2,3,4
        ;
      quit;
    %end;
  %end;
%mend flag_207;
/*-------------------------------------------------------------------------------*/
/* END ==> %flag_207                                                             */
/*-------------------------------------------------------------------------------*/

/*********************************************************************************/
/* START ==> %flag_211                                                           */
/*********************************************************************************/
/* Check 211 - Perform duplicate record by key variables                         */
/*-------------------------------------------------------------------------------*/
%macro flag_211;
  %local i;
  proc sql noprint;
    create table temp as
    select monotonic( ) as row, *
    from temp_l2_flags (where=(checkid="&checkid."))
    ;
  quit;
  %let ct=&sqlobs.;

  %if &ct. > 0 %then %do;
    %do i=1 %to &ct.;
      proc sql noprint;
        select tableid into :tabid trimmed
        from temp
        where row=&i.
        ;
        create table flag_&i. as
        select b.flagid
             , b.flag_descr
             , b.flagtype
             , b.abortyn 
             , a.count_dup as count
        from dplocal.all_l2_nobs_dup a, temp (where=(row=&i.)) b
        where a.TabID=b.tableid
        ;
      quit;
      %get_flagid (ntabs=1, nvars=0);
    %end;
  %end;
%mend flag_211;
/*-------------------------------------------------------------------------------*/
/* END ==> %flag_211                                                             */
/*-------------------------------------------------------------------------------*/

/*********************************************************************************/
/* START ==> %flag_215                                                           */
/*********************************************************************************/
/* Overlapping enrollment spans by PatID, enr_start, enr_end;                    */
/* Regardless of coverage type (must be 2nd L2 flag macro run)                   */
/*-------------------------------------------------------------------------------*/
%macro flag_215;

  proc sql noprint;
    select dataset into :ds trimmed
    from temp_l2_flags (where=(checkid="&checkid"))
    ;
  quit;

  %let recct=0;
  proc sql noprint;
    select count(*) into :recct trimmed
    from &ds.
    ;
  quit;

  data tmp;
    checkid="&checkid";
    count=&recct. ;
  run;

  proc sql noprint;
    create table flag_l2_&checkid. as
    select a.flagid
         , a.flag_descr
         , a.flagtype
         , a.abortyn 
         , b.count format=comma15. informat=comma15.
    from temp_l2_flags (where=(checkid="&checkid.")) a right join tmp b 
    on a.checkid=b.checkid
    ;
    drop table tmp
    ;
  quit;
%mend flag_215;
/*-------------------------------------------------------------------------------*/
/* END ==> %flag_215                                                             */
/*-------------------------------------------------------------------------------*/

/*********************************************************************************/
/* START ==> %flag_216                                                           */
/*********************************************************************************/
/* Identify consecutive, non-bridged enrollment records by patid,enr_start,      */
/*   enr_end, medcov, drugcov, and chart                                         */
/*-------------------------------------------------------------------------------*/
%macro flag_216;
  data flag; 
    set dplocal.l2_nodup_enr (where=(enr_start ne . and enr_end ne . and enr_start ge enr_end));
    by patid;
    if first.patid then do;
      lag_start=.;
      lag_end=.;
      lag_medcov=' ';
      lag_drugcov=' ';
      lag_chart=' ';
    end;  
    else do;
      lag_start=lag(enr_start);
      lag_end=lag(enr_end);
      lag_medcov=lag(medcov);
      lag_drugcov=lag(drugcov);
      lag_chart=lag(chart);
      if enr_start eq (lag_end+1) and medcov=lag_medcov and drugcov=lag_drugcov and chart=lag_chart then output flag;
    end;
    drop lag_:;
  run;

  proc sql noprint;
    create table flag_l2_&checkid. as
    select b.flagid
         , b.flag_descr
         , b.flagtype
         , b.abortyn 
         , a.count
    from (select count(*) as count, "&checkid." as checkid from flag) a, temp_l2_flags (where=(checkid="&checkid.")) b
    where a.checkid=b.checkid
    ;
  quit;
%mend flag_216;
/*-------------------------------------------------------------------------------*/
/* END ==> %flag_216                                                             */
/*-------------------------------------------------------------------------------*/

/*********************************************************************************/
/* START ==> %flag_223                                                           */
/*********************************************************************************/
/* Intra-table check for invalid data relationship across 2 variables            */
/*-------------------------------------------------------------------------------*/
%macro flag_223;
  %l2_flags_223_228_229; 
%mend flag_223;
/*-------------------------------------------------------------------------------*/
/* END ==> %flag_223                                                             */
/*-------------------------------------------------------------------------------*/

/*********************************************************************************/
/* START ==> %flag_226                                                           */
/*********************************************************************************/
/* Intra-table check for invalid date relationship (var1 gt var2)                */
/*-------------------------------------------------------------------------------*/
%macro flag_226;
  %l2_flags_226_227; 
%mend flag_226;
/*-------------------------------------------------------------------------------*/
/* END ==> %flag_226                                                             */
/*-------------------------------------------------------------------------------*/

/*********************************************************************************/
/* START ==> %flag_227                                                           */
/*********************************************************************************/
/* Intra-table check for invalid date relationship (var1 lt var2)                */
/*-------------------------------------------------------------------------------*/
%macro flag_227;
  %l2_flags_226_227; 
%mend flag_227;
/*-------------------------------------------------------------------------------*/
/* END ==> %flag_227                                                             */
/*-------------------------------------------------------------------------------*/

/*********************************************************************************/
/* START ==> %flag_228                                                           */
/*********************************************************************************/
/* Intra-table check for invalid data value relationship across 2 variables      */
/*-------------------------------------------------------------------------------*/
%macro flag_228;
  %l2_flags_223_228_229; 
%mend flag_228;
/*-------------------------------------------------------------------------------*/
/* END ==> %flag_228                                                             */
/*-------------------------------------------------------------------------------*/

/*********************************************************************************/
/* START ==> %flag_229                                                           */
/*********************************************************************************/
/* Intra-table check for invalid variable value based on specified date          */
/*-------------------------------------------------------------------------------*/
%macro flag_229;
  %l2_flags_223_228_229; 
%mend flag_229;
/*-------------------------------------------------------------------------------*/
/* END ==> %flag_229                                                             */
/*-------------------------------------------------------------------------------*/


/*********************************************************************************/
/* START ==> %level2                                                             */
/*********************************************************************************/
%macro level2 (level=2);
  /* Create temporary lookup table */
  %let sql_tabidlist=%str("&tabid.");
  %l2_lkp_table (abortyn=n, flagtype= , crosstable=n);

  /* Create a macro variable with list of unique CheckIds from temporary lookup */
  proc sql noprint;
    select distinct checkid
         , count(distinct checkid) 
    into :checkidlist separated by ' '
       , :checkct trimmed
    from temp_l2_flags
    ; 
  quit; 

    %if %sysevalf(&checkct. > 0) %then %do;
    /* Loop through each CheckID and output temporary flags datasets by CheckID  */
      %do c=1 %to &checkct.;
        %let i=;
        %let checkid=%scan(&checkidlist.,&c.);
        %str(%flag_&checkid.);
      %end;
  /* Combine temporary flags datasets  */
      %set_ds (libin=work, dsin_prefix=flag_l2_, libout=dplocal, dsout=l2_flags_&tabid.);
    %end;
  proc datasets kill lib=work memtype=data nolist nowarn nodetails;
  quit;
%mend level2;
/*-------------------------------------------------------------------------------*/
/* END ==> %level2                                                               */
/*-------------------------------------------------------------------------------*/

/*********************************************************************************/
/* START ==> %date_percentiles                                                   */
/*********************************************************************************/
%macro date_percentiles (libin=, dsin=, libout=, dsout=, vars=);
  proc means nolabels data=&libin..&dsin. (keep=&vars. n) missing vardef=weight StackODSOutput 
       n min p1 P5 P25 median P75 P95 p99 max; 
    var &vars.;
    weight n;
    ods output summary=&libout..&dsout.;
  run;

  data &libout..&dsout. (drop=var);
    length TabID $3 Variable $12;
    set &libout..&dsout. (rename=(variable=var));
    TabID=upcase("&tabid.");
    variable=var;
    format min--max yymmdd10.;
  run;
%mend date_percentiles;
/*-------------------------------------------------------------------------------*/
/* END ==> %date_percentiles                                                     */
/*-------------------------------------------------------------------------------*/

/*********************************************************************************/
/* PROC MEANS that sums numeric variable over a class of variables (NO OUTPUT) */
/*********************************************************************************/
%macro l2_procmeans_sum (libin=,dsin=,libout=,dsout=,keepvars=,vars=,classvars=,names=,numobs=);
  proc means noprint nway data=&libin..&dsin.(obs=&numobs. keep=&keepvars.) missing;
    var &vars.;
    class &classvars.;
    output out = &libout..&dsout.(drop=_:) &names.;
  run;
  %remove_labels(&libout.,&dsout.);
%mend l2_procmeans_sum;


/*********************************************************************************/
/* PROC MEANS WITH NWAY CLASS 1 VARIABLE ONLY + SPECIFIC FORMAT FOR THAT CLASSVAR*/
/*********************************************************************************/
%macro mscdm_means_nway_format_sum 
  (libin=,dsin=,libout=,dsout=,keepvars=,vars=,classvars=,names=,format=,formatvar=,numobs=);
  proc means nway noprint data=&libin..&dsin.(obs=&numobs. keep=&keepvars.) missing;
    var &vars.;
    class &classvars.;
    output out = &libout..&dsout.(drop=_:) &names.;
    format &formatvar. &format..;
  run;
  %remove_labels(&libout.,&dsout.);
%mend mscdm_means_nway_format_sum;


/*********************************************************************************/
/* Macro Proc Print to procedure for output listing and .log files               */
/*********************************************************************************/
%macro reset_printto(parm);
  proc printto log=runlog /*print=runlst*/ &parm.;
  run;
  %sysfunc(ifc(%eval(%sysfunc(fileref(msoclog)) <= 1), filename msoclog clear ,));
  page;
%mend reset_printto;

%macro printto_strt;
  options pagesize=40 linesize=200 orientation = landscape number;
  proc printto log = logfile print = lisfile ;
  run;
%mend printto_strt;

%macro printto_end;
  proc printto;
  run;
  quit;
%mend printto_end;


/*********************************************************************************/
/* Module Level Signature File macro for QA                                      */
/*********************************************************************************/
%MACRO SIGNATURE_BEGIN(MODULE);
  /*Signature file start code*/
  %global &module.start &module.stop;
  %global start;

  data _NULL_;
    temp=DATETIME();
    call symput("&MODULE.START",temp);
    call symput('STARTDATE',put(datepart(temp),date9.));
    call symput('STARTTIME',put(timepart(temp),time4.));
  run;
%MEND SIGNATURE_BEGIN;

%MACRO SIGNATURE_END(MODULE);
/*Signature file end code*/
data _NULL_;
   temp=DATETIME();
   seconds=temp-&&&module.start.;
   hours=int(seconds/3600);
   minutes=int((seconds-hours*3600)/60);
   seconds2=int((seconds-hours*3600-minutes*60));
   call symput("&MODULE.STOP",temp);
   call symput('hours',put(hours,4.0));
   call symput('minutes',put(minutes,2.0));
   call symput('seconds2',put(seconds2,2.0));
   call symput('seconds',put(seconds,12.0));
run;
/*Create signature file*/
data signature;
   DPID="&DPID.";                                    
   SiteID="&SITEID.";                                   
   MSReqID="&MSReqID.";
   MSProjID="&MSProjID.";
   MSWPType="&MSWPType.";
   MSWPID="&MSWPID.";
   MSDPID="&MSDPID.";
   MSVerID="&MSVerID.";
   QAVer="&QAVer.";
   SCDMVer="&SCDMVer.";
   Module="&MODULE."; 
   OSABBR="&sysscp.";
   OSNAME="&sysscpl.";
   SASVersion="&sysver.";
   SASVersionLong="&sysvlong.";
   RunType="&sysenv.";
   NCPU="&sysncpu.";
   format StartTime StopTime datetime21.2; 
   StartTime=trim(left("&&&MODULE.START."));                                
   StopTime=trim(left("&&&MODULE.STOP."));
   Seconds=trim(left("&Seconds.")); 
   format RunTime $20.; 
   RunTime=strip("&hours. h &minutes. m &seconds2. s"); 
   output;
run;

proc transpose data=signature out=dplocal.&prefix.&MODULE._signature (rename=(_NAME_=Variable COL1=Value));
   var _ALL_;
run;
%remove_labels(dplocal,&prefix.&module._signature);
%MEND SIGNATURE_END; 


/*********************************************************************************/
/* Min/Max Dates macro copied and adapted for QA package                         */
/*********************************************************************************/
/**********************************************************************************
*                             SENTINEL MACRO
***********************************************************************************
* NAME:  ms_min_max_dates.sas
*
* PURPOSE:  
*   Calculates min/max dates of data completeness for MSCDM Core tables and  
*   stores results in a SAS dataset.  This data will be used by Common-Components 
*   to populate the MinDate and MaxDate parameters.
*
* MAJOR STEPS: 
*   1- For each MSCDM Core table, use metadata from QA results to 
*      A- calculate MaxDate as the largest date with at least X% of the prior 
*         year-month row    
*      B- calculate MinDate as the smallest date with at least X% of the next
*         year-month row    
       C- append calculated results to min/max datasets
*   2- Create final dataset
*      A- derive overall Min/Max dates from Step 1-C, 
*      B- transpose datasets from Step 1-C 
*      C- create final dataset by merging datasets from Step 2-A and Step 2-B 
*
* KEY DEPENDENCIES/CONSTRAINTS:
*   - Externally defined macro variables DPID and SITEID
*   - Access to Infolder.lkp_all_minmax_dates that defines key macro variables
*   - Access to QA datasets with record counts by year-month
*   - Date algorithm may not work well with all types of distributions 
*     (Example: a distribution with a large drop proceeded or followed by a long 
*               flattail of many months) 
*   - This version works with QA data that stores the minimum date for a given
*     year-month row.  Thus, when calculating the maximum dates, we need to push  
*     out the dates to the end of month.
*
*----------------------------------------------------------------------------------
* USER-PARAMETERS:
*   threshold...minimum qualifying percentage of current/prior or current/next 
*              (default: .80)
*
*----------------------------------------------------------------------------------
*/
%macro MS_MIN_MAX_DATES (threshold=.80);
 /*-------------------------------------*/
 /* 0- Setup Tasks                      */
 /*-------------------------------------*/     
  %local i;
  /* Create the list of tables to loop through */
  proc sql noprint;
    select c.tabid into :tabidlist separated by ' '
    from (select a.*
          from infolder.lkp_all_minmax as a right join msoc.control_flow_3 as b
          on lowcase(a.tabid)=lowcase(b.module)
          where lowcase(b.execute_flag)="y" and b.cc_table ne "X") as c
    ; 
  quit;
  proc datasets library=work nolist nowarn nodetails ;
    delete maxDate: minDate:;
  quit ;
  %do i = 1 %to %sysfunc(countw(&tabidlist.)); /* BEGIN tbl_loop */
    %let tabid=%lowcase(%scan(&tabidlist.,&i.));
    proc sql noprint;
      select tabid
           , library
           , dataset
           , datevar
           , countvar
           , sumyn
           , dpminmax
      into :tabid trimmed
         , :libin trimmed
         , :dsin trimmed
         , :date trimmed
         , :count trimmed
         , :sum trimmed
         , :inc trimmed
      from infolder.lkp_all_minmax (where=(tabid="&tabid."))
      ;
    quit; 
    %if %sysfunc(exist(&libin..&dsin., data)) %then %do;
      %if %sysevalf(%lowcase(&sum.)=y) %then %do;
        proc sql noprint;
          create table _temp as
          select &date. as _date
               , sum(&count.) as count
          from &libin..&dsin. (keep=&date. &count.)
          group by 1
          ;
        quit;
      %end;
      %else %do;
        proc sql noprint;
          create table _temp as
          select &date. as _date
               , tempct as count
          from &libin..&dsin. (keep=&date. &count. rename=(&count.=tempct))
          order by 1
          ;
        quit;
      %end;
      proc sql noprint;
        create table temp as
        select mdy(input(substr(_date,6,2),2.),1,input(substr(_date,1,4),4.)) as Date
             , count
        from _temp
        ;
        drop table _temp
        ;
      quit;
       /* Get number of months for tbl*/
      %local dsid n_months rc ;
      %let dsid = %sysfunc(open(work.temp, IS));
      %let n_months = %sysfunc(attrn(&dsid, NLOBS));
      %let rc = %sysfunc(close(&dsid));
  /* NOTE: The logic for Steps 1-A and 1-B below are intermingled */
    /*---------------------------------------------------------*/
    /*  Contributes to Step 1-A:                               */
    /*  Grab prior month count and attach to current month     */
    /*  and flag if curr month qualifies for max date          */ 
    /*---------------------------------------------------------*/            
      data temp ;
        set temp ;
        by date ;                            
        month_n = _n_ ;            
        lagPriorCount = lag(count) ;    
        if lagPriorCount ne . then do ;
          format percentPrev percent8.2 ;
          percentPrev = (count / lagPriorCount) ;
          qualifyMax = (percentPrev ge &threshold) ;    
        end ;            
      run ;      
    /*----------------------------------------------------------*/         
    /*  Contribute to Step 1-B                                  */         
    /*  Grab next month count and attach to current month and   */
    /*  flag if curr month qualifies for min date               */ 
    /*----------------------------------------------------------*/                 
      proc sort data=temp;
        by descending date;
      run;
      data temp;
        set temp;      
        by descending date;            
        NextCount = lag(count) ;    
        if NextCount ne . then do ;
          format percentNext percent8.2 ;
          percentNext = (count / NextCount) ;
          qualifyMin = (percentNext ge &threshold) ;    
        end ;                        
      run ;      
    /*---------------------------------------------------------*/         
    /* Finalizes Step 1-A:                                     */                  
    /* Grab first qualifing MaxDate                            */
    /*---------------------------------------------------------*/                 
      data MaxDate_&tabid.;
        set temp;
        by descending date; 
        type=upcase("&tabid.");  
        include="&inc.";
        retain trap 0 ;
        if (trap eq 0) and (qualifyMax eq 1) then do ;               
          label months_from_last = 'Number of months from last month with any data' ;
          months_from_last = month_n - &n_months ;
          output ;
          trap = 1 ;
          stop ;            
        end ;
        rename date=MaxDate;
        keep date months_from_last include type ;
      run ;
    /*---------------------------------------------------------*/         
    /* Finalizes Step 1-B:                                     */                           
    /* Grab first qualifing MinDate                            */
    /*---------------------------------------------------------*/               
      proc sort data=temp;
        by date;
      run;
      data MinDate_&tabid.;
        set temp;
        by date;  
        type=upcase("&tabid."); 
        include="&inc."; 
        retain trap 0 ;
        if (trap eq 0) and (qualifyMin eq 1) then do ;               
          output ;
          trap = 1 ;
          stop ;            
        end ;
        rename date=MinDate;
        keep date month_n include type ;
      run;

 /*-------------------------------------------------------------*/         
 /* 1-C Append min dates together and append max dates together */
 /*-------------------------------------------------------------*/         
      proc append force base=minDates data=MinDate_&tabid. ;
        format MinDate yymmdd10. ;
      run ;    
      proc append force base=maxDates data=MaxDate_&tabid. ;
        format MaxDate yymmdd10. ;       
      run ; 
  /* Fix max dates to be the last day of the month */
      data maxDates ;
        set maxDates (rename=(maxDate=maxDt)) ;
        format maxDate yymmdd10. ;        
        maxDate = intnx('month',maxDt,0,'end') ;
        drop maxDt ;
      run ;
      %if &i.=%sysfunc(countw(&tabidlist.)) %then %do; /* do if last table */
        proc sql noprint;
          create table dplocal.tmp_minmax_dates as
          select a.type as TabID length=3
               , a.mindate
               , b.maxdate
          from mindates a, maxdates b
          where a.type=b.type
          ;
        quit;
      %end;
    %end;
    %else %do;
      %let syscc=9999;
    %end;
  %end;
  %if %sysevalf(&syscc. ne 9999) %then %do;
  /*--------------------------------------*/
  /* 2-Create Final Dataset               */
  /*--------------------------------------*/
  /* 2-A Create Overall Minimum and Maximum Dates with Complete Data */
    proc sql ;
      create table minDate as
      select max(minDate) as DP_MinDate format=yymmdd10. 
           label='Overall DP Minimum Date for Data Completeness'
      from minDates (where=(lowcase(include)='y'))
      ;
      create table maxDate as
      select min(maxDate) as DP_MaxDate format=yymmdd10. 
           label='Overall DP Maximum Date for Data Completeness'
      from maxDates (where=(lowcase(include)='y'))
      ;        
    quit;  
  /* 2-B Transpose table specific dates from rows to cols */
    proc transpose data=minDates (where=(lowcase(include)='y')) out=transposed_minDates suffix=_MinDate;
      var minDate ;
      id type ;
      format minDate yymmdd10. ;
    run ;
    proc transpose data=maxDates (where=(lowcase(include)='y')) out=transposed_maxDates suffix=_MaxDate;
      var maxDate ;
      id type ;
      format maxDate yymmdd10. ;      
    run ;
  /* 2-C Save Final Dataset */
    options mergenoby=nowarn ;
    data msoc.MinMax_Dates;     
      %add_dpids_ds
       merge minDate (keep=DP_MinDate)
           maxDate (keep=DP_MaxDate)
           transposed_minDates (drop= _:)
           transposed_maxDates (drop=_:) ;
    run ;
    options mergenoby=warn ;
    proc datasets lib=work nolist nodetails nowarn;
      delete mindate: maxdate: trans: temp;
    quit;
  %end;
%mend ms_min_max_dates;


/*********************************************************************************/
/* Disable syntax checking so that we may continue processing if err ors         */
/*********************************************************************************/
%macro _disable_syntax_checks ;
  options obs=max ;
  options NOSYNTAXCHECK ;
  %if &SYSSCP eq WIN %then %do ;
    options NODMSSYNCHK ;
  %end ; 
  run ;
%mend ;

/*********************************************************************************/
/* Enable syntax checking                                                        */
/*********************************************************************************/
%macro _enable_syntax_checks ;
  options obs=max ;
  options SYNTAXCHECK ;
  %if &SYSSCP eq WIN %then %do ;
    options DMSSYNCHK ;
  %end ; 
  run ;
%mend ;


/*********************************************************************************/
/* Get list of all subdirectories / files                                        */
/*********************************************************************************/
%macro get_dir_file_names(
    type = ,           /* Specify a type to search [dir_name | file_name]  */
    root='./'   ,      /* Root to start search                             */
    out=_data_  ,      /* Output data set with search results              */
    source=     ,      /* Value for optional SOURCE variable               */
    filter=1           /* directory/file filter                            */
    );

/* Acknowledgement: This macro has been adapted from Jack Hamilton's macro      */
/*                  'get_file_names' to search for either files or directories  */

/* The MOPEN function returns a 0 for directories and a positive number for files. */
  %local found_type ; 
  %if %lowcase(&type) eq dir_name %then %do ;
    %let found_type = eq ;    /* equal to 0 means a directory is found */
  %end ;
  %else %if %lowcase(&type) eq file_name %then %do ;
    %let found_type = gt ;    /* > 0 means a file is found */
  %end ;  
 
  data &OUT.;
    keep name type ;
    retain type "&type" ;
  %if %length(&SOURCE.) ne 0 %then %do;
    retain source &SOURCE.;
    keep source;
  %end;
    length fref $8  name $600;
    rc = filename(fref, &ROOT.);
    if rc = 0 then do;
      did = dopen(fref);
      rc = filename(fref);
    end;
    else do;
      length msg $200.;
      msg = sysmsg();
      put msg=;
      did = .;
    end;
    if did <= 0 then putlog "ERR"'OR: Unable to open directory.';
    dnum = dnum(did);
    do i = 1 to dnum;
    name = dread(did, i);
    /* If this entry is the right type, then output. */
    fid = mopen(did, name);
    if fid &found_type 0 then if &FILTER. then output;
    end;
    rc = dclose(did);
    rc = filename(fref);        
  run;

%mend get_dir_file_names ;

*-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-;
* End 00.1_mscdm_standard_macros.sas                                              ;
*-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-;
