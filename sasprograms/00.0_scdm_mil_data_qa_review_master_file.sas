options linesize=100 pagesize=50;
/****************************************************************************************
*                                     SENTINEL PROGRAM
*****************************************************************************************
* NAME: 00.0_scdm_mil_data_qa_review_master_file.sas
*
* PURPOSE: The purpose of this program is to check the quality of data in the Sentinel
*   Common Data Model(SCDM). Prior to conducting a statistical query,
*   sufficient data screening methods should be used for all variables to identify
*   miscoded, missing, or otherwise disorganized data. Some of the items to check for
*   include: missing required fields,validating values, validating dates or date ranges,
*   validating data types, etc.
*
*   Data are generated from health plan administrative claims data held by Data Partners
*   (DP) into the SCDM.  Analytic models and monitoring are dependent on data, which are
*   both high in quality and contain a broad representation of the population. To ensure
*   the data will meet these goals, the Sentinel Operations Center (SOC) has written this
*   program to perform both data quality checks and to profile the data to expose the
*   breadth and depth of that data. This program defines the data check process, the
*   specific checks that will be performed and how flagged data will be identified.
*
*   This package also executes the SCDM Snapshot package, which includes SAS programs and input
*   files that operate together to produce a set of aggregate tables based on SCDM tables for the ETL
*   under review. These tables are returned to the SOC and used to produce descriptive reports that
*   characterize the current Sentinel Population.
*
*   All routine Sentinel distributed SAS program packages require that the QA Common Components (CC)
*   package is setup at each Data Partner (DP) site prior to execution of any Sentinel Operations
*   Center (SOC) distributed packages. By default, this program is set to run the CC package after QA
*   has completed. The purpose of CC is to provide commonly used metadata to executing SAS packages
*   ---e.g., location of SCDM formatted tables, SCDM table names, ETL refresh version, minimum
*   and maximum dates of data-completeness, etc.
*
* MAJOR STEPS:
*
* KEY DEPENDENCIES/CONSTRAINTS/CAVEATS:
*
*   PROGRAM INPUT:
*     PRODUCTION SCDM tables that MIL table is derived from:
*        indata.EnrTable    (enrollment)
*        indata.DemTable    (demographic)
*        indata.DisTable    (dispensing)
*        indata.EncTable    (encounter)
*        indata.DiaTable    (diagnosis)
*        indata.ProcTable   (procedure)
*        indata.FacTable    (facility)
*        indata.PvdTable    (provider)
*        indata.DeathTable  (death, if available)
*        indata.CODTable    (cause_of_death, if available)
*        indata.LabTable    (laboratory_results, if available)
*        indata.VitTable    (vital_signs, if available)
*        indata.iPharmtable (inpatient pharmacy, if available)
*        indata.iTranstable (inpatient transfusion, if available)
*        indata.PreTable    (prescribing, if available)
*        indata.PrrTable    (patient reported response table, if available)
*        indata.PrsTable    (patient reported survey table, if available)
*        indata.Featable    (feature engineering table, if available)
*
*     STAGED MIL SCDM table:
*        qadata.MILTable (mother_infant_linkage)
*
*     SAS programs:
*        00.0_scdm_mil_control_flow.sas
*        00.1_scdm_mil_standard_macros.sas
*        00.2_scdm_mil_formats.sas
*        00.3_scdm_mil_sas_log_checker_directory_cc.sas
*        00.4_scdm_mil_qasignaturerequest.sas
*        01.1_scdm_mil_data_qa_review-level1.sas
*        01.2_scdm_mil_data_qa_review-level2.sas
*        01.3_scdm_mil_data_qa_review-level3.sas
*        soc_setup_macros.sas
*
*     Lookup tables:
*        control_flow.sas7bdat
*        lkp_all_flags.sas7bdat
*        lkp_all_l1.sas7bdat
*
*   PROGRAM OUTPUT:  See documentation in DOCs subfolder of this request
*
*----------------------------------------------------------------------------------------
* CONTACT INFO:
*  Sentinel Coordinating Center
*  info@sentinelsystem.org
*
*----------------------------------------------------------------------------------------
* HISTORY:
*  Create date (mm/dd/yy): 10/2018
*  Last modified date (mm/dd/yy): 02/18/2025
*  Version: 4.0.2
*
****************************************************************************************/

/*---------------------------------------------------------------------------------------
*                                        DEFINITIONS
*----------------------------------------------------------------------------------------
* Evaluate_MIL...Location of ETL SCDM tables to be evaluated by this QA request
*
* DPL_MI...Location of the DPLOCAL subfolder containing the Mother_Infant Identification
*          results, created from a prior execution of either a 'qar' or 'mir' request
*
* _MILTABLE...The DP-specific name of the staged SCDM MIL table under review
*
* SCC...Location of the Phase A Common Components (CC) request associated with this ETL
*       Note: Organizations without a CC request should leave this parameter blank and
*             provide CC parameters in Section 1e.
*
* ReqID...Sentinel Project Request-ID
*    NOTE: This parameter needs to be set by the programmer preparing the Request-ID in
*          coordination with the Sentinel Operations Center (SOC)
*
* The following paths for the current request are automatically derived
*    DPLOCAL  ...path for data created that remains local (i.e. behind the DP firewall)
*    MSOC     ...path for data created to share with Sentinel Operations Center
*    INFOLDER ...path for program inputs (e.g. lookup data, include programs/macros)
*    SASPROGRAMS... path for the main SAS program for the request
*
*---------------------------------------------------------------------------------------/

*---------------------------------------------------------------------------------------
* NOTES:
*  For reasons of compatibility and standardization, ALL paths must meet the following
*  criteria:
*     1- Starting with the request directory, all subdirectory names must be specified
*        in lower case (for UNIX compatibility)
*     2- Slashes must be forward-leaning slashes '/' (for UNIX compatibility)
*     3- Paths must end with a final forward-leaning slash '/' (extra slashes are fine)
*     4- Paths must not contain any embedded spaces
*---------------------------------------------------------------------------------------;

/*-------------------------------------------------------------------------------------*/
/* SECTION 1: Data Partner/Data Site programmer defines parameters in this section.    */
/*-------------------------------------------------------------------------------------*/
/* 1a. Define path to location(s) of approved Phase A SCDM Tables and staged SCDM tables under review
       Delimit multiple paths via single space
       Example: %let Evaluate_MIL= //sentinel/etl22/PhaseA/ //sentinel/etl22/PhaseB/ */
  %let Evaluate_MIL= <edit-path>;

/* 1b. Define path to location of Mother-Infant ID results in DPLOCAL created by either
       an executed QA (qar) or MI ID (mir) package
       Example: %let DPL_MI= //sentinel/etl22/PhaseA/soc_qar_wp001_xxxx_v01/dplocal/   */
  %let DPL_MI= <edit-path>;

/* 1c. Specify the name of the staged SCDM MIL table, not including .sas7bdat. A default
       value has been entered. Edit if ETL-specific name is used at your site
       Example: %let _MILTABLE= mother_infant_linkage;                                 */
  %let _MILTABLE= mother_infant_linkage;

/* 1d. Edit macro variable SCC to point to the directory containing the executed Phase A
       Common Components (CC) request associated with this ETL, INCLUDING the request-id.
       Example: %let SCC = /<root>/soc_cca_wp001_xxxx_v01/
       NOTE: ORGANIZATIONS WITHOUT CC SHOULD LEAVE BLANK AND SKIP TO STEP 1f.          */
  %let SCC = <edit-path> ;

/* 1e. Identify the list of patients to exclude (if applicable) from snapshot-specific output.
       SAS Dataset should contain one variable, patid, and list all patids that should be excluded.
       Must include libname (e.g., indata.PtsToExclude).                          */
  %let PTSTOEXCLUDE= ;

/***************************************************************************************/
/* 1f. OPTIONAL: Organizations WITHOUT Phase A Common Components define parameters in this
       section, leaving STEP 1d. above blank.                                          */

    /* _DP is a descriptive identifier for your organization. Specify a 3-6 UPPERCASE
      character abbreviation for _DP. Example: %let DP=ABCDE ;                         */
       %let _DP= ;

    /* Specify the location of this request package, containing the 4 subfolders: dplocal,
      msoc, inputfiles, and sasprograms */
   /* Example: %let packageroot = A:/sentinel/qa_mil_package/                          */
       %let _packageroot = ;

    /* Specify the file path to the location of your Phase A Sentinel Common Data Model
      (SCDM) datasets.  Example: %let prod_scdm=A:/sentinel/etl1/phaseA/scdm/ ;        */
       %let prod_scdm= ;

    /* The following metadata describe characteristics of your SCDM. If known, modify the
      following parameters:
      /* DP_MinDate: Specify the overall SCDM minimum date in the format "DDMMMYYYY"d
                     Default value is "01Jan2000"d                                     */
      %let _DP_MinDate="01Jan2000"d ;

      /* DP_MaxDate: Specify the overall SCDM maximum date in the format "DDMMMYYYY"d
                    Default value is today's date (e.g. "&sysdate."d)                  */
       %let _DP_MaxDate = "&sysdate."d ;

      /* ETL: Please enter the ETL version # for your current Phase A production SCDM.
              Default is 1                                                              */
      %let _ETL_ = 1;

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
       %let _PRETABLE= ;    *specify the prescribing table name;
       %let _PRRTABLE= ;    *specify the patient reported response table name;
       %let _PRSTABLE= ;    *specify the patient reported survey table name;
       %let _FEATABLE= ;    *specify the feature engineering table name;
  /***************************************************************************************/
  /* 1f. Define Parameters for Common Components (CC) Phase B Run
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
     written to a metadata file for use by all production queries for this ETL.
     Example: %let _ROOT_DPLOCAL=//sentinel/requests/etl_22/
  */

    /* The individual production request packages create the global macro variable &ReqID
       --> Note:  This is separate from the ReqID for this CC request
       Example:  Production request &ReqID resolves to: "cder_ahr_soc_wp005_b03"
    */

    /* This CC package creates the global macro variable &DPLocal
       %let DPLOCAL = &_root_dplocal.&ReqID./dplocal/ ;
    */

    /* &DPLOCAL resolves to: //sentinel/requests/cder_ahr_soc_wp005_b03/dplocal/ */

  **************************************************************************************;
  /* Specify the local path(s) to the subfolders for FUTURE PRODUCTION requests run
    on this ETL, excluding the Request ID.

    Note: A value must be provided for each subfolder, even if they are located
    in a single directory.

    Example: %let _ROOT_DPLOCAL= /sentinel/requests/etl22/PhaseB/;
  */

  %let _ROOT_DPLOCAL= ;

  /* Optional: Only modify the defaults below if your site plans to use different paths
    for each of the following subfolders for production requests run on this ETL after,
    but not including, this request. */

   %let _ROOT_MSOC= &_root_dplocal ;
   %let _ROOT_INPUTFILES= &_root_dplocal ;
   %let _ROOT_SASPROGRAMS= &_root_dplocal ;

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
  *  [Project-ID: SOC]                       %let ProjID = soc ;
  *  [Workplan-Type: QA MIL package request] %let WPType = qmr ;
  *  [Workplan-ID: 1]                        %let WPID =   wp001 ;
  *  [DP-ID: SOC]                            %let DPID =   soc ;
  *  [Version-ID: version 1]                 %let VerID =  v01 ;
  *
  *  The example values above would produce Request-ID --> soc_qmr_wp001_soc_v01 ;
 /*------------------------------------------------------------------------------------*/
   /* Specify project-ID, workplan-type, workplan-ID, workplan-type, dpid, version-ID  */
   %let ProjID = <edit-projid>;
   %let WPType = <edit-wptype>;
   %let WPID   = <edit-wpid>;
   %let DPID   = <edit-dpid>;
   %let VerID  = <edit-verid>;

   /* Create request-id delimiter - Default is underscore (_)                          */
   %let dlm = _ ;  /* Do not edit */

   /* Specify ETL # for this request (i.e., Same ETL # for Phase A SCDM tables)        */
   %let _ETL = <edit-etl#> ;

  /* Specify if Phase B Common Components (CC) program package should run */
  /* Enter 'Y' for yes, otherwise leave blank or enter 'N' for no */
   %let Execute_CC = Y;

****************************************************************************************
*******                             END OF USER INPUT                             ******
*******                        DO NOT EDIT BELOW THIS LINE                        ******
******* (Consult with SOC or Sentinel team leader if you feel edits are required) ******
****************************************************************************************;
/*-------------------------------------------------------------------------------------*/
/* SECTION 3: Standard SOC environment setup code -- DO NOT EDIT
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
options FMTERR;

/* Create clean work environment */
proc datasets lib=work kill memtype=data nolist nodetails;
quit;

/* Request-ID (must be lower case) */
%let ReqID = %lowcase(&ProjID.&dlm.&WPType.&dlm.&WPID.&dlm.&DPID.&dlm.&VerID);

/* Delete macro variable used as delimiter as no longer needed */
%symdel dlm ;

/* Defensive Pre-Check: Abort Program if Execute_CC=Y and _ROOT_DPLOCAL variable not populated (for CCB)*/
%macro ccb_precheck;
  %macro isBlank(param);
    %sysevalf(%superq(param)=,boolean)
  %mend isBlank; 

  %if &Execute_CC=Y and %isBlank(&_ROOT_DPLOCAL)=1 %then %do;
    data _null_;
      put 90*'!';
      put ' ';
      put 'Defensive Pre-Check: _ROOT_DPLOCAL parameter not populated. Program is aborting.';
      put ' ';
      put '==> The _ROOT_DPLOCAL parameter cannot be blank if Execute_CC=Y.';
      put '==> Please go back to the master program and populate _ROOT_DPLOCAL.';
      put ' ';
      put 90*'!';
      put ' ';
    run;
    %abort cancel 99 ;
  %end ; 
%mend ccb_precheck;
%ccb_precheck

/* Rename and delete CCB _root variables as CCA uses same variables */
%let _CCROOT_DPLOCAL= &_ROOT_DPLOCAL;
%let _CCROOT_MSOC= &_ROOT_MSOC ;
%let _CCROOT_INPUTFILES= &_ROOT_INPUTFILES ;
%let _CCROOT_SASPROGRAMS= &_ROOT_SASPROGRAMS ;
%symdel _ROOT_DPLOCAL _ROOT_MSOC _ROOT_INPUTFILES _ROOT_SASPROGRAMS;

%macro scc_yn; /* Please do not edit */
  %global ccbypass;
  /*-----------------------------------------------------------------------------------*/
  /* If common components specified, define all file paths                             */
  /*-----------------------------------------------------------------------------------*/
  %if %str("&SCC.") ne %str("") %then %do;
    %let ccbypass=N;
    %inc "&SCC./inputfiles/cc_utility/cc_macvars.sas" /nosource2 ; /* Include CC  */
  %end;
  /*-----------------------------------------------------------------------------------*/
  /* If common components NOT specified, define all file paths and CC macro parameters */
  /*-----------------------------------------------------------------------------------*/
  %else %if %str("&SCC.") = %str("") %then %do;
    %let ccbypass=Y;

    /* If Execute_CC=Y then abort package and output error message, CCB requires CCA metadata to run successfully */
    %if %lowcase(&Execute_CC)=y %then %do;
      data _null_;
        put 80*'!';
        put ' ';
        put 'Program is aborting due to Phase A Common Components (CC) bypass.';
        put ' ';
        put '==> The Execute_CC parameter is set to Y. For a successful Phase B CC run,';
        put '    Phase A CC metadata is required. Ensure your site is not bypassing';
        put '    Phase A CC by populating section 1d of the master program.';
        put ' ';
        put 80*'!';
        put ' ';
      run;
      %abort cancel 99 ;
    %end ; 

    %else %do;
  /*-----------------------------------------------------------------------------------*/
  /* Define all macro parameters as global - DO NOT EDIT                               */
    %global etl _etl dp dp_mindate dp_maxdate dplocal msoc infolder sasprograms
            enrtable demtable distable enctable diatable proctable deathtable
            codtable labtable vittable ipharmtable itranstable phase miltable scdmver
            pretable pvdtable factable prrtable prstable featable;
  /*-----------------------------------------------------------------------------------*/
    %inc "&_packageroot./inputfiles/soc_setup_macros.sas" /nosource2;

    /* Assign Macro variables*/
    %let dp=&_dp;
    %let etl=&_etl_;
    %let _etl=&_etl;
    %let scdmver=&_scdmver;
    %let dp_mindate=&_dp_mindate;
    %let dp_maxdate=&_dp_maxdate;
    %let enrtable= &_enrtable;
    %let demtable= &_demtable;
    %let distable= &_distable;
    %let enctable= &_enctable;
    %let diatable= &_diatable;
    %let proctable= &_proctable;
    %let deathtable= &_deathtable;
    %let codtable= &_codtable;
    %let labtable= &_labtable;
    %let vittable= &_vittable;
    %let ipharmtable= &_ipharmtable;
    %let itranstable= &_itranstable;
    %let pretable= &_pretable;
    %let factable= &_factable;
    %let pvdtable= &_pvdtable;
    %let prrtable= &_prrtable;
    %let prstable= &_prstable;
    %let featable= &_featable;

    %symdel  _dp _dp_mindate _dp_maxdate _scdmver
            _enrtable _demtable _distable _enctable _diatable _proctable _deathtable
            _codtable _labtable _vittable _ipharmtable _itranstable _phase
            _pretable _pvdtable _factable _prrtable _prstable _featable;

   /* Define request specific subdirectories */
    %let DPLOCAL = %soc_clean_paths(&_packageroot./dplocal/) ;
    %let MSOC = %soc_clean_paths(&_packageroot./msoc/) ;
    %let INFOLDER = %soc_clean_paths(&_packageroot./inputfiles/) ;
    %let SASPROGRAMS = %soc_clean_paths(&_packageroot./sasprograms) ;
    %let INDATA=%soc_clean_paths(&prod_scdm) ;

    %soc_lib(INDATA, &INDATA, options=%str(access=readonly))
    %end;
  %end;
%mend scc_yn;
%scc_yn

/* Clean up path (e.g. convert/add slashes if necessary) and validate that path exist */
%let QADATA = %soc_clean_paths(&Evaluate_MIL. &DPL_MI) ;

/* Assign libnames */
/* %soc_lib(libref-name, path-name, options=%str(options-name=options-value)) */
%soc_lib(DPLOCAL,&DPLOCAL)
%soc_lib(MSOC,&MSOC)
%soc_lib(INFOLDER,&INFOLDER, options=%str(access=readonly))
%soc_lib(QADATA, &QADATA, options=%str(access=readonly))

/* Create root path for Phase B qa_common_components package */
%let CCroot=&INFOLDER.qa_common_components/;
%let SSroot=&INFOLDER.scdm_snapshot/;


*****************************************************************************************
******                                 BEGIN PROGRAM                               ******
*****************************************************************************************
****** NOTE: Programmer developing a packages writes the rest of the program below ******
*****************************************************************************************;
/*--------------------------------------------------------------------------------------*/
/* 1- Define package specific macro paramaters                                          */
/*--------------------------------------------------------------------------------------*/
%global QAVer Phase MaxObs deltable inftable irxtable protable dthtable;

%let protable=&proctable;
%let dthtable=&deathtable;
%let irxtable=&ipharmtable;
%let txntable=&itranstable;

/* Overwrite MIL table name from CC (set to blank for Phase A CC) */
%let miltable=&_miltable.;

/* Set default values for delivery and infant MI ID dplocal datasets */
%let deltable=r01_mother_deliveries;
%let inftable=r02_infants;

/* Overwrite Phase from CC */
%let Phase= B;

/* Current QA and CC versions needed for signature file */
%let QAVer= 4.0.2;
%let CCVer= 1.6.0;
%let SnapshotVer=3.1.2;

/* Set Number of Observations for dplocal flags datasets */
%let MaxObs= 500;

/* Set KILL_DIR_[local package directory] to 'y' for production runs */
%global kill_dir_work kill_dir_dplocal kill_dir_msoc;
%let kill_dir_work= y;
%let kill_dir_dplocal= y;
%let kill_dir_msoc= y;

options nodsnferr fmtsearch=(dplocal);
proc options group=memory;
run;

*---------------------------------------------------------------------------------------
* 2- Execute Program
*---------------------------------------------------------------------------------------;
%include "&INFOLDER.scdm_qa_mil_control_flow.sas" /nosource2;

*+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+;
* End 00.0_scdm_mil_data_qa_review_master_file.sas                                      ;
*+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+;
