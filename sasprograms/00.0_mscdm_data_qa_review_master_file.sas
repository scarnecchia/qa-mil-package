options linesize=100 pagesize=50;

/*--------------------------------------------------------------------------------------\
| PROGRAM NAME: 00.0_mscdm_data_qa_review_master_file.sas                               |
|                                                                                       |
| MIL/MIS QA PACKAGE VERSION: 2.0.0                                                             |
| DATE: 01/30/2018                                                                      |
|---------------------------------------------------------------------------------------|
| PURPOSE:                                                                              |
|     The purpose of this program is to check data characteristics and quality of the   |
|	  SCDM-formatted Mother-Infant Linkage table.					|
|	  Prior to conducting a statistical 		                                        |
|	  query, sufficient data screening methods should be used for all variables to 		|
|	  identify miscoded, missing, or otherwise disorganized data. Some of the items 	|
|	  to check for include: missing required fields, validating values, validating 		|
|	  dates or dateranges, validating data types, etc.                                  |
|                                                                                       |
|     Data are generated from health plan administrative claims data held by Data       |
|     Partners into the SCDM.  Analytic models and monitoring are dependent on data,    |
|     which are both high in quality and contain a broad representation of the          |
|     population. To ensure the data will meet these goals, the Sentinel Operations     |
|     Center (SOC) has written this program to perform both data quality checks and to  |
|     profile the data to expose the breadth and depth of that data. This program       |
|     defines the data check process, the specific checks that will be performed and    |
|     how flagged data will be identified.                                              |
|---------------------------------------------------------------------------------------|
| PROGRAM INPUT:                                                                        |
|     MSCDM tables:                                                                     |
|           mscdm.EnrTable                                                              |
|           mscdm.DemTable                                                              |
|           mscdm.EncTable    															|
|           ds.[RUNID]_mother_deliveries                                                |
|           ds.[RUNID]_infants                                                          |
|           mil.MILTABLE or                                                             |
|           mil.MISTABLE				                                                |
|                                                                                       |
|     Dependencies:                                                                     |
|           ms_common_components.sas (not part of QA package, pre-placed via CC pkg)    |
|                                                                                       |
|     SAS programs:                                                                     |
|           00.0_mscdm_control_flow.sas                                                 |
|           00.1_mscdm_standard_macros.sas                                              |
|           00.2_mscdm_formats.sas                                                      |
|           00.3_mscdm_sas_log_checker_directory_cc.sas                                 |
|           00.4_mscdm_qasignaturerequest.sas                                           |
|           01.1_mscdm_data_qa_review-level1.sas                                        |
|           01.2_mscdm_data_qa_review-level2.sas                                        |
|           99.2_mscdm_data_qa_review-level3.sas                                        |
|                                                                                       |
|     Input files:                                                                      |
|           control_flow.sas7bdat                                                       |
|           lkp_all_flags.sas7bdat                                                      |
|           lkp_all_l1.sas7bdat                                                         |
|                                                                                       |
|     PROGRAM OUTPUT:                                                                   |
|                   See Workplan PDF                                                    |
*---------------------------------------------------------------------------------------*
|                                      DEFINITIONS                                      |
*---------------------------------------------------------------------------------------*
| MSCC...[Mini-]Sentinel Common-Components File                                         |
|     Specific to each Data Partner/Data Site, the Common-Components defines key:       |
|       - macro variables (e.g. Data Partner ID, Min and Max Dates, MSCDM table names)  |
|       - libname assignments (e.g. libref INDATA is assigned to production SCDM tables)|
|     NOTE: This parameter needs to be set by programmer at the Data Partner/Data Site  |
|                                                                                       |
| Evaluate_MSCDM... Location of ETL SCDM tables to be evaluated by this QA request      |
|     NOTE: This parameter needs to be set by programmer at the Data Partner/Data Site  |
|                                                                                       |
| MSReqID...[Mini-]Sentinel Project Request-Id                                          |
|     NOTE: This parameter needs to be set by the programmer preparing the Request-ID   |
|           in coordination with the Sentinel Operations Center (SOC)                   |
|                                                                                       |
|---------------------------------------------------------------------------------------|
| CONTACT:                                                                              |
|     Sentinel Coordinating Center                                                      |
|     info@sentinelsystem.org                                                           |
\--------------------------------------------------------------------------------------*/

/***************************************************************************************/
/*                                    User Inputs                                      */
/***************************************************************************************/

/*-------------------------------------------------------------------------------------*/
/* NOTE: The DP Programmer executing this Request sets the following macro variables   */
/*-------------------------------------------------------------------------------------*/

/* Edit macro variable MSCC to point to the directory containing the CC file .sas file */
/* e.g. <full-path>\ms_common_components.sas */
%let MSCC = <edit-path>/ms_common_components.sas ;

/* Include Common Components */
%inc "&MSCC" /source2 ;   /* Please do not edit */

/* Edit macro variable Evaluate_MSCDM to specify path to directory with SCDM data tables 
   to be evaluated by this QA request */
%let Evaluate_MSCDM = ;

/* Name of the Mom Infant Linkage SAS dataset*/
%let MILTABLE =;

/* Edit macro variable Evaluate_MIL to specify path to directory with mom Infant
   linkage table to be evaluated by this QA request */
%let Evaluate_MIL = ;

/* Name of the Mother deliveries SAS dataset from distributed code (residing at distributed code DPLOCAL folder) */
%let deliveries = ;

/*Name of the Infants SAS dataset from distributed code (residing at distributed code DPLOCAL folder)*/
%let infants = ;

/* Edit macro variable Evaluate_DS to specify path to directory with Mother deliveries
   and infant table to be evaluated by this QA request */
%let Evaluate_DS = ;

/*-------------------------------------------------------------------------------------*/
/* Notes about SCDM table names defined in Common Components (CC)                      */
/* ------------------------------------------------------------------------------------*/
/*  If the names or presence/absence of SCDM tables has changed for the this ETL now   */
/*  being evaluted as compared to the currently approved ETL, we will need to override */
/*  the values for the Common Components macro variables holding the table names.      */
/*  The values need to be overwritten here, not in CC, because the values in CC need   */
/*  to point to the currently approved ETL.  Once the ETL under review has been        */
/*  approved,  the values may be updated in Common Components.                         */
/* ------------------------------------------------------------------------------------*/
/***************************************************************************************\
  The macro variables below hold the SCDM table names for your site as currently 
  defined for your approved ETL as specified in Common Components. Values should be 
  changed only if necessary (see note above).
\***************************************************************************************/
;
%let EnrTable=   &EnrTable ;       * Enrollment table name     *;
%let DemTable=   &DemTable ;       * Demographic table name    *;
%let DisTable=   &DisTable ;       * Dispensing table name     *;
%let DiaTable=   &DiaTable ;       * Diagnosis table name      *;
%let ProcTable=  &ProcTable ;      * Procedure table name      *;
%let EncTable=   &EncTable ;       * Encounter table name      *;
%let DeathTable= &DeathTable ;     * Death table name          *;
%let CODTable=   &CODTable ;       * Cause_of_death table name *;
%let LabTable=   &LabTable ;       * Lab_result table name     *;

*****************************************************************************************
*******                             END OF USER INPUT                              ******
*******                        DO NOT EDIT BELOW THIS LINE                         ******
*******                   (Consult with SOC or Sentinel team leader                ******
*******                      if you feel edits are required)                       ******
*****************************************************************************************
;

/*-------------------------------------------------------------------------------------*/
/* NOTE: Programmer preparing RequestID defines the parameter MSReqID ReqETL           */
/*       in coordination with the SOC                                                  */
/*-------------------------------------------------------------------------------------*/
/*-------------------------------------------------------------------------------------*\
* Specific RequestIDs are made up of: 
*     project-id, workplan-type, workplan-id, unique-dpid, version-id
*
*  If this is your request is...     -->  then set parameter values as follows...
*  ---------------------------------      ---------------------------------------
*   [Project SOC]                          %let MSProjID = soc ;
*   [Work Plan Type]                       %let MSWPType = qar;
*   [Workplan # 5]                         %let MSWPID = wp005 ;
*   [Unique DPID - MSOC]                   %let MSDPID = msoc;
*   [Beta 3]                               %let MSVerID = b03 ;
*   [use underscores as delimiter]         %let dlm = _ ;
*
*  The example values above would produce a Request-Id equal to soc_qar_wp005_msoc_b03
\*--------------------------------------------------------------------------------------*/

* Specify expected ETL # for this request (i.e. last approved ETL # incremented by 1) *;
%let ReqETL = <edit-expected-ETL-#>;

* Specify project-id, workplan-type, workplan-id, unique-dpid, and version-id *;
%let MSProjID =  ;
%let MSWPType =  ;
%let MSWPID   =  ;
%let MSDPID   =  ;
%let MSVerID  =  ;

%let dlm = _ ;

* Request-Id *;
%let MSReqID = &MSProjID.&dlm.&MSWPType.&dlm.&MSWPID.&dlm.&MSDPID.&dlm.&MSVerID ;

* Delete macro variable used as delimiter as we no longer need it *;
%symdel dlm ;

/*-------------------------------------------------------------------------*/
/* NOTE: Programmer maintaining the QA code defines the following versions */
/*-------------------------------------------------------------------------*/
%let QAVer   = 2.0.0 ;  /* Current QA version needed for signature file */
%let SCDMVer = 6.0.2 ;  /* Current SCDM version needed for signature file */

/*-------------------------------------------------------------------------*/
/* NOTE: Programmer maintaining the QA code might set obslimit for testing */
/*-------------------------------------------------------------------------*/
/*Set Number of Observations (for testing purposes) */
%let MaxObs=500;

/*-------------------------------------------------------------------------*/
/* NOTE: Programmer maintaining the QA code may reset kill_dir_[directory] */
/*     to N for specific needs (testing, dp issue), but default=y          */
/*-------------------------------------------------------------------------*/
/*Set KILL_DIR_[local package directory] to 'y' for production runs */
%let kill_dir_work= y;
%let kill_dir_dplocal= y;
%let kill_dir_msoc= y;

*-------------------------------------------------------------------------------------------------
* 0- Setup Environment
*-------------------------------------------------------------------------------------------------;
/*-------------------------------------------------------------------------*/
/* NOTE: This is standard MSOC environment setup code -- DO Not EDIT       */
/*-------------------------------------------------------------------------*/
/* System options */
options obs=MAX ;
options msglevel=i ;
options mprint mprintnest ;
options errorcheck=strict errors=0 ;
options merror serror ;
options dkricond=error dkrocond=error mergenoby=warn;
options dsoptions=nonote2err noquotelenmax ;
options reuse=no ;
options fullstimer ;
** for qa program;
options nodsnferr fmtsearch=(dplocal);
*------------------------------------------------------------------------------------------------
* NOTES:
*   For reasons of compatibility and standardization, paths must meet the following criteria:
*     1- Starting with the request subdirectory, all subdirectory names must be specified in
*        lower case (for UNIX compatibility)
*     2- Slashes must be forward-leaning slashes '/' (for UNIX compatibility)
*     3- Paths must end with a final forward-leaning slash '/' (extra slashes are fine)
*------------------------------------------------------------------------------------------------*/

/* Request-Id parameter value must be lower case */
%let MSReqID = %lowcase(&MSReqID) ;

/*Prefix added to the all DPLOCAL and MSOC files*/
%let prefix = mil_;

/* Define Request Specific Subdirectories */
%let DPLOCAL = &_root_dplocal./&MSReqID./dplocal/ ;
%let MSOC = &_root_msoc./&MSReqID./msoc/ ;
%let INFOLDER = &_root_inputfiles./&MSReqID./inputfiles/ ;
%let SASPROGRAMS = &_root_sasprograms./&MSReqID./sasprograms/ ;

/* Clean up paths (e.g. convert or add slashes when necessary) and validate that paths exist */
%let DPLOCAL = %ms_clean_path(&DPLOCAL) ;
%let MSOC = %ms_clean_path(&MSOC) ;
%let INFOLDER = %ms_clean_path(&INFOLDER) ;
%let SASPROGRAMS = %ms_clean_path(&SASPROGRAMS) ;

/* Assign libnames */
/* e.g. %ms_lib(<libref-name>, <path-name>, options=%str(options-name=<options-value>)) */
%ms_lib(dplocal, &DPLOCAL)
%ms_lib(msoc, &MSOC)
%ms_lib(infolder, &INFOLDER, options=%str(access=readonly))
%ms_lib(mscdm, &Evaluate_MSCDM, options=%str(access=readonly))
%ms_lib(mil, &Evaluate_MiL, options=%str(access=readonly));
%ms_lib(ds, &Evaluate_DS, options=%str(access=readonly));

/* Create clean work environment */
proc datasets lib=work kill memtype=data nolist nodetails;
quit;

*-------------------------------------------------------------------------------------------------
* 1- Execute Program
*-------------------------------------------------------------------------------------------------;
%include "&INFOLDER.00.0_mscdm_control_flow.sas" /nosource2;
%MASTER_FLOW ;

*+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+;
* End 00.0_mscdm_data_qa_review_master_file.sas                                                   ;
*+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+;

