****************************************************************************************************
*                                           PROGRAM OVERVIEW
****************************************************************************************************
*
* PROGRAM: ms_macros.sas  
*
* Created (mm/dd/yyyy): 12/19/2014
* Last modified: 05/05/2017
* Version: 1.1
*
*--------------------------------------------------------------------------------------------------
* PURPOSE:
*   These are utility macros that are used to import files and verify if an dataset contains observations.                                        
*   
*  Program inputs:                                                                                   
*                                     
*  Program outputs:                                                                                                                                       
*                                                                                                  
*  PARAMETERS:    
*   ISDATA(dataset=)
*       dataset = Name of a dataset for which we want to verify if it contains observations
*
*   IMPORTFILES(var=)
*       var = Name of a dataset that we want to import
*            
*
*    soc_delete_dir(dir=)
*       dir = Name of directory to delete
*
*  Programming Notes:                                                                                
*                                                                           
*
*
*--------------------------------------------------------------------------------------------------
* CONTACT INFO: 
*  Sentinel Coordinating Center
*  info@sentinelsystem.org
*
*--------------------------------------------------------------------------------------------------
*  CHANGE LOG: 
*
*   Version   Date       Initials      Comment (reference external documentation when available)
*   -------   --------   --------   ---------------------------------------------------------------
*   1.1       05/05/2017    AP      Added macro %create_comma_charlist
*
*   1.2       05/25/2018    AP      Added macro %nonrep
*
***************************************************************************************************;

*Macro to determine whether a dataset is empty or not;
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

%MACRO IMPORTFILES(var=);

%PUT =====> MACRO CALLED: ms_macros v1.0 => IMPORTFILES;

    %IF %INDEX(%UPCASE("&VAR."),CPORT) %THEN %DO;
        proc cimport infile="&infolder.&VAR." library=infolder memtype=data;
        run;
    %END;

%put NOTE: ********END OF MACRO: ms_macros v1.0 => IMPORTFILES ********;

%MEND IMPORTFILES;

%MACRO VAREXIST(DS,VAR);

%PUT =====> MACRO CALLED: ms_macros v1.0 => VAREXIST;

%GLOBAL VAREXIST;
%LET VAREXIST=0;
%LET DSID = %SYSFUNC(OPEN(&DS));
%IF (&DSID) %THEN %DO;
    %IF %SYSFUNC(VARNUM(&DSID,&VAR)) %THEN %LET VAREXIST=1;
    %LET RC = %SYSFUNC(CLOSE(&DSID));
%END;

%put NOTE: ********END OF MACRO: ms_macros v1.0 => VAREXIST ********;

%MEND VAREXIST;

 %macro ms_check_path(path) ;
    %local ln lc d_exist ;
    %let ln = %length(&path) ;
    %if &ln eq 0 %then %do ;
         %put The parameter path must be non-missing. ;
         %abort cancel ;
    %end ;
    %else %if &ln > 0 %then %do ;
       %let path = %sysfunc(translate(&path, %str(/), %str(\))) ;
       %let lc = %substr(&path, &ln) ;
       %if "&lc" ne "/" %then %do ;
          %let path = &path./ ;
       %end ;      
       %let d_exist = %ms_dirCheck(&path) ;  
     %if &d_exist eq 0 %then %do ;
        %put Path &path does not exist;
        %abort cancel;
     %end ;    
    %end ;
    &path    /* returns value to calling enivornment, like a function */
%mend ms_check_path ;


%macro ms_dirCheck(dir) ; 
  /* Original Author: Adrien Vallee */  
  /* Original Source: http://www.sascommunity.org/wiki/Tips:Check_if_a_directory_exists */
  /* Terms of Use: http://www.sascommunity.org/wiki/sasCommunity:Terms_of_Use */

   %if %length(&dir) eq 0 %then %do ;
      %put The parameter dir must be non-missing.  ;
      %abort cancel ;
   %end ;
   %local rc fileref return ; 
   %let rc = %sysfunc(filename(fileref,&dir)) ; 
   %let return = %sysfunc(fexist(&fileref)) ;  
   &return  /* returns value to calling enivornment, like a function */
   %let rc = %sysfunc(filename(fileref)) ;  
%mend ms_dirCheck;


* Macro to collapse overlapping time periods;
%macro MergeTimePeriods(dataset=,DateStart=,DateEnd=);

    proc sort data= &dataset.;
    by PatId &DateStart. &DateEnd.;
    run;

    data &dataset.(rename=New&DateStart.=&DateStart. rename=New&DateEnd.=&DateEnd.);
    set &dataset.;
    by PatId;
    if first.PatId then do;
      New&DateStart. = &DateStart.;
      New&DateEnd. = &DateEnd.;
    end;
    retain New&DateStart. New&DateEnd.;
    if &DateStart. > New&DateEnd. + 1 then do;
      output;
      New&DateStart. = &DateStart.;
      New&DateEnd. = &DateEnd.;
    end;
    else New&DateEnd. = max(&DateEnd.,New&DateEnd.);
    if last.PatId then output;
    keep PatId New&DateStart. New&DateEnd.;
    format New&DateStart. New&DateEnd. date9.;
    run;

%mend MergeTimePeriods;


/*converts space separate list into comma separated list in quotes*/
%macro create_comma_charlist(inlist=, outlist=);
    %global &outlist.;

    %let countvars = %sysfunc(Countw(%quote(&inlist.)));
        %do c = 1 %to &countvars.;
            %let word = %scan(%quote(&inlist),&c.);
                %if &c. = 1 %then %do;
                    %let &outlist. = "&word.";
                %end;
                %else %do;
                    %let &outlist. = &&&outlist. , "&word.";
                %end;
        %end;
    %let &outlist = %upcase(&&&outlist);
%mend create_comma_charlist;

*Removes repeated words in a macro variable;
%macro nonrep(invar= , outvar= );
    %global &outvar;
    %let long = ;
    %if %str(&&&invar) ne %str() %then %do;
    %do w=1 %to %sysfunc(countw(&&&invar));
        %if %sysfunc(indexw(&long, %scan(&&&invar,&w))) = 0 %then %do;
            %let long = &long %scan(&&&invar,&w);
        %end;
    %end;
    %end;
    %let &outvar = &long.;
%mend;

*Restrict data to those in master list;
%macro restrictclms(dataset=);
             data &dataset.;
                if 0 then set worktemp.ptsmstrall;
                declare hash pt (hashexp:16, dataset:"worktemp.ptsmstrall");
                pt.definekey('PatId');
                pt.definedone();

                do until(eof1);
                set &dataset. end=eof1;
                if pt.find()=0 then do;
                    output;
                end;
                end;
                stop;
             run;
%mend restrictclms;

/*Delete temporary subfolders*/
%macro soc_delete_dir(dir=);
    proc datasets nowarn noprint nolist kill lib=&dir.; quit;

    filename dir "&&&dir";
    data _null_;
       rc=fdelete('dir');
       put rc=;
       msg=sysmsg();
       put msg=;
    run;
%mend;

%macro varlength (var = , indata = );
	%global &var._len &var._typ;
	
	proc contents noprint data=&indata. out=var_length_contents;
    run;
	
	proc sql noprint;
	  select length 
	        ,type  
		into: &var._len 
		     ,:&var._typ
	  from var_length_contents
      where lowcase(name) = "&var.";
	quit;
	
	proc datasets noprint lib = work;
	  delete var_length_contents;
	quit;
%mend varlength;

/* Convert uppercase and mixed case variables to lower case value   */
%macro convert_to_lowcase (indata =, varlist = , outdata =);
    %let num_variables = %sysfunc(countw(&varlist.));
	
    data uppercase_values;
	  set &indata.;
	  %do nv = 1 %to &num_variables.;
	    if findc(%scan(&varlist.,&nv.),,'u') > 0 then do;
		  modified_var = "%scan(&varlist.,&nv.)";
		  output;
		end;
	  %end;
    run;
	
	%isdata(dataset=uppercase_values);
	%if %eval(&nobs.>0) %then %do;
	  proc sql noprint;
	    select distinct(modified_var) into: modified_vars separated by ","
		from uppercase_values;
	  quit;
	  
	  %put WARNING: (Sentinel) In inputfile &indata., &modified_vars. contains uppercase characters.; 
	  %put File &indata. was direclty modified to set all characters to lowercase for the specified variables.;
	  
	   data &outdata.;
	     set &indata.;
	     %do nv = 1 %to &num_variables.;
	        %scan(&varlist.,&nv.) = lowcase(%scan(&varlist.,&nv.));
	     %end;
	   run; 
	%end;

%mend convert_to_lowcase;


/** Utility macro %ms_attrition_compute selects episodes to exclude **/
/** Macro creates dataset _attrition **/
%macro ms_attrition_compute(file=,ToExcl=,analysisgrp=,milattr=,pregdate=);
    proc sql noprint;
        select count(*) into: NumToExcl
		%if %eval(&milattr. =1) %then %do;
			from (select distinct PatID, &pregdate. from &file. where not (&ToExcl.));
		%end;        
		%else %do;
			from &file.
			where not (&ToExcl.);
		%end;
    quit;
    %put &NumToExcl.;
    data &file.;
        set &file.;
		%if %eval(&milattr. =1) %then %do;
			where not (%scan(&ToExcl.,1,|));
		%end;        
		%else %do;
			where not (&ToExcl.);
		%end;
    run;

    %ISDATA(dataset=_Attrition);
    %IF %EVAL(&NOBS.>=1) %THEN %DO;
        data _Attrition;
        set _Attrition end=eof;
        output;
        if eof then do;
		    Analysisgrp="&analysisgrp.";
            Level="&level.";
            Num=input("&NumToExcl.",best.);
            call symputx("level",&level.+1);
            output;
        end;
        run;
    %END;
    %ELSE %DO;
        data _Attrition;
        format analysisgrp $40. level $7. num comma10.;
		length analysisgrp $40;
		Analysisgrp="&analysisgrp.";
        Level="&level.";
        Num=input("&NumToExcl.",best10.);
        call symputx("level",&level.+1);
        output;
        run;
    %END;
    %put %eval(&level.-1) &NumToExcl.;
%mend; 
