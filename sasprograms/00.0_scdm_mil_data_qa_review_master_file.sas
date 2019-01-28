options linesize=100 pagesize=50;
/****************************************************************************************
*                                         SENTINEL PROGRAM
*****************************************************************************************
* NAME: 00.0_scdm_mil_data_qa_review_master_file.sas 
*
* PURPOSE: The purpose of this program is to check the quality of data in the Common Data
*   Model for the Sentinel Inititive (SCDM). Prior to conducting a statistical query, 
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
*        indata.EnrTable (enrollment)
*        indata.DemTable (demographic)
*        indata.DisTable (dispensing)
*        indata.EncTable (encounter)
*        indata.DiaTable (diagnosis)
*        indata.ProcTable (procedure)
*        indata.DeathTable (death, if available)
*        indata.CODTable (cause_of_death, if available)
*        indata.LabTable (laboratory_results, if available)
*        indata.VitTable (vital_signs, if available)
*        
*
*    qadata.MILTable (mother_infant_linkage)
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
*        99.1_scdm_mil_data_qa_review-minmax_dates.sas
* 
*     Lookup tables:
*        control_flow_mil.sas7bdat
*        lkp_mil_flags.sas7bdat
*        lkp_mil_l1.sas7bdat
*
*   PROGRAM OUTPUT:  See documentation in DOCS subfolder of this request
*            
*----------------------------------------------------------------------------------------
* CONTACT INFO: 
*  Sentinel Coordinating Center
*  info@sentinelsystem.org
*
*----------------------------------------------------------------------------------------
* HISTORY:
*  Create date (mm/dd/yy): 01/28/2019
*  Last modified date (mm/dd/yy): NA
*  Version: 3.0.0
*
****************************************************************************************/

/*---------------------------------------------------------------------------------------
*                                        DEFINITIONS
*----------------------------------------------------------------------------------------
* MILQApackage_root...Location of the QA package request folder
*    NOTE: This parameter needs to be set by programmer at the DP site prior to execution
*
* Evaluate_MIL...Location of ETL SCDM tables to be evaluated by this QA request  
*    NOTE: This parameter needs to be set by programmer at the DP site prior to execution
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

/*-------------------------------------------------------------------------------------*/
/* Section 1: Data Partner/Data Site programmer defines parameters in this section.			 */
/*-------------------------------------------------------------------------------------*/

 /* Define path(s) to location of staged SCDM tables under review */
   /* Example: %let Evaluate_MIL= //sentinel/etl22/PhaseB/ */
   %let Evaluate_MIL= <edit-path>;

 /* Specify the name of the staged SCDM MIL table, not including .sas7bdat  */
   /* Default values have been entered. Edit if ETL-specific names are used at your site*/
	  %let MILTABLE= mother_infant_linkage;   *specify the mother-infant-linkage table name *;  

/* Define path to location of Mother-Infant ID results (e.g.  created by either the QA (qar)
   or MI ID (mir) package */
   /* Example: %let Evaluate_MI= //sentinel/etl22/PhaseA/soc_qar_wp001_xxxx_v01/dplocal/ */
   %let Evaluate_MI= <edit-path>

   /* Edit macro variable MSCC to point to the directory containing the Phase A CC request
      associated with this ETL */
     /* e.g. \<root>\soc_cca_wp001_xxxx_v01\inputfiles\cc_utility_macvars.sas */
   %let QA_CCA = <edit-root>\cc_utility_macvars.sas ;

/*-------------------------------------------------------------------------------------*/
/* Section 2: SOC Programmer/Analyst preparing the Request sets each parameter prior 
              to distributing to DP  
/*-------------------------------------------------------------------------------------*/
 /* Specific request IDs are made up of the following 5 tokens:
      project-ID, workplan-type, workplan-ID, unique-DPID, version-ID */   
 /*-------------------------------------------------------------------------------*/
  *  If this is your request   . . . . . . .then set parameter values as follows 
  *  ---------------------------------      --------------------------------------
  *  [Project-ID: SOC]                      %let ProjID = soc ;  
  *  [Workplan-Type: QA package request]    %let WPType = qar ; 
  *  [Workplan-ID: 1]                       %let WPID =   wp001 ; 
  *  [Unique-DPID: SOC]                     %let DPID =   soc ;     
  *  [Version-ID: version 1]                %let VerID =  v01 ;               
  *
  *  The example values above would produce Request-ID --> soc_qar_wp001_soc_v01 ;
 /*------------------------------------------------------------------------------------*/

 /* Specify project-ID, workplan-type, workplan-ID, workplan-type, dpid, version-ID */
   %let ProjID = <edit-project-id> ; 
   %let WPType = <edit-workplan-type> ;      
   %let WPID   = <edid-workplan-id> ;        
   %let DPID   = <edit-dpid> ; 
   %let VerID  = <edit-version> ;        
   
 /* Specify ETL # for this request (i.e. ETL # for Phase A SCDM tables) */
   %let PhaseA_ETL = <edit-ETL-#> ;

****************************************************************************************
*******                             END OF USER INPUT                             ******
*******                        DO NOT EDIT BELOW THIS LINE                        ******
******* (Consult with SOC or Sentinel team leader if you feel edits are required) ******
****************************************************************************************;
/*-------------------------------------------------------------------------------------*/
/* Section 3: Standard SOC environment setup code -- DO NOT EDIT
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
   
/* Include Common Components */
%inc "&QA_CCA" /source2 ;   /* Please do not edit */ 

/* Create clean work environment */
proc datasets lib=work kill memtype=data nolist nodetails;
quit;

/* Create request-id delimiter - Default is underscore (_) */
%let dlm = _ ; 

/* Request-ID (must be lower case) */
%let ReqID = %lowcase(&ProjID.&dlm.&WPType.&dlm.&WPID.&dlm.&DPID.&dlm.&VerID);

/* Delete macro variable used as delimiter as no longer needed */
%symdel dlm ; 

*---------------------------------------------------------------------------------------
* NOTES:
*  For reasons of compatibility and standardization, paths must meet the following 
*  criteria:
*     1- Starting with the request directory, all subdirectory names must be specified 
*        in lower case (for UNIX compatibility)
*     2- Slashes must be forward-leaning slashes '/' (for UNIX compatibility)
*     3- Paths must end with a final forward-leaning slash '/' (extra slashes are fine)
*     4- Paths must not contain any embedded spaces
*---------------------------------------------------------------------------------------;
/* Clean up path (e.g. convert/add slashes if necessary) and validate that path exist */
 %let QADATA = %soc_clean_path(&Evaluate_MIL. &Evaluate_MI) ;
 %let DPLOCAL = %soc_clean_path(&DPLOCAL) ;
	%let MSOC = %soc_clean_path(&MSOC) ;
	%let INFOLDER = %soc_clean_path(&INFOLDER) ;
	%let SASPROGRAMS = %soc_clean_path(&SASPROGRAMS) ;

	/* Define request specific subdirectories */
	%let DPLOCAL = &_root_dplocal.&ReqID./dplocal/ ; 
	%let MSOC = &_root_msoc.&ReqID./msoc/ ;            
	%let INFOLDER = &_root_inputfiles.&ReqID./inputfiles/ ;  
	%let SASPROGRAMS = &_root_sasprograms.&ReqID./sasprograms/ ;  

/* Assign libnames */
/* %soc_lib(libref-name, path-name, options=%str(options-name=options-value)) */
%soc_lib(DPLOCAL,&DPLOCAL)
%soc_lib(MSOC,&MSOC)
%soc_lib(INFOLDER,&INFOLDER, options=%str(access=readonly))
%soc_lib(QADATA, &QADATA, options=%str(access=readonly))

****************************************************************************************
*******                               BEGIN PROGRAM                               ******
****************************************************************************************;
/*-------------------------------------------------------------------------------------*/
/* NOTE: Programmer preparing a packages includes/writes the rest of the program below */
/*-------------------------------------------------------------------------------------*/
%global Phase QAVer_MIL SCDMVer MaxObs;

/* Default approval phase needed for metadata file */
%let Phase= B; 

/* Current QA version needed for signature file */
%let QAVer_MIL= 2.1.0;

/* Current SCDM version needed for signature file */
%let SCDMVer= 7.0.0; 
 
/* Set Number of Observations for dplocal flags datasets */
%let MaxObs= 500;

/* Set KILL_DIR_[local package directory] to 'y' for production runs */
%global kill_dir_work kill_dir_dplocal kill_dir_msoc;
%let kill_dir_work= y;
%let kill_dir_dplocal= y;
%let kill_dir_msoc= y;

*---------------------------------------------------------------------------------------
* 1- Execute Program
*---------------------------------------------------------------------------------------;
options nodsnferr fmtsearch=(dplocal);
proc options group=memory;
run;

%include "&INFOLDER.00.0_scdm_mil_control_flow.sas" /nosource2;
%MASTER_FLOW ;

*+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+;
* End 00.0_scdm_mil_data_qa_review_master_file.sas                                      ;
*+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+;
