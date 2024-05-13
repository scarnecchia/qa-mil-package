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
  AGE_YEARS 15-18      15 18 N N . N
  AGE_YEARS 19-21      19 21 N N . N
  AGE_YEARS 22-44      22 44 N N . N
  AGE_YEARS 45-64      45 64 N N . N
  AGE_YEARS 65-74      65 74 N N . N
  AGE_YEARS 75+        75 .  N N H N
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

proc sql;
  create table msoc.age_sort as
  select monotonic( ) as SortOrder format=z2.
       , label
  from temp_format
  ;
  drop table temp_format
  ;
quit;

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