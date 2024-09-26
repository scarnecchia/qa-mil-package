%macro mergeDataset(inlib=work, indsn_root=);

   data &inlib..&indsn_root.;
      set %do p = 1 %to &numpartitions.;
              &inlib..&indsn_root.&p
         %end;;
   run;

   %do p = 1 %to &numpartitions.
      proc datasets lib=&inlib. mt=data nolist nodetails nowarn;
        delete &indsn_root.&p;
      run;
    %end;

%mend;