/*-------------------------------------------------------------------------------------*\
|  PROGRAM NAME:                                                                        |
|     00.4_mscdm_qasignaturerequest.sas                                                 |
|                                                                                       |
|  QA PACKAGE VERSION: 4.0.3                                                            |
|---------------------------------------------------------------------------------------|
|  PURPOSE:                                                                             |
|     The purpose of the program is to create request-level metadata "signature" files  |
|                                                                                       |
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

/*libname msoc "&msoc.";*/

%MACRO MS_QASIGNATUREREQUEST;

/*--Get the names of all the SIGNATURE files in the MSOC folder--*/
  data _sigfiles;
   keep fname;
   length filref $8 fname $80; 
   rc = filename(filref, "&DPLOCAL"); 
   if rc = 0 then do; 
      dir_id = dopen(filref); 
      rc = filename(filref); 
   end; 
   else do; 
      length msg $200.; 
      msg = sysmsg(); 
      put msg=; 
      dir_id = .; 
   end;
   if dir_id <= 0 then do;
      putlog '================================================================';
      putlog ' ERR'"OR: Unable to open directory.";
      abort cancel;
      putlog '================================================================';
   end;
   n_members = dnum(dir_id);
   do i = 1 to n_members; 
      fname = dread(dir_id, i); 
      fid = mopen(dir_id, fname); 
      if fid > 0 then output; 
   end;
   rc = dclose(dir_id);
run;

/*--Put all the signature file names in a string and create macro variables with 
    the string and count of names--*/
data _null_; set _sigfiles end=eof;
   length strng $ 1000 filname $ 36;;
   retain strng;
   retain nfiles 0;

   /*-Look for all files with the phase 'signature' in them, but only with mXXrX or mXXrXX run/scenario numbers
      in the name.  If a req signature file had already been created, it will have an mXX in the name and,
      therefore, [correctly] not included in the list of signature files being read in-*/

   /* has phrase '_signature' and not the output file prefix 'allrun' from a prior run */
   if index(lowcase(fname),'_signature') > 0 and
      index(lowcase(fname),'alltable') = 0 then do; 
         filname = substr(fname,1,index(fname,'.')-1);
         strng = strip(strng) || ' ' || strip(filname);
         nfiles = nfiles + 1;
   end;
   if eof then do;
      call symput("FLIST",strng);
      call symput("NFILS",put(nfiles,3.));
   end;
run;

%PUT FILE COUNT: &NFILS;
%PUT FILE LIST: &FLIST;

/*--Loop through all signature files gathering information for request-level sig file--*/
%DO F = 1 %TO &NFILS;

data _tmp_signature; 
   length DPID $ 4 SiteID $ 8 MSReqID $ 36 MSProjID $16 MSWPType MSWPID MSDPID MSVerID QAVer SCDMVer 
          OSAbbr OSName SASVersion $ 12 SASVersionLong $ 30 RunType NCPU $ 12;
   length Seconds 8; 
   set DPLOCAL.%SCAN(&FLIST,&F) end=eof;
   retain DPID SiteID MSReqID MSProjID MSWPType MSWPID MSDPID MSVerID QAVer SCDMVer OSAbbr 
          OSName SASVersion SASVersionLong RunType NCPU Seconds;
   keep   DPID SiteID MSReqID MSProjID MSWPType MSWPID MSDPID MSVerID QAVer SCDMVer OSAbbr 
          OSName SASVersion SASVersionLong RunType NCPU Seconds;

   length svalue $ 49;

   /* Save necessary signature file values for displaying in Request Summary output */

   svalue = strip(value);
   select (upcase(strip(variable)));
      when ('DPID') DPID = svalue;
      when ('SITEID') SITEID = svalue;
      when ('MSREQID') MSREQID = svalue;
      when ('MSPROJID') MSPROJID = svalue;
      when ('MSWPTYPE') MSWPTYPE = svalue;
      when ('MSWPID') MSWPID = svalue;
      when ('MSDPID') MSDPID = svalue;
      when ('MSVERID') MSVERID = svalue;
      when ('QAVER') QAVer = svalue;
      when ('SCDMVER') SCDMVer= svalue;
      when ('OSABBR') OSAbbr = svalue;
      when ('OSNAME') OSName = svalue;
      when ('SASVERSION') SASVersion = svalue;
      when ('SASVERSIONLONG') SASVersionLong = svalue;
      when ('RUNTYPE') RunType = svalue;
      when ('NCPU') NCPU = svalue;
      when ('SECONDS') Seconds = input(strip(compress(svalue,,'A')),15.);
      otherwise;
   end;
         
   if eof then do;
      output;
   end;
run;

proc append base=_all_sigs data=_tmp_signature;
run;

%END;

/*--Summarize signature file information from all runs into a single record of information--*/
/*     (allowing any number of scenarios per summary run in this version of the program)     */
data _sig1; set _all_sigs end=eof;
   retain total_seconds 0;
   total_seconds = total_seconds + seconds;
   if eof then output;
run;

/*--Add machine/software/run specific information to the accumulated run information--*/
data _signatures; set _sig1;
  length TotalRequestTime $ 30;
  drop hours minutes seconds2 total_seconds seconds;
  hours=int(total_seconds/3600);
  minutes=int((total_seconds-hours*3600)/60);
  seconds2=int((total_seconds-hours*3600-minutes*60));
  TotalRequestTime=strip(put(hours, 3.))||' h '||strip(put(minutes,2.))||' m '||strip(put(seconds2,2.))||' s';
run;

/*--Reorganize information and output to request-level signature file--*/
proc transpose data=_signatures out=_signature(rename=_NAME_=Variable rename=COL1=Value);
   var _ALL_;
run;

data dplocal.&prefix.alltable_signature; 
  set _signature;
  value = strip(value);
  label variable = "Metadata Variable";
run;

proc datasets lib=work nolist;
   delete _sigfiles _tmp_signature _all_sigs _sig1 _signatures _signature;
quit;

%mend ms_qasignaturerequest; 
%ms_qasignaturerequest;

*-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-;
*  End 00.4_mscdm_qasignaturerequest.sas                                                ;
*-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-;
