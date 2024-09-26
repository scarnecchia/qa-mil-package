/**
@file    compile_macros.sas

@brief   Macro for compiling macros

@details  This macro searches the current directory in which it is saved and
          compiles a list of all macro program with an underscore ('_') prefix
          (i.e. _utility). The macros are then compiled by a %include statement.
@param   n/a

@author  qa_development@sentinel.org

@version v1.0.0

**/

%macro compile_macros;

  filename _dir_ "%bquote(&infolder.macros/)";

  data list_mname (keep= inc_macro);
    length inc_macro $250;
    handle=dopen( '_dir_' );
    if handle > 0 then do;
      count=dnum(handle);
      do i=1 to count;
        mname = dread(handle,i);
        if substr(mname,1,1) = '_' and scan(mname,-1,'.') = 'sas' then do;
          inc_macro= catt('%include "&infolder.macros/',mname,'";');
          call execute(inc_macro);
        end;
      end;
    end;
    call symputx('mcount',count);
    rc=dclose(handle);
  run;

  filename _dir_ clear;

  proc datasets nolist nowarn lib=work;
    delete list_mname;
  quit;


%mend;