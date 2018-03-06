/*-------------------------------------------------------------------------------------*\
|  PROGRAM NAME:                                                                        |
|     02.1_mscdm_data_qa_review-enrollment.sas                                          |
|                                                                                       |
|  QA PACKAGE VERSION: 4.0.3                                                            |
|---------------------------------------------------------------------------------------|
|  PURPOSE:                                                                             |
|     The purpose of this program is to perform data quality checks on the Enrollment   |
|     table.                                                                            |
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

%table_name (n=);
%timestamp(&tabid._start);

/*-------------------------------------------------------------------------------------*/
/*  START Level 2                                                                      */
/*-------------------------------------------------------------------------------------*/
%level2;

/*-------------------------------------------------------------------------------------*/
/*  START Level 3                                                                      */
/*-------------------------------------------------------------------------------------*/
%let level=3;

proc sql noprint;
  create table dplocal.temp_enr_start as
  select *
       , count(*) as n
  from dplocal.l2_nodup_&tabid. (keep=enr_start)
  group by 1
  ;
quit;
%date_percentiles (libin=dplocal, dsin=temp_enr_start, libout=dplocal, dsout=temp_date_dist_&tabid._1, vars=enr_start);

proc sql noprint;
  drop table dplocal.temp_enr_start
  ;
  create table dplocal.temp_enr_end as
  select *
       , count(*) as n
  from dplocal.l2_nodup_&tabid. (keep=enr_end)
  group by 1
  ;
quit;
%date_percentiles (libin=dplocal, dsin=temp_enr_end, libout=dplocal, dsout=temp_date_dist_&tabid._2, vars=enr_end);
%set_ds (libin=dplocal, dsin_prefix=temp_date_dist_&tabid., libout=dplocal, dsout=date_dist_&tabid.);

/* enr_l3_cov_chart */
proc sql noprint;
  drop table dplocal.temp_enr_end;
  ;
  create table msoc.&tabid._l3_covtype_chart as
  select *
       , count(*) as count format=comma15.
  from  dplocal.l2_nodup_&tabid. (keep=medcov drugcov chart)
  group by medcov, drugcov, chart
  ;
quit;

/* enr_l3_chart_y */
proc sql noprint;
  create table msoc.enr_l3_chart_y as
  select put(enr_start,year4.) as Year 
       , chart
       , count(*) as count format=comma15.
  from dplocal.l2_nodup_enr (keep=chart enr_start)
  group by 1,2
  ;
quit;

 /*<statistics and distribution of number of enrollment months per patient (by coverage status)>
   <medcov=”y”: mean, standard deviation, and median, and distribution >
   <drugcov=”y”: mean, standard deviation, and median, and distribution>
   <medcov=”y” and drugcov=”y”: mean, standard deviation, and median, and distribution>*/

data month (drop=cntyr cntmo);
  set dplocal.l2_nodup_enr (where=(lowcase(medcov)="y" or lowcase(drugcov)="y"));
  meddrug=(lowcase(medcov)="y" and lowcase(drugcov)="y");
  med=(lowcase(medcov)="y");
  drug  =(lowcase(drugcov)="y");
  cntyr = intck('year',enr_start,enr_end);
  cntmo = intck('month',enr_start,enr_end);
  do m=0 to cntmo;
    month=put(intnx('month', enr_start,m),yymmd.);
    output month;
  end;
run;

%macro split(in,var,out);
  proc sort data=&in. nodupkey out=one_&in._&var._&out.;
    by patid &in.;
    where &var.=1;
  run;

  data one_&in._&var._&out.;
    set one_&in._&var._&out.;
    by patid;
    if first.patid then &var._ = 1;
    else &var._ +1;
  run;

  proc means data=one_&in._&var._&out. nway noprint;
    class patid;
    var &var._ ;
    output out=two_&in._&var._&out. max(&var._ )=&var._ ;
  run;

  proc freq data=two_&in._&var._&out. noprint;
    tables &var._ /list missing out=&tabid._l3_dist_enr&in._&out.;
  run;
%mend split;

%split(month,med,m);
%split(month,drug,d);
%split(month,meddrug,md);

%macro split2 (in,var,out,suff);
  proc means data=one_&in._&var._&out. nway noprint;
    class &in.;
    var &var.;
      output out=final_&tabid._l3_enr&out._&suff. (keep=&in. &var.) sum(&var.)=&var.;
    run;

%mend split2;
%split2 (month,med,m,ym);
%split2 (month,drug,d,ym);
%split2 (month,meddrug,md,ym);


data msoc.enr_l3_enrmd_ym (rename=(month=YearMonth));
  merge final_enr_l3_enrm_ym final_enr_l3_enrd_ym final_enr_l3_enrmd_ym;
  by month;
  format _numeric_ comma15.;
run;

%macro m(in,var,out);
  proc means data=two_&in._&var._&out. noprint nway;
    var &var._;
    output out=msoc.&tabid._l3_&out.cov_months_stats (drop=_type_ _freq_) 
    n=members sum=&var. mean=mean std=std min=min p1=p1 p5=p5 p25=p25 median=median p75=p75 p95=p95 p99=p99 max=max;
  run;

  proc datasets library=msoc nolist nodetails nowarn;
    modify &tabid._l3_&out.cov_months_stats;
    format members &var. comma15. mean std 10.2  median 10.1;
    informat mean std 10.2  median 10.1;
  run;
  quit;
%mend m;
%m(month,meddrug,md);



proc datasets lib=work memtype=data nolist nodetails nowarn;
  delete one: two: month;
quit;

proc sql noprint;
  create table msoc.enr_l3_covtype_duration as
  select coalesce(a.meddrug_,b.months) as Months
       , b.Count_Med label=' ' format=comma15.
       , b.Count_Drug label=' ' format=comma15.
       , a.count as Count_MedDrug label=' ' format=comma15.
  from enr_l3_dist_enrmonth_md as a full join 
    (select coalesce(m.med_,d.drug_) as Months, m.count as Count_Med, d.count as Count_Drug from enr_l3_dist_enrmonth_m as m 
     full join enr_l3_dist_enrmonth_d as d on m.med_=d.drug_) as b
  on a.meddrug_=b.months
  order by 1
  ;
quit;

%timestamp(&tabid._end);
%timereport(&&&tabid._start,&&&tabid._end);

*-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-;
*  END  01.1-mscdm-data-qa-review-enrollment.sas                                        ;
*-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-;
