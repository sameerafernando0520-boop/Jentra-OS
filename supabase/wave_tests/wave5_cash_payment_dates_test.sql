-- Actual W4 candidate schemas + W4 synthetic fixture precede this strict rollback.
-- Injected actors exercise policy only: no real MFA/session/installation claim.
create extension if not exists pgtap with schema extensions;
set local search_path=extensions,public,pg_catalog;
select no_plan();
insert into billing.plan_entitlements(plan_code,entitlement_code,enabled)
 select 'w4_integrated_rollback',x,true from unnest(array['analytics','module.projects','module.finance']) x;
insert into core.role_permissions(tenant_id,role_id,permission_code)
 select pg_temp.wid('tenant'),pg_temp.wid(actor||'.role'),p.code from unnest(array['creator','reviewer']) actor cross join core.permissions p
 where p.code in('analytics.view','analytics.cash_dates.prepare','analytics.cash_dates.approve','finance.view','finance.receivables.view','finance.payments.manage','finance.reports.export') or p.module='projects' on conflict do nothing;
select pg_temp.wactor('creator');
insert into finance.accounts(id,tenant_id,legal_entity_id,code,name,account_type,normal_balance,created_by,updated_by)
 select pg_temp.wid('date.'||x),pg_temp.wid('tenant'),pg_temp.wid('entity'),'DATE-'||upper(x),'Synthetic '||x,
 case x when 'bank' then 'asset' when 'expense' then 'expense' else 'liability' end,
 case x when 'control' then 'credit' else 'debit' end,auth.uid(),auth.uid() from unnest(array['bank','expense','control']) x;
insert into finance.cash_bank_accounts(id,tenant_id,legal_entity_id,branch_id,code,name,account_kind,account_id,currency_code,created_by,updated_by,updated_at)
 values(pg_temp.wid('date.bank'),pg_temp.wid('tenant'),pg_temp.wid('entity'),pg_temp.wid('branch'),'DATE-BANK','Synthetic recorded bank','bank',pg_temp.wid('date.bank'),'LKR',auth.uid(),auth.uid(),current_date-20);
insert into finance.fiscal_periods(id,tenant_id,legal_entity_id,name,start_date,end_date,created_by,updated_by)
 values(pg_temp.wid('date.period'),pg_temp.wid('tenant'),pg_temp.wid('entity'),'Synthetic cash dates',current_date-30,current_date+30,auth.uid(),auth.uid());
create function pg_temp.date_journal(k text,d date) returns uuid language plpgsql as $$declare i uuid:=pg_temp.wid('date.j.'||k);begin
 insert into finance.journal_entries(id,tenant_id,legal_entity_id,branch_id,fiscal_period_id,document_number,posting_date,source_type,source_id,currency_code,base_currency_code,exchange_rate,request_id,command_id,correlation_id,created_by)
 values(i,pg_temp.wid('tenant'),pg_temp.wid('entity'),pg_temp.wid('branch'),pg_temp.wid('date.period'),'SYN-DATE-'||k,d,'synthetic_dates',i,'LKR','LKR',1,i,i,i,auth.uid());
 insert into finance.journal_lines(tenant_id,legal_entity_id,branch_id,journal_entry_id,line_number,account_id,currency_code,transaction_debit,transaction_credit,base_debit,base_credit,posting_date,created_by)
 select pg_temp.wid('tenant'),pg_temp.wid('entity'),pg_temp.wid('branch'),i,n,pg_temp.wid('date.'||case n when 1 then 'expense' else 'control' end),'LKR',
  case n when 1 then 1 else 0 end,case n when 2 then 1 else 0 end,case n when 1 then 1 else 0 end,case n when 2 then 1 else 0 end,d,auth.uid() from generate_series(1,2) n;
 update finance.journal_entries set status='posted' where id=i;return i;end $$;
select pg_temp.date_journal('issue',current_date-4);
select pg_temp.date_journal('settle',current_date-2);
select pg_temp.date_journal('reverse',current_date+1);
insert into people_payroll.settings_versions values(pg_temp.wid('date.settings'),pg_temp.wid('tenant'),pg_temp.wid('entity'),1,pg_temp.wid('date.control'),'Synthetic settings',auth.uid(),clock_timestamp());
insert into people_payroll.runs(id,tenant_id,legal_entity_id,branch_id,name,start_date,end_date_exclusive,posting_date,currency_code,status,approved_digest,approved_by,posted_journal_id,created_by)
 values(pg_temp.wid('date.run'),pg_temp.wid('tenant'),pg_temp.wid('entity'),pg_temp.wid('branch'),'Synthetic issued payroll',current_date-10,current_date-4,current_date-4,'LKR','posted',repeat('a',64),pg_temp.wid('reviewer'),pg_temp.wid('date.j.issue'),auth.uid());
insert into people_payroll.run_employees values(pg_temp.wid('tenant'),pg_temp.wid('entity'),pg_temp.wid('branch'),pg_temp.wid('date.run'),pg_temp.wid('employee'));
insert into people_payroll.run_revisions(id,tenant_id,legal_entity_id,run_id,version,settings_version_id,digest,employee_count,prepared_by)
 values(pg_temp.wid('date.revision'),pg_temp.wid('tenant'),pg_temp.wid('entity'),pg_temp.wid('date.run'),1,pg_temp.wid('date.settings'),repeat('a',64),1,auth.uid());
update people_payroll.runs set current_revision_id=pg_temp.wid('date.revision'),approved_revision_id=pg_temp.wid('date.revision') where id=pg_temp.wid('date.run');
insert into people_payroll.employee_calculations(id,tenant_id,legal_entity_id,run_id,revision_id,employee_id,inputs,input_digest,calculation,gross,deductions,employer_cost,net)
 values(pg_temp.wid('date.calc'),pg_temp.wid('tenant'),pg_temp.wid('entity'),pg_temp.wid('date.run'),pg_temp.wid('date.revision'),pg_temp.wid('employee'),'{}',repeat('a',64),'{}',10.000001,0,0,10.000001);
insert into people_payroll.obligations(id,tenant_id,legal_entity_id,branch_id,run_id,employee_id,calculation_id,kind,account_id,currency_code,amount)
 values(pg_temp.wid('date.payroll'),pg_temp.wid('tenant'),pg_temp.wid('entity'),pg_temp.wid('branch'),pg_temp.wid('date.run'),pg_temp.wid('employee'),pg_temp.wid('date.calc'),'net',pg_temp.wid('date.control'),'LKR',10.000001);
insert into people_payroll.obligation_effects(tenant_id,legal_entity_id,obligation_id,kind,amount,source_id,recorded_by,recorded_at)
 values(pg_temp.wid('tenant'),pg_temp.wid('entity'),pg_temp.wid('date.payroll'),'issue',10.000001,pg_temp.wid('date.run'),auth.uid(),statement_timestamp());
insert into people_payroll.settlements(id,tenant_id,legal_entity_id,branch_id,run_id,posting_date,bank_id,bank_account_id,currency_code,bank_version,evidence_reference,reason,status,journal_id,reversal_journal_id,recorded_by)
 values(pg_temp.wid('date.pay.settle'),pg_temp.wid('tenant'),pg_temp.wid('entity'),pg_temp.wid('branch'),pg_temp.wid('date.run'),current_date-2,pg_temp.wid('date.bank'),pg_temp.wid('date.bank'),'LKR',1,'SYN-DATE-PAY','Synthetic partial and future reversal','reversed',pg_temp.wid('date.j.settle'),pg_temp.wid('date.j.reverse'),auth.uid());
insert into people_payroll.settlement_allocations values(pg_temp.wid('tenant'),pg_temp.wid('entity'),pg_temp.wid('date.pay.settle'),pg_temp.wid('date.payroll'),3.000000);
insert into people_payroll.obligation_effects(id,tenant_id,legal_entity_id,obligation_id,kind,amount,source_id,recorded_by,recorded_at)
 values(pg_temp.wid('date.pay.effect'),pg_temp.wid('tenant'),pg_temp.wid('entity'),pg_temp.wid('date.payroll'),'settle',-3,pg_temp.wid('date.pay.settle'),auth.uid(),statement_timestamp());
insert into people_payroll.obligation_effects(tenant_id,legal_entity_id,obligation_id,kind,amount,source_id,reversal_of,recorded_by)
 values(pg_temp.wid('tenant'),pg_temp.wid('entity'),pg_temp.wid('date.payroll'),'settlement_reverse',3,pg_temp.wid('date.pay.settle'),pg_temp.wid('date.pay.effect'),auth.uid());
insert into people_payroll.corrections(id,tenant_id,legal_entity_id,branch_id,original_calculation_id,employee_id,original_run_id,chain_version,posting_date,currency_code,status,digest,before_calculation,after_calculation,difference,prepared_by,approved_by,approved_digest,posted_journal_id,reason)
 values(pg_temp.wid('date.correction'),pg_temp.wid('tenant'),pg_temp.wid('entity'),pg_temp.wid('branch'),pg_temp.wid('date.calc'),pg_temp.wid('employee'),pg_temp.wid('date.run'),0,current_date-4,'LKR','posted',repeat('b',64),'{}','{}','{}',auth.uid(),pg_temp.wid('reviewer'),repeat('b',64),pg_temp.wid('date.j.issue'),'Synthetic recovery');
insert into people_payroll.correction_balances(id,tenant_id,legal_entity_id,branch_id,correction_id,employee_id,kind,account_id,currency_code,amount)
 values(pg_temp.wid('date.recovery'),pg_temp.wid('tenant'),pg_temp.wid('entity'),pg_temp.wid('branch'),pg_temp.wid('date.correction'),pg_temp.wid('employee'),'net',pg_temp.wid('date.control'),'LKR',-2.000002);
insert into people_payroll.correction_balance_effects(tenant_id,legal_entity_id,balance_id,kind,amount,source_id,recorded_by,recorded_at)
 values(pg_temp.wid('tenant'),pg_temp.wid('entity'),pg_temp.wid('date.recovery'),'issue',-2.000002,pg_temp.wid('date.correction'),auth.uid(),statement_timestamp());
insert into projects.register(id,tenant_id,legal_entity_id,branch_id,code,name,manager_id,currency_code,precision,start_date,end_date_exclusive,created_by)
 values(pg_temp.wid('date.project'),pg_temp.wid('tenant'),pg_temp.wid('entity'),pg_temp.wid('branch'),'DATE-PROJECT','Synthetic reimbursements',pg_temp.wid('manager'),'LKR',6,current_date-10,current_date+10,auth.uid());
insert into projects.expenses(id,tenant_id,legal_entity_id,branch_id,project_id,employee_id,current_revision_id,status,external_reference,created_by)
 values(pg_temp.wid('date.expense'),pg_temp.wid('tenant'),pg_temp.wid('entity'),pg_temp.wid('branch'),pg_temp.wid('date.project'),pg_temp.wid('employee'),pg_temp.wid('date.expense.revision'),'posted','SYN-DATE-EXPENSE',auth.uid());
insert into projects.expense_revisions(id,tenant_id,legal_entity_id,project_id,expense_id,version,service_date,purpose,evidence_reference,original_currency,base_currency,original_precision,base_precision,net,tax,gross,base_net,base_tax,base_gross,tax_rounding_residue,tax_basis,no_tax_reason,fx_numerator,fx_denominator,fx_basis,expense_account_id,liability_account_id,bill_amount,billable,digest,reason,recorded_by)
 values(pg_temp.wid('date.expense.revision'),pg_temp.wid('tenant'),pg_temp.wid('entity'),pg_temp.wid('date.project'),pg_temp.wid('date.expense'),1,current_date-4,'Synthetic','PRIVATE RECEIPT','LKR','LKR',6,6,4,0,4,4,0,4,0,'{}','Synthetic',1,1,'{}',pg_temp.wid('date.expense'),pg_temp.wid('date.control'),0,false,repeat('c',64),'Synthetic',auth.uid());
insert into projects.expense_ownership values(pg_temp.wid('date.expense'),pg_temp.wid('tenant'),pg_temp.wid('entity'),pg_temp.wid('date.expense.revision'),'reimbursement',auth.uid(),clock_timestamp());
insert into projects.expense_decisions(tenant_id,legal_entity_id,expense_id,revision_id,decision,digest,reason,actor_id)
 values(pg_temp.wid('tenant'),pg_temp.wid('entity'),pg_temp.wid('date.expense'),pg_temp.wid('date.expense.revision'),'approved',repeat('c',64),'Synthetic',pg_temp.wid('reviewer'));
insert into projects.reimbursements(id,tenant_id,legal_entity_id,branch_id,project_id,expense_id,revision_id,currency_code,amount,account_id,posting_date,journal_id,recorded_by,recorded_at)
 values(pg_temp.wid('date.reimbursement'),pg_temp.wid('tenant'),pg_temp.wid('entity'),pg_temp.wid('branch'),pg_temp.wid('date.project'),pg_temp.wid('date.expense'),pg_temp.wid('date.expense.revision'),'LKR',4,pg_temp.wid('date.control'),current_date-4,pg_temp.wid('date.j.issue'),auth.uid(),statement_timestamp());
insert into projects.reimbursement_effects(tenant_id,legal_entity_id,obligation_id,kind,amount,source_id,journal_id,posting_date,recorded_by,recorded_at)
 values(pg_temp.wid('tenant'),pg_temp.wid('entity'),pg_temp.wid('date.reimbursement'),'issue',4,pg_temp.wid('date.expense'),pg_temp.wid('date.j.issue'),current_date-4,auth.uid(),statement_timestamp());

create function pg_temp.date_cmd(act text,payload jsonb,key text) returns jsonb language sql as $$
 select api.wave5_cash_date_command(pg_temp.wid('tenant'),pg_temp.wid('entity'),pg_temp.wid('branch'),pg_temp.wid('date.cmd.'||key),pg_temp.wid('date.cmd.'||key),statement_timestamp(),act,payload)$$;
create function pg_temp.date_prepare(k text,src text,key text,v text default '1',day date default current_date+2) returns jsonb language sql as $$
 select pg_temp.date_cmd('prepare',jsonb_build_object('id',pg_temp.wid('date.proposal.'||key)::text,'sourceKind',k,'sourceId',pg_temp.wid(src)::text,
  'sourceHash',x->>'sourceHash','dueDate',day::text,'reasonCode',case k when 'payroll_correction' then 'correction_recovery' else 'payment_terms' end,'expectedVersion',v),key)
 from jsonb_array_elements(api.wave5_cash_date_sources(pg_temp.wid('tenant'),pg_temp.wid('entity'),pg_temp.wid('branch'),k)->'rows') x where x->>'sourceId'=pg_temp.wid(src)::text$$;
create function pg_temp.date_decide(key text,act text default 'approve') returns jsonb language sql as $$
 select pg_temp.date_cmd(act,jsonb_build_object('id',pg_temp.wid('date.proposal.'||key)::text,'proposalHash',
  api.wave5_cash_date_get(pg_temp.wid('tenant'),pg_temp.wid('entity'),pg_temp.wid('branch'),pg_temp.wid('date.proposal.'||key))->>'proposalHash'),key||'.'||act)$$;

select is((select x->>'remainingAmount' from analytics.cash_source_rows(pg_temp.wid('tenant'),pg_temp.wid('entity'),pg_temp.wid('branch'),'payroll_obligation',current_date,clock_timestamp()) x),'7.000001','future settlement reversal does not rewrite opening residual');
select is((select x->>'remainingAmount' from analytics.cash_source_rows(pg_temp.wid('tenant'),pg_temp.wid('entity'),pg_temp.wid('branch'),'payroll_obligation',current_date+2,clock_timestamp()) x),'10.000001','reversal restores residual only at its effective journal date');
select is((select x->>'inflow' from analytics.cash_source_rows(pg_temp.wid('tenant'),pg_temp.wid('entity'),pg_temp.wid('branch'),'payroll_correction',current_date,clock_timestamp()) x),'true','negative correction is an explicit recovery inflow');
select is((select count(*)::integer from pg_class where oid in('analytics.cash_date_proposals'::regclass,'analytics.cash_date_decisions'::regclass) and relrowsecurity and relforcerowsecurity),2,'both date stores force RLS');
select ok(not has_table_privilege('authenticated','analytics.cash_date_proposals','select'),'date bodies never enter generic client reads');
select ok(not has_function_privilege('authenticated','analytics.cash_source_rows(uuid,uuid,uuid,text,date,timestamptz)','execute'),'private source adapter is not client callable');

create temporary table dates_basis(name text primary key,data jsonb);
insert into dates_basis values('undated',(api.wave5_cash_basis(pg_temp.wid('tenant'),pg_temp.wid('entity'),pg_temp.wid('branch'),current_date,current_date+5,statement_timestamp())->>'canonicalText')::jsonb);
select is((select data#>>'{providerStatus,payroll}' from dates_basis where name='undated'),'missing_payment_date','one undated obligation makes whole payroll family incomplete');
select is((select data#>>'{providerStatus,project_reimbursements}' from dates_basis where name='undated'),'missing_payment_date','project posting dates never masquerade as payment dates');
select throws_ok($$select api.wave5_cash_save(pg_temp.wid('tenant'),pg_temp.wid('entity'),pg_temp.wid('branch'),pg_temp.wid('date.unavailable.scenario'),repeat('a',64),jsonb_build_object('horizonStart',current_date,'horizonEnd',current_date+5,'recordedThrough',analytics.process_utc(statement_timestamp()),'overrides','{}'::jsonb))$$,'55000','CASH_COMPLETE_PROVIDERS_REQUIRED','incomplete v3 scenario cannot freeze');

-- Historical approved states inserted immutably at their original captured times.
-- Actual command approval/replay policy is tested independently below.
insert into analytics.cash_date_proposals(id,tenant_id,legal_entity_id,branch_id,source_kind,source_id,source_hash,expected_version,due_date,reason_code,proposal_hash,prepared_by,prepared_at)
 select pg_temp.wid('date.history.'||k),pg_temp.wid('tenant'),pg_temp.wid('entity'),pg_temp.wid('branch'),k,(x->>'sourceId')::uuid,x->>'sourceHash',0,current_date+2,'payment_terms',repeat('d',64),pg_temp.wid('creator'),statement_timestamp()-interval '1 day'
 from unnest(array['payroll_obligation','payroll_correction','project_reimbursement']) k cross join lateral analytics.cash_source_rows(pg_temp.wid('tenant'),pg_temp.wid('entity'),pg_temp.wid('branch'),k,current_date,statement_timestamp()) x;
insert into analytics.cash_date_decisions(id,tenant_id,legal_entity_id,branch_id,proposal_id,source_kind,source_id,decision,approved_version,actor_id,recorded_at)
 select pg_temp.wid('date.history.decision.'||source_kind),tenant_id,legal_entity_id,branch_id,id,source_kind,source_id,'approved',1,pg_temp.wid('reviewer'),statement_timestamp()-interval '1 hour' from analytics.cash_date_proposals;
insert into dates_basis values('complete',(api.wave5_cash_basis(pg_temp.wid('tenant'),pg_temp.wid('entity'),pg_temp.wid('branch'),current_date,current_date+5,statement_timestamp())->>'canonicalText')::jsonb);
select is((select jsonb_array_length(data->'completeProviders') from dates_basis where name='complete'),5,'all five actual source providers complete after reviewed dates');
select is((select x->>'amount' from dates_basis,jsonb_array_elements(data->'obligations') x where name='complete' and x->>'provider'='payroll' and x->>'inflow'='false'),'7.000001','cash basis uses exact residual after partial payroll settlement');
select is((select x->>'amount' from dates_basis,jsonb_array_elements(data->'obligations') x where name='complete' and x->>'provider'='payroll' and x->>'inflow'='true'),'2.000002','cash basis includes signed recovery magnitude');
select is((select x->>'amount' from dates_basis,jsonb_array_elements(data->'obligations') x where name='complete' and x->>'provider'='project_reimbursements'),'4.000000','cash basis includes original project reimbursement');
select ok((select data::text not like '%PRIVATE RECEIPT%' and data::text not like '%employee_id%' from dates_basis where name='complete'),'cash manifest excludes employee and receipt bodies');
select api.wave5_cash_save(pg_temp.wid('tenant'),pg_temp.wid('entity'),pg_temp.wid('branch'),pg_temp.wid('date.scenario'),
 encode(extensions.digest((select data::text from dates_basis where name='complete'),'sha256'),'hex'),
 jsonb_build_object('horizonStart',current_date,'horizonEnd',current_date+5,'recordedThrough',analytics.process_utc(statement_timestamp()),'overrides','{}'::jsonb));
select is((finance.report_export_document(pg_temp.wid('tenant'),pg_temp.wid('entity'),pg_temp.wid('branch'),'w5_cash',pg_temp.wid('date.scenario'),'buckets','{}')->'rows'->4->>'balance')::numeric,-8.999999::numeric,'governed export includes payroll recovery and reimbursement with exact parity');
select is(finance.report_export_document(pg_temp.wid('tenant'),pg_temp.wid('entity'),pg_temp.wid('branch'),'w5_cash',pg_temp.wid('date.scenario'),'buckets','{}')#>>'{metadata,calculation}','dated_transaction_cash_all_obligations.v3','export attributes actual provider calculation revision');

-- Commands run as actual authenticated DB role with injected synthetic policy actors.
set local role authenticated;
select pg_temp.date_prepare('payroll_obligation','date.payroll','pay');
select throws_ok($$select pg_temp.date_prepare('payroll_obligation','date.payroll','too-early','1',current_date-5)$$,'22023','CASH_DATE_COMMAND_INVALID','payment date cannot precede original recognition');
select throws_ok($$select pg_temp.date_cmd('prepare',jsonb_build_object('id',pg_temp.wid('date.bad.hash')::text,'sourceKind','payroll_obligation','sourceId',pg_temp.wid('date.payroll')::text,'sourceHash',repeat('e',64),'dueDate',(current_date+2)::text,'reasonCode','payment_terms','expectedVersion','1'),'wrong-source')$$,'PT409','CASH_DATE_SOURCE_CHANGED','source fingerprint is rechecked at preparation');
select throws_ok($$select pg_temp.date_decide('pay')$$,'42501','CASH_DATE_INDEPENDENT_APPROVER_REQUIRED','proposer cannot approve its own date');
select pg_temp.wactor('creator','aal1');
select throws_ok($$select pg_temp.date_prepare('payroll_obligation','date.payroll','pay')$$,'42501',null,'MFA checked before command replay');
select pg_temp.wactor('reviewer');
select throws_ok($$select pg_temp.date_cmd('approve',jsonb_build_object('id',pg_temp.wid('date.proposal.pay')::text,'proposalHash',repeat('e',64)),'wrong-proposal')$$,'PT409','CASH_DATE_PROPOSAL_CHANGED','approver must bind exact prepared digest');
select pg_temp.date_decide('pay');
select is(pg_temp.date_decide('pay')->'entity'->>'version','2','uncertain approval retry returns original approved version');
select pg_temp.wactor('creator');
select pg_temp.date_prepare('payroll_correction','date.recovery','recovery');
select pg_temp.date_prepare('project_reimbursement','date.reimbursement','project');
select pg_temp.date_prepare('payroll_obligation','date.payroll','revision-a','2',current_date+3);
select pg_temp.date_prepare('payroll_obligation','date.payroll','revision-b','2',current_date+4);
select pg_temp.wactor('reviewer');
select pg_temp.date_decide('recovery');select pg_temp.date_decide('project');
select pg_temp.date_decide('revision-a');
select throws_ok($$select pg_temp.date_decide('revision-b')$$,'PT409','CASH_DATE_VERSION_CONFLICT','stale concurrent proposal cannot overwrite winning date');
select pg_temp.wactor('outsider');
select throws_ok($$select api.wave5_cash_date_get(pg_temp.wid('tenant'),pg_temp.wid('entity'),pg_temp.wid('branch'),pg_temp.wid('date.proposal.pay'))$$,'42501',null,'foreign member cannot read proposal');
reset role;select pg_temp.wactor('creator');
delete from core.role_permissions where role_id=pg_temp.wid('creator.role') and permission_code='people.payroll.view';
select throws_ok($$select api.wave5_cash_get(pg_temp.wid('tenant'),pg_temp.wid('entity'),pg_temp.wid('branch'),pg_temp.wid('date.scenario'))$$,'42501',null,'payroll view revocation blocks frozen amount reopen');
select throws_ok($$select finance.report_export_document(pg_temp.wid('tenant'),pg_temp.wid('entity'),pg_temp.wid('branch'),'w5_cash',pg_temp.wid('date.scenario'),'buckets','{}')$$,'42501',null,'source revocation blocks governed export recreation');
insert into core.role_permissions values(pg_temp.wid('tenant'),pg_temp.wid('creator.role'),'people.payroll.view');
delete from core.role_permissions where role_id=pg_temp.wid('creator.role') and permission_code='projects.cost.view';
select throws_ok($$select api.wave5_cash_get(pg_temp.wid('tenant'),pg_temp.wid('entity'),pg_temp.wid('branch'),pg_temp.wid('date.scenario'))$$,'42501',null,'project cost revocation blocks frozen reimbursement reopen');
insert into core.role_permissions values(pg_temp.wid('tenant'),pg_temp.wid('creator.role'),'projects.cost.view');
select pg_temp.wactor('creator','aal1');
select throws_ok($$select api.wave5_cash_get(pg_temp.wid('tenant'),pg_temp.wid('entity'),pg_temp.wid('branch'),pg_temp.wid('date.scenario'))$$,'42501',null,'MFA checked again on frozen cash reopen');
select pg_temp.wactor('creator');
select pg_temp.date_prepare('payroll_obligation','date.payroll','rejected','3',current_date+4);
select pg_temp.wactor('reviewer');select pg_temp.date_decide('rejected','reject');
select is(analytics.cash_date_current(pg_temp.wid('tenant'),pg_temp.wid('entity'),'payroll_obligation',pg_temp.wid('date.payroll'),clock_timestamp())->>'version','3','rejected reschedule retains prior approved date');
select pg_temp.wactor('creator');
select throws_ok($$update analytics.cash_date_proposals set due_date=current_date where id=pg_temp.wid('date.proposal.pay')$$,'55000',null,'authoritative proposal cannot be edited');
select throws_ok($$delete from analytics.cash_date_decisions where proposal_id=pg_temp.wid('date.proposal.pay')$$,'55000',null,'approval cannot be deleted');
select is(analytics.cash_date_current(pg_temp.wid('tenant'),pg_temp.wid('entity'),'payroll_obligation',pg_temp.wid('date.payroll'),clock_timestamp())->>'version','3','winning approved version is monotonic');
select is(analytics.cash_date_current(pg_temp.wid('tenant'),pg_temp.wid('entity'),'payroll_obligation',pg_temp.wid('date.payroll'),(select d.recorded_at from analytics.cash_date_decisions d where proposal_id=pg_temp.wid('date.proposal.pay')))->>'version','2','historical approval cutoff retains original date');
select ok(not exists(select 1 from core.command_receipts where command_name like 'analytics.cash_dates.%' and response::text ~ 'dueDate|remainingAmount|PRIVATE RECEIPT|employee_id'),'generic receipts exclude private dates, amounts and HR evidence');
-- An uninstalled family is independently unavailable, even if no rows exist.
alter table people_payroll.correction_balances rename to rollback_only_hidden_correction_balances;
select is(((api.wave5_cash_basis(pg_temp.wid('tenant'),pg_temp.wid('entity'),pg_temp.wid('branch'),current_date,current_date+5,statement_timestamp())->>'canonicalText')::jsonb)#>>'{providerStatus,payroll}','source_not_installed','missing correction provider cannot be called complete payroll');
alter table people_payroll.rollback_only_hidden_correction_balances rename to correction_balances;
set constraints all immediate;
select * from finish(true);
