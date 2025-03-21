options linesize=100 pagesize=50;
/****************************************************************************************
*                                     SENTINEL PROGRAM
*****************************************************************************************
* NAME: 00.0_soc_qa_cc_master_file.sas
*
* PURPOSE: All routine Sentinel distributed SAS program packages require that the
* QA Common Components (CC) package is setup at each Data Partner (DP) site prior to
* execution of any Sentinel Operations Center (SOC) distributed packages.  The purpose
* of CC is to provide commonly used metadata to executing SAS packages---e.g., location
* of SCDM formatted tables, SCDM table names, ETL refresh version, minimum and maximum
* dates of data-completeness, etc.
*
* MAJOR STEPS: See workplan
*
* KEY DEPENDENCIES/CONSTRAINTS/CAVEATS:  See individual program modules in 'inputfiles'
*    subdirectory of this package.
*
*----------------------------------------------------------------------------------------
* CONTACT INFO:
*  Sentinel Coordinating Center
*  info@sentinelsystem.org
*
*----------------------------------------------------------------------------------------
* HISTORY:
*  Create date (mm/dd/yy): 01/31/2019
*  Last modified date (mm/dd/yy): 03/18/2025
*  Version: 1.6.1
*
****************************************************************************************/

/*---------------------------------------------------------------------------------------
*                                        DEFINITIONS
*----------------------------------------------------------------------------------------
* CCpackage_root...Location of the QA CC package request folder
*    NOTE: This parameter needs to be set by programmer at the DP site prior to execution
*
* Evaluate_SCDM...Location of ETL SCDM tables to be evaluated by this QA CC request
*    NOTE: This parameter needs to be set by programmer at the DP site prior to execution
*
* ReqID...Sentinel Project Request-ID
*    NOTE: This parameter needs to be set by the programmer preparing the Request-ID in
*          coordination with the Sentinel Operations Center (SOC)
*
* The following paths for FUTURE production requests using the ETL associated with this CC
*    NOTE:  This CC request will only use the &CCPACKAGE_ROOT, and NOT these paths.
*    _ROOT_DPLOCAL  ...path for data created that remains local (i.e. behind the DP firewall)
*    _ROOT_MSOC     ...path for data created to share with Sentinel Operations Center
*    _ROOT_INFOLDER ...path for program inputs (e.g. lookup data, include programs/macros)
*    _ROOT_SASPROGRAMS... path for the main SAS program for production requests
*
*---------------------------------------------------------------------------------------/

/*-------------------------------------------------------------------------------------*/
/* Section 1: Data Partner/Data Site programmer defines parameters in this section.    */
/*-------------------------------------------------------------------------------------*/
*****************************************************************************************
 >> Data Partner (DP) Local Directory Macro Variables <<

    IMPORTANT NOTES:
    1- DO use forward slashes (e.g. /) which are compatible with both UNIX and WINDOWS.
    2- DO use end of path separators (e.g. /xyz/ and not /xyz) which are assumed by many
       programs.
    3- DO NOT surround directory paths with quotes (e.g. /xyz/ and  not "/xyz/").
    4- DO NOT use embedded blanks/spaces within path names. */
****************************************************************************************;
  /* 1a. Specify the local path to the Sentinel CC request package, excluding the RequestID.
    Example: %let CC_Package_Root=//sentinel/requests/etl_22/PhaseB/requests/      */
    %let CCpackage_root= <edit-path> ;

  /* 1b. Provide the local path(s) to the QA approved SCDM data tables for this ETL.
    Note: To specify multiple paths, use a single space for paths separator.
    Example: %let Evaluate_SCDM=//sentinel/etl22/PhaseA/ //sentinel/etl22/PhaseB/  */
    %let Evaluate_SCDM= <edit-path(s)> ;

*****************************************************************************************
  Linkage between Root-Path parameters and FUTURE Production Request Subdirectory
  parameters.
*****************************************************************************************
  The root-path parameters in this common component request are defined for each standard
  workplan subdirectory, but they are not used in this request. These root-path parameters
  are specific to the ETL and phase, but not to a given production request. When
  combined with parameters from the master program for a specific production request,
  the full path(s) specific to that request are generated dynamically.

  Note that for most sites, all root-path parameters will point to the same directory.

  An example is provided using the variable "DPLOCAL" to illustrate how the parameters
  are resolved to dynamically build the full path to the "dplocal" subdirectory for
  the request "cder_ahr_soc_wp005_b03".

  /* The DP specifies the variable "_ROOT_DPLOCAL" in Section 1c. These values are then
    written to a metadata file for use by all production queries for this ETL. */
     Example: %let _ROOT_DPLOCAL=//sentinel/requests/etl_22/

    /* The individual production request packages create the global macro variable &ReqID
       --> Note:  This is separate from the ReqID for this CC request */
       Example:  Production request &ReqID resolves to: "cder_ahr_soc_wp005_b03"

    /* This CC package creates the global macro variable &DPLocal */
       %let DPLOCAL = &_root_dplocal.&ReqID./dplocal/ ;

    /* &DPLOCAL resolves to: //sentinel/requests/cder_ahr_soc_wp005_b03/dplocal/ */

  **************************************************************************************;
  /* 1d. Specify the local path(s) to the subfolders for FUTURE PRODUCTION requests run
    on this ETL, excluding the Request ID.

    Note: A value must be provided for each subfolder, even if they are located
    in a single directory.

    Example: %let _ROOT_DPLOCAL= /sentinel/requests/etl22/PhaseB/;
  */

  %let _ROOT_DPLOCAL= <edit-root>;

  /* Optional: Only modify the defaults below if your site plans to use different paths
    for each of the following subfolders for production requests run on this ETL after,
    but not including, this request. */

   %let _ROOT_MSOC= &_root_dplocal ;
   %let _ROOT_INPUTFILES= &_root_dplocal ;
   %let _ROOT_SASPROGRAMS= &_root_dplocal ;

/*-------------------------------------------------------------------------------------*/
/* Section 2: Analyst preparing Request-ID defines each parameter in coordination      */
/*    with the SOC. Specific requests are made up a project-ID, workplan-type,         */
/*    workplan-ID, DPID, version-ID                                             */
/*-------------------------------------------------------------------------------------*/
/*
/*        If this is your request   . . . . .  then set parameter values as follows
/*  ---------------------------------     -----------------------------------------------
/*  [Project-ID: CDER]                        %let ProjID = cder ;
/*  [Workplan-Type: ad hoc request]           %let WPType = ahr ;
/*  [Workplan-ID: 5]                          %let WPID =   wp005 ;
/*  [DPID: non-specific DP]                  %let DPID =   nsdp ;
/*  [Version-ID: beta 3]                      %let VerID =  b03 ;
/*  [use underscores as delimiter]            %let dlm = _ ;
/*
/*  The example values above would produce a Request-ID equal to cder_ahr_wp005_nsdp_b03
/*
/*-------------------------------------------------------------------------------------*/

/* Specify project-ID, workplan-type, workplan-ID, workplan-type, dp-id, version-ID */
  %let ProjID = <edit-project-ID>;
  %let WPType = <edit-workplan-type>;
  %let WPID   = <edit-workplan-ID>;
  %let DPID   = <edit-dp-id>;
  %let VerID  = <edit-version-ID>;

  %let dlm = _ ;

****************************************************************************************
*******                             END OF USER INPUT                             ******
*******                        DO NOT EDIT BELOW THIS LINE                        ******
******* (Consult with SOC or Sentinel team leader if you feel edits are required) ******
****************************************************************************************;
/*-------------------------------------------------------------------------------------*/
/* Section 3a: Standard SOC environment setup code -- DO NOT EDIT                      */
/*-------------------------------------------------------------------------------------*/
/* System options */
options nosymbolgen;
options nomlogic ;
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
options validvarname=v7;
options missing = .;
options fmterr;

/*-------------------------------------------------------------------------------------*/
/* Section 3b: Define macro variables and set paths                                    */
/*-------------------------------------------------------------------------------------*/
* Request-ID (must be lower case) *;
%let ReqID = %lowcase(&ProjID.&dlm.&WPType.&dlm.&WPID.&dlm.&DPID.&dlm.&VerID);

/* Delete macro variable used as delimiter as we no longer need it */
%symdel dlm ;

/*  Compile set up macros */
%inc "&CCPackage_root./&reqid./inputfiles/soc_setup_macros.sas" / nosource ;

/* Clean up path (e.g. convert/add slashes if necessary) and validate that path exists */
%let _ROOT=%soc_clean_paths(&CCPackage_root) ;
%let _ROOT=&_root.&reqid./ ;
%let QADATA=%soc_clean_paths(&Evaluate_SCDM) ;

/* Define request specific subdirectories */
%let DPLOCAL=&_root.dplocal/ ;
%let MSOC= &_root.msoc/ ;
%let INFOLDER= &_root.inputfiles/ ;
%let SASPROGRAMS= &_root.sasprograms/ ;

/* Assign libnames */
/* %soc_lib(libref-name, path-name, options=%str(options-name=options-value)) */
%soc_lib(DPLOCAL,&DPLOCAL)
%soc_lib(MSOC,&MSOC)
%soc_lib(INFOLDER,&INFOLDER. &infolder./cc_test/, options=%str(access=readonly))
%soc_lib(QADATA, &QADATA, options=%str(access=readonly))
%soc_lib(QARESULT, &infolder.dp_metadata, options=%str(access=readonly))

****************************************************************************************
*******                               BEGIN PROGRAM                               ******
****************************************************************************************;
/*-------------------------------------------------------------------------------------*/
/* Section 3c: Programmer developing a packages writes the rest of the program below   */
/*-------------------------------------------------------------------------------------*/

/* Specify Common Components and SCDM Versions */
%let CCVer = 1.6.1;

/* Use this conditional code to set the current SCDM version (e.g. 7.0.0) if it is
  not already present in the metadata file. */

/* Consider removing after all DP sites update to SCDM v8.0.0 */
%macro ifnotexist;
  %global scdmver;
  %let exist = 0;
  proc sql noprint;
    select count(*) into :exist from qaresult.qa_cc_metadata (where=(lowcase(variable)="scdmver"))
    ;
  quit;
  %if &exist. %then %do;
    proc sql noprint;
      select value into : SCDMVer trimmed
      from qaresult.qa_cc_metadata (where=(lowcase(variable)=lowcase("scdmver")))
      ;
    quit;
  %end;
  %else %do;
    %let SCDMVer=8.0.0;
  %end;
%mend;
%ifnotexist;

* Set KILL_DIR_[local package directory] to 'y' for production runs */
%global kill_dir_work kill_dir_dplocal kill_dir_msoc;
%let kill_dir_work= y;
%let kill_dir_dplocal= y;
%let kill_dir_msoc= y;

*---------------------------------------------------------------------------------------
* 1- Execute Driver Program
*---------------------------------------------------------------------------------------;
%include "&infolder./01.0_run_cc.sas" /nosource2;


*+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+;
* End 00.0_soc_qa_cc_master_file.sas                                                    ;
*+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+;
