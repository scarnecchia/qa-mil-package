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
*  Last modified date (mm/dd/yy): 7/29/2021
*  Version: 3.0.1
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
/* 1a. Define path to location of staged SCDM tables under review
       Example: %let Evaluate_MIL= //sentinel/etl22/PhaseB/ */
  %let Evaluate_MIL= <edit-path>/ ;

/* 1b. Define path to location of Mother-Infant ID results in DPLOCAL created by either
       an executed QA (qar) or MI ID (mir) package 
       Example: %let DPL_MI= //sentinel/etl22/PhaseA/soc_qar_wp001_xxxx_v01/dplocal/   */
  %let DPL_MI= <edit-root>/dplocal/;

/* 1c. Specify the name of the staged SCDM MIL table, not including .sas7bdat. A default
       value has been entered. Edit if ETL-specific name is used at your site         
       Example: %let _MILTABLE= mother_infant_linkage;                                 */
   %let _MILTABLE= mother_infant_linkage;

/* 1d. Edit macro variable SCC to point to the directory containing the executed Phase A
       Common Components (CC) request associated with this ETL, INCLUDING the request-id. 
       Example: %let SCC = /<root>/soc_cca_wp001_xxxx_v01/
       NOTE: ORGANIZATIONS WITHOUT CC SHOULD LEAVE BLANK AND SKIP TO STEP 1e.          */
  %let SCC = <edit-root>/<edit-CC-A-request-ID>/ ;
 
/***************************************************************************************/
/* 1e. OPTIONAL: Organizations WITHOUT Common Components define parameters in this 
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
       %let _PRETABLE= ;    *specify the prescribing table name */


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
   %let ProjID = <edit-project-id> ;
   %let WPType = <edit-workplan-type> ;
   %let WPID   = <edid-workplan-id> ;
   %let DPID   = <edit-dpid> ;
   %let VerID  = <edit-version> ;
 
   /* Create request-id delimiter - Default is underscore (_)                          */
   %let dlm = _ ;  /* Do not edit */  

   /* Specify ETL # for this request (i.e., Same ETL # for Phase A SCDM tables)        */
   %let _ETL = <edit-ETL-#> ;

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
  /*-----------------------------------------------------------------------------------*/
  /* Define all macro parameters as global - DO NOT EDIT                               */
    %global etl _etl dp dp_mindate dp_maxdate dplocal msoc infolder sasprograms
            enrtable demtable distable enctable diatable proctable deathtable  
            codtable labtable vittable ipharmtable itranstable phase miltable scdmver
            pretable pvdtable factable;
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

    %symdel  _dp _dp_mindate _dp_maxdate _scdmver
            _enrtable _demtable _distable _enctable _diatable _proctable _deathtable  
            _codtable _labtable _vittable _ipharmtable _itranstable _phase
            _pretable _pvdtable _factable;

   /* Define request specific subdirectories */
    %let DPLOCAL = %soc_clean_paths(&_packageroot./dplocal/) ;
    %let MSOC = %soc_clean_paths(&_packageroot./msoc/) ;         
    %let INFOLDER = %soc_clean_paths(&_packageroot./inputfiles/) ;
    %let SASPROGRAMS = %soc_clean_paths(&_packageroot./sasprograms) ;
    %let INDATA=%soc_clean_paths(&prod_scdm) ;

    %soc_lib(INDATA, &INDATA, options=%str(access=readonly))
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

/* Current QA version needed for signature file */
%let QAVer= 3.0.0;

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
%include "&INFOLDER.00.0_scdm_control_flow.sas" /nosource2;
%MASTER_FLOW ;

*+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+;
* End 00.0_scdm_mil_data_qa_review_master_file.sas                                      ;
*+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+;
