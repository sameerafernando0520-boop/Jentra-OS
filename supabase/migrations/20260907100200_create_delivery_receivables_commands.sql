-- AC-305..AC-308 command implementation. Each command is atomic and idempotent.
create function sales.flow_upsert(p_kind text,p_tenant_id uuid,p_legal_entity_id uuid,p_branch_id uuid,
 p_command_id uuid,p_idempotency_key uuid,p_client_timestamp timestamptz,p_payload jsonb,p_expected_entity_version bigint)
returns jsonb language plpgsql security definer set search_path='' as $$
declare v_table text:=sales.flow_table(p_kind);v_id uuid:=coalesce((p_payload->>'id')::uuid,gen_random_uuid());
 v_command text:='sales.'||p_kind||'.upsert';v_hash text;v_replay jsonb;v_before jsonb;v_doc jsonb;v_price jsonb;
 v_rate jsonb;v_scale integer;v_line jsonb;v_request uuid:=gen_random_uuid();v_cols text;v_values text;
 v_allowed text[]:=array['id','customer_id','document_date','due_date','currency_code','sales_order_id','warehouse_id',
 'cash_bank_account_id','external_reference','terms','notes','reason','tender_metadata','source_context'];
begin
 perform core.wave3_require_scope(p_tenant_id,sales.flow_permission(p_kind,'manage'),p_legal_entity_id,p_branch_id);
 if v_table is null or p_branch_id is null or p_client_timestamp is null or jsonb_typeof(p_payload) is distinct from 'object'
 or p_legal_entity_id is null then raise exception using errcode='22023',message='DOCUMENT_PAYLOAD_INVALID';end if;
 v_hash:=core.wave3_request_hash(v_command,p_command_id,p_tenant_id,p_legal_entity_id,p_branch_id,p_payload,p_expected_entity_version);
 v_replay:=core.wave3_replay(p_tenant_id,v_command,p_command_id,p_idempotency_key,v_hash);if v_replay is not null then return v_replay;end if;
 v_before:=sales.flow_document(p_kind,p_tenant_id,v_id,true);
 if v_before is not null then
 if (v_before->>'legal_entity_id')::uuid<>p_legal_entity_id or (v_before->>'branch_id')::uuid<>p_branch_id then
 raise exception using errcode='42501',message='DOCUMENT_SCOPE_INVALID';end if;
 perform core.wave3_assert_expected_version((v_before->>'version')::bigint,p_expected_entity_version,v_before);
 if v_before->>'status'<>'draft' then raise exception using errcode='55000',message='DOCUMENT_NOT_EDITABLE';end if;
 elsif p_expected_entity_version is not null then raise exception using errcode='40001',message='VERSION_CONFLICT';end if;
 if not exists(select 1 from crm.parties where tenant_id=p_tenant_id and id=(p_payload->>'customer_id')::uuid
 and status='active' and kind in ('customer','both')) then raise exception using errcode='22023',message='CUSTOMER_INACTIVE';end if;
 select rounding_scale into v_scale from core.legal_entities where tenant_id=p_tenant_id and id=p_legal_entity_id;
 v_rate:=finance.flow_rate(p_tenant_id,p_legal_entity_id,p_payload->>'currency_code',(p_payload->>'document_date')::date,(p_payload->>'exchange_rate_id')::uuid);
 select coalesce(jsonb_object_agg(key,value),'{}') into v_doc from jsonb_each(p_payload) where key=any(v_allowed);
 v_doc:=v_doc||v_rate||jsonb_build_object('id',v_id,'tenant_id',p_tenant_id,'legal_entity_id',p_legal_entity_id,
 'branch_id',p_branch_id,'document_type',p_kind,'status','draft','rounding_scale',v_scale,
 'due_date',coalesce(p_payload->>'due_date',p_payload->>'document_date'),'request_id',v_request,'command_id',p_command_id,
 'correlation_id',v_request,'client_timestamp',p_client_timestamp,'created_by',coalesce(v_before->>'created_by',auth.uid()::text),
 'updated_by',auth.uid(),'version',coalesce((v_before->>'version')::bigint,1),
 'created_at',coalesce(v_before->>'created_at',clock_timestamp()::text),'updated_at',clock_timestamp(),
 'source_context',coalesce(p_payload->'source_context','{}'::jsonb),'tender_metadata',coalesce(p_payload->'tender_metadata','{}'::jsonb),
 'document_number',v_before->>'document_number');
 if p_kind='delivery' and (v_doc->>'sales_order_id' is null or v_doc->>'warehouse_id' is null) then
 raise exception using errcode='22023',message='DELIVERY_SOURCE_REQUIRED';end if;
 if p_kind='customer_receipt' and not exists(select 1 from finance.cash_bank_accounts a where a.tenant_id=p_tenant_id
 and a.legal_entity_id=p_legal_entity_id and a.branch_id=p_branch_id and a.id=(v_doc->>'cash_bank_account_id')::uuid
 and a.status='active' and a.currency_code=v_doc->>'currency_code') then raise exception using errcode='22023',message='CASH_BANK_ACCOUNT_INVALID';end if;
 v_price:=sales.flow_price(p_kind,v_doc||jsonb_build_object('amount',p_payload->'amount'),p_payload->'lines');
 v_doc:=v_doc||(v_price-'lines');
 -- Explicitly populated record includes only whitelisted and server-owned fields.
 select string_agg(quote_ident(a.attname),',' order by a.attnum),string_agg('x.'||quote_ident(a.attname),',' order by a.attnum)
 into v_cols,v_values from pg_attribute a where a.attrelid=format('sales.%I',v_table)::regclass and a.attnum>0 and not a.attisdropped;
 if v_before is null then execute format('insert into sales.%I(%s) select %s from jsonb_populate_record(null::sales.%I,$1) x',v_table,v_cols,v_values,v_table) using v_doc;
 else
 execute format('update sales.%I d set (%s)=(select %s from jsonb_populate_record(null::sales.%I,$1) x) where d.tenant_id=$2 and d.id=$3',v_table,v_cols,v_values,v_table)
 using v_doc,p_tenant_id,v_id;
 execute format('delete from sales.%I where tenant_id=$1 and document_id=$2',sales.flow_lines_table(p_kind)) using p_tenant_id,v_id;
 end if;
 for v_line in select value from jsonb_array_elements(v_price->'lines') loop
 execute format('insert into sales.%I(id,tenant_id,legal_entity_id,branch_id,document_id,line_number,product_id,description,quantity,base_quantity,unit_id,sales_order_line_id,delivery_line_id,sales_invoice_line_id,taxable_amount,tax_amount,line_total,snapshot,created_by) values($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12,$13,$14,$15,$16,$17,$18,$19)',sales.flow_lines_table(p_kind))
 using (v_line->>'line_id')::uuid,p_tenant_id,p_legal_entity_id,p_branch_id,v_id,(v_line->>'line_number')::integer,
 (v_line->>'product_id')::uuid,v_line->>'description',(v_line->>'quantity')::numeric,(v_line->>'base_quantity')::numeric,
 (v_line->>'unit_id')::uuid,(v_line->>'sales_order_line_id')::uuid,(v_line->>'delivery_line_id')::uuid,
 (v_line->>'sales_invoice_line_id')::uuid,(v_line->>'taxable_amount')::numeric,(v_line->>'tax_amount')::numeric,
 (v_line->>'line_total')::numeric,v_line,auth.uid();end loop;
 v_doc:=sales.flow_document(p_kind,p_tenant_id,v_id);
 return core.wave3_finish_command(p_tenant_id,v_command,p_command_id,p_kind,v_id,p_idempotency_key,v_hash,v_before,v_doc,
 p_legal_entity_id,p_branch_id,coalesce(p_payload->'source_context','{}'),null,
 jsonb_build_array(jsonb_build_object('topic',v_command,'payload',jsonb_build_object('status','draft'))),'[]',v_request,v_request);
end $$;

create function sales.flow_revalidate(p_kind text,p_doc jsonb) returns jsonb
language plpgsql security definer set search_path='' as $$
declare v_price jsonb;v_inputs jsonb;v_rate jsonb;v_scale integer;begin
 if not exists(select 1 from crm.parties where tenant_id=(p_doc->>'tenant_id')::uuid and id=(p_doc->>'customer_id')::uuid
 and status='active' and kind in ('customer','both')) then raise exception using errcode='22023',message='CUSTOMER_INACTIVE';end if;
 v_rate:=finance.flow_rate((p_doc->>'tenant_id')::uuid,(p_doc->>'legal_entity_id')::uuid,p_doc->>'currency_code',
 (p_doc->>'document_date')::date,(p_doc->>'exchange_rate_id')::uuid);
 select rounding_scale into v_scale from core.legal_entities where id=(p_doc->>'legal_entity_id')::uuid;
 if (v_rate->>'exchange_rate')::numeric<>(p_doc->>'exchange_rate')::numeric or v_scale<>(p_doc->>'rounding_scale')::integer then
 raise exception using errcode='55000',message='DOCUMENT_RECALCULATION_REQUIRED';end if;
 select coalesce(jsonb_agg(x->'snapshot' order by (x->>'line_number')::integer),'[]') into v_inputs from jsonb_array_elements(p_doc->'lines') x;
 v_price:=sales.flow_price(p_kind,p_doc||jsonb_build_object('amount',p_doc->'grand_total'),v_inputs);
 if (v_price->>'grand_total')::numeric<>(p_doc->>'grand_total')::numeric
 or (v_price->>'tax_total')::numeric<>(p_doc->>'tax_total')::numeric
 or (v_price->>'base_total')::numeric<>(p_doc->>'base_total')::numeric
 or exists(select 1 from jsonb_array_elements(v_price->'lines') n join jsonb_array_elements(p_doc->'lines') o
 on n->>'line_id'=o->>'id' where (n->>'taxable_amount')::numeric<>(o->>'taxable_amount')::numeric
 or (n->>'tax_amount')::numeric<>(o->>'tax_amount')::numeric
 or n->>'product_kind' is distinct from o#>>'{snapshot,product_kind}'
 or n->>'tracking_mode' is distinct from o#>>'{snapshot,tracking_mode}') then
 raise exception using errcode='55000',message='DOCUMENT_RECALCULATION_REQUIRED';end if;return v_price;end $$;

create function sales.flow_transition(p_tenant_id uuid,p_legal_entity_id uuid,p_branch_id uuid,p_command_id uuid,
 p_idempotency_key uuid,p_client_timestamp timestamptz,p_payload jsonb,p_expected_entity_version bigint)
returns jsonb language plpgsql security definer set search_path='' as $$
declare v_kind text:=p_payload->>'document_type';v_id uuid:=(p_payload->>'document_id')::uuid;
 v_action text:=p_payload->>'action';v_decision text:=p_payload->>'decision';v_command text;
 v_doc jsonb;v_before jsonb;v_hash text;v_replay jsonb;v_to text;v_snapshot jsonb;
 v_workflow workflow.workflow_definitions%rowtype;v_request uuid:=gen_random_uuid();v_first integer;
 v_ar workflow.approval_requests%rowtype;v_step jsonb;v_number text;
begin
 v_command:='sales.'||v_kind||case when v_decision is null then '.transition' else '.decide' end;
 perform core.wave3_require_scope(p_tenant_id,case when v_decision is null then sales.flow_permission(v_kind,'manage') else 'workflow.approvals.decide' end,p_legal_entity_id,p_branch_id);
 if sales.flow_table(v_kind) is null or p_branch_id is null or p_client_timestamp is null then raise exception using errcode='22023',message='DOCUMENT_PAYLOAD_INVALID';end if;
 v_hash:=core.wave3_request_hash(v_command,p_command_id,p_tenant_id,p_legal_entity_id,p_branch_id,p_payload,p_expected_entity_version);
 v_replay:=core.wave3_replay(p_tenant_id,v_command,p_command_id,p_idempotency_key,v_hash);if v_replay is not null then return v_replay;end if;
 v_doc:=sales.flow_document(v_kind,p_tenant_id,v_id,true);v_before:=v_doc;
 if v_doc is null or (v_doc->>'legal_entity_id')::uuid<>p_legal_entity_id or (v_doc->>'branch_id')::uuid<>p_branch_id then
 raise exception using errcode='P0002',message='DOCUMENT_NOT_FOUND';end if;
 perform core.wave3_assert_expected_version((v_doc->>'version')::bigint,p_expected_entity_version,v_doc);
 if v_doc->>'status'='posted' then raise exception using errcode='55000',message='POSTED_DOCUMENT_IMMUTABLE';end if;
 v_snapshot:=v_doc->'workflow_snapshot';v_number:=v_doc->>'document_number';
 if v_decision is not null then
 if v_decision not in ('approved','rejected') or v_doc->>'status'<>'pending_approval' then raise exception using errcode='55000',message='APPROVAL_NOT_PENDING';end if;
 select * into v_ar from workflow.approval_requests where tenant_id=p_tenant_id and document_type=v_kind and document_id=v_id and status='submitted' for update;
 if not found then raise exception using errcode='55000',message='APPROVAL_REQUEST_NOT_FOUND';end if;
 if v_ar.submitted_by=auth.uid() then raise exception using errcode='42501',message='SEGREGATION_OF_DUTIES_VIOLATION';end if;
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
 perform sales.flow_revalidate(v_kind,v_doc);
 select * into v_workflow from workflow.workflow_definitions where tenant_id=p_tenant_id and document_type=v_kind and status='active'
 and (legal_entity_id is null or legal_entity_id=p_legal_entity_id) order by (legal_entity_id is not null) desc limit 1;
 if not found then raise exception using errcode='55000',message='WORKFLOW_CONFIGURATION_ERROR';end if;
 select jsonb_build_object('definition_id',v_workflow.id,'revision',v_workflow.revision,'lifecycle',v_workflow.lifecycle,
 'steps',coalesce(jsonb_agg(sales.flow_exact_json(to_jsonb(s)) order by s.step_order),'[]'::jsonb)) into v_snapshot
 from workflow.approval_matrix_steps s where s.tenant_id=p_tenant_id and s.workflow_definition_id=v_workflow.id and s.status='active'
 and (s.currency_code is null or s.currency_code=v_doc->>'currency_code')
 and (s.minimum_amount is null or (v_doc->>'grand_total')::numeric>=s.minimum_amount)
 and (s.maximum_amount is null or (v_doc->>'grand_total')::numeric<=s.maximum_amount);
 if v_workflow.lifecycle->'requires_approval' is distinct from 'false'::jsonb then
 select min((x->>'step_order')::integer) into v_first from jsonb_array_elements(v_snapshot->'steps') x;
 if v_first is null then raise exception using errcode='55000',message='WORKFLOW_CONFIGURATION_ERROR';end if;end if;
 v_to:=case when v_first is null then 'submitted' else 'pending_approval' end;
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
 execute format('update sales.%I set status=$1,workflow_snapshot=$2,document_number=$3,submitted_by=case when $4=''submit'' then $5 else submitted_by end,updated_by=$5,request_id=$6,command_id=$7,correlation_id=$6,client_timestamp=$8 where tenant_id=$9 and id=$10',sales.flow_table(v_kind))
 using v_to,v_snapshot,v_number,v_action,auth.uid(),v_request,p_command_id,p_client_timestamp,p_tenant_id,v_id;
 return core.wave3_finish_command(p_tenant_id,v_command,p_command_id,v_kind,v_id,p_idempotency_key,v_hash,v_before,
 sales.flow_document(v_kind,p_tenant_id,v_id),p_legal_entity_id,p_branch_id,coalesce(p_payload->'source_context','{}'),
 jsonb_build_object('from_status',v_doc->>'status','to_status',v_to,'reason',coalesce(p_payload->>'reason',p_payload->>'note')),
 jsonb_build_array(jsonb_build_object('topic',v_command,'payload',jsonb_build_object('status',v_to))),'[]',v_request,v_request);
end $$;

-- Keep generic transition signatures and preserve the latest AC-304 implementation.
-- A tiny dispatch branch is added to each existing function; all original paths remain.
do $$ declare v_name text;v_definition text;v_marker integer;v_dispatch text;begin
 foreach v_name in array array['transition_operational_document','decide_operational_approval'] loop
 select pg_get_functiondef(p.oid) into v_definition from pg_proc p join pg_namespace n on n.oid=p.pronamespace
 where n.nspname='api' and p.proname=v_name and p.pronargs=8;
 v_marker:=strpos(v_definition,E'\nbegin\n');
 if v_marker=0 then raise exception 'Operational dispatch integration requires a reviewed function body';end if;
 v_dispatch:=E'\n  if p_payload->>''document_type'' in (''delivery'',''sales_invoice'',''customer_receipt'',''sales_return'') then\n    return sales.flow_transition(p_tenant_id,p_legal_entity_id,p_branch_id,p_command_id,p_idempotency_key,p_client_timestamp,p_payload,p_expected_entity_version);\n  end if;';
 v_definition:=overlay(v_definition placing E'\nbegin'||v_dispatch||E'\n' from v_marker for 7);
 execute v_definition;
 end loop;end $$;

-- Declare typed named draft commands while sharing their invariants privately.
do $$ declare v_kind text;v_name text;begin
 for v_kind,v_name in select * from (values ('delivery','upsert_delivery'),('sales_invoice','upsert_sales_invoice'),
 ('customer_receipt','upsert_customer_receipt'),('sales_return','upsert_sales_return')) x loop
 execute format($ddl$create function api.%I(p_tenant_id uuid,p_legal_entity_id uuid,p_branch_id uuid,p_command_id uuid,
 p_idempotency_key uuid,p_client_timestamp timestamptz,p_payload jsonb,p_expected_entity_version bigint default null)
 returns jsonb language sql security definer set search_path='' as $body$
 select sales.flow_upsert(%L,p_tenant_id,p_legal_entity_id,p_branch_id,p_command_id,p_idempotency_key,p_client_timestamp,p_payload,p_expected_entity_version) $body$ $ddl$,v_name,v_kind);
 execute format('revoke all on function api.%I(uuid,uuid,uuid,uuid,uuid,timestamptz,jsonb,bigint) from public,anon,authenticated',v_name);
 execute format('grant execute on function api.%I(uuid,uuid,uuid,uuid,uuid,timestamptz,jsonb,bigint) to authenticated',v_name);
 end loop;end $$;
revoke all on function sales.flow_upsert(text,uuid,uuid,uuid,uuid,uuid,timestamptz,jsonb,bigint),sales.flow_revalidate(text,jsonb),
 sales.flow_transition(uuid,uuid,uuid,uuid,uuid,timestamptz,jsonb,bigint) from public,anon,authenticated;
