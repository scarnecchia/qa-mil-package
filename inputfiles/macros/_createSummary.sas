/**
 * Macro: create_summary_ct
 * Description: This macro creates a summary table based on the specified input dataset and variables.
 *
 * Parameters:
 *   - indsn: The name of the input dataset.
 *   - outdsn: The name of the output dataset to be created.
 *   - var: The variable to be summarized.
 *   - varlabel: The label for the variable in the output dataset.
 *   - ctlabel: The label for the count variable in the output dataset.
 *   - fromCnd: Additional conditions to be applied to the input dataset.
 *   - group: The grouping variables for the summary.
 *   - order: The order of the summary table.
 *
 * Example Usage:
 *   %create_summary_ct(indsn=mydata, outdsn=summary, var=age, varlabel=Age, ctlabel=Count, fromCnd=where gender='M', group=gender, order=descending);
 */
%macro create_summary_ct(indsn=, outdsn=, var=, varlabel=, ctlabel=, fromCnd=, group=, order=);

  proc sql noprint;
    create table msoc.&outdsn. as
    select upcase("&dp.") as DP length=6
      , &var. label=&varlabel.
      , count(*) as Count label=&ctlabel. format=comma12.
      from &indsn. &fromCnd.
      &group.
      &order.
      ;
  quit;

%mend;