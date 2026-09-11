-- Additive Wave 3 opening-stock prerequisite. Existing applied SQL is immutable.
create table inventory.stock_openings (
 id uuid primary key default gen_random_uuid(), tenant_id uuid not null references core.tenants(id),
 legal_entity_id uuid not null, branch_id uuid not null, warehouse_id uuid not null,
 document_type text not null default 'stock_opening' check(document_type='stock_opening'),
 document_number text, document_date date not null, reason text not null check(length(trim(reason)) between 3 and 1000),
 currency_code text not null references core.currencies(code), offset_account_id uuid not null,
 lines jsonb not null check(jsonb_typeof(lines)='array' and jsonb_array_length(lines) between 1 and 100),
 grand_total numeric(20,6) not null check(grand_total>0),
 status text not null default 'draft' check(status in ('draft','pending_approval','approved','rejected','cancelled','posted')),
 version bigint not null default 1, workflow_snapshot jsonb, submitted_by uuid references auth.users(id),
 posted_by uuid references auth.users(id), posted_at timestamptz, stock_movement_id uuid, journal_entry_id uuid,
 request_id uuid not null, command_id uuid not null, correlation_id uuid not null, client_timestamp timestamptz not null,
 prepared_by uuid not null references auth.users(id),
 created_by uuid not null references auth.users(id), updated_by uuid not null references auth.users(id),
 created_at timestamptz not null default now(), updated_at timestamptz not null default now(),
 unique(tenant_id,id), unique(tenant_id,legal_entity_id,branch_id,document_number),
 foreign key(tenant_id,legal_entity_id) references core.legal_entities(tenant_id,id),
 foreign key(tenant_id,branch_id) references core.branches(tenant_id,id),
 foreign key(tenant_id,warehouse_id) references core.warehouses(tenant_id,id),
 foreign key(tenant_id,legal_entity_id,offset_account_id) references finance.accounts(tenant_id,legal_entity_id,id),
 foreign key(tenant_id,stock_movement_id) references inventory.stock_movements(tenant_id,id),
 foreign key(tenant_id,journal_entry_id) references finance.journal_entries(tenant_id,id),
 check((status='posted')=(posted_at is not null)),
 check(status<>'posted' or (stock_movement_id is not null and journal_entry_id is not null and posted_by is not null))
);
alter table inventory.stock_openings enable row level security;
alter table inventory.stock_openings force row level security;
create policy opening_permitted_read on inventory.stock_openings for select to authenticated using (
 core.is_tenant_member(tenant_id) and core.has_permission(tenant_id,'inventory.cost.view',legal_entity_id,branch_id)
 and (core.has_permission(tenant_id,'inventory.adjustments.post',legal_entity_id,branch_id)
 or core.has_permission(tenant_id,'workflow.approvals.decide',legal_entity_id,branch_id))
);
create trigger opening_immutable_posted before update or delete on inventory.stock_openings
 for each row execute function sales.flow_protect_document();
create trigger opening_touch before update on inventory.stock_openings
 for each row execute function core.touch_mutable_record();
create index stock_openings_scope_idx on inventory.stock_openings(tenant_id,legal_entity_id,branch_id,status,id);
-- Lead each FK index with its referencing columns; retain the scoped register index.
do $$ declare f record; begin
 for f in select c.conname, (select string_agg(quote_ident(a.attname),',' order by k.n)
 from unnest(c.conkey) with ordinality k(num,n) join pg_attribute a on a.attrelid=c.conrelid and a.attnum=k.num) cols
 from pg_constraint c where c.conrelid='inventory.stock_openings'::regclass and c.contype='f' loop
 execute format('create index %I on inventory.stock_openings(%s)',f.conname||'_idx',f.cols);
 end loop;
end $$;
revoke all on inventory.stock_openings from public,anon,authenticated;
grant select on inventory.stock_openings to authenticated;
create view api.stock_openings with(security_invoker=true) as
 select id,tenant_id,legal_entity_id,branch_id,warehouse_id,document_number,document_date,status,version,
 sales.flow_exact_json(to_jsonb(o)) as detail from inventory.stock_openings o;
revoke all on api.stock_openings from public,anon,authenticated;
grant select on api.stock_openings to authenticated;

create function inventory.opening_document(p_kind text,p_tenant uuid,p_id uuid,p_lock boolean default false)
returns jsonb language plpgsql security definer set search_path='' as $$
declare d inventory.stock_openings%rowtype; begin
 if p_kind is distinct from 'stock_opening' then raise exception using errcode='22023',message='DOCUMENT_TYPE_INVALID';end if;
 if p_lock then select * into d from inventory.stock_openings where tenant_id=p_tenant and id=p_id for update;
 else select * into d from inventory.stock_openings where tenant_id=p_tenant and id=p_id;end if;
 if not found then return null;end if;
 return sales.flow_exact_json(to_jsonb(d));
end $$;

create function inventory.opening_normalize(p_tenant uuid,p_entity uuid,p_branch uuid,p_payload jsonb)
returns jsonb language plpgsql security definer set search_path='' as $$
declare le core.legal_entities%rowtype; prod inventory.products%rowtype; item jsonb; arr jsonb:='[]';
 q numeric; val numeric; total numeric:=0; prec integer; warehouse uuid:=(p_payload->>'warehouse_id')::uuid;
 offset_id uuid:=(p_payload->>'offset_account_id')::uuid; dt date:=(p_payload->>'document_date')::date;
 lot text; serials jsonb; code text; line_id uuid; seen uuid[]:='{}';
begin
 if jsonb_typeof(p_payload) is distinct from 'object' or dt is null
 or coalesce(length(trim(p_payload->>'reason')),0) not between 3 and 1000
 or jsonb_typeof(p_payload->'lines') is distinct from 'array' then
 raise exception using errcode='22023',message='OPENING_PAYLOAD_INVALID';end if;
 if jsonb_array_length(p_payload->'lines') not between 1 and 100 then
 raise exception using errcode='22023',message='OPENING_LINE_LIMIT';end if;
 select * into le from core.legal_entities where tenant_id=p_tenant and id=p_entity and status='active';
 if not found or not exists(select 1 from core.currencies c where c.code=le.currency_code and c.active) then
 raise exception using errcode='22023',message='CURRENCY_INVALID';end if;
 if not exists(select 1 from core.warehouses where tenant_id=p_tenant and legal_entity_id=p_entity
 and branch_id=p_branch and id=warehouse and status='active') then
 raise exception using errcode='22023',message='WAREHOUSE_INACTIVE';end if;
 perform finance.flow_account(p_tenant,p_entity,offset_id,'equity',le.currency_code);
 for item in select value from jsonb_array_elements(p_payload->'lines') loop
 line_id:=(item->>'line_id')::uuid;
 if line_id is null or line_id=any(seen) then raise exception using errcode='22023',message='OPENING_LINE_ID_INVALID';end if;
 seen:=array_append(seen,line_id);
 select * into prod from inventory.products where tenant_id=p_tenant and legal_entity_id=p_entity
 and id=(item->>'product_id')::uuid and status='active' and kind='stocked';
 if not found then raise exception using errcode='22023',message='OPENING_STOCKED_PRODUCT_REQUIRED';end if;
 select precision into prec from inventory.units where tenant_id=p_tenant and id=prod.base_unit_id and status='active';
 if not found then raise exception using errcode='22023',message='UNIT_INVALID';end if;
 perform finance.flow_account(p_tenant,p_entity,prod.inventory_account_id,'asset',le.currency_code);
 q:=sales.wave3_decimal_string(item->'base_quantity','base_quantity',6,true,0.000001,99999999999999.999999);
 val:=sales.wave3_decimal_string(item->'base_value','base_value',6,true,0.000001,99999999999999.999999);
 if q<>round(q,prec) or val<>round(val,le.rounding_scale) then
 raise exception using errcode='22023',message='OPENING_PRECISION_INVALID';end if;
 lot:=nullif(trim(item->>'lot_code'),'');serials:=coalesce(item->'serial_codes','[]');
 if jsonb_typeof(serials) is distinct from 'array' or jsonb_array_length(serials)>500 then
 raise exception using errcode='22023',message='TRACKING_INPUT_INVALID';end if;
 if prod.tracking_mode='lot' then
 if lot is null or length(lot)>100 or jsonb_array_length(serials)>0 then
 raise exception using errcode='22023',message='TRACKING_INPUT_INVALID';end if;
 if (item->>'expiry_date')::date<greatest(dt,(clock_timestamp() at time zone 'UTC')::date)
 or (item->>'manufacture_date')::date>dt
 or (item->>'expiry_date')::date<(item->>'manufacture_date')::date then
 raise exception using errcode='22023',message='LOT_NOT_SALEABLE';end if;
 elsif prod.tracking_mode='serial' then
 if lot is not null or q<>trunc(q) or jsonb_array_length(serials)<>q
 or exists(select 1 from jsonb_array_elements(serials) s where jsonb_typeof(s)<>'string')
 or (select count(distinct trim(s)) from jsonb_array_elements_text(serials) s)<>q then
 raise exception using errcode='22023',message='SERIAL_CONFLICT';end if;
 for code in select trim(s) from jsonb_array_elements_text(serials) s loop
 if length(code) not between 1 and 100 then raise exception using errcode='22023',message='SERIAL_CONFLICT';end if;
 end loop;
 select jsonb_agg(trim(s) order by trim(s)) into serials from jsonb_array_elements_text(serials) s;
 elsif lot is not null or jsonb_array_length(serials)>0 then
 raise exception using errcode='22023',message='TRACKING_INPUT_INVALID';end if;
 if prod.tracking_mode<>'lot' and (item->>'manufacture_date' is not null or item->>'expiry_date' is not null) then
 raise exception using errcode='22023',message='TRACKING_INPUT_INVALID';end if;
 if exists(select 1 from jsonb_array_elements(arr) a where a->>'product_id'=prod.id::text
 and (prod.tracking_mode<>'lot' or a->>'lot_code'=lot)) then
 raise exception using errcode='22023',message='OPENING_DUPLICATE_PRODUCT_LOT';end if;
 arr:=arr||jsonb_build_array(jsonb_strip_nulls(jsonb_build_object('line_id',line_id,'product_id',prod.id,
 'product_name',prod.name,'sku',prod.sku,'base_unit_id',prod.base_unit_id,'tracking_mode',prod.tracking_mode,
 'inventory_account_id',prod.inventory_account_id,'base_quantity',q::text,'base_value',val::text,
 'lot_code',lot,'manufacture_date',(item->>'manufacture_date')::date,'expiry_date',(item->>'expiry_date')::date,'serial_codes',serials)));
 total:=total+val;
 end loop;
 if total>99999999999999.999999 then raise exception using errcode='22023',message='OPENING_TOTAL_EXCEEDED';end if;
 return jsonb_build_object('warehouse_id',warehouse,'document_date',dt,'reason',trim(p_payload->>'reason'),
 'offset_account_id',offset_id,'currency_code',le.currency_code,'grand_total',total::text,'lines',arr);
end $$;

create function inventory.opening_revalidate(p_kind text,p_doc jsonb) returns jsonb
language plpgsql security definer set search_path='' as $$
declare normalized jsonb;begin
 normalized:=inventory.opening_normalize((p_doc->>'tenant_id')::uuid,(p_doc->>'legal_entity_id')::uuid,(p_doc->>'branch_id')::uuid,p_doc);
 if normalized->'lines'<>p_doc->'lines' or normalized->>'currency_code'<>p_doc->>'currency_code'
 or (normalized->>'grand_total')::numeric<>(p_doc->>'grand_total')::numeric then
 raise exception using errcode='55000',message='OPENING_MASTER_CHANGED';end if;
 return normalized;
end $$;

create function api.upsert_stock_opening(p_tenant_id uuid,p_legal_entity_id uuid,p_branch_id uuid,p_command_id uuid,
 p_idempotency_key uuid,p_client_timestamp timestamptz,p_payload jsonb,p_expected_entity_version bigint default null)
returns jsonb language plpgsql security definer set search_path='' as $$
declare v_id uuid:=coalesce((p_payload->>'id')::uuid,gen_random_uuid());v_request uuid:=gen_random_uuid();
 v_command text:='inventory.stock_opening.upsert';v_hash text;v_replay jsonb;v_before jsonb;v_doc jsonb;
begin
 perform core.wave3_require_scope(p_tenant_id,'inventory.adjustments.post',p_legal_entity_id,p_branch_id);
 perform core.require_permission(p_tenant_id,'inventory.cost.view',p_legal_entity_id,p_branch_id);
 if p_branch_id is null or p_legal_entity_id is null or p_client_timestamp is null then
 raise exception using errcode='22023',message='OPENING_PAYLOAD_INVALID';end if;
 v_hash:=core.wave3_request_hash(v_command,p_command_id,p_tenant_id,p_legal_entity_id,p_branch_id,p_payload,p_expected_entity_version);
 v_replay:=core.wave3_replay(p_tenant_id,v_command,p_command_id,p_idempotency_key,v_hash);if v_replay is not null then return v_replay;end if;
 perform pg_advisory_xact_lock(hashtextextended(p_tenant_id::text||':opening:'||v_id::text,0));
 v_before:=inventory.opening_document('stock_opening',p_tenant_id,v_id,true);
 if v_before is not null then
 if (v_before->>'legal_entity_id')::uuid<>p_legal_entity_id or (v_before->>'branch_id')::uuid<>p_branch_id then
 raise exception using errcode='42501',message='DOCUMENT_SCOPE_INVALID';end if;
 perform core.wave3_assert_expected_version((v_before->>'version')::bigint,p_expected_entity_version,v_before);
 if v_before->>'status'<>'draft' then raise exception using errcode='55000',message='DOCUMENT_NOT_EDITABLE';end if;
 elsif p_expected_entity_version is not null then raise exception using errcode='40001',message='VERSION_CONFLICT';end if;
 v_doc:=inventory.opening_normalize(p_tenant_id,p_legal_entity_id,p_branch_id,p_payload);
 insert into inventory.stock_openings(id,tenant_id,legal_entity_id,branch_id,warehouse_id,document_date,reason,currency_code,
 offset_account_id,lines,grand_total,request_id,command_id,correlation_id,client_timestamp,prepared_by,created_by,updated_by)
 values(v_id,p_tenant_id,p_legal_entity_id,p_branch_id,(v_doc->>'warehouse_id')::uuid,(v_doc->>'document_date')::date,
 v_doc->>'reason',v_doc->>'currency_code',(v_doc->>'offset_account_id')::uuid,v_doc->'lines',(v_doc->>'grand_total')::numeric,
 v_request,p_command_id,v_request,p_client_timestamp,auth.uid(),auth.uid(),auth.uid())
 on conflict(id) do update set warehouse_id=excluded.warehouse_id,document_date=excluded.document_date,reason=excluded.reason,
 currency_code=excluded.currency_code,offset_account_id=excluded.offset_account_id,lines=excluded.lines,grand_total=excluded.grand_total,
 request_id=excluded.request_id,command_id=excluded.command_id,correlation_id=excluded.correlation_id,client_timestamp=excluded.client_timestamp,prepared_by=auth.uid(),updated_by=auth.uid()
 where inventory.stock_openings.tenant_id=excluded.tenant_id
 and inventory.stock_openings.legal_entity_id=excluded.legal_entity_id and inventory.stock_openings.branch_id=excluded.branch_id;
 if not found then raise exception using errcode='42501',message='DOCUMENT_SCOPE_INVALID';end if;
 return core.wave3_finish_command(p_tenant_id,v_command,p_command_id,'stock_opening',v_id,p_idempotency_key,v_hash,v_before,
 inventory.opening_document('stock_opening',p_tenant_id,v_id),p_legal_entity_id,p_branch_id,'{}',null,'[]','[]',v_request,v_request);
end $$;

-- Independent approval uses the same governed workflow snapshots as commerce.
create function api.transition_stock_opening(p_tenant_id uuid,p_legal_entity_id uuid,p_branch_id uuid,p_command_id uuid,
 p_idempotency_key uuid,p_client_timestamp timestamptz,p_payload jsonb,p_expected_entity_version bigint default null)
returns jsonb language plpgsql security definer set search_path='' as $$
declare v_kind text:='stock_opening';v_id uuid:=(p_payload->>'document_id')::uuid;
 v_action text:=p_payload->>'action';v_decision text:=p_payload->>'decision';v_command text;
 v_doc jsonb;v_before jsonb;v_hash text;v_replay jsonb;v_to text;v_snapshot jsonb;
 v_workflow workflow.workflow_definitions%rowtype;v_request uuid:=gen_random_uuid();v_first integer;
 v_ar workflow.approval_requests%rowtype;v_step jsonb;v_number text;
begin
 v_command:='inventory.'||v_kind||case when v_decision is null then '.transition' else '.decide' end;
 perform core.wave3_require_scope(p_tenant_id,case when v_decision is null then 'inventory.adjustments.post' else 'workflow.approvals.decide' end,p_legal_entity_id,p_branch_id);
 perform core.require_permission(p_tenant_id,'inventory.cost.view',p_legal_entity_id,p_branch_id);
 if p_legal_entity_id is null or p_branch_id is null or p_client_timestamp is null
 or (p_payload ? 'document_type' and p_payload->>'document_type' is distinct from 'stock_opening')
 or (v_decision is not null and v_action is not null) then raise exception using errcode='22023',message='DOCUMENT_PAYLOAD_INVALID';end if;
 v_hash:=core.wave3_request_hash(v_command,p_command_id,p_tenant_id,p_legal_entity_id,p_branch_id,p_payload,p_expected_entity_version);
 v_replay:=core.wave3_replay(p_tenant_id,v_command,p_command_id,p_idempotency_key,v_hash);if v_replay is not null then return v_replay;end if;
 v_doc:=inventory.opening_document(v_kind,p_tenant_id,v_id,true);v_before:=v_doc;
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
 perform inventory.opening_revalidate(v_kind,v_doc);
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
 raise exception using errcode='55000',message='OPENING_APPROVAL_REQUIRED';end if;
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
 execute format('update inventory.%I set status=$1,workflow_snapshot=$2,document_number=$3,submitted_by=case when $4=''submit'' then $5 else submitted_by end,updated_by=$5,request_id=$6,command_id=$7,correlation_id=$6,client_timestamp=$8 where tenant_id=$9 and id=$10','stock_openings')
 using v_to,v_snapshot,v_number,v_action,auth.uid(),v_request,p_command_id,p_client_timestamp,p_tenant_id,v_id;
 return core.wave3_finish_command(p_tenant_id,v_command,p_command_id,v_kind,v_id,p_idempotency_key,v_hash,v_before,
 inventory.opening_document(v_kind,p_tenant_id,v_id),p_legal_entity_id,p_branch_id,coalesce(p_payload->'source_context','{}'),
 case when v_doc->>'status'=v_to then null else
 jsonb_build_object('from_status',v_doc->>'status','to_status',v_to,'reason',coalesce(p_payload->>'reason',p_payload->>'note')) end,
 jsonb_build_array(jsonb_build_object('topic',v_command,'payload',jsonb_build_object('status',v_to))),'[]',v_request,v_request);
end $$;

create function api.post_stock_opening(p_tenant_id uuid,p_legal_entity_id uuid,p_branch_id uuid,p_command_id uuid,
 p_idempotency_key uuid,p_client_timestamp timestamptz,p_payload jsonb,p_expected_entity_version bigint default null)
returns jsonb language plpgsql security definer set search_path='' as $$
declare v_id uuid:=(p_payload->>'document_id')::uuid;v_request uuid:=gen_random_uuid();v_command text:='inventory.stock_opening.post';
 v_doc jsonb;v_hash text;v_replay jsonb;v_line jsonb;v_product uuid;v_warehouse uuid;v_balance inventory.stock_balances%rowtype;
 v_movement uuid:=gen_random_uuid();v_journal uuid;v_jlines jsonb:='[]';v_lot uuid;v_serials uuid[];v_serial uuid;v_code text;
 v_q numeric;v_value numeric;v_dt date;v_fiscal uuid;v_currency text;
begin
 perform core.wave3_require_scope(p_tenant_id,'inventory.adjustments.post',p_legal_entity_id,p_branch_id);
 perform core.require_permission(p_tenant_id,'inventory.cost.view',p_legal_entity_id,p_branch_id);
 if p_branch_id is null or p_legal_entity_id is null or p_client_timestamp is null then
 raise exception using errcode='22023',message='OPENING_PAYLOAD_INVALID';end if;
 v_hash:=core.wave3_request_hash(v_command,p_command_id,p_tenant_id,p_legal_entity_id,p_branch_id,p_payload,p_expected_entity_version);
 v_replay:=core.wave3_replay(p_tenant_id,v_command,p_command_id,p_idempotency_key,v_hash);if v_replay is not null then return v_replay;end if;
 v_doc:=inventory.opening_document('stock_opening',p_tenant_id,v_id,true);
 if v_doc is null or (v_doc->>'legal_entity_id')::uuid<>p_legal_entity_id or (v_doc->>'branch_id')::uuid<>p_branch_id then
 raise exception using errcode='P0002',message='DOCUMENT_NOT_FOUND';end if;
 perform core.wave3_assert_expected_version((v_doc->>'version')::bigint,p_expected_entity_version,v_doc);
 if v_doc->>'status'<>'approved' then raise exception using errcode='55000',message='OPENING_APPROVAL_REQUIRED';end if;
 perform inventory.opening_revalidate('stock_opening',v_doc);
 perform sales.flow_assert_transition(v_doc#>'{workflow_snapshot,lifecycle}','approved','posted');
 v_dt:=(v_doc->>'document_date')::date;v_currency:=v_doc->>'currency_code';v_warehouse:=(v_doc->>'warehouse_id')::uuid;
 v_fiscal:=finance.wave3_lock_open_period(p_tenant_id,p_legal_entity_id,v_dt);
 for v_product in select distinct (x->>'product_id')::uuid from jsonb_array_elements(v_doc->'lines') x order by 1 loop
 perform pg_advisory_xact_lock(hashtextextended(p_tenant_id::text||':'||v_warehouse::text||':'||v_product::text,0));
 if exists(select 1 from inventory.stock_movement_lines where tenant_id=p_tenant_id and warehouse_id=v_warehouse and product_id=v_product)
 or exists(select 1 from inventory.stock_balances b left join inventory.stock_valuations v on v.stock_balance_id=b.id and v.tenant_id=b.tenant_id
 where b.tenant_id=p_tenant_id and b.warehouse_id=v_warehouse and b.product_id=v_product
 and (b.on_hand_quantity<>0 or b.allocated_quantity<>0 or coalesce(v.carrying_value,0)<>0))
 or exists(select 1 from inventory.stock_reservations where tenant_id=p_tenant_id and warehouse_id=v_warehouse and product_id=v_product and status='active') then
 raise exception using errcode='55000',message='OPENING_ALREADY_ESTABLISHED';end if;
 end loop;
 insert into inventory.stock_movements(id,tenant_id,legal_entity_id,branch_id,source_type,source_id,warehouse_id,posting_date,
 movement_kind,request_id,command_id,correlation_id,created_by)
 values(v_movement,p_tenant_id,p_legal_entity_id,p_branch_id,'stock_opening',v_id,v_warehouse,v_dt,'opening',v_request,p_command_id,v_request,auth.uid());
 for v_line in select value from jsonb_array_elements(v_doc->'lines') loop
 v_product:=(v_line->>'product_id')::uuid;v_q:=(v_line->>'base_quantity')::numeric;v_value:=(v_line->>'base_value')::numeric;
 v_lot:=null;v_serials:='{}';
 if v_line->>'tracking_mode'='lot' then
 insert into inventory.lots(tenant_id,legal_entity_id,product_id,code,manufacture_date,expiry_date,created_by,updated_by)
 values(p_tenant_id,p_legal_entity_id,v_product,v_line->>'lot_code',(v_line->>'manufacture_date')::date,(v_line->>'expiry_date')::date,auth.uid(),auth.uid())
 on conflict(tenant_id,product_id,code) do nothing;
 select id into v_lot from inventory.lots where tenant_id=p_tenant_id and product_id=v_product and code=v_line->>'lot_code'
 and legal_entity_id=p_legal_entity_id and status='saleable' and manufacture_date is not distinct from (v_line->>'manufacture_date')::date
 and expiry_date is not distinct from (v_line->>'expiry_date')::date for update;
 if not found then raise exception using errcode='22023',message='LOT_METADATA_CONFLICT';end if;
 insert into inventory.lot_balances(tenant_id,legal_entity_id,branch_id,warehouse_id,product_id,lot_id,on_hand_quantity,created_by,updated_by)
 values(p_tenant_id,p_legal_entity_id,p_branch_id,v_warehouse,v_product,v_lot,v_q,auth.uid(),auth.uid());
 elsif v_line->>'tracking_mode'='serial' then
 for v_code in select s from jsonb_array_elements_text(v_line->'serial_codes') s loop
 insert into inventory.serials(tenant_id,legal_entity_id,branch_id,warehouse_id,product_id,code,created_by,updated_by)
 values(p_tenant_id,p_legal_entity_id,p_branch_id,v_warehouse,v_product,v_code,auth.uid(),auth.uid()) returning id into v_serial;
 v_serials:=array_append(v_serials,v_serial);
 end loop;
 end if;
 insert into inventory.stock_balances(tenant_id,legal_entity_id,branch_id,warehouse_id,product_id,on_hand_quantity,created_by,updated_by)
 values(p_tenant_id,p_legal_entity_id,p_branch_id,v_warehouse,v_product,v_q,auth.uid(),auth.uid())
 on conflict(tenant_id,legal_entity_id,branch_id,warehouse_id,product_id)
 do update set on_hand_quantity=inventory.stock_balances.on_hand_quantity+excluded.on_hand_quantity,updated_by=auth.uid()
 returning * into v_balance;
 insert into inventory.stock_valuations(tenant_id,legal_entity_id,branch_id,stock_balance_id,carrying_value,created_by,updated_by)
 values(p_tenant_id,p_legal_entity_id,p_branch_id,v_balance.id,v_value,auth.uid(),auth.uid())
 on conflict(tenant_id,stock_balance_id) do update set carrying_value=inventory.stock_valuations.carrying_value+excluded.carrying_value,updated_by=auth.uid();
 insert into inventory.stock_movement_lines(tenant_id,legal_entity_id,branch_id,stock_movement_id,warehouse_id,product_id,
 source_line_id,base_quantity,base_value,lot_id,serial_ids,posting_date,created_by)
 values(p_tenant_id,p_legal_entity_id,p_branch_id,v_movement,v_warehouse,v_product,(v_line->>'line_id')::uuid,v_q,v_value,v_lot,v_serials,v_dt,auth.uid());
 v_jlines:=v_jlines||jsonb_build_array(finance.flow_jline((v_line->>'inventory_account_id')::uuid,v_value,v_value,(v_line->>'line_id')::uuid));
 end loop;
 v_value:=(v_doc->>'grand_total')::numeric;
 v_jlines:=v_jlines||jsonb_build_array(finance.flow_jline((v_doc->>'offset_account_id')::uuid,-v_value,-v_value));
 v_journal:=finance.flow_post_journal(v_doc||jsonb_build_object('base_currency_code',v_currency,'exchange_rate','1'),v_jlines,'stock_opening',v_id,v_request,p_command_id);
 update inventory.stock_openings set status='posted',posted_by=auth.uid(),posted_at=clock_timestamp(),stock_movement_id=v_movement,
 journal_entry_id=v_journal,updated_by=auth.uid(),request_id=v_request,command_id=p_command_id,correlation_id=v_request,client_timestamp=p_client_timestamp
 where tenant_id=p_tenant_id and id=v_id;
 return core.wave3_finish_command(p_tenant_id,v_command,p_command_id,'stock_opening',v_id,p_idempotency_key,v_hash,v_doc,
 inventory.opening_document('stock_opening',p_tenant_id,v_id),p_legal_entity_id,p_branch_id,'{}',
 jsonb_build_object('from_status','approved','to_status','posted','reason',v_doc->>'reason'),'[]','[]',v_request,v_request);
end $$;

-- Helpers are private. Only the three permission-checked envelopes are callable.
revoke all on function inventory.opening_document(text,uuid,uuid,boolean),
 inventory.opening_normalize(uuid,uuid,uuid,jsonb),inventory.opening_revalidate(text,jsonb)
 from public,anon,authenticated;
revoke all on function api.upsert_stock_opening(uuid,uuid,uuid,uuid,uuid,timestamptz,jsonb,bigint),
 api.transition_stock_opening(uuid,uuid,uuid,uuid,uuid,timestamptz,jsonb,bigint),
 api.post_stock_opening(uuid,uuid,uuid,uuid,uuid,timestamptz,jsonb,bigint) from public,anon,authenticated;
grant execute on function api.upsert_stock_opening(uuid,uuid,uuid,uuid,uuid,timestamptz,jsonb,bigint),
 api.transition_stock_opening(uuid,uuid,uuid,uuid,uuid,timestamptz,jsonb,bigint),
 api.post_stock_opening(uuid,uuid,uuid,uuid,uuid,timestamptz,jsonb,bigint) to authenticated;
