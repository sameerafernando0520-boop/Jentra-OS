-- CANDIDATE ONLY. Compose after governance and order-email candidates inside the
-- rollback harness. No sender, migration installation or progression activation.
-- At most one active challenge, including races between different recipients.
create unique index confirmation_one_current_request on field_sales.confirmation_challenges(request_id) where state<>'revoked';
create function api.field_sales_confirmation_subjects(p_tenant_id uuid,p_legal_entity_id uuid,p_branch_id uuid,
 p_after uuid default null,p_limit integer default 50) returns jsonb
language plpgsql security definer set search_path='' as $$declare items jsonb; begin
 perform field_sales.require_company(p_tenant_id,p_legal_entity_id,p_branch_id,'sales.field.confirmations.manage');
 if p_limit is null or p_limit not between 1 and 200 then raise exception using errcode='22023',message='PAGE_INVALID'; end if;
 select coalesce(jsonb_agg(x.item order by x.id),'[]') into items from (
  select r.id,field_sales.entity(r)||jsonb_build_object('customer_name',c.display_name) item
  from field_sales.order_requests r join crm.parties c on c.tenant_id=r.tenant_id and c.id=r.customer_id
  where r.tenant_id=p_tenant_id and r.legal_entity_id=p_legal_entity_id and r.branch_id=p_branch_id
   and r.state='approved' and (p_after is null or r.id>p_after) order by r.id limit p_limit+1) x;
 return jsonb_build_object('provider_state',case when field_sales.confirmation_ready(p_tenant_id) then 'configured' else 'unavailable' end,
  'items',(select coalesce(jsonb_agg(value order by ordinality),'[]') from jsonb_array_elements(items) with ordinality where ordinality<=p_limit),
  'next_cursor',case when jsonb_array_length(items)>p_limit then items->(p_limit-1)->>'id' end);
end $$;

create function api.field_sales_confirmation_challenges(p_tenant_id uuid,p_legal_entity_id uuid,p_branch_id uuid,p_request_id uuid,
 p_after uuid default null,p_limit integer default 50) returns jsonb
language plpgsql security definer set search_path='' as $$declare items jsonb; begin
 perform field_sales.require_company(p_tenant_id,p_legal_entity_id,p_branch_id,'sales.field.confirmations.manage');
 if p_limit is null or p_limit not between 1 and 200 then raise exception using errcode='22023',message='PAGE_INVALID'; end if;
 if not exists(select 1 from field_sales.order_requests where id=p_request_id and tenant_id=p_tenant_id
  and legal_entity_id=p_legal_entity_id and branch_id=p_branch_id) then
  raise exception using errcode='42501',message='CONFIRMATION_SCOPE_INVALID'; end if;
 select coalesce(jsonb_agg(x.item order by x.id),'[]') into items from (
  select ch.id,field_sales.confirmation_challenge_entity(ch)||jsonb_build_object(
   'effective_state',case when ch.state='revoked' then 'revoked'
    when ch.state='responded' then field_sales.confirmation_status(r)->>'state'
    when ch.expires_at<=clock_timestamp() then 'expired'
    when not field_sales.confirmation_current(ch) then 'superseded' else ch.state end,
   'recipient_name',c.name) item
  from field_sales.confirmation_challenges ch join field_sales.order_requests r on r.id=ch.request_id
   join field_sales.confirmation_contacts c on c.id=ch.contact_id
  where ch.request_id=p_request_id and ch.tenant_id=p_tenant_id and ch.legal_entity_id=p_legal_entity_id and ch.branch_id=p_branch_id
   and (p_after is null or ch.id>p_after) order by ch.id limit p_limit+1) x;
 return jsonb_build_object('items',(select coalesce(jsonb_agg(value order by ordinality),'[]')
  from jsonb_array_elements(items) with ordinality where ordinality<=p_limit),
  'next_cursor',case when jsonb_array_length(items)>p_limit then items->(p_limit-1)->>'id' end);
end $$;

-- Staff UI additionally binds the exact contact revision it reviewed. This
-- wrapper delegates to the original audited command using the caller's JWT.
-- Exact receipt recovery remains available without requiring stale source data.
create function api.field_sales_confirmation_company_command(p_tenant_id uuid,p_legal_entity_id uuid,p_branch_id uuid,
 p_command_id uuid,p_idempotency_key uuid,p_client_timestamp timestamptz,p_action text,p_payload jsonb,
 p_expected_entity_version bigint default null) returns jsonb
language plpgsql security definer set search_path='' as $$declare c field_sales.confirmation_contacts; r field_sales.order_requests; replay jsonb; hash text; result jsonb; begin
 perform field_sales.require_company(p_tenant_id,p_legal_entity_id,p_branch_id,'sales.field.confirmations.manage');
 if p_action='issue_order' then
  select * into c from field_sales.confirmation_contacts where id=(p_payload->>'contact_id')::uuid
   and tenant_id=p_tenant_id and legal_entity_id=p_legal_entity_id and branch_id=p_branch_id for share;
  if c.id is null then raise exception using errcode='42501',message='CONTACT_NOT_AUTHORIZED'; end if;
  if c.version::text is distinct from p_payload->>'contact_version' then
   raise exception using errcode='40001',message='CONTACT_CHANGED'; end if;
  hash:=core.wave3_request_hash('sales.field.confirmation.issue_order',p_command_id,p_tenant_id,p_legal_entity_id,p_branch_id,
   p_payload-'contact_version',p_expected_entity_version);
  replay:=core.wave3_replay(p_tenant_id,'sales.field.confirmation.issue_order',p_command_id,p_idempotency_key,hash);
  if replay is not null then
   if replay->'entity'->>'contact_version' is distinct from p_payload->>'contact_version' then
    raise exception using errcode='22023',message='IDEMPOTENCY_PAYLOAD_CHANGED'; end if;
   return replay;
  end if;
  perform pg_advisory_xact_lock(hashtextextended('field-confirmation:'||(p_payload->>'request_id'),0));
  select * into r from field_sales.order_requests where id=(p_payload->>'request_id')::uuid
   and tenant_id=p_tenant_id and legal_entity_id=p_legal_entity_id and branch_id=p_branch_id for share;
  if r.id is null then raise exception using errcode='42501',message='CONFIRMATION_SCOPE_INVALID'; end if;
  if field_sales.confirmation_status(r)->>'state'='accepted' then
   raise exception using errcode='55000',message='RESPONSE_ALREADY_CURRENT'; end if;
 elsif p_payload ? 'contact_version' then raise exception using errcode='22023',message='CONFIRMATION_FIELDS_INVALID'; end if;
 result:=api.field_sales_confirmation_command(p_tenant_id,p_legal_entity_id,p_branch_id,p_command_id,p_idempotency_key,
  p_client_timestamp,p_action,p_payload-'contact_version',p_expected_entity_version);
 if p_action='issue_order' and result->'entity'->>'contact_version' is distinct from p_payload->>'contact_version' then
  raise exception using errcode='22023',message='IDEMPOTENCY_PAYLOAD_CHANGED'; end if;
 return result;
end $$;
revoke all on function api.field_sales_confirmation_subjects(uuid,uuid,uuid,uuid,integer),
 api.field_sales_confirmation_challenges(uuid,uuid,uuid,uuid,uuid,integer),
 api.field_sales_confirmation_company_command(uuid,uuid,uuid,uuid,uuid,timestamptz,text,jsonb,bigint) from public,anon,service_role;
grant execute on function api.field_sales_confirmation_subjects(uuid,uuid,uuid,uuid,integer),
 api.field_sales_confirmation_challenges(uuid,uuid,uuid,uuid,uuid,integer),
 api.field_sales_confirmation_company_command(uuid,uuid,uuid,uuid,uuid,timestamptz,text,jsonb,bigint) to authenticated;
-- Only the reviewed staff wrapper remains callable by clients. Its owner calls
-- the original command internally; no role is impersonated or granted authority.
revoke all on function api.field_sales_confirmation_command(uuid,uuid,uuid,uuid,uuid,timestamptz,text,jsonb,bigint) from public,anon,authenticated,service_role;
