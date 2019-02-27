/*----------------------------------------------------------------------*/
/* Sentinel package of SAS macros to assist with environment setup      */
/*                                                                      */
/*   List of macros included in package                                 */
/*     - SOC_CLEAN_PATHS... cleans & validates path-name(s)             */
/*     - SOC_DIREXIST... checks if directory exists                     */
/*     - SOC_LIB... conditionally assigns libname                       */
/*     - SOC_QUOTEPATH... creates a quoted list of paths                */
/*                                                                      */
/*----------------------------------------------------------------------*/
* CONTACT INFO: 
* Sentinel Coordinating Center
* info@sentinelsystem.org
*
*------------------------------------------------------------------------------;


  /*****************************************************************************
  *                               SENTINEL MACRO
  ******************************************************************************
  * NAME:  soc_clean_paths
  *
  * PURPOSE: Clean up path(s) according to soc conventions, then validates
  *
  * MAJOR STEPS:  
  *  1. Checks if &paths is populated and aborts with message if it is left blank
  *  2. Loops through each path provided and:
  *    - Replaces back slashes (\) with forward slashes (/)
  *    - Checks if path ends with forward slash, appending one if necessary
  *    - Replaces up to 4 consecutive slashes (e.g. ////) with single slash (/) 
  *      if found, excluding any leading double slashes (e.g. //path-to-server/) 
  *    - Checks if path(s) actually exist and abort if not
  *
  * KEY DEPENDENCIES/CONSTRAINTS:  calls macro soc_dirExist 
  *
  *------------------------------------------------------------------------------
  * USER-PARAMETERS
  *   paths ... name of path, without surrounding quotes, separated by a single 
  *   space (e.g. X:\project-xyz or /path1/ /path2/)
  *------------------------------------------------------------------------------
  * HISTORY:
  *  Create date (mm/dd/yy):  08/27/13
  *  Last modified date (mm/dd/yy): 01/10/19 
  **********************************************************************************/  
%macro soc_clean_paths(paths);
  %local j ln subpath temppath;  
  
  %if %length(%superq(paths)) eq 0 %then %do;
		  %put The parameter path must be non-missing. ;
		  %abort cancel ;
	 %end ;

  /* remove any double spaces in the paths list and replace with single space */
  %let paths=%qsysfunc(translate(&paths,%str(/),%str(\)));

  %do j=1 %to %qsysfunc(countw(&paths.,%str( )));
    %let subpath=%qscan(&paths,&j,%str( ));
    %let ln=%length(&subpath);
    
    %if %qsubstr(&subpath,&ln,1) ne %str(/) %then %do;
      %let subpath=&subpath./;
    %end;

    %let d_exist = %soc_dirExist(&subpath) ;  
    %if &d_exist eq 0 %then %do ;
      %put Path &subpath. does not exist;
      %abort cancel;
    %end ;	
  %let temppath=&temppath. &subpath.;
  %end;
  %let paths=%qleft(&temppath);
  &paths   /* returns value to calling environment, like a function */
%mend soc_clean_paths;


%macro soc_dirExist(dir) ; 
  /*****************************************************************************
  *                               SENTINEL MACRO
  ******************************************************************************
  * NAME:  soc_dirExist
  *
  * PURPOSE:  Checks if a directory exists, returning 1 if exists, 0 if not, 
  *           aborting if directory is missing.
  *------------------------------------------------------------------------------
  * USER-PARAMETERS
  *   dir ... name of directory, without surrounding quotes (e.g. X:\project-xyz)
  *------------------------------------------------------------------------------
  * HISTORY:
  *  Create date (mm/dd/yy):  08/27/13
  *  Last modified date (mm/dd/yy): 01/31/19
  *  Verison: 2
  *
  *  CHANGE LOG: 
  *
  *   Version   Date       Comment (reference external documentation if available)
  *   -------   --------   --------------------------------------------------------
  *      1      08/08/13   This is a modified version of a macro created and freely
  *                        shared by Adrien Vallee (see below).  The original macro
  *                        has been modified to clear the filref after use.  It  
  *                        also issues abort cancel if dir is blank.
  *      2      01/31/19   Renamed to "soc_direxists"
  *                        
  **********************************************************************************/  	  
  /* Original Author: Adrien Vallee */	
  /* Original Source: http://www.sascommunity.org/wiki/Tips:Check_if_a_directory_exists */
  /* Terms of Use: http://www.sascommunity.org/wiki/sasCommunity:Terms_of_Use */

   %if %length(&dir.) eq 0 %then %do ;
   	  %put The parameter dir must be non-missing.  ;
   	  %abort cancel ;
   %end ;
   %local rc fileref return ; 
   %let rc = %qsysfunc(filename(fileref,&dir.)) ; 
   %let return = %qsysfunc(fexist(&fileref.)) ;  
   &return  /* returns value to calling enivornment, like a function */
   %let rc = %qsysfunc(filename(fileref)) ;  
%mend soc_dirExist;

/* Create a quoted list from a space-delimited list of path names  
   in order to concatenate paths for %soc_lib macro */
/* e.g. list=/pathA/ /pathB/ ==> list="/pathA/" "/pathB/"  */
%macro soc_quotepath(list);
  %local j d_exist path_ct path subpath temppath;
  %let list_ct=%qsysfunc(countw(&list,%str( )));
  %do j=1 %to &list_ct.;
    %let subpath=%qscan(&list,&j,%str( ));
    %let d_exist = %soc_dirExist(&subpath) ;  
    %if &d_exist eq 0 %then %do;
      %put Path &subpath does not exist;
      %abort cancel;
    %end;
    %let subpath="&subpath.";
    %let temppath=&temppath. &subpath.;
  %end;
  %let list=%qleft(&temppath);

  &list /* returns value to calling enivornment, like a function */

%mend soc_quotepath;

%macro soc_lib(ref, paths, options=) ;
  /*****************************************************************************
  *                               SENTINEL MACRO
  ******************************************************************************
  * NAME:  soc_lib
  *
  * PURPOSE:  Conditionally assigns a libref with options, if specified, and
  *           aborting if non-missing path is invalid
  *
  * KEY DEPENDENCIES/CONSTRAINTS:  calls macros soc_dirExist and soc_quotePath
  *
  *------------------------------------------------------------------------------
  * USER-PARAMETERS
  *   ref  ... SAS libref-name (e.g. indata) that SAS uses to point to a path
  *   paths ... path-names, deliminated with a single space, without surrounding 
  *             quotes (e.g. X:\project-xyz or /path1/ /path2/)
  *   options ... SAS libname options, with macro-quoting if necessary 
  *               [ e.g. %str(access=readonly) ]
  *------------------------------------------------------------------------------
  * HISTORY:
  *  Create date (mm/dd/yy):  08/27/13
  *  Last modified date (mm/dd/yy): 01/11/19
  *  Verison: 1
  **********************************************************************************/  
  %local libpaths;

  %if %length(&ref) eq 0 %then %do ;
    %put libref is blank ;
	   %abort cancel ; 
  %end ;

  %if %length(%superq(paths)) eq 0 %then %do ;
    %put SOC-NOTE: For libref &ref the path is blank, libname assignment skipped ;
  %end ;

  %let libpaths= %soc_quotepath(&paths) ;

  libname &ref. %unquote((&libpaths.)) &options.;
 
 %mend soc_lib;
