alter table core.report_definitions
  drop constraint report_definitions_row_limit_check;

alter table core.report_definitions
  add constraint report_definitions_row_limit_check
  check (row_limit between 1 and 200) not valid;

alter table core.report_definitions
  validate constraint report_definitions_row_limit_check;
