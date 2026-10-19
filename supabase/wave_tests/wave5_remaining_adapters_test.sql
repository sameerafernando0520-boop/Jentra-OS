-- Follows installed process fixture; all rows and candidates roll back.
select pg_temp.actor('owner');
insert into core.role_permissions values(pg_temp.fid('t'),pg_temp.fid('owner.role'),'finance.view'),
 (pg_temp.fid('t'),pg_temp.fid('owner.role'),'finance.receivables.view'),
 (pg_temp.fid('t'),pg_temp.fid('owner.role'),'finance.payments.manage') on conflict do nothing;
-- Rollback-only shape shim for the separately owned Wave 3 correction source.
-- The real table is still uninstalled in the live project and is not created by W5.
create table if not exists finance.allocation_reversals(
 id uuid primary key,tenant_id uuid not null,legal_entity_id uuid not null,branch_id uuid not null,
 allocation_id uuid not null unique,posting_date date not null,reason text not null,
 journal_entry_id uuid,source_snapshot jsonb not null,request_id uuid not null,command_id uuid not null,
 created_by uuid not null,created_at timestamptz not null default statement_timestamp());
insert into finance.accounts(id,tenant_id,legal_entity_id,code,name,account_type,normal_balance,created_by,updated_by)
 select pg_temp.fid('cash.'||x),pg_temp.fid('t'),pg_temp.fid('e'),upper(x),'Synthetic '||x,
  case x when 'cash' then 'asset' else 'revenue' end,case x when 'cash' then 'debit' else 'credit' end,auth.uid(),auth.uid()
 from unnest(array['cash','offset']) x;
insert into finance.cash_bank_accounts(id,tenant_id,legal_entity_id,branch_id,code,name,account_kind,account_id,currency_code,created_by,updated_by,updated_at)
 values(pg_temp.fid('cash.control'),pg_temp.fid('t'),pg_temp.fid('e'),pg_temp.fid('b'),'SYN-CASH','Synthetic cash','cash',pg_temp.fid('cash.cash'),'LKR',auth.uid(),auth.uid(),current_date-2);
insert into finance.fiscal_periods(id,tenant_id,legal_entity_id,name,start_date,end_date,created_by,updated_by)
 values(pg_temp.fid('cash.period'),pg_temp.fid('t'),pg_temp.fid('e'),'Synthetic cash period',current_date-30,current_date+30,auth.uid(),auth.uid());
insert into finance.journal_entries(id,tenant_id,legal_entity_id,branch_id,fiscal_period_id,document_number,posting_date,source_type,source_id,currency_code,base_currency_code,exchange_rate,request_id,command_id,correlation_id,created_by)
 values(pg_temp.fid('cash.journal'),pg_temp.fid('t'),pg_temp.fid('e'),pg_temp.fid('b'),pg_temp.fid('cash.period'),'SYN-CASH',current_date-1,'synthetic_cash_fixture',pg_temp.fid('cash.journal'),'LKR','LKR',1,
  pg_temp.fid('cash.journal'),pg_temp.fid('cash.journal'),pg_temp.fid('cash.journal'),auth.uid());
insert into finance.journal_lines(id,tenant_id,legal_entity_id,branch_id,journal_entry_id,line_number,account_id,currency_code,transaction_debit,transaction_credit,base_debit,base_credit,posting_date,created_by)
 select pg_temp.fid('cash.line.'||x),pg_temp.fid('t'),pg_temp.fid('e'),pg_temp.fid('b'),pg_temp.fid('cash.journal'),case x when 'cash' then 1 else 2 end,pg_temp.fid('cash.'||x),'LKR',
  case x when 'cash' then 100 else 0 end,case x when 'offset' then 100 else 0 end,case x when 'cash' then 100 else 0 end,case x when 'offset' then 100 else 0 end,current_date-1,auth.uid()
 from unnest(array['cash','offset']) x;
update finance.journal_entries set status='posted' where id=pg_temp.fid('cash.journal');
insert into crm.parties(id,tenant_id,code,legal_name,display_name,kind,created_by,updated_by)
 values(pg_temp.fid('cash.party'),pg_temp.fid('t'),'SYN-CASH','Synthetic cash customer','Synthetic cash customer','customer',auth.uid(),auth.uid());
insert into crm.parties(id,tenant_id,code,legal_name,display_name,kind,created_by,updated_by)
 values(pg_temp.fid('cash.supplier'),pg_temp.fid('t'),'SYN-CASH-SUP','Synthetic cash supplier','Synthetic cash supplier','supplier',auth.uid(),auth.uid());
insert into finance.open_items(id,tenant_id,legal_entity_id,branch_id,kind,party_id,source_type,source_id,document_number,currency_code,base_currency_code,exchange_rate,
 original_amount,original_base_amount,posting_date,due_date,journal_entry_id,request_id,command_id,correlation_id,created_by)
 select pg_temp.fid('cash.item.'||x),pg_temp.fid('t'),pg_temp.fid('e'),pg_temp.fid('b'),'AR',pg_temp.fid('cash.party'),'synthetic_cash_'||x,pg_temp.fid('cash.item.'||x),'SYN-'||x,'LKR','LKR',1,
  case x when 'invoice' then 500 else -200 end,case x when 'invoice' then 500 else -200 end,current_date-1,current_date+1,pg_temp.fid('cash.journal'),pg_temp.fid('cash.item.'||x),pg_temp.fid('cash.item.'||x),pg_temp.fid('cash.item.'||x),auth.uid()
 from unnest(array['invoice','receipt']) x;
insert into finance.open_items(id,tenant_id,legal_entity_id,branch_id,kind,party_id,source_type,source_id,document_number,currency_code,base_currency_code,exchange_rate,
 original_amount,original_base_amount,posting_date,due_date,journal_entry_id,request_id,command_id,correlation_id,created_by)
 select pg_temp.fid('cash.ap.'||x),pg_temp.fid('t'),pg_temp.fid('e'),pg_temp.fid('b'),'AP',pg_temp.fid('cash.supplier'),'synthetic_cash_ap_'||x,
  pg_temp.fid('cash.ap.'||x),'SYN-AP-'||x,'LKR','LKR',1,case x when 'active_bill' then 150 else 80 end,case x when 'active_bill' then 150 else 80 end,
  current_date-3,current_date+2,pg_temp.fid('cash.journal'),pg_temp.fid('cash.ap.'||x),pg_temp.fid('cash.ap.'||x),pg_temp.fid('cash.ap.'||x),auth.uid()
 from unnest(array['active_bill','reversed_bill']) x;
insert into finance.open_items(id,tenant_id,legal_entity_id,branch_id,kind,party_id,source_type,source_id,document_number,currency_code,base_currency_code,exchange_rate,
 original_amount,original_base_amount,posting_date,due_date,journal_entry_id,request_id,command_id,correlation_id,created_by)
 select pg_temp.fid('cash.ap.credit.'||x),pg_temp.fid('t'),pg_temp.fid('e'),pg_temp.fid('b'),'AP',pg_temp.fid('cash.supplier'),'synthetic_cash_ap_credit_'||x,
  pg_temp.fid('cash.ap.credit.'||x),'SYN-AP-CREDIT-'||x,'LKR','LKR',1,case x when 'active' then -40 else -20 end,case x when 'active' then -40 else -20 end,
  current_date-3,current_date+2,pg_temp.fid('cash.journal'),pg_temp.fid('cash.ap.credit.'||x),pg_temp.fid('cash.ap.credit.'||x),pg_temp.fid('cash.ap.credit.'||x),auth.uid()
 from unnest(array['active','reversed']) x;
insert into finance.open_item_allocations(tenant_id,legal_entity_id,branch_id,source_open_item_id,target_open_item_id,source_amount,transaction_amount,source_base_amount,target_base_amount,posting_date,request_id,command_id,correlation_id,created_by)
 values(pg_temp.fid('t'),pg_temp.fid('e'),pg_temp.fid('b'),pg_temp.fid('cash.item.receipt'),pg_temp.fid('cash.item.invoice'),200,200,200,200,current_date-1,pg_temp.fid('cash.allocation'),pg_temp.fid('cash.allocation'),pg_temp.fid('cash.allocation'),auth.uid());
insert into finance.open_item_allocations(id,tenant_id,legal_entity_id,branch_id,source_open_item_id,target_open_item_id,source_amount,transaction_amount,source_base_amount,target_base_amount,posting_date,request_id,command_id,correlation_id,created_by)
 values(pg_temp.fid('cash.ap.alloc.active'),pg_temp.fid('t'),pg_temp.fid('e'),pg_temp.fid('b'),pg_temp.fid('cash.ap.credit.active'),pg_temp.fid('cash.ap.active_bill'),40,40,40,40,current_date-2,
  pg_temp.fid('cash.ap.alloc.active'),pg_temp.fid('cash.ap.alloc.active'),pg_temp.fid('cash.ap.alloc.active'),auth.uid()),
 (pg_temp.fid('cash.ap.alloc.reversed'),pg_temp.fid('t'),pg_temp.fid('e'),pg_temp.fid('b'),pg_temp.fid('cash.ap.credit.reversed'),pg_temp.fid('cash.ap.reversed_bill'),20,20,20,20,current_date-2,
  pg_temp.fid('cash.ap.alloc.reversed'),pg_temp.fid('cash.ap.alloc.reversed'),pg_temp.fid('cash.ap.alloc.reversed'),auth.uid());
insert into finance.allocation_reversals(id,tenant_id,legal_entity_id,branch_id,allocation_id,posting_date,reason,source_snapshot,request_id,command_id,created_by)
 values(pg_temp.fid('cash.ap.reversal'),pg_temp.fid('t'),pg_temp.fid('e'),pg_temp.fid('b'),pg_temp.fid('cash.ap.alloc.reversed'),current_date-1,
  'Synthetic rollback reversal',jsonb_build_object('allocation_id',pg_temp.fid('cash.ap.alloc.reversed')),pg_temp.fid('cash.ap.reversal'),pg_temp.fid('cash.ap.reversal'),auth.uid());
create temporary table w5_cash as select api.wave5_cash_basis(pg_temp.fid('t'),pg_temp.fid('e'),pg_temp.fid('b'),
 current_date,current_date+30,statement_timestamp()) basis;
select is(((select basis->>'canonicalText' from w5_cash)::jsonb)->>'definition','dated_transaction_cash_ar_and_ap.v2','Cash authority names dated transaction, AR and AP basis');
select is(((select basis->>'canonicalText' from w5_cash)::jsonb)#>>'{controls,0,amount}','100.000000','Dated cash control reconciles to posted journal transactions');
select is((select x->>'amount' from w5_cash,jsonb_array_elements((basis->>'canonicalText')::jsonb->'obligations') x where x->>'id'=pg_temp.fid('cash.item.invoice')::text),
 '300.000000','AR residual subtracts one immutable allocation without counting receipt as another inflow');
select is(((select basis->>'canonicalText' from w5_cash)::jsonb)#>>'{completeProviders,2}','payables','Dated provider exposes AP only under payable read authority');
select is((select x->>'amount' from w5_cash,jsonb_array_elements((basis->>'canonicalText')::jsonb->'obligations') x where x->>'id'=pg_temp.fid('cash.ap.active_bill')::text),'110.000000','AP residual subtracts committed payment allocations');
select is((select x->>'amount' from w5_cash,jsonb_array_elements((basis->>'canonicalText')::jsonb->'obligations') x where x->>'id'=pg_temp.fid('cash.ap.reversed_bill')::text),'80.000000','Reversed AP allocation is restored to remaining obligations');
select is(((select basis->>'canonicalText' from w5_cash)::jsonb)#>>'{providerStatus,payroll}','missing_authoritative_due_date','Payroll stays unavailable without a due-date source');
select is(((select basis->>'canonicalText' from w5_cash)::jsonb)#>>'{providerStatus,project_reimbursements}','missing_authoritative_due_date','Project reimbursements stay unavailable without a due-date source');
delete from core.role_permissions where tenant_id=pg_temp.fid('t') and role_id=pg_temp.fid('owner.role') and permission_code='finance.payments.manage';
create temporary table w5_cash_without_ap as select api.wave5_cash_basis(pg_temp.fid('t'),pg_temp.fid('e'),pg_temp.fid('b'),current_date,current_date+30,statement_timestamp()) basis;
select is(((select basis->>'canonicalText' from w5_cash_without_ap)::jsonb)#>>'{providerStatus,payables}','permission_required','Payables are withheld when the current actor loses their scoped capability');
select is(jsonb_array_length((select basis->>'canonicalText' from w5_cash_without_ap)::jsonb->'obligations'),1,'Unauthorized AP rows are not returned to the receivables-only reader');
insert into core.role_permissions values(pg_temp.fid('t'),pg_temp.fid('owner.role'),'finance.payments.manage') on conflict do nothing;
select is(api.wave5_cash_authorize(pg_temp.fid('t'),pg_temp.fid('e'),pg_temp.fid('b')),auth.uid(),'Cash recovery revalidates current actor');
select is(api.wave5_cash_save(pg_temp.fid('t'),pg_temp.fid('e'),pg_temp.fid('b'),pg_temp.fid('cashscenario'),(select basis->>'sourceHash' from w5_cash),
 jsonb_build_object('horizonStart',current_date::text,'horizonEnd',(current_date+30)::text,'recordedThrough',analytics.process_utc(statement_timestamp()),'overrides','{}'::jsonb))->>'version','1','Cash scenario stores immutable version with captured source hash');
select is(api.wave5_cash_get(pg_temp.fid('t'),pg_temp.fid('e'),pg_temp.fid('b'),pg_temp.fid('cashscenario'))->>'sourceHash',(select basis->>'sourceHash' from w5_cash),'Scenario reopens identical captured source evidence');
delete from core.role_permissions where tenant_id=pg_temp.fid('t') and role_id=pg_temp.fid('owner.role') and permission_code='finance.payments.manage';
select throws_ok($$select api.wave5_cash_get(pg_temp.fid('t'),pg_temp.fid('e'),pg_temp.fid('b'),pg_temp.fid('cashscenario'))$$,'42501','PERMISSION_DENIED','Scenario reopen rechecks payable permission for frozen AP evidence');
insert into core.role_permissions values(pg_temp.fid('t'),pg_temp.fid('owner.role'),'finance.payments.manage') on conflict do nothing;
select throws_ok($$update analytics.cash_scenario_revisions set parameters='{}'$$,'55000','IMMUTABLE_EVIDENCE','Scenario parameters cannot be overwritten');
select ok(not has_table_privilege('authenticated','analytics.cash_scenario_revisions','select'),'Scenario evidence denied to direct client reads');
insert into core.role_permissions values(pg_temp.fid('t'),pg_temp.fid('owner.role'),'finance.reports.export');
create temporary table w5_export as select api.report_export_preview(pg_temp.fid('t'),pg_temp.fid('e'),pg_temp.fid('b'),'w5_cash',pg_temp.fid('cashscenario'),'buckets','{}') preview;
select is(((select preview->>'canonical_text' from w5_export)::jsonb)#>>'{rows,1,balance}','400.000000','Governed cash export calculates exact dated scenario buckets');
select is(((select preview->>'canonical_text' from w5_export)::jsonb)#>>'{metadata,source_basis_hash}',(select basis->>'sourceHash' from w5_cash),'Export preserves frozen calculation source hash');
-- SQL tests register metadata only. Dart codec tests separately verify actual
-- bytes; this placeholder artifact is never written or externally delivered.
create temporary table w5_export_payload as select jsonb_build_object('id',pg_temp.fid('exportjob'),'source_type','w5_cash','source_id',pg_temp.fid('cashscenario'),
 'section','buckets','filters','{}'::jsonb,'source_hash',preview->>'source_hash','file_format','csv','file_name','synthetic.csv','file_size','1','file_sha256',repeat('a',64),
 'prepared_at',analytics.process_utc(statement_timestamp()),'columns',jsonb_build_array('record_type')||
  (select jsonb_agg('report.'||key order by key) from(select jsonb_object_keys((preview->>'canonical_text')::jsonb->'metadata') key
   union select unnest(array['export_id','export_prepared_at','source_hash','file_format']))x)||
  (select jsonb_agg('data.'||key order by key) from(select distinct key from jsonb_array_elements((preview->>'canonical_text')::jsonb->'rows')r
   cross join lateral jsonb_object_keys(r)key)x)) payload from w5_export;
create temporary table w5_export_receipt as select api.record_report_export(pg_temp.fid('t'),pg_temp.fid('e'),pg_temp.fid('b'),pg_temp.fid('exportjob'),pg_temp.fid('exportjob'),statement_timestamp(),(select payload from w5_export_payload),0) result;
select is(api.record_report_export(pg_temp.fid('t'),pg_temp.fid('e'),pg_temp.fid('b'),pg_temp.fid('exportjob'),pg_temp.fid('exportjob'),statement_timestamp(),(select payload from w5_export_payload),0),
 (select result from w5_export_receipt),'Governed export registration retries its original audited metadata receipt');
select is(api.wave5_export_reopen(pg_temp.fid('t'),pg_temp.fid('e'),pg_temp.fid('b'),pg_temp.fid('exportjob'))->>'sourceHash',(select preview->>'source_hash' from w5_export),
 'Governed export reopens the captured source hash under current access');
delete from core.role_permissions where tenant_id=pg_temp.fid('t') and role_id=pg_temp.fid('owner.role') and permission_code='finance.reports.export';
select throws_ok($$select api.wave5_export_reopen(pg_temp.fid('t'),pg_temp.fid('e'),pg_temp.fid('b'),pg_temp.fid('exportjob'))$$,
 '42501','Permission denied or multi-factor authentication required.','Export source is rechecked after export capability revocation');
insert into core.role_permissions values(pg_temp.fid('t'),pg_temp.fid('owner.role'),'finance.reports.export');
select is((api.wave5_pipeline_history(pg_temp.fid('t'),pg_temp.fid('e'),pg_temp.fid('b'),statement_timestamp(),statement_timestamp())
 ->>'canonicalText')::jsonb->>'complete','true','History adapter advertises complete bounded revisions');
select is(jsonb_array_length(((api.wave5_pipeline_history(pg_temp.fid('t'),pg_temp.fid('e'),pg_temp.fid('b'),statement_timestamp(),statement_timestamp())
 ->>'canonicalText')::jsonb)->'revisions'),1,'Installed immutable CRM revision selected');
select throws_ok($$select api.wave5_pipeline_history(pg_temp.fid('t'),pg_temp.fid('e'),pg_temp.fid('b'),now(),now()+interval '1 day')$$,
 '22023','VALIDATION_ERROR','Future history cutoff denied');
select ok(not has_function_privilege('anon','api.wave5_pipeline_history(uuid,uuid,uuid,timestamptz,timestamptz)','execute'),'Anonymous history read denied');
select throws_ok($test$do $body$begin
 insert into crm.pipeline_history select (jsonb_populate_record(null::crm.pipeline_history,to_jsonb(h)||
  jsonb_build_object('id',pg_temp.fid('historygap'),'version',3,'recorded_at',statement_timestamp()))).* from crm.pipeline_history h
  where h.tenant_id=pg_temp.fid('t') and h.entity_type='opportunity' limit 1;
 perform api.wave5_pipeline_history(pg_temp.fid('t'),pg_temp.fid('e'),pg_temp.fid('b'),statement_timestamp(),statement_timestamp());
end $body$$test$,'55000','HISTORY_REVISION_GAP','Historical revision gap fails instead of reporting plausible partial conversion or stage age');
insert into core.role_permissions values(pg_temp.fid('t'),pg_temp.fid('owner.role'),'integrations.manage');
insert into intelligence_control.integration_hosts values('events.jentra.test');
create temporary table w5_registered as select api.wave5_integration_manage(pg_temp.fid('t'),pg_temp.fid('e'),pg_temp.fid('b'),
 'register',pg_temp.fid('subscription'),0,'{"url":"https://events.jentra.test/hook","keyRef":"synthetic/key1"}') result;
select is((select result->>'version' from w5_registered),'1','Scoped MFA integration registration persists revision');
select is(api.wave5_integration_manage(pg_temp.fid('t'),pg_temp.fid('e'),pg_temp.fid('b'),
 'register',pg_temp.fid('subscription'),0,'{"url":"https://events.jentra.test/hook","keyRef":"synthetic/key1"}'),
 (select result from w5_registered),'Registration uncertain retry reopens original receipt');
select throws_ok($$select api.wave5_integration_manage(pg_temp.fid('t'),pg_temp.fid('e'),pg_temp.fid('b'),
 'register',pg_temp.fid('unreviewed'),0,'{"url":"https://unreviewed.jentra.test/hook","keyRef":"synthetic/key1"}')$$,
 '42501','UNREVIEWED_DESTINATION','Destination must have explicit server review');
select throws_ok($$select api.wave5_integration_manage(pg_temp.fid('t'),pg_temp.fid('e'),pg_temp.fid('b'),
 'rotate',pg_temp.fid('subscription'),2,'{"keyRef":"synthetic/key2"}')$$,'40001','CONFLICT','Key rotation checks exact version');
select is(api.wave5_integration_manage(pg_temp.fid('t'),pg_temp.fid('e'),pg_temp.fid('b'),
 'rotate',pg_temp.fid('subscription'),1,'{"keyRef":"synthetic/key2"}')->>'keyVersion','2','Key rotation creates next server version');
select is(api.wave5_integration_manage(pg_temp.fid('t'),pg_temp.fid('e'),pg_temp.fid('b'),
 'rotate',pg_temp.fid('subscription'),1,'{"keyRef":"synthetic/key2"}')->>'keyVersion','2','Repeated rotation does not create another key version');
select throws_ok($$update intelligence_control.integration_changes set action='rewrite'$$,'55000','IMMUTABLE_EVIDENCE','Registration and rotation evidence immutable');
select ok(not has_table_privilege('authenticated','intelligence_control.delivery_heads','select'),'Desktop cannot read worker state');
select ok(not has_function_privilege('authenticated','api.wave5_delivery_worker(text,jsonb)','execute'),'Worker API denied to authenticated desktop');
update billing.plan_entitlements set enabled=true,numeric_limit=10 where plan_code='starter' and entitlement_code='quota.webhook.deliveries';
select api.freeze_pipeline_forecast(pg_temp.fid('t'),pg_temp.fid('e'),pg_temp.fid('b'),pg_temp.fid('leaseforecast'),pg_temp.fid('leaseforecast'),
 statement_timestamp(),'2026-10-01','2026-11-01');
select set_config('request.jwt.claims','{"role":"service_role"}',true);
select is(api.wave5_delivery_worker('readiness','{}')->>'ready','true','Composed candidate worker contract readiness');
create temporary table w5_claimed as select api.wave5_delivery_worker('claim','{}') job;
select is((select job#>>'{event,type}' from w5_claimed),'analytics.forecast.frozen.v1','Committed outbox maps to allowlisted redacted event');
select is((select job->>'attempt' from w5_claimed),'1','Atomic claim creates first immutable lease attempt');
select is(api.wave5_delivery_worker('claim','{}'),null::jsonb,'Leased delivery cannot be claimed again');
select api.wave5_delivery_worker('outcome',(select jsonb_build_object('deliveryId',job->>'deliveryId','leaseId',job->>'leaseId','state','unknown','httpStatus',null) from w5_claimed));
select is(api.wave5_delivery_worker('claim','{}'),null::jsonb,'Unknown outcome is never automatically retried');
select is((select count(*) from intelligence_control.delivery_outcomes),1::bigint,'Outcome remains immutable recorded evidence');
select pg_temp.actor('owner');
select throws_ok($$select api.wave5_delivery_review(pg_temp.fid('t'),pg_temp.fid('e'),pg_temp.fid('b'),
 (select job->>'deliveryId' from w5_claimed)::uuid,pg_temp.fid('review'),'replay','Synthetic review reason')$$,
 '22023','OUTCOME_REVIEW_REQUIRED','Unknown delivery cannot use ordinary dead-letter replay');
select is(api.wave5_delivery_review(pg_temp.fid('t'),pg_temp.fid('e'),pg_temp.fid('b'),
 (select job->>'deliveryId' from w5_claimed)::uuid,pg_temp.fid('review'),'not_sent','Synthetic receiver confirmed no send')->>'state',
 'retry','MFA reviewed no-send decision authorizes original delivery retry');
select pg_temp.actor('owner');
select is(api.wave5_integration_manage(pg_temp.fid('t'),pg_temp.fid('e'),pg_temp.fid('b'),
 'revoke',pg_temp.fid('subscription'),2,'{}')->>'enabled','false','Revocation disables current subscription');
select is((select count(*) from intelligence_control.integration_changes),3::bigint,'All three reviewed changes retain immutable history');
select ok(not has_function_privilege('authenticated','api.wave5_external_worker(text,jsonb)','execute'),'External dispatcher is server-only');
select ok(not has_function_privilege('authenticated','api.wave5_model_worker(text,jsonb)','execute'),'Model metering port is server-only');
select set_config('request.jwt.claims','{"role":"service_role"}',true);
select is(api.wave5_model_worker('readiness','{}')->>'contractRevision','1','Persistent model contract revision verified');
create temporary table w5_model_request as select jsonb_build_object('invocationId',pg_temp.fid('model'),
 'usageEventId',pg_temp.fid('modelusage'),'tenantId',pg_temp.fid('t'),'sourceId',f.id,'sourceHash',f.source_hash,
 'manifestHash',repeat('a',64),'maxTokens','20','policyRevision',1) payload from analytics.pipeline_forecasts f where f.tenant_id=pg_temp.fid('t') limit 1;
select is(api.wave5_model_worker('begin',(select payload from w5_model_request))->>'state','new','Model invocation is durably created before provider send');
select is(api.wave5_model_worker('begin',(select payload from w5_model_request))->>'state','pending','Restart cannot silently resend a pending invocation');
select throws_ok($$select api.wave5_model_worker('outcome',jsonb_build_object('invocationId',pg_temp.fid('model'),'state','settled'))$$,
 '22023','MODEL_OUTCOME_MISMATCH','Missing trusted usage cannot settle a pending model request');
select throws_ok($$select api.wave5_model_worker('outcome',jsonb_build_object('invocationId',pg_temp.fid('model'),'state','settled','tokens','21','suggestion','{}'::jsonb))$$,
 '22023','MODEL_OUTCOME_MISMATCH','Model tokens cannot exceed the original reservation');
select api.wave5_model_worker('outcome',jsonb_build_object('invocationId',pg_temp.fid('model'),'state','unknown'));
select is(api.wave5_model_worker('begin',(select payload from w5_model_request))->>'state','unknown','Unknown provider result persists across independent calls');
select throws_ok($$update intelligence_control.model_outcomes set state='settled'$$,'55000','IMMUTABLE_EVIDENCE','Model outcome cannot be overwritten');
select is(api.wave5_model_worker('begin',(select jsonb_set(payload,'{invocationId}',to_jsonb(pg_temp.fid('model2')::text)) from w5_model_request))->>'state','new','Another reviewed invocation has its own durable identity');
select api.wave5_model_worker('outcome',jsonb_build_object('invocationId',pg_temp.fid('model2'),'state','settled','tokens','7',
 'suggestion',(select jsonb_build_object('commandCode','analytics.freeze_pipeline.v1','sourceId',f.id,'sourceHash',f.source_hash,
  'horizonStart',f.horizon_start::text,'horizonEnd',f.horizon_end::text) from analytics.pipeline_forecasts f where f.id=(select (payload->>'sourceId')::uuid from w5_model_request))));
select is(api.wave5_model_worker('begin',(select jsonb_set(payload,'{invocationId}',to_jsonb(pg_temp.fid('model2')::text)) from w5_model_request))->>'tokens','7',
 'Settled durable model outcome reopens only validated suggestion and trusted usage');
select is(api.wave5_subscription_due(null)->>'contractRevision','1','Synthetic scheduler reads a bounded server-only due queue');
select is(api.wave5_health_collect(pg_temp.fid('health'),pg_temp.fid('t'))->>'contractRevision','1','Operator probe collector reads durable queue and quota data');
create temporary table w5_collected_health as select api.wave5_health_collect(pg_temp.fid('health'),pg_temp.fid('t')) result;
select is(api.wave5_health_collect(pg_temp.fid('health'),pg_temp.fid('t')),(select result from w5_collected_health),'Health collection retry retains original observation times and quantities');
select ok(not has_function_privilege('authenticated','api.wave5_health_collect(uuid,uuid)','execute'),'Desktop cannot publish purported worker health');
select ok(not has_function_privilege('authenticated','api.wave5_subscription_due(uuid)','execute'),'Desktop cannot enumerate cross-tenant activation work');
select pg_temp.actor('owner');
select api.wave5_credential_manage(pg_temp.fid('t'),pg_temp.fid('e'),pg_temp.fid('b'),'register',pg_temp.fid('credential'),
 jsonb_build_object('tokenHash',repeat('b',64),'startsAt',analytics.process_utc(statement_timestamp()-interval '1 minute'),
 'expiresAt',analytics.process_utc(statement_timestamp()+interval '1 day')));
select api.wave5_credential_manage(pg_temp.fid('t'),pg_temp.fid('e'),pg_temp.fid('b'),'register',pg_temp.fid('credential'),
 jsonb_build_object('tokenHash',repeat('b',64),'startsAt',analytics.process_utc(statement_timestamp()-interval '1 minute'),
 'expiresAt',analytics.process_utc(statement_timestamp()+interval '1 day')));
select is((select count(*) from intelligence_control.integration_credentials),1::bigint,'Credential registration retry creates one hashed credential');
select is((select count(*) from core.command_receipts where command_name='integration.credential.register'),1::bigint,'Credential registration has one stable audited command');
select set_config('request.jwt.claims','{"role":"service_role"}',true);
select is(api.wave5_external_worker('credential',jsonb_build_object('tokenHash',repeat('b',64)))#>>'{scope,tenantId}',
 pg_temp.fid('t')::text,'Credential hash resolves exact scoped authority');
update billing.plan_entitlements set enabled=true,numeric_limit=2 where plan_code='starter' and entitlement_code='quota.integration.commands';
create temporary table w5_external_request as select jsonb_build_object('tokenHash',repeat('b',64),'request',jsonb_build_object(
 'schemaVersion',1,'scope',jsonb_build_object('tenantId',pg_temp.fid('t'),'legalEntityId',pg_temp.fid('e'),'branchId',pg_temp.fid('b')),
 'commandCode','analytics.freeze_pipeline.v1','commandId',pg_temp.fid('external'),'idempotencyKey',pg_temp.fid('external'),
 'clientTimestamp',analytics.process_utc(statement_timestamp()),'horizonStart','2026-10-01','horizonEnd','2026-11-01')) payload;
select is(api.wave5_external_worker('reserve',(select payload from w5_external_request))->>'quotaReserved','true','External reservation reads live billing hard cap');
select is(api.wave5_external_worker('reserve',(select payload from w5_external_request))->>'throttleReserved','true','Identical retry reuses its atomic throttle slot');
select is((select reserved::text from intelligence_control.external_periods where tenant_id=pg_temp.fid('t')),'1','Duplicate reservation consumes one unit');
create temporary table w5_external_receipt as select api.wave5_external_worker('dispatch',(select payload from w5_external_request)) result;
select is(api.wave5_external_worker('dispatch',(select payload from w5_external_request)),(select result from w5_external_receipt),'Named dispatch restart reopens original domain receipt');
select is((select count(*) from core.command_receipts where tenant_id=pg_temp.fid('t') and command_id=pg_temp.fid('external')),1::bigint,'External stable identity creates one actual domain command');
select throws_ok($$select api.wave5_external_worker('credential',jsonb_build_object('tokenHash',repeat('c',64)))$$,
 '42501','INTEGRATION_ACCESS_DENIED','Unknown credential hash is non-disclosing');
select pg_temp.actor('owner');
select api.wave5_credential_manage(pg_temp.fid('t'),pg_temp.fid('e'),pg_temp.fid('b'),'revoke',pg_temp.fid('credential'),'{}');
select set_config('request.jwt.claims','{"role":"service_role"}',true);
select throws_ok($$select api.wave5_external_worker('credential',jsonb_build_object('tokenHash',repeat('b',64)))$$,
 '42501','INTEGRATION_ACCESS_DENIED','Credential revocation precedes dispatch or reservation');
select pg_temp.actor('owner');

-- Statement authority is entity-wide; branch-only finance access is insufficient.
insert into core.role_assignments(tenant_id,membership_id,role_id,legal_entity_id,branch_id,created_by)
 values(pg_temp.fid('t'),pg_temp.fid('owner.member'),pg_temp.fid('owner.role'),pg_temp.fid('e'),null,auth.uid());
insert into core.role_permissions values(pg_temp.fid('t'),pg_temp.fid('owner.role'),'finance.classifications.approve');
select api.generate_financial_statement(pg_temp.fid('t'),pg_temp.fid('e'),pg_temp.fid('b'),pg_temp.fid('pl'),pg_temp.fid('pl'),statement_timestamp(),
 jsonb_build_object('id',pg_temp.fid('pl'),'kind','profit_loss','period_id',pg_temp.fid('cash.period'),'as_of',current_date),0);
select api.generate_financial_statement(pg_temp.fid('t'),pg_temp.fid('e'),pg_temp.fid('b'),pg_temp.fid('bs'),pg_temp.fid('bs'),statement_timestamp(),
 jsonb_build_object('id',pg_temp.fid('bs'),'kind','balance_sheet','period_id',pg_temp.fid('cash.period'),'as_of',current_date),0);
create temporary table w5_ratios as select (api.wave5_financial_ratios(pg_temp.fid('t'),pg_temp.fid('e'),pg_temp.fid('b'),pg_temp.fid('pl'),pg_temp.fid('bs'),null)->>'canonicalText')::jsonb value;
select is((select value#>>'{ratios,net_profit_margin,exactValue}' from w5_ratios),'1.000000','Named ratio consumes matching immutable P&L and balance-sheet ledger evidence');
select throws_ok($$select api.wave5_classification_publish(pg_temp.fid('t'),pg_temp.fid('e'),pg_temp.fid('b'),pg_temp.fid('classification'),
 pg_temp.fid('pl'),pg_temp.fid('bs'),'{}','Synthetic classification review')$$,'22023','CLASSIFICATION_COVERAGE_REQUIRED','Missing classifications cannot guess current assets or cost of sales');
create temporary table w5_classified as select api.wave5_classification_publish(pg_temp.fid('t'),pg_temp.fid('e'),pg_temp.fid('b'),pg_temp.fid('classification'),
 pg_temp.fid('pl'),pg_temp.fid('bs'),jsonb_build_object(pg_temp.fid('cash.cash')::text,'current_asset',pg_temp.fid('cash.offset')::text,'revenue'),'Synthetic classification review') value;
select is(api.wave5_classification_publish(pg_temp.fid('t'),pg_temp.fid('e'),pg_temp.fid('b'),pg_temp.fid('classification'),
 pg_temp.fid('pl'),pg_temp.fid('bs'),jsonb_build_object(pg_temp.fid('cash.cash')::text,'current_asset',pg_temp.fid('cash.offset')::text,'revenue'),'Synthetic classification review'),
 (select value from w5_classified),'Classification publication retry reuses original audited receipt');
select is(((api.wave5_financial_ratios(pg_temp.fid('t'),pg_temp.fid('e'),pg_temp.fid('b'),pg_temp.fid('pl'),pg_temp.fid('bs'),pg_temp.fid('classification'))->>'canonicalText')::jsonb)#>>'{ratios,current_ratio,unavailableReason}',
 'ZERO_DENOMINATOR','Classified ratio distinguishes zero denominator from a zero ratio');
select is(((api.wave5_financial_ratios(pg_temp.fid('t'),pg_temp.fid('e'),pg_temp.fid('b'),pg_temp.fid('pl'),pg_temp.fid('bs'),pg_temp.fid('classification'))->>'canonicalText')::jsonb)#>>'{ratios,gross_profit_margin,exactValue}',
 '1.000000','Classified cost-of-sales population provides exact gross margin');
select throws_ok($$update analytics.statement_classifications set labels='{}'$$,'55000','IMMUTABLE_EVIDENCE','Governed classifications cannot mutate');
select ok(not has_table_privilege('authenticated','analytics.statement_classifications','select'),'Classifications have forced RLS and deny direct client reads');

-- A synthetic prospectively dated frozen basis exercises the complete realized
-- SQL mapping. This fixture is rolled back; it is not a real past prediction.
insert into analytics.pipeline_forecasts(id,tenant_id,legal_entity_id,branch_id,created_by,horizon_start,horizon_end,observed_at,canonical_text,source_hash,evidence)
 select pg_temp.fid('realized'),pg_temp.fid('t'),pg_temp.fid('e'),pg_temp.fid('b'),auth.uid(),current_date-30,current_date,current_date-2,
  data::text,encode(extensions.digest(data::text,'sha256'),'hex'),data from (
  select jsonb_set(jsonb_set(jsonb_set(evidence,'{asOf}',to_jsonb(analytics.process_utc((current_date-2)::timestamptz))),
   '{horizonStart}',to_jsonb((current_date-30)::text)),'{horizonEnd}',to_jsonb(current_date::text)) data
  from analytics.pipeline_forecasts where tenant_id=pg_temp.fid('t') limit 1) f;
insert into core.role_permissions values(pg_temp.fid('t'),pg_temp.fid('owner.role'),'sales.returns.view');
select is(api.wave5_pipeline_realized(pg_temp.fid('t'),pg_temp.fid('e'),pg_temp.fid('b'),pg_temp.fid('realized'),statement_timestamp())->>'complete',
 'true','Closed realized mapping queries installed invoice/order/return contracts completely');

-- Bounded keyset pages keep every captured scope check; no receiver or key is provisioned.
insert into intelligence_control.integration_subscriptions(id,tenant_id,legal_entity_id,branch_id,created_by,url,hostname,key_ref)
 select pg_temp.fid('page.'||i),pg_temp.fid('t'),pg_temp.fid('e'),pg_temp.fid('b'),auth.uid(),
 'https://events.jentra.test/hook','events.jentra.test','synthetic/key1' from generate_series(1,51)i;
create temporary table w5_subscription_page as select api.wave5_integration_list(pg_temp.fid('t'),pg_temp.fid('e'),pg_temp.fid('b')) result;
select is(jsonb_array_length((select result->'subscriptions' from w5_subscription_page)),50,'Integration interactive page defaults to exactly 50 bounded rows');
select ok((select result->>'subscriptionNext' is not null from w5_subscription_page),'Integration page advertises an exact scoped continuation cursor');
create temporary table w5_subscription_next as select api.wave5_integration_list(pg_temp.fid('t'),pg_temp.fid('e'),pg_temp.fid('b'),
 (select (result->>'subscriptionNext')::uuid from w5_subscription_page),null) result;
select is(jsonb_array_length((select result->'subscriptions' from w5_subscription_next)),2,'Continuation returns the remainder without dropping scoped rows');
select ok(not exists(select 1 from jsonb_array_elements((select result->'subscriptions' from w5_subscription_page)) a
 join jsonb_array_elements((select result->'subscriptions' from w5_subscription_next)) b on a->>'id'=b->>'id'),'Keyset continuation never repeats a row');
select set_config('request.jwt.claims',jsonb_build_object('sub',auth.uid(),'role','authenticated','aal','aal1')::text,true);
select throws_ok($$select api.wave5_integration_list(pg_temp.fid('t'),pg_temp.fid('e'),pg_temp.fid('b'))$$,
 '42501','APPROVAL_REQUIRED','Integration storage projection itself requires real MFA assurance');
select pg_temp.actor('owner');
select is((select count(*) from pg_class c join pg_namespace n on n.oid=c.relnamespace
 where n.nspname in('analytics','intelligence_control') and c.relkind='r'),30::bigint,'Composed Wave 5 adds fifteen tables alongside the fifteen installed tables');
select ok(not exists(select 1 from pg_class c join pg_namespace n on n.oid=c.relnamespace
 where n.nspname in('analytics','intelligence_control') and c.relkind='r' and (not c.relrowsecurity or not c.relforcerowsecurity)),
 'Every installed and candidate Wave 5 table enables and forces RLS');
select ok(not exists(select 1 from pg_class c join pg_namespace n on n.oid=c.relnamespace
 where n.nspname in('analytics','intelligence_control') and c.relkind='r' and
 (has_table_privilege('authenticated',c.oid,'select,insert,update,delete') or has_table_privilege('anon',c.oid,'select,insert,update,delete'))),
 'All thirty Wave 5 tables deny direct client table access');
