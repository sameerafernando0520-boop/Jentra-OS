-- DIAGNOSTIC ONLY: simulated service-role request context, no provider I/O.
-- All effects, including a possible invocation insert, are rolled back.
begin;
set local statement_timeout = '10s';
create temporary table w5_model_begin_diagnostic (result jsonb) on commit drop;
do $diagnostic$
declare payload jsonb; answer jsonb; failure_state text; failure_message text; failure_detail text; failure_context text;
begin
  perform set_config('request.jwt.claims', '{"role":"service_role"}', true);
  perform set_config('request.jwt.claim.role', 'service_role', true);
  payload := '{"sourceId":"38742ecf-91fe-4cd3-93c5-9d6f726a59e5","scope":{"tenantId":"babe6c86-a764-4d3a-80a3-952a7c096c2c","legalEntityId":"caa2bb06-219a-47e9-8132-66d1271b0ffd","branchId":"3813692c-f0de-4c69-8e34-d56cf54695b1"},"invocationId":"bf887435-88db-4a1f-9df9-2e9ec326f9b4","usageEventId":"287f1f6a-fe5d-4cfe-aec0-bbe710eb8e9d","maxTokens":"2000","periodStart":"2026-11-02T20:14:41.000000Z","periodEnd":"2026-11-02T20:44:41.000000Z","tenantId":"babe6c86-a764-4d3a-80a3-952a7c096c2c","sourceHash":"0e9255bd3871c3ee8130ec94af09d1e21c4ec73191d8ade81f23923f21ca1e47","manifestHash":"0000000000000000000000000000000000000000000000000000000000000000","policyRevision":1}'::jsonb;
  begin
    answer := api.wave5_runtime_worker('778237e3-3d4e-4871-8cc9-e08b07b989c7', 'model.begin', payload);
    insert into pg_temp.w5_model_begin_diagnostic values(jsonb_build_object('succeeded',true,'response',answer));
  exception when others then
    get stacked diagnostics failure_state = returned_sqlstate, failure_message = message_text, failure_detail = pg_exception_detail, failure_context = pg_exception_context;
    insert into pg_temp.w5_model_begin_diagnostic values(jsonb_build_object('succeeded',false,'sqlState',failure_state,'message',failure_message,'detail',failure_detail,'context',failure_context));
  end;
end
$diagnostic$;
select jsonb_build_object('kind','rollback-only-model-begin-diagnostic','observedAt',statement_timestamp(),'simulatedServiceRole',true,'genuineAuthAcceptance',false,'providerRequests',0,'willRollback',true,'result',result) as diagnostic from pg_temp.w5_model_begin_diagnostic;
rollback;
