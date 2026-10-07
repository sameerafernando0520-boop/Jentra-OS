-- Compose after the existing process fixture, before its finish(true).
select is(api.analytics_pipeline_authorize(pg_temp.fid('t'),pg_temp.fid('e'),pg_temp.fid('b')),pg_temp.fid('owner'),'Forecast recovery binds actual actor');
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
select is((select result#>>'{evidence,sourceCount}' from w5_frozen),'3','Complete open opportunity cohort frozen');
select is((select jsonb_array_length(result#>'{evidence,currencies}') from w5_frozen),2,'Currencies remain separate');
select is((select c->>'weightedAmount' from w5_frozen,jsonb_array_elements(result#>'{evidence,currencies}') c
 where c->>'currency'='LKR'),'10.000002','Exact per-opportunity half-away rounding precedes sum');
select is((select c->>'weightedAmount' from w5_frozen,jsonb_array_elements(result#>'{evidence,currencies}') c
 where c->>'currency'='USD'),'5.000001','USD forecast is never added to LKR');
select ok((select result::text like '%9007199254740993%' from w5_frozen),'Huge source revisions remain decimal strings');
select ok((select result::text not like '%prospect%' and result::text not like '%ownerId%' and result::text not like '%won_loss_reason%' from w5_frozen),'Names and private free text omitted');
select is((select result#>>'{evidence,unavailable,accuracy}' from w5_frozen),'REALIZED_MAPPING_UNAVAILABLE','Accuracy lacks realized cohort mapping');
select is((select result->>'sourceHash' from w5_frozen),
 (select encode(extensions.digest(convert_to(result->>'canonicalText','UTF8'),'sha256'),'hex') from w5_frozen),'Captured bytes bind complete evidence');
select is(pg_temp.freeze(),(select receipt from w5_forecast),'Identical retry reuses original receipt');
do $$begin for i in 1..100 loop perform pg_temp.freeze();end loop;end $$;
select is((select count(*) from analytics.pipeline_forecasts where tenant_id=pg_temp.fid('t')),1::bigint,'100 duplicate requests produce one frozen aggregate');
select is((select count(*) from core.command_receipts where tenant_id=pg_temp.fid('t') and command_name='analytics.freeze_pipeline'),1::bigint,'100 duplicate requests produce one command receipt');
select throws_ok($$select pg_temp.freeze('forecast','2026-12-01')$$,'22023','IDEMPOTENCY_MISMATCH','Changed retry payload denied');
update crm.opportunities set expected_value=999,probability=1,version=version+1 where id=pg_temp.fid('o');
select is((api.get_pipeline_forecast(pg_temp.fid('t'),pg_temp.fid('e'),pg_temp.fid('b'),
 (select receipt#>>'{entity,id}' from w5_forecast)::uuid)->>'sourceHash'),(select result->>'sourceHash' from w5_frozen),'Later source edits cannot change frozen evidence');
select throws_ok($$update analytics.pipeline_forecasts set evidence='{}' where tenant_id=pg_temp.fid('t')$$,
 '55000','IMMUTABLE_EVIDENCE','Frozen aggregate cannot be overwritten');
select throws_ok($$delete from analytics.pipeline_forecasts where tenant_id=pg_temp.fid('t')$$,
 '55000','IMMUTABLE_EVIDENCE','Frozen aggregate cannot be deleted');
select throws_ok($$select api.get_pipeline_forecast(pg_temp.fid('t'),pg_temp.fid('e'),pg_temp.fid('b2'),
 (select receipt#>>'{entity,id}' from w5_forecast)::uuid)$$,'42501','Permission denied or multi-factor authentication required.','Foreign branch cannot reopen');
select throws_ok($$select pg_temp.freeze('too-long','2028-01-01')$$,'54000','LIMIT_EXCEEDED','Forecast range bound rejects before effect');
select pg_temp.actor('outsider');
select throws_ok($$select pg_temp.freeze('outsider')$$,'42501','Permission denied or multi-factor authentication required.','Nonmember denied before capture');
select pg_temp.actor('owner');
delete from core.role_permissions where role_id=pg_temp.fid('owner.role') and permission_code='crm.opportunities.view';
select throws_ok($$select api.get_pipeline_forecast(pg_temp.fid('t'),pg_temp.fid('e'),pg_temp.fid('b'),
 (select receipt#>>'{entity,id}' from w5_forecast)::uuid)$$,'42501','PERMISSION_DENIED','Revocation blocks frozen reopen');
insert into core.role_permissions values(pg_temp.fid('t'),pg_temp.fid('owner.role'),'crm.opportunities.view');
select ok(not has_table_privilege('authenticated','analytics.pipeline_forecasts','select'),'No direct client table read bypass');
select ok(not has_function_privilege('anon','api.freeze_pipeline_forecast(uuid,uuid,uuid,uuid,uuid,timestamptz,date,date)','execute'),'Anonymous cannot freeze');
select * from finish(true);
select result as pipeline_snapshot from w5_frozen;
