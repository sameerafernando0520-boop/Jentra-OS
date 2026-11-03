-- CANDIDATE ONLY. Delivery evidence is separate from order acceptance and all
-- stock/accounting commands. Requires mail worker and company progression.
create table field_sales.delivery_challenges (
 like field_sales.confirmation_challenges including defaults including constraints,
 delivery_id uuid not null references sales.deliveries(id),
 delivery_version bigint not null check(delivery_version>0)
);
alter table field_sales.delivery_challenges add primary key(id);
create unique index delivery_token_hash_unique on field_sales.delivery_challenges(token_hash);
alter table field_sales.delivery_challenges rename column order_digest to delivery_digest;
alter table field_sales.delivery_challenges add foreign key(tenant_id) references core.tenants(id),
 add foreign key(request_id) references field_sales.order_requests(id),
 add foreign key(contact_id) references field_sales.confirmation_contacts(id),
 add foreign key(issued_by) references auth.users(id);
alter table field_sales.delivery_challenges enable row level security;
create unique index delivery_one_current_challenge on field_sales.delivery_challenges(delivery_id) where state<>'revoked';
create index delivery_recipient_rate on field_sales.delivery_challenges(tenant_id,recipient_tag,issued_at);
create index delivery_challenge_history on field_sales.delivery_challenges(delivery_id,id);
create index delivery_challenge_request on field_sales.delivery_challenges(request_id);
create index delivery_challenge_contact on field_sales.delivery_challenges(contact_id);
create table field_sales.delivery_responses (
 id uuid primary key default gen_random_uuid(),challenge_id uuid not null unique references field_sales.delivery_challenges(id),
 tenant_id uuid not null,legal_entity_id uuid not null,branch_id uuid not null,request_id uuid not null,
 delivery_id uuid not null references sales.deliveries(id),delivery_version bigint not null,delivery_digest text not null,
 contact_snapshot jsonb not null,offer_snapshot jsonb not null,quantities jsonb not null,
 response text not null check(response in('received','refused','exception')),reason text not null,
 method text not null default 'delivery_email_and_code' check(method='delivery_email_and_code'),
 responded_at timestamptz not null default clock_timestamp()
);
alter table field_sales.delivery_responses enable row level security;
create index delivery_response_history on field_sales.delivery_responses(delivery_id,responded_at desc,id);

create function field_sales.delivery_source(did uuid) returns jsonb
language plpgsql security definer set search_path='' as $$declare d sales.deliveries; r field_sales.order_requests; lines jsonb; offer jsonb; digest text; begin
 select * into d from sales.deliveries where id=did for share;
 select * into r from field_sales.order_requests where canonical_order_id=d.sales_order_id;
 if d.id is null or d.status<>'posted' or r.id is null or not exists(select 1 from field_sales.order_progressions where request_id=r.id)
  or d.tenant_id<>r.tenant_id or d.legal_entity_id<>r.legal_entity_id or d.branch_id<>r.branch_id or d.customer_id<>r.customer_id then
  raise exception using errcode='55000',message='POSTED_FIELD_DELIVERY_REQUIRED'; end if;
 select coalesce(jsonb_agg(to_jsonb(l) order by l.line_number,l.id),'[]') into lines from sales.delivery_lines l where document_id=d.id;
 if jsonb_array_length(lines)=0 then raise exception using errcode='55000',message='DELIVERY_LINES_REQUIRED'; end if;
 digest:=encode(extensions.digest((to_jsonb(d)||jsonb_build_object('lines',lines))::text,'sha256'),'hex');
 offer:=jsonb_build_object('delivery_id',d.id,'delivery_version',d.version::text,'delivery_digest',digest,'document_number',d.document_number,
  'posted_at',d.posted_at,'company',(select name from core.legal_entities where tenant_id=d.tenant_id and id=d.legal_entity_id),
  'customer',(select display_name from crm.parties where tenant_id=d.tenant_id and id=d.customer_id),
  'lines',(select jsonb_agg(jsonb_build_object('id',l.id,'description',l.description,
   'posted_base_quantity',l.base_quantity::text,'base_unit',u.symbol) order by l.line_number,l.id)
   from sales.delivery_lines l join inventory.products p on p.tenant_id=l.tenant_id and p.id=l.product_id
   join inventory.units u on u.tenant_id=p.tenant_id and u.id=p.base_unit_id where l.document_id=d.id));
 return jsonb_build_object('tenant_id',d.tenant_id,'legal_entity_id',d.legal_entity_id,'branch_id',d.branch_id,
  'customer_id',d.customer_id,'request_id',r.id,'request_version',r.version::text,'source_digest',r.source_digest,
  'delivery_id',d.id,'delivery_version',d.version::text,
  'delivery_digest',digest,'offer',offer);
end $$;
create function field_sales.order_delivery_status(oid uuid) returns text
language plpgsql security definer set search_path='' as $$declare states text[]; begin
 select array_agg(field_sales.delivery_status(d.id)->>'state') into states from sales.deliveries d
 join sales.sales_orders o on o.id=oid and o.tenant_id=d.tenant_id and o.legal_entity_id=d.legal_entity_id
 where d.sales_order_id=oid and d.status='posted';
 if states is null then return 'not_requested'; end if;
 if states&&array['refused','exception'] then return 'attention_required'; end if;
 if states<@array['received'] then return 'acknowledged'; end if;
 return 'awaiting_acknowledgement';
end $$;
create or replace function field_sales.entity(r field_sales.order_requests) returns jsonb
language sql stable set search_path='' as $$
 select jsonb_build_object('id',r.id,'version',r.version::text,'tenant_id',r.tenant_id,
  'legal_entity_id',r.legal_entity_id,'branch_id',r.branch_id,'customer_id',r.customer_id,'rep_id',r.rep_id,
  'input',r.input,'source_digest',r.source_digest,'preview',r.preview-'canonical','company_state',r.state,
  'canonical_order_id',r.canonical_order_id,'canonical_state',(select status from sales.sales_orders where id=r.canonical_order_id),
  'customer_state',field_sales.confirmation_status(r)->>'state','customer_response',field_sales.confirmation_status(r),
  'delivery_state',field_sales.order_delivery_status(r.canonical_order_id),'decision_by',r.decision_by,'decision_reason',r.decision_reason,
  'decided_at',r.decided_at,'created_at',r.created_at)
$$;
create function field_sales.delivery_current(ch field_sales.delivery_challenges,check_expiry boolean default true) returns boolean
language plpgsql security definer set search_path='' as $$declare c field_sales.confirmation_contacts; p field_sales.confirmation_transport; s jsonb; begin
 if ch.id is null or ch.state='revoked' or ch.failures>=5 or ch.acceptance_valid_until<=clock_timestamp()
  or check_expiry and ch.expires_at<=clock_timestamp() then return false; end if;
 select * into p from field_sales.confirmation_transport where tenant_id=ch.tenant_id for share;
 if check_expiry and (not coalesce(p.enabled,false) or p.version<>ch.policy_version) then return false; end if;
 select * into c from field_sales.confirmation_contacts where id=ch.contact_id for share;
 if c.id is null or not c.active or c.valid_until<=clock_timestamp() or c.version<>ch.contact_version
  or c.tenant_id<>ch.tenant_id or c.legal_entity_id<>ch.legal_entity_id or c.branch_id<>ch.branch_id then return false; end if;
 s:=field_sales.delivery_source(ch.delivery_id);
 return s->>'delivery_version'=ch.delivery_version::text and s->>'delivery_digest'=ch.delivery_digest
  and s->>'customer_id'=c.customer_id::text and s->>'request_id'=ch.request_id::text;
 exception when others then return false;
end $$;
create function field_sales.delivery_code_hash(ch field_sales.delivery_challenges,code text) returns text
language sql stable security definer set search_path='' as $$
 select encode(extensions.hmac('delivery:'||ch.id::text||':'||code,encode(p.verification_secret,'hex'),'sha256'),'hex')
 from field_sales.confirmation_transport p where p.tenant_id=ch.tenant_id
$$;
-- Reuse the reviewed hash-only preparation and immutable provider-ack protocol,
-- with a distinct table, current-source check, code domain and private function.
do $copy$ declare definition text; begin
 definition:=pg_get_functiondef('field_sales.confirmation_dispatch(uuid,text,text,text)'::regprocedure);
 if strpos(definition,'field_sales.confirmation_challenges')=0 or strpos(definition,'field_sales.confirmation_current')=0 then
  raise exception 'DISPATCH_CONTRACT_CHANGED'; end if;
 definition:=replace(replace(replace(replace(definition,'confirmation_dispatch','delivery_dispatch'),
  'confirmation_challenges','delivery_challenges'),'confirmation_current','delivery_current'),'confirmation_code_hash','delivery_code_hash');
 definition:=replace(replace(definition,'''order_link''','''delivery_link'''),'''verification_code''','''delivery_code''');
 execute definition;
end $copy$;
create function field_sales.delivery_challenge_entity(ch field_sales.delivery_challenges) returns jsonb
language sql stable set search_path='' as $$
 select jsonb_build_object('id',ch.id,'tenant_id',ch.tenant_id,'legal_entity_id',ch.legal_entity_id,'branch_id',ch.branch_id,
  'delivery_id',ch.delivery_id,'delivery_version',ch.delivery_version::text,'delivery_digest',ch.delivery_digest,
  'request_id',ch.request_id,'contact_id',ch.contact_id,'contact_version',ch.contact_version::text,
  'version',ch.version::text,'state',ch.state,'expires_at',ch.expires_at,'acceptance_valid_until',ch.acceptance_valid_until)
$$;
create function field_sales.delivery_status(did uuid) returns jsonb
language plpgsql security definer set search_path='' as $$declare response field_sales.delivery_responses; s jsonb; begin
 select * into response from field_sales.delivery_responses where delivery_id=did order by responded_at desc,id desc limit 1;
 if response.id is null then return jsonb_build_object('state','not_requested'); end if;
 s:=field_sales.delivery_source(did);
 return jsonb_build_object('state',case when s->>'delivery_digest'=response.delivery_digest then response.response else 'superseded' end,
  'responded_at',response.responded_at,'method',response.method,'quantities',response.quantities);
 exception when others then return jsonb_build_object('state','superseded');
end $$;
create function field_sales.delivery_response_entity(response field_sales.delivery_responses) returns jsonb
language sql stable set search_path='' as $$
 select jsonb_build_object('id',response.id,'delivery_id',response.delivery_id,'delivery_version',response.delivery_version::text,
  'delivery_digest',response.delivery_digest,'quantities',response.quantities,'response',response.response,
  'method',response.method,'responded_at',response.responded_at)
$$;
create function api.field_sales_delivery_command(p_tenant_id uuid,p_legal_entity_id uuid,p_branch_id uuid,
 p_command_id uuid,p_idempotency_key uuid,p_client_timestamp timestamptz,p_action text,p_payload jsonb,p_expected_entity_version bigint default null)
returns jsonb language plpgsql security definer set search_path='' as $$
declare c field_sales.confirmation_contacts; ch field_sales.delivery_challenges; s jsonb; hash text; replay jsonb; before jsonb; tag text; begin
 perform field_sales.require_company(p_tenant_id,p_legal_entity_id,p_branch_id,'sales.field.confirmations.manage');
 if p_client_timestamp is null or p_action not in('issue_delivery','revoke_delivery') or jsonb_typeof(p_payload) is distinct from 'object' then
  raise exception using errcode='22023',message='DELIVERY_COMMAND_INVALID'; end if;
 hash:=core.wave3_request_hash('sales.field.delivery.'||p_action,p_command_id,p_tenant_id,p_legal_entity_id,p_branch_id,p_payload,p_expected_entity_version);
 replay:=core.wave3_replay(p_tenant_id,'sales.field.delivery.'||p_action,p_command_id,p_idempotency_key,hash);
 if replay is not null then return replay; end if;
 if p_action='revoke_delivery' then
  if exists(select 1 from jsonb_object_keys(p_payload) k where k not in('id','reason')) or length(trim(coalesce(p_payload->>'reason',''))) not between 1 and 500 then
   raise exception using errcode='22023',message='REVOCATION_REASON_REQUIRED'; end if;
  select * into ch from field_sales.delivery_challenges where id=(p_payload->>'id')::uuid for update;
  if ch.id is null or ch.tenant_id<>p_tenant_id or ch.legal_entity_id<>p_legal_entity_id or ch.branch_id<>p_branch_id then
   raise exception using errcode='42501',message='DELIVERY_SCOPE_INVALID'; end if;
  before:=field_sales.delivery_challenge_entity(ch);perform core.wave3_assert_expected_version(ch.version,p_expected_entity_version,before);
  update field_sales.delivery_challenges set state='revoked',version=version+1 where id=ch.id returning * into ch;
 else
  if p_expected_entity_version is not null or exists(select 1 from jsonb_object_keys(p_payload) k where k not in('id','delivery_id','delivery_version','delivery_digest','contact_id','contact_version')) then
   raise exception using errcode='22023',message='DELIVERY_FIELDS_INVALID'; end if;
  s:=field_sales.delivery_source((p_payload->>'delivery_id')::uuid);
  if s->>'tenant_id'<>p_tenant_id::text or s->>'legal_entity_id'<>p_legal_entity_id::text or s->>'branch_id'<>p_branch_id::text then
   raise exception using errcode='42501',message='DELIVERY_SCOPE_INVALID'; end if;
  if s->>'delivery_version' is distinct from p_payload->>'delivery_version' or s->>'delivery_digest' is distinct from p_payload->>'delivery_digest' then
   raise exception using errcode='40001',message='DELIVERY_CHANGED'; end if;
  if not field_sales.confirmation_ready(p_tenant_id) then raise exception using errcode='55000',message='CONFIRMATION_PROVIDER_UNAVAILABLE'; end if;
  select * into c from field_sales.confirmation_contacts where id=(p_payload->>'contact_id')::uuid for share;
  if c.id is null or c.tenant_id<>p_tenant_id or c.legal_entity_id<>p_legal_entity_id or c.branch_id<>p_branch_id
   or c.customer_id::text<>s->>'customer_id' or not c.active or c.valid_until<=clock_timestamp() then
   raise exception using errcode='42501',message='CONTACT_NOT_AUTHORIZED'; end if;
  if c.version::text is distinct from p_payload->>'contact_version' then raise exception using errcode='40001',message='CONTACT_CHANGED'; end if;
  perform pg_advisory_xact_lock(hashtextextended('field-delivery:'||(s->>'delivery_id'),0));
  if field_sales.delivery_status((s->>'delivery_id')::uuid)->>'state' in('received','refused','exception') then
   raise exception using errcode='55000',message='DELIVERY_RESPONSE_ALREADY_RECORDED'; end if;
  select encode(extensions.hmac(c.email,encode(p.verification_secret,'hex'),'sha256'),'hex') into tag
   from field_sales.confirmation_transport p where p.tenant_id=p_tenant_id;
  perform pg_advisory_xact_lock(hashtextextended(p_tenant_id::text||tag,0));
  if (select count(*) from (select issued_at from field_sales.confirmation_challenges where tenant_id=p_tenant_id and recipient_tag=tag
   union all select issued_at from field_sales.delivery_challenges where tenant_id=p_tenant_id and recipient_tag=tag) q where issued_at>clock_timestamp()-interval '1 hour')>=5 then
   raise exception using errcode='54000',message='CONFIRMATION_RATE_LIMIT'; end if;
  update field_sales.delivery_challenges set state='revoked',version=version+1 where delivery_id=(s->>'delivery_id')::uuid and state<>'revoked';
  insert into field_sales.delivery_challenges(id,tenant_id,legal_entity_id,branch_id,request_id,request_version,source_digest,
   contact_id,contact_version,delivery_digest,policy_version,recipient_tag,issued_by,issued_at,expires_at,acceptance_valid_until,delivery_id,delivery_version)
  select (p_payload->>'id')::uuid,p_tenant_id,p_legal_entity_id,p_branch_id,(s->>'request_id')::uuid,(s->>'request_version')::bigint,s->>'source_digest',
   c.id,c.version,s->>'delivery_digest',p.version,tag,auth.uid(),clock_timestamp(),clock_timestamp()+interval '15 minutes',
   least(c.valid_until,clock_timestamp()+make_interval(mins=>p.acceptance_minutes)),(s->>'delivery_id')::uuid,(s->>'delivery_version')::bigint
  from field_sales.confirmation_transport p where p.tenant_id=p_tenant_id returning * into ch;
 end if;
 return core.wave3_finish_command(p_tenant_id,'sales.field.delivery.'||p_action,p_command_id,'field_delivery_challenge',ch.id,
  p_idempotency_key,hash,before,field_sales.delivery_challenge_entity(ch),p_legal_entity_id,p_branch_id);
end $$;

create function api.field_sales_delivery_request_code(p_token text) returns jsonb
language plpgsql security definer set search_path='' as $$declare ch field_sales.delivery_challenges; begin
 if not field_sales.confirmation_public_request() or coalesce(p_token,'')!~'^[0-9a-f]{64}$' then return jsonb_build_object('state','unavailable'); end if;
 select * into ch from field_sales.delivery_challenges where token_hash=encode(extensions.digest(p_token,'sha256'),'hex') for update;
 if not field_sales.delivery_current(ch) or ch.state not in('link_accepted','code_requested','code_prepared','code_accepted','verified') then return jsonb_build_object('state','unavailable'); end if;
 if ch.state='link_accepted' then update field_sales.delivery_challenges set state='code_requested' where id=ch.id; end if;
 return jsonb_build_object('state','check_email');
end $$;
create function api.field_sales_delivery_verify(p_token text,p_code text) returns jsonb
language plpgsql security definer set search_path='' as $$declare ch field_sales.delivery_challenges; offer jsonb; proof text; secret bytea; begin
 if not field_sales.confirmation_public_request() or coalesce(p_token,'')!~'^[0-9a-f]{64}$' then return jsonb_build_object('state','unavailable'); end if;
 select * into ch from field_sales.delivery_challenges where token_hash=encode(extensions.digest(p_token,'sha256'),'hex') for update;
 if not field_sales.delivery_current(ch) or ch.state not in('code_accepted','verified','responded') then return jsonb_build_object('state','unavailable'); end if;
 if ch.code_hash is distinct from field_sales.delivery_code_hash(ch,p_code) or coalesce(p_code,'')!~'^[0-9]{6}$' then
  if ch.state<>'responded' then update field_sales.delivery_challenges set failures=failures+1 where id=ch.id; end if;
  return jsonb_build_object('state','unavailable'); end if;
 if ch.state='responded' then return jsonb_build_object('state','already_recorded'); end if;
 offer:=field_sales.delivery_source(ch.delivery_id)->'offer';
 select verification_secret into secret from field_sales.confirmation_transport where tenant_id=ch.tenant_id;
 ch.offer_hash:=encode(extensions.digest(offer::text,'sha256'),'hex');
 proof:=encode(extensions.hmac('delivery-response:'||ch.id::text||':'||ch.code_hash||':'||ch.offer_hash,encode(secret,'hex'),'sha256'),'hex');
 update field_sales.delivery_challenges set state='verified',proof_hash=encode(extensions.digest(proof,'sha256'),'hex'),offer_hash=ch.offer_hash where id=ch.id;
 return jsonb_build_object('state','review','proof',proof,'offer',offer);
end $$;
create function api.field_sales_delivery_respond(p_token text,p_proof text,p_quantities jsonb,p_reason text,p_authorized boolean) returns jsonb
language plpgsql security definer set search_path='' as $$
declare ch field_sales.delivery_challenges; prior field_sales.delivery_responses; offer jsonb; line jsonb; item jsonb;
 quantities jsonb:='[]'; received numeric; refused numeric; short numeric; all_received boolean:=true; all_refused boolean:=true; outcome text; begin
 if not field_sales.confirmation_public_request() or coalesce(p_token,'')!~'^[0-9a-f]{64}$' or coalesce(p_proof,'')!~'^[0-9a-f]{64}$' then return jsonb_build_object('state','unavailable'); end if;
 select * into ch from field_sales.delivery_challenges where token_hash=encode(extensions.digest(p_token,'sha256'),'hex') for update;
 if ch.id is null or ch.proof_hash is distinct from encode(extensions.digest(p_proof,'sha256'),'hex') then return jsonb_build_object('state','unavailable'); end if;
 if p_authorized is distinct from true or length(coalesce(p_reason,''))>500 or jsonb_typeof(p_quantities) is distinct from 'array' then
  return jsonb_build_object('state','review_required'); end if;
 select * into prior from field_sales.delivery_responses where challenge_id=ch.id;
 if prior.id is not null then
  if prior.quantities=p_quantities and prior.reason=trim(coalesce(p_reason,'')) then return field_sales.delivery_response_entity(prior)||jsonb_build_object('state','recorded'); end if;
  return jsonb_build_object('state','already_recorded');
 end if;
 if ch.state<>'verified' or not field_sales.delivery_current(ch) then return jsonb_build_object('state','unavailable'); end if;
 offer:=field_sales.delivery_source(ch.delivery_id)->'offer';
 if encode(extensions.digest(offer::text,'sha256'),'hex')<>ch.offer_hash then return jsonb_build_object('state','review_required'); end if;
 if jsonb_array_length(p_quantities)<>jsonb_array_length(offer->'lines') or exists(select 1 from jsonb_array_elements(p_quantities) x group by x->>'id' having count(*)>1) then
  return jsonb_build_object('state','quantities_invalid'); end if;
 if exists(select 1 from jsonb_array_elements(p_quantities) x where jsonb_typeof(x)<>'object') then return jsonb_build_object('state','quantities_invalid'); end if;
 for line in select value from jsonb_array_elements(offer->'lines') loop
  select value into item from jsonb_array_elements(p_quantities) where value->>'id'=line->>'id';
  if item is null or exists(select 1 from jsonb_object_keys(item) k where k not in('id','received','refused','short')) then return jsonb_build_object('state','quantities_invalid'); end if;
  begin
   received:=sales.wave3_decimal_string(item->'received','Received',6,true,0,null);
   refused:=sales.wave3_decimal_string(item->'refused','Refused',6,true,0,null);
   short:=sales.wave3_decimal_string(item->'short','Short',6,true,0,null);
  exception when others then return jsonb_build_object('state','quantities_invalid'); end;
  if received+refused+short<>(line->>'posted_base_quantity')::numeric then return jsonb_build_object('state','quantities_invalid'); end if;
  all_received:=all_received and received=(line->>'posted_base_quantity')::numeric;
  all_refused:=all_refused and refused=(line->>'posted_base_quantity')::numeric;
 end loop;
 if not all_received and length(trim(coalesce(p_reason,'')))=0 then return jsonb_build_object('state','review_required'); end if;
 outcome:=case when all_received then 'received' when all_refused then 'refused' else 'exception' end;
 insert into field_sales.delivery_responses(challenge_id,tenant_id,legal_entity_id,branch_id,request_id,delivery_id,delivery_version,delivery_digest,
  contact_snapshot,offer_snapshot,quantities,response,reason)
 values(ch.id,ch.tenant_id,ch.legal_entity_id,ch.branch_id,ch.request_id,ch.delivery_id,ch.delivery_version,ch.delivery_digest,
  (select field_sales.confirmation_contact_entity(c) from field_sales.confirmation_contacts c where c.id=ch.contact_id),offer,p_quantities,outcome,trim(coalesce(p_reason,''))) returning * into prior;
 update field_sales.delivery_challenges set state='responded' where id=ch.id;
 return field_sales.delivery_response_entity(prior)||jsonb_build_object('state','recorded');
end $$;

-- The existing order command takes the same recipient advisory lock. Share its
-- hourly budget with delivery requests, instead of creating a second allowance.
do $rate$ declare definition text; old_fragment text; new_fragment text; begin
 definition:=replace(pg_get_functiondef('api.field_sales_confirmation_command(uuid,uuid,uuid,uuid,uuid,timestamptz,text,jsonb,bigint)'::regprocedure),E'\r\n',E'\n');
 old_fragment:=E'select count(*) from field_sales.confirmation_challenges where tenant_id=p_tenant_id\n   and recipient_tag=context->>''recipient_tag'' and issued_at>clock_timestamp()-interval ''1 hour''';
 new_fragment:=E'select count(*) from (select issued_at from field_sales.confirmation_challenges where tenant_id=p_tenant_id and recipient_tag=context->>''recipient_tag'' union all select issued_at from field_sales.delivery_challenges where tenant_id=p_tenant_id and recipient_tag=context->>''recipient_tag'') shared where issued_at>clock_timestamp()-interval ''1 hour''';
 if strpos(definition,old_fragment)=0 then raise exception 'RECIPIENT_RATE_CONTRACT_CHANGED'; end if;
 execute replace(definition,old_fragment,new_fragment);
end $rate$;

create function api.field_sales_delivery_subjects(p_tenant_id uuid,p_legal_entity_id uuid,p_branch_id uuid,p_after uuid default null,p_limit integer default 50) returns jsonb
language plpgsql security definer set search_path='' as $$declare items jsonb; begin
 perform field_sales.require_company(p_tenant_id,p_legal_entity_id,p_branch_id,'sales.field.confirmations.manage');
 if p_limit is null or p_limit not between 1 and 200 then raise exception using errcode='22023',message='PAGE_INVALID'; end if;
 select coalesce(jsonb_agg(x.item order by x.id),'[]') into items from (
  select d.id,field_sales.delivery_source(d.id)||jsonb_build_object('id',d.id,'version',d.version::text,
   'customer_name',c.display_name,'company_state','posted','delivery_state',field_sales.delivery_status(d.id)->>'state') item
  from sales.deliveries d join field_sales.order_progressions p on p.order_id=d.sales_order_id
  join crm.parties c on c.tenant_id=d.tenant_id and c.id=d.customer_id
  where d.tenant_id=p_tenant_id and d.legal_entity_id=p_legal_entity_id and d.branch_id=p_branch_id and d.status='posted'
   and (p_after is null or d.id>p_after) order by d.id limit p_limit+1) x;
 return jsonb_build_object('provider_state',case when field_sales.confirmation_ready(p_tenant_id) then 'configured' else 'unavailable' end,
  'items',(select coalesce(jsonb_agg(value order by ordinality),'[]') from jsonb_array_elements(items) with ordinality where ordinality<=p_limit),
  'next_cursor',case when jsonb_array_length(items)>p_limit then items->(p_limit-1)->>'id' end);
end $$;
create function api.field_sales_delivery_challenges(p_tenant_id uuid,p_legal_entity_id uuid,p_branch_id uuid,p_request_id uuid,p_after uuid default null,p_limit integer default 50) returns jsonb
language plpgsql security definer set search_path='' as $$declare items jsonb; begin
 perform field_sales.require_company(p_tenant_id,p_legal_entity_id,p_branch_id,'sales.field.confirmations.manage');
 if p_limit is null or p_limit not between 1 and 200 then raise exception using errcode='22023',message='PAGE_INVALID'; end if;
 if not exists(select 1 from sales.deliveries where id=p_request_id and tenant_id=p_tenant_id and legal_entity_id=p_legal_entity_id and branch_id=p_branch_id) then
  raise exception using errcode='42501',message='DELIVERY_SCOPE_INVALID'; end if;
 select coalesce(jsonb_agg(x.item order by x.id),'[]') into items from (
  select ch.id,field_sales.delivery_challenge_entity(ch)||jsonb_build_object('recipient_name',c.name,
   'effective_state',case when ch.state='revoked' then 'revoked' when ch.state='responded' then field_sales.delivery_status(ch.delivery_id)->>'state'
    when not field_sales.delivery_current(ch) then 'superseded' else ch.state end) item
  from field_sales.delivery_challenges ch join field_sales.confirmation_contacts c on c.id=ch.contact_id
  where ch.delivery_id=p_request_id and ch.tenant_id=p_tenant_id and ch.legal_entity_id=p_legal_entity_id and ch.branch_id=p_branch_id
   and (p_after is null or ch.id>p_after) order by ch.id limit p_limit+1) x;
 return jsonb_build_object('items',(select coalesce(jsonb_agg(value order by ordinality),'[]') from jsonb_array_elements(items) with ordinality where ordinality<=p_limit),
  'next_cursor',case when jsonb_array_length(items)>p_limit then items->(p_limit-1)->>'id' end);
end $$;
create function api.field_sales_delivery_receipt(p_tenant_id uuid,p_legal_entity_id uuid,p_branch_id uuid,p_idempotency_key uuid) returns jsonb
language plpgsql security definer set search_path='' as $$declare receipt core.command_receipts; entity jsonb; begin
 perform field_sales.require_company(p_tenant_id,p_legal_entity_id,p_branch_id,'sales.field.confirmations.manage');
 select * into receipt from core.command_receipts where tenant_id=p_tenant_id and actor_id=auth.uid() and idempotency_key=p_idempotency_key
  and command_name in('sales.field.delivery.issue_delivery','sales.field.delivery.revoke_delivery');
 if receipt.id is null then return jsonb_build_object('state','not_found'); end if;
 entity:=receipt.response->'entity';
 if entity->>'tenant_id'<>p_tenant_id::text or entity->>'legal_entity_id'<>p_legal_entity_id::text or entity->>'branch_id'<>p_branch_id::text then
  raise exception using errcode='42501',message='RECEIPT_SCOPE_INVALID'; end if;
 return jsonb_build_object('state','committed','receipt',receipt.response);
end $$;

alter function field_sales.mail_current(uuid,text) rename to mail_current_before_delivery;
create function field_sales.mail_current(id uuid,kind text) returns boolean
language plpgsql security definer set search_path='' as $$declare ch field_sales.delivery_challenges; begin
 if kind in('delivery_link','delivery_code') then
  select * into ch from field_sales.delivery_challenges where delivery_challenges.id=mail_current.id;
  return field_sales.delivery_current(ch);
 end if;return field_sales.mail_current_before_delivery(id,kind);
end $$;
alter function field_sales.mail_dispatch(uuid,text,text,text,text) rename to mail_dispatch_before_delivery;
create function field_sales.mail_dispatch(id uuid,kind text,step text,secret text,reference text default null) returns jsonb
language plpgsql security definer set search_path='' as $$begin
 if kind in('delivery_link','delivery_code') then return field_sales.delivery_dispatch(id,step,secret,reference); end if;
 return field_sales.mail_dispatch_before_delivery(id,kind,step,secret,reference);
end $$;
alter function field_sales.mail_sources(uuid[]) rename to mail_sources_before_delivery;
create function field_sales.mail_sources(ids uuid[]) returns table(tenant_id uuid,challenge_id uuid,kind text,snapshot jsonb,issued_at timestamptz)
language sql security definer set search_path='' as $$
 select * from field_sales.mail_sources_before_delivery(ids)
 union all
 select ch.tenant_id,ch.id,case when ch.state='queued_link' then 'delivery_link' else 'delivery_code' end,
  jsonb_build_object('template','v1','provider',p.provider,'credential_alias',p.credential_alias,
   'key_version',p.key_version,'secret_key_sha256',p.secret_key_sha256,'sender',p.sender_email,'origin',p.confirmation_origin,
   'recipient',c.email,'organization',e.name,'expires_at',ch.expires_at,'policy_version',p.version::text,
   'domain_evidence_sha256',p.domain_evidence_sha256),ch.issued_at
 from field_sales.delivery_challenges ch join field_sales.mail_policies p on p.tenant_id=ch.tenant_id and p.enabled
 join field_sales.confirmation_contacts c on c.id=ch.contact_id
 join core.legal_entities e on e.tenant_id=ch.tenant_id and e.id=ch.legal_entity_id
 where ch.tenant_id=any(ids) and ch.state in('queued_link','code_requested') and field_sales.delivery_current(ch)
  and ch.expires_at>clock_timestamp()+interval '30 seconds'
$$;
-- No private helper, raw challenge, contact snapshot or worker operation is public.
do $acl$ declare v_proc record; begin
 for v_proc in select proc.oid::regprocedure signature from pg_proc proc join pg_namespace n on n.oid=proc.pronamespace
  where n.nspname='field_sales' and (proc.proname like 'delivery_%' or proc.proname like 'mail_%') loop
  execute format('revoke all on function %s from public,anon,authenticated,service_role',v_proc.signature);
 end loop;
end $acl$;
revoke all on function field_sales.order_delivery_status(uuid) from public,anon,authenticated,service_role;
revoke all on function api.field_sales_delivery_command(uuid,uuid,uuid,uuid,uuid,timestamptz,text,jsonb,bigint),
 api.field_sales_delivery_subjects(uuid,uuid,uuid,uuid,integer),api.field_sales_delivery_challenges(uuid,uuid,uuid,uuid,uuid,integer),
 api.field_sales_delivery_receipt(uuid,uuid,uuid,uuid) from public,anon,service_role;
grant execute on function api.field_sales_delivery_command(uuid,uuid,uuid,uuid,uuid,timestamptz,text,jsonb,bigint),
 api.field_sales_delivery_subjects(uuid,uuid,uuid,uuid,integer),api.field_sales_delivery_challenges(uuid,uuid,uuid,uuid,uuid,integer),
 api.field_sales_delivery_receipt(uuid,uuid,uuid,uuid) to authenticated;
revoke all on function api.field_sales_delivery_request_code(text),api.field_sales_delivery_verify(text,text),
 api.field_sales_delivery_respond(text,text,jsonb,text,boolean) from public,authenticated,service_role;
grant execute on function api.field_sales_delivery_request_code(text),api.field_sales_delivery_verify(text,text),
 api.field_sales_delivery_respond(text,text,jsonb,text,boolean) to anon;
