-- Candidate only. Manual source aggregate; posting uses the existing journal engine.
create table finance.manual_journals (
 id uuid primary key,tenant_id uuid not null references core.tenants(id),legal_entity_id uuid not null,branch_id uuid not null,
 document_type text not null default 'manual_journal' check(document_type='manual_journal'),document_number text,document_date date not null,
 reason text not null,description text not null,currency_code text not null references core.currencies(code),
 grand_total numeric(20,6) not null check(grand_total>0),snapshot jsonb not null,reversal_of_id uuid,
 status text not null default 'draft' check(status in('draft','pending_approval','approved','rejected','cancelled','posted')),
 version bigint not null default 1,workflow_snapshot jsonb,submitted_by uuid references auth.users(id),
 prepared_by uuid not null references auth.users(id),posted_by uuid references auth.users(id),posted_at timestamptz,journal_entry_id uuid,
 request_id uuid not null,command_id uuid not null,correlation_id uuid not null,client_timestamp timestamptz not null,
 created_by uuid not null references auth.users(id),updated_by uuid not null references auth.users(id),
 created_at timestamptz not null default now(),updated_at timestamptz not null default now(),
 unique(tenant_id,id),unique(tenant_id,legal_entity_id,branch_id,document_number),
 foreign key(tenant_id,legal_entity_id) references core.legal_entities(tenant_id,id),
 foreign key(tenant_id,branch_id) references core.branches(tenant_id,id),
 foreign key(tenant_id,reversal_of_id) references finance.manual_journals(tenant_id,id),
 foreign key(tenant_id,journal_entry_id) references finance.journal_entries(tenant_id,id),
 check((status='posted')=(posted_at is not null)),check(status<>'posted' or posted_by is not null)
);
create unique index manual_one_posted_reversal on finance.manual_journals(tenant_id,reversal_of_id) where status='posted';
create index manual_journals_scope on finance.manual_journals(tenant_id,legal_entity_id,branch_id,id);
alter table finance.manual_journals enable row level security;
alter table finance.manual_journals force row level security;
revoke all on finance.manual_journals from public,anon,authenticated;
create trigger manual_immutable before update or delete on finance.manual_journals for each row execute function sales.flow_protect_document();
create trigger manual_touch before update on finance.manual_journals for each row execute function core.touch_mutable_record();
do $$declare f record;begin
 for f in select c.conname,(select string_agg(quote_ident(a.attname),',' order by k.n) from unnest(c.conkey) with ordinality k(num,n)
 join pg_attribute a on a.attrelid=c.conrelid and a.attnum=k.num) cols from pg_constraint c where c.conrelid='finance.manual_journals'::regclass and c.contype='f' loop
 execute format('create index %I on finance.manual_journals(%s)',f.conname||'_idx',f.cols);end loop;
end$$;

create function finance.manual_command_access(t uuid,e uuid,b uuid,p jsonb) returns void
language plpgsql security definer set search_path='' as $$declare d finance.manual_journals%rowtype;begin
 select * into d from finance.manual_journals where tenant_id=t and legal_entity_id=e and branch_id=b and id=coalesce((p->>'id')::uuid,(p->>'document_id')::uuid);
 if d.reversal_of_id is not null or p->>'reversal_of_id' is not null then perform core.require_permission(t,'finance.reversals.post',e,b);end if;
 if coalesce(jsonb_array_length(d.snapshot->'attachments'),0)>0 or (p->'attachment_ids' is not null and p->'attachment_ids'<>'[]'::jsonb) then
 perform core.require_permission(t,'core.files.view',e,b);end if;
end$$;
revoke all on function finance.manual_command_access(uuid,uuid,uuid,jsonb) from public,anon,authenticated;

create function finance.manual_document(p_kind text,t uuid,v_id uuid,p_lock boolean default false) returns jsonb
language plpgsql security definer set search_path='' as $$declare d finance.manual_journals%rowtype;begin
 if p_kind is distinct from 'manual_journal' then raise exception using errcode='22023',message='DOCUMENT_TYPE_INVALID';end if;
 if p_lock then select * into d from finance.manual_journals where tenant_id=t and id=v_id for update;
 else select * into d from finance.manual_journals where tenant_id=t and id=v_id;end if;
 if not found then return null;end if;
 return d.snapshot||(sales.flow_exact_json(to_jsonb(d))-'snapshot');
end$$;

create function finance.manual_normalize(t uuid,e uuid,b uuid,p jsonb) returns jsonb
language plpgsql security definer set search_path='' as $$
declare d date:=(p->>'document_date')::date;c text:=p->>'currency_code';fx jsonb;rate numeric;x jsonb;a finance.accounts%rowtype;
 lines jsonb:='[]';attachments jsonb:='[]';deb numeric:=0;cred numeric:=0;prevdeb numeric:=0;prevcred numeric:=0;
 debit numeric;credit numeric;base numeric;line_id uuid;ids uuid[]:='{}';file_id uuid;f core.attachments%rowtype;
 original jsonb;rawlines jsonb;reversal uuid:=(p->>'reversal_of_id')::uuid;begin
 if d is null or d>(clock_timestamp() at time zone 'UTC')::date or length(coalesce(trim(p->>'reason'),'')) not between 3 and 1000
 or length(coalesce(trim(p->>'description'),'')) not between 3 and 1000 then raise exception using errcode='22023',message='JOURNAL_INPUT_INVALID';end if;
 perform 1 from core.legal_entities where tenant_id=t and id=e for share;
 rawlines:=p->'lines';
 if reversal is not null then
  perform core.require_permission(t,'finance.reversals.post',e,b);
  original:=finance.manual_document('manual_journal',t,reversal,true);
  if original is null or original->>'legal_entity_id'<>e::text or original->>'branch_id'<>b::text or original->>'status'<>'posted'
   or original->>'reversal_of_id' is not null then raise exception using errcode='55000',message='JOURNAL_REVERSAL_INVALID';end if;
  if d<(original->>'document_date')::date then raise exception using errcode='22023',message='REVERSAL_DATE_INVALID';end if;
  if exists(select 1 from finance.manual_journals where tenant_id=t and reversal_of_id=reversal and status='posted') then
   raise exception using errcode='55000',message='JOURNAL_ALREADY_REVERSED';end if;
  c:=original->>'currency_code';
  fx:=jsonb_build_object('base_currency_code',original->>'base_currency_code','exchange_rate',original->>'exchange_rate',
   'exchange_rate_id',original->'exchange_rate_id','rate_date',original->'rate_date');
  if fx->>'base_currency_code' is distinct from (select currency_code from core.legal_entities where tenant_id=t and id=e) then
   raise exception using errcode='55000',message='JOURNAL_REAPPROVAL_REQUIRED';end if;
  select jsonb_agg(z.item||jsonb_build_object('debit',z.item->'credit','credit',z.item->'debit','base_amount',(-(z.item->>'base_amount')::numeric)::text)
   order by ord) into rawlines from jsonb_array_elements(original->'lines') with ordinality z(item,ord);
 else
  perform 1 from finance.exchange_rates where tenant_id=t and legal_entity_id=e and id=(p->>'exchange_rate_id')::uuid for share;
  fx:=finance.flow_rate(t,e,c,d,(p->>'exchange_rate_id')::uuid);
 end if;
 rate:=(fx->>'exchange_rate')::numeric;
 if jsonb_typeof(rawlines) is distinct from 'array' or jsonb_array_length(rawlines) not between 2 and 200 then
  raise exception using errcode='22023',message='JOURNAL_LINES_INVALID';end if;
 for x in select value from jsonb_array_elements(rawlines) loop
  line_id:=(x->>'line_id')::uuid;
  if line_id is null or line_id=any(ids) or length(coalesce(x->>'description',''))>500 or length(coalesce(x->>'cost_center',''))>100
   or length(coalesce(x->>'project',''))>100 then raise exception using errcode='22023',message='JOURNAL_LINE_INVALID';end if;
  ids:=array_append(ids,line_id);
  debit:=sales.wave3_decimal_string(x->'debit','debit',6,true,0,null)::numeric;
  credit:=sales.wave3_decimal_string(x->'credit','credit',6,true,0,null)::numeric;
  if (debit>0)=(credit>0) then raise exception using errcode='22023',message='JOURNAL_LINE_SIDES_INVALID';end if;
  select * into a from finance.accounts where tenant_id=t and legal_entity_id=e and id=(x->>'account_id')::uuid and status='active' and is_posting
   and (currency_code is null or currency_code=c) for share;
  if not found then raise exception using errcode='55000',message='ACCOUNT_MAPPING_INVALID';end if;
  if exists(select 1 from finance.posting_mappings where tenant_id=t and legal_entity_id=e and account_id=a.id and purpose in('receivable_control','payable_control'))
   or exists(select 1 from procurement.supplier_bill_controls where tenant_id=t and legal_entity_id=e and payable_account_id=a.id)
   or exists(select 1 from finance.journal_lines jl join finance.open_items oi on oi.journal_entry_id=jl.journal_entry_id and oi.tenant_id=jl.tenant_id
    where jl.tenant_id=t and jl.legal_entity_id=e and jl.account_id=a.id
    and ((oi.kind='AR' and a.account_type='asset' and jl.base_debit-jl.base_credit=oi.original_base_amount)
      or(oi.kind='AP' and a.account_type='liability' and jl.base_credit-jl.base_debit=oi.original_base_amount))) then
   raise exception using errcode='55000',message='SUBLEDGER_CONTROL_REQUIRES_SOURCE';end if;
  deb:=deb+debit;cred:=cred+credit;
  base:=case when debit>0 then round(deb*rate,6)-prevdeb else -(round(cred*rate,6)-prevcred) end;
  prevdeb:=round(deb*rate,6);prevcred:=round(cred*rate,6);
  if reversal is not null then base:=(x->>'base_amount')::numeric;end if;
  if base=0 then raise exception using errcode='22023',message='AMOUNT_BELOW_BASE_PRECISION';end if;
  lines:=lines||jsonb_build_array(jsonb_build_object('line_id',line_id,'account_id',a.id,'account_code',a.code,'account_name',a.name,
   'debit',debit::text,'credit',credit::text,'amount',(debit-credit)::text,'base_amount',base::text,
   'description',coalesce(x->>'description',''),'cost_center',coalesce(x->>'cost_center',''),'project',coalesce(x->>'project','')));
 end loop;
 if deb<>cred or (select sum((z.item->>'base_amount')::numeric) from jsonb_array_elements(lines)z(item))<>0 then raise exception using errcode='23514',message='UNBALANCED_JOURNAL';end if;
 if jsonb_typeof(coalesce(p->'attachment_ids','[]')) is distinct from 'array' or jsonb_array_length(coalesce(p->'attachment_ids','[]'))>20 then
  raise exception using errcode='22023',message='JOURNAL_ATTACHMENTS_INVALID';end if;
 ids:='{}';
 for file_id in select value::uuid from jsonb_array_elements_text(coalesce(p->'attachment_ids','[]')) loop
  perform core.require_permission(t,'core.files.view',e,b);
  select * into f from core.attachments where tenant_id=t and id=file_id and upload_status='ready' and checksum_sha256 is not null
   and ((aggregate_type='legal_entity' and aggregate_id=e) or (aggregate_type='branch' and aggregate_id=b)) for share;
  if not found or file_id=any(ids) then raise exception using errcode='22023',message='JOURNAL_ATTACHMENT_INVALID';end if;
  ids:=array_append(ids,file_id);attachments:=attachments||jsonb_build_array(jsonb_build_object('id',f.id,'file_name',f.file_name,'checksum_sha256',f.checksum_sha256));
 end loop;
 return fx||jsonb_build_object('document_date',d,'reason',trim(p->>'reason'),'description',trim(p->>'description'),'currency_code',c,
  'lines',lines,'grand_total',deb::text,'base_total',prevdeb::text,'attachment_ids',to_jsonb(ids),'attachments',attachments,'reversal_of_id',reversal);
end$$;

create function finance.manual_revalidate(p_kind text,d jsonb) returns jsonb language plpgsql security definer set search_path='' as $$declare fresh jsonb;begin
 fresh:=finance.manual_normalize((d->>'tenant_id')::uuid,(d->>'legal_entity_id')::uuid,(d->>'branch_id')::uuid,d);
 if fresh-'reason'-'description'-'document_date' is distinct from (select snapshot-'reason'-'description'-'document_date' from finance.manual_journals where id=(d->>'id')::uuid) then
  raise exception using errcode='55000',message='JOURNAL_REAPPROVAL_REQUIRED';end if;
 return fresh;
end$$;

create function api.upsert_manual_journal(p_tenant_id uuid,p_legal_entity_id uuid,p_branch_id uuid,p_command_id uuid,p_idempotency_key uuid,
 p_client_timestamp timestamptz,p_payload jsonb,p_expected_entity_version bigint default null) returns jsonb
language plpgsql security definer set search_path='' as $$declare v_id uuid:=(p_payload->>'id')::uuid;req uuid:=gen_random_uuid();h text;r jsonb;old_doc jsonb;d jsonb;begin
 perform core.wave3_require_scope(p_tenant_id,'finance.journals.post',p_legal_entity_id,p_branch_id);
 perform core.require_permission(p_tenant_id,'finance.view',p_legal_entity_id,p_branch_id);
 if v_id is null or p_branch_id is null or p_legal_entity_id is null or p_client_timestamp is null then raise exception using errcode='22023',message='JOURNAL_INPUT_INVALID';end if;
 perform finance.manual_command_access(p_tenant_id,p_legal_entity_id,p_branch_id,p_payload);
 h:=core.wave3_request_hash('finance.manual_journal.upsert',p_command_id,p_tenant_id,p_legal_entity_id,p_branch_id,p_payload,p_expected_entity_version);
 r:=core.wave3_replay(p_tenant_id,'finance.manual_journal.upsert',p_command_id,p_idempotency_key,h);if r is not null then return r;end if;
 perform pg_advisory_xact_lock(hashtextextended(p_tenant_id::text||':manual:'||v_id::text,0));
 old_doc:=finance.manual_document('manual_journal',p_tenant_id,v_id,true);
 if old_doc is not null then
  if old_doc->>'legal_entity_id'<>p_legal_entity_id::text or old_doc->>'branch_id'<>p_branch_id::text then raise exception using errcode='42501',message='DOCUMENT_SCOPE_INVALID';end if;
  perform core.wave3_assert_expected_version((old_doc->>'version')::bigint,p_expected_entity_version,old_doc);
  if old_doc->>'status'<>'draft' then raise exception using errcode='55000',message='DOCUMENT_NOT_EDITABLE';end if;
 else perform core.wave3_assert_expected_version(0,p_expected_entity_version,'{}');end if;
 d:=finance.manual_normalize(p_tenant_id,p_legal_entity_id,p_branch_id,p_payload);
 if old_doc is null then
 insert into finance.manual_journals(id,tenant_id,legal_entity_id,branch_id,document_date,reason,description,currency_code,grand_total,snapshot,reversal_of_id,
 prepared_by,created_by,updated_by,request_id,command_id,correlation_id,client_timestamp)
 values(v_id,p_tenant_id,p_legal_entity_id,p_branch_id,(d->>'document_date')::date,d->>'reason',d->>'description',d->>'currency_code',(d->>'grand_total')::numeric,d,
 (d->>'reversal_of_id')::uuid,auth.uid(),auth.uid(),auth.uid(),req,p_command_id,req,p_client_timestamp);
 else update finance.manual_journals set document_date=(d->>'document_date')::date,reason=d->>'reason',description=d->>'description',currency_code=d->>'currency_code',
 grand_total=(d->>'grand_total')::numeric,snapshot=d,reversal_of_id=(d->>'reversal_of_id')::uuid,prepared_by=auth.uid(),updated_by=auth.uid(),
 request_id=req,command_id=p_command_id,correlation_id=req,client_timestamp=p_client_timestamp where tenant_id=p_tenant_id and id=v_id;end if;
 return core.wave3_finish_command(p_tenant_id,'finance.manual_journal.upsert',p_command_id,'manual_journal',v_id,p_idempotency_key,h,old_doc,
 finance.manual_document('manual_journal',p_tenant_id,v_id),p_legal_entity_id,p_branch_id,'{}',null,
 jsonb_build_array(jsonb_build_object('topic','finance.manual_journal.upsert','payload',jsonb_build_object('id',v_id))),'[]',req,req);
end$$;

create function api.transition_manual_journal(p_tenant_id uuid,p_legal_entity_id uuid,p_branch_id uuid,p_command_id uuid,
 p_idempotency_key uuid,p_client_timestamp timestamptz,p_payload jsonb,p_expected_entity_version bigint default null)
returns jsonb language plpgsql security definer set search_path='' as $$
declare v_kind text:='manual_journal';v_id uuid:=(p_payload->>'document_id')::uuid;
 v_action text:=p_payload->>'action';v_decision text:=p_payload->>'decision';v_command text;
 v_doc jsonb;v_before jsonb;v_hash text;v_replay jsonb;v_to text;v_snapshot jsonb;
 v_workflow workflow.workflow_definitions%rowtype;v_request uuid:=gen_random_uuid();v_first integer;
 v_ar workflow.approval_requests%rowtype;v_step jsonb;v_number text;
begin
 v_command:='finance.'||v_kind||case when v_decision is null then '.transition' else '.decide' end;
 perform core.wave3_require_scope(p_tenant_id,case when v_decision is null then 'finance.journals.post' else 'workflow.approvals.decide' end,p_legal_entity_id,p_branch_id);
 perform core.require_permission(p_tenant_id,'finance.view',p_legal_entity_id,p_branch_id);
 if p_legal_entity_id is null or p_branch_id is null or p_client_timestamp is null
 or (p_payload ? 'document_type' and p_payload->>'document_type' is distinct from 'manual_journal')
 or (v_decision is not null and v_action is not null) then raise exception using errcode='22023',message='DOCUMENT_PAYLOAD_INVALID';end if;
 perform finance.manual_command_access(p_tenant_id,p_legal_entity_id,p_branch_id,p_payload);
 v_hash:=core.wave3_request_hash(v_command,p_command_id,p_tenant_id,p_legal_entity_id,p_branch_id,p_payload,p_expected_entity_version);
 v_replay:=core.wave3_replay(p_tenant_id,v_command,p_command_id,p_idempotency_key,v_hash);if v_replay is not null then return v_replay;end if;
 v_doc:=finance.manual_document(v_kind,p_tenant_id,v_id,true);v_before:=v_doc;
 if v_doc is null or (v_doc->>'legal_entity_id')::uuid<>p_legal_entity_id or (v_doc->>'branch_id')::uuid<>p_branch_id then
 raise exception using errcode='P0002',message='DOCUMENT_NOT_FOUND';end if;
 perform core.wave3_assert_expected_version((v_doc->>'version')::bigint,p_expected_entity_version,v_doc);
 if v_doc->>'status'='posted' then raise exception using errcode='55000',message='POSTED_DOCUMENT_IMMUTABLE';end if;
 v_snapshot:=v_doc->'workflow_snapshot';v_number:=v_doc->>'document_number';
 if v_decision is not null then
 if v_decision not in ('approved','rejected') or v_doc->>'status'<>'pending_approval' then raise exception using errcode='55000',message='APPROVAL_NOT_PENDING';end if;
 select * into v_ar from workflow.approval_requests where tenant_id=p_tenant_id and document_type=v_kind and document_id=v_id and status='submitted' for update;
 if not found then raise exception using errcode='55000',message='APPROVAL_REQUEST_NOT_FOUND';end if;
 if v_ar.submitted_by=auth.uid() or (v_doc->>'created_by')::uuid=auth.uid() or (v_doc->>'prepared_by')::uuid=auth.uid() then raise exception using errcode='42501',message='SEGREGATION_OF_DUTIES_VIOLATION';end if;
 select x into v_step from jsonb_array_elements(v_snapshot->'steps') x where (x->>'step_order')::integer=v_ar.current_step;
 if v_step is null or not exists(select 1 from core.memberships m join core.role_assignments ra on ra.tenant_id=m.tenant_id and ra.membership_id=m.id
 join core.roles r on r.id=ra.role_id and r.tenant_id=m.tenant_id
 where m.tenant_id=p_tenant_id and m.user_id=auth.uid() and m.status='active' and ra.role_id=(v_step->>'role_id')::uuid
 and (ra.legal_entity_id is null or ra.legal_entity_id=p_legal_entity_id) and (ra.branch_id is null or ra.branch_id=p_branch_id)
 and (not r.requires_mfa or auth.jwt()->>'aal'='aal2')) then raise exception using errcode='42501',message='APPROVAL_ROLE_REQUIRED';end if;
 if v_decision='rejected' and nullif(trim(p_payload->>'note'),'') is null then raise exception using errcode='22023',message='REASON_REQUIRED';end if;
 perform sales.flow_assert_transition(v_snapshot->'lifecycle','submitted',v_decision);
 insert into workflow.approval_decisions(tenant_id,approval_request_id,workflow_definition_id,workflow_revision,
 approval_matrix_step_id,step_order,actor_id,decision,note,amount,currency_code,request_id,command_id,correlation_id)
 values(p_tenant_id,v_ar.id,v_ar.workflow_definition_id,v_ar.workflow_revision,(v_step->>'id')::uuid,v_ar.current_step,
 auth.uid(),v_decision,p_payload->>'note',v_ar.amount,v_ar.currency_code,v_request,p_command_id,v_request);
 if v_decision='approved' then select min((x->>'step_order')::integer) into v_first from jsonb_array_elements(v_snapshot->'steps') x
 where (x->>'step_order')::integer>v_ar.current_step;end if;
 v_to:=case when v_decision='rejected' then 'rejected' when v_first is null then 'approved' else 'pending_approval' end;
 if v_first is null then update workflow.approval_requests set status=v_to,decision_by=auth.uid(),decision_note=p_payload->>'note',decided_at=clock_timestamp() where id=v_ar.id;
 else update workflow.approval_requests set current_step=v_first where id=v_ar.id;end if;
 elsif v_action='submit' then
 if v_doc->>'status'<>'draft' then raise exception using errcode='55000',message='DOCUMENT_NOT_EDITABLE';end if;
 perform finance.manual_revalidate(v_kind,v_doc);
 select * into v_workflow from workflow.workflow_definitions where tenant_id=p_tenant_id and document_type=v_kind and status='active'
 and (legal_entity_id is null or legal_entity_id=p_legal_entity_id) order by (legal_entity_id is not null) desc limit 1;
 if not found then raise exception using errcode='55000',message='WORKFLOW_CONFIGURATION_ERROR';end if;
 select jsonb_build_object('definition_id',v_workflow.id,'revision',v_workflow.revision,'lifecycle',v_workflow.lifecycle,
 'steps',coalesce(jsonb_agg(sales.flow_exact_json(to_jsonb(s)) order by s.step_order),'[]'::jsonb)) into v_snapshot
 from workflow.approval_matrix_steps s where s.tenant_id=p_tenant_id and s.workflow_definition_id=v_workflow.id and s.status='active'
 and (s.currency_code is null or s.currency_code=v_doc->>'currency_code')
 and (s.minimum_amount is null or (v_doc->>'grand_total')::numeric>=s.minimum_amount)
 and (s.maximum_amount is null or (v_doc->>'grand_total')::numeric<=s.maximum_amount);
 if v_workflow.lifecycle->'requires_approval'='false'::jsonb then
 raise exception using errcode='55000',message='JOURNAL_APPROVAL_REQUIRED';end if;
 select min((x->>'step_order')::integer) into v_first from jsonb_array_elements(v_snapshot->'steps') x;
 if v_first is null then raise exception using errcode='55000',message='WORKFLOW_CONFIGURATION_ERROR';end if;
 v_to:='pending_approval';
 perform sales.flow_assert_transition(v_workflow.lifecycle,'draft','submitted');
 v_number:=coalesce(v_number,sales.wave3_reserve_document_number(p_tenant_id,p_legal_entity_id,p_branch_id,v_kind,(v_doc->>'document_date')::date,auth.uid()));
 if v_first is not null then insert into workflow.approval_requests(tenant_id,legal_entity_id,branch_id,document_type,document_id,status,
 submitted_by,workflow_definition_id,workflow_revision,current_step,amount,currency_code,command_id,request_id,correlation_id)
 values(p_tenant_id,p_legal_entity_id,p_branch_id,v_kind,v_id,'submitted',auth.uid(),v_workflow.id,v_workflow.revision,v_first,
 (v_doc->>'grand_total')::numeric,v_doc->>'currency_code',p_command_id,v_request,v_request);end if;
 elsif v_action in ('recall','cancel') then
 if nullif(trim(p_payload->>'reason'),'') is null then raise exception using errcode='22023',message='REASON_REQUIRED';end if;
 if v_snapshot is null and v_doc->>'status'='draft' then
 select jsonb_build_object('lifecycle',lifecycle) into v_snapshot from workflow.workflow_definitions
 where tenant_id=p_tenant_id and document_type=v_kind and status='active'
 and (legal_entity_id is null or legal_entity_id=p_legal_entity_id) order by (legal_entity_id is not null) desc limit 1;
 end if;
 v_to:=case when v_action='recall' then 'draft' else 'cancelled' end;
 perform sales.flow_assert_transition(v_snapshot->'lifecycle',v_doc->>'status',v_to);
 update workflow.approval_requests set status='cancelled',decision_by=auth.uid(),decision_note=p_payload->>'reason',decided_at=clock_timestamp()
 where tenant_id=p_tenant_id and document_type=v_kind and document_id=v_id and status='submitted';
 if v_action='recall' then v_snapshot:=null;end if;
 else raise exception using errcode='22023',message='DOCUMENT_ACTION_INVALID';end if;
 execute format('update finance.%I set status=$1,workflow_snapshot=$2,document_number=$3,submitted_by=case when $4=''submit'' then $5 else submitted_by end,updated_by=$5,request_id=$6,command_id=$7,correlation_id=$6,client_timestamp=$8 where tenant_id=$9 and id=$10','manual_journals')
 using v_to,v_snapshot,v_number,v_action,auth.uid(),v_request,p_command_id,p_client_timestamp,p_tenant_id,v_id;
 return core.wave3_finish_command(p_tenant_id,v_command,p_command_id,v_kind,v_id,p_idempotency_key,v_hash,v_before,
 finance.manual_document(v_kind,p_tenant_id,v_id),p_legal_entity_id,p_branch_id,coalesce(p_payload->'source_context','{}'),
 case when v_doc->>'status'=v_to then null else
 jsonb_build_object('from_status',v_doc->>'status','to_status',v_to,'reason',coalesce(p_payload->>'reason',p_payload->>'note')) end,
 jsonb_build_array(jsonb_build_object('topic',v_command,'payload',jsonb_build_object('status',v_to))),'[]',v_request,v_request);
end $$;



create function api.post_manual_journal(p_tenant_id uuid,p_legal_entity_id uuid,p_branch_id uuid,p_command_id uuid,p_idempotency_key uuid,
 p_client_timestamp timestamptz,p_payload jsonb,p_expected_entity_version bigint default null) returns jsonb
language plpgsql security definer set search_path='' as $$declare v_id uuid:=(p_payload->>'document_id')::uuid;d jsonb;h text;r jsonb;req uuid:=gen_random_uuid();j uuid;jlines jsonb;begin
 perform core.wave3_require_scope(p_tenant_id,'finance.journals.post',p_legal_entity_id,p_branch_id);
 perform core.require_permission(p_tenant_id,'finance.view',p_legal_entity_id,p_branch_id);
 if v_id is null or p_branch_id is null or p_legal_entity_id is null or p_client_timestamp is null then raise exception using errcode='22023',message='JOURNAL_INPUT_INVALID';end if;
 perform finance.manual_command_access(p_tenant_id,p_legal_entity_id,p_branch_id,p_payload);
 h:=core.wave3_request_hash('finance.manual_journal.post',p_command_id,p_tenant_id,p_legal_entity_id,p_branch_id,p_payload,p_expected_entity_version);
 r:=core.wave3_replay(p_tenant_id,'finance.manual_journal.post',p_command_id,p_idempotency_key,h);if r is not null then return r;end if;
 d:=finance.manual_document('manual_journal',p_tenant_id,v_id,true);
 if d is null or d->>'legal_entity_id'<>p_legal_entity_id::text or d->>'branch_id'<>p_branch_id::text then raise exception using errcode='P0002',message='DOCUMENT_NOT_FOUND';end if;
 perform core.wave3_assert_expected_version((d->>'version')::bigint,p_expected_entity_version,d);
 if d->>'status'<>'approved' then raise exception using errcode='55000',message='JOURNAL_APPROVAL_REQUIRED';end if;
 if auth.uid() in ((d->>'prepared_by')::uuid,(d->>'submitted_by')::uuid) then raise exception using errcode='42501',message='SEGREGATION_OF_DUTIES_VIOLATION';end if;
 perform sales.flow_assert_transition(d#>'{workflow_snapshot,lifecycle}','approved','posted');
 perform finance.manual_revalidate('manual_journal',d);
 select jsonb_agg(finance.flow_jline((x->>'account_id')::uuid,(x->>'amount')::numeric,(x->>'base_amount')::numeric,(x->>'line_id')::uuid) order by n)
 into jlines from jsonb_array_elements(d->'lines') with ordinality z(x,n);
 j:=finance.flow_post_journal(d,jlines,'manual_journal',v_id,req,p_command_id);
 update finance.manual_journals set status='posted',journal_entry_id=j,posted_at=clock_timestamp(),posted_by=auth.uid(),updated_by=auth.uid(),
 request_id=req,command_id=p_command_id,correlation_id=req,client_timestamp=p_client_timestamp where tenant_id=p_tenant_id and id=v_id;
 return core.wave3_finish_command(p_tenant_id,'finance.manual_journal.post',p_command_id,'manual_journal',v_id,p_idempotency_key,h,d,
 finance.manual_document('manual_journal',p_tenant_id,v_id),p_legal_entity_id,p_branch_id,'{}',jsonb_build_object('from_status','approved','to_status','posted','reason',d->>'reason'),
 jsonb_build_array(jsonb_build_object('topic','finance.manual_journal.post','payload',jsonb_build_object('id',v_id,'journal_entry_id',j))),'[]',req,req);
end$$;

create function api.manual_journal_detail(p_tenant_id uuid,p_legal_entity_id uuid,p_branch_id uuid,p_id uuid) returns jsonb
language plpgsql stable security definer set search_path='' as $$declare d jsonb;begin
 perform core.wave3_require_scope(p_tenant_id,'finance.view',p_legal_entity_id,p_branch_id);
 if p_branch_id is null or p_legal_entity_id is null then raise exception using errcode='42501',message='OPERATIONAL_SCOPE_REQUIRED';end if;
 d:=finance.manual_document('manual_journal',p_tenant_id,p_id);
 if d is null or d->>'legal_entity_id'<>p_legal_entity_id::text or d->>'branch_id'<>p_branch_id::text then raise exception using errcode='P0002',message='DOCUMENT_NOT_FOUND';end if;
 if jsonb_array_length(d->'attachments')>0 then perform core.require_permission(p_tenant_id,'core.files.view',p_legal_entity_id,p_branch_id);end if;
 return d||jsonb_build_object('reversed_by_id',(select id from finance.manual_journals where tenant_id=p_tenant_id and reversal_of_id=p_id and status='posted'),
 'ledger_lines',coalesce((select jsonb_agg(sales.flow_exact_json(to_jsonb(l)) order by line_number) from finance.journal_lines l
 where l.tenant_id=p_tenant_id and l.journal_entry_id=(d->>'journal_entry_id')::uuid),'[]'::jsonb));
end$$;

create function api.manual_journal_options(p_tenant_id uuid,p_legal_entity_id uuid,p_branch_id uuid,p_resource text,p_after uuid default null,p_search text default '')
returns jsonb language plpgsql stable security definer set search_path='' as $$declare rows jsonb;next_id uuid;begin
 perform core.wave3_require_scope(p_tenant_id,'finance.view',p_legal_entity_id,p_branch_id);
 if p_branch_id is null or p_legal_entity_id is null or coalesce(length(p_search),0)>100 then raise exception using errcode='22023',message='JOURNAL_OPTIONS_INVALID';end if;
 if p_resource='reports' then
 select coalesce(jsonb_agg(to_jsonb(q) order by id),'[]') into rows from(select id,document_number,document_date,description,status,version,currency_code,grand_total::text,reversal_of_id
 from finance.manual_journals where tenant_id=p_tenant_id and legal_entity_id=p_legal_entity_id and branch_id=p_branch_id and(p_after is null or id>p_after)
 and(description ilike '%'||p_search||'%' or document_number ilike '%'||p_search||'%') order by id limit 51)q;
 elsif p_resource='accounts' then
 select coalesce(jsonb_agg(to_jsonb(q) order by id),'[]') into rows from(select id,code,name,account_type,currency_code from finance.accounts
 where tenant_id=p_tenant_id and legal_entity_id=p_legal_entity_id and status='active' and is_posting and(p_after is null or id>p_after)
 and(name ilike '%'||p_search||'%' or code ilike '%'||p_search||'%') order by id limit 51)q;
 elsif p_resource='rates' then
 select coalesce(jsonb_agg(to_jsonb(q) order by id),'[]') into rows from(select r.id,r.source_currency_code,r.target_currency_code,r.effective_date,r.rate::text
 from finance.exchange_rates r join core.legal_entities e on e.tenant_id=r.tenant_id and e.id=r.legal_entity_id
 where r.tenant_id=p_tenant_id and r.legal_entity_id=p_legal_entity_id and r.target_currency_code=e.currency_code and r.status='active' and(p_after is null or r.id>p_after) order by r.id limit 51)q;
 elsif p_resource='attachments' then
 perform core.require_permission(p_tenant_id,'core.files.view',p_legal_entity_id,p_branch_id);
 select coalesce(jsonb_agg(to_jsonb(q) order by id),'[]') into rows from(select id,file_name,checksum_sha256 from core.attachments where tenant_id=p_tenant_id
 and upload_status='ready' and checksum_sha256 is not null and((aggregate_type='legal_entity' and aggregate_id=p_legal_entity_id)or(aggregate_type='branch' and aggregate_id=p_branch_id))
 and(p_after is null or id>p_after) and file_name ilike '%'||p_search||'%' order by id limit 51)q;
 else raise exception using errcode='22023',message='JOURNAL_OPTIONS_INVALID';end if;
 if jsonb_array_length(rows)>50 then next_id:=(rows->49->>'id')::uuid;rows:=rows-50;end if;
 return jsonb_build_object('items',rows,'next_cursor',next_id,'base_currency_code',(select currency_code from core.legal_entities where tenant_id=p_tenant_id and id=p_legal_entity_id));
end$$;
revoke all on function finance.manual_document(text,uuid,uuid,boolean),finance.manual_normalize(uuid,uuid,uuid,jsonb),finance.manual_revalidate(text,jsonb) from public,anon,authenticated;
do $$declare f text;begin
 foreach f in array array['upsert_manual_journal','transition_manual_journal','post_manual_journal'] loop
 execute format('revoke all on function api.%I(uuid,uuid,uuid,uuid,uuid,timestamptz,jsonb,bigint) from public,anon,authenticated',f);
 execute format('grant execute on function api.%I(uuid,uuid,uuid,uuid,uuid,timestamptz,jsonb,bigint) to authenticated',f);end loop;
end$$;
revoke all on function api.manual_journal_detail(uuid,uuid,uuid,uuid),api.manual_journal_options(uuid,uuid,uuid,text,uuid,text) from public,anon,authenticated;
grant execute on function api.manual_journal_detail(uuid,uuid,uuid,uuid),api.manual_journal_options(uuid,uuid,uuid,text,uuid,text) to authenticated;
notify pgrst,'reload schema';
