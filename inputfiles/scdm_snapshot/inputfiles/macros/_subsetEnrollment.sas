/*-------------------------------------------------------------------------------*/
/* Data step to subset enrollment by coverage types                              */
/*-------------------------------------------------------------------------------*/

%macro subset_enrtable(inlib=, indsn=);
  %do p = 1 %to &numpartitions.;
    data dplocal.temp_enr_m&p.
         dplocal.temp_enr_d&p.
         dplocal.temp_enr_md&p.;
        set &inlib..&indsn.&p. (drop=chart plantype payertype);
        _start_year=year(enr_start);
        _end_year=year(enr_end);

        if lowcase(medcov)='y' then
            do;
                %* create an enrollment ds with at least med coverage;
                output dplocal.temp_enr_m&p.;
                %* create an enrollment with at least med and drug coverage;
                if lowcase(drugcov)='y' then output dplocal.temp_enr_md&p.;
            end;
        %* create an enrollment with at least med and drug coverage;
        if lowcase(drugcov)='y' then output dplocal.temp_enr_d&p.;
    run;
    
  %end; /* end of partition loop */
%mend;