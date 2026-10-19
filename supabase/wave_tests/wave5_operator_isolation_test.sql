select pg_temp.actor('owner');
select throws_ok($$select api.get_operator_health()$$,'42501','OPERATOR_ACCESS_REQUIRED','Tenant role does not grant operator authority');
select set_config('request.jwt.claims','{}',true);
select throws_ok($$select api.get_operator_health()$$,'42501','OPERATOR_ACCESS_REQUIRED','Anonymous cannot read health');
insert into intelligence_control.operators values(pg_temp.fid('reader'),true,true,false),(pg_temp.fid('outsider'),true,true,true);
select pg_temp.actor('reader');
select is((select count(*) from jsonb_array_elements(api.get_operator_health()->'probes') p where p->>'state'='unknown'),4::bigint,'Missing probes are unknown');
select set_config('request.jwt.claims',jsonb_build_object('sub',pg_temp.fid('reader'),'role','authenticated','aal','aal1')::text,true);
select throws_ok($$select api.get_operator_health()$$,'42501','OPERATOR_ACCESS_REQUIRED','Operator capability still requires live MFA');
select pg_temp.worker();
select api.record_wave5_health_probe(pg_temp.fid('probe'),null,'retry_count','0',now());
select api.record_wave5_health_probe(pg_temp.fid('probe'),null,'retry_count','0',now());
select api.record_wave5_health_probe(pg_temp.fid('stale-probe'),null,'worker_lag_seconds','100',now()-interval '6 minutes');
select throws_ok($$select api.record_wave5_health_probe(pg_temp.fid('probe'),null,'retry_count','1',now())$$,
 '22023','IDEMPOTENCY_MISMATCH','Changed probe retry rejected');
select pg_temp.actor('reader');
select is((select p->>'exactValue' from jsonb_array_elements(api.get_operator_health()->'probes') p where p->>'code'='retry_count'),'0','Observed zero is a real zero');
select is((select p->>'state' from jsonb_array_elements(api.get_operator_health()->'probes') p where p->>'code'='worker_lag_seconds'),'unknown','Stale probe does not imply health');
select throws_ok($$select api.get_operator_tenant_health(pg_temp.fid('t'),pg_temp.fid('no-grant'))$$,
 '42501','OPERATOR_ACCESS_REQUIRED','Operator cannot inspect selected tenant without exact grant');
select pg_temp.actor('outsider');
create temporary table w5_grant as select api.issue_operator_tenant_grant(pg_temp.fid('t'),pg_temp.fid('reader'),
 'Synthetic incident investigation',now()+interval '30 minutes',pg_temp.fid('grant-command')) receipt;
do $$begin for i in 1..100 loop perform api.issue_operator_tenant_grant(pg_temp.fid('t'),pg_temp.fid('reader'),
 'Synthetic incident investigation',now()+interval '30 minutes',pg_temp.fid('grant-command'));end loop;end$$;
select is((select count(*) from intelligence_control.operator_tenant_grants where tenant_id=pg_temp.fid('t')),1::bigint,'Duplicate grant command creates one immutable grant');
select is((select count(*) from core.command_receipts where tenant_id=pg_temp.fid('t') and command_name='operator.issue_grant'),1::bigint,'Grant reuses existing audited command receipts');
select pg_temp.actor('reader');
select ok(api.get_operator_tenant_health(pg_temp.fid('t'),(select receipt#>>'{entity,id}' from w5_grant)::uuid) is not null,'Exact current MFA grant authorizes bounded tenant health');
select is((select count(*) from intelligence_control.operator_access_events where tenant_id=pg_temp.fid('t')),1::bigint,'Every selected tenant access is recorded');
select throws_ok($$select api.get_operator_tenant_health(pg_temp.fid('foreign-tenant'),(select receipt#>>'{entity,id}' from w5_grant)::uuid)$$,
 '42501','OPERATOR_ACCESS_REQUIRED','Grant cannot cross tenants');
insert into intelligence_control.operator_tenant_grants(id,tenant_id,operator_id,issued_by,reason,issued_at,expires_at)
 values(pg_temp.fid('expired-grant'),pg_temp.fid('t'),pg_temp.fid('reader'),pg_temp.fid('outsider'),'Synthetic expired access',now()-interval '1 hour',now()-interval '1 second');
select throws_ok($$select api.get_operator_tenant_health(pg_temp.fid('t'),pg_temp.fid('expired-grant'))$$,
 '42501','OPERATOR_ACCESS_REQUIRED','Expired grant denied');
update intelligence_control.operators set active=false where actor_id=pg_temp.fid('reader');
select throws_ok($$select api.get_operator_tenant_health(pg_temp.fid('t'),(select receipt#>>'{entity,id}' from w5_grant)::uuid)$$,
 '42501','OPERATOR_ACCESS_REQUIRED','Operator revocation blocks still-current grant');
select throws_ok($$delete from intelligence_control.operator_access_events where tenant_id=pg_temp.fid('t')$$,
 '55000','IMMUTABLE_EVIDENCE','Operator access audit immutable');
select ok(not has_table_privilege('authenticated','intelligence_control.operators','select'),'Client cannot inspect or bootstrap operator authority');
select ok(not has_function_privilege('authenticated','api.record_wave5_health_probe(uuid,uuid,text,text,timestamptz)','execute'),'Client cannot manufacture trusted health');
select pg_temp.actor('owner');
