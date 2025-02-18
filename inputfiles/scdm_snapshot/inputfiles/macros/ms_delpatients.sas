****************************************************************************************************
*                                           PROGRAM OVERVIEW
****************************************************************************************************
*
* PROGRAM: ms_delpatients.sas
*
* Created (mm/dd/yyyy): 07/31/2014
* Version: 1.1
*
*--------------------------------------------------------------------------------------------------
* PURPOSE:
*   This program deletes PatId from a file
*
*  Program inputs:
*   -dataset to delete patients from
*   -dataset containing the list of patients to delete
*   -&p. = partition number, created by an external loop
*
*  Program outputs:
*   -dataset containing record excluding patients to delete
*
* PARAMETERS:
*   -datafile   = Name of the dataset to delete patients from.
*   -Ptsfile    = Name of the dataset containing the list of patients to delete.
*   -outfile    = Name of the output dataset containing record excluding patients.
*   -patvar     = Name of Patient identifier. Default is PatID.
*
*  Programming Notes:
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
*             mm/dd/yy
*
***************************************************************************************************;

%MACRO ms_delpatients(datafile=, ptsfile= , outfile=, patvar=patid);

%put =====> MACRO CALLED: ms_delpatients v1.1;

    %ISDATA(dataset=&ptsfile.);
      %IF %EVAL(&NOBS.>=1) %THEN %DO;
         %if &numpartitions. gt 1 %then %do;
            data exclude;
              merge &ptsfile.(in=a rename=(patid = &patvar)) &partable.(in=b rename=(patid = &patvar) where=(partitionID=&p.));
              by &patvar;
                if a and b;
            run;
          %end;
            %else %do;
              data exclude;
                set &ptsfile.(rename=(patid = &patvar));
              run;
          %end; /* end numpartitions check */

      data &outfile.;
        if 0 then set exclude (keep=&patvar.);
        declare hash ht (hashexp:16,dataset:"exclude");
        ht.definekey("&patvar.");
        ht.definedone();

        do until(eof1);
          set &datafile. end=eof1;
          if ht.find() ne 0 then output;
        end;
        stop;
        run;
    %END;
    %ELSE %IF %upcase(%str("&datafile.")) ne %upcase(%str("&outfile.")) %THEN %DO;
        data &outfile.;
        set &datafile.;
        run;
    %END;

    %put NOTE: ********END OF MACRO: ms_delpatients v1.1********;

%MEND ms_delpatients;
