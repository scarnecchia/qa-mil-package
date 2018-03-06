/*-------------------------------------------------------------------------------------*\
|  PROGRAM NAME: 99.2_mscdm_data_qa_review-level3.sas                                   |
|                                                                                       |
|  QA PACKAGE VERSION: 4.0.3                                                            |
|---------------------------------------------------------------------------------------|
|  PURPOSE:                                                                             |
|     The purpose of the program is to create cross-table level 3 output datasets for   |
|     all SCDM tables                                                                   |
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
%timestamp(&module._start);
/*---------------------------------------------------------------------------------*/
/* Combine temporary flags datasets                                                */
/*---------------------------------------------------------------------------------*/
%macro l2_flags_final;
  data temp_flag;
    set dplocal.&prefix.all_l2_flags:;
  run;

  %ISDATA(dataset = temp_flag);
  %IF &NOBS. > 0 %then %do;
  proc sql noprint;
    create table all_l1_l2_flags as
    select flagid, abortyn, flagtype, flag_descr, count as count format=comma15. informat=comma15.
    from temp_flag (where=(count gt 0))
    %if %sysfunc(exist(dplocal.&prefix.all_l1_flags,data)) %then %do;
      %str(union all 
           select flagid, abortyn, flagtype, flag_descr, count as count format=comma15. informat=comma15.
           from dplocal.&prefix.all_l1_flags)
    %end;
    ;
    create table dplocal.&Prefix.all_l1_l2_flags as
    select flagid, abortyn, flagtype, flag_descr, sum(count) as count format=comma15. informat=comma15.
    from all_l1_l2_flags
    group by 1,2,3,4
    order by 1,3
    ;
    drop table temp_flag, all_l1_l2_flags
    ;
  quit;
  %END;
  %ELSE %DO;
  	%ISDATA(dataset = dplocal.&prefix.all_l1_flags);
	%IF &NOBS. > 0 %THEN %DO;
		 proc sql noprint;
   		   create table all_l1_l2_flags as
           select flagid, abortyn, flagtype, flag_descr, count as count format=comma15. informat=comma15.
           from dplocal.&prefix.all_l1_flags
    	  ;
    	 create table dplocal.&Prefix.all_l1_l2_flags as
    	 select flagid, abortyn, flagtype, flag_descr, sum(count) as count format=comma15. informat=comma15.
    	 from all_l1_l2_flags
    	 group by 1,2,3,4
    	order by 1,3
    	;
    	drop table  all_l1_l2_flags
    	;
  	quit;
   %END;
 %END;

  proc datasets lib=dplocal nolist nodetails nowarn;
    delete l2_flags_:;
  quit;

%mend l2_flags_final;


/*********************************************************************************/
/*Suspect Linkages
/*This describes evaluating linkages and producing a detail report for the Data  */
/*Partner and an aggregate file for the SOC.  Note that there are no abort rules */
/*for these checks.																 */
/*********************************************************************************/
%macro suplinkage;

	%let birth_types = %str(1 2 3 4 5);
	%let level = 3;

	 proc sql noprint;
    	select module
       , count(*) 
    	into :tabidlist separated by ' '
       , :tabct trimmed
    	from dplocal.&prefix.control_flow_3 (where=(/*execute_flag='y' and */cc_table ne 'X'))
    	;
  	quit;

	/*Birth_Type= 1-5 and number of linked records per  MPatID/ADate combination differs */
  	%put &tabidlist.;
  	%do a=1 %to &tabct.;
	 	%let tabid=%scan(&tabidlist.,&a.);
		%do b = 1 %to %sysfunc(countw(&birth_types.));
		%let bt = %scan(&birth_types,&b.);
		proc sql;
		 	create table linkage&b. as
		 	select count(distinct cpatid) as crows, mpatid, adate, encounterid, birth_type
		 	from mil.&&&tabid.table
		 	where birth_type = &bt.
			and not missing(cpatid) and not missing(mpatid) /*Linked Record*/
			group by mpatid, adate, encounterid, birth_type
			order by mpatid, adate, encounterid, birth_type;
		quit;

		data flag_&b._&a.;
			 set linkage&b.;
			 length message $300 flag_descr $255;
			 length flagid $21;
			 length FlagType $4 AbortYN $1;
			 flag_descr = cat("Birth_Type (",birth_type,") not consistent with number of linkages; confirmation required");
			 flagid = cats("%upcase(&tabid.)_",&level.,"_00_00-0_37&b.");
			 FlagType = "Warn";
			 AbortYN = "N";
			 flag_l3 = 0;
			 if crows ne birth_type then do;
			 	message = cat("MPatID (",strip(mpatid),"), EncounterID (",strip(encounterid),"), Adate (",put(adate, mmddyy10.),
							 	  "), Birth_type (",birth_type,"):Birth_Type value not consistent with number of linkages; confirmation required");
				flag_l3 = 1;
			end;
			if flag_l3;
		run;
		
		%ISDATA(dataset = flag_&b._&a.);
		%if &NOBS. > 0 %then %do;
			proc sql;
	          create table %str(dplocal.flag_l3_37&b._&tabid.) as
			   select flagid, message, flag_descr, flagtype, abortyn, count(*) as count	
					  from  flag_&b._&a.
					  group by flagid, message, flag_descr, flagtype, abortyn;
				 drop table flag_&b._&a.
      				;
    		quit;
		%end;
	  	%end;
	 %end;
	
	 /*QA for Birth_Type= 2-8 and no CPatIDs are linked*/
	 %do a=1 %to &tabct.;
	 	%let tabid=%scan(&tabidlist.,&a.);
			proc sql;
	   			create table %str(dplocal.flag_l3_394_&tabid.) as
					select cats("%upcase(&tabid.)_",&level.,"_00_00-0_394") as flagid length =21
						  ,cat("MPatid (",strip(mpatid),"), EncounterID (",
							   strip(Encounterid),"), Adate (",put(adate, mmddyy10.),"), Birth_Type (",birth_type,"): No linkages were found; confirmation required")
							as message length = 300
						  ,cat("Birth_Type= 2-8 and no CPatIDs are linked") as flag_descr length = 255
						  ,"Warn" as Flagtype length = 4
						  ,"N" as abortyn length = 1
						  ,count(*) as count
					 from mil.&&&tabid.table
					where 2 <= birth_type <= 8
					and missing(Cpatid)
					group by calculated flagid, calculated message, calculated flag_descr, flagtype, calculated abortyn;
		     quit;
	%end;

	/*MPatID not linked to CPatID OR CPatID not linked to MPatID*/
	%do a=1 %to &tabct.;
	 	%let tabid=%scan(&tabidlist.,&a.);
			proc sql;
	   			create table %str(dplocal.flag_l3_396_&tabid.) as
					select cats("%upcase(&tabid.)_",&level.,"_00_00-0_396") as flagid length =21
						  ,cat("MPatid (",strip(mpatid),"), EncounterID (",
							   strip(Encounterid),"), Adate (",put(adate, mmddyy10.),"): No linkage to infant was found; confirmation required")
							as message length = 300
						  ,cat("MPatID not linked to CPatID") as flag_descr length = 255
						  ,"Warn" as Flagtype length = 4
						  ,"N" as abortyn length = 1
						  ,count(*) as count
					 from mil.&&&tabid.table
					where missing(Cpatid) and not missing(mpatid)
					group by calculated flagid, calculated message, calculated flag_descr, flagtype, calculated abortyn;
		     quit;
	%end;

	%do a=1 %to &tabct.;
	 	%let tabid=%scan(&tabidlist.,&a.);
			proc sql;
	   			create table %str(dplocal.flag_l3_397_&tabid.) as
					select cats("%upcase(&tabid.)_",&level.,"_00_00-0_397") as flagid length =21
						  ,cat("CPatid (",strip(Cpatid),"), CBirth_Date (",put(CBirth_Date, mmddyy10.),"): No linkage to mother/delivery was found; confirmation required")
							as message length = 300
						  ,cat("MPatID not linked to CPatID") as flag_descr length = 255
						  ,"Warn" as Flagtype length = 4
						  ,"N" as abortyn length = 1
						  ,count(*) as count
					 from mil.&&&tabid.table
					where not missing(Cpatid) and missing(mpatid)
					group by calculated flagid, calculated message, calculated flag_descr, flagtype, calculated abortyn;
		     quit;
	%end;



	/*MLName, MFName linked to multiple rows of same values of CLName, CFName, but with different CPatID values*/
	%if %sysfunc(exist(mil.&MISTABLE.)) %then %do;

		data temp1;
			 set mil.&MISTABLE;
			 length cpatidMname $255;
			 length CName $41;
			 if not missing(cpatid) and not missing(mpatid); /*Linked record*/
			 cpatidMname = cats(strip(Cpatid),strip(lowcase(MFName)),":",strip(lowcase(MLName)));
			 CName = cat(strip(CFName),":",strip(CLName));
		run;

	    proc sort data = temp1 nodupkey;
			by CName cpatidMname;
		run;

		data flag_1;
			 set temp1;
				by CName cpatidMname;
			 length l_key $41;
			 length count 3.;
			 retain l_key count;
			 
			 if first.CName then do;
			 	 l_key = cpatidMname;
				 count = 1;
			end;
			else do;
				 if l_key ne cpatidMname then count = count+1;
				  l_key = cpatidMname;
			end;
			if first.CName and last.CName then delete;
			run;


		%ISDATA(dataset = flag_1);
		%IF (&NOBS. > 0) %THEN %DO;
		proc sql;
			   create table %str(dplocal.flag_l3_398_&tabid.) as
			   	select	flagid, 
						message,
						flag_descr,
						Flagtype,
						abortyn,
						count(crows) as count
				from (
					select cats("%upcase(&tabid.)_",&level.,"_00_00-0_398") as flagid length =21
						  ,cat("MLName (",strip(MLName),"), MFName (",strip(MFName),"): Linked to apparent multiple child records of the same person CLName (",
							   strip(CLName),"), CFName (",strip(CFName),"), with different CPatID values")
							as message length = 255
						  ,cat("MLName, MFName linked to multiple rows of same values of CLName, CFName, but with different CPatID values") 
							as flag_descr length = 255
						  ,"Warn" as Flagtype length = 4
						  ,"N" as abortyn length = 1
						  ,1 as crows
					 from flag_1
					 )
					group by  flagid,  message,  flag_descr, flagtype,  abortyn;
					drop table flag_1;
		     quit;
		%END;

	/*CLName, CFName linked to multiple rows of same MLName,MFName*/
	data temp2;
			 set mil.&MISTABLE;
			 length MName $41;
			 length CName $41;
			 if not missing(cpatid) and not missing(mpatid); /*Linked record*/
			 CName = cat(strip(CFName),":",strip(CLName));
			 MName = cat(strip(MFName),":",strip(MLName));
		run;

	    proc sort data = temp2 nodupkey;
			by MName CName mpatid cpatid;
		run;

		data flag_2;
			 set temp2;
				by MName CName;
			 length l_cname $41;
			 length count 3.;
			 retain l_cname count;
			 
			 if first.MName then do;
			 	 l_cname = CName;
				 count = 1;
			end;
			else do;
				 if l_cname ne CName then count = count+1;
				  l_cname = CName;
			end;
			if first.MName and last.MName then delete;
			run;

		
		%ISDATA(dataset = flag_2);
		%IF (&NOBS. > 0) %THEN %DO;
		proc sql;
			   create table %str(dplocal.flag_l3_399_&tabid.) as
			   	select	flagid, 
						message,
						flag_descr,
						Flagtype,
						abortyn,
						count(crows) as count
				from (
					select cats("%upcase(&tabid.)_",&level.,"_00_00-0_399") as flagid length =21
						  ,cat("CLName (",strip(CLName),"), CFName (",strip(CFName),"):Linked to apparent multiple Mother/Delivery records of the same person MLName(",
							   strip(MLName),"), MFName (",strip(MFName),")")
							as message length = 300
						  ,cat("CLName, CFName linked to multiple rows of MLName,MFName") as flag_descr length = 255
						  ,"Warn" as Flagtype length = 4
						  ,"N" as abortyn length = 1
						  ,1 as crows
					 from flag_2
					 )
					group by  flagid,  message,  flag_descr, flagtype,  abortyn;
					drop table flag_2;
		     quit;
		%END;

	%end;		

%mend suplinkage;

%macro level3();
	*aggregated l1 l2 flags;
	%l2_flags_final;

	*suspect linkage;
	%suplinkage;

	%set_ds (libin=dplocal, dsin_prefix=flag_l3_, libout=dplocal, dsout=&prefix.all_l3_flags_mstr); 

	*aggregate linkage files;
	proc sql noprint;
    	create table dplocal.&Prefix.all_l3_flags as
    	select flagid, abortyn, flagtype, flag_descr, sum(count) as count format=comma15. informat=comma15.
    	from dplocal.&prefix.all_l3_flags_mstr
    	group by 1,2,3,4
    	order by 1,3
    	;
  	quit;
%mend level3;
%level3;	
/*---------------------------------------------------------------------------------*/
/* Create level 3 aggregate dataset 										       */
/*---------------------------------------------------------------------------------*/

%macro createl3table();
	proc sql noprint;
		 select module into: tabid trimmed
		 from dplocal.&prefix.control_flow_3 (where = (cc_table ne 'X'));
	quit;

	%if "%upcase(&tabid.)" = "MIL" %then %do;

	%macro filestatus(indata=, outdata=, var1=, var2=, num=, type= );

		proc sort data = mil.&&&tabid.table (where = (not missing(&var1.))) out = &type. nodupkey;
			by &var1. &var2.;
	    run;
		proc sort data = ds.&indata. out = &indata. nodupkey;
			by &var1. &var2.;

		data &outdata.;
			 merge &type. (in = link keep = &var1. &var2.)
			 	   &indata. (in = del keep = &var1. &var2. );
			 by &var1. &var2.;
			 length IDFileStatus&num.  $1;
			 if link and del then IDFileStatus&num. = "Y";
			 if del and not link then IDFileStatus&num. = "N";
			 if link and not del then IDFileStatus&num. = "E"; /*EXTRA*/
		run;

		proc sort data = &outdata. nodupkey;
			 by &var1. &var2.;
		run;

		data &outdata.fmt;
			 retain fmtname "$&type.fmt" type 'C';
			 	set &outdata. end = eof;
				length start $255;
				start = %if "&type." = "mother" %then cat(&var1.,&var2.); %else cat(&var1.);;
				label = IDFileStatus&num.;
				output;
				if eof then do;
					 start = ' ';
					 hlo = 'o';
					 label = '';
					 output;
				end;
		run;

		proc format cntlin = &outdata.fmt library = work;
		run;
		%global N&num;
		proc sql noprint;
			 select count(*) as rows into: N&num. from &outdata. 
			 where IDFileStatus&num. = "N";
		quit;

	%mend filestatus;
	%filestatus(indata=&deliveries, outdata=mtemp, var1=mpatid, var2=encounterid, num=1, type= mother);
	%filestatus(indata=&infants, outdata=ctemp, var1=cpatid, var2=, num=2, type= child);
		
		%let totalN = %eval(&N1.+&N2.);

		%put ===>&totalN.;
			
		proc sort data = mil.&&&tabid.table out = mi ;
			by mpatid encounterid;
	    run;		

		data l3_temp;
			set mi;
			by mpatid encounterid;
			length LinkageStatus $1 Year $4 Year_Month $7 ICD_Ver $1 AgeGroup $9;
			Length IDFilestatus IDFilestatus1 IDFilestatus2 $1.;
			 if not missing(mpatid) and not missing(cpatid) then LinkageStatus = "L";
			 if not missing(mpatid) and missing(cpatid) then LinkageStatus  = "M";
			 if missing(mpatid) and not missing(cpatid) then LinkageStatus = "C";

			 /*yEAR*/
			 If ADate ne . then do;
					Year = put(year(adate), 4.);
					Year_Month = cat(put(year(adate),4.),"_",put(month(adate),z2.));
			end;
			 else if Adate eq . and CBirth_date ne . then do;
			 			Year = put(year(Cbirth_date), 4.);
					Year_Month = cat(put(year(CBirth_date),4.),"_",put(month(Cbirth_date),z2.));
			end;

			/*ICD 9 VERSION*/
			icd_date = COALESCE(ddate, adate, CBirth_date);
			if icd_date le "30Sep2015"d then ICD_Ver = "9";
			else if icd_date ge "01Oct2015"d then ICD_Ver = "0";

			/*IDFilestatus*/
			IDFilestatus1 = put(cats(mpatid,encounterid),$motherfmt.);
			IDFilestatus2 = put(cats(cpatid),$childfmt.);

			/*UnLinked record*/
			if  missing(cpatid) or  missing(mpatid) then do;
			if IDFilestatus1 = "Y" or IDFilestatus2 = "Y" then IDFilestatus = "Y";
			else if IDFilestatus1 = "E" or IDFilestatus2 = "E" then IDFilestatus = "E";
			else IDFilestatus = "N";
			end;
			/*Linked record*/
			if not missing(cpatid) and not missing(mpatid) then do;
				if IDFilestatus1 = "Y" and IDFilestatus2 = "Y" then IDFilestatus = "Y";
				else if IDFilestatus1 = "E" or IDFilestatus2 = "E" then IDFilestatus = "E";
				else IDFilestatus = "N";
			end; 

			patid  = 1;

			 if  not missing(mpatid) then do;
	 			if age >= 10 & age <= 19 then Agegroup = "10-19";
	 			else if age >= 20 & age <= 44 then Agegroup = "20-44";
				else if age >= 45 & age <= 54 then Agegroup = "45-54";
				else Agegroup = "Other";
			end;
			else Agegroup = "Infants";
			drop icd_date ;


	proc means data = l3_temp  MISSING noprint;
		class  Sex  EncType AgeGroup ICD_Ver Year_Month Year Birth_Type LinkageStatus ;
		var patid;
	output out = l3_temp_summ(drop = _freq_)sum(patid)=count;
	run;
	/*Create dummy file for IDFILESTATUS*/
	proc means data = l3_temp nway noprint;
		class IDFilestatus;
		var patid;
	output out = idfile(drop = _freq_)sum(patid)=count;
	run; 

	data idfile_N;
	 length count 8. ;
	 length IDFilestatus $1;
	 IDFilestatus = "N";
	 count = &TotalN;
	run;

	data idfile_all;
		 merge idfile
		 		idfile_N;
		  by IDFilestatus;
		  length level $3;
		  level = "001";
	run;
	

	data msoc.l3_m_i_aggregate;
	retain level IDFilestatus LinkageStatus Birth_Type Year Year_Month ICD_Ver AgeGroup EncType Sex;
	set l3_temp_summ
		idfile_all (in = a);
	length level $3;
	if not a and level ne "000" then  
	level = put(_type_+1, z3.);
	format count comma9.0;
	drop _type_;
	run;

	proc sort data = msoc.l3_m_i_aggregate;
	by level;
	run;
%end;
	
%mend createl3table;
%createl3table;




/*---------------------------------------------------------------------------------*/
/* Move specific files from DPLOCAL to MSOC                                        */
/*---------------------------------------------------------------------------------*/
%macro move_files;
	proc sql noprint;
		 select module into: tabid trimmed
		 from dplocal.&prefix.control_flow_3 (where = (cc_table ne 'X'));
	quit;

	%if "%upcase(&tabid.)" = "MIL" %then %do;
  	 proc sql;
    	select memname, count(memname) into :filelist separated by ' ', :filect trimmed
    	from dictionary.tables
     where libname="DPLOCAL" and (memname eq "MIL_ALL_L1_L2_FLAGS" or memname eq "MIL_ALL_L3_FLAGS" or memname like "%SIGNATURE" 
								 or memname like "MIL_CONTROL%" or memname like "MIL_ETL%" or memname like "MIL_LICENSED%")  
    	;
  	quit;

  	%do i=1 %to &filect.;
    %let file=%scan(&filelist.,&i.);

     proc sql noprint;
      create table msoc.&file. as
      select %add_dpids_sql
           , *
      from dplocal.&file.
      ;
      drop table dplocal.&file.
      ;
    quit;
  	%end;
   %end;
%mend;
%move_files;



/*---------------------------------------------------------------------------------*/
/* Add DPID and SiteID to all datasets in MSOC folder, except signature files      */
/*---------------------------------------------------------------------------------*/
*%add_dpids_all_ds (libin=msoc, libout=msoc);

/* Clean up datasets from DPLOCAL */
proc sql noprint;
  select memname into :ds separated by " "
  from dictionary.tables where libname='DPLOCAL'
  having nobs-delobs=0
  ;
quit;

/* Delete unnecessary DPLOCAL datasets */
proc datasets lib=dplocal nolist nowarn nodetails;
  delete &ds. l2_nodup_: lab_testdates_ym ;
quit;
  
%timestamp(&module._end);
%timereport(&&&module._start,&&&module._end);

*-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-;
* END 99.2_mscdm_data_qa_review_level3.sas                                              ;
*-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-;
