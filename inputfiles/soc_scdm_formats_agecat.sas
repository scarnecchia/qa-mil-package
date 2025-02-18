/*-----------------------------------------------------------------------------------*\
|   PROGRAM NAME: soc_scdm_formats_agecat.sas                                         |
|-------------------------------------------------------------------------------------|
|                                                                                     |
|   PURPOSE:  The purpose of this macro program is to generate age category formats   |
|             and sort order.                                                         |
|                                                                                     |
|-------------------------------------------------------------------------------------|
|                                                                                     |
|   PROGRAM INPUT:  See master program and/or workplan                                |
|                                                                                     |
|   PROGRAM OUTPUT:  See master program and/or workplan                               |
|                                                                                     |
|-------------------------------------------------------------------------------------|
|   CONTACT:                                                                          |
|        Sentinel Coordinating Center                                                 |
|        info@sentinelsystem.org                                                      |
|                                                                                     |
\*-----------------------------------------------------------------------------------*/

*+_+_+_+_+_+_+_+_+_+_+_+_+_+_+_+_+_+_+_+_+_+_+_+_+_+_+_+_+_+_+_+_+_+_+_+_+_+_+_+_+_;
* PLEASE DO NOT EDIT BELOW WITHOUT CONTACTING THE SENTINEL OPERATIONS CENTER       ;
*+_+_+_+_+_+_+_+_+_+_+_+_+_+_+_+_+_+_+_+_+_+_+_+_+_+_+_+_+_+_+_+_+_+_+_+_+_+_+_+_+_;

data temp_format;
  infile datalines truncover expandtabs;
  input FMTNAME $3-11 LABEL $13-17 START 24-25 END 27-28 SEXCL $30 EEXCL $32 HLO $34 TYPE $36;
  datalines;
  AGE_YEARS <0         .  00 Y N L N
  AGE_YEARS 00-01      00 01 N N . N
  AGE_YEARS 02-04      02 04 N N . N
  AGE_YEARS 05-09      05 09 N N . N
  AGE_YEARS 10-14      10 14 N N . N
  AGE_YEARS 15-19      15 19 N N . N
  AGE_YEARS 20-24      20 24 N N . N
  AGE_YEARS 25-29      25 29 N N . N
  AGE_YEARS 30-34      30 34 N N . N
  AGE_YEARS 35-39      35 39 N N . N
  AGE_YEARS 40-44      40 44 N N . N
  AGE_YEARS 45-49      45 49 N N . N
  AGE_YEARS 50-54      50 54 N N . N
  AGE_YEARS 55-59      55 59 N N . N
  AGE_YEARS 60-64      60 64 N N . N
  AGE_YEARS 65-69      65 69 N N . N
  AGE_YEARS 70-74      70 74 N N . N
  AGE_YEARS 75-79      75 79 N N . N
  AGE_YEARS 80+        80 .  N N H N
;
run;

proc format cntlin=temp_format;
run;
quit;

/* format for mother age (MIL) */
data temp_mage_format;
  infile datalines truncover expandtabs;
  input FMTNAME $3-11 LABEL $13-17 START 24-25 END 27-28 SEXCL $30 EEXCL $32 HLO $34 TYPE $36;
  datalines;
  M_AGEFMT  10-19      10 19 N N . N
  M_AGEFMT  20-44      20 44 N N . N
  M_AGEFMT  45-54      45 54 N N . N
;
run;

proc format cntlin=temp_mage_format;
run;
quit;

/* format for birth_type (MIL) */
data temp_btype_format;
  infile datalines truncover expandtabs;
  input FMTNAME $3-10 LABEL $13-60 START 62 END 64 TYPE $66;
  datalines;
  B_TYPFMT  0= Unspecified number of live births             0 0 N
  B_TYPFMT  1= 1 live birth                                  1 1 N
  B_TYPFMT  2= 2 live births                                 2 2 N
  B_TYPFMT  3= 3 live births                                 3 3 N
  B_TYPFMT  4= 4 live births                                 4 4 N
  B_TYPFMT  5-8= Multiple live births, unspecified number    5 8 N
  B_TYPFMT  9= Conflicting code(s) for number of live births 9 9 N
;
run;

proc format cntlin=temp_btype_format;
run;
quit;

proc sql noprint ;
  create table msoc.age_sort as
  select monotonic( ) as SortOrder format=z2.
       , label
  from temp_format
  ;
  select max(sortorder) into: _lastsort trimmed from msoc.age_sort;
  drop table temp_format
  ;
quit;

data new_labels;
  length label $40;
  label='0-18 (Pediatric Populations I)';
  sortorder=&_lastsort+1;
  output;
  label='0-21 (Pediatric Populations II)';
  sortorder=&_lastsort+1;
  output;
  label='0-<26 (Young Adult Coverage Eligible)';
  sortorder=sortorder+1;
  output;
  label='10-54 & Sex = F (Childbearing Age)';
  sortorder=sortorder+1;
  output;
run;

data msoc.age_sort;
  length label $40;
  set msoc.age_sort new_labels;
run;
/* format for cod_pat_codct_md & cod_pat_codct_m  */

data temp_rec_ct_format;
  infile datalines truncover expandtabs;
  input FMTNAME $3-8 LABEL $10-11 START $17 END $19 SEXCL $21 EEXCL $23 HLO $25 TYPE $27;
  datalines;
  REC_CT 1      . 1 Y N L N
  REC_CT 2      2 2 N N . N
  REC_CT 3      3 3 N N . N
  REC_CT 4      4 4 N N . N
  REC_CT >4     5 . N N H N
;
run;

proc format cntlin=temp_rec_ct_format;
run;
quit;
