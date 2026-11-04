-- CANDIDATE ONLY. Compose after the company confirmation candidate.
-- No policy is inserted or enabled. Provider credentials stay in server secrets.
create table field_sales.mail_policies (
 tenant_id uuid primary key references core.tenants(id), enabled boolean not null default false,
 version bigint not null default 1 check(version>0), provider text not null check(provider='resend'),
 credential_alias text not null check(credential_alias ~ '^[a-z][a-z0-9_]{0,39}$'),
 key_version text not null check(key_version ~ '^[a-z0-9_]{1,40}$'),
 secret_key_sha256 text not null check(secret_key_sha256 ~ '^[0-9a-f]{64}$'),
 sender_email text not null check(sender_email ~ '^[a-zA-Z0-9.!#$%&''*+/=?^_`{|}~-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$'),
 confirmation_origin text not null check(confirmation_origin='https://jentra-os-sales.web.app'),
 domain_evidence_sha256 text not null check(domain_evidence_sha256 ~ '^[0-9a-f]{64}$'),
 reviewed_by uuid not null references auth.users(id), reviewed_at timestamptz not null default clock_timestamp()
);
alter table field_sales.mail_policies enable row level security;
create table field_sales.mail_jobs (
 id uuid primary key default gen_random_uuid(), tenant_id uuid not null references core.tenants(id),
 challenge_id uuid not null,
 kind text not null check(kind in('order_link','order_code','delivery_link','delivery_code')),
 state text not null default 'ready' check(state in('ready','leased','sending','accepted','uncertain','failed','cancelled')),
 snapshot jsonb not null, attempts integer not null default 0 check(attempts between 0 and 5),
 lease_id uuid, lease_until timestamptz, provider_reference text,
 created_at timestamptz not null default clock_timestamp(), accepted_at timestamptz,
 unique(challenge_id,kind), check(provider_reference is null or length(provider_reference) between 1 and 200)
);
alter table field_sales.mail_jobs enable row level security;
create index field_mail_pending on field_sales.mail_jobs(tenant_id,state,created_at,id);

create function field_sales.mail_current(id uuid,kind text) returns boolean
language plpgsql security definer set search_path='' as $$declare ch field_sales.confirmation_challenges; begin
 if kind not in('order_link','order_code') then return false; end if;
 select * into ch from field_sales.confirmation_challenges where confirmation_challenges.id=mail_current.id;
 return field_sales.confirmation_current(ch);
end $$;
create function field_sales.mail_dispatch(id uuid,kind text,step text,secret text,reference text default null) returns jsonb
language plpgsql security definer set search_path='' as $$begin
 if kind not in('order_link','order_code') then raise exception using errcode='22023',message='MAIL_PURPOSE_INVALID'; end if;
 return field_sales.confirmation_dispatch(id,step,secret,reference);
end $$;
create function field_sales.mail_sources(ids uuid[]) returns table(tenant_id uuid,challenge_id uuid,kind text,snapshot jsonb,issued_at timestamptz)
language sql security definer set search_path='' as $$
 select ch.tenant_id,ch.id,case when ch.state='queued_link' then 'order_link' else 'order_code' end,
  jsonb_build_object('template','v1','provider',p.provider,'credential_alias',p.credential_alias,
   'key_version',p.key_version,'secret_key_sha256',p.secret_key_sha256,'sender',p.sender_email,'origin',p.confirmation_origin,
   'recipient',c.email,'organization',e.name,'expires_at',ch.expires_at,
   'policy_version',p.version::text,'domain_evidence_sha256',p.domain_evidence_sha256),ch.issued_at
 from field_sales.confirmation_challenges ch
 join field_sales.mail_policies p on p.tenant_id=ch.tenant_id and p.enabled
 join field_sales.confirmation_contacts c on c.id=ch.contact_id
 join core.legal_entities e on e.tenant_id=ch.tenant_id and e.id=ch.legal_entity_id
 where ch.tenant_id=any(ids) and ch.state in('queued_link','code_requested')
  and field_sales.confirmation_current(ch) and ch.expires_at>clock_timestamp()+interval '30 seconds'
$$;

-- A dedicated API-schema facade is service-only. Private schema exposure is not
-- needed by the worker, and browsers cannot choose a recipient or template.
create or replace function field_sales.confirmation_ready(t uuid) returns boolean
language sql stable security definer set search_path='' as $$
 select coalesce((select p.enabled and m.enabled from field_sales.confirmation_transport p
  join field_sales.mail_policies m on m.tenant_id=p.tenant_id where p.tenant_id=t),false)
$$;

create function api.field_sales_mail_claim(p_tenant_ids uuid[],p_lease_id uuid) returns jsonb
language plpgsql security definer set search_path='' as $$
declare j field_sales.mail_jobs; begin
 if p_lease_id is null or coalesce(cardinality(p_tenant_ids),0) not between 1 and 100 then
  raise exception using errcode='22023',message='MAIL_SCOPE_INVALID'; end if;
 insert into field_sales.mail_jobs(tenant_id,challenge_id,kind,snapshot)
 select s.tenant_id,s.challenge_id,s.kind,s.snapshot from field_sales.mail_sources(p_tenant_ids) s
 order by s.issued_at,s.challenge_id limit 50 on conflict(challenge_id,kind) do nothing;
 select q.* into j from field_sales.mail_jobs q
 join field_sales.mail_policies p on p.tenant_id=q.tenant_id and p.enabled
 where q.tenant_id=any(p_tenant_ids) and q.attempts<5
  and (q.state='ready' or q.state in('leased','sending') and q.lease_until<clock_timestamp())
  and field_sales.mail_current(q.challenge_id,q.kind) and (q.snapshot->>'expires_at')::timestamptz>clock_timestamp()+interval '30 seconds'
 order by q.created_at,q.id for update of q skip locked limit 1;
 if j.id is null then return jsonb_build_object('state','idle'); end if;
 update field_sales.mail_jobs set state='leased',lease_id=p_lease_id,
  lease_until=clock_timestamp()+interval '60 seconds',attempts=attempts+1 where id=j.id returning * into j;
 return jsonb_build_object('state','claimed','id',j.id,'tenant_id',j.tenant_id,
  'challenge_id',j.challenge_id,'kind',j.kind,'snapshot',j.snapshot);
end $$;

create function api.field_sales_mail_step(p_tenant_id uuid,p_job_id uuid,p_lease_id uuid,
 p_action text,p_secret text default null,p_provider_reference text default null) returns jsonb
language plpgsql security definer set search_path='' as $$
declare j field_sales.mail_jobs; receipt jsonb; begin
 select * into j from field_sales.mail_jobs where id=p_job_id and tenant_id=p_tenant_id for update;
 if j.id is null or j.lease_id is distinct from p_lease_id or j.lease_until<=clock_timestamp()
  or j.state not in('leased','sending') then raise exception using errcode='42501',message='MAIL_LEASE_INVALID'; end if;
 if p_action='defer' then
  update field_sales.mail_jobs set state=case when attempts>=5 then 'failed' else 'ready' end,
   lease_id=null,lease_until=null where id=j.id;
  return jsonb_build_object('state','deferred');
 end if;
 if not exists(select 1 from field_sales.mail_policies where tenant_id=p_tenant_id and enabled) then
  raise exception using errcode='55000',message='MAIL_DISABLED'; end if;
 if not field_sales.mail_current(j.challenge_id,j.kind) or (j.snapshot->>'expires_at')::timestamptz<=clock_timestamp()+interval '5 seconds' then
  raise exception using errcode='55000',message='MAIL_SOURCE_CHANGED'; end if;
 if p_action='prepare' and j.state='leased' then
  receipt:=field_sales.mail_dispatch(j.challenge_id,j.kind,case when j.kind in('order_link','delivery_link') then 'prepare_link' else 'prepare_code' end,p_secret);
  if receipt->>'recipient' is distinct from j.snapshot->>'recipient' then
   raise exception using errcode='55000',message='MAIL_RECIPIENT_CHANGED'; end if;
  update field_sales.mail_jobs set state='sending' where id=j.id;
  return jsonb_build_object('state','prepared');
 elsif p_action='ack' and j.state='sending' then
  receipt:=field_sales.mail_dispatch(j.challenge_id,j.kind,case when j.kind in('order_link','delivery_link') then 'ack_link' else 'ack_code' end,p_secret,p_provider_reference);
  update field_sales.mail_jobs set state='accepted',provider_reference=p_provider_reference,accepted_at=clock_timestamp()
   where id=j.id;
  return jsonb_build_object('state','provider_accepted','delivery','not_established');
 end if;
 raise exception using errcode='22023',message='MAIL_STEP_INVALID';
end $$;
revoke all on function api.field_sales_mail_claim(uuid[],uuid),
 api.field_sales_mail_step(uuid,uuid,uuid,text,text,text) from public,anon,authenticated;
grant execute on function api.field_sales_mail_claim(uuid[],uuid),
 api.field_sales_mail_step(uuid,uuid,uuid,text,text,text) to service_role;
revoke all on function field_sales.mail_current(uuid,text),field_sales.mail_dispatch(uuid,text,text,text,text),
 field_sales.mail_sources(uuid[]) from public,anon,authenticated,service_role;
