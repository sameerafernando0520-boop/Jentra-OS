begin;
-- 20260924185321_wave3_period_governance forbids a direct period state change;
-- fixture steps take the governed event path wave3_period_test.sql uses.
create function pg_temp.fixture_period_state(p_id uuid,p_target text) returns void
language plpgsql as $fixture_period$
declare p finance.fiscal_periods%rowtype;next_state text;claims text;
begin
 claims:=current_setting('request.jwt.claims',true);
 loop
  select * into p from finance.fiscal_periods where id=p_id;
  exit when not found or p.state=p_target;
  if auth.uid() is null then
   perform set_config('request.jwt.claims',jsonb_build_object('sub',p.created_by)::text,true);
  end if;
  next_state:=case p.state when 'open' then 'soft_locked' when 'soft_locked' then 'hard_locked' else 'open' end;
  insert into finance.period_events(id,tenant_id,legal_entity_id,period_id,action,from_state,to_state,period_version,
   reason,exceptions,actor_id,transaction_id)
  values(gen_random_uuid(),p.tenant_id,p.legal_entity_id,p.id,
   case next_state when 'soft_locked' then 'soft_lock' when 'hard_locked' then 'hard_lock' else 'reopened' end,
   p.state,next_state,p.version,'Synthetic fixture period state','[]',auth.uid(),txid_current());
  update finance.fiscal_periods set state=next_state where id=p.id;
 end loop;
 perform set_config('request.jwt.claims',coalesce(claims,''),true);
end $fixture_period$;
create extension if not exists pgtap with schema extensions;
set local search_path = extensions, public, pg_catalog;
select no_plan();
create temporary table opening_test_results(message text);
insert into opening_test_results select has_table('inventory','stock_openings','governed stock opening documents exist');
insert into opening_test_results select has_function('api','upsert_stock_opening',array['uuid','uuid','uuid','uuid','uuid','timestamp with time zone','jsonb','bigint'],'opening draft command exists');
insert into opening_test_results select has_function('api','transition_stock_opening',array['uuid','uuid','uuid','uuid','uuid','timestamp with time zone','jsonb','bigint'],'opening workflow command exists');
insert into opening_test_results select has_function('api','post_stock_opening',array['uuid','uuid','uuid','uuid','uuid','timestamp with time zone','jsonb','bigint'],'opening posting command exists');

create function pg_temp.fid(p text) returns uuid language sql immutable as $$select md5('stock-opening:'||p)::uuid$$;
create function pg_temp.actor(p text,p_aal text default 'aal2') returns void language plpgsql as $$begin
 perform set_config('request.jwt.claims',jsonb_build_object('sub',pg_temp.fid(p),'role','authenticated','aal',p_aal)::text,true);
 perform set_config('request.jwt.claim.sub',pg_temp.fid(p)::text,true);end $$;
create function pg_temp.call(p_rpc text,p_payload jsonb,p_version bigint default null,p_key text default null,p_scope text default '')
returns jsonb language plpgsql as $$declare r jsonb;k uuid:=case when p_key is null then gen_random_uuid() else pg_temp.fid(p_key) end;begin
 execute format('select api.%I($1,$2,$3,$4,$5,$6,$7,$8)',p_rpc) into r using pg_temp.fid(p_scope||'tenant'),pg_temp.fid(p_scope||'entity'),
 pg_temp.fid(p_scope||'branch'),k,k,'2026-09-11T00:00:00Z'::timestamptz,p_payload,p_version;return r;end $$;
create function pg_temp.line(p_product text default 'stock',p_q text default '10.125',p_v text default '607.50',p_extra jsonb default '{}')
returns jsonb language sql as $$select jsonb_build_object('line_id',pg_temp.fid(p_product||'.line'),'product_id',pg_temp.fid(p_product),
 'base_quantity',p_q,'base_value',p_v)||p_extra$$;
create function pg_temp.header(p_name text,p_lines jsonb default null,p_scope text default '') returns jsonb language sql as $$
select jsonb_build_object('id',pg_temp.fid(p_name),'document_date','2026-09-01','warehouse_id',pg_temp.fid(p_scope||'warehouse'),
 'offset_account_id',pg_temp.fid(p_scope||'equity'),'reason','Synthetic physical opening count',
 'lines',coalesce(p_lines,jsonb_build_array(pg_temp.line(p_scope||'stock'))))$$;
create function pg_temp.version(p_name text) returns bigint language sql as $$select version from inventory.stock_openings where id=pg_temp.fid(p_name)$$;
create function pg_temp.transition(p_name text,p_extra jsonb) returns jsonb language sql as $$
select pg_temp.call('transition_stock_opening',jsonb_build_object('document_id',pg_temp.fid(p_name))||p_extra,pg_temp.version(p_name))$$;
create function pg_temp.post(p_name text,p_key text default null) returns jsonb language sql as $$
select pg_temp.call('post_stock_opening',jsonb_build_object('document_id',pg_temp.fid(p_name)),pg_temp.version(p_name),p_key)$$;
create function pg_temp.prepare(p_name text,p_lines jsonb default null) returns void language plpgsql as $$begin
 perform pg_temp.actor('actor');perform pg_temp.call('upsert_stock_opening',pg_temp.header(p_name,p_lines));
 perform pg_temp.transition(p_name,'{"action":"submit"}');perform pg_temp.actor('approver');
 perform pg_temp.transition(p_name,'{"decision":"approved"}');perform pg_temp.actor('actor');end $$;
-- All identities and business masters are synthetic and roll back.
insert into auth.users(id,instance_id,aud,role,email,encrypted_password,email_confirmed_at,created_at,updated_at)
select pg_temp.fid(x),'00000000-0000-0000-0000-000000000000','authenticated','authenticated',x||'@opening.jentra.test','',now(),now(),now()
from unnest(array['actor','approver','editor','viewer','outsider']) x;

insert into core.tenants(id,name,slug,created_by) values(pg_temp.fid('tenant'),'Opening Test','opening-fixture-',pg_temp.fid('actor'));
insert into core.legal_entities(id,tenant_id,name,code,currency_code,rounding_scale,created_by)
values(pg_temp.fid('entity'),pg_temp.fid('tenant'),'Opening Entity','OPEN','LKR',2,pg_temp.fid('actor'));
insert into core.branches(id,tenant_id,legal_entity_id,name,code,created_by)
values(pg_temp.fid('branch'),pg_temp.fid('tenant'),pg_temp.fid('entity'),'Opening Branch','OPEN',pg_temp.fid('actor'));
insert into core.warehouses(id,tenant_id,legal_entity_id,branch_id,name,code,created_by)
values(pg_temp.fid('warehouse'),pg_temp.fid('tenant'),pg_temp.fid('entity'),pg_temp.fid('branch'),'Opening Warehouse','OPEN',pg_temp.fid('actor'));
insert into core.memberships(id,tenant_id,user_id,status) select pg_temp.fid(''||x||'.membership'),pg_temp.fid('tenant'),pg_temp.fid(x),'active' from unnest(array['actor','approver','editor','viewer']) x;
insert into core.roles(id,tenant_id,code,name,requires_mfa) select pg_temp.fid(''||x||'.role'),pg_temp.fid('tenant'),x,x,true from unnest(array['actor','approver','editor','viewer']) x;
insert into core.role_permissions(tenant_id,role_id,permission_code)
select pg_temp.fid('tenant'),pg_temp.fid('actor.role'),code from core.permissions;
insert into core.role_permissions(tenant_id,role_id,permission_code)
select pg_temp.fid('tenant'),pg_temp.fid(''||x||'.role'),p from unnest(array['approver','editor']) x cross join unnest(array['workflow.approvals.decide','inventory.cost.view','inventory.adjustments.post']) p;
insert into core.role_permissions(tenant_id,role_id,permission_code) values(pg_temp.fid('tenant'),pg_temp.fid('viewer.role'),'inventory.adjustments.post');
insert into core.role_assignments(tenant_id,membership_id,role_id,legal_entity_id,branch_id,created_by)
select pg_temp.fid('tenant'),pg_temp.fid(''||x||'.membership'),pg_temp.fid(''||x||'.role'),pg_temp.fid('entity'),pg_temp.fid('branch'),pg_temp.fid('actor') from unnest(array['actor','approver','editor','viewer']) x;
insert into finance.accounts(id,tenant_id,legal_entity_id,code,name,account_type,normal_balance,created_by,updated_by)
select pg_temp.fid(''||x),pg_temp.fid('tenant'),pg_temp.fid('entity'),upper(x),x,
case when x='equity' then 'equity' else 'asset' end,case when x='equity' then 'credit' else 'debit' end,pg_temp.fid('actor'),pg_temp.fid('actor') from unnest(array['inventory','inventory2','equity']) x;
insert into inventory.units(id,tenant_id,code,name,symbol,category,precision,created_by,updated_by)
values(pg_temp.fid('unit'),pg_temp.fid('tenant'),'UNIT','Unit','ea','quantity',3,pg_temp.fid('actor'),pg_temp.fid('actor'));
insert into inventory.products(id,tenant_id,legal_entity_id,sku,name,kind,base_unit_id,tracking_mode,inventory_account_id,created_by,updated_by)
select pg_temp.fid(''||x),pg_temp.fid('tenant'),pg_temp.fid('entity'),upper(x),x,case when x='service' then 'service' else 'stocked' end,
pg_temp.fid('unit'),case when x in ('lot','serial') then x else 'none' end,pg_temp.fid('inventory'),pg_temp.fid('actor'),pg_temp.fid('actor')
from unnest(array['stock','lot','serial','service','fresh','existing','authstock']) x;

insert into core.tenants(id,name,slug,created_by) values(pg_temp.fid('othertenant'),'Opening Test','opening-fixture-other',pg_temp.fid('actor'));
insert into core.legal_entities(id,tenant_id,name,code,currency_code,rounding_scale,created_by)
values(pg_temp.fid('otherentity'),pg_temp.fid('othertenant'),'Opening Entity','OPEN','LKR',2,pg_temp.fid('actor'));
insert into core.branches(id,tenant_id,legal_entity_id,name,code,created_by)
values(pg_temp.fid('otherbranch'),pg_temp.fid('othertenant'),pg_temp.fid('otherentity'),'Opening Branch','OPEN',pg_temp.fid('actor'));
insert into core.warehouses(id,tenant_id,legal_entity_id,branch_id,name,code,created_by)
values(pg_temp.fid('otherwarehouse'),pg_temp.fid('othertenant'),pg_temp.fid('otherentity'),pg_temp.fid('otherbranch'),'Opening Warehouse','OPEN',pg_temp.fid('actor'));
insert into core.memberships(id,tenant_id,user_id,status) select pg_temp.fid('other'||x||'.membership'),pg_temp.fid('othertenant'),pg_temp.fid(x),'active' from unnest(array['actor','approver','editor','viewer']) x;
insert into core.roles(id,tenant_id,code,name,requires_mfa) select pg_temp.fid('other'||x||'.role'),pg_temp.fid('othertenant'),x,x,true from unnest(array['actor','approver','editor','viewer']) x;
insert into core.role_permissions(tenant_id,role_id,permission_code)
select pg_temp.fid('othertenant'),pg_temp.fid('otheractor.role'),code from core.permissions;
insert into core.role_permissions(tenant_id,role_id,permission_code)
select pg_temp.fid('othertenant'),pg_temp.fid('other'||x||'.role'),p from unnest(array['approver','editor']) x cross join unnest(array['workflow.approvals.decide','inventory.cost.view','inventory.adjustments.post']) p;
insert into core.role_permissions(tenant_id,role_id,permission_code) values(pg_temp.fid('othertenant'),pg_temp.fid('otherviewer.role'),'inventory.adjustments.post');
insert into core.role_assignments(tenant_id,membership_id,role_id,legal_entity_id,branch_id,created_by)
select pg_temp.fid('othertenant'),pg_temp.fid('other'||x||'.membership'),pg_temp.fid('other'||x||'.role'),pg_temp.fid('otherentity'),pg_temp.fid('otherbranch'),pg_temp.fid('actor') from unnest(array['actor','approver','editor','viewer']) x;
insert into finance.accounts(id,tenant_id,legal_entity_id,code,name,account_type,normal_balance,created_by,updated_by)
select pg_temp.fid('other'||x),pg_temp.fid('othertenant'),pg_temp.fid('otherentity'),upper(x),x,
case when x='equity' then 'equity' else 'asset' end,case when x='equity' then 'credit' else 'debit' end,pg_temp.fid('actor'),pg_temp.fid('actor') from unnest(array['inventory','inventory2','equity']) x;
insert into inventory.units(id,tenant_id,code,name,symbol,category,precision,created_by,updated_by)
values(pg_temp.fid('otherunit'),pg_temp.fid('othertenant'),'UNIT','Unit','ea','quantity',3,pg_temp.fid('actor'),pg_temp.fid('actor'));
insert into inventory.products(id,tenant_id,legal_entity_id,sku,name,kind,base_unit_id,tracking_mode,inventory_account_id,created_by,updated_by)
select pg_temp.fid('other'||x),pg_temp.fid('othertenant'),pg_temp.fid('otherentity'),upper(x),x,case when x='service' then 'service' else 'stocked' end,
pg_temp.fid('otherunit'),case when x in ('lot','serial') then x else 'none' end,pg_temp.fid('otherinventory'),pg_temp.fid('actor'),pg_temp.fid('actor')
from unnest(array['stock','lot','serial','service','fresh','existing','authstock']) x;

insert into finance.fiscal_periods(id,tenant_id,legal_entity_id,name,start_date,end_date,created_by,updated_by)
values(pg_temp.fid('period'),pg_temp.fid('tenant'),pg_temp.fid('entity'),'September','2026-09-01','2026-09-30',pg_temp.fid('actor'),pg_temp.fid('actor'));
insert into core.document_sequences(tenant_id,legal_entity_id,branch_id,document_type,prefix,created_by,updated_by)
select pg_temp.fid('tenant'),pg_temp.fid('entity'),pg_temp.fid('branch'),x,x||'-',pg_temp.fid('actor'),pg_temp.fid('actor') from unnest(array['stock_opening','journal_entry']) x;
insert into workflow.workflow_definitions(id,tenant_id,legal_entity_id,document_type,name,status,lifecycle,created_by,updated_by)
values(pg_temp.fid('workflow'),pg_temp.fid('tenant'),pg_temp.fid('entity'),'stock_opening','Opening workflow','active',
'{"states":["draft","submitted","approved","rejected","posted","settled","fulfilled","closed","cancelled","reversed"],"transitions":[["draft","submitted"],["submitted","approved"],["submitted","rejected"],["approved","posted"],["rejected","draft"],["draft","cancelled"],["submitted","cancelled"]],"posting_transitions":[["submitted","draft"],["approved","draft"]],"requires_approval":true}',pg_temp.fid('actor'),pg_temp.fid('actor'));
insert into workflow.approval_matrix_steps(id,tenant_id,workflow_definition_id,role_id,step_order,created_by,updated_by)
values(pg_temp.fid('step'),pg_temp.fid('tenant'),pg_temp.fid('workflow'),pg_temp.fid('approver.role'),1,pg_temp.fid('actor'),pg_temp.fid('actor'));
select pg_temp.actor('actor');
insert into opening_test_results select throws_ok($$select pg_temp.call('upsert_stock_opening',pg_temp.header('bad',jsonb_build_array(pg_temp.line('stock','1','1.001'))))$$,'22023','OPENING_PRECISION_INVALID','sub-cent value rejected');
insert into opening_test_results select throws_ok($$select pg_temp.call('upsert_stock_opening',pg_temp.header('bad',jsonb_build_array(pg_temp.line('stock','0.0001'))))$$,'22023','OPENING_PRECISION_INVALID','quantity respects unit precision');
insert into opening_test_results select throws_ok($$select pg_temp.call('upsert_stock_opening',pg_temp.header('bad',jsonb_build_array(pg_temp.line('service'))))$$,'22023','OPENING_STOCKED_PRODUCT_REQUIRED','service cannot enter stock');
insert into opening_test_results select throws_ok($$select pg_temp.call('upsert_stock_opening',pg_temp.header('bad',jsonb_build_array(pg_temp.line('lot'))))$$,'22023','TRACKING_INPUT_INVALID','lot requires code');
insert into opening_test_results select throws_ok($$select pg_temp.call('upsert_stock_opening',pg_temp.header('bad',jsonb_build_array(pg_temp.line('lot','1','1','{"lot_code":"OLD","expiry_date":"2020-01-01"}'))))$$,'22023','LOT_NOT_SALEABLE','expired lot rejected');
insert into opening_test_results select throws_ok($$select pg_temp.call('upsert_stock_opening',pg_temp.header('bad',jsonb_build_array(pg_temp.line('serial','2','20','{"serial_codes":["S1"," S1 "]}'))))$$,'22023','SERIAL_CONFLICT','duplicate serials rejected');
insert into opening_test_results select throws_ok($$select pg_temp.call('upsert_stock_opening',pg_temp.header('bad',jsonb_build_array(pg_temp.line('serial','2','20','{"serial_codes":["S1"]}'))))$$,'22023','SERIAL_CONFLICT','serial count must match');
insert into opening_test_results select throws_ok($$select pg_temp.call('upsert_stock_opening',pg_temp.header('bad',jsonb_build_array(pg_temp.line(),pg_temp.line())))$$,'22023','OPENING_LINE_ID_INVALID','duplicate line ids rejected');
insert into opening_test_results select throws_ok($$select pg_temp.call('upsert_stock_opening',pg_temp.header('bad')||jsonb_build_object('offset_account_id',pg_temp.fid('inventory')))$$,'55000','ACCOUNT_MAPPING_INVALID','offset must be equity');
insert into opening_test_results select throws_ok($$select pg_temp.call('upsert_stock_opening',pg_temp.header('bad')||jsonb_build_object('warehouse_id',pg_temp.fid('otherwarehouse')))$$,'22023','WAREHOUSE_INACTIVE','foreign warehouse rejected');

create temporary table opening_responses(name text primary key,response jsonb);
insert into opening_responses select 'draft',pg_temp.call('upsert_stock_opening',pg_temp.header('opening'),null,'save-key');
insert into opening_test_results select is((select pg_temp.call('upsert_stock_opening',pg_temp.header('opening'),null,'save-key')),(select response from opening_responses where name='draft'),'save replay returns original receipt');
insert into opening_test_results select is((select jsonb_typeof(lines#>'{0,base_quantity}') from inventory.stock_openings where id=pg_temp.fid('opening')),'string','quantities remain decimal strings');
insert into opening_test_results select is((select (response#>>'{entity,grand_total}')::numeric from opening_responses where name='draft'),607.50::numeric,'exact computed total');
insert into opening_test_results select throws_ok($$select pg_temp.call('upsert_stock_opening',pg_temp.header('opening'),99)$$,'40001','VERSION_CONFLICT','stale save rejected');
insert into opening_test_results select throws_ok($$select pg_temp.post('opening')$$,'55000','OPENING_APPROVAL_REQUIRED','draft cannot post');
select pg_temp.call('upsert_stock_opening',pg_temp.header('foreign-opening',null,'other'),null,null,'other');
insert into opening_test_results select throws_ok($$select pg_temp.call('upsert_stock_opening',pg_temp.header('foreign-opening'))$$,'42501','DOCUMENT_SCOPE_INVALID','foreign document cannot be overwritten');
insert into opening_test_results select is((select tenant_id from inventory.stock_openings where id=pg_temp.fid('foreign-opening')),pg_temp.fid('othertenant'),'foreign tenant remains unchanged');
update workflow.approval_matrix_steps set status='inactive' where id=pg_temp.fid('step');
insert into opening_test_results select throws_ok($$select pg_temp.transition('opening','{"action":"submit"}')$$,'55000','WORKFLOW_CONFIGURATION_ERROR','missing approval step fails closed');
update workflow.approval_matrix_steps set status='active' where id=pg_temp.fid('step');
update workflow.workflow_definitions set lifecycle=jsonb_set(lifecycle,'{requires_approval}','false') where id=pg_temp.fid('workflow');
insert into opening_test_results select throws_ok($$select pg_temp.transition('opening','{"action":"submit"}')$$,'55000','OPENING_APPROVAL_REQUIRED','configuration cannot bypass approval');
update workflow.workflow_definitions set lifecycle=jsonb_set(lifecycle,'{requires_approval}','true') where id=pg_temp.fid('workflow');
insert into opening_test_results select lives_ok($$select pg_temp.transition('opening','{"action":"submit"}')$$,'opening submits');
insert into opening_test_results select is((select status from inventory.stock_openings where id=pg_temp.fid('opening')),'pending_approval','opening waits for approver');
insert into opening_test_results select throws_ok($$select pg_temp.transition('opening','{"decision":"approved"}')$$,'42501','SEGREGATION_OF_DUTIES_VIOLATION','creator or submitter cannot approve');
select pg_temp.actor('editor');
insert into opening_test_results select throws_ok($$select pg_temp.transition('opening','{"decision":"approved"}')$$,'42501','APPROVAL_ROLE_REQUIRED','unconfigured role cannot approve');
select pg_temp.actor('approver','aal1');
insert into opening_test_results select throws_ok($$select pg_temp.transition('opening','{"decision":"approved"}')$$,'42501','Permission denied or multi-factor authentication required.','approval requires MFA');
select pg_temp.actor('approver');
insert into opening_test_results select throws_ok($$select pg_temp.transition('opening','{"decision":"rejected"}')$$,'22023','REASON_REQUIRED','rejection requires note');
insert into opening_test_results select lives_ok($$select pg_temp.transition('opening','{"decision":"approved"}')$$,'independent approver approves');
select pg_temp.actor('actor');
select pg_temp.fixture_period_state(id,'soft_locked') from finance.fiscal_periods where id=pg_temp.fid('period');
insert into opening_test_results select throws_ok($$select pg_temp.post('opening')$$,'55000','PERIOD_CLOSED','closed period blocks posting');
select pg_temp.fixture_period_state(id,'open') from finance.fiscal_periods where id=pg_temp.fid('period');
update inventory.products set inventory_account_id=pg_temp.fid('inventory2') where id=pg_temp.fid('stock');
insert into opening_test_results select throws_ok($$select pg_temp.post('opening')$$,'55000','OPENING_MASTER_CHANGED','changed mapping needs renewed approval');
update inventory.products set inventory_account_id=pg_temp.fid('inventory') where id=pg_temp.fid('stock');
-- Fail after stock writes at journal sequence allocation.
update core.document_sequences set status='inactive' where document_type='journal_entry' and tenant_id=pg_temp.fid('tenant');
insert into opening_test_results select throws_ok($$select pg_temp.post('opening','post-key')$$,'55000','DOCUMENT_SEQUENCE_NOT_CONFIGURED','late journal failure rolls back');
insert into opening_test_results select is((select count(*) from inventory.stock_movements where tenant_id=pg_temp.fid('tenant')),0::bigint,'late failure leaves no movement');
insert into opening_test_results select is((select count(*) from inventory.stock_balances where tenant_id=pg_temp.fid('tenant')),0::bigint,'late failure leaves no balance');
insert into opening_test_results select is((select count(*) from core.command_receipts where command_id=pg_temp.fid('post-key')),0::bigint,'late failure leaves no receipt');
update core.document_sequences set status='active' where document_type='journal_entry' and tenant_id=pg_temp.fid('tenant');
insert into opening_responses select 'prepost',jsonb_build_object('version',pg_temp.version('opening'));
insert into opening_responses select 'posted',pg_temp.post('opening','post-key');
insert into opening_test_results select is((select status from inventory.stock_openings where id=pg_temp.fid('opening')),'posted','approved opening posts');
insert into opening_test_results select is((select on_hand_quantity from inventory.stock_balances where product_id=pg_temp.fid('stock')),10.125::numeric,'exact base quantity');
insert into opening_test_results select is((select carrying_value from inventory.stock_valuations where tenant_id=pg_temp.fid('tenant')),607.50::numeric,'exact carrying value');
insert into opening_test_results select is((select sum(base_debit-base_credit) from finance.journal_lines where tenant_id=pg_temp.fid('tenant')),0::numeric,'journal balances exactly');
insert into opening_test_results select is((select sum(base_debit-base_credit) from finance.journal_lines where account_id=pg_temp.fid('inventory')),607.50::numeric,'inventory debit matches valuation');
insert into opening_test_results select is((select sum(base_debit-base_credit) from finance.journal_lines where account_id=pg_temp.fid('equity')),-607.50::numeric,'equity offsets inventory');
insert into opening_test_results select is((select pg_temp.call('post_stock_opening',jsonb_build_object('document_id',pg_temp.fid('opening')),(select (response->>'version')::bigint from opening_responses where name='prepost'),'post-key')),(select response from opening_responses where name='posted'),'lost response retry replays posting');
insert into opening_test_results select is((select count(*) from finance.journal_entries where source_id=pg_temp.fid('opening')),1::bigint,'only one journal after retry');
insert into opening_test_results select throws_ok($$update inventory.stock_openings set reason='tamper' where id=pg_temp.fid('opening')$$,'55000','POSTED_DOCUMENT_IMMUTABLE','posted document cannot change');
insert into opening_test_results select throws_ok($$delete from inventory.stock_openings where id=pg_temp.fid('opening')$$,'55000','POSTED_DOCUMENT_IMMUTABLE','posted document cannot be deleted');
select pg_temp.prepare('duplicate');
insert into opening_test_results select throws_ok($$select pg_temp.post('duplicate')$$,'55000','OPENING_ALREADY_ESTABLISHED','second opening rejected');

select pg_temp.prepare('tracked',jsonb_build_array(
 pg_temp.line('lot','2','40','{"lot_code":"LOT-A","expiry_date":"2099-01-01"}'),
 pg_temp.line('lot','3','60',jsonb_build_object('line_id',pg_temp.fid('lot.line2'),'lot_code','LOT-B')),
 pg_temp.line('serial','2','80','{"serial_codes":["SERIAL-B"," SERIAL-A "]}')));
insert into opening_test_results select lives_ok($$select pg_temp.post('tracked')$$,'multiple lots and serials post atomically');
insert into opening_test_results select is((select sum(on_hand_quantity) from inventory.lot_balances where product_id=pg_temp.fid('lot')),5::numeric,'lot balances match quantity');
insert into opening_test_results select is((select on_hand_quantity from inventory.stock_balances where product_id=pg_temp.fid('lot')),5::numeric,'lot lines aggregate to product balance');
insert into opening_test_results select is((select count(*) from inventory.serials where product_id=pg_temp.fid('serial') and status='available'),2::bigint,'serial identities available');
insert into opening_test_results select is((select cardinality(serial_ids) from inventory.stock_movement_lines where product_id=pg_temp.fid('serial')),2,'movement retains serial identities');

select pg_temp.prepare('fresh-opening',jsonb_build_array(pg_temp.line('fresh')));
select pg_temp.transition('fresh-opening','{"action":"recall","reason":"Revise opening count"}');
select pg_temp.actor('approver');
select pg_temp.call('upsert_stock_opening',pg_temp.header('fresh-opening',jsonb_build_array(pg_temp.line('fresh'))),pg_temp.version('fresh-opening'));
select pg_temp.actor('actor');
select pg_temp.transition('fresh-opening','{"action":"submit"}');
select pg_temp.actor('approver');
insert into opening_test_results select throws_ok($$select pg_temp.transition('fresh-opening','{"decision":"approved"}')$$,'42501','SEGREGATION_OF_DUTIES_VIOLATION','latest editor cannot approve');
select pg_temp.actor('actor');
insert into opening_test_results select throws_ok($$select pg_temp.transition('fresh-opening','{"action":"recall"}')$$,'22023','REASON_REQUIRED','recall requires reason');
insert into opening_test_results select lives_ok($$select pg_temp.transition('fresh-opening','{"action":"cancel","reason":"Count superseded"}')$$,'pending opening can be cancelled');

-- Existing projections also prevent opening before a movement history is available.
select pg_temp.actor('actor');
select pg_temp.prepare('existing-opening',jsonb_build_array(pg_temp.line('existing')));
insert into inventory.stock_balances(id,tenant_id,legal_entity_id,branch_id,warehouse_id,product_id,on_hand_quantity,created_by,updated_by)
values(pg_temp.fid('existing.balance'),pg_temp.fid('tenant'),pg_temp.fid('entity'),pg_temp.fid('branch'),pg_temp.fid('warehouse'),pg_temp.fid('existing'),1,pg_temp.fid('actor'),pg_temp.fid('actor'));
insert into opening_test_results select throws_ok($$select pg_temp.post('existing-opening')$$,'55000','OPENING_ALREADY_ESTABLISHED','nonzero legacy quantity prevents opening');
update inventory.stock_balances set on_hand_quantity=0 where id=pg_temp.fid('existing.balance');
insert into inventory.stock_valuations(tenant_id,legal_entity_id,branch_id,stock_balance_id,carrying_value,created_by,updated_by)
values(pg_temp.fid('tenant'),pg_temp.fid('entity'),pg_temp.fid('branch'),pg_temp.fid('existing.balance'),1,pg_temp.fid('actor'),pg_temp.fid('actor'));
insert into opening_test_results select throws_ok($$select pg_temp.post('existing-opening')$$,'55000','OPENING_ALREADY_ESTABLISHED','nonzero legacy valuation prevents opening');
update inventory.stock_valuations set carrying_value=0 where stock_balance_id=pg_temp.fid('existing.balance');
insert into opening_test_results select lives_ok($$select pg_temp.post('existing-opening')$$,'empty historical projection can receive first opening');
insert into opening_test_results select throws_ok($$select pg_temp.call('upsert_stock_opening',pg_temp.header('different'),null,'save-key')$$,'22023','IDEMPOTENCY_MISMATCH','reused key cannot change request');
insert into opening_test_results select throws_ok($$select pg_temp.call('upsert_stock_opening',jsonb_set(pg_temp.header('numeric'),'{lines,0,base_quantity}'::text[],'10'))$$,'22023',null,'JSON numeric quantity is rejected');
insert into opening_test_results select is((select count(*) from audit.events where command_id=pg_temp.fid('post-key')),1::bigint,'posting emits one audit event');
insert into opening_test_results select is((select count(*) from workflow.process_events where command_id=pg_temp.fid('post-key')),1::bigint,'posting emits one process event');
insert into opening_test_results select is((select count(*) from core.outbox_events where command_id=pg_temp.fid('post-key')),1::bigint,'posting emits one outbox event');
insert into opening_test_results select is((select count(*) from workflow.approval_decisions where approval_request_id in
(select id from workflow.approval_requests where document_id=pg_temp.fid('opening'))),1::bigint,'independent decision is retained');

-- Every configured approval step must complete before posting.
insert into workflow.approval_matrix_steps(id,tenant_id,workflow_definition_id,role_id,step_order,created_by,updated_by)
values(pg_temp.fid('step2'),pg_temp.fid('tenant'),pg_temp.fid('workflow'),pg_temp.fid('editor.role'),2,pg_temp.fid('actor'),pg_temp.fid('actor'));
select pg_temp.call('upsert_stock_opening',pg_temp.header('multi',jsonb_build_array(pg_temp.line('fresh'))));
select pg_temp.transition('multi','{"action":"submit"}');
select pg_temp.actor('approver');
select pg_temp.transition('multi','{"decision":"approved"}');
insert into opening_test_results select is((select status from inventory.stock_openings where id=pg_temp.fid('multi')),'pending_approval','first step does not prematurely approve');
select pg_temp.actor('actor');
insert into opening_test_results select throws_ok($$select pg_temp.post('multi')$$,'55000','OPENING_APPROVAL_REQUIRED','incomplete approval blocks posting');
select pg_temp.actor('editor');
insert into opening_test_results select lives_ok($$select pg_temp.transition('multi','{"decision":"approved"}')$$,'second scoped approver completes approval');
select pg_temp.actor('actor');
insert into opening_test_results select lives_ok($$select pg_temp.post('multi')$$,'fully approved multistep opening posts');
insert into opening_test_results select is((select count(*) from workflow.approval_decisions where approval_request_id in
(select id from workflow.approval_requests where document_id=pg_temp.fid('multi'))),2::bigint,'both decision steps retained');
insert into opening_test_results select ok(not exists(select journal_entry_id from finance.journal_lines
where tenant_id=pg_temp.fid('tenant') group by journal_entry_id having sum(base_debit)<>sum(base_credit) or count(*)<2),'every opening journal balances');
insert into opening_test_results select is((select sum(carrying_value) from inventory.stock_valuations where tenant_id=pg_temp.fid('tenant')),
(select sum(base_debit-base_credit) from finance.journal_lines where account_id=pg_temp.fid('inventory')),'all carrying values reconcile to inventory control');

update workflow.approval_matrix_steps set status='inactive' where id=pg_temp.fid('step2');
grant select,insert on opening_test_results to authenticated;
set local role authenticated;
insert into opening_test_results select lives_ok($$select pg_temp.prepare('authenticated',jsonb_build_array(pg_temp.line('authstock')))$$,'authenticated role can save submit and approve through named commands');
insert into opening_test_results select lives_ok($$select pg_temp.post('authenticated')$$,'authenticated role posts approved opening through named command');
insert into opening_test_results select is((select count(*) from api.stock_openings where id=pg_temp.fid('opening')),1::bigint,'authorized caller reads opening');
select pg_temp.actor('viewer');
insert into opening_test_results select is((select count(*) from api.stock_openings),0::bigint,'missing cost permission hides values');
insert into opening_test_results select throws_ok($$select pg_temp.call('upsert_stock_opening',pg_temp.header('unauthorized'))$$,'42501','Permission denied or multi-factor authentication required.','cost permission required to save');
insert into opening_test_results select ok(not has_function_privilege('authenticated','inventory.opening_document(text,uuid,uuid,boolean)','execute'),'private helper cannot bypass RLS');
insert into opening_test_results select ok(not has_table_privilege('authenticated','inventory.stock_openings','insert,update,delete'),'direct writes revoked');
insert into opening_test_results select ok(not has_function_privilege('anon','api.post_stock_opening(uuid,uuid,uuid,uuid,uuid,timestamptz,jsonb,bigint)','execute'),'anonymous posting revoked');
select pg_temp.actor('outsider');
insert into opening_test_results select is((select count(*) from api.stock_openings),0::bigint,'outsider cannot read openings');
reset role;
set constraints all immediate;
insert into opening_test_results select * from finish(true);
select message from opening_test_results;
rollback;
