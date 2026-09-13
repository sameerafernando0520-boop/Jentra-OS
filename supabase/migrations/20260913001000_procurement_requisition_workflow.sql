-- Unapplied candidate, AC-309 FR-336. Module-owned; no shared function replacement.
alter table procurement.requisitions
 add column document_number text,
 add column workflow_snapshot jsonb,
 add column submitted_by uuid references auth.users(id),
 add column submitted_at timestamptz,
 add constraint requisition_number_unique unique(tenant_id,legal_entity_id,branch_id,document_number);
create index requisitions_submitter on procurement.requisitions(submitted_by);
create index requisitions_creator on procurement.requisitions(created_by);
create index requisitions_editor on procurement.requisitions(updated_by);
create index requisitions_currency on procurement.requisitions(currency_code);

create table procurement.requisition_history (
 id uuid primary key default gen_random_uuid(),
 tenant_id uuid not null,
 legal_entity_id uuid not null,
 requisition_id uuid not null,
 version bigint not null,
 snapshot jsonb not null check(jsonb_typeof(snapshot)='object'),
 actor_id uuid not null references auth.users(id),
 created_at timestamptz not null default now(),
 unique(requisition_id,version),
 foreign key(tenant_id,legal_entity_id,requisition_id) references procurement.requisitions(tenant_id,legal_entity_id,id)
);
create index requisition_history_source on procurement.requisition_history(tenant_id,legal_entity_id,requisition_id);
create index requisition_history_actor on procurement.requisition_history(actor_id);
alter table procurement.requisition_history enable row level security;
alter table procurement.requisition_history force row level security;
create policy requisition_history_read on procurement.requisition_history for select to authenticated
using(exists(select 1 from procurement.requisitions r where r.id=requisition_id
 and r.tenant_id=requisition_history.tenant_id and r.legal_entity_id=requisition_history.legal_entity_id));
create trigger requisition_history_immutable before update or delete on procurement.requisition_history
for each row execute function workflow.reject_history_mutation();
revoke all on procurement.requisition_history from public,anon,authenticated;
grant select on procurement.requisition_history to authenticated;

-- Do not install a trigger on shared receipts: history is written by module-owned commands.
-- Wrap only this session's unpublished requisition function; signature remains stable.
alter function api.upsert_purchase_requisition(uuid,uuid,uuid,uuid,uuid,timestamptz,jsonb,bigint)
 set schema procurement;
alter function procurement.upsert_purchase_requisition(uuid,uuid,uuid,uuid,uuid,timestamptz,jsonb,bigint)
 rename to save_requisition_draft;
revoke all on function procurement.save_requisition_draft(uuid,uuid,uuid,uuid,uuid,timestamptz,jsonb,bigint) from public,anon,authenticated;

create function procurement.record_requisition_history(p_result jsonb) returns void
language plpgsql security definer set search_path='' as $$begin
 insert into procurement.requisition_history(tenant_id,legal_entity_id,requisition_id,version,snapshot,actor_id)
 select r.tenant_id,r.legal_entity_id,r.id,(p_result#>>'{entity,version}')::bigint,p_result->'entity',auth.uid()
 from procurement.requisitions r where r.id=(p_result#>>'{entity,id}')::uuid
 on conflict(requisition_id,version) do nothing;
end $$;
create function api.upsert_purchase_requisition(
 p_tenant_id uuid,p_legal_entity_id uuid,p_branch_id uuid,p_command_id uuid,p_idempotency_key uuid,
 p_client_timestamp timestamptz,p_payload jsonb,p_expected_entity_version bigint default null)
returns jsonb language plpgsql security definer set search_path='' as $$declare v_result jsonb;begin
 v_result:=procurement.save_requisition_draft(p_tenant_id,p_legal_entity_id,p_branch_id,p_command_id,p_idempotency_key,
 p_client_timestamp,p_payload,p_expected_entity_version);
 perform procurement.record_requisition_history(v_result);return v_result;end $$;

create or replace view api.purchase_requisitions with(security_invoker=true) as
select r.tenant_id,r.legal_entity_id,r.branch_id,r.id,r.status,
 jsonb_build_object('id',r.id,'requester_id',r.requester_id,'need_by',r.need_by,
 'justification',r.justification,'currency_code',r.currency_code,'document_number',r.document_number,
 'estimated_total',r.estimated_total::text,'status',r.status,'version',r.version,
 'workflow_snapshot',r.workflow_snapshot,'created_by',r.created_by,'updated_by',r.updated_by,
 'submitted_by',r.submitted_by,'submitted_at',r.submitted_at,'created_at',r.created_at,
 'lines',coalesce((select jsonb_agg(jsonb_build_object('line_id',l.id,'product_id',l.product_id,
 'description',l.description,'unit_id',l.unit_id,'quantity',l.quantity::text,
 'estimated_unit_price',l.estimated_unit_price::text,'estimated_total',l.estimated_total::text,
 'base_quantity',l.base_quantity::text,'conversion_numerator',l.conversion_numerator::text,
 'conversion_denominator',l.conversion_denominator::text,'conversion_id',l.conversion_id,'conversion_version',l.conversion_version) order by l.ordinal)
 from procurement.requisition_lines l where l.requisition_id=r.id),'[]'::jsonb)) detail
from procurement.requisitions r;

create function api.transition_purchase_requisition(
 p_tenant_id uuid,p_legal_entity_id uuid,p_branch_id uuid,p_command_id uuid,p_idempotency_key uuid,
 p_client_timestamp timestamptz,p_payload jsonb,p_expected_entity_version bigint default null)
returns jsonb language plpgsql security definer set search_path='' as $$
declare
 v_actor uuid:=auth.uid();v_id uuid;v_action text:=p_payload->>'action';v_decision text:=p_payload->>'decision';
 v_command text:='procurement.requisition.transition';v_hash text;v_result jsonb;v_before jsonb;v_entity jsonb;
 v_doc procurement.requisitions%rowtype;v_workflow workflow.workflow_definitions%rowtype;
 v_ar workflow.approval_requests%rowtype;v_snapshot jsonb;v_step jsonb;v_first integer;v_to text;
 v_request uuid:=gen_random_uuid();v_reason text:=nullif(trim(coalesce(p_payload->>'reason',p_payload->>'note')),'');
begin
 perform core.wave3_require_scope(p_tenant_id,'procurement.requisitions.manage',p_legal_entity_id,p_branch_id);
 if p_legal_entity_id is null or p_branch_id is null or p_client_timestamp is null
 or jsonb_typeof(p_payload) is distinct from 'object' or (v_action is null)=(v_decision is null) then
 raise exception using errcode='22023',message='INVALID_COMMAND';end if;
 if v_decision is not null then
  perform core.require_permission(p_tenant_id,'workflow.approvals.decide',p_legal_entity_id,p_branch_id);
 end if;
 v_id:=(p_payload->>'document_id')::uuid;
 v_hash:=core.wave3_request_hash(v_command,p_command_id,p_tenant_id,p_legal_entity_id,p_branch_id,p_payload,p_expected_entity_version);
 v_result:=core.wave3_replay(p_tenant_id,v_command,p_command_id,p_idempotency_key,v_hash);
 if v_result is not null then return v_result;end if;
 select * into v_doc from procurement.requisitions where id=v_id and tenant_id=p_tenant_id
 and legal_entity_id=p_legal_entity_id and branch_id=p_branch_id for update;
 if not found then raise exception using errcode='P0002',message='DOCUMENT_NOT_FOUND';end if;
 select detail into v_before from api.purchase_requisitions where id=v_id;
 perform core.wave3_assert_expected_version(v_doc.version,p_expected_entity_version,v_before);
 v_snapshot:=v_doc.workflow_snapshot;
 if v_action='submit' then
  if v_doc.status<>'draft' then raise exception using errcode='55000',message='REQUISITION_NOT_EDITABLE';end if;
  if not exists(select 1 from core.memberships where tenant_id=p_tenant_id and user_id=v_doc.requester_id and status='active')
  or exists(select 1 from procurement.requisition_lines l left join inventory.units u on u.id=l.unit_id and u.tenant_id=l.tenant_id
    left join inventory.products p on p.id=l.product_id and p.tenant_id=l.tenant_id and p.legal_entity_id=l.legal_entity_id
    where l.requisition_id=v_id and (u.status is distinct from 'active' or round(l.quantity,u.precision)<>l.quantity
    or (l.product_id is not null and (p.status is distinct from 'active' or not p.can_purchase)))) then
   raise exception using errcode='22023',message='REFERENCE_INVALID';end if;
  perform inventory.resolve_product_unit(p_tenant_id,p_legal_entity_id,l.product_id,l.unit_id,to_jsonb(l.quantity::text),
    to_jsonb(l.conversion_numerator::text),to_jsonb(l.conversion_denominator::text)) from procurement.requisition_lines l where l.requisition_id=v_id;
  select * into v_workflow from workflow.workflow_definitions where tenant_id=p_tenant_id
   and document_type='purchase_requisition' and status='active' and (legal_entity_id is null or legal_entity_id=p_legal_entity_id)
   order by (legal_entity_id is not null) desc,revision desc,id limit 1;
  if not found then raise exception using errcode='55000',message='WORKFLOW_CONFIGURATION_ERROR';end if;
  select jsonb_build_object('definition_id',v_workflow.id,'revision',v_workflow.revision,'lifecycle',v_workflow.lifecycle,
   'steps',coalesce(jsonb_agg(sales.flow_exact_json(to_jsonb(s)) order by s.step_order),'[]'::jsonb)) into v_snapshot
   from workflow.approval_matrix_steps s where s.tenant_id=p_tenant_id and s.workflow_definition_id=v_workflow.id and s.status='active'
   and (s.currency_code is null or s.currency_code=v_doc.currency_code)
   and (s.minimum_amount is null or s.minimum_amount<=v_doc.estimated_total)
   and (s.maximum_amount is null or s.maximum_amount>=v_doc.estimated_total);
  select min((x->>'step_order')::integer) into v_first from jsonb_array_elements(v_snapshot->'steps') x;
  if v_first is null and v_workflow.lifecycle->'requires_approval' is distinct from 'false'::jsonb then
   raise exception using errcode='55000',message='WORKFLOW_CONFIGURATION_ERROR';end if;
  perform sales.flow_assert_transition(v_workflow.lifecycle,'draft','submitted');
  v_to:=case when v_first is null then 'approved' else 'pending_approval' end;
  if v_first is null then perform sales.flow_assert_transition(v_workflow.lifecycle,'submitted','approved');end if;
  v_doc.document_number:=coalesce(v_doc.document_number,sales.wave3_reserve_document_number(p_tenant_id,p_legal_entity_id,
    p_branch_id,'purchase_requisition',(v_doc.created_at at time zone 'UTC')::date,v_actor));
  if v_first is not null then
   insert into workflow.approval_requests(tenant_id,legal_entity_id,branch_id,document_type,document_id,status,
    submitted_by,workflow_definition_id,workflow_revision,current_step,amount,currency_code,command_id,request_id,correlation_id)
   values(p_tenant_id,p_legal_entity_id,p_branch_id,'purchase_requisition',v_id,'submitted',v_actor,
    v_workflow.id,v_workflow.revision,v_first,v_doc.estimated_total,v_doc.currency_code,p_command_id,v_request,v_request);
  end if;
 elsif v_decision is not null then
  if v_doc.status<>'pending_approval' or v_decision not in ('approved','rejected') then
   raise exception using errcode='55000',message='APPROVAL_NOT_PENDING';end if;
  select * into v_ar from workflow.approval_requests where tenant_id=p_tenant_id and document_type='purchase_requisition'
   and document_id=v_id and status='submitted' for update;
  if not found then raise exception using errcode='55000',message='APPROVAL_REQUEST_NOT_FOUND';end if;
  if v_actor in(v_doc.requester_id,v_doc.created_by,v_doc.updated_by,v_doc.submitted_by) then
   raise exception using errcode='42501',message='SEGREGATION_OF_DUTIES_VIOLATION';end if;
  select x into v_step from jsonb_array_elements(v_snapshot->'steps') x where (x->>'step_order')::integer=v_ar.current_step;
  if v_step is null or not exists(select 1 from core.memberships m
   join core.role_assignments ra on ra.membership_id=m.id and ra.tenant_id=m.tenant_id
   join core.roles r on r.id=ra.role_id and r.tenant_id=m.tenant_id
   where m.tenant_id=p_tenant_id and m.user_id=v_actor and m.status='active' and ra.role_id=(v_step->>'role_id')::uuid
   and (ra.legal_entity_id is null or ra.legal_entity_id=p_legal_entity_id) and (ra.branch_id is null or ra.branch_id=p_branch_id)
   and (not r.requires_mfa or auth.jwt()->>'aal'='aal2')) then
   raise exception using errcode='42501',message='APPROVAL_ROLE_REQUIRED';end if;
  if v_decision='rejected' and v_reason is null then raise exception using errcode='22023',message='REASON_REQUIRED';end if;
  perform sales.flow_assert_transition(v_snapshot->'lifecycle','submitted',v_decision);
  insert into workflow.approval_decisions(tenant_id,approval_request_id,workflow_definition_id,workflow_revision,
   approval_matrix_step_id,step_order,actor_id,decision,note,amount,currency_code,request_id,command_id,correlation_id)
  values(p_tenant_id,v_ar.id,v_ar.workflow_definition_id,v_ar.workflow_revision,(v_step->>'id')::uuid,v_ar.current_step,
   v_actor,v_decision,v_reason,v_ar.amount,v_ar.currency_code,v_request,p_command_id,v_request);
  if v_decision='approved' then
   select min((x->>'step_order')::integer) into v_first from jsonb_array_elements(v_snapshot->'steps') x
    where (x->>'step_order')::integer>v_ar.current_step;
  end if;
  v_to:=case when v_decision='rejected' then 'rejected' when v_first is null then 'approved' else 'pending_approval' end;
  update workflow.approval_requests set current_step=coalesce(v_first,current_step),
   status=case when v_first is null then v_to else status end,
   decision_by=case when v_first is null then v_actor else decision_by end,
   decision_note=case when v_first is null then v_reason else decision_note end,
   decided_at=case when v_first is null then clock_timestamp() else decided_at end where id=v_ar.id;
 elsif v_action in('recall','cancel') then
  if v_reason is null then raise exception using errcode='22023',message='REASON_REQUIRED';end if;
  if v_snapshot is null then
   select jsonb_build_object('lifecycle',lifecycle) into v_snapshot from workflow.workflow_definitions
    where tenant_id=p_tenant_id and document_type='purchase_requisition' and status='active'
    and (legal_entity_id is null or legal_entity_id=p_legal_entity_id)
    order by (legal_entity_id is not null) desc,revision desc,id limit 1;
  end if;
  v_to:=case when v_action='recall' then 'draft' else 'cancelled' end;
  perform sales.flow_assert_transition(v_snapshot->'lifecycle',v_doc.status,v_to);
  update workflow.approval_requests set status='cancelled',decision_by=v_actor,decision_note=v_reason,decided_at=clock_timestamp()
   where tenant_id=p_tenant_id and document_type='purchase_requisition' and document_id=v_id and status='submitted';
  if v_action='recall' then v_snapshot:=null;end if;
 else raise exception using errcode='22023',message='INVALID_COMMAND';end if;
 update procurement.requisitions set status=v_to,version=version+1,updated_at=clock_timestamp(),updated_by=v_actor,
  workflow_snapshot=v_snapshot,document_number=v_doc.document_number,
  submitted_by=case when v_action='submit' then v_actor else submitted_by end,
  submitted_at=case when v_action='submit' then clock_timestamp() else submitted_at end where id=v_id;
 select detail into v_entity from api.purchase_requisitions where id=v_id;
 v_result:=core.wave3_finish_command(p_tenant_id,v_command,p_command_id,'purchase_requisition',v_id,
  p_idempotency_key,v_hash,v_before,v_entity,p_legal_entity_id,p_branch_id,'{}',
  case when v_doc.status=v_to then null else jsonb_build_object('from_status',v_doc.status,'to_status',v_to,'reason',v_reason) end,
  jsonb_build_array(jsonb_build_object('topic',v_command,'payload',jsonb_build_object('status',v_to))),'[]',v_request,v_request);
 perform procurement.record_requisition_history(v_result);return v_result;
end $$;
revoke all on function procurement.record_requisition_history(jsonb) from public,anon,authenticated;
revoke all on function api.upsert_purchase_requisition(uuid,uuid,uuid,uuid,uuid,timestamptz,jsonb,bigint),
 api.transition_purchase_requisition(uuid,uuid,uuid,uuid,uuid,timestamptz,jsonb,bigint) from public,anon;
grant execute on function api.upsert_purchase_requisition(uuid,uuid,uuid,uuid,uuid,timestamptz,jsonb,bigint),
 api.transition_purchase_requisition(uuid,uuid,uuid,uuid,uuid,timestamptz,jsonb,bigint) to authenticated;
