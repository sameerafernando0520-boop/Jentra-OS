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
select throws_ok($$select pg_temp.reserve('client')$$,'42501','TRUSTED_WORKER_REQUIRED','Client usage claims cannot reserve allowance');
select pg_temp.worker();
select is(pg_temp.reserve('invocation')->>'reservedUnits','60','Trusted worker reserves exact allowance');
do $$begin for i in 1..100 loop perform pg_temp.reserve('invocation');end loop;end$$;
select is((select reserved_units::text from intelligence_control.quota_periods where tenant_id=pg_temp.fid('t')),'60','100 retries consume one reservation');
select throws_ok($$select pg_temp.reserve('invocation','61')$$,'22023','IDEMPOTENCY_MISMATCH','Changed retry amount rejected');
select throws_ok($$select pg_temp.reserve('other','41')$$,'54000','QUOTA_EXCEEDED','Hard allowance rejects excess before effect');
select is((select count(*) from intelligence_control.usage_reservations where tenant_id=pg_temp.fid('t')),1::bigint,'Denied reservation has no effect');
select throws_ok($$select api.wave5_reserve_usage(pg_temp.fid('t'),pg_temp.fid('period'),'ai.tokens',now()-interval '1 hour',now()+interval '1 hour','1')$$,
 '22023','PERIOD_CONFLICT','Caller cannot split an authoritative trial period');
select throws_ok($$select api.wave5_settle_usage(pg_temp.fid('t'),pg_temp.fid('invocation'),pg_temp.fid('event'),'61')$$,
 '54000','RESERVATION_EXCEEDED','Settlement cannot exceed reservation');
select is(api.wave5_settle_usage(pg_temp.fid('t'),pg_temp.fid('invocation'),pg_temp.fid('event'),'55')->>'quantity','55','Trusted exact usage settlement');
do $$begin for i in 1..100 loop perform api.wave5_settle_usage(pg_temp.fid('t'),pg_temp.fid('invocation'),pg_temp.fid('event'),'55');end loop;end$$;
select is((select count(*) from intelligence_control.usage_events where tenant_id=pg_temp.fid('t')),1::bigint,'100 settlements produce one append-only usage event');
select is((select settled_units::text||':'||reserved_units::text from intelligence_control.quota_periods where tenant_id=pg_temp.fid('t')),'55:0','Settlement releases only its reservation and records actual usage');
select throws_ok($$select api.wave5_settle_usage(pg_temp.fid('t'),pg_temp.fid('invocation'),pg_temp.fid('changed-event'),'55')$$,
 '22023','IDEMPOTENCY_MISMATCH','Different event cannot resettle invocation');
select api.wave5_correct_usage(pg_temp.fid('t'),pg_temp.fid('correction'),pg_temp.fid('event'),'5','provider_reconciled');
select api.wave5_correct_usage(pg_temp.fid('t'),pg_temp.fid('correction'),pg_temp.fid('event'),'5','provider_reconciled');
select is((select settled_units::text from intelligence_control.quota_periods where tenant_id=pg_temp.fid('t')),'50','Linked correction counted once');
select throws_ok($$select api.wave5_correct_usage(pg_temp.fid('t'),pg_temp.fid('excess-correction'),pg_temp.fid('event'),'51','provider_reconciled')$$,
 '22023','CORRECTION_EXCEEDED','Corrections cannot erase more than original usage');
select throws_ok($$update intelligence_control.usage_events set quantity=0 where tenant_id=pg_temp.fid('t')$$,'55000','IMMUTABLE_EVIDENCE','Usage history immutable');
select throws_ok($$delete from intelligence_control.usage_corrections where tenant_id=pg_temp.fid('t')$$,'55000','IMMUTABLE_EVIDENCE','Correction history immutable');
select is(pg_temp.reserve('unknown','50')->>'reservedUnits','50','Unknown provider outcome retains full reservation');
select throws_ok($$select pg_temp.reserve('excess-after-unknown','1')$$,'54000','QUOTA_EXCEEDED','Unknown outcome cannot release or duplicate allowance');
select pg_temp.actor('owner');
select is((api.get_wave5_usage_allowance(pg_temp.fid('t'),'ai.tokens',now())->>'remaining'),'0','Scoped billing read reports actual remaining zero');
select pg_temp.actor('outsider');
select throws_ok($$select api.get_wave5_usage_allowance(pg_temp.fid('t'),'ai.tokens',now())$$,'42501','Permission denied or multi-factor authentication required.','Foreign member cannot read aggregate usage');
select pg_temp.actor('owner');
select ok(not has_function_privilege('authenticated','api.wave5_reserve_usage(uuid,uuid,text,timestamptz,timestamptz,text)','execute'),'Client cannot execute trusted reserve RPC');
select ok(not has_table_privilege('authenticated','intelligence_control.usage_events','select'),'Private trusted usage ledger has no client bypass');
select ok((select bool_and(c.relrowsecurity and c.relforcerowsecurity) from pg_class c join pg_namespace n on n.oid=c.relnamespace
 where n.nspname='intelligence_control' and c.relkind='r'),'Every tenant-bearing metering table forces RLS');
