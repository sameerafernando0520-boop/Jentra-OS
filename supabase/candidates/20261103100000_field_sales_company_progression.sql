-- CANDIDATE ONLY. Explicit company commands retain canonical credit/stock/ledger
-- implementations. No migration, order transition or role grant is activated.
insert into core.permissions(code,module,description,privileged) values
 ('sales.field.orders.progress','sales','Progress independently approved and customer-accepted field orders.',true);
create table field_sales.order_progressions (
 request_id uuid primary key references field_sales.order_requests(id),
 tenant_id uuid not null, legal_entity_id uuid not null, branch_id uuid not null,
 order_id uuid not null unique references sales.sales_orders(id),
 response_id uuid not null references field_sales.order_responses(id),
 confirmed_by uuid not null references auth.users(id), command_id uuid not null,
 applied_at timestamptz not null default clock_timestamp()
);
alter table field_sales.order_progressions enable row level security;
create index field_progression_response on field_sales.order_progressions(response_id);
create index field_progression_scope on field_sales.order_progressions(tenant_id,legal_entity_id,branch_id,applied_at);
create table field_sales.progression_permits (
 transaction_id bigint not null, order_id uuid not null, actor_id uuid not null,
 primary key(transaction_id,order_id)
);
alter table field_sales.progression_permits enable row level security;

create function field_sales.permit_progression(t uuid,e uuid,b uuid,oid uuid) returns void
language plpgsql security definer set search_path='' as $$declare r field_sales.order_requests; begin
 select * into r from field_sales.order_requests where canonical_order_id=oid for update;
 if r.id is null then return; end if;
 perform field_sales.require_company(t,e,b,'sales.field.orders.progress');
 if r.tenant_id<>t or r.legal_entity_id<>e or r.branch_id<>b or r.rep_id=auth.uid() then
  raise exception using errcode='42501',message='FIELD_PROGRESSION_SCOPE_INVALID'; end if;
 if not exists(select 1 from field_sales.order_progressions where request_id=r.id and order_id=oid) then
  raise exception using errcode='55000',message='FIELD_ORDER_NOT_CONFIRMED'; end if;
 insert into field_sales.progression_permits values(txid_current(),oid,auth.uid()) on conflict do nothing;
end $$;
create or replace function field_sales.guard_order() returns trigger
language plpgsql security definer set search_path='' as $$declare oid uuid; r field_sales.order_requests; begin
 if tg_table_name='sales_orders' then oid:=old.id;
 else oid:=case when tg_op='INSERT' then new.sales_order_id else old.sales_order_id end; end if;
 select * into r from field_sales.order_requests where canonical_order_id=oid;
 if r.id is not null and not exists(select 1 from field_sales.progression_permits
  where transaction_id=txid_current() and order_id=oid and actor_id=auth.uid()) then
  raise exception using errcode='55000',message='FIELD_COMPANY_COMMAND_REQUIRED'; end if;
 if tg_op='DELETE' then return old; end if; return new;
end $$;

-- A confirmed order retains its applied response as an immutable historical
-- fact. Later contact expiry/revocation does not rewrite an already confirmed
-- order. New recipient access and delivery evidence still need current authority.
alter function field_sales.confirmation_status(field_sales.order_requests) rename to confirmation_status_before_progression;
create function field_sales.confirmation_status(r field_sales.order_requests) returns jsonb
language plpgsql security definer set search_path='' as $$declare p field_sales.order_progressions; response field_sales.order_responses; begin
 select * into p from field_sales.order_progressions where request_id=r.id;
 if p.request_id is null then return field_sales.confirmation_status_before_progression(r); end if;
 select * into response from field_sales.order_responses where id=p.response_id;
 return jsonb_build_object('state','accepted','method',response.method,'responded_at',response.responded_at,
  'valid_until',response.valid_until,'applied_at',p.applied_at,'applied_to_order',p.order_id);
end $$;
create or replace function field_sales.entity(r field_sales.order_requests) returns jsonb
language sql stable set search_path='' as $$
 select jsonb_build_object('id',r.id,'version',r.version::text,'tenant_id',r.tenant_id,
  'legal_entity_id',r.legal_entity_id,'branch_id',r.branch_id,'customer_id',r.customer_id,'rep_id',r.rep_id,
  'input',r.input,'source_digest',r.source_digest,'preview',r.preview-'canonical','company_state',r.state,
  'canonical_order_id',r.canonical_order_id,'canonical_state',(select status from sales.sales_orders where id=r.canonical_order_id),
  'customer_state',field_sales.confirmation_status(r)->>'state','customer_response',field_sales.confirmation_status(r),
  'delivery_state','not_requested','decision_by',r.decision_by,'decision_reason',r.decision_reason,
  'decided_at',r.decided_at,'created_at',r.created_at)
$$;

-- The review digest excludes only the server's observation timestamp. Exposure,
-- credit projection time, customer limit/status and exact order version bind it.
alter function api.get_sales_order_credit_preview(uuid,uuid,uuid,uuid) rename to field_credit_preview_canonical;
create function api.get_sales_order_credit_preview(p_tenant_id uuid,p_legal_entity_id uuid,p_branch_id uuid,p_sales_order_id uuid)
returns jsonb language plpgsql security definer set search_path='' as $$declare preview jsonb; r field_sales.order_requests; begin
 preview:=api.field_credit_preview_canonical(p_tenant_id,p_legal_entity_id,p_branch_id,p_sales_order_id);
 select * into r from field_sales.order_requests where canonical_order_id=p_sales_order_id;
 if r.id is null then return preview; end if;
 perform field_sales.require_company(p_tenant_id,p_legal_entity_id,p_branch_id,'sales.field.orders.progress');
 return preview||jsonb_build_object('field_sales_request_id',r.id,
  'field_customer_state',field_sales.confirmation_status(r)->>'state',
  'field_credit_review',encode(extensions.digest((preview-'checked_at')::text,'sha256'),'hex'));
end $$;
revoke all on function api.field_credit_preview_canonical(uuid,uuid,uuid,uuid) from public,anon,authenticated,service_role;
revoke all on function api.get_sales_order_credit_preview(uuid,uuid,uuid,uuid) from public,anon;
grant execute on function api.get_sales_order_credit_preview(uuid,uuid,uuid,uuid) to authenticated;

alter function api.transition_operational_document(uuid,uuid,uuid,uuid,uuid,timestamptz,jsonb,bigint) rename to field_transition_canonical;
create function api.transition_operational_document(p_tenant_id uuid,p_legal_entity_id uuid,p_branch_id uuid,
 p_command_id uuid,p_idempotency_key uuid,p_client_timestamp timestamptz,p_payload jsonb,p_expected_entity_version bigint default null)
returns jsonb language plpgsql security definer set search_path='' as $$
declare r field_sales.order_requests; ch field_sales.confirmation_challenges; response field_sales.order_responses;
 credit jsonb; result jsonb; replay jsonb; oid uuid:=(p_payload->>'document_id')::uuid; begin
 if p_payload->>'document_type'='sales_order' then
  select * into r from field_sales.order_requests where canonical_order_id=oid;
 end if;
 if r.id is null then return api.field_transition_canonical(p_tenant_id,p_legal_entity_id,p_branch_id,
  p_command_id,p_idempotency_key,p_client_timestamp,p_payload,p_expected_entity_version); end if;
 perform field_sales.require_company(p_tenant_id,p_legal_entity_id,p_branch_id,'sales.field.orders.progress');
 perform core.wave3_require_scope(p_tenant_id,'sales.orders.manage',p_legal_entity_id,p_branch_id);
 if r.tenant_id<>p_tenant_id or r.legal_entity_id<>p_legal_entity_id or r.branch_id<>p_branch_id or r.rep_id=auth.uid() then
  raise exception using errcode='42501',message='FIELD_PROGRESSION_SCOPE_INVALID'; end if;
 replay:=core.wave3_replay(p_tenant_id,'sales.document.transition',p_command_id,p_idempotency_key,
  core.wave3_request_hash('sales.document.transition',p_command_id,p_tenant_id,p_legal_entity_id,p_branch_id,p_payload,p_expected_entity_version));
 if replay is not null then return replay; end if;
 perform 1 from field_sales.order_requests where id=r.id for update;
 perform 1 from sales.sales_orders where id=oid for update;
 if p_payload->>'action'='confirm' then
  select * into response from field_sales.order_responses where request_id=r.id order by responded_at desc,id desc limit 1 for share;
  select * into ch from field_sales.confirmation_challenges where id=response.challenge_id for share;
  if response.response is distinct from 'accepted' or response.valid_until<=clock_timestamp()
   or not field_sales.confirmation_current(ch,false) then
   raise exception using errcode='55000',message='CUSTOMER_ACCEPTANCE_REQUIRED'; end if;
  perform field_sales.confirmation_source(r.id);
  -- Preserve the canonical order -> customer -> exposure lock order after the
  -- field request lock. Other confirmations cannot change reviewed exposure.
  perform 1 from crm.parties where tenant_id=p_tenant_id and id=r.customer_id for update;
  perform 1 from sales.customer_credit_exposures where tenant_id=p_tenant_id and legal_entity_id=p_legal_entity_id
   and branch_id=p_branch_id and customer_id=r.customer_id for update;
  credit:=api.field_credit_preview_canonical(p_tenant_id,p_legal_entity_id,p_branch_id,oid);
  if credit->>'projection_available'<>'true' or credit->>'credit_as_of_at' is null
   or (credit->>'credit_as_of_at')::timestamptz<clock_timestamp()-interval '5 minutes'
   or (credit->>'credit_as_of_at')::timestamptz>clock_timestamp() then
   raise exception using errcode='55000',message='CREDIT_PROJECTION_STALE'; end if;
  if p_payload#>>'{source_context,field_credit_review}' is distinct from encode(extensions.digest((credit-'checked_at')::text,'sha256'),'hex') then
   raise exception using errcode='40001',message='CREDIT_REVIEW_CHANGED'; end if;
  if credit->>'reason' is not null and (credit->>'reason'<>'CREDIT_LIMIT_EXCEEDED'
   or coalesce((p_payload->>'override_credit')::boolean,false)=false) then
   raise exception using errcode='55000',message='CREDIT_REVIEW_REQUIRED'; end if;
 elsif p_payload->>'action'='cancel' then
  if length(trim(coalesce(p_payload->>'reason',''))) not between 1 and 1000 then
   raise exception using errcode='22023',message='CANCELLATION_REASON_REQUIRED'; end if;
 else raise exception using errcode='22023',message='FIELD_ACTION_INVALID'; end if;
 insert into field_sales.progression_permits values(txid_current(),oid,auth.uid());
 result:=api.field_transition_canonical(p_tenant_id,p_legal_entity_id,p_branch_id,p_command_id,p_idempotency_key,
  p_client_timestamp,p_payload,p_expected_entity_version);
 delete from field_sales.progression_permits where transaction_id=txid_current() and order_id=oid;
 if p_payload->>'action'='confirm' then
  if result->'entity'->>'status'<>'confirmed' then raise exception using errcode='55000',message='CREDIT_REVIEW_REQUIRED'; end if;
  insert into field_sales.order_progressions values(r.id,p_tenant_id,p_legal_entity_id,p_branch_id,oid,response.id,auth.uid(),p_command_id,clock_timestamp());
 end if;
 return result;
end $$;
revoke all on function api.field_transition_canonical(uuid,uuid,uuid,uuid,uuid,timestamptz,jsonb,bigint) from public,anon,authenticated,service_role;
revoke all on function api.transition_operational_document(uuid,uuid,uuid,uuid,uuid,timestamptz,jsonb,bigint) from public,anon;
grant execute on function api.transition_operational_document(uuid,uuid,uuid,uuid,uuid,timestamptz,jsonb,bigint) to authenticated;

alter function api.reserve_sales_order_stock(uuid,uuid,uuid,uuid,uuid,timestamptz,jsonb,bigint) rename to field_reserve_canonical;
create function api.reserve_sales_order_stock(p_tenant_id uuid,p_legal_entity_id uuid,p_branch_id uuid,
 p_command_id uuid,p_idempotency_key uuid,p_client_timestamp timestamptz,p_payload jsonb,p_expected_entity_version bigint default null)
returns jsonb language plpgsql security definer set search_path='' as $$declare result jsonb; oid uuid:=(p_payload->>'sales_order_id')::uuid; begin
 perform field_sales.permit_progression(p_tenant_id,p_legal_entity_id,p_branch_id,oid);
 result:=api.field_reserve_canonical(p_tenant_id,p_legal_entity_id,p_branch_id,p_command_id,p_idempotency_key,p_client_timestamp,p_payload,p_expected_entity_version);
 delete from field_sales.progression_permits where transaction_id=txid_current() and order_id=oid;
 return result;
end $$;
revoke all on function api.field_reserve_canonical(uuid,uuid,uuid,uuid,uuid,timestamptz,jsonb,bigint) from public,anon,authenticated,service_role;
revoke all on function api.reserve_sales_order_stock(uuid,uuid,uuid,uuid,uuid,timestamptz,jsonb,bigint) from public,anon;
grant execute on function api.reserve_sales_order_stock(uuid,uuid,uuid,uuid,uuid,timestamptz,jsonb,bigint) to authenticated;

-- Every existing delivery draft and posting entry point reaches these private
-- canonical dispatchers. Calls for ordinary company orders keep their behavior.
alter function sales.flow_upsert(text,uuid,uuid,uuid,uuid,uuid,timestamptz,jsonb,bigint) rename to field_flow_upsert_canonical;
create function sales.flow_upsert(p_kind text,p_tenant_id uuid,p_legal_entity_id uuid,p_branch_id uuid,p_command_id uuid,
 p_idempotency_key uuid,p_client_timestamp timestamptz,p_payload jsonb,p_expected_entity_version bigint)
returns jsonb language plpgsql security definer set search_path='' as $$declare oid uuid; result jsonb; begin
 if p_kind='delivery' then
  oid:=(p_payload->>'sales_order_id')::uuid;
  perform field_sales.permit_progression(p_tenant_id,p_legal_entity_id,p_branch_id,oid);
 end if;
 result:=sales.field_flow_upsert_canonical(p_kind,p_tenant_id,p_legal_entity_id,p_branch_id,p_command_id,p_idempotency_key,p_client_timestamp,p_payload,p_expected_entity_version);
 delete from field_sales.progression_permits where transaction_id=txid_current() and order_id=oid;
 return result;
end $$;
alter function sales.flow_post(text,uuid,uuid,uuid,uuid,uuid,timestamptz,jsonb,bigint) rename to field_flow_post_canonical;
create function sales.flow_post(p_kind text,p_tenant_id uuid,p_legal_entity_id uuid,p_branch_id uuid,p_command_id uuid,
 p_idempotency_key uuid,p_client_timestamp timestamptz,p_payload jsonb,p_expected_entity_version bigint)
returns jsonb language plpgsql security definer set search_path='' as $$declare result jsonb; oid uuid; doc jsonb; begin
 doc:=sales.flow_document(p_kind,p_tenant_id,coalesce((p_payload->>'document_id')::uuid,(p_payload->>'id')::uuid),false);
 for oid in select distinct l.sales_order_id from sales.sales_order_lines l
  join jsonb_array_elements(doc->'lines') x on l.id=(x->>'sales_order_line_id')::uuid
  where l.tenant_id=p_tenant_id order by l.sales_order_id loop
  perform field_sales.permit_progression(p_tenant_id,p_legal_entity_id,p_branch_id,oid);
 end loop;
 result:=sales.field_flow_post_canonical(p_kind,p_tenant_id,p_legal_entity_id,p_branch_id,p_command_id,p_idempotency_key,p_client_timestamp,p_payload,p_expected_entity_version);
 delete from field_sales.progression_permits where transaction_id=txid_current() and actor_id=auth.uid();
 return result;
end $$;
revoke all on function field_sales.permit_progression(uuid,uuid,uuid,uuid),
 field_sales.confirmation_status(field_sales.order_requests),
 field_sales.confirmation_status_before_progression(field_sales.order_requests),
 sales.flow_upsert(text,uuid,uuid,uuid,uuid,uuid,timestamptz,jsonb,bigint),
 sales.field_flow_upsert_canonical(text,uuid,uuid,uuid,uuid,uuid,timestamptz,jsonb,bigint),
 sales.flow_post(text,uuid,uuid,uuid,uuid,uuid,timestamptz,jsonb,bigint),
 sales.field_flow_post_canonical(text,uuid,uuid,uuid,uuid,uuid,timestamptz,jsonb,bigint) from public,anon,authenticated,service_role;
