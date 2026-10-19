-- AC-309: isolated synthetic test identities only. Everything rolls back.
begin;
create extension if not exists pgtap with schema extensions;
set local lock_timeout='2s';
set local statement_timeout='30s';
set local search_path=extensions,public,pg_catalog;
select no_plan();
create temporary table procurement_test_results(message text);
grant insert on procurement_test_results to authenticated;
create function pg_temp.fid(p text) returns uuid language sql immutable as $$select md5('remaining-wave3-procurement-20260913:'||p)::uuid$$;
create function pg_temp.actor(p text,p_aal text default 'aal2') returns void language plpgsql as $$begin
 perform set_config('request.jwt.claims',jsonb_build_object('sub',pg_temp.fid(p),'role','authenticated','aal',p_aal)::text,true);
 perform set_config('request.jwt.claim.sub',pg_temp.fid(p)::text,true);end $$;
create function pg_temp.call(p_rpc text,p_payload jsonb,p_version bigint default null,p_key text default null)
returns jsonb language plpgsql as $$declare r jsonb;k uuid:=case when p_key is null then gen_random_uuid() else pg_temp.fid(p_key) end;begin
 execute format('select api.%I($1,$2,$3,$4,$5,$6,$7,$8)',p_rpc) into r using pg_temp.fid('tenant'),pg_temp.fid('entity'),
 pg_temp.fid('branch'),k,k,'2026-09-13T00:00:00Z'::timestamptz,p_payload,p_version;return r;end $$;
create function pg_temp.header(p_name text) returns jsonb language sql as $$select jsonb_build_object(
 'id',pg_temp.fid(p_name),'need_by','2026-09-30','currency_code','LKR','justification','Synthetic requisition fixture',
 'lines',jsonb_build_array(jsonb_build_object('line_id',pg_temp.fid(p_name||'.line'),'unit_id',pg_temp.fid('unit'),
 'description','Paper','quantity','3','estimated_unit_price','0.333333','conversion_numerator','1','conversion_denominator','1')))$$;
create function pg_temp.version(p_name text) returns bigint language sql as $$select version from procurement.requisitions where id=pg_temp.fid(p_name)$$;
create function pg_temp.transition(p_name text,p_extra jsonb,p_key text default null) returns jsonb language sql as $$
 select pg_temp.call('transition_purchase_requisition',jsonb_build_object('document_id',pg_temp.fid(p_name))||p_extra,pg_temp.version(p_name),p_key)$$;

insert into auth.users(id,instance_id,aud,role,email,encrypted_password,email_confirmed_at,created_at,updated_at)
select pg_temp.fid(x),'00000000-0000-0000-0000-000000000000','authenticated','authenticated',x||'@procurement.jentra.test','',now(),now(),now()
from unnest(array['creator','approver','outsider']) x;
insert into core.tenants(id,name,slug,created_by) values(pg_temp.fid('tenant'),'Procurement Test','remaining-w3-procurement-fixture',pg_temp.fid('creator'));
insert into core.legal_entities(id,tenant_id,name,code,currency_code,rounding_scale,created_by)
values(pg_temp.fid('entity'),pg_temp.fid('tenant'),'Procurement Entity','PRTEST','LKR',2,pg_temp.fid('creator'));
insert into core.branches(id,tenant_id,legal_entity_id,name,code,created_by)
values(pg_temp.fid('branch'),pg_temp.fid('tenant'),pg_temp.fid('entity'),'Procurement Branch','PRTEST',pg_temp.fid('creator'));
insert into core.memberships(id,tenant_id,user_id,status)
select pg_temp.fid(x||'.membership'),pg_temp.fid('tenant'),pg_temp.fid(x),'active' from unnest(array['creator','approver']) x;
insert into core.roles(id,tenant_id,code,name,requires_mfa)
select pg_temp.fid(x||'.role'),pg_temp.fid('tenant'),x,x,true from unnest(array['creator','approver']) x;
insert into core.role_permissions(tenant_id,role_id,permission_code)
select pg_temp.fid('tenant'),pg_temp.fid(x||'.role'),p from unnest(array['creator','approver']) x
cross join unnest(array['procurement.requisitions.manage','procurement.rfq.manage','procurement.orders.manage','workflow.approvals.decide']) p;
insert into core.role_assignments(tenant_id,membership_id,role_id,legal_entity_id,branch_id,created_by)
select pg_temp.fid('tenant'),pg_temp.fid(x||'.membership'),pg_temp.fid(x||'.role'),pg_temp.fid('entity'),pg_temp.fid('branch'),pg_temp.fid('creator')
from unnest(array['creator','approver']) x;
insert into inventory.units(id,tenant_id,code,name,symbol,category,precision,created_by,updated_by)
values(pg_temp.fid('unit'),pg_temp.fid('tenant'),'EA','Each','ea','quantity',6,pg_temp.fid('creator'),pg_temp.fid('creator'));
insert into core.document_sequences(tenant_id,legal_entity_id,branch_id,document_type,prefix,created_by,updated_by)
values(pg_temp.fid('tenant'),pg_temp.fid('entity'),pg_temp.fid('branch'),'purchase_requisition','PRTEST-',pg_temp.fid('creator'),pg_temp.fid('creator'));

select pg_temp.actor('creator');
create temporary table procurement_responses(name text primary key,response jsonb);
insert into procurement_responses values('save',pg_temp.call('upsert_purchase_requisition',pg_temp.header('request'),null,'save'));
insert into procurement_test_results select is((select response#>>'{entity,estimated_total}' from procurement_responses where name='save'),'0.999999','AC-309 server exact estimate');
insert into procurement_test_results select is(pg_temp.call('upsert_purchase_requisition',pg_temp.header('request'),null,'save'),(select response from procurement_responses where name='save'),'identical save replay');
insert into procurement_test_results select throws_ok($$select pg_temp.call('upsert_purchase_requisition',pg_temp.header('request')||'{"justification":"changed"}',null,'save')$$,'22023','IDEMPOTENCY_MISMATCH','changed-body key reuse rejected');
insert into procurement_test_results select throws_ok($$select pg_temp.call('upsert_purchase_requisition',pg_temp.header('request'),99)$$,'40001','VERSION_CONFLICT','stale save rejected');
insert into procurement_test_results select throws_ok($$select pg_temp.call('upsert_purchase_requisition',jsonb_set(pg_temp.header('invalid'),'{lines,0,quantity}','3'))$$,'22023','quantity must be a decimal string.','JSON numeric rejected');
insert into procurement_test_results select is((select count(*)::integer from procurement.requisitions),1,'failed save creates no header');
insert into procurement_test_results select throws_ok($$select pg_temp.transition('request','{"action":"submit"}')$$,'55000','WORKFLOW_CONFIGURATION_ERROR','missing workflow fails closed');
insert into procurement_test_results select is((select next_value::text from core.document_sequences where tenant_id=pg_temp.fid('tenant')),'1','failed submit consumes no number');

insert into workflow.workflow_definitions(id,tenant_id,legal_entity_id,document_type,name,status,lifecycle,created_by,updated_by)
values(pg_temp.fid('workflow'),pg_temp.fid('tenant'),pg_temp.fid('entity'),'purchase_requisition','Procurement workflow','active',
'{"states":["draft","submitted","approved","rejected","posted","settled","fulfilled","closed","cancelled","reversed"],"transitions":[["draft","submitted"],["submitted","approved"],["submitted","rejected"],["rejected","draft"],["draft","cancelled"],["submitted","cancelled"]],"posting_transitions":[["submitted","draft"]],"requires_approval":true}',pg_temp.fid('creator'),pg_temp.fid('creator'));
insert into procurement_test_results select throws_ok($$select pg_temp.transition('request','{"action":"submit"}')$$,'55000','WORKFLOW_CONFIGURATION_ERROR','required approval with no matrix fails closed');
insert into workflow.approval_matrix_steps(id,tenant_id,workflow_definition_id,role_id,step_order,created_by,updated_by)
values(pg_temp.fid('step'),pg_temp.fid('tenant'),pg_temp.fid('workflow'),pg_temp.fid('approver.role'),1,pg_temp.fid('creator'),pg_temp.fid('creator'));
insert into procurement_responses values('submit',pg_temp.transition('request','{"action":"submit"}','submit'));
insert into procurement_test_results select is((select status from procurement.requisitions where id=pg_temp.fid('request')),'pending_approval','submission freezes approval');
insert into procurement_test_results select throws_ok($$select pg_temp.call('upsert_purchase_requisition',pg_temp.header('request'),pg_temp.version('request'))$$,'55000','REQUISITION_NOT_EDITABLE','submitted request cannot be edited');
insert into procurement_test_results select throws_ok($$select pg_temp.transition('request','{"decision":"approved"}')$$,'42501','SEGREGATION_OF_DUTIES_VIOLATION','creator cannot approve');
select pg_temp.actor('approver','aal1');
insert into procurement_test_results select throws_ok($$select pg_temp.transition('request','{"decision":"approved"}')$$,'42501',null,'MFA requirement enforced');
select pg_temp.actor('approver');
insert into procurement_responses values('approval',pg_temp.transition('request','{"decision":"approved"}'));
insert into procurement_test_results select is((select status from procurement.requisitions where id=pg_temp.fid('request')),'approved','independent approval completes');
insert into procurement_test_results select is((select count(*)::integer from procurement.requisition_history where requisition_id=pg_temp.fid('request')),3,'all versions have immutable history');
insert into procurement_test_results select throws_ok($$delete from procurement.requisition_history where requisition_id=pg_temp.fid('request')$$,'55000',null,'history deletion rejected even for trusted caller');
insert into procurement_test_results select is((select count(*)::integer from finance.journal_entries where tenant_id=pg_temp.fid('tenant')),0,'requisition creates no ledger posting');
insert into procurement_test_results select is((select count(*)::integer from core.command_receipts where tenant_id=pg_temp.fid('tenant')),3,'one receipt per successful command');
select pg_temp.actor('creator');
insert into crm.parties(id,tenant_id,code,legal_name,display_name,kind,created_by,updated_by)
select pg_temp.fid(s),pg_temp.fid('tenant'),upper(s),s,s,'supplier',pg_temp.fid('creator'),pg_temp.fid('creator') from unnest(array['supplier_a','supplier_b']) s;
insert into core.document_sequences(tenant_id,legal_entity_id,branch_id,document_type,prefix,created_by,updated_by)
values(pg_temp.fid('tenant'),pg_temp.fid('entity'),pg_temp.fid('branch'),'request_for_quote','RFQTEST-',pg_temp.fid('creator'),pg_temp.fid('creator'));
create function pg_temp.rfq() returns jsonb language sql as $$select jsonb_build_object(
 'id',pg_temp.fid('rfq'),'operation','issue','title','Paper sourcing','document_date','2026-09-13','close_date','2026-09-30',
 'requisition_id',pg_temp.fid('request'),'requisition_version',pg_temp.version('request'),
 'invited_supplier_ids',jsonb_build_array(pg_temp.fid('supplier_a'),pg_temp.fid('supplier_b')))$$;
create function pg_temp.q(p_supplier text default 'supplier_a',p_quantity text default '3') returns jsonb language sql as $$select jsonb_build_object(
 'id',pg_temp.fid('rfq'),'operation','record_quote','quote_id',pg_temp.fid(p_supplier||'.quote'),'supplier_id',pg_temp.fid(p_supplier),
 'quote_date','2026-09-13','valid_until','2026-12-31','currency_code','LKR','exchange_rate','1','rate_date','2026-09-13',
 'payment_terms','30 days','delivery_terms','Delivered to warehouse',
 'lines',jsonb_build_array(jsonb_build_object('source_line_id',pg_temp.fid('request.line'),'quantity',p_quantity,'unit_price','123.456789','discount_percent','10')))$$;
create function pg_temp.rfq_version() returns bigint language sql as $$select version from procurement.rfqs where id=pg_temp.fid('rfq')$$;
insert into procurement_test_results select throws_ok($$select pg_temp.call('upsert_request_for_quote',pg_temp.rfq()||jsonb_build_object('source_line_ids',jsonb_build_array(pg_temp.fid('unrelated-line'))))$$,'22023','RFQ_SOURCE_LINES_INVALID','RFQ cannot source an unrelated requisition line');
insert into procurement_responses values('rfq',pg_temp.call('upsert_request_for_quote',pg_temp.rfq(),null,'rfq-issue'));
insert into procurement_test_results select is(pg_temp.call('upsert_request_for_quote',pg_temp.rfq(),null,'rfq-issue'),(select response from procurement_responses where name='rfq'),'RFQ issue replay');
insert into procurement_test_results select is((select count(*)::integer from procurement.rfq_lines where rfq_id=pg_temp.fid('rfq')),1,'RFQ retains source lines');
insert into procurement_test_results select throws_ok($$update procurement.rfq_lines set source_snapshot='{}' where rfq_id=pg_temp.fid('rfq')$$,'55000',null,'RFQ source snapshot immutable');
insert into procurement_test_results select throws_ok($$select pg_temp.call('upsert_request_for_quote',pg_temp.q('outsider'),pg_temp.rfq_version())$$,'22023','INVITED_SUPPLIER_REQUIRED','uninvited response denied');
select pg_temp.call('upsert_request_for_quote',pg_temp.q('supplier_a','2'),pg_temp.rfq_version());
insert into procurement_test_results select is((select complete from procurement.supplier_quotes where id=pg_temp.fid('supplier_a.quote')),false,'partial response remains visible as incomplete');
insert into procurement_test_results select throws_ok($$select pg_temp.call('upsert_request_for_quote',jsonb_build_object('id',pg_temp.fid('rfq'),'operation','select','quote_id',pg_temp.fid('supplier_a.quote'),'selection_reason','Lowest price'),pg_temp.rfq_version())$$,'55000','COMPLETE_VALID_QUOTE_REQUIRED','incomplete quote cannot be selected');
select pg_temp.call('upsert_request_for_quote',pg_temp.q(),pg_temp.rfq_version());
insert into procurement_test_results select is((select total::text from procurement.supplier_quotes where id=pg_temp.fid('supplier_a.quote')),'333.330000','quote recalculated using entity rounding and discount');
insert into procurement_test_results select is((select jsonb_typeof(detail#>'{quotes,0,total}') from api.request_for_quotes where id=pg_temp.fid('rfq')),'string','quote financial JSON remains exact strings');
insert into procurement_test_results select throws_ok($$select pg_temp.call('upsert_request_for_quote',pg_temp.q(),1)$$,'40001','VERSION_CONFLICT','stale RFQ response denied');
select pg_temp.call('upsert_request_for_quote',jsonb_build_object('id',pg_temp.fid('rfq'),'operation','select','quote_id',pg_temp.fid('supplier_a.quote'),'selection_reason','Required coverage and lead time'),pg_temp.rfq_version());
insert into procurement_test_results select is((select status from procurement.rfqs where id=pg_temp.fid('rfq')),'selected','supplier selected with rationale');
insert into procurement_test_results select throws_ok($$select pg_temp.call('upsert_request_for_quote',pg_temp.q(),pg_temp.rfq_version())$$,'55000','RFQ_NOT_EDITABLE','selected response cannot be silently replaced');
insert into procurement_test_results select is((select count(*)::integer from procurement.rfq_history where rfq_id=pg_temp.fid('rfq')),4,'response revisions retained in RFQ history');
insert into procurement_test_results select is((select api.procurement_reference_options(pg_temp.fid('tenant'),pg_temp.fid('entity'),pg_temp.fid('branch'),'units')->>'base_currency'),'LKR','reference read returns governed base currency');
select pg_temp.actor('outsider');
set local role authenticated;
insert into procurement_test_results select is((select count(*)::integer from api.purchase_requisitions),0,'outsider security-invoker read denied');
insert into procurement_test_results select throws_ok($$insert into procurement.requisitions(id) values(gen_random_uuid())$$,'42501',null,'authenticated direct writes denied');
reset role;
insert into procurement_test_results select * from finish();
select jsonb_agg(message) as results from procurement_test_results;
rollback;
