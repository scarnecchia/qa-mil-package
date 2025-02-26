/**
@file       _bridgeEnrollment.sas

@brief      Macro for bridging enrollment spans by coverage type

@details    Creates master enrollment dataset with bridged spans,
            and med and drug indicator (MDCov), and an indicator for
            enrollment on calendar date of interest (snapshot)

@author     qa_development@sentinel.org

@par Program inputs
    - dplocal.temp_enr_&cov. Dataset containing an subset of enrollment data by coverage type.

@par Program outputs
    - dplocal.enr_final_&cov. Dataset containing a list of PatIDs by coverage type, with enrollments bridged per SCDM rules.
    - dplocal.enr_patid_&cov. A list of unique PatIDs derived from dplocal.enr_final_&cov.

**/

%macro bridgeEnrollment;

  %do p = 1 %to &numpartitions.;

    /**
        dth_dthct_m and cod_codct_m are the only two datasets which use a medical coverage only dataset. Both are optional
        and COD cannot be present without the DTH table. Testing for the DTH table will let us avoid creating all three
        subsets when not necessary
    */
    %if &deathtable. ne %str( ) %then %do;
        %let covtypes = m|md|d;
    %end;
    %else %do;
        %let covtypes = md|d;
    %end;

    %do j = 1 %to %sysfunc(countw(&covtypes.,"|"));

        %let cov = %scan(&covtypes.,&j.,"|");

        %* retain only variables required to bridge enrollment and remove duplicates to prepare for this processing;
        proc sort data = dplocal.temp_enr_&cov.&p. (keep = patid enr_start enr_end)
                      out = _deduped_enr_&cov.&p. NODUPKEY;
                by patid enr_start enr_end;
        run;

        data _temp_enr_&cov.&p.(keep =  patid enr_start enr_end span_period);
            set _deduped_enr_&cov.&p.;
            format lag_end mmddyy10.;
            by patid;
            lag_end=lag(enr_end);
            if first.patid then do;
                span_period=1;
            end;
            /* Identify SCDM compliant (disjointed) records by patid by assigning a unique enrollment period ID */
            else do;
                if enr_start gt (lag_end+46) then span_period + 1;
            end;
        run;

        /* combine enr_periods within span_period */
        proc sql noprint;
            create table dplocal.enr_final_&cov.&p. as
                select patid
                     , min(enr_start) as _enr_start format=mmddyy10.
                     , max(enr_end) as _enr_end     format=mmddyy10.
                 from _temp_enr_&cov.&p.
                 group by patid,span_period;

        quit;

        proc sort data=dplocal.enr_final_&cov.&p. (keep=patid) out=dplocal.enr_patid_&cov.&p. nodupkey;
          by PatID;
        run;

        proc datasets library = work nolist nowarn;
            delete _deduped_enr_&cov.&p. _temp_enr_&cov.&p.;
        quit;

        %end; %* end j loop;
  %end; %* end p loop;
%mend bridgeEnrollment;