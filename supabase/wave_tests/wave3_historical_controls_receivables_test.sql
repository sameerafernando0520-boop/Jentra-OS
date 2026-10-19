-- The source suite remaps AR and retains the original posted open items.
insert into final_stack_results select is((select count(distinct account_id) from finance.control_account_basis
 where tenant_id=pg_temp.fid('tenant') and legal_entity_id=pg_temp.fid('entity') and kind='AR'),
 2::bigint,'retired and current AR accounts remain in the append-only mapping basis');
insert into final_stack_results select is((finance.build_control_report(pg_temp.fid('tenant'),pg_temp.fid('entity'),pg_temp.fid('branch'),
 jsonb_build_object('id',pg_temp.fid('control.history.report'),'kind','AR',
 'as_of',(statement_timestamp() at time zone 'UTC')::date))#>>'{summary,basis_coverage,registry_accounts}')::bigint,
 2::bigint,'dated AR reconciliation discloses both mapped account identities');
insert into final_stack_results select ok(exists(select 1 from finance.control_account_basis where tenant_id=pg_temp.fid('tenant')
 and legal_entity_id=pg_temp.fid('entity') and kind='AR' and account_id=pg_temp.fid('receivable_control')
 and source_type='future_mapping_old'),
 'remapping appends the old AR account before the new mapping replaces it');
