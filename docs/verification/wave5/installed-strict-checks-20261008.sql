begin;
-- Synthetic namespace; included after the candidate inside one strict rollback.
create extension if not exists pgtap with schema extensions;
set local search_path=extensions,public,pg_catalog;
select no_plan();
create temporary table w5_tap(message text);
create function pg_temp.fid(s text) returns uuid language sql immutable as $$select md5('wave5-process-20261006:'||s)::uuid$$;
create function pg_temp.actor(s text) returns void language plpgsql as $$begin perform set_config('request.jwt.claims',jsonb_build_object('sub',pg_temp.fid(s),'role','authenticated','aal','aal2')::text,true);end$$;
insert into auth.users(id,instance_id,aud,role,email,encrypted_password,email_confirmed_at,created_at,updated_at)
select pg_temp.fid(x),'00000000-0000-0000-0000-000000000000','authenticated','authenticated',x||'@w5.jentra.test','',now(),now(),now()
from unnest(array['owner','reader','outsider']) x;
insert into core.tenants(id,name,slug,created_by) values(pg_temp.fid('t'),'Synthetic Wave 5','wave5-process-synthetic',pg_temp.fid('owner'));
insert into core.legal_entities(id,tenant_id,name,code,currency_code,timezone,rounding_scale,created_by)
values(pg_temp.fid('e'),pg_temp.fid('t'),'Synthetic Analytics','W5SYN','LKR','UTC',2,pg_temp.fid('owner'));
insert into core.branches(id,tenant_id,legal_entity_id,name,code,created_by)
select pg_temp.fid(x),pg_temp.fid('t'),pg_temp.fid('e'),'Synthetic Branch '||x,'W5'||upper(x),pg_temp.fid('owner') from unnest(array['b','b2']) x;
insert into billing.tenant_subscriptions(tenant_id,plan_code,status,seats,trial_ends_at)
values(pg_temp.fid('t'),'starter','trialing',5,now()+interval '1 day');
-- The existing plan is changed only within this rollback transaction.
insert into billing.plan_entitlements(plan_code,entitlement_code,enabled) values('starter','analytics',true)
on conflict(plan_code,entitlement_code) do update set enabled=true;
insert into core.memberships(id,tenant_id,user_id,status)
select pg_temp.fid(x||'.member'),pg_temp.fid('t'),pg_temp.fid(x),'active' from unnest(array['owner','reader']) x;
insert into core.roles(id,tenant_id,code,name,requires_mfa)
select pg_temp.fid(x||'.role'),pg_temp.fid('t'),x,x,false from unnest(array['owner','reader']) x;
insert into core.role_permissions(tenant_id,role_id,permission_code)
select pg_temp.fid('t'),pg_temp.fid(x||'.role'),p from unnest(array['owner','reader']) x
cross join unnest(array['analytics.view','workflow.process.view','crm.opportunities.view']) p;
insert into core.role_assignments(tenant_id,membership_id,role_id,legal_entity_id,branch_id,created_by)
select pg_temp.fid('t'),pg_temp.fid(x||'.member'),pg_temp.fid(x||'.role'),pg_temp.fid('e'),pg_temp.fid('b'),pg_temp.fid('owner')
from unnest(array['owner','reader']) x;
insert into crm.opportunities(id,tenant_id,legal_entity_id,branch_id,code,prospect_name,owner_id,currency_code,created_by,updated_by,
 expected_close_date,request_id,command_id,correlation_id,client_timestamp)
values(pg_temp.fid('o'),pg_temp.fid('t'),pg_temp.fid('e'),pg_temp.fid('b'),'W5-O','Synthetic prospect',pg_temp.fid('owner'),'LKR',pg_temp.fid('owner'),pg_temp.fid('owner'),
 '2026-10-01',pg_temp.fid('o'),pg_temp.fid('o'),pg_temp.fid('o'),'2026-09-01');
insert into workflow.process_events(id,tenant_id,legal_entity_id,branch_id,document_type,document_id,to_status,actor_id,owner_id,
 entered_at,completed_at,request_id,command_id,correlation_id,created_at,reason)
select pg_temp.fid(x),pg_temp.fid('t'),pg_temp.fid('e'),pg_temp.fid('b'),'crm_opportunity',pg_temp.fid('o'),'qualified',
 pg_temp.fid('reader'),pg_temp.fid('reader'),'2026-09-01T00:00:00Z',
 case x when 'zero' then '2026-09-01T00:00:00Z'::timestamptz when 'closed' then '2026-09-01T00:00:00.000001Z'::timestamptz else null end,
 pg_temp.fid(x),pg_temp.fid(x),pg_temp.fid(x),'2026-09-02T00:00:00Z','PRIVATE TEST REASON'
from unnest(array['zero','closed','open']) x;
create function pg_temp.read(b text default 'b', ending timestamptz default '2026-10-01T00:00:00Z') returns jsonb language sql as $$
select api.analytics_process_snapshot(pg_temp.fid('t'),pg_temp.fid('e'),pg_temp.fid(b),'2026-09-01T00:00:00Z',ending,'2026-10-01T00:00:00Z','2026-10-02T00:00:00Z')$$;
select pg_temp.actor('owner');
create temporary table w5_results(name text primary key,result jsonb);
insert into w5_tap select is(api.analytics_process_authorize(pg_temp.fid('t'),pg_temp.fid('e'),pg_temp.fid('b')),pg_temp.fid('owner'),'Recovery authorization returns actual authenticated actor');
insert into w5_results values('snapshot',pg_temp.read());
insert into w5_tap select is((select result#>>'{source,sourceCount}' from w5_results),'3','Complete authorized cohort captured');
insert into w5_tap select is((select result#>>'{source,complete}' from w5_results),'true','Complete manifest advertised only after bounded query');
insert into w5_tap select ok((select result#>>'{source,sourceManifestHash}' ~ '^[0-9a-f]{64}$' from w5_results),'Canonical SHA256 captured');
insert into w5_tap select ok((select result::text not like '%PRIVATE TEST REASON%' and result::text not like '%actorId%' and result::text not like '%ownerId%' from w5_results),'Private reason and identities omitted');
insert into w5_tap select is((select count(*) from jsonb_array_elements((select result->'observations' from w5_results)) x where x->>'completedAt'='2026-09-01T00:00:00.000001Z'),1::bigint,'Exact microsecond transport');
insert into w5_tap select is((pg_temp.read()->'source'->>'sourceManifestHash'),(select result#>>'{source,sourceManifestHash}' from w5_results),'Repeated basis digest stable');
insert into w5_tap select is((api.analytics_process_event(pg_temp.fid('t'),pg_temp.fid('e'),pg_temp.fid('b'),pg_temp.fid('zero'))->>'documentId'),pg_temp.fid('o')::text,'Drill-through rechecks actual source');
insert into w5_tap select throws_ok($$select pg_temp.read('b2')$$,'42501','Permission denied or multi-factor authentication required.','Foreign branch denied');
insert into w5_tap select throws_ok($$select pg_temp.read('b','2026-09-01')$$,'22023','VALIDATION_ERROR','Empty range rejected');
insert into w5_tap select throws_ok($$select api.analytics_process_snapshot(pg_temp.fid('t'),pg_temp.fid('e'),pg_temp.fid('b'),'2024-01-01','2026-01-01','2026-01-01','2026-01-01')$$,'54000','LIMIT_EXCEEDED','366-day bound enforced');
insert into w5_tap select throws_ok($$select api.analytics_process_snapshot(pg_temp.fid('t'),pg_temp.fid('e'),pg_temp.fid('b'),'2026-09-01','2026-10-01','2026-10-01','2099-01-01')$$,'22023','VALIDATION_ERROR','Future recorded cutoff rejected');
delete from core.role_permissions where role_id=pg_temp.fid('reader.role') and permission_code='crm.opportunities.view';
select pg_temp.actor('reader');
insert into w5_tap select throws_ok($$select pg_temp.read()$$,'42501','PERMISSION_DENIED','Own/owned event is insufficient without source permission');
insert into w5_tap select throws_ok($$select api.analytics_process_event(pg_temp.fid('t'),pg_temp.fid('e'),pg_temp.fid('b'),pg_temp.fid('zero'))$$,'42501','PERMISSION_DENIED','Revoked source blocks drill-through');
select pg_temp.actor('outsider');
insert into w5_tap select throws_ok($$select pg_temp.read()$$,'42501','Permission denied or multi-factor authentication required.','Foreign member denied before aggregate');
select set_config('request.jwt.claims','{}',true);
insert into w5_tap select throws_ok($$select pg_temp.read()$$,'42501','AUTH_REQUIRED','Anonymous denied');
select pg_temp.actor('owner');
update billing.plan_entitlements set enabled=false where plan_code='starter' and entitlement_code='analytics';
insert into w5_tap select throws_ok($$select pg_temp.read()$$,'42501','ENTITLEMENT_REQUIRED','Missing entitlement denies aggregate');
update billing.plan_entitlements set enabled=true where plan_code='starter' and entitlement_code='analytics';
insert into w5_tap select ok(not has_function_privilege('anon','api.analytics_process_snapshot(uuid,uuid,uuid,timestamptz,timestamptz,timestamptz,timestamptz)','execute'),'Anonymous cannot execute provider');
insert into w5_tap select ok(not has_function_privilege('authenticated','analytics.process_access(uuid,uuid,uuid)','execute'),'Private helper denied');
insert into w5_tap select throws_ok($test$do $body$begin
 insert into workflow.process_events(id,tenant_id,legal_entity_id,branch_id,document_type,document_id,to_status,actor_id,
  entered_at,completed_at,request_id,command_id,correlation_id,created_at)
 select pg_temp.fid('bound.'||i),pg_temp.fid('t'),pg_temp.fid('e'),pg_temp.fid('b'),'crm_opportunity',pg_temp.fid('o'),'qualified',pg_temp.fid('owner'),
  '2026-09-01','2026-09-02',pg_temp.fid('bound.'||i),pg_temp.fid('bound.'||i),pg_temp.fid('bound.'||i),'2026-09-02'
 from generate_series(1,9998) i;
 perform pg_temp.read();
end $body$$test$,'54000','LIMIT_EXCEEDED','10001 rows fail atomically without truncated totals');
insert into w5_tap select is((pg_temp.read()#>>'{source,sourceCount}'),'3','Excess-fixture failure leaves original cohort intact');

-- Compose after the existing process fixture, before its finish(true).
insert into w5_tap select is(api.analytics_pipeline_authorize(pg_temp.fid('t'),pg_temp.fid('e'),pg_temp.fid('b')),pg_temp.fid('owner'),'Forecast recovery binds actual actor');
update crm.opportunities set expected_value=10.000001,probability=50,version=9007199254740993
 where id=pg_temp.fid('o');
insert into crm.opportunities(id,tenant_id,legal_entity_id,branch_id,code,prospect_name,owner_id,currency_code,created_by,updated_by,
 expected_value,probability,expected_close_date,request_id,command_id,correlation_id,client_timestamp,version)
select pg_temp.fid(x),pg_temp.fid('t'),pg_temp.fid('e'),pg_temp.fid('b'),'W5-'||upper(x),'Synthetic prospect',
 pg_temp.fid('owner'),case x when 'usd' then 'USD' else 'LKR' end,pg_temp.fid('owner'),pg_temp.fid('owner'),
 10.000001,50,'2026-10-01',pg_temp.fid(x),pg_temp.fid(x),pg_temp.fid(x),'2026-09-01',9007199254740993
from unnest(array['usd','lkr']) x;
create function pg_temp.freeze(cmd text default 'forecast',end_date date default '2026-11-01') returns jsonb language sql as $$
select api.freeze_pipeline_forecast(pg_temp.fid('t'),pg_temp.fid('e'),pg_temp.fid('b'),pg_temp.fid(cmd),pg_temp.fid(cmd),
 '2026-10-06','2026-10-01',end_date)$$;
create temporary table w5_forecast as select pg_temp.freeze() receipt;
create temporary table w5_frozen as select api.get_pipeline_forecast(pg_temp.fid('t'),pg_temp.fid('e'),pg_temp.fid('b'),
 (receipt#>>'{entity,id}')::uuid) result from w5_forecast;
insert into w5_tap select is((select result#>>'{evidence,sourceCount}' from w5_frozen),'3','Complete open opportunity cohort frozen');
insert into w5_tap select is((select jsonb_array_length(result#>'{evidence,currencies}') from w5_frozen),2,'Currencies remain separate');
insert into w5_tap select is((select c->>'weightedAmount' from w5_frozen,jsonb_array_elements(result#>'{evidence,currencies}') c
 where c->>'currency'='LKR'),'10.000002','Exact per-opportunity half-away rounding precedes sum');
insert into w5_tap select is((select c->>'weightedAmount' from w5_frozen,jsonb_array_elements(result#>'{evidence,currencies}') c
 where c->>'currency'='USD'),'5.000001','USD forecast is never added to LKR');
insert into w5_tap select ok((select result::text like '%9007199254740993%' from w5_frozen),'Huge source revisions remain decimal strings');
insert into w5_tap select ok((select result::text not like '%prospect%' and result::text not like '%ownerId%' and result::text not like '%won_loss_reason%' from w5_frozen),'Names and private free text omitted');
insert into w5_tap select is((select result#>>'{evidence,unavailable,accuracy}' from w5_frozen),'REALIZED_MAPPING_UNAVAILABLE','Accuracy lacks realized cohort mapping');
insert into w5_tap select is((select result->>'sourceHash' from w5_frozen),
 (select encode(extensions.digest(convert_to(result->>'canonicalText','UTF8'),'sha256'),'hex') from w5_frozen),'Captured bytes bind complete evidence');
insert into w5_tap select is(pg_temp.freeze(),(select receipt from w5_forecast),'Identical retry reuses original receipt');
do $$begin for i in 1..100 loop perform pg_temp.freeze();end loop;end $$;
insert into w5_tap select is((select count(*) from analytics.pipeline_forecasts where tenant_id=pg_temp.fid('t')),1::bigint,'100 duplicate requests produce one frozen aggregate');
insert into w5_tap select is((select count(*) from core.command_receipts where tenant_id=pg_temp.fid('t') and command_name='analytics.freeze_pipeline'),1::bigint,'100 duplicate requests produce one command receipt');
insert into w5_tap select throws_ok($$select pg_temp.freeze('forecast','2026-12-01')$$,'22023','IDEMPOTENCY_MISMATCH','Changed retry payload denied');
update crm.opportunities set expected_value=999,probability=1,version=version+1 where id=pg_temp.fid('o');
insert into w5_tap select is((api.get_pipeline_forecast(pg_temp.fid('t'),pg_temp.fid('e'),pg_temp.fid('b'),
 (select receipt#>>'{entity,id}' from w5_forecast)::uuid)->>'sourceHash'),(select result->>'sourceHash' from w5_frozen),'Later source edits cannot change frozen evidence');
insert into w5_tap select throws_ok($$update analytics.pipeline_forecasts set evidence='{}' where tenant_id=pg_temp.fid('t')$$,
 '55000','IMMUTABLE_EVIDENCE','Frozen aggregate cannot be overwritten');
insert into w5_tap select throws_ok($$delete from analytics.pipeline_forecasts where tenant_id=pg_temp.fid('t')$$,
 '55000','IMMUTABLE_EVIDENCE','Frozen aggregate cannot be deleted');
insert into w5_tap select throws_ok($$select api.get_pipeline_forecast(pg_temp.fid('t'),pg_temp.fid('e'),pg_temp.fid('b2'),
 (select receipt#>>'{entity,id}' from w5_forecast)::uuid)$$,'42501','Permission denied or multi-factor authentication required.','Foreign branch cannot reopen');
insert into w5_tap select throws_ok($$select pg_temp.freeze('too-long','2028-01-01')$$,'54000','LIMIT_EXCEEDED','Forecast range bound rejects before effect');
select pg_temp.actor('outsider');
insert into w5_tap select throws_ok($$select pg_temp.freeze('outsider')$$,'42501','Permission denied or multi-factor authentication required.','Nonmember denied before capture');
select pg_temp.actor('owner');
delete from core.role_permissions where role_id=pg_temp.fid('owner.role') and permission_code='crm.opportunities.view';
insert into w5_tap select throws_ok($$select api.get_pipeline_forecast(pg_temp.fid('t'),pg_temp.fid('e'),pg_temp.fid('b'),
 (select receipt#>>'{entity,id}' from w5_forecast)::uuid)$$,'42501','PERMISSION_DENIED','Revocation blocks frozen reopen');
insert into core.role_permissions values(pg_temp.fid('t'),pg_temp.fid('owner.role'),'crm.opportunities.view');
insert into w5_tap select ok(not has_table_privilege('authenticated','analytics.pipeline_forecasts','select'),'No direct client table read bypass');
insert into w5_tap select ok(not has_function_privilege('anon','api.freeze_pipeline_forecast(uuid,uuid,uuid,uuid,uuid,timestamptz,date,date)','execute'),'Anonymous cannot freeze');

-- Compose with process/pipeline setup; all state rolls back.
insert into core.role_permissions values(pg_temp.fid('t'),pg_temp.fid('owner.role'),'billing.read');
insert into core.role_assignments(tenant_id,membership_id,role_id,created_by)
 values(pg_temp.fid('t'),pg_temp.fid('owner.member'),pg_temp.fid('owner.role'),pg_temp.fid('owner'));
update billing.plan_entitlements set enabled=true,numeric_limit=100 where plan_code='starter' and entitlement_code='quota.ai.tokens';
create function pg_temp.worker() returns void language sql as $$select set_config('request.jwt.claims',jsonb_build_object('role','service_role','sub',pg_temp.fid('owner'))::text,true)::void$$;
create function pg_temp.reserve(i text,q text default '60') returns jsonb language sql as $$
 select api.wave5_reserve_usage(pg_temp.fid('t'),pg_temp.fid(i),'ai.tokens',s.created_at,s.trial_ends_at,q)
 from billing.tenant_subscriptions s where s.tenant_id=pg_temp.fid('t')$$;
select pg_temp.actor('owner');
insert into w5_tap select throws_ok($$select pg_temp.reserve('client')$$,'42501','TRUSTED_WORKER_REQUIRED','Client usage claims cannot reserve allowance');
select pg_temp.worker();
insert into w5_tap select is(pg_temp.reserve('invocation')->>'reservedUnits','60','Trusted worker reserves exact allowance');
do $$begin for i in 1..100 loop perform pg_temp.reserve('invocation');end loop;end$$;
insert into w5_tap select is((select reserved_units::text from intelligence_control.quota_periods where tenant_id=pg_temp.fid('t')),'60','100 retries consume one reservation');
insert into w5_tap select throws_ok($$select pg_temp.reserve('invocation','61')$$,'22023','IDEMPOTENCY_MISMATCH','Changed retry amount rejected');
insert into w5_tap select throws_ok($$select pg_temp.reserve('other','41')$$,'54000','QUOTA_EXCEEDED','Hard allowance rejects excess before effect');
insert into w5_tap select is((select count(*) from intelligence_control.usage_reservations where tenant_id=pg_temp.fid('t')),1::bigint,'Denied reservation has no effect');
insert into w5_tap select throws_ok($$select api.wave5_reserve_usage(pg_temp.fid('t'),pg_temp.fid('period'),'ai.tokens',now()-interval '1 hour',now()+interval '1 hour','1')$$,
 '22023','PERIOD_CONFLICT','Caller cannot split an authoritative trial period');
insert into w5_tap select throws_ok($$select api.wave5_settle_usage(pg_temp.fid('t'),pg_temp.fid('invocation'),pg_temp.fid('event'),'61')$$,
 '54000','RESERVATION_EXCEEDED','Settlement cannot exceed reservation');
insert into w5_tap select is(api.wave5_settle_usage(pg_temp.fid('t'),pg_temp.fid('invocation'),pg_temp.fid('event'),'55')->>'quantity','55','Trusted exact usage settlement');
do $$begin for i in 1..100 loop perform api.wave5_settle_usage(pg_temp.fid('t'),pg_temp.fid('invocation'),pg_temp.fid('event'),'55');end loop;end$$;
insert into w5_tap select is((select count(*) from intelligence_control.usage_events where tenant_id=pg_temp.fid('t')),1::bigint,'100 settlements produce one append-only usage event');
insert into w5_tap select is((select settled_units::text||':'||reserved_units::text from intelligence_control.quota_periods where tenant_id=pg_temp.fid('t')),'55:0','Settlement releases only its reservation and records actual usage');
insert into w5_tap select throws_ok($$select api.wave5_settle_usage(pg_temp.fid('t'),pg_temp.fid('invocation'),pg_temp.fid('changed-event'),'55')$$,
 '22023','IDEMPOTENCY_MISMATCH','Different event cannot resettle invocation');
select api.wave5_correct_usage(pg_temp.fid('t'),pg_temp.fid('correction'),pg_temp.fid('event'),'5','provider_reconciled');
select api.wave5_correct_usage(pg_temp.fid('t'),pg_temp.fid('correction'),pg_temp.fid('event'),'5','provider_reconciled');
insert into w5_tap select is((select settled_units::text from intelligence_control.quota_periods where tenant_id=pg_temp.fid('t')),'50','Linked correction counted once');
insert into w5_tap select throws_ok($$select api.wave5_correct_usage(pg_temp.fid('t'),pg_temp.fid('excess-correction'),pg_temp.fid('event'),'51','provider_reconciled')$$,
 '22023','CORRECTION_EXCEEDED','Corrections cannot erase more than original usage');
insert into w5_tap select throws_ok($$update intelligence_control.usage_events set quantity=0 where tenant_id=pg_temp.fid('t')$$,'55000','IMMUTABLE_EVIDENCE','Usage history immutable');
insert into w5_tap select throws_ok($$delete from intelligence_control.usage_corrections where tenant_id=pg_temp.fid('t')$$,'55000','IMMUTABLE_EVIDENCE','Correction history immutable');
insert into w5_tap select is(pg_temp.reserve('unknown','50')->>'reservedUnits','50','Unknown provider outcome retains full reservation');
insert into w5_tap select throws_ok($$select pg_temp.reserve('excess-after-unknown','1')$$,'54000','QUOTA_EXCEEDED','Unknown outcome cannot release or duplicate allowance');
select pg_temp.actor('owner');
insert into w5_tap select is((api.get_wave5_usage_allowance(pg_temp.fid('t'),'ai.tokens',now())->>'remaining'),'0','Scoped billing read reports actual remaining zero');
select pg_temp.actor('outsider');
insert into w5_tap select throws_ok($$select api.get_wave5_usage_allowance(pg_temp.fid('t'),'ai.tokens',now())$$,'42501','Permission denied or multi-factor authentication required.','Foreign member cannot read aggregate usage');
select pg_temp.actor('owner');
insert into w5_tap select ok(not has_function_privilege('authenticated','api.wave5_reserve_usage(uuid,uuid,text,timestamptz,timestamptz,text)','execute'),'Client cannot execute trusted reserve RPC');
insert into w5_tap select ok(not has_table_privilege('authenticated','intelligence_control.usage_events','select'),'Private trusted usage ledger has no client bypass');
insert into w5_tap select ok((select bool_and(c.relrowsecurity and c.relforcerowsecurity) from pg_class c join pg_namespace n on n.oid=c.relnamespace
 where n.nspname='intelligence_control' and c.relkind='r'),'Every tenant-bearing metering table forces RLS');

select pg_temp.actor('owner');
insert into w5_tap select throws_ok($$select api.get_operator_health()$$,'42501','OPERATOR_ACCESS_REQUIRED','Tenant role does not grant operator authority');
select set_config('request.jwt.claims','{}',true);
insert into w5_tap select throws_ok($$select api.get_operator_health()$$,'42501','OPERATOR_ACCESS_REQUIRED','Anonymous cannot read health');
insert into intelligence_control.operators values(pg_temp.fid('reader'),true,true,false),(pg_temp.fid('outsider'),true,true,true);
select pg_temp.actor('reader');
insert into w5_tap select is((select count(*) from jsonb_array_elements(api.get_operator_health()->'probes') p where p->>'state'='unknown'),4::bigint,'Missing probes are unknown');
select set_config('request.jwt.claims',jsonb_build_object('sub',pg_temp.fid('reader'),'role','authenticated','aal','aal1')::text,true);
insert into w5_tap select throws_ok($$select api.get_operator_health()$$,'42501','OPERATOR_ACCESS_REQUIRED','Operator capability still requires live MFA');
select pg_temp.worker();
select api.record_wave5_health_probe(pg_temp.fid('probe'),null,'retry_count','0',now());
select api.record_wave5_health_probe(pg_temp.fid('probe'),null,'retry_count','0',now());
select api.record_wave5_health_probe(pg_temp.fid('stale-probe'),null,'worker_lag_seconds','100',now()-interval '6 minutes');
insert into w5_tap select throws_ok($$select api.record_wave5_health_probe(pg_temp.fid('probe'),null,'retry_count','1',now())$$,
 '22023','IDEMPOTENCY_MISMATCH','Changed probe retry rejected');
select pg_temp.actor('reader');
insert into w5_tap select is((select p->>'exactValue' from jsonb_array_elements(api.get_operator_health()->'probes') p where p->>'code'='retry_count'),'0','Observed zero is a real zero');
insert into w5_tap select is((select p->>'state' from jsonb_array_elements(api.get_operator_health()->'probes') p where p->>'code'='worker_lag_seconds'),'unknown','Stale probe does not imply health');
insert into w5_tap select throws_ok($$select api.get_operator_tenant_health(pg_temp.fid('t'),pg_temp.fid('no-grant'))$$,
 '42501','OPERATOR_ACCESS_REQUIRED','Operator cannot inspect selected tenant without exact grant');
select pg_temp.actor('outsider');
create temporary table w5_grant as select api.issue_operator_tenant_grant(pg_temp.fid('t'),pg_temp.fid('reader'),
 'Synthetic incident investigation',now()+interval '30 minutes',pg_temp.fid('grant-command')) receipt;
do $$begin for i in 1..100 loop perform api.issue_operator_tenant_grant(pg_temp.fid('t'),pg_temp.fid('reader'),
 'Synthetic incident investigation',now()+interval '30 minutes',pg_temp.fid('grant-command'));end loop;end$$;
insert into w5_tap select is((select count(*) from intelligence_control.operator_tenant_grants where tenant_id=pg_temp.fid('t')),1::bigint,'Duplicate grant command creates one immutable grant');
insert into w5_tap select is((select count(*) from core.command_receipts where tenant_id=pg_temp.fid('t') and command_name='operator.issue_grant'),1::bigint,'Grant reuses existing audited command receipts');
select pg_temp.actor('reader');
insert into w5_tap select ok(api.get_operator_tenant_health(pg_temp.fid('t'),(select receipt#>>'{entity,id}' from w5_grant)::uuid) is not null,'Exact current MFA grant authorizes bounded tenant health');
insert into w5_tap select is((select count(*) from intelligence_control.operator_access_events where tenant_id=pg_temp.fid('t')),1::bigint,'Every selected tenant access is recorded');
insert into w5_tap select throws_ok($$select api.get_operator_tenant_health(pg_temp.fid('foreign-tenant'),(select receipt#>>'{entity,id}' from w5_grant)::uuid)$$,
 '42501','OPERATOR_ACCESS_REQUIRED','Grant cannot cross tenants');
insert into intelligence_control.operator_tenant_grants(id,tenant_id,operator_id,issued_by,reason,issued_at,expires_at)
 values(pg_temp.fid('expired-grant'),pg_temp.fid('t'),pg_temp.fid('reader'),pg_temp.fid('outsider'),'Synthetic expired access',now()-interval '1 hour',now()-interval '1 second');
insert into w5_tap select throws_ok($$select api.get_operator_tenant_health(pg_temp.fid('t'),pg_temp.fid('expired-grant'))$$,
 '42501','OPERATOR_ACCESS_REQUIRED','Expired grant denied');
update intelligence_control.operators set active=false where actor_id=pg_temp.fid('reader');
insert into w5_tap select throws_ok($$select api.get_operator_tenant_health(pg_temp.fid('t'),(select receipt#>>'{entity,id}' from w5_grant)::uuid)$$,
 '42501','OPERATOR_ACCESS_REQUIRED','Operator revocation blocks still-current grant');
insert into w5_tap select throws_ok($$delete from intelligence_control.operator_access_events where tenant_id=pg_temp.fid('t')$$,
 '55000','IMMUTABLE_EVIDENCE','Operator access audit immutable');
insert into w5_tap select ok(not has_table_privilege('authenticated','intelligence_control.operators','select'),'Client cannot inspect or bootstrap operator authority');
insert into w5_tap select ok(not has_function_privilege('authenticated','api.record_wave5_health_probe(uuid,uuid,text,text,timestamptz)','execute'),'Client cannot manufacture trusted health');
select pg_temp.actor('owner');

insert into core.role_permissions(tenant_id,role_id,permission_code)
 select pg_temp.fid('t'),pg_temp.fid(x||'.role'),p from unnest(array['owner','reader']) x
 cross join unnest(array['ai.proposals.view','ai.proposals.manage','ai.proposals.approve','ai.proposals.execute','crm.opportunities.view']) p on conflict do nothing;
update billing.plan_entitlements set enabled=true where plan_code='starter' and entitlement_code='module.ai';
-- Synthetic factor metadata only, inside rollback; no real session or secret.
insert into auth.mfa_factors(id,user_id,factor_type,status,created_at,updated_at)
 values(pg_temp.fid('reader-factor'),pg_temp.fid('reader'),'totp','verified',now(),now());
select pg_temp.actor('owner');
create temporary table w5_ai_basis as select pg_temp.freeze('ai-basis') receipt;
insert into w5_tap select is(api.wave5_proposal_authorize(pg_temp.fid('t'),pg_temp.fid('e'),pg_temp.fid('b')),pg_temp.fid('owner'),'Proposal recovery binds actual actor');
create function pg_temp.proposal_command(cmd text,act text,payload jsonb) returns jsonb language sql as $$
 select api.wave5_proposal_command(pg_temp.fid('t'),pg_temp.fid('e'),pg_temp.fid('b'),pg_temp.fid(cmd),pg_temp.fid(cmd),now(),act,payload)$$;
create temporary table w5_proposal as select pg_temp.proposal_command('proposal-create','create',jsonb_build_object(
 'sourceId',(select receipt#>>'{entity,id}' from w5_ai_basis),'expiresAt',now()+interval '1 hour')) receipt;
create temporary table w5_proposal_wire as select api.get_wave5_proposal(pg_temp.fid('t'),pg_temp.fid('e'),pg_temp.fid('b'),
 (receipt#>>'{entity,id}')::uuid) result from w5_proposal;
insert into w5_tap select is((select result->>'origin' from w5_proposal_wire),'human','Human proposal never impersonates model output');
insert into w5_tap select is((select result->>'modelProvider' from w5_proposal_wire),'unavailable','Unconfigured model provider remains unavailable');
insert into w5_tap select ok((select result->>'parametersHash' ~ '^[0-9a-f]{64}$' from w5_proposal_wire),'Exact immutable proposal hash produced');
insert into w5_tap select is((api.get_ai_forecast_evidence(pg_temp.fid('t'),pg_temp.fid('e'),pg_temp.fid('b'),
 (select receipt#>>'{entity,id}' from w5_ai_basis)::uuid)->>'modelProvider'),'unavailable','Scoped retrieval does not invoke an absent model');
do $$begin for i in 1..100 loop perform pg_temp.proposal_command('proposal-create','create',jsonb_build_object(
 'sourceId',(select receipt#>>'{entity,id}' from w5_ai_basis),'expiresAt',now()+interval '1 hour'));end loop;end$$;
insert into w5_tap select is((select count(*) from intelligence_control.proposals where tenant_id=pg_temp.fid('t')),1::bigint,'100 creation retries produce one proposal');
insert into w5_tap select throws_ok($$select pg_temp.proposal_command('arbitrary','create',jsonb_build_object('sourceId',(select receipt#>>'{entity,id}' from w5_ai_basis),
 'expiresAt',now()+interval '1 hour','commandCode','arbitrary.sql'))$$,'22023','VALIDATION_ERROR','Unallowlisted executable parameters rejected');
insert into w5_tap select throws_ok($$select pg_temp.proposal_command('self-approve','decide',jsonb_build_object('proposalId',(select receipt#>>'{entity,id}' from w5_proposal),
 'parametersHash',(select receipt#>>'{entity,parametersHash}' from w5_proposal),'decision','approved'))$$,
 '42501','DISTINCT_APPROVER_REQUIRED','Proposer cannot approve own mutation');
select pg_temp.actor('reader');
insert into w5_tap select throws_ok($$select pg_temp.proposal_command('wrong-hash','decide',jsonb_build_object('proposalId',(select receipt#>>'{entity,id}' from w5_proposal),
 'parametersHash',repeat('b',64),'decision','approved'))$$,'22023','APPROVAL_HASH_MISMATCH','Approval binds exact submitted parameters');
select set_config('request.jwt.claims',jsonb_build_object('sub',pg_temp.fid('reader'),'role','authenticated','aal','aal1')::text,true);
insert into w5_tap select throws_ok($$select pg_temp.proposal_command('weak-mfa','decide',jsonb_build_object('proposalId',(select receipt#>>'{entity,id}' from w5_proposal),
 'parametersHash',(select receipt#>>'{entity,parametersHash}' from w5_proposal),'decision','approved'))$$,
 '42501','APPROVAL_REQUIRED','Approval requires online MFA assurance');
select pg_temp.actor('reader');
insert into w5_tap select is(pg_temp.proposal_command('approve','decide',jsonb_build_object('proposalId',(select receipt#>>'{entity,id}' from w5_proposal),
 'parametersHash',(select receipt#>>'{entity,parametersHash}' from w5_proposal),'decision','approved'))#>>'{entity,state}',
 'approved','Distinct authorized human approves exact revision');
select pg_temp.actor('owner');
insert into w5_tap select is(pg_temp.proposal_command('execute','execute',jsonb_build_object('proposalId',(select receipt#>>'{entity,id}' from w5_proposal)))#>>'{entity,state}',
 'executed','Execution dispatches through existing forecast command');
do $$begin for i in 1..100 loop perform pg_temp.proposal_command('execute','execute',jsonb_build_object('proposalId',(select receipt#>>'{entity,id}' from w5_proposal)));end loop;end$$;
insert into w5_tap select is((select count(*) from intelligence_control.proposal_executions where tenant_id=pg_temp.fid('t')),1::bigint,'100 execution retries produce one business invocation');
insert into w5_tap select is((select count(*) from analytics.pipeline_forecasts where tenant_id=pg_temp.fid('t')),3::bigint,'Only baseline, proposal basis and one execution forecast exist');
insert into w5_tap select throws_ok($$update intelligence_control.proposals set targets='{}' where tenant_id=pg_temp.fid('t')$$,
 '55000','IMMUTABLE_EVIDENCE','Submitted proposal cannot inherit approval after editing');
delete from auth.mfa_factors where id=pg_temp.fid('reader-factor');
insert into w5_tap select throws_ok($$select pg_temp.proposal_command('revoked-mfa-execute','execute',jsonb_build_object('proposalId',(select receipt#>>'{entity,id}' from w5_proposal)))$$,
 '42501','APPROVAL_REQUIRED','Revoked approver MFA blocks fresh execution requests');
insert into auth.mfa_factors(id,user_id,factor_type,status,created_at,updated_at)
 values(pg_temp.fid('reader-factor'),pg_temp.fid('reader'),'totp','verified',now(),now());
create temporary table w5_stale_proposal as select pg_temp.proposal_command('stale-create','create',jsonb_build_object(
 'sourceId',(select receipt#>>'{entity,id}' from w5_ai_basis),'expiresAt',now()+interval '1 hour')) receipt;
select pg_temp.actor('reader');
select pg_temp.proposal_command('stale-approve','decide',jsonb_build_object('proposalId',(select receipt#>>'{entity,id}' from w5_stale_proposal),
 'parametersHash',(select receipt#>>'{entity,parametersHash}' from w5_stale_proposal),'decision','approved'));
select pg_temp.actor('owner');
update crm.opportunities set expected_value=1000 where id=pg_temp.fid('o');
insert into w5_tap select throws_ok($$select pg_temp.proposal_command('stale-execute','execute',jsonb_build_object('proposalId',(select receipt#>>'{entity,id}' from w5_stale_proposal)))$$,
 '40001','TARGET_SOURCE_CHANGED','Changed live source revision invalidates execution');
insert into w5_tap select is((select count(*) from analytics.pipeline_forecasts where tenant_id=pg_temp.fid('t')),3::bigint,'Rejected stale execution has no business effect');
insert into w5_tap select ok(not has_table_privilege('authenticated','intelligence_control.proposal_decisions','insert'),'Client cannot forge stored approval');
insert into w5_tap select ok(not has_function_privilege('anon','api.wave5_proposal_command(uuid,uuid,uuid,uuid,uuid,timestamptz,text,jsonb)','execute'),'Anonymous cannot dispatch proposals');

-- Independent synthetic tenant. Every row and authority change is rolled back.
select pg_temp.actor('owner');
insert into core.tenants(id,name,slug,created_by) values(pg_temp.fid('billing-t'),'Synthetic Billing','wave5-billing-synthetic',pg_temp.fid('owner'));
insert into billing.tenant_subscriptions(tenant_id,plan_code,status,seats) values(pg_temp.fid('billing-t'),'starter','active',5);
insert into core.memberships(id,tenant_id,user_id,status) values(pg_temp.fid('billing-member'),pg_temp.fid('billing-t'),pg_temp.fid('owner'),'active');
insert into core.roles(id,tenant_id,code,name,requires_mfa) values(pg_temp.fid('billing-role'),pg_temp.fid('billing-t'),'synthetic-admin','Synthetic billing administrator',true);
insert into core.role_permissions values(pg_temp.fid('billing-t'),pg_temp.fid('billing-role'),'billing.synthetic.manage');
insert into core.role_permissions values(pg_temp.fid('billing-t'),pg_temp.fid('billing-role'),'billing.read');
insert into core.role_assignments(tenant_id,membership_id,role_id,created_by) values(pg_temp.fid('billing-t'),pg_temp.fid('billing-member'),pg_temp.fid('billing-role'),pg_temp.fid('owner'));
insert into auth.mfa_factors(id,user_id,factor_type,status,created_at,updated_at) values(pg_temp.fid('owner-factor'),pg_temp.fid('owner'),'totp','verified',now(),now());
create function pg_temp.schedule_trial(cmd text,seat_count integer default 2,starts timestamptz default now()) returns jsonb language sql as $$
 select api.schedule_synthetic_subscription(pg_temp.fid('billing-t'),pg_temp.fid(cmd),pg_temp.fid(cmd),now(),1,'starter',seat_count,starts,starts+interval '1 day')$$;
insert into w5_tap select throws_ok($$select pg_temp.schedule_trial('trial')$$,'42501','SYNTHETIC_TARGET_REQUIRED','No tenant is automatically allowlisted');
insert into intelligence_control.synthetic_tenants values(pg_temp.fid('billing-t'),true);
insert into w5_tap select is(api.wave5_subscription_authorize(pg_temp.fid('billing-t')),pg_temp.fid('owner'),'Subscription recovery binds actual MFA actor');
insert into w5_tap select is(api.get_wave5_subscription(pg_temp.fid('billing-t'))->>'version','1','Native subscription read preserves exact revision');
select set_config('request.jwt.claims',jsonb_build_object('sub',pg_temp.fid('owner'),'role','authenticated','aal','aal1')::text,true);
insert into w5_tap select throws_ok($$select pg_temp.schedule_trial('trial')$$,'42501','Permission denied or multi-factor authentication required.','Synthetic changes need privileged MFA');
select pg_temp.actor('owner');
create temporary table w5_trial as select pg_temp.schedule_trial('trial') receipt;
do $$begin for i in 1..100 loop perform pg_temp.schedule_trial('trial');end loop;end$$;
insert into w5_tap select is((select count(*) from intelligence_control.subscription_revisions where tenant_id=pg_temp.fid('billing-t')),1::bigint,'100 schedule retries produce one immutable revision');
insert into w5_tap select is((select status from billing.tenant_subscriptions where tenant_id=pg_temp.fid('billing-t')),'active','Scheduling does not activate a trial');
insert into w5_tap select throws_ok($$select pg_temp.schedule_trial('trial',3)$$,'22023','IDEMPOTENCY_MISMATCH','Changed subscription retry denied');
create temporary table w5_future_trial as select pg_temp.schedule_trial('future',2,now()+interval '1 day') receipt;
select pg_temp.worker();
insert into w5_tap select throws_ok($$select api.apply_synthetic_subscription(pg_temp.fid('billing-t'),(select receipt#>>'{entity,id}' from w5_future_trial)::uuid)$$,'22023','NOT_EFFECTIVE','Future trial does not activate early');
delete from auth.mfa_factors where id=pg_temp.fid('owner-factor');
insert into w5_tap select throws_ok($$select api.apply_synthetic_subscription(pg_temp.fid('billing-t'),(select receipt#>>'{entity,id}' from w5_trial)::uuid)$$,'42501','PERMISSION_DENIED','Worker rechecks live privileged actor MFA');
insert into auth.mfa_factors(id,user_id,factor_type,status,created_at,updated_at) values(pg_temp.fid('owner-factor'),pg_temp.fid('owner'),'totp','verified',now(),now());
create temporary table w5_trial_activation as select api.apply_synthetic_subscription(pg_temp.fid('billing-t'),(select receipt#>>'{entity,id}' from w5_trial)::uuid) result;
do $$begin for i in 1..100 loop perform api.apply_synthetic_subscription(pg_temp.fid('billing-t'),(select receipt#>>'{entity,id}' from w5_trial)::uuid);end loop;end$$;
insert into w5_tap select is((select count(*) from intelligence_control.subscription_activations where tenant_id=pg_temp.fid('billing-t')),1::bigint,'100 worker retries activate once');
insert into w5_tap select is((select version from billing.tenant_subscriptions where tenant_id=pg_temp.fid('billing-t')),2::bigint,'Existing billing row has one optimistic revision increment');
insert into w5_tap select is((select status from billing.tenant_subscriptions where tenant_id=pg_temp.fid('billing-t')),'trialing','Explicit synthetic trial is authoritative');
insert into w5_tap select ok((select trial_started_at=now() and trial_ends_at=now()+interval '1 day' from billing.tenant_subscriptions where tenant_id=pg_temp.fid('billing-t')),'Trial preserves exact explicit half-open dates');
insert into w5_tap select is((select count(*) from core.command_receipts where tenant_id=pg_temp.fid('billing-t') and command_name='billing.synthetic.activate'),1::bigint,'Activation retains one existing authoritative receipt');
insert into w5_tap select is((select count(*) from audit.events where tenant_id=pg_temp.fid('billing-t') and event_type='billing.synthetic.activate'),1::bigint,'Activation records original actor and trusted worker audit');
insert into core.memberships(id,tenant_id,user_id,status) values(pg_temp.fid('billing-reader'),pg_temp.fid('billing-t'),pg_temp.fid('reader'),'active');
insert into w5_tap select throws_ok($$insert into core.memberships(id,tenant_id,user_id,status) values(pg_temp.fid('billing-outsider'),pg_temp.fid('billing-t'),pg_temp.fid('outsider'),'active')$$,'54000','SEAT_QUOTA_EXCEEDED','Seat admission checks existing authoritative cap');
insert into w5_tap select throws_ok($$update intelligence_control.subscription_revisions set seats=3 where tenant_id=pg_temp.fid('billing-t')$$,'55000','IMMUTABLE_EVIDENCE','Effective decision revisions cannot be edited');
insert into w5_tap select ok(not has_function_privilege('authenticated','api.apply_synthetic_subscription(uuid,uuid)','execute'),'Desktop cannot impersonate subscription worker');
insert into w5_tap select ok(not has_table_privilege('authenticated','intelligence_control.synthetic_tenants','insert'),'Client cannot allowlist real subscriptions');
update billing.plan_entitlements set enabled=true,numeric_limit=100 where plan_code='starter' and entitlement_code='quota.ai.tokens';
insert into w5_tap select ok(api.wave5_reserve_usage(pg_temp.fid('billing-t'),pg_temp.fid('billing-usage'),'ai.tokens',now(),now()+interval '1 day','1') is not null,'Metering uses explicit trial start instead of row creation');
select pg_temp.actor('owner');
insert into w5_tap select throws_ok($$select pg_temp.schedule_trial('stale')$$,'40001','VERSION_CONFLICT','Stale expected billing version denied');
create temporary table w5_subscription_wire as select api.get_wave5_subscription(pg_temp.fid('billing-t')) result;
select pg_temp.worker();
insert into w5_tap select is((select count(*) from core.memberships where tenant_id=pg_temp.fid('billing-t')),2::bigint,'Denied admission has zero membership effect');

select * from finish(true);
select jsonb_agg(message) tap from w5_tap;
rollback;
