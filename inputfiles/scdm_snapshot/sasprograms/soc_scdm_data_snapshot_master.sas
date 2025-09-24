options linesize=100 pagesize=50;
/****************************************************************************************
*                                     SENTINEL PROGRAM
*****************************************************************************************
* NAME:  SCDM Snapshot Adhoc Program soc_scdm_data_snapshot_master.sas
*
* PURPOSE: The purpose of this ad hoc program is to generate analytic datasets (ADS) to
*          be used in a SCDM summary report. This program will be distributed to all Data
*          Partners (DP) and run on the most current production ETL.
*
* MAJOR STEPS: See Workplan in "docs" subfolder
*
* KEY DEPENDENCIES/CONSTRAINTS/CAVEATS:
*
*----------------------------------------------------------------------------------------
* CONTACT INFO:
*  Sentinel Coordinating Center
*  info@sentinelsystem.org
*
*----------------------------------------------------------------------------------------
* HISTORY:
*  Create date (mm/dd/yyyy): 01/05/2017
*  Last modified date (mm/dd/yyyy): 09/08/2025
*  Package version: 3.2.0
*
*  Sentinel master program header version: 4.0.0 (DO NOT EDIT)
****************************************************************************************/

/*---------------------------------------------------------------------------------------
*                                      DEFINITIONS
*----------------------------------------------------------------------------------------
* SCC... Location of Sentinel Common-Components (CC) request associated with the most
*        recent production ETL for either Phase A (standard SCDM) or Phase B (standard
*        SCDM plus MIL table). Specific to each Data Partner/Data Site, the CC utility
*        macro defines key:
*          - macro variables (e.g. Data Partner ID, Min and Max Dates, SCDM table names)
*          - libname assignments (e.g. libref INDATA is assigned to SCDM tables)
*        NOTE: This parameter needs to be set by programmer at the Data Partner/Data Site
*              in QA CC request.
*
* NumSession... Number of parallel SAS sessions spawned by the master SAS program.
*               NOTE: This parameter controls the number of parallel sessions (SAS Grid
*                     or SAS/CONNECT) that may be spawned by the master program. It is
*                     used by Data Partner/Data Site that have an SCDM ETL QA approved
*                     for parallel processing.
*
* ReqID... Sentinel Project Request-ID (formerly MSReqID)
*          NOTE: This parameter needs to be set by the programmer/analyst preparing the
*               Request-ID in coordination with the Sentinel Operations Center (SOC)
*
* The following paths for the current request are automatically derived from QA CC
*    DPLOCAL  ... path for data created that remains local (i.e. behind the DP firewall)
*    MSOC     ... path for data created to share with Sentinel Operations Center
*    INFOLDER ... path for program inputs (e.g. lookup data, program modules, macros)
*    SASPROGRAMS ... path for the main SAS program for the request
*--------------------------------------------------------------------------------------*/

*---------------------------------------------------------------------------------------
* NOTES:
*  For reasons of compatibility and standardization, ALL PATHS must meet the following
*  criteria:
*     1- Starting with the request directory, all subdirectory names must be specified
*        in lower case (for UNIX compatibility)
*     2- Slashes must be forward-leaning slashes '/' (for UNIX compatibility)
*     3- Paths must end with a final forward-leaning slash '/' (extra slashes are fine)
*     4- Paths must NOT contain any embedded spaces
*---------------------------------------------------------------------------------------;

/*-------------------------------------------------------------------------------------*/
/* Section 1: Data Partner/Data Site programmer defines parameters in this section.    */
/*-------------------------------------------------------------------------------------*/
/* 1a. Edit macro variable SCC to point to the directory containing the executed Common
         Components (CC) request associated with the relevant production ETL, INCLUDING
         the Request-id.
       NOTE: ORGANIZATIONS WITHOUT CC SHOULD LEAVE BLANK (DO NOT comment out)
             AND COMPLETE ALL OF SECTION 1c.
       Example: %let SCC = /sentinel/requests/etl4/soc_cca_wp001_xxxx_v01/             */
   %let SCC = ;

/*    Edit macro variable NumSession if needed to set # of spawned parallel sessions.
      NOTE: UNLESS THE ETL HAS BEEN QA APPROVED FOR PARALLEL SESSIONS, DO NOT CHANGE.
            OTHERWISE THE QUERY MAY FAIL.                                              */
   %let NumSession=0;

/* 1b. Edit this parameter to identify the list of patients to exclude (if applicable).
       SAS Dataset should contain one variable, patid, and list all patids that should be
       excluded. Must include libname (e.g., indata.PtsToExclude).                          */
  %let PTSTOEXCLUDE= ;

  	/* Edit this parameter to identify the list of patients and their encounterids to exclude (if applicable).
       Dataset should contain two variables, patid and encounterid, and list all patids, encounterids that should be
       excluded. Must include libname (e.g., indata.EncIdToExclude).
     */

	%let ENCIDTOEXCLUDE=;


/***************************************************************************************/
/* 1c. OPTIONAL: Organizations WITHOUT Common Components define parameters in this
       section, leaving STEP 1a. above blank.                                          */

    /* _DP is a descriptive identifier for your organization. Specify a 3-6 UPPERCASE
       character abbreviation for _DP. Example: %let DP=ABCDE ;                        */
       %let _DP= ;

    /* Specify the path(s) to the four (4) request package subfolders (dplocal, msoc,
       inputfiles, and sasprograms).

       Please note, some organizations choose to separate the package subfolders prior to
       execution.  This is optional, but ALL four macro variables below MUST be populated,
       even if they are all in the same location (DO NOT comment out).

    /* Example: %let packageroot_dplocal = A:/sentinel/requests/<package-name>/dplocal/ */
       %let _packageroot_dplocal= ;
       %let _packageroot_msoc = ;
       %let _packageroot_inputfiles = ;
       %let _packageroot_sasprograms= ;

    /* Specify the file path(s) to the location of your Sentinel CDM datasets. If
       Example: %let prod_scdm= A:/sentinel/etl1/phaseA/scdm/ ;        */
       %let prod_scdm= ;

    /* The following metadata describe characteristics of your SCDM. If known, modify the
       following parameters:
    /* DP_MinDate: Specify the overall SCDM minimum date in the format "DDMMMYYYY"d
                   Default value is "01Jan2000"d                                       */
       %let _DP_MinDate="01Jan2000"d ;

    /* DP_MaxDate: Specify the overall SCDM maximum date in the format "DDMMMYYYY"d
                    Default value is today's date (e.g. "&sysdate."d)                  */
       %let _DP_MaxDate = "&sysdate9."d ;

    /* ETL: Please enter the ETL version # for the production SCDM.
              Default is 1                                                             */
       %let _ETL = 1 ;

    /* Phase: Please enter the Phase (A or B) of the associated ETL SCDM.
              Default is A                                                             */
       %let _Phase = A ;

    /* SCDMVer: Please enter the version of the SCDM associated ETL SCDM in
                  format #.#.# (e.g., 7.0.0)                                           */
       %let _SCDMVer = ;

    /* Specify the name of each of the Sentinel Common Data Model tables, if different
       from the default values entered. Do NOT include '.sas7bdat'. DO NOT leave blank.
       Example: %let _ENRTABLE=enrollment ;                                            */
       %let _ENRTABLE= ; *specify the enrollment table name *;
       %let _DEMTABLE= ; *specify the demographic table name *;
       %let _DISTABLE= ; *specify the rx dispensing table name *;
       %let _ENCTABLE= ; *specify the encounter table name *;
       %let _DIATABLE= ; *specify the diagnosis table name *;
       %let _PROCTABLE= ;*specify the procedure table name *;
       %let _FACTABLE= ; *specify the facility table name *;
       %let _PVDTABLE= ; *specify the provider table name *;

    /****************************************************************************\
       The following tables are optional. Leave BLANK if they are not available
       at your site (DO NOT COMMENT OUT).
    \****************************************************************************/
       %let _DEATHTABLE= ;  *specify the death table name *;
       %let _CODTABLE= ;    *specify the cause of death table name *;
       %let _LABTABLE= ;    *specify the lab result table name *;
       %let _VITTABLE= ;    *specify the vital signs table name *;
       %let _IPHARMTABLE= ; *specify the inpatient pharmacy table name *;
       %let _ITRANSTABLE= ; *specify the inpatient transfusion table name *;
       %let _MILTABLE= ;    *specify the mother-infant linkage table name (Phase B only);
       %let _PRETABLE= ;    *specify the prescribing table name *;
       %let _PRRTABLE= ;    *specify the patient reported response table name;
       %let _PRSTABLE= ;    *specify the patient reported survey table name;
       %let _FEATABLE= ;    *specify the feature engineering table name;

    /*******************************************************************************\
     The following parameters are for Data Partner/Data Site with ETL approved for
     parallel processing of Sentinel queries and for partitioned SCDM tables.
    \*******************************************************************************/

     %let _SASCMD= ;     *specify command used to start new SAS session (e.g., sas);
     %let _SASConnect= ; *specify if SAS/Connect can be used for queries [Y/N];
     %let _SASGrid= ;    *specify if SAS Grid can be used for queries [Y/N];
     %let _GridSrv= ;    *specify the name of the grid server, if applicable;
     %let _NumPartitions= ; *specify # of partitions for the partitioned SCDM tables ;
     %let _ParTable= ;   *specify the name of the PatID to PartitionID crosswalk table;

/********************************** END OF SECTION 1 ***********************************/

/*-------------------------------------------------------------------------------------*/
/* SECTION 2: SOC Programmer/Analyst preparing the Request sets each parameter prior
              to distributing to DP
/*-------------------------------------------------------------------------------------*/
 /* Specific request IDs are made up of the following 5 tokens:
    project-ID, workplan-type, workplan-ID, unique-DPID, version-ID */
 /*-------------------------------------------------------------------------------*/
  *  If this is your request   . . . . . . . then set parameter values as follows
  *  ---------------------------------       --------------------------------------
  *   [Project-ID: CDER]                      %let ProjID= cder ;
  *   [Workplan-Type: ad hoc request]         %let WPType = ahr ;
  *   [Workplan-ID: 5]                        %let WPID =   wp005 ;
  *   [Unique-DPID: non-specific DP]          %let DPID =   nsdp ;
  *   [Version-ID: beta 3]                    %let VerID =  b03 ;
  *   [use underscores as delimiter]          %let dlm = _ ;
  *
  *   The example values above would produce Request-ID --> cder_ahr_wp005_nsdp_b03 ;
 /*------------------------------------------------------------------------------------*/
 /* Specify project-ID, workplan-type, workplan-ID, workplan-type, dpid, version-ID    */
   %let ProjID = <edit-project-id> ;
   %let WPType = <edit-workplantype-id> ;
   %let WPID = <edit-workplan-id> ;
   %let DPID = <edit-DP-id> ;
   %let VerID = <edit-version-id> ;

  /* Create request-id delimiter - Default is underscore (_)                           */
   %let dlm = _ ;  /* Do not edit */

****************************************************************************************
*******                             END OF USER INPUT                             ******
*******                        DO NOT EDIT BELOW THIS LINE                        ******
******* (Consult with SOC or Sentinel team leader if you feel edits are required) ******
****************************************************************************************;
/*-------------------------------------------------------------------------------------*/
/* SECTION 3a: Standard SOC environment setup code -- DO NOT EDIT
/*-------------------------------------------------------------------------------------*/
/* System options */
options nosymbolgen nomlogic;
options ls=100 nocenter ;
options obs=MAX ;
options msglevel=i ;
options mprint mprintnest ;
options errorcheck=strict errors=0 ;
options merror serror ;
options dkricond=error dkrocond=error mergenoby=warn;
options dsoptions=nonote2err noquotelenmax ;
options reuse=no ;
options fullstimer ;
options missing = .;
options validvarname = v7;
options fmterr;

%global reqid soc_master_program_version ccbypass;

/* Request-ID (must be lower case) */
%let ReqID = %lowcase(&ProjID.&dlm.&WPType.&dlm.&WPID.&dlm.&DPID.&dlm.&VerID);

/* Sentinel master program header version for use in signature files */
%let soc_master_program_version= 4.0.0;

%macro scc_yn; /* Please DO NOT edit */
  /*-----------------------------------------------------------------------------------*/
  /* If common components specified, define all file paths                             */
  /*-----------------------------------------------------------------------------------*/
  %if %str("&SCC.") ne ("") %then %do;
    %let ccbypass=N;
    /* Include Common Components */
    %inc "&SCC./inputfiles/cc_utility/cc_macvars.sas" /nosource2 ;
    %end;
  /*-----------------------------------------------------------------------------------*/
  /* If common components NOT specified, define all file paths and CC macro parameters */
  /*-----------------------------------------------------------------------------------*/
  %else %if %str("&SCC.") = ("") %then %do;
    %let ccbypass=Y;
  /*-----------------------------------------------------------------------------------*/
  /* Define all macro parameters as global - DO NOT EDIT                               */
    %global etl dp phase scdmver dp_mindate dp_maxdate dplocal msoc infolder sasprograms
            enrtable demtable distable enctable diatable proctable factable pvdtable
            deathtable codtable labtable vittable ipharmtable itranstable miltable
            pretable prstable prrtable featable
            sascmd sasconnect sasgrid gridsrv
            numpartitions partable;
  /*-----------------------------------------------------------------------------------*/
    /* Assign Macro variables*/
    %let dp=&_dp;
    %let etl=&_etl;
    %let dp_mindate=%sysfunc(putn(%superq(_dp_mindate),best12.));
    %let dp_maxdate=%sysfunc(putn(%superq(_dp_maxdate),best12.));
    %let scdmver = &_scdmver;
    %let enrtable= &_enrtable;
    %let demtable= &_demtable;
    %let distable= &_distable;
    %let enctable= &_enctable;
    %let diatable= &_diatable;
    %let proctable= &_proctable;
    %let factable= &_factable;
    %let pvdtable= &_pvdtable;
    %let deathtable= &_deathtable;
    %let codtable= &_codtable;
    %let labtable= &_labtable;
    %let vittable= &_vittable;
    %let ipharmtable= &_ipharmtable;
    %let itranstable= &_itranstable;
    %let miltable= &_miltable;
    %let pretable= &_pretable;
    %let prrtable= &_prrtable;
    %let prstable= &_prstable;
    %let featable= &_featable;
    %let sascmd= &_sascmd;
    %let sasconnect= &_sasconnect;
    %let sasgrid= &_sasgrid;
    %let gridsrv= &_gridsrv;
    %let numpartitions= &_numpartitions;
    %let partable= &_partable;

    /* Delete temporary macro variables */
    %symdel _dp _etl _dp_mindate _dp_maxdate _scdmver _enrtable _demtable _distable _enctable _diatable _proctable;
    %symdel _deathtable _codtable _labtable _vittable _ipharmtable _itranstable _miltable _pretable _prrtable _prstable _featable;
    %symdel _sascmd _sasconnect _sasgrid _gridsrv;
    %symdel _numpartitions _partable;
    %macro soc_clean_paths(paths);
      %local j ln subpath temppath;
      %if %length(%superq(paths)) eq 0 %then %do;
      %put The parameter path must be non-missing.; %abort cancel; %end;
      %let paths=%qsysfunc(translate(&paths,%str(/),%str(\)));
      %do j=1 %to %qsysfunc(countw(&paths.,%str( )));
      %let subpath=%qscan(&paths,&j,%str( )); %let ln=%length(&subpath);
      %if %qsubstr(&subpath,&ln,1) ne %str(/) %then %do; %let subpath=&subpath./; %end;
      %let d_exist = %soc_dirExist(&subpath) ;
      %if &d_exist eq 0 %then %do; %put Path &subpath. does not exist; %abort cancel; %end;
      %let temppath=&temppath. &subpath.; %end;
      %let paths=%qleft(&temppath);
      &paths   /* returns value to calling environment, like a function */
    %mend soc_clean_paths;
    %macro soc_dirExist(dir) ;
      %if %length(&dir.) eq 0 %then %do;
      %put The parameter dir must be non-missing.; %abort cancel; %end;
      %local rc fileref return; %let rc=%qsysfunc(filename(fileref,&dir.));
      %let return=%qsysfunc(fexist(&fileref.));
      &return  /* returns value to calling enivornment, like a function */
      %let rc=%qsysfunc(filename(fileref));
    %mend soc_dirExist;
    %macro soc_quotepath(list);
      %local j d_exist path_ct path subpath temppath; %let list_ct=%qsysfunc(countw(&list,%str( )));
      %do j=1 %to &list_ct.;
      %let subpath=%qscan(&list,&j,%str( )); %let d_exist = %soc_dirExist(&subpath);
      %if &d_exist eq 0 %then %do; %put Path &subpath does not exist; %abort cancel; %end;
      %let subpath="&subpath."; %let temppath=&temppath. &subpath.; %end;
      %let list=%qleft(&temppath);
      &list /* returns value to calling enivornment, like a function */
    %mend soc_quotepath;
    %macro soc_lib(ref, paths, options=) ;
      %local libpaths; %if %length(&ref) eq 0 %then %do; %put libref is blank; %abort cancel; %end;
      %if %length(%superq(paths)) eq 0 %then %do ;
      %put SOC-NOTE: For libref &ref the path is blank, libname assignment skipped; %end;
      %let libpaths= %soc_quotepath(&paths) ;
      libname &ref. %unquote((&libpaths.)) &options.;
    %mend soc_lib;

   /* Define request specific subdirectories */
    %let DPLOCAL = %soc_clean_paths(&_packageroot_dplocal.);
    %let MSOC = %soc_clean_paths(&_packageroot_msoc.);
    %let INFOLDER = %soc_clean_paths(&_packageroot_inputfiles.);
    %let SASPROGRAMS =%soc_clean_paths(&_packageroot_sasprograms.);
    %let INDATA=%soc_clean_paths(&prod_scdm.) ;

    %soc_lib(INDATA, &INDATA, options=%str(access=readonly))
  %end;
%mend scc_yn;
%scc_yn

/* Assign libnames */
/* %soc_lib(libref-name, path-name, options=%str(options-name=options-value)) */
%soc_lib(DPLOCAL,&DPLOCAL)
%soc_lib(MSOC,&MSOC)
%soc_lib(INFOLDER,&INFOLDER, options=%str(access=readonly))

/* Delete macro variable used as delimiter as no longer needed */
%symdel dlm ;

/* Create clean work environment */
proc datasets lib=work kill memtype=data nolist nodetails;
quit;


****************************************************************************************
*****                                BEGIN PROGRAM                                 *****
****************************************************************************************
***** NOTE: Programmer developing a packages writes the rest of the program below  *****
****************************************************************************************;
/*-------------------------------------------------------------------------------------*/
/* 1- Execute package                                                                  */
/*-------------------------------------------------------------------------------------*/
%let SnapshotVer=3.2.0;

/* Create clean output environment */
proc datasets lib=msoc kill memtype=data nolist nodetails nowarn;
run;
proc datasets lib=dplocal kill memtype=data nolist nodetails nowarn;
run;
quit;

%inc "&infolder.soc_scdm_snapshot_signature_module.sas" / nosource2;
%inc "&infolder.soc_scdm_formats_agecat.sas" / nosource2;
%inc "&infolder.macros/ms_macros.sas" / nosource2;
%inc "&infolder.macros/ms_delpatients.sas" / nosource2;
%inc "&infolder.macros/ms_delencounterids.sas" / nosource2;

%include "&infolder./macros/compile_macros.sas";
%compile_macros;


%inc "&infolder.soc_snapshot_driver.sas" / source2;

*+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+;
* End soc_scdm_data_snapshot_master.sas                                                 ;
*+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+;
