-- CANDIDATE ONLY. No migration installation, sender activation or deployment.
-- Requires 20261031090000_field_sales_governance.sql inside the rollback harness.
insert into core.permissions(code,module,description,privileged) values
 ('sales.field.confirmations.manage','sales','Authorize contacts and request scoped verified order responses.',true);
-- Existing role/membership grants are unchanged. Restricted reps cannot inherit this capability.
create table field_sales.confirmation_contacts (
 id uuid primary key, tenant_id uuid not null, legal_entity_id uuid not null,
 branch_id uuid not null, customer_id uuid not null, version bigint not null default 1,
 name text not null, email text not null, authority_note text not null,
 active boolean not null default true, valid_until timestamptz not null,
 authorized_by uuid not null references auth.users(id), authorized_at timestamptz not null default now(),
 foreign key(tenant_id,legal_entity_id) references core.legal_entities(tenant_id,id),
 foreign key(tenant_id,branch_id) references core.branches(tenant_id,id),
 foreign key(tenant_id,customer_id) references crm.parties(tenant_id,id),
 check(version>0),check(length(name) between 1 and 200),
 check(length(email)<=254 and email=lower(trim(email)) and email ~ '^[^[:space:]@]+@[^[:space:]@]+\.[^[:space:]@]+$'),
 check(length(authority_note) between 1 and 1000)
);
alter table field_sales.confirmation_contacts enable row level security;
create index confirmation_contacts_scope on field_sales.confirmation_contacts(tenant_id,legal_entity_id,branch_id,customer_id);

-- No public API enables transport. A separately reviewed worker/provider rollout
-- must configure this private policy. Missing policy means unavailable.
create table field_sales.confirmation_transport (
 tenant_id uuid primary key references core.tenants(id), enabled boolean not null default false,
 version bigint not null default 1 check(version>0),
 acceptance_minutes integer not null default 1440 check(acceptance_minutes between 15 and 10080),
 verification_secret bytea not null default extensions.gen_random_bytes(32)
);
alter table field_sales.confirmation_transport enable row level security;
create function field_sales.confirmation_ready(t uuid) returns boolean
language sql stable security definer set search_path='' as $$
 select coalesce((select enabled from field_sales.confirmation_transport where tenant_id=t),false)
$$;
create function field_sales.confirmation_contact_entity(c field_sales.confirmation_contacts) returns jsonb
language sql stable set search_path='' as $$
 select field_sales.exact(to_jsonb(c))||jsonb_build_object('channel_state','unverified')
$$;
create table field_sales.confirmation_challenges (
 id uuid primary key, tenant_id uuid not null references core.tenants(id), legal_entity_id uuid not null, branch_id uuid not null,
 request_id uuid not null references field_sales.order_requests(id), request_version bigint not null, source_digest text not null,
 contact_id uuid not null references field_sales.confirmation_contacts(id), contact_version bigint not null,
 order_digest text not null, policy_version bigint not null, recipient_tag text not null,
 version bigint not null default 1, state text not null default 'queued_link'
  check(state in('queued_link','link_prepared','link_accepted','code_requested','code_prepared','code_accepted','verified','responded','revoked')),
 token_hash text unique, code_hash text, proof_hash text, offer_hash text, failures integer not null default 0 check(failures between 0 and 5),
 provider_link_reference text, provider_code_reference text,
 issued_by uuid not null references auth.users(id), issued_at timestamptz not null default clock_timestamp(),
 expires_at timestamptz not null, acceptance_valid_until timestamptz not null,
 check(expires_at>issued_at),check(acceptance_valid_until>=expires_at),check(version>0)
);
alter table field_sales.confirmation_challenges enable row level security;
create index confirmation_recipient_rate on field_sales.confirmation_challenges(tenant_id,recipient_tag,issued_at);
create index confirmation_request on field_sales.confirmation_challenges(request_id,issued_at);

create function field_sales.confirmation_source(request uuid,revalidate boolean default true) returns jsonb
language plpgsql security definer set search_path='' as $$
declare r field_sales.order_requests; o sales.sales_orders; reviewed jsonb; lines jsonb; begin
 select * into r from field_sales.order_requests where id=request for share;
 if r.id is null or r.state<>'approved' or r.canonical_order_id is null
  or not exists(select 1 from core.tenants t join core.legal_entities e on e.tenant_id=t.id
   join core.branches b on b.tenant_id=t.id and b.legal_entity_id=e.id
   where t.id=r.tenant_id and e.id=r.legal_entity_id and b.id=r.branch_id
    and t.status in('active','trial') and e.status='active' and b.status='active') then
  raise exception using errcode='55000',message='CONFIRMATION_SOURCE_UNAVAILABLE'; end if;
 if revalidate then
  reviewed:=field_sales.prepare(r.tenant_id,r.legal_entity_id,r.branch_id,r.rep_id,r.input);
  if reviewed->>'source_digest' is distinct from r.source_digest then
   raise exception using errcode='40001',message='SOURCE_CHANGED'; end if;
 else
  perform field_sales.assignment(r.tenant_id,r.legal_entity_id,r.branch_id,r.customer_id,r.rep_id);
  if not exists(select 1 from crm.parties where tenant_id=r.tenant_id and id=r.customer_id and status='active') then
   raise exception using errcode='55000',message='CONFIRMATION_SOURCE_UNAVAILABLE'; end if;
 end if;
 select * into o from sales.sales_orders where id=r.canonical_order_id for share;
 if o.status<>'draft' or o.customer_id<>r.customer_id or o.tenant_id<>r.tenant_id
  or o.legal_entity_id<>r.legal_entity_id or o.branch_id<>r.branch_id then
  raise exception using errcode='55000',message='CONFIRMATION_SOURCE_UNAVAILABLE'; end if;
 select coalesce(jsonb_agg(to_jsonb(l) order by l.id),'[]') into lines from sales.sales_order_lines l where l.sales_order_id=o.id;
 return jsonb_build_object('request',to_jsonb(r),'order_version',o.version::text,
  'order_digest',encode(extensions.digest((to_jsonb(o)||jsonb_build_object('lines',lines))::text,'sha256'),'hex'));
end $$;
create function field_sales.confirmation_issue_context(t uuid,e uuid,b uuid,payload jsonb) returns jsonb
language plpgsql security definer set search_path='' as $$
declare c field_sales.confirmation_contacts; source jsonb; policy field_sales.confirmation_transport; issued_at timestamptz; begin
 if not field_sales.confirmation_ready(t) then
  raise exception using errcode='55000',message='CONFIRMATION_PROVIDER_UNAVAILABLE'; end if;
 if exists(select 1 from jsonb_object_keys(payload) k where k not in('id','request_id','contact_id','request_version','source_digest')) then
  raise exception using errcode='22023',message='CONFIRMATION_FIELDS_INVALID'; end if;
 if not exists(select 1 from field_sales.order_requests where id=(payload->>'request_id')::uuid
  and tenant_id=t and legal_entity_id=e and branch_id=b) then
  raise exception using errcode='42501',message='CONFIRMATION_SCOPE_INVALID'; end if;
 source:=field_sales.confirmation_source((payload->>'request_id')::uuid);
 if source->'request'->>'version' is distinct from payload->>'request_version'
  or source->'request'->>'source_digest' is distinct from payload->>'source_digest' then
  raise exception using errcode='40001',message='SOURCE_CHANGED'; end if;
 select * into c from field_sales.confirmation_contacts where id=(payload->>'contact_id')::uuid for share;
 if c.id is null or c.tenant_id<>t or c.legal_entity_id<>e or c.branch_id<>b
  or c.customer_id<>(source->'request'->>'customer_id')::uuid or not c.active
  or c.valid_until<=clock_timestamp()+interval '15 minutes' then
  raise exception using errcode='42501',message='CONTACT_NOT_AUTHORIZED'; end if;
 select * into policy from field_sales.confirmation_transport where tenant_id=t for share;
 issued_at:=clock_timestamp();
 return source||jsonb_build_object('contact_version',c.version::text,'policy_version',policy.version::text,
  'recipient_tag',encode(extensions.hmac(c.email,encode(policy.verification_secret,'hex'),'sha256'),'hex'),
  'issued_at',issued_at,'acceptance_valid_until',least(c.valid_until,issued_at+make_interval(mins=>policy.acceptance_minutes)));
end $$;
create function field_sales.confirmation_challenge_entity(c field_sales.confirmation_challenges) returns jsonb
language sql stable set search_path='' as $$
 select jsonb_build_object('id',c.id,'tenant_id',c.tenant_id,'legal_entity_id',c.legal_entity_id,'branch_id',c.branch_id,
  'request_id',c.request_id,'request_version',c.request_version::text,'contact_id',c.contact_id,'contact_version',c.contact_version::text,
  'source_digest',c.source_digest,'version',c.version::text,'state',c.state,'expires_at',c.expires_at,
  'acceptance_valid_until',c.acceptance_valid_until)
$$;

create function api.field_sales_confirmation_contacts(p_tenant_id uuid,p_legal_entity_id uuid,p_branch_id uuid,p_customer_id uuid,
 p_after uuid default null,p_limit integer default 50)
returns jsonb language plpgsql security definer set search_path='' as $$declare items jsonb; begin
 perform field_sales.require_company(p_tenant_id,p_legal_entity_id,p_branch_id,'sales.field.confirmations.manage');
 if p_limit is null or p_limit not between 1 and 200 then raise exception using errcode='22023',message='PAGE_INVALID'; end if;
 select coalesce(jsonb_agg(x.item order by x.id),'[]') into items from (
  select c.id,field_sales.confirmation_contact_entity(c) item from field_sales.confirmation_contacts c
  where c.tenant_id=p_tenant_id and c.legal_entity_id=p_legal_entity_id and c.branch_id=p_branch_id
   and c.customer_id=p_customer_id and c.active and c.valid_until>clock_timestamp() and (p_after is null or c.id>p_after)
  order by c.id limit p_limit+1) x;
 return jsonb_build_object('provider_state',case when field_sales.confirmation_ready(p_tenant_id) then 'configured' else 'unavailable' end,
  'items',(select coalesce(jsonb_agg(value order by ordinality),'[]') from jsonb_array_elements(items) with ordinality where ordinality<=p_limit),
  'next_cursor',case when jsonb_array_length(items)>p_limit then items->(p_limit-1)->>'id' end);
end $$;

create function api.field_sales_confirmation_command(p_tenant_id uuid,p_legal_entity_id uuid,p_branch_id uuid,
 p_command_id uuid,p_idempotency_key uuid,p_client_timestamp timestamptz,p_action text,p_payload jsonb,
 p_expected_entity_version bigint default null) returns jsonb
language plpgsql security definer set search_path='' as $$
declare c field_sales.confirmation_contacts; ch field_sales.confirmation_challenges; context jsonb;
 hash text; replay jsonb; before jsonb; entity jsonb; name text; begin
 perform field_sales.require_company(p_tenant_id,p_legal_entity_id,p_branch_id,'sales.field.confirmations.manage');
 if p_client_timestamp is null or coalesce(p_action,'') not in('authorize_contact','revoke_contact','issue_order','revoke_challenge')
  or jsonb_typeof(p_payload) is distinct from 'object' or p_command_id is null or p_idempotency_key is null then
  raise exception using errcode='22023',message='CONFIRMATION_COMMAND_INVALID'; end if;
 name:='sales.field.confirmation.'||p_action;
 if p_action='issue_order' then
  if p_expected_entity_version is not null then raise exception using errcode='22023',message='CONFIRMATION_COMMAND_INVALID'; end if;
  context:=field_sales.confirmation_issue_context(p_tenant_id,p_legal_entity_id,p_branch_id,p_payload);
 end if;
 hash:=core.wave3_request_hash(name,p_command_id,p_tenant_id,p_legal_entity_id,p_branch_id,p_payload,p_expected_entity_version);
 replay:=core.wave3_replay(p_tenant_id,name,p_command_id,p_idempotency_key,hash);
 if replay is not null then return replay; end if;
 if p_action='revoke_challenge' then
  if exists(select 1 from jsonb_object_keys(p_payload) k where k not in('id','reason'))
   or length(trim(coalesce(p_payload->>'reason',''))) not between 1 and 500 then
   raise exception using errcode='22023',message='REVOCATION_REASON_REQUIRED'; end if;
  select * into ch from field_sales.confirmation_challenges where id=(p_payload->>'id')::uuid
   and tenant_id=p_tenant_id and legal_entity_id=p_legal_entity_id and branch_id=p_branch_id for update;
  if ch.id is null then raise exception using errcode='42501',message='CONFIRMATION_SCOPE_INVALID'; end if;
  before:=field_sales.confirmation_challenge_entity(ch);
  perform core.wave3_assert_expected_version(ch.version,p_expected_entity_version,before);
  update field_sales.confirmation_challenges set state='revoked',version=version+1 where id=ch.id returning * into ch;
  return core.wave3_finish_command(p_tenant_id,name,p_command_id,'field_confirmation_challenge',ch.id,p_idempotency_key,hash,before,
   field_sales.confirmation_challenge_entity(ch),p_legal_entity_id,p_branch_id);
 end if;
 if p_action='issue_order' then
  perform pg_advisory_xact_lock(hashtextextended(p_tenant_id::text||(context->>'recipient_tag'),0));
  if (select count(*) from field_sales.confirmation_challenges where tenant_id=p_tenant_id
   and recipient_tag=context->>'recipient_tag' and issued_at>clock_timestamp()-interval '1 hour')>=5 then
   raise exception using errcode='54000',message='CONFIRMATION_RATE_LIMITED'; end if;
  update field_sales.confirmation_challenges set state='revoked',version=version+1
   where request_id=(p_payload->>'request_id')::uuid and state<>'revoked';
  insert into field_sales.confirmation_challenges(id,tenant_id,legal_entity_id,branch_id,request_id,request_version,source_digest,
   contact_id,contact_version,order_digest,policy_version,recipient_tag,issued_by,issued_at,expires_at,acceptance_valid_until)
   values((p_payload->>'id')::uuid,p_tenant_id,p_legal_entity_id,p_branch_id,(p_payload->>'request_id')::uuid,
    (p_payload->>'request_version')::bigint,p_payload->>'source_digest',(p_payload->>'contact_id')::uuid,
    (context->>'contact_version')::bigint,context->>'order_digest',(context->>'policy_version')::bigint,
    context->>'recipient_tag',auth.uid(),(context->>'issued_at')::timestamptz,
    (context->>'issued_at')::timestamptz+interval '15 minutes',(context->>'acceptance_valid_until')::timestamptz)
   returning * into ch;
  return core.wave3_finish_command(p_tenant_id,name,p_command_id,'field_confirmation_challenge',ch.id,p_idempotency_key,hash,null,
   field_sales.confirmation_challenge_entity(ch),p_legal_entity_id,p_branch_id);
 end if;
 if exists(select 1 from jsonb_object_keys(p_payload) k where k not in
  ('id','customer_id','name','email','authority_note','valid_until')) then
  raise exception using errcode='22023',message='CONTACT_FIELDS_INVALID'; end if;
 select * into c from field_sales.confirmation_contacts where id=(p_payload->>'id')::uuid for update;
 if c.id is not null then
  if c.tenant_id<>p_tenant_id or c.legal_entity_id<>p_legal_entity_id or c.branch_id<>p_branch_id then
   raise exception using errcode='42501',message='CONTACT_SCOPE_INVALID'; end if;
  before:=field_sales.confirmation_contact_entity(c);
  perform core.wave3_assert_expected_version(c.version,p_expected_entity_version,before);
 elsif p_expected_entity_version is not null or p_action='revoke_contact' then
  raise exception using errcode='40001',message='VERSION_CONFLICT'; end if;
 if p_action='revoke_contact' then
  update field_sales.confirmation_contacts set active=false,version=version+1
   where id=c.id returning * into c;
 else
  if not exists(select 1 from crm.parties where tenant_id=p_tenant_id and id=(p_payload->>'customer_id')::uuid
   and status='active' and kind in('customer','both'))
   or (p_payload->>'valid_until')::timestamptz<=clock_timestamp()
   or (p_payload->>'valid_until')::timestamptz>clock_timestamp()+interval '366 days' then
   raise exception using errcode='22023',message='CONTACT_INVALID'; end if;
  insert into field_sales.confirmation_contacts(id,tenant_id,legal_entity_id,branch_id,customer_id,name,email,authority_note,valid_until,authorized_by)
   values((p_payload->>'id')::uuid,p_tenant_id,p_legal_entity_id,p_branch_id,(p_payload->>'customer_id')::uuid,
    trim(p_payload->>'name'),lower(trim(p_payload->>'email')),trim(p_payload->>'authority_note'),(p_payload->>'valid_until')::timestamptz,auth.uid())
   on conflict(id) do update set customer_id=excluded.customer_id,name=excluded.name,email=excluded.email,
    authority_note=excluded.authority_note,valid_until=excluded.valid_until,active=true,
    authorized_by=auth.uid(),authorized_at=clock_timestamp(),version=field_sales.confirmation_contacts.version+1
   where field_sales.confirmation_contacts.tenant_id=p_tenant_id
    and field_sales.confirmation_contacts.legal_entity_id=p_legal_entity_id and field_sales.confirmation_contacts.branch_id=p_branch_id
    and field_sales.confirmation_contacts.version=p_expected_entity_version
   returning * into c;
  if c.id is null then raise exception using errcode='40001',message='VERSION_CONFLICT'; end if;
 end if;
 entity:=field_sales.confirmation_contact_entity(c);
 return core.wave3_finish_command(p_tenant_id,name,p_command_id,'field_confirmation_contact',c.id,
  p_idempotency_key,hash,before,entity,p_legal_entity_id,p_branch_id);
end $$;
revoke all on function api.field_sales_confirmation_contacts(uuid,uuid,uuid,uuid,uuid,integer),
 api.field_sales_confirmation_command(uuid,uuid,uuid,uuid,uuid,timestamptz,text,jsonb,bigint) from public,anon;
grant execute on function api.field_sales_confirmation_contacts(uuid,uuid,uuid,uuid,uuid,integer),
 api.field_sales_confirmation_command(uuid,uuid,uuid,uuid,uuid,timestamptz,text,jsonb,bigint) to authenticated;

create function field_sales.confirmation_current(ch field_sales.confirmation_challenges,check_expiry boolean default true)
returns boolean language plpgsql security definer set search_path='' as $$
declare c field_sales.confirmation_contacts; policy field_sales.confirmation_transport; source jsonb; begin
 if ch.id is null or ch.state='revoked' or ch.failures>=5
  or (check_expiry and ch.expires_at<=clock_timestamp()) or ch.acceptance_valid_until<=clock_timestamp() then return false; end if;
 select * into policy from field_sales.confirmation_transport where tenant_id=ch.tenant_id for share;
 if check_expiry and (policy.tenant_id is null or not policy.enabled or policy.version<>ch.policy_version) then return false; end if;
 select * into c from field_sales.confirmation_contacts where id=ch.contact_id for share;
 if c.id is null or not c.active or c.valid_until<=clock_timestamp() or c.version<>ch.contact_version then return false; end if;
 source:=field_sales.confirmation_source(ch.request_id,check_expiry);
 return (source->'request'->>'version')::bigint=ch.request_version
  and source->'request'->>'source_digest'=ch.source_digest and source->>'order_digest'=ch.order_digest
  and c.tenant_id=ch.tenant_id and c.legal_entity_id=ch.legal_entity_id and c.branch_id=ch.branch_id
  and c.customer_id=(source->'request'->>'customer_id')::uuid;
 exception when others then return false;
end $$;
create function field_sales.confirmation_code_hash(ch field_sales.confirmation_challenges,code text) returns text
language sql stable security definer set search_path='' as $$
 select encode(extensions.hmac(ch.id::text||':'||code,encode(p.verification_secret,'hex'),'sha256'),'hex')
 from field_sales.confirmation_transport p where p.tenant_id=ch.tenant_id
$$;
-- Service-only preparation/acknowledgement seam. There is deliberately no
-- network sender or background job. Secrets arrive ephemerally from a future
-- reviewed worker and only hashes are retained. Acknowledgements are not proof
-- of email delivery or legal authority.
create function field_sales.confirmation_dispatch(p_id uuid,p_step text,p_secret text,p_provider_reference text default null)
returns jsonb language plpgsql security definer set search_path='' as $$
declare ch field_sales.confirmation_challenges; secret_hash text; begin
 select * into ch from field_sales.confirmation_challenges where id=p_id for update;
 if not field_sales.confirmation_current(ch) then
  raise exception using errcode='55000',message='CONFIRMATION_UNAVAILABLE'; end if;
 if p_step in('prepare_link','ack_link') then
  if coalesce(p_secret,'') !~ '^[0-9a-f]{64}$' then raise exception using errcode='22023',message='DISPATCH_INVALID'; end if;
  secret_hash:=encode(extensions.digest(p_secret,'sha256'),'hex');
  if p_step='prepare_link' and ch.state in('queued_link','link_prepared') then
   if ch.token_hash is not null and ch.token_hash<>secret_hash then raise exception using errcode='22023',message='DISPATCH_IMMUTABLE'; end if;
   update field_sales.confirmation_challenges set token_hash=secret_hash,state='link_prepared' where id=p_id;
  elsif p_step='ack_link' and ch.state in('link_prepared','link_accepted') and ch.token_hash=secret_hash
   and length(coalesce(p_provider_reference,'')) between 1 and 200 then
   if ch.provider_link_reference is not null and ch.provider_link_reference<>p_provider_reference then
    raise exception using errcode='22023',message='DISPATCH_IMMUTABLE'; end if;
   update field_sales.confirmation_challenges set state='link_accepted',provider_link_reference=p_provider_reference where id=p_id;
  else raise exception using errcode='55000',message='DISPATCH_STATE_INVALID'; end if;
 elsif p_step in('prepare_code','ack_code') then
  if coalesce(p_secret,'') !~ '^[0-9]{6}$' then raise exception using errcode='22023',message='DISPATCH_INVALID'; end if;
  secret_hash:=field_sales.confirmation_code_hash(ch,p_secret);
  if p_step='prepare_code' and ch.state in('code_requested','code_prepared') then
   if ch.code_hash is not null and ch.code_hash<>secret_hash then raise exception using errcode='22023',message='DISPATCH_IMMUTABLE'; end if;
   update field_sales.confirmation_challenges set code_hash=secret_hash,state='code_prepared' where id=p_id;
  elsif p_step='ack_code' and ch.state in('code_prepared','code_accepted') and ch.code_hash=secret_hash
   and length(coalesce(p_provider_reference,'')) between 1 and 200 then
   if ch.provider_code_reference is not null and ch.provider_code_reference<>p_provider_reference then
    raise exception using errcode='22023',message='DISPATCH_IMMUTABLE'; end if;
   update field_sales.confirmation_challenges set state='code_accepted',provider_code_reference=p_provider_reference where id=p_id;
  else raise exception using errcode='55000',message='DISPATCH_STATE_INVALID'; end if;
 else raise exception using errcode='22023',message='DISPATCH_INVALID'; end if;
 return jsonb_build_object('id',p_id,'kind',case when p_step in('prepare_link','ack_link') then 'order_link' else 'verification_code' end,
  'recipient',(select email from field_sales.confirmation_contacts where id=ch.contact_id),'expires_at',ch.expires_at);
end $$;
grant usage on schema field_sales to service_role;
revoke all on function field_sales.confirmation_dispatch(uuid,text,text,text) from public,anon,authenticated;
grant execute on function field_sales.confirmation_dispatch(uuid,text,text,text) to service_role;

-- Public RPCs are POST-only, anonymous, non-cacheable and intentionally reveal
-- no contact address or offer until the separately delivered code is verified.
create function field_sales.confirmation_public_request() returns boolean
language plpgsql set search_path='' as $$begin
 perform set_config('response.headers','[{"Cache-Control":"no-store"},{"Referrer-Policy":"no-referrer"}]',true);
 return auth.uid() is null and coalesce(current_setting('request.method',true),'')='POST';
end $$;
create function field_sales.confirmation_offer(ch field_sales.confirmation_challenges) returns jsonb
language sql stable security definer set search_path='' as $$
 select jsonb_build_object('request_id',r.id,'request_version',r.version::text,'source_digest',r.source_digest,
  'company',(select name from core.legal_entities where tenant_id=r.tenant_id and id=r.legal_entity_id),
  'customer',(select display_name from crm.parties where tenant_id=r.tenant_id and id=r.customer_id),
  'reference',r.input->>'reference','currency_code',r.preview->>'currency_code','discount_percent',r.preview->>'discount_percent',
  'terms',r.preview->'terms','valid_until',ch.acceptance_valid_until,
  'totals',(r.preview->'pricing')-'lines','lines',(select jsonb_agg(jsonb_build_object(
   'description',line->>'description','quantity',line->>'quantity','unit_price',line->>'unit_price',
   'unit',(select symbol from inventory.units where tenant_id=r.tenant_id and id=(line->>'unit_id')::uuid),
   'line_discount_amount',line->>'line_discount_amount','header_discount_amount',line->>'header_discount_amount',
   'tax_amount',line->>'tax_amount','tax_name',line->>'tax_name','tax_rate',line->>'tax_rate',
   'tax_inclusive',line->'tax_inclusive','line_total',line->>'line_total') order by n)
   from jsonb_array_elements(r.preview->'pricing'->'lines') with ordinality p(line,n)))
 from field_sales.order_requests r where r.id=ch.request_id
$$;
create function api.field_sales_confirmation_request_code(p_token text) returns jsonb
language plpgsql volatile security definer set search_path='' as $$
declare ch field_sales.confirmation_challenges; begin
 if not field_sales.confirmation_public_request() or coalesce(p_token,'') !~ '^[0-9a-f]{64}$' then
  return jsonb_build_object('state','unavailable'); end if;
 select * into ch from field_sales.confirmation_challenges where token_hash=encode(extensions.digest(p_token,'sha256'),'hex') for update;
 if not field_sales.confirmation_current(ch) or ch.state not in('link_accepted','code_requested','code_prepared','code_accepted','verified') then
  return jsonb_build_object('state','unavailable'); end if;
 if ch.state='link_accepted' then
  update field_sales.confirmation_challenges set state='code_requested' where id=ch.id;
 end if;
 return jsonb_build_object('state','check_email');
end $$;
create function api.field_sales_confirmation_verify(p_token text,p_code text) returns jsonb
language plpgsql volatile security definer set search_path='' as $$
declare ch field_sales.confirmation_challenges; proof text; secret bytea; offer jsonb; review_hash text; begin
 if not field_sales.confirmation_public_request() or coalesce(p_token,'') !~ '^[0-9a-f]{64}$' then
  return jsonb_build_object('state','unavailable'); end if;
 select * into ch from field_sales.confirmation_challenges where token_hash=encode(extensions.digest(p_token,'sha256'),'hex') for update;
 if not field_sales.confirmation_current(ch) or ch.state not in('code_accepted','verified','responded') then
  return jsonb_build_object('state','unavailable'); end if;
 if ch.code_hash is distinct from field_sales.confirmation_code_hash(ch,coalesce(p_code,'')) then
  if ch.state<>'responded' then
   update field_sales.confirmation_challenges set failures=failures+1,
    state=case when failures+1>=5 then 'revoked' else state end where id=ch.id;
  end if;
  return jsonb_build_object('state','unavailable'); end if;
 if ch.state='responded' then return jsonb_build_object('state','already_recorded'); end if;
 select verification_secret into secret from field_sales.confirmation_transport where tenant_id=ch.tenant_id;
 offer:=field_sales.confirmation_offer(ch);review_hash:=encode(extensions.digest(offer::text,'sha256'),'hex');
 proof:=encode(extensions.hmac(ch.id::text||':'||ch.token_hash||':'||ch.code_hash||':'||review_hash,encode(secret,'hex'),'sha256'),'hex');
 update field_sales.confirmation_challenges set state='verified',proof_hash=encode(extensions.digest(proof,'sha256'),'hex'),
  offer_hash=review_hash where id=ch.id;
 return jsonb_build_object('state','review','proof',proof,'offer',offer);
end $$;
grant usage on schema api to anon;
revoke all on function api.field_sales_confirmation_request_code(text),api.field_sales_confirmation_verify(text,text) from public,authenticated;
grant execute on function api.field_sales_confirmation_request_code(text),api.field_sales_confirmation_verify(text,text) to anon;

create table field_sales.order_responses (
 id uuid primary key default gen_random_uuid(), challenge_id uuid not null unique references field_sales.confirmation_challenges(id),
 request_id uuid not null references field_sales.order_requests(id), request_version bigint not null, source_digest text not null,
 order_digest text not null, contact_id uuid not null references field_sales.confirmation_contacts(id), contact_version bigint not null,
 contact_snapshot jsonb not null, offer_snapshot jsonb not null,
 response text not null check(response in('accepted','rejected')), reason text not null check(length(reason)<=500),
 authority_attested boolean not null check(authority_attested), method text not null check(method='email_link_and_code'),
 responded_at timestamptz not null default clock_timestamp(), valid_until timestamptz not null
);
alter table field_sales.order_responses enable row level security;
create index confirmation_response_request on field_sales.order_responses(request_id,responded_at);
create function field_sales.confirmation_response_receipt(r field_sales.order_responses) returns jsonb
language sql stable set search_path='' as $$
 select jsonb_build_object('state','recorded','id',r.id,'request_id',r.request_id,'request_version',r.request_version::text,
  'source_digest',r.source_digest,'response',r.response,'responded_at',r.responded_at,'valid_until',r.valid_until,'method',r.method)
$$;
create function api.field_sales_confirmation_respond(p_token text,p_proof text,p_response text,p_reason text,p_authorized boolean)
returns jsonb language plpgsql volatile security definer set search_path='' as $$
declare ch field_sales.confirmation_challenges; response field_sales.order_responses; c field_sales.confirmation_contacts; reviewed_offer jsonb; begin
 if not field_sales.confirmation_public_request() or coalesce(p_token,'') !~ '^[0-9a-f]{64}$'
  or coalesce(p_proof,'') !~ '^[0-9a-f]{64}$' or coalesce(p_response,'') not in('accept','reject')
  or p_authorized is distinct from true or length(coalesce(p_reason,''))>500 then
  return jsonb_build_object('state','unavailable'); end if;
 select * into ch from field_sales.confirmation_challenges where token_hash=encode(extensions.digest(p_token,'sha256'),'hex') for update;
 if not field_sales.confirmation_current(ch) or ch.state not in('verified','responded') then
  return jsonb_build_object('state','unavailable'); end if;
 if ch.proof_hash is distinct from encode(extensions.digest(p_proof,'sha256'),'hex') then
  if ch.state<>'responded' then
   update field_sales.confirmation_challenges set failures=failures+1,
    state=case when failures+1>=5 then 'revoked' else state end where id=ch.id;
  end if;
  return jsonb_build_object('state','unavailable'); end if;
 select * into response from field_sales.order_responses where challenge_id=ch.id;
 if response.id is not null then
  if response.response=(case when p_response='accept' then 'accepted' else 'rejected' end)
   and response.reason=trim(coalesce(p_reason,'')) then return field_sales.confirmation_response_receipt(response); end if;
  return jsonb_build_object('state','conflict');
 end if;
 reviewed_offer:=field_sales.confirmation_offer(ch);
 if ch.offer_hash is distinct from encode(extensions.digest(reviewed_offer::text,'sha256'),'hex') then
  return jsonb_build_object('state','unavailable'); end if;
 select * into c from field_sales.confirmation_contacts where id=ch.contact_id;
 insert into field_sales.order_responses(challenge_id,request_id,request_version,source_digest,order_digest,
  contact_id,contact_version,contact_snapshot,offer_snapshot,response,reason,authority_attested,method,valid_until)
  values(ch.id,ch.request_id,ch.request_version,ch.source_digest,ch.order_digest,ch.contact_id,ch.contact_version,
   field_sales.confirmation_contact_entity(c),reviewed_offer,
   case when p_response='accept' then 'accepted' else 'rejected' end,trim(coalesce(p_reason,'')),true,'email_link_and_code',ch.acceptance_valid_until)
  returning * into response;
 update field_sales.confirmation_challenges set state='responded' where id=ch.id;
 return field_sales.confirmation_response_receipt(response);
end $$;
revoke all on function api.field_sales_confirmation_respond(text,text,text,text,boolean) from public,authenticated;
grant execute on function api.field_sales_confirmation_respond(text,text,text,text,boolean) to anon;

create function api.field_sales_confirmation_receipt(p_tenant_id uuid,p_legal_entity_id uuid,p_branch_id uuid,p_idempotency_key uuid)
returns jsonb language plpgsql security definer set search_path='' as $$declare receipt core.command_receipts; entity jsonb; begin
 perform field_sales.require_company(p_tenant_id,p_legal_entity_id,p_branch_id,'sales.field.confirmations.manage');
 select * into receipt from core.command_receipts where tenant_id=p_tenant_id and actor_id=auth.uid()
  and idempotency_key=p_idempotency_key and command_name in('sales.field.confirmation.authorize_contact',
   'sales.field.confirmation.revoke_contact','sales.field.confirmation.issue_order','sales.field.confirmation.revoke_challenge');
 if receipt.id is null then return jsonb_build_object('state','not_found'); end if;
 entity:=receipt.response->'entity';
 if entity->>'tenant_id' is distinct from p_tenant_id::text or entity->>'legal_entity_id' is distinct from p_legal_entity_id::text
  or entity->>'branch_id' is distinct from p_branch_id::text then
  raise exception using errcode='42501',message='RECEIPT_SCOPE_INVALID'; end if;
 return jsonb_build_object('state','committed','receipt',receipt.response);
end $$;
revoke all on function api.field_sales_confirmation_receipt(uuid,uuid,uuid,uuid) from public,anon;
grant execute on function api.field_sales_confirmation_receipt(uuid,uuid,uuid,uuid) to authenticated;

create function field_sales.confirmation_status(r field_sales.order_requests) returns jsonb
language plpgsql security definer set search_path='' as $$
declare response field_sales.order_responses; ch field_sales.confirmation_challenges; state text; begin
 select * into response from field_sales.order_responses where request_id=r.id order by responded_at desc,id desc limit 1;
 if response.id is null then return jsonb_build_object('state','email_link_pending'); end if;
 select * into ch from field_sales.confirmation_challenges where id=response.challenge_id;
 state:=case when response.valid_until<=clock_timestamp() then 'expired'
  when not field_sales.confirmation_current(ch,false) then 'superseded' else response.response end;
 return jsonb_build_object('state',state,'responded_at',response.responded_at,'valid_until',response.valid_until,'method',response.method);
end $$;
create or replace function field_sales.entity(r field_sales.order_requests) returns jsonb
language sql stable set search_path='' as $$
 select jsonb_build_object('id',r.id,'version',r.version::text,'tenant_id',r.tenant_id,
  'legal_entity_id',r.legal_entity_id,'branch_id',r.branch_id,'customer_id',r.customer_id,'rep_id',r.rep_id,
  'input',r.input,'source_digest',r.source_digest,'preview',r.preview-'canonical','company_state',r.state,
  'canonical_order_id',r.canonical_order_id,'canonical_state',case when r.canonical_order_id is not null then 'draft' end,
  'customer_state',c.status->>'state','customer_response',c.status,'delivery_state','not_requested','decision_by',r.decision_by,
  'decision_reason',r.decision_reason,'decided_at',r.decided_at,'created_at',r.created_at)
 from (select field_sales.confirmation_status(r) status) c
$$;
-- Customer evidence never advances or edits canonical commerce. The separately
-- reviewed company progression/credit/stock slice remains unavailable.
create or replace function field_sales.guard_order() returns trigger
language plpgsql security definer set search_path='' as $$declare order_id uuid; r field_sales.order_requests; begin
 if tg_table_name='sales_orders' then order_id:=old.id;
 else order_id:=case when tg_op='INSERT' then new.sales_order_id else old.sales_order_id end; end if;
 select * into r from field_sales.order_requests where canonical_order_id=order_id;
 if r.id is not null then
  if field_sales.confirmation_status(r)->>'state'='accepted' then
   raise exception using errcode='55000',message='COMPANY_PROGRESSION_UNAVAILABLE'; end if;
  raise exception using errcode='55000',message='CUSTOMER_ACCEPTANCE_REQUIRED';
 end if;
 if tg_op='DELETE' then return old; end if; return new;
end $$;

-- Close explicit ACLs as well as the prerequisite's default privileges, so a
-- different reviewed migration creator cannot expose private helper execution.
do $$declare f record; begin
 for f in select p.oid from pg_proc p join pg_namespace n on n.oid=p.pronamespace
  where n.nspname='field_sales' and left(p.proname,13)='confirmation_' loop
  execute format('revoke all on function %s from public,anon,authenticated,service_role',f.oid::regprocedure);
 end loop;
end $$;
revoke all on field_sales.confirmation_contacts,field_sales.confirmation_transport,
 field_sales.confirmation_challenges,field_sales.order_responses from public,anon,authenticated,service_role;
revoke all on function api.field_sales_confirmation_request_code(text),api.field_sales_confirmation_verify(text,text),
 api.field_sales_confirmation_respond(text,text,text,text,boolean) from public,authenticated,service_role;
grant execute on function field_sales.confirmation_dispatch(uuid,text,text,text) to service_role;
