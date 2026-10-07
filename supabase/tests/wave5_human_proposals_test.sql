insert into core.role_permissions(tenant_id,role_id,permission_code)
 select pg_temp.fid('t'),pg_temp.fid(x||'.role'),p from unnest(array['owner','reader']) x
 cross join unnest(array['ai.proposals.view','ai.proposals.manage','ai.proposals.approve','ai.proposals.execute','crm.opportunities.view']) p on conflict do nothing;
update billing.plan_entitlements set enabled=true where plan_code='starter' and entitlement_code='module.ai';
-- Synthetic factor metadata only, inside rollback; no real session or secret.
insert into auth.mfa_factors(id,user_id,factor_type,status,created_at,updated_at)
 values(pg_temp.fid('reader-factor'),pg_temp.fid('reader'),'totp','verified',now(),now());
select pg_temp.actor('owner');
create temporary table w5_ai_basis as select pg_temp.freeze('ai-basis') receipt;
select is(api.wave5_proposal_authorize(pg_temp.fid('t'),pg_temp.fid('e'),pg_temp.fid('b')),pg_temp.fid('owner'),'Proposal recovery binds actual actor');
create function pg_temp.proposal_command(cmd text,act text,payload jsonb) returns jsonb language sql as $$
 select api.wave5_proposal_command(pg_temp.fid('t'),pg_temp.fid('e'),pg_temp.fid('b'),pg_temp.fid(cmd),pg_temp.fid(cmd),now(),act,payload)$$;
create temporary table w5_proposal as select pg_temp.proposal_command('proposal-create','create',jsonb_build_object(
 'sourceId',(select receipt#>>'{entity,id}' from w5_ai_basis),'expiresAt',now()+interval '1 hour')) receipt;
create temporary table w5_proposal_wire as select api.get_wave5_proposal(pg_temp.fid('t'),pg_temp.fid('e'),pg_temp.fid('b'),
 (receipt#>>'{entity,id}')::uuid) result from w5_proposal;
select is((select result->>'origin' from w5_proposal_wire),'human','Human proposal never impersonates model output');
select is((select result->>'modelProvider' from w5_proposal_wire),'unavailable','Unconfigured model provider remains unavailable');
select ok((select result->>'parametersHash' ~ '^[0-9a-f]{64}$' from w5_proposal_wire),'Exact immutable proposal hash produced');
select is((api.get_ai_forecast_evidence(pg_temp.fid('t'),pg_temp.fid('e'),pg_temp.fid('b'),
 (select receipt#>>'{entity,id}' from w5_ai_basis)::uuid)->>'modelProvider'),'unavailable','Scoped retrieval does not invoke an absent model');
do $$begin for i in 1..100 loop perform pg_temp.proposal_command('proposal-create','create',jsonb_build_object(
 'sourceId',(select receipt#>>'{entity,id}' from w5_ai_basis),'expiresAt',now()+interval '1 hour'));end loop;end$$;
select is((select count(*) from intelligence_control.proposals where tenant_id=pg_temp.fid('t')),1::bigint,'100 creation retries produce one proposal');
select throws_ok($$select pg_temp.proposal_command('arbitrary','create',jsonb_build_object('sourceId',(select receipt#>>'{entity,id}' from w5_ai_basis),
 'expiresAt',now()+interval '1 hour','commandCode','arbitrary.sql'))$$,'22023','VALIDATION_ERROR','Unallowlisted executable parameters rejected');
select throws_ok($$select pg_temp.proposal_command('self-approve','decide',jsonb_build_object('proposalId',(select receipt#>>'{entity,id}' from w5_proposal),
 'parametersHash',(select receipt#>>'{entity,parametersHash}' from w5_proposal),'decision','approved'))$$,
 '42501','DISTINCT_APPROVER_REQUIRED','Proposer cannot approve own mutation');
select pg_temp.actor('reader');
select throws_ok($$select pg_temp.proposal_command('wrong-hash','decide',jsonb_build_object('proposalId',(select receipt#>>'{entity,id}' from w5_proposal),
 'parametersHash',repeat('b',64),'decision','approved'))$$,'22023','APPROVAL_HASH_MISMATCH','Approval binds exact submitted parameters');
select set_config('request.jwt.claims',jsonb_build_object('sub',pg_temp.fid('reader'),'role','authenticated','aal','aal1')::text,true);
select throws_ok($$select pg_temp.proposal_command('weak-mfa','decide',jsonb_build_object('proposalId',(select receipt#>>'{entity,id}' from w5_proposal),
 'parametersHash',(select receipt#>>'{entity,parametersHash}' from w5_proposal),'decision','approved'))$$,
 '42501','APPROVAL_REQUIRED','Approval requires online MFA assurance');
select pg_temp.actor('reader');
select is(pg_temp.proposal_command('approve','decide',jsonb_build_object('proposalId',(select receipt#>>'{entity,id}' from w5_proposal),
 'parametersHash',(select receipt#>>'{entity,parametersHash}' from w5_proposal),'decision','approved'))#>>'{entity,state}',
 'approved','Distinct authorized human approves exact revision');
select pg_temp.actor('owner');
select is(pg_temp.proposal_command('execute','execute',jsonb_build_object('proposalId',(select receipt#>>'{entity,id}' from w5_proposal)))#>>'{entity,state}',
 'executed','Execution dispatches through existing forecast command');
do $$begin for i in 1..100 loop perform pg_temp.proposal_command('execute','execute',jsonb_build_object('proposalId',(select receipt#>>'{entity,id}' from w5_proposal)));end loop;end$$;
select is((select count(*) from intelligence_control.proposal_executions where tenant_id=pg_temp.fid('t')),1::bigint,'100 execution retries produce one business invocation');
select is((select count(*) from analytics.pipeline_forecasts where tenant_id=pg_temp.fid('t')),3::bigint,'Only baseline, proposal basis and one execution forecast exist');
select throws_ok($$update intelligence_control.proposals set targets='{}' where tenant_id=pg_temp.fid('t')$$,
 '55000','IMMUTABLE_EVIDENCE','Submitted proposal cannot inherit approval after editing');
delete from auth.mfa_factors where id=pg_temp.fid('reader-factor');
select throws_ok($$select pg_temp.proposal_command('revoked-mfa-execute','execute',jsonb_build_object('proposalId',(select receipt#>>'{entity,id}' from w5_proposal)))$$,
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
select throws_ok($$select pg_temp.proposal_command('stale-execute','execute',jsonb_build_object('proposalId',(select receipt#>>'{entity,id}' from w5_stale_proposal)))$$,
 '40001','TARGET_SOURCE_CHANGED','Changed live source revision invalidates execution');
select is((select count(*) from analytics.pipeline_forecasts where tenant_id=pg_temp.fid('t')),3::bigint,'Rejected stale execution has no business effect');
select ok(not has_table_privilege('authenticated','intelligence_control.proposal_decisions','insert'),'Client cannot forge stored approval');
select ok(not has_function_privilege('anon','api.wave5_proposal_command(uuid,uuid,uuid,uuid,uuid,timestamptz,text,jsonb)','execute'),'Anonymous cannot dispatch proposals');
