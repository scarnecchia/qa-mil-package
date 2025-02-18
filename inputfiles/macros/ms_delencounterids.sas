/**
   @file ms_delencounterids.sas
   @brief This macro deletes encounterids from a file.

   @details
  
   @par Program inputs
	- &DATAFILE. (Dataset to delete encounterids from.)
	- &ENCIDSFILE. (Dataset containing the list of encounterids to delete.)

   @par Program outputs
	- &OUTFILE. (Dataset containing record excluding encounterids to delete.)

* **Usage**

	  %ms_delencounterids(DATAFILE=worktemp._procextract,
                      	  ENCIDSFILE=&ENCIDSTOEXCLUDE.,
                      	  OUTFILE=worktemp._procextract);
    
   @param [in] DATAFILE	Name of the dataset to delete encounterids from.
   @param [in] ENCIDSFILE Name of the dataset containing the list of encounterids to delete.
   @param [in] OUTFILE	Name of the output dataset containing record excluding encounterids.

<h4> SAS Macros Dependencies </h4>
   None.

   @author Sentinel Coordinating Center (info@sentinelsystem.org)
**/

%MACRO ms_delencounterids(datafile=, EncIdsfile= , outfile=, patvar=patid);

%put =====> MACRO CALLED: ms_delencounterids;

    %ISDATA(dataset=&EncIdsfile.);

	%IF %EVAL(&NOBS.>=1) %THEN %DO;

    /** Add logic allowing this to be done partition by partition if multiple partitions exist */
        %if &numpartitions. gt 1 %then %do;
            data exclude;
              merge &EncIdsfile.(in=a rename=(patid = &patvar)) &partable.(in=b rename=(patid = &patvar) where=(partitionID=&p.));
              by &patvar;
                if a and b;
            run;
          %end;
            %else %do;
              data exclude;
                set &EncIdsfile.(rename=(patid = &patvar));
              run;
          %end; /* end numpartitions check */

        data &outfile.;
        if 0 then set &EncIdsfile.(keep=&patvar. encounterid);
        declare hash ht (hashexp:16,dataset:" &EncIdsfile.");
        ht.definekey("&patvar.",'encounterid');
        ht.definedone();

        do until(eof1);
          set &datafile.  end=eof1;      
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

    %put NOTE: ********END OF MACRO: ms_delencounterids ********;

%MEND ms_delencounterids;  