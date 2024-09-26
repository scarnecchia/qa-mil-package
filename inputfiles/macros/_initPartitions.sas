/**
@file       _initPartitions.sas

@detail     Checks for the existence of numpartitions. If it is not popoulated or does not exist,
            sets numpartitions equal to 1 and initializes all tables with a partition number of 1.

**/
%macro initPartitions;

  %if %symexist(numpartitions) = 0 or %str("&numpartitions.") eq %str("") %then
    %do;
      %global numpartitions;
      %let numpartitions = 1;
  %end;

  /* Since single partition tables will not need a number appended to them, we need to abstract the table name */
  %local _enrtable;
  %do p = 1 %to &numpartitions.;
    %if &numpartitions. gt 1 %then %do;
      %let _enrtable = indata.&enrtable.&p.;
    %end; /* end of numpartitions check */
    %else %let _enrtable = indata.&enrtable;

    /* import ptstoexclude if in cport format */
    %importfiles(var=&ptstoexclude.);

    %ms_delpatients(datafile=&_enrtable.,
                    ptsfile=&PTSTOEXCLUDE.,
                    Outfile=dplocal.temp_enr&p.);

  %end; /* end of partition loop */
%mend;