-- W4-02B synthetic private HR. Unapplied candidate; no role/plan grants.
create schema people_private;
revoke all on schema people_private from public,anon,authenticated,service_role;
grant usage on schema api to service_role;

insert into core.permissions(code,description,module,privileged)
values
 ('people.hr.private.view','Read private contact','people',false),
 ('people.hr.private.manage','Manage private contact with MFA','people',true),
 ('people.hr.documents.view','Read private HR documents','people',false),
 ('people.hr.documents.manage','Manage private HR documents with MFA','people',true),
 ('people.reviews.view','Read restricted reviews','people',false),
 ('people.reviews.manage','Manage restricted reviews with MFA','people',true),
 ('people.hr.retention.manage','Manage synthetic retention with MFA','people',true),
 ('people.hr.export','Export private HR content with MFA','people',true),
 ('people.hr.erase','Request private HR erasure with MFA','people',true),
 ('people.account_links.manage','Manage exact employee account links with MFA','people',true),
 ('people.self.view','Read linked employee self projection','people',false);

create table people_private.policies(
 id uuid primary key,tenant_id uuid not null,legal_entity_id uuid not null,
 version bigint not null default 1 check(version>0),purpose text not null check(length(purpose) between 1 and 160),
 contract text not null default 'w4-private-hr-v1' check(contract='w4-private-hr-v1'),
 retention_days integer not null default 30 check(retention_days=30),
 closed_at timestamptz,hold_reason text,hold_review_date date,
 digest_key bytea not null default extensions.gen_random_bytes(32) check(octet_length(digest_key)=32),
 created_by uuid not null references auth.users(id),created_at timestamptz not null default clock_timestamp(),
 unique(tenant_id,legal_entity_id),unique(tenant_id,legal_entity_id,id),
 foreign key(tenant_id,legal_entity_id) references core.legal_entities(tenant_id,id),
 check((hold_reason is null and hold_review_date is null) or
       (length(hold_reason) between 1 and 1000 and hold_review_date is not null))
);
create table people_private.policy_events(
 id uuid primary key default gen_random_uuid(),tenant_id uuid not null,legal_entity_id uuid not null,
 policy_id uuid not null,version bigint not null,event_type text not null,
 reason text,recorded_by uuid not null references auth.users(id),recorded_at timestamptz not null default clock_timestamp(),
 foreign key(tenant_id,legal_entity_id,policy_id) references people_private.policies(tenant_id,legal_entity_id,id)
);
create index on people_private.policy_events(tenant_id,legal_entity_id,policy_id,id);
create table people_private.worker_readiness(
 contract text primary key check(contract='w4-private-hr-v1'),
 artifact_digest text not null check(artifact_digest ~ '^[a-f0-9]{64}$'),
 storage_probe_digest text not null check(storage_probe_digest ~ '^[a-f0-9]{64}$'),
 verified_at timestamptz not null default clock_timestamp()
);
create table people_private.profiles(
 employee_id uuid primary key,tenant_id uuid not null,legal_entity_id uuid not null,branch_id uuid not null,
 policy_id uuid not null,version bigint not null check(version>0),revision_id uuid not null,
 erased_at timestamptz,
 unique(tenant_id,legal_entity_id,employee_id),
 foreign key(tenant_id,legal_entity_id,employee_id) references people.employees(tenant_id,legal_entity_id,id),
 foreign key(tenant_id,legal_entity_id,branch_id) references core.branches(tenant_id,legal_entity_id,id),
 foreign key(tenant_id,legal_entity_id,policy_id) references people_private.policies(tenant_id,legal_entity_id,id)
);
create index on people_private.profiles(tenant_id,branch_id,employee_id);
create index on people_private.profiles(tenant_id,legal_entity_id,policy_id);
create table people_private.profile_revisions(
 id uuid primary key,tenant_id uuid not null,legal_entity_id uuid not null,employee_id uuid not null,
 version bigint not null,body jsonb,reason text,digest text not null check(digest ~ '^[a-f0-9]{64}$'),
 recorded_by uuid not null references auth.users(id),recorded_at timestamptz not null default clock_timestamp(),
 redacted_at timestamptz,unique(tenant_id,legal_entity_id,employee_id,version),
 foreign key(tenant_id,legal_entity_id,employee_id) references people_private.profiles(tenant_id,legal_entity_id,employee_id)
);
create index on people_private.profile_revisions(tenant_id,legal_entity_id,employee_id,id);
create table people_private.documents(
 id uuid primary key,tenant_id uuid not null,legal_entity_id uuid not null,branch_id uuid not null,
 employee_id uuid not null,policy_id uuid not null,version bigint not null default 1 check(version>0),
 classification text not null check(classification in ('contact-support','review-evidence')),
 purpose text, mime text not null check(mime in ('text/plain','image/png','image/jpeg','application/pdf')),
 byte_size integer not null check(byte_size between 1 and 10485760),
 checksum text not null check(checksum ~ '^[a-f0-9]{64}$'),object_path text,
 status text not null default 'reserved' check(status in ('reserved','verified','active','erasing','erased')),
 created_by uuid not null references auth.users(id),created_at timestamptz not null default clock_timestamp(),
 verified_at timestamptz,erased_at timestamptz,
 unique(tenant_id,legal_entity_id,employee_id,id),
 foreign key(tenant_id,legal_entity_id,employee_id) references people.employees(tenant_id,legal_entity_id,id),
 foreign key(tenant_id,legal_entity_id,branch_id) references core.branches(tenant_id,legal_entity_id,id),
 foreign key(tenant_id,legal_entity_id,policy_id) references people_private.policies(tenant_id,legal_entity_id,id)
);
create index on people_private.documents(tenant_id,legal_entity_id,employee_id,id);
create index on people_private.documents(tenant_id,branch_id,id);
create index on people_private.documents(tenant_id,legal_entity_id,policy_id);
create table people_private.reviews(
 id uuid primary key,tenant_id uuid not null,legal_entity_id uuid not null,branch_id uuid not null,
 employee_id uuid not null,reviewer_id uuid not null,policy_id uuid not null,
 version bigint not null default 1 check(version>0),revision_id uuid not null,
 status text not null check(status in ('draft','submitted','reviewed','acknowledged','closed','erased')),
 start_date date not null,end_date_exclusive date not null,
 created_by uuid not null references auth.users(id),erased_at timestamptz,
 unique(tenant_id,legal_entity_id,employee_id,id),
 foreign key(tenant_id,legal_entity_id,employee_id) references people.employees(tenant_id,legal_entity_id,id),
 foreign key(tenant_id,legal_entity_id,reviewer_id) references people.employees(tenant_id,legal_entity_id,id),
 foreign key(tenant_id,legal_entity_id,branch_id) references core.branches(tenant_id,legal_entity_id,id),
 foreign key(tenant_id,legal_entity_id,policy_id) references people_private.policies(tenant_id,legal_entity_id,id),
 check(employee_id<>reviewer_id and end_date_exclusive>start_date and end_date_exclusive-start_date<=366)
);
create index on people_private.reviews(tenant_id,legal_entity_id,reviewer_id);
create index on people_private.reviews(tenant_id,branch_id,employee_id,id);
create index on people_private.reviews(tenant_id,legal_entity_id,policy_id);
create table people_private.review_revisions(
 id uuid primary key,tenant_id uuid not null,legal_entity_id uuid not null,employee_id uuid not null,
 review_id uuid not null,body jsonb,reason text,digest text not null check(digest ~ '^[a-f0-9]{64}$'),
 recorded_by uuid not null references auth.users(id),recorded_at timestamptz not null default clock_timestamp(),
 redacted_at timestamptz,
 foreign key(tenant_id,legal_entity_id,employee_id,review_id)
 references people_private.reviews(tenant_id,legal_entity_id,employee_id,id)
);
create index on people_private.review_revisions(tenant_id,legal_entity_id,employee_id,review_id,id);
create table people_private.review_events(
 id uuid primary key default gen_random_uuid(),tenant_id uuid not null,legal_entity_id uuid not null,
 employee_id uuid not null,review_id uuid not null,revision_id uuid not null,event_type text not null,
 private_text text,digest text not null check(digest ~ '^[a-f0-9]{64}$'),
 recorded_by uuid not null references auth.users(id),recorded_at timestamptz not null default clock_timestamp(),
 redacted_at timestamptz,
 foreign key(tenant_id,legal_entity_id,employee_id,review_id)
 references people_private.reviews(tenant_id,legal_entity_id,employee_id,id),
 foreign key(revision_id) references people_private.review_revisions(id)
);
create index on people_private.review_events(tenant_id,legal_entity_id,employee_id,review_id,id);
create index on people_private.review_events(revision_id);
create table people_private.account_links(
 id uuid primary key,tenant_id uuid not null,legal_entity_id uuid not null,branch_id uuid not null,
 employee_id uuid not null,membership_id uuid not null,user_id uuid not null references auth.users(id),
 version bigint not null default 1 check(version>0),
 status text not null default 'pending' check(status in ('pending','accepted','rejected','expired','revoked')),
 initiated_by uuid not null references auth.users(id),initiated_at timestamptz not null default clock_timestamp(),
 expires_at timestamptz not null default (clock_timestamp()+interval '24 hours'),accepted_at timestamptz,
 unique(tenant_id,legal_entity_id,employee_id,id),
 foreign key(tenant_id,legal_entity_id,employee_id) references people.employees(tenant_id,legal_entity_id,id),
 foreign key(tenant_id,legal_entity_id,branch_id) references core.branches(tenant_id,legal_entity_id,id),
 foreign key(tenant_id,membership_id) references core.memberships(tenant_id,id),
 foreign key(tenant_id,user_id) references core.memberships(tenant_id,user_id)
);
create unique index on people_private.account_links(tenant_id,employee_id) where status in ('pending','accepted');
create unique index on people_private.account_links(tenant_id,user_id) where status in ('pending','accepted');
create index on people_private.account_links(tenant_id,legal_entity_id,employee_id,id);
create index on people_private.account_links(tenant_id,branch_id,id);
create index on people_private.account_links(tenant_id,membership_id);
create table people_private.link_events(
 id uuid primary key default gen_random_uuid(),tenant_id uuid not null,legal_entity_id uuid not null,
 employee_id uuid not null,link_id uuid not null,event_type text not null,
 recorded_by uuid references auth.users(id),actor_kind text not null check(actor_kind in ('user','system')),
 recorded_at timestamptz not null default clock_timestamp(),
 foreign key(tenant_id,legal_entity_id,employee_id,link_id)
 references people_private.account_links(tenant_id,legal_entity_id,employee_id,id),
 check((actor_kind='user')=(recorded_by is not null))
);
create index on people_private.link_events(tenant_id,legal_entity_id,employee_id,link_id,id);
create table people_private.purge_jobs(
 id uuid primary key default gen_random_uuid(),tenant_id uuid not null,legal_entity_id uuid not null,
 employee_id uuid not null,requested_by uuid references auth.users(id),
 requested_at timestamptz not null default clock_timestamp(),lease_id uuid,lease_until timestamptz,
 status text not null default 'pending' check(status in ('pending','leased','complete')),
 completed_at timestamptz,unique(tenant_id,legal_entity_id,employee_id),
 foreign key(tenant_id,legal_entity_id,employee_id) references people.employees(tenant_id,legal_entity_id,id)
);
create index on people_private.purge_jobs(status,lease_until,id);
create table people_private.erasure_events(
 id uuid primary key default gen_random_uuid(),tenant_id uuid not null,legal_entity_id uuid not null,
 employee_id uuid not null,job_id uuid not null references people_private.purge_jobs(id),
 actor_kind text not null default 'system' check(actor_kind='system'),requested_by uuid references auth.users(id),
 recorded_at timestamptz not null default clock_timestamp(),contract text not null,
 profile_revisions integer not null,review_revisions integer not null,documents integer not null,
 unique(job_id),
 foreign key(tenant_id,legal_entity_id,employee_id) references people.employees(tenant_id,legal_entity_id,id)
);
create index on people_private.erasure_events(tenant_id,legal_entity_id,employee_id,id);
create table people_private.document_tickets(
 id uuid primary key default gen_random_uuid(),tenant_id uuid not null,legal_entity_id uuid not null,
 branch_id uuid not null,employee_id uuid not null,document_id uuid not null,user_id uuid not null references auth.users(id),
 operation text not null check(operation in ('upload','download','export')),
 issued_aal text not null,expires_at timestamptz not null default (clock_timestamp()+interval '30 seconds'),
 consumed_at timestamptz,verified_at timestamptz,
 foreign key(tenant_id,legal_entity_id,employee_id,document_id)
 references people_private.documents(tenant_id,legal_entity_id,employee_id,id)
);
create index on people_private.document_tickets(tenant_id,legal_entity_id,employee_id,document_id);
create index on people_private.document_tickets(expires_at);
-- Export preparations freeze identifiers only. Private bodies are returned by
-- a separate currently authorized API and never copied into generic receipts.
create table people_private.exports(
 id uuid primary key,tenant_id uuid not null,legal_entity_id uuid not null,branch_id uuid not null,
 employee_id uuid not null,kind text not null check(kind in ('profile','review')),
 source_id uuid not null,source_version bigint not null check(source_version between 1 and 9007199254740991),
 revision_id uuid not null,prepared_by uuid not null references auth.users(id),
 prepared_at timestamptz not null default clock_timestamp(),
 foreign key(tenant_id,legal_entity_id,employee_id) references people.employees(tenant_id,legal_entity_id,id),
 foreign key(tenant_id,legal_entity_id,branch_id) references core.branches(tenant_id,legal_entity_id,id)
);
create index on people_private.exports(tenant_id,legal_entity_id,branch_id,employee_id,id);
alter table people_private.profile_revisions add unique(tenant_id,legal_entity_id,employee_id,id);
alter table people_private.profiles add foreign key(tenant_id,legal_entity_id,employee_id,revision_id)
 references people_private.profile_revisions(tenant_id,legal_entity_id,employee_id,id) deferrable initially deferred;
alter table people_private.review_revisions add unique(tenant_id,legal_entity_id,employee_id,review_id,id);
alter table people_private.reviews add foreign key(tenant_id,legal_entity_id,employee_id,id,revision_id)
 references people_private.review_revisions(tenant_id,legal_entity_id,employee_id,review_id,id) deferrable initially deferred;
alter table people_private.review_events add foreign key(tenant_id,legal_entity_id,employee_id,review_id,revision_id)
 references people_private.review_revisions(tenant_id,legal_entity_id,employee_id,review_id,id);

-- Cover private FK lookups, including actor references, without changing other modules.
do $$declare v record;begin
 for v in select c.conrelid::regclass tab,c.conname,
 (select string_agg(quote_ident(a.attname),',' order by k.ord) from unnest(c.conkey) with ordinality k(att,ord)
 join pg_attribute a on a.attrelid=c.conrelid and a.attnum=k.att) cols
 from pg_constraint c join pg_class t on t.oid=c.conrelid join pg_namespace n on n.oid=t.relnamespace
 where n.nspname='people_private' and c.contype='f' and not exists(
 select 1 from pg_index i where i.indrelid=c.conrelid and i.indisvalid
 and array(select i.indkey[k] from generate_series(0,cardinality(c.conkey)-1) k)=c.conkey)
 loop execute format('create index %I on %s (%s)','w4hr_fk_'||substr(md5(v.tab::text||v.conname),1,16),v.tab,v.cols);end loop;
end $$;

insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types)
values('jentra-hr-private','jentra-hr-private',false,10485760,
 array['text/plain','image/png','image/jpeg','application/pdf']);
create policy wave4_private_hr_no_direct_storage on storage.objects as restrictive
 for all to anon,authenticated using(bucket_id<>'jentra-hr-private')
 with check(bucket_id<>'jentra-hr-private');

create function people_private.fields(p_body jsonb,p_allowed text[]) returns void
language plpgsql immutable set search_path='' as $$begin
 if coalesce(jsonb_typeof(p_body),'null')<>'object'
  or exists(select 1 from jsonb_object_keys(p_body) k where k<>all(p_allowed)) then
  raise exception using errcode='22023',message='HR_FIELDS_INVALID';
 end if;
end $$;
create function people_private.employee_scope(p_t uuid,p_e uuid,p_b uuid,p_employee uuid) returns void
language plpgsql stable security definer set search_path='' as $$begin
 if not exists(select 1 from people.employment_assignments a join core.branches b
  on b.tenant_id=a.tenant_id and b.id=a.branch_id and b.legal_entity_id=a.legal_entity_id
  where a.tenant_id=p_t and a.legal_entity_id=p_e and a.branch_id=p_b and a.employee_id=p_employee) then
  raise exception using errcode='42501',message='HR_SCOPE_DENIED';
 end if;
end $$;
create function people_private.require_access(p_t uuid,p_e uuid,p_b uuid,p_employee uuid,p_cap text,p_write boolean default false)
returns void language plpgsql security definer set search_path='' as $$begin
 perform people.require_access(p_t,p_e,p_b,p_cap);
 if p_write and coalesce(auth.jwt()->>'aal','aal1')<>'aal2' then
  raise exception using errcode='42501',message='HR_MFA_REQUIRED';
 end if;
 if p_employee is not null then perform people_private.employee_scope(p_t,p_e,p_b,p_employee); end if;
end $$;
create function people_private.content_available(p_t uuid,p_e uuid,p_employee uuid,p_write boolean default false)
returns void language plpgsql stable security definer set search_path='' as $$begin
 if not exists(select 1 from people_private.policies p where p.tenant_id=p_t and p.legal_entity_id=p_e
  and (p.closed_at is null or p.closed_at+interval '30 days'>now()))
  or exists(select 1 from people_private.purge_jobs j where j.tenant_id=p_t and j.legal_entity_id=p_e
   and j.employee_id=p_employee) then raise exception using errcode='55000',message='HR_CONTENT_EXPIRED'; end if;
 if p_write and not exists(select 1 from people_private.worker_readiness
  where contract='w4-private-hr-v1' and verified_at>now()-interval '26 hours') then
  raise exception using errcode='55000',message='HR_RETENTION_WORKER_UNAVAILABLE';
 end if;
end $$;
create function people_private.digest(p_t uuid,p_e uuid,p_body jsonb) returns text
language sql stable security definer set search_path='' as $$
 select encode(extensions.hmac(convert_to(p_body::text,'UTF8'),p.digest_key,'sha256'),'hex')
 from people_private.policies p where p.tenant_id=p_t and p.legal_entity_id=p_e
$$;
create function people_private.request_hash(p_t uuid,p_e uuid,p_b uuid,p_action text,p_command uuid,p_payload jsonb,p_version bigint)
returns text language plpgsql stable security definer set search_path='' as $$
declare v_base text;v_key bytea;begin
 v_base:=core.wave3_request_hash('people.private.'||p_action,p_command,p_t,p_e,p_b,p_payload,p_version);
 select digest_key into v_key from people_private.policies where tenant_id=p_t and legal_entity_id=p_e;
 -- Only the bounded policy-create command may precede its entity key.
 if v_key is null and p_action<>'policy_create' then
  raise exception using errcode='55000',message='HR_RETENTION_POLICY_REQUIRED'; end if;
 if p_action='policy_create' then return v_base; end if;
 return encode(extensions.hmac(convert_to(v_base,'UTF8'),v_key,'sha256'),'hex');
end $$;
create function people_private.active_link(p_t uuid,p_e uuid,p_b uuid,p_employee uuid) returns boolean
language sql stable security definer set search_path='' as $$
 select exists(select 1 from people_private.account_links l join core.memberships m
 on m.tenant_id=l.tenant_id and m.id=l.membership_id and m.user_id=l.user_id and m.status='active'
 where l.tenant_id=p_t and l.legal_entity_id=p_e and l.branch_id=p_b and l.employee_id=p_employee
 and l.user_id=auth.uid() and l.status='accepted')
$$;
create function people_private.employed(p_t uuid,p_e uuid,p_employee uuid,p_start date,p_end date) returns boolean
language sql stable security definer set search_path='' as $$
 select coalesce(range_agg(daterange(s.start_date,s.end_date_exclusive,'[)')) @> daterange(p_start,p_end,'[)'),false)
 from people.employment_spells s where s.tenant_id=p_t and s.legal_entity_id=p_e and s.employee_id=p_employee
$$;
create function people_private.guard_history() returns trigger language plpgsql set search_path='' as $$begin
 if current_setting('people_private.purging',true)='on' and tg_op='UPDATE' then
  if (to_jsonb(new)-'body'-'reason'-'private_text'-'redacted_at') is distinct from
    (to_jsonb(old)-'body'-'reason'-'private_text'-'redacted_at')
    or (to_jsonb(new)->'body' is not null and to_jsonb(new)->'body'<>'null')
    or (to_jsonb(new)->'reason' is not null and to_jsonb(new)->'reason'<>'null')
    or (to_jsonb(new)->'private_text' is not null and to_jsonb(new)->'private_text'<>'null') then
    raise exception using errcode='55000',message='HR_HISTORY_IMMUTABLE';
  end if;
  return new;
 end if;
 raise exception using errcode='55000',message='HR_HISTORY_IMMUTABLE';
end $$;
create trigger profile_revision_immutable before update or delete on people_private.profile_revisions
 for each row execute function people_private.guard_history();
create trigger review_revision_immutable before update or delete on people_private.review_revisions
 for each row execute function people_private.guard_history();
create trigger review_event_immutable before update or delete on people_private.review_events
 for each row execute function people_private.guard_history();
create trigger link_event_immutable before update or delete on people_private.link_events
 for each row execute function people_private.guard_history();
create trigger policy_event_immutable before update or delete on people_private.policy_events
 for each row execute function people_private.guard_history();
create trigger erasure_event_immutable before update or delete on people_private.erasure_events
 for each row execute function people_private.guard_history();
create trigger export_immutable before update or delete on people_private.exports
 for each row execute function people_private.guard_history();

create function api.people_hr_subjects(p_tenant_id uuid,p_legal_entity_id uuid,p_branch_id uuid,
 p_capability text,p_search text default '',p_after uuid default null) returns jsonb
language plpgsql stable security definer set search_path='' as $$
declare v_items jsonb;begin
 if p_capability not in ('people.hr.private.view','people.hr.private.manage','people.hr.documents.view',
  'people.hr.documents.manage','people.reviews.view','people.reviews.manage','people.account_links.manage')
  or length(coalesce(p_search,''))>160 then raise exception using errcode='22023',message='HR_FILTER_INVALID'; end if;
 perform people_private.require_access(p_tenant_id,p_legal_entity_id,p_branch_id,null,p_capability);
 select coalesce(jsonb_agg(jsonb_build_object('id',q.id,'code',q.code,'display_name',q.display_name) order by q.id),'[]')
 into v_items from(select e.id,e.code,e.display_name from people.employees e where e.tenant_id=p_tenant_id
 and e.legal_entity_id=p_legal_entity_id and (p_after is null or e.id>p_after)
 and (coalesce(p_search,'')='' or position(lower(btrim(p_search)) in lower(e.code||' '||e.display_name))>0)
 and exists(select 1 from people.employment_assignments a where a.tenant_id=e.tenant_id
 and a.legal_entity_id=e.legal_entity_id and a.employee_id=e.id and a.branch_id=p_branch_id)
 order by e.id limit 51) q;
 return jsonb_build_object('tenant_id',p_tenant_id,'legal_entity_id',p_legal_entity_id,'branch_id',p_branch_id,
  'items',v_items-50,'next_cursor',case when jsonb_array_length(v_items)>50 then v_items->49->>'id' end);
end $$;
create function api.people_hr_policy(p_tenant_id uuid,p_legal_entity_id uuid,p_branch_id uuid) returns jsonb
language plpgsql stable security definer set search_path='' as $$
declare v_policy jsonb;begin
 perform people_private.require_access(p_tenant_id,p_legal_entity_id,p_branch_id,null,'people.hr.retention.manage');
 select jsonb_build_object('id',p.id,'version',p.version,'purpose',p.purpose,'contract',p.contract,
  'retention_days',p.retention_days,'closed_at',p.closed_at,'hold_reason',p.hold_reason,'hold_review_date',p.hold_review_date)
 into v_policy from people_private.policies p where p.tenant_id=p_tenant_id and p.legal_entity_id=p_legal_entity_id;
 return jsonb_build_object('tenant_id',p_tenant_id,'legal_entity_id',p_legal_entity_id,'branch_id',p_branch_id,
  'policy',v_policy,'worker_ready',exists(select 1 from people_private.worker_readiness
   where contract='w4-private-hr-v1' and verified_at>now()-interval '26 hours'));
end $$;
create function api.people_hr_profile(p_tenant_id uuid,p_legal_entity_id uuid,p_branch_id uuid,p_employee_id uuid,
 p_after uuid default null) returns jsonb language plpgsql stable security definer set search_path='' as $$
declare v_profile jsonb;v_items jsonb;begin
 perform people_private.require_access(p_tenant_id,p_legal_entity_id,p_branch_id,p_employee_id,'people.hr.private.view');
 perform people_private.content_available(p_tenant_id,p_legal_entity_id,p_employee_id);
 select jsonb_build_object('employee_id',p.employee_id,'version',p.version,'revision_id',p.revision_id,
  'body',r.body,'recorded_by',r.recorded_by,'recorded_at',r.recorded_at)
 into v_profile from people_private.profiles p join people_private.profile_revisions r on r.id=p.revision_id
 where p.tenant_id=p_tenant_id and p.legal_entity_id=p_legal_entity_id and p.branch_id=p_branch_id
 and p.employee_id=p_employee_id and p.erased_at is null;
 select coalesce(jsonb_agg(jsonb_build_object('id',q.id,'version',q.version,'body',q.body,'reason',q.reason,
  'digest',q.digest,'recorded_by',q.recorded_by,'recorded_at',q.recorded_at) order by q.id),'[]') into v_items
 from(select r.* from people_private.profile_revisions r join people_private.profiles p
 on p.tenant_id=r.tenant_id and p.legal_entity_id=r.legal_entity_id and p.employee_id=r.employee_id
 where r.tenant_id=p_tenant_id and r.legal_entity_id=p_legal_entity_id and r.employee_id=p_employee_id
 and p.branch_id=p_branch_id and p.erased_at is null and (p_after is null or r.id>p_after) order by r.id limit 51) q;
 return jsonb_build_object('tenant_id',p_tenant_id,'legal_entity_id',p_legal_entity_id,'branch_id',p_branch_id,
 'employee_id',p_employee_id,'profile',v_profile,'history',v_items-50,
 'next_cursor',case when jsonb_array_length(v_items)>50 then v_items->49->>'id' end);
end $$;
create function api.people_hr_documents(p_tenant_id uuid,p_legal_entity_id uuid,p_branch_id uuid,
 p_employee_id uuid,p_after uuid default null) returns jsonb language plpgsql stable security definer set search_path='' as $$
declare v_items jsonb;begin
 perform people_private.require_access(p_tenant_id,p_legal_entity_id,p_branch_id,p_employee_id,'people.hr.documents.view');
 perform people_private.content_available(p_tenant_id,p_legal_entity_id,p_employee_id);
 select coalesce(jsonb_agg(jsonb_build_object('id',q.id,'version',q.version,'classification',q.classification,
 'purpose',q.purpose,'mime',q.mime,'byte_size',q.byte_size,'checksum',q.checksum,'status',q.status,
 'created_by',q.created_by,'created_at',q.created_at) order by q.id),'[]') into v_items
 from(select d.* from people_private.documents d where d.tenant_id=p_tenant_id and d.legal_entity_id=p_legal_entity_id
 and d.branch_id=p_branch_id and d.employee_id=p_employee_id and d.status not in ('erasing','erased')
 and (p_after is null or d.id>p_after) order by d.id limit 51) q;
 return jsonb_build_object('tenant_id',p_tenant_id,'legal_entity_id',p_legal_entity_id,'branch_id',p_branch_id,
 'employee_id',p_employee_id,'items',v_items-50,'next_cursor',case when jsonb_array_length(v_items)>50 then v_items->49->>'id' end);
end $$;
create function api.people_hr_reviews(p_tenant_id uuid,p_legal_entity_id uuid,p_branch_id uuid,
 p_employee_id uuid,p_after uuid default null) returns jsonb language plpgsql stable security definer set search_path='' as $$
declare v_self boolean;v_items jsonb;begin
 v_self:=people_private.active_link(p_tenant_id,p_legal_entity_id,p_branch_id,p_employee_id)
 and core.has_permission(p_tenant_id,'people.self.view',p_legal_entity_id,p_branch_id)
 and not core.has_permission(p_tenant_id,'people.reviews.view',p_legal_entity_id,p_branch_id);
 perform people_private.require_access(p_tenant_id,p_legal_entity_id,p_branch_id,p_employee_id,
 case when v_self then 'people.self.view' else 'people.reviews.view' end);
 perform people_private.content_available(p_tenant_id,p_legal_entity_id,p_employee_id);
 select coalesce(jsonb_agg(jsonb_build_object('id',q.id,'version',q.version,'revision_id',q.revision_id,
 'reviewer_id',q.reviewer_id,'status',q.status,'start_date',q.start_date,'end_date_exclusive',q.end_date_exclusive,
 'body',q.body,'recorded_by',q.recorded_by,'recorded_at',q.recorded_at) order by q.id),'[]') into v_items
 from(select r.*,v.body,v.recorded_by,v.recorded_at from people_private.reviews r
 join people_private.review_revisions v on v.id=r.revision_id
 where r.tenant_id=p_tenant_id and r.legal_entity_id=p_legal_entity_id and r.branch_id=p_branch_id
 and r.employee_id=p_employee_id and r.status<>'erased' and (not v_self or r.status<>'draft')
 and (r.status<>'draft' or r.created_by=auth.uid() or core.has_permission(p_tenant_id,'people.reviews.manage',p_legal_entity_id,p_branch_id))
 and (p_after is null or r.id>p_after) order by r.id limit 51) q;
 return jsonb_build_object('tenant_id',p_tenant_id,'legal_entity_id',p_legal_entity_id,'branch_id',p_branch_id,
 'employee_id',p_employee_id,'items',v_items-50,'next_cursor',case when jsonb_array_length(v_items)>50 then v_items->49->>'id' end);
end $$;
create function api.people_hr_links(p_tenant_id uuid,p_legal_entity_id uuid,p_branch_id uuid,
 p_employee_id uuid,p_after uuid default null) returns jsonb language plpgsql stable security definer set search_path='' as $$
declare v_items jsonb;begin
 perform people_private.require_access(p_tenant_id,p_legal_entity_id,p_branch_id,p_employee_id,'people.account_links.manage');
 select coalesce(jsonb_agg(jsonb_build_object('id',q.id,'version',q.version,'membership_id',q.membership_id,
 'user_id',q.user_id,'status',case when q.status='pending' and q.expires_at<=now() then 'expired' else q.status end,
 'initiated_by',q.initiated_by,'initiated_at',q.initiated_at,'expires_at',q.expires_at,'accepted_at',q.accepted_at) order by q.id),'[]')
 into v_items from(select l.* from people_private.account_links l where l.tenant_id=p_tenant_id
 and l.legal_entity_id=p_legal_entity_id and l.branch_id=p_branch_id and l.employee_id=p_employee_id
 and (p_after is null or l.id>p_after) order by l.id limit 51) q;
 return jsonb_build_object('tenant_id',p_tenant_id,'legal_entity_id',p_legal_entity_id,'branch_id',p_branch_id,
 'employee_id',p_employee_id,'items',v_items-50,'next_cursor',case when jsonb_array_length(v_items)>50 then v_items->49->>'id' end);
end $$;

create function api.people_hr_memberships(p_tenant_id uuid,p_legal_entity_id uuid,p_branch_id uuid,p_after uuid default null)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare v_items jsonb;begin
 perform people_private.require_access(p_tenant_id,p_legal_entity_id,p_branch_id,null,'people.account_links.manage',true);
 -- No login email or inferred employee match; exact existing identities only.
 select coalesce(jsonb_agg(jsonb_build_object('id',q.id,'user_id',q.user_id) order by q.id),'[]') into v_items
 from(select m.id,m.user_id from core.memberships m where m.tenant_id=p_tenant_id and m.status='active'
 and (p_after is null or m.id>p_after) order by m.id limit 51) q;
 return jsonb_build_object('tenant_id',p_tenant_id,'legal_entity_id',p_legal_entity_id,'branch_id',p_branch_id,
 'items',v_items-50,'next_cursor',case when jsonb_array_length(v_items)>50 then v_items->49->>'id' end);
end $$;
create function api.people_hr_link_inbox(p_tenant_id uuid,p_legal_entity_id uuid,p_branch_id uuid,p_after uuid default null)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare v_items jsonb;begin
 perform people.require_access(p_tenant_id,p_legal_entity_id,p_branch_id,'people.view');
 select coalesce(jsonb_agg(jsonb_build_object('id',q.id,'employee_id',q.employee_id,'employee_name',q.display_name,
 'version',q.version,'status',q.status,'initiated_by',q.initiated_by,'expires_at',q.expires_at) order by q.id),'[]') into v_items
 from(select l.*,e.display_name from people_private.account_links l join people.employees e
 on e.tenant_id=l.tenant_id and e.legal_entity_id=l.legal_entity_id and e.id=l.employee_id
 join core.memberships m on m.tenant_id=l.tenant_id and m.id=l.membership_id and m.user_id=l.user_id and m.status='active'
 where l.tenant_id=p_tenant_id and l.legal_entity_id=p_legal_entity_id and l.branch_id=p_branch_id
 and l.user_id=auth.uid() and l.status='pending' and l.expires_at>now()
 and (p_after is null or l.id>p_after) order by l.id limit 51) q;
 return jsonb_build_object('tenant_id',p_tenant_id,'legal_entity_id',p_legal_entity_id,'branch_id',p_branch_id,
 'items',v_items-50,'next_cursor',case when jsonb_array_length(v_items)>50 then v_items->49->>'id' end);
end $$;
create function api.people_hr_self(p_tenant_id uuid,p_legal_entity_id uuid,p_branch_id uuid) returns jsonb
language plpgsql stable security definer set search_path='' as $$
declare v_employee uuid;v_name text;begin
 perform people.require_access(p_tenant_id,p_legal_entity_id,p_branch_id,'people.self.view');
 select l.employee_id,e.display_name into v_employee,v_name from people_private.account_links l
 join people.employees e on e.tenant_id=l.tenant_id and e.legal_entity_id=l.legal_entity_id and e.id=l.employee_id
 join core.memberships m on m.tenant_id=l.tenant_id and m.id=l.membership_id and m.user_id=l.user_id and m.status='active'
 where l.tenant_id=p_tenant_id and l.legal_entity_id=p_legal_entity_id and l.branch_id=p_branch_id
 and l.user_id=auth.uid() and l.status='accepted';
 if v_employee is null then raise exception using errcode='42501',message='HR_ACTIVE_LINK_REQUIRED'; end if;
 return jsonb_build_object('tenant_id',p_tenant_id,'legal_entity_id',p_legal_entity_id,'branch_id',p_branch_id,
 'employee_id',v_employee,'display_name',v_name);
end $$;
create function api.people_hr_review_history(p_tenant_id uuid,p_legal_entity_id uuid,p_branch_id uuid,
 p_employee_id uuid,p_review_id uuid,p_after uuid default null) returns jsonb
language plpgsql stable security definer set search_path='' as $$
declare v_items jsonb;begin
 perform people_private.require_access(p_tenant_id,p_legal_entity_id,p_branch_id,p_employee_id,'people.reviews.view');
 perform people_private.content_available(p_tenant_id,p_legal_entity_id,p_employee_id);
 if not exists(select 1 from people_private.reviews r where r.id=p_review_id and r.tenant_id=p_tenant_id
 and r.legal_entity_id=p_legal_entity_id and r.branch_id=p_branch_id and r.employee_id=p_employee_id
 and r.status<>'erased' and (r.status<>'draft' or r.created_by=auth.uid()
 or core.has_permission(p_tenant_id,'people.reviews.manage',p_legal_entity_id,p_branch_id))) then
 raise exception using errcode='42501',message='HR_REVIEW_DENIED'; end if;
 select coalesce(jsonb_agg(q.body order by q.id),'[]') into v_items from(
 select v.id,jsonb_build_object('id',v.id,'kind','revision','revision_id',v.id,'body',v.body,'private_text',v.reason,
 'digest',v.digest,'recorded_by',v.recorded_by,'recorded_at',v.recorded_at) body
 from people_private.review_revisions v where v.review_id=p_review_id and (p_after is null or v.id>p_after)
 union all
 select v.id,jsonb_build_object('id',v.id,'kind',v.event_type,'revision_id',v.revision_id,'body',null,'private_text',v.private_text,
 'digest',v.digest,'recorded_by',v.recorded_by,'recorded_at',v.recorded_at)
 from people_private.review_events v where v.review_id=p_review_id and (p_after is null or v.id>p_after)
 order by id limit 51) q;
 return jsonb_build_object('tenant_id',p_tenant_id,'legal_entity_id',p_legal_entity_id,'branch_id',p_branch_id,
 'employee_id',p_employee_id,'review_id',p_review_id,'items',v_items-50,
 'next_cursor',case when jsonb_array_length(v_items)>50 then v_items->49->>'id' end);
end $$;

create function api.people_hr_command(p_tenant_id uuid,p_legal_entity_id uuid,p_branch_id uuid,
 p_command_id uuid,p_idempotency_key uuid,p_client_timestamp timestamptz,p_payload jsonb,p_expected_version bigint)
returns jsonb language plpgsql security definer set search_path='' as $$
declare v_action text:=p_payload->>'action';v_id uuid;v_employee uuid;v_reviewer uuid;v_revision uuid;
 v_cap text;v_allowed text[];v_hash text;v_replay jsonb;v_result jsonb;v_policy people_private.policies%rowtype;
 v_profile people_private.profiles%rowtype;v_doc people_private.documents%rowtype;
 v_review people_private.reviews%rowtype;v_link people_private.account_links%rowtype;
 v_body jsonb;v_field text;v_text text;v_start date;v_end date;v_digest text;v_version bigint;
begin
 if v_action is null or p_command_id is null or p_idempotency_key is null or p_client_timestamp is null
 or p_expected_version is null or p_expected_version not between 0 and 9007199254740990 then
 raise exception using errcode='22023',message='HR_COMMAND_INVALID'; end if;
 v_cap:=case
 when v_action in ('policy_create','cycle_close','hold','release_hold') then 'people.hr.retention.manage'
 when v_action='profile_save' then 'people.hr.private.manage'
 when v_action in ('document_reserve','document_complete') then 'people.hr.documents.manage'
 when v_action like 'review_%' and v_action<>'review_acknowledge' then 'people.reviews.manage'
 when v_action='review_acknowledge' then 'people.self.view'
 when v_action in ('link_initiate','link_revoke') then 'people.account_links.manage'
 when v_action in ('link_accept','link_reject') then 'people.view'
 when v_action='export_prepare' then 'people.hr.export'
 when v_action='erase_request' then 'people.hr.erase' end;
 v_allowed:=case v_action
 when 'policy_create' then array['action','id','purpose']
 when 'cycle_close' then array['action','id','closed_at']
 when 'hold' then array['action','id','reason','review_date']
 when 'release_hold' then array['action','id','reason']
 when 'profile_save' then array['action','id','employee_id','revision_id','body','reason']
 when 'document_reserve' then array['action','id','employee_id','classification','purpose','mime','byte_size','checksum']
 when 'document_complete' then array['action','id','employee_id']
 when 'review_create' then array['action','id','employee_id','reviewer_id','revision_id','start_date','end_date_exclusive','body','reason']
 when 'review_revise' then array['action','id','employee_id','revision_id','body','reason']
 when 'review_submit' then array['action','id','employee_id']
 when 'review_decide' then array['action','id','employee_id','private_text']
 when 'review_acknowledge' then array['action','id','employee_id']
 when 'review_close' then array['action','id','employee_id']
 when 'link_initiate' then array['action','id','employee_id','membership_id','user_id']
 when 'link_accept' then array['action','id','employee_id']
 when 'link_reject' then array['action','id','employee_id']
 when 'link_revoke' then array['action','id','employee_id']
 when 'export_prepare' then array['action','id','employee_id','kind','source_id','source_version','revision_id']
 when 'erase_request' then array['action','id','employee_id'] end;
 if v_cap is null or v_allowed is null then raise exception using errcode='22023',message='HR_COMMAND_INVALID'; end if;
 perform people_private.fields(p_payload,v_allowed);
 v_id:=(p_payload->>'id')::uuid;v_employee:=nullif(p_payload->>'employee_id','')::uuid;
 if v_id is null or (v_action not in ('policy_create','cycle_close','hold','release_hold') and v_employee is null) then
 raise exception using errcode='22023',message='HR_COMMAND_INVALID'; end if;
 perform people_private.require_access(p_tenant_id,p_legal_entity_id,p_branch_id,v_employee,v_cap,
 v_action not in ('link_accept','link_reject','review_acknowledge'));
 if v_employee is null then
 perform core.require_permission(p_tenant_id,v_cap,p_legal_entity_id,null); end if;
 if v_action in ('link_accept','link_reject') then
 select * into v_link from people_private.account_links where id=v_id and tenant_id=p_tenant_id
 and legal_entity_id=p_legal_entity_id and branch_id=p_branch_id and employee_id=v_employee;
 if not found or v_link.user_id<>auth.uid() or not exists(select 1 from core.memberships m
 where m.tenant_id=p_tenant_id and m.id=v_link.membership_id and m.user_id=auth.uid() and m.status='active')
 or (v_link.status='pending' and v_link.expires_at<=now())
 or v_link.status not in ('pending',case when v_action='link_accept' then 'accepted' else 'rejected' end) then
 raise exception using errcode='42501',message='HR_LINK_TARGET_DENIED'; end if;
 end if;
 if v_action='review_acknowledge' and not people_private.active_link(p_tenant_id,p_legal_entity_id,p_branch_id,v_employee) then
 raise exception using errcode='42501',message='HR_ACTIVE_LINK_REQUIRED'; end if;
 if v_action in ('review_decide','review_close') then
 select * into v_review from people_private.reviews where id=v_id and tenant_id=p_tenant_id
 and legal_entity_id=p_legal_entity_id and branch_id=p_branch_id and employee_id=v_employee;
 if v_review.id is null or not people_private.active_link(p_tenant_id,p_legal_entity_id,p_branch_id,v_review.reviewer_id)
 or not people_private.employed(p_tenant_id,p_legal_entity_id,v_review.reviewer_id,v_review.start_date,v_review.end_date_exclusive) then
 raise exception using errcode='42501',message='HR_INDEPENDENT_REVIEWER_REQUIRED';end if;
 end if;
 if v_action in ('profile_save','document_reserve','document_complete','review_create','review_revise',
 'review_submit','review_decide','review_acknowledge','review_close','export_prepare') then
 perform people_private.content_available(p_tenant_id,p_legal_entity_id,v_employee,true); end if;
 v_hash:=people_private.request_hash(p_tenant_id,p_legal_entity_id,p_branch_id,v_action,p_command_id,p_payload,p_expected_version);
 v_replay:=core.wave3_replay(p_tenant_id,'people.private.'||v_action,p_command_id,p_idempotency_key,v_hash);
 if v_replay is not null then return v_replay; end if;
 if v_action='review_create' then v_reviewer:=(p_payload->>'reviewer_id')::uuid;
 elsif v_action like 'review_%' then select reviewer_id into v_reviewer from people_private.reviews
 where id=v_id and tenant_id=p_tenant_id and legal_entity_id=p_legal_entity_id and branch_id=p_branch_id and employee_id=v_employee; end if;
 if v_employee is not null then perform e.id from people.employees e where e.tenant_id=p_tenant_id
 and e.legal_entity_id=p_legal_entity_id and e.id in (v_employee,v_reviewer) order by e.id for update; end if;
 perform pg_advisory_xact_lock(hashtextextended('people.private:'||p_tenant_id||':'||p_legal_entity_id,0));
 -- Recheck mutable access and retention after locks.
 perform people_private.require_access(p_tenant_id,p_legal_entity_id,p_branch_id,v_employee,v_cap,
 v_action not in ('link_accept','link_reject','review_acknowledge'));
 select * into v_policy from people_private.policies where tenant_id=p_tenant_id and legal_entity_id=p_legal_entity_id;
 if v_action in ('profile_save','document_reserve','document_complete','review_create','review_revise',
 'review_submit','review_decide','review_acknowledge','review_close','export_prepare') then
 perform people_private.content_available(p_tenant_id,p_legal_entity_id,v_employee,true); end if;

 if v_employee is null then
 if v_action='policy_create' then
 if v_policy.id is not null or p_expected_version<>0 or coalesce(jsonb_typeof(p_payload->'purpose'),'null')<>'string'
 or length(btrim(p_payload->>'purpose')) not between 1 and 160 then
 raise exception using errcode='22023',message='HR_POLICY_INVALID'; end if;
 insert into people_private.policies(id,tenant_id,legal_entity_id,purpose,created_by)
 values(v_id,p_tenant_id,p_legal_entity_id,btrim(p_payload->>'purpose'),auth.uid());
 v_version:=1;
 else
 if v_policy.id is distinct from v_id or v_policy.version is distinct from p_expected_version then
 raise exception using errcode='40001',message='VERSION_CONFLICT'; end if;
 if v_action='cycle_close' then
 if v_policy.closed_at is not null or coalesce(p_payload->>'closed_at','') !~ 'Z$'
 or (p_payload->>'closed_at')::timestamptz>now() then raise exception using errcode='22023',message='HR_POLICY_INVALID'; end if;
 update people_private.policies set closed_at=(p_payload->>'closed_at')::timestamptz,version=version+1 where id=v_id;
 elsif v_action='hold' then
 if coalesce(jsonb_typeof(p_payload->'reason'),'null')<>'string' or length(btrim(p_payload->>'reason')) not between 1 and 1000
 or coalesce(p_payload->>'review_date','') !~ '^\d{4}-\d{2}-\d{2}$'
 or (p_payload->>'review_date')::date<(now() at time zone 'UTC')::date then
 raise exception using errcode='22023',message='HR_POLICY_INVALID'; end if;
 if exists(select 1 from people_private.purge_jobs where tenant_id=p_tenant_id and legal_entity_id=p_legal_entity_id
 and status in ('leased','complete')) then raise exception using errcode='55000',message='HR_PURGE_ALREADY_STARTED'; end if;
 update people_private.policies set hold_reason=btrim(p_payload->>'reason'),hold_review_date=(p_payload->>'review_date')::date,
 version=version+1 where id=v_id;
 else
 if v_policy.hold_reason is null or coalesce(jsonb_typeof(p_payload->'reason'),'null')<>'string'
 or length(btrim(p_payload->>'reason')) not between 1 and 1000 then raise exception using errcode='22023',message='HR_POLICY_INVALID'; end if;
 update people_private.policies set hold_reason=null,hold_review_date=null,version=version+1 where id=v_id;
 end if;v_version:=p_expected_version+1;
 end if;
 insert into people_private.policy_events(tenant_id,legal_entity_id,policy_id,version,event_type,reason,recorded_by)
 values(p_tenant_id,p_legal_entity_id,v_id,v_version,v_action,p_payload->>'reason',auth.uid());
 elsif v_action='profile_save' then
 if v_id<>v_employee then raise exception using errcode='22023',message='HR_PROFILE_ID_INVALID'; end if;
 select * into v_profile from people_private.profiles where employee_id=v_employee;
 if (v_profile.employee_id is null and p_expected_version<>0) or (v_profile.employee_id is not null
 and (v_profile.version<>p_expected_version or v_profile.branch_id<>p_branch_id or v_profile.erased_at is not null)) then
 raise exception using errcode='40001',message='VERSION_CONFLICT'; end if;
 v_body:=p_payload->'body';perform people_private.fields(v_body,array['personal_email','personal_phone','postal_address',
 'emergency_name','emergency_relationship','emergency_phone']);
 v_body:=jsonb_build_object('personal_email',null,'personal_phone',null,'postal_address',null,'emergency_name',null,
 'emergency_relationship',null,'emergency_phone',null)||v_body;
 foreach v_field in array array['personal_email','personal_phone','postal_address','emergency_name','emergency_relationship','emergency_phone'] loop
 if v_body ? v_field and v_body->v_field<>'null'::jsonb and (jsonb_typeof(v_body->v_field)<>'string'
 or length(btrim(v_body->>v_field)) not between 1 and case when v_field='postal_address' then 1000 else 160 end) then
 raise exception using errcode='22023',message='HR_PROFILE_FIELDS_INVALID'; end if;end loop;
 if coalesce(jsonb_typeof(p_payload->'reason'),'null')<>'string' or length(btrim(p_payload->>'reason')) not between 1 and 1000 then
 raise exception using errcode='22023',message='HR_PROFILE_FIELDS_INVALID'; end if;
 v_revision:=(p_payload->>'revision_id')::uuid;if v_revision is null then raise exception using errcode='22023',message='HR_FIELDS_INVALID';end if;
 v_version:=p_expected_version+1;v_digest:=people_private.digest(p_tenant_id,p_legal_entity_id,v_body);
 insert into people_private.profiles(employee_id,tenant_id,legal_entity_id,branch_id,policy_id,version,revision_id)
 values(v_employee,p_tenant_id,p_legal_entity_id,p_branch_id,v_policy.id,v_version,v_revision)
 on conflict(employee_id) do update set version=excluded.version,revision_id=excluded.revision_id;
 insert into people_private.profile_revisions(id,tenant_id,legal_entity_id,employee_id,version,body,reason,digest,recorded_by)
 values(v_revision,p_tenant_id,p_legal_entity_id,v_employee,v_version,v_body,btrim(p_payload->>'reason'),v_digest,auth.uid());
 elsif v_action in ('document_reserve','document_complete') then
 select * into v_doc from people_private.documents where id=v_id and tenant_id=p_tenant_id
 and legal_entity_id=p_legal_entity_id and branch_id=p_branch_id and employee_id=v_employee;
 if v_action='document_reserve' then
 if v_doc.id is not null or p_expected_version<>0 then raise exception using errcode='40001',message='VERSION_CONFLICT'; end if;
 if coalesce(p_payload->>'classification','') not in ('contact-support','review-evidence')
 or coalesce(p_payload->>'mime','') not in ('text/plain','image/png','image/jpeg','application/pdf')
 or coalesce(jsonb_typeof(p_payload->'purpose'),'null')<>'string' or length(btrim(p_payload->>'purpose')) not between 1 and 160
 or coalesce(p_payload->>'byte_size','') !~ '^[1-9][0-9]{0,7}$' or (p_payload->>'byte_size')::integer>10485760
 or coalesce(p_payload->>'checksum','') !~ '^[a-f0-9]{64}$' then raise exception using errcode='22023',message='HR_DOCUMENT_INVALID'; end if;
 if (select count(*) from people_private.documents where employee_id=v_employee)>=50 then
 raise exception using errcode='54000',message='HR_DOCUMENT_LIMIT'; end if;
 insert into people_private.documents(id,tenant_id,legal_entity_id,branch_id,employee_id,policy_id,classification,purpose,mime,
 byte_size,checksum,object_path,created_by) values(v_id,p_tenant_id,p_legal_entity_id,p_branch_id,v_employee,v_policy.id,
 p_payload->>'classification',btrim(p_payload->>'purpose'),p_payload->>'mime',(p_payload->>'byte_size')::integer,p_payload->>'checksum',
 p_tenant_id||'/'||p_legal_entity_id||'/'||v_employee||'/'||v_id,auth.uid());v_version:=1;
 else
 if v_doc.id is null or v_doc.version<>p_expected_version then raise exception using errcode='40001',message='VERSION_CONFLICT'; end if;
 if v_doc.status<>'verified' then raise exception using errcode='55000',message='HR_UPLOAD_VERIFICATION_REQUIRED'; end if;
 update people_private.documents set status='active',version=version+1 where id=v_id;v_version:=p_expected_version+1;
 end if;
 elsif v_action like 'review_%' then
 select * into v_review from people_private.reviews where id=v_id and tenant_id=p_tenant_id
 and legal_entity_id=p_legal_entity_id and branch_id=p_branch_id and employee_id=v_employee;
 if v_action='review_create' then
 if v_review.id is not null or p_expected_version<>0 then raise exception using errcode='40001',message='VERSION_CONFLICT';end if;
 v_start:=(p_payload->>'start_date')::date;v_end:=(p_payload->>'end_date_exclusive')::date;
 if v_start is null or v_end is null or not isfinite(v_start) or not isfinite(v_end)
 or v_end<=v_start or v_end-v_start>366 or v_reviewer is null or v_employee=v_reviewer
 or not people_private.employed(p_tenant_id,p_legal_entity_id,v_employee,v_start,v_end)
 or not people_private.employed(p_tenant_id,p_legal_entity_id,v_reviewer,v_start,v_end) then
 raise exception using errcode='22023',message='HR_REVIEW_ELIGIBILITY_INVALID';end if;
 else
 if v_review.id is null or v_review.version<>p_expected_version or v_review.status='erased' then
 raise exception using errcode='40001',message='VERSION_CONFLICT';end if;
 end if;
 if v_action in ('review_create','review_revise') then
 v_revision:=(p_payload->>'revision_id')::uuid;v_body:=p_payload->'body';
 perform people_private.fields(v_body,array['objectives','comments']);
 v_body:=jsonb_build_object('comments',null)||v_body;
 if v_revision is null or coalesce(jsonb_typeof(v_body->'objectives'),'null')<>'array'
 or jsonb_array_length(v_body->'objectives') not between 1 and 20
 or exists(select 1 from jsonb_array_elements(v_body->'objectives') x where jsonb_typeof(x)<>'string' or length(btrim(x#>>'{}')) not between 1 and 1000)
 or (v_body->'comments'<>'null'::jsonb and (jsonb_typeof(v_body->'comments')<>'string' or length(v_body->>'comments')>4000))
 or coalesce(jsonb_typeof(p_payload->'reason'),'null')<>'string' or length(btrim(p_payload->>'reason')) not between 1 and 1000 then
 raise exception using errcode='22023',message='HR_REVIEW_FIELDS_INVALID';end if;
 v_digest:=people_private.digest(p_tenant_id,p_legal_entity_id,v_body);v_version:=p_expected_version+1;
 if v_action='review_create' then
 insert into people_private.reviews(id,tenant_id,legal_entity_id,branch_id,employee_id,reviewer_id,policy_id,
 revision_id,status,start_date,end_date_exclusive,created_by)
 values(v_id,p_tenant_id,p_legal_entity_id,p_branch_id,v_employee,v_reviewer,v_policy.id,v_revision,'draft',v_start,v_end,auth.uid());
 else
 update people_private.reviews set version=v_version,revision_id=v_revision,status='draft',created_by=auth.uid() where id=v_id;
 end if;
 insert into people_private.review_revisions(id,tenant_id,legal_entity_id,employee_id,review_id,body,reason,digest,recorded_by)
 values(v_revision,p_tenant_id,p_legal_entity_id,v_employee,v_id,v_body,btrim(p_payload->>'reason'),v_digest,auth.uid());
 else
 v_revision:=v_review.revision_id;
 if v_action='review_submit' then
 if v_review.status<>'draft' or v_review.created_by<>auth.uid() then
 raise exception using errcode='42501',message='HR_REVIEW_AUTHOR_REQUIRED';end if;
 v_text:=null;update people_private.reviews set status='submitted',version=version+1 where id=v_id;
 elsif v_action='review_decide' then
 if v_review.status<>'submitted' or v_review.created_by=auth.uid()
 or not people_private.active_link(p_tenant_id,p_legal_entity_id,p_branch_id,v_review.reviewer_id)
 or not people_private.employed(p_tenant_id,p_legal_entity_id,v_review.reviewer_id,v_review.start_date,v_review.end_date_exclusive)
 or coalesce(jsonb_typeof(p_payload->'private_text'),'null')<>'string' or length(btrim(p_payload->>'private_text')) not between 1 and 4000 then
 raise exception using errcode='42501',message='HR_INDEPENDENT_REVIEWER_REQUIRED';end if;
 v_text:=btrim(p_payload->>'private_text');update people_private.reviews set status='reviewed',version=version+1 where id=v_id;
 elsif v_action='review_acknowledge' then
 if v_review.status<>'reviewed' then raise exception using errcode='55000',message='HR_REVIEW_STATUS_INVALID';end if;
 v_text:=null;update people_private.reviews set status='acknowledged',version=version+1 where id=v_id;
 elsif v_action='review_close' then
 if v_review.status<>'acknowledged' or not people_private.active_link(p_tenant_id,p_legal_entity_id,p_branch_id,v_review.reviewer_id)
 then raise exception using errcode='42501',message='HR_INDEPENDENT_REVIEWER_REQUIRED';end if;
 v_text:=null;update people_private.reviews set status='closed',version=version+1 where id=v_id;
 else raise exception using errcode='22023',message='HR_COMMAND_INVALID';end if;
 v_version:=p_expected_version+1;v_digest:=people_private.digest(p_tenant_id,p_legal_entity_id,jsonb_build_object('action',v_action,'text',v_text,'revision',v_revision));
 insert into people_private.review_events(tenant_id,legal_entity_id,employee_id,review_id,revision_id,event_type,private_text,digest,recorded_by)
 values(p_tenant_id,p_legal_entity_id,v_employee,v_id,v_revision,v_action,v_text,v_digest,auth.uid());
 end if;
 elsif v_action like 'link_%' then
 perform pg_advisory_xact_lock(hashtextextended('people.links:'||p_tenant_id,0));
 if v_action='link_initiate' then
 if p_expected_version<>0 or not exists(select 1 from core.memberships m where m.tenant_id=p_tenant_id
 and m.id=(p_payload->>'membership_id')::uuid and m.user_id=(p_payload->>'user_id')::uuid and m.status='active') then
 raise exception using errcode='42501',message='HR_EXACT_MEMBERSHIP_REQUIRED';end if;
 insert into people_private.link_events(tenant_id,legal_entity_id,employee_id,link_id,event_type,actor_kind)
 select tenant_id,legal_entity_id,employee_id,id,'expired','system' from people_private.account_links
 where tenant_id=p_tenant_id and status='pending' and expires_at<=now()
 and (employee_id=v_employee or user_id=(p_payload->>'user_id')::uuid);
 update people_private.account_links set status='expired',version=version+1 where tenant_id=p_tenant_id
 and status='pending' and expires_at<=now() and (employee_id=v_employee or user_id=(p_payload->>'user_id')::uuid);
 if exists(select 1 from people_private.account_links where tenant_id=p_tenant_id and status in ('pending','accepted')
 and (employee_id=v_employee or user_id=(p_payload->>'user_id')::uuid)) then
 raise exception using errcode='55000',message='HR_LINK_ALREADY_EXISTS';end if;
 insert into people_private.account_links(id,tenant_id,legal_entity_id,branch_id,employee_id,membership_id,user_id,initiated_by)
 values(v_id,p_tenant_id,p_legal_entity_id,p_branch_id,v_employee,(p_payload->>'membership_id')::uuid,(p_payload->>'user_id')::uuid,auth.uid());
 v_version:=1;
 else
 select * into v_link from people_private.account_links where id=v_id and tenant_id=p_tenant_id
 and legal_entity_id=p_legal_entity_id and branch_id=p_branch_id and employee_id=v_employee;
 if not found or v_link.version<>p_expected_version then raise exception using errcode='40001',message='VERSION_CONFLICT';end if;
 if v_action in ('link_accept','link_reject') and (v_link.status<>'pending' or v_link.expires_at<=now()
 or v_link.user_id<>auth.uid() or not exists(select 1 from core.memberships m where m.tenant_id=p_tenant_id
 and m.id=v_link.membership_id and m.user_id=auth.uid() and m.status='active')) then
 raise exception using errcode='42501',message='HR_LINK_TARGET_DENIED';end if;
 if v_action='link_revoke' and v_link.status not in ('pending','accepted') then raise exception using errcode='55000',message='HR_LINK_STATUS_INVALID';end if;
 update people_private.account_links set status=case v_action when 'link_accept' then 'accepted'
 when 'link_reject' then 'rejected' else 'revoked' end,version=version+1,
 accepted_at=case when v_action='link_accept' then clock_timestamp() else accepted_at end where id=v_id;
 v_version:=p_expected_version+1;
 end if;
 insert into people_private.link_events(tenant_id,legal_entity_id,employee_id,link_id,event_type,recorded_by,actor_kind)
 values(p_tenant_id,p_legal_entity_id,v_employee,v_id,v_action,auth.uid(),'user');
 elsif v_action='export_prepare' then
 if p_expected_version<>0 or p_payload->>'kind' not in ('profile','review')
 or (p_payload->>'source_version')::bigint not between 1 and 9007199254740991 then
 raise exception using errcode='22023',message='HR_EXPORT_INVALID';end if;
 v_revision:=(p_payload->>'revision_id')::uuid;
 if p_payload->>'kind'='profile' then
 perform people_private.require_access(p_tenant_id,p_legal_entity_id,p_branch_id,v_employee,'people.hr.private.view');
 if not exists(select 1 from people_private.profiles p where p.employee_id=v_employee and p.branch_id=p_branch_id
 and p.employee_id=(p_payload->>'source_id')::uuid and p.version=(p_payload->>'source_version')::bigint
 and p.revision_id=v_revision and p.erased_at is null) then
 raise exception using errcode='40001',message='VERSION_CONFLICT';end if;
 else
 perform people_private.require_access(p_tenant_id,p_legal_entity_id,p_branch_id,v_employee,'people.reviews.view');
 if not exists(select 1 from people_private.reviews r where r.id=(p_payload->>'source_id')::uuid
 and r.tenant_id=p_tenant_id and r.legal_entity_id=p_legal_entity_id and r.branch_id=p_branch_id
 and r.employee_id=v_employee and r.version=(p_payload->>'source_version')::bigint and r.revision_id=v_revision
 and r.status<>'erased' and (r.status<>'draft' or r.created_by=auth.uid()
 or core.has_permission(p_tenant_id,'people.reviews.manage',p_legal_entity_id,p_branch_id))) then
 raise exception using errcode='40001',message='VERSION_CONFLICT';end if;
 end if;
 insert into people_private.exports(id,tenant_id,legal_entity_id,branch_id,employee_id,kind,source_id,
 source_version,revision_id,prepared_by) values(v_id,p_tenant_id,p_legal_entity_id,p_branch_id,v_employee,
 p_payload->>'kind',(p_payload->>'source_id')::uuid,(p_payload->>'source_version')::bigint,v_revision,auth.uid());
 v_version:=1;
 elsif v_action='erase_request' then
 if v_policy.hold_reason is not null then raise exception using errcode='55000',message='HR_LEGAL_HOLD';end if;
 if v_id<>v_employee or p_expected_version<>0 then raise exception using errcode='22023',message='HR_ERASURE_INVALID';end if;
 insert into people_private.purge_jobs(tenant_id,legal_entity_id,employee_id,requested_by)
 values(p_tenant_id,p_legal_entity_id,v_employee,auth.uid()) on conflict(tenant_id,legal_entity_id,employee_id) do nothing;
 v_version:=1;
 end if;
 v_result:=jsonb_build_object('id',v_id,'tenant_id',p_tenant_id,'legal_entity_id',p_legal_entity_id,'branch_id',p_branch_id,
 'employee_id',v_employee,'version',v_version,'action',v_action,'revision_id',v_revision,'digest',v_digest);
 -- No private body, reason, path, link target or filename enters generic evidence.
 return core.wave3_finish_command(p_tenant_id,'people.private.'||v_action,p_command_id,'people.private',v_id,
 p_idempotency_key,v_hash,'{}',v_result,p_legal_entity_id,p_branch_id);
exception when invalid_text_representation or invalid_datetime_format or datetime_field_overflow or numeric_value_out_of_range then
 raise exception using errcode='22023',message='HR_FIELDS_INVALID';
end $$;

create function api.people_hr_access(p_tenant_id uuid,p_legal_entity_id uuid,p_branch_id uuid,p_employee_id uuid,p_capability text)
returns jsonb language plpgsql stable security definer set search_path='' as $$begin
 if p_capability not in ('people.hr.private.view','people.hr.private.manage','people.hr.documents.view',
 'people.hr.documents.manage','people.reviews.view','people.reviews.manage','people.account_links.manage','people.self.view',
 'people.hr.retention.manage','people.hr.export','people.hr.erase','people.view') then
 raise exception using errcode='22023',message='HR_CAPABILITY_INVALID';end if;
 perform people_private.require_access(p_tenant_id,p_legal_entity_id,p_branch_id,p_employee_id,p_capability,
 p_capability in ('people.hr.private.manage','people.hr.documents.manage','people.reviews.manage',
 'people.account_links.manage','people.hr.retention.manage','people.hr.export','people.hr.erase'));
 if p_capability='people.self.view' and not people_private.active_link(p_tenant_id,p_legal_entity_id,p_branch_id,p_employee_id) then
 raise exception using errcode='42501',message='HR_ACTIVE_LINK_REQUIRED';end if;
 if p_capability in ('people.hr.private.view','people.hr.private.manage','people.hr.documents.view',
 'people.hr.documents.manage','people.reviews.view','people.reviews.manage','people.hr.export') then
 perform people_private.content_available(p_tenant_id,p_legal_entity_id,p_employee_id,
 p_capability in ('people.hr.private.manage','people.hr.documents.manage','people.reviews.manage'));end if;
 return jsonb_build_object('authorized',true,'actor_id',auth.uid());
end $$;
create function api.people_hr_own_receipt(p_tenant_id uuid,p_legal_entity_id uuid,p_branch_id uuid,p_command_id uuid)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare v_receipt core.command_receipts%rowtype;v_cap text;v_action text;v_employee uuid;begin
 select * into v_receipt from core.command_receipts where actor_id=auth.uid() and command_id=p_command_id
 and tenant_id=p_tenant_id and legal_entity_id=p_legal_entity_id and branch_id=p_branch_id
 and command_name like 'people.private.%';
 if not found then perform people.require_access(p_tenant_id,p_legal_entity_id,p_branch_id,'people.view');return null;end if;
 v_action:=substr(v_receipt.command_name,length('people.private.')+1);
 v_cap:=case when v_action in ('policy_create','cycle_close','hold','release_hold') then 'people.hr.retention.manage'
 when v_action='profile_save' then 'people.hr.private.manage'
 when v_action in ('document_reserve','document_complete') then 'people.hr.documents.manage'
 when v_action='review_acknowledge' then 'people.self.view'
 when v_action like 'review_%' then 'people.reviews.manage'
 when v_action in ('link_accept','link_reject') then 'people.view'
 when v_action like 'link_%' then 'people.account_links.manage'
 when v_action='export_prepare' then 'people.hr.export'
 when v_action='erase_request' then 'people.hr.erase' end;
 v_employee:=(v_receipt.response->'entity'->>'employee_id')::uuid;
 perform people_private.require_access(p_tenant_id,p_legal_entity_id,p_branch_id,v_employee,v_cap,
 v_action not in ('link_accept','link_reject','review_acknowledge'));
 if v_action='review_acknowledge' and not people_private.active_link(p_tenant_id,p_legal_entity_id,p_branch_id,v_employee) then
 raise exception using errcode='42501',message='HR_ACTIVE_LINK_REQUIRED';end if;
 if v_action='link_accept' and not exists(select 1 from people_private.account_links where id=v_receipt.aggregate_id
 and user_id=auth.uid() and status='accepted') then raise exception using errcode='42501',message='HR_ACTIVE_LINK_REQUIRED';end if;
 if v_action in ('review_decide','review_close') and not exists(select 1 from people_private.reviews r
 where r.id=v_receipt.aggregate_id and people_private.active_link(p_tenant_id,p_legal_entity_id,p_branch_id,r.reviewer_id)
 and people_private.employed(p_tenant_id,p_legal_entity_id,r.reviewer_id,r.start_date,r.end_date_exclusive)) then
 raise exception using errcode='42501',message='HR_INDEPENDENT_REVIEWER_REQUIRED';end if;
 return v_receipt.response;
end $$;
create function api.people_hr_export_content(p_tenant_id uuid,p_legal_entity_id uuid,p_branch_id uuid,p_export_id uuid)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare v people_private.exports%rowtype;v_body jsonb;v_digest text;v_by uuid;v_at timestamptz;begin
 select * into v from people_private.exports where id=p_export_id and tenant_id=p_tenant_id
 and legal_entity_id=p_legal_entity_id and branch_id=p_branch_id and prepared_by=auth.uid();
 if not found then raise exception using errcode='42501',message='HR_EXPORT_DENIED';end if;
 perform people_private.require_access(p_tenant_id,p_legal_entity_id,p_branch_id,v.employee_id,'people.hr.export',true);
 perform people_private.content_available(p_tenant_id,p_legal_entity_id,v.employee_id);
 if v.kind='profile' then
 perform people_private.require_access(p_tenant_id,p_legal_entity_id,p_branch_id,v.employee_id,'people.hr.private.view');
 select body,digest,recorded_by,recorded_at into v_body,v_digest,v_by,v_at from people_private.profile_revisions
 where id=v.revision_id and tenant_id=p_tenant_id and legal_entity_id=p_legal_entity_id and employee_id=v.employee_id;
 else
 perform people_private.require_access(p_tenant_id,p_legal_entity_id,p_branch_id,v.employee_id,'people.reviews.view');
 if not exists(select 1 from people_private.reviews r where r.id=v.source_id and r.tenant_id=p_tenant_id
 and r.legal_entity_id=p_legal_entity_id and r.branch_id=p_branch_id and r.employee_id=v.employee_id
 and r.status<>'erased' and (r.status<>'draft' or r.created_by=auth.uid()
 or core.has_permission(p_tenant_id,'people.reviews.manage',p_legal_entity_id,p_branch_id))) then
 raise exception using errcode='42501',message='HR_EXPORT_DENIED';end if;
 select body,digest,recorded_by,recorded_at into v_body,v_digest,v_by,v_at from people_private.review_revisions
 where id=v.revision_id and review_id=v.source_id and tenant_id=p_tenant_id
 and legal_entity_id=p_legal_entity_id and employee_id=v.employee_id;
 end if;
 if v_body is null then raise exception using errcode='55000',message='HR_CONTENT_EXPIRED';end if;
 return jsonb_build_object('format','w4-hr-export-v1','export_id',v.id,'tenant_id',v.tenant_id,
 'legal_entity_id',v.legal_entity_id,'branch_id',v.branch_id,'employee_id',v.employee_id,'kind',v.kind,
 'source_id',v.source_id,'source_version',v.source_version,'revision_id',v.revision_id,'body',v_body,
 'digest',v_digest,'recorded_by',v_by,'recorded_at',v_at);
end $$;
create function people_private.service_only() returns void language plpgsql stable set search_path='' as $$begin
 if coalesce(auth.role(),'')<>'service_role' then raise exception using errcode='42501',message='HR_TRUSTED_SERVICE_REQUIRED';end if;
end $$;
create function people_private.user_has(p_t uuid,p_e uuid,p_b uuid,p_user uuid,p_cap text,p_aal text) returns boolean
language sql stable security definer set search_path='' as $$
 select exists(select 1 from core.memberships m join core.role_assignments ra
 on ra.tenant_id=m.tenant_id and ra.membership_id=m.id join core.roles r on r.tenant_id=ra.tenant_id and r.id=ra.role_id
 join core.role_permissions rp on rp.tenant_id=r.tenant_id and rp.role_id=r.id
 where m.tenant_id=p_t and m.user_id=p_user and m.status='active' and rp.permission_code=p_cap
 and (ra.legal_entity_id is null or ra.legal_entity_id=p_e) and (ra.branch_id is null or ra.branch_id=p_b)
 and (not r.requires_mfa or p_aal='aal2'))
 and exists(select 1 from billing.tenant_subscriptions s join billing.plan_entitlements pe on pe.plan_code=s.plan_code
 where s.tenant_id=p_t and pe.entitlement_code='module.people' and pe.enabled
 and ((s.status='active' and (s.current_period_ends_at is null or s.current_period_ends_at>now()))
 or (s.status='trialing' and s.trial_ends_at>now())))
 and exists(select 1 from core.branches where tenant_id=p_t and legal_entity_id=p_e and id=p_b)
$$;
create function api.people_hr_document_ticket(p_tenant_id uuid,p_legal_entity_id uuid,p_branch_id uuid,
 p_employee_id uuid,p_document_id uuid,p_operation text) returns jsonb
language plpgsql security definer set search_path='' as $$
declare v_id uuid;v_doc people_private.documents%rowtype;begin
 if p_operation not in ('upload','download','export') then raise exception using errcode='22023',message='HR_DOCUMENT_OPERATION_INVALID';end if;
 perform people_private.require_access(p_tenant_id,p_legal_entity_id,p_branch_id,p_employee_id,
 case when p_operation='upload' then 'people.hr.documents.manage' else 'people.hr.documents.view' end,p_operation='upload');
 if p_operation='export' then perform people_private.require_access(p_tenant_id,p_legal_entity_id,p_branch_id,p_employee_id,'people.hr.export',true);end if;
 perform people_private.content_available(p_tenant_id,p_legal_entity_id,p_employee_id,p_operation='upload');
 select * into v_doc from people_private.documents where id=p_document_id and tenant_id=p_tenant_id
 and legal_entity_id=p_legal_entity_id and branch_id=p_branch_id and employee_id=p_employee_id;
 if not found or (p_operation='upload' and v_doc.status not in ('reserved','verified','active'))
 or (p_operation<>'upload' and v_doc.status<>'active') then raise exception using errcode='42501',message='HR_DOCUMENT_DENIED';end if;
 insert into people_private.document_tickets(tenant_id,legal_entity_id,branch_id,employee_id,document_id,user_id,operation,issued_aal)
 values(p_tenant_id,p_legal_entity_id,p_branch_id,p_employee_id,p_document_id,auth.uid(),p_operation,coalesce(auth.jwt()->>'aal','aal1'))
 returning id into v_id;
 return jsonb_build_object('ticket_id',v_id,'expires_at',now()+interval '30 seconds');
end $$;
create function api.people_hr_service_document(p_ticket_id uuid,p_user_id uuid) returns jsonb
language plpgsql security definer set search_path='' as $$
declare v_ticket people_private.document_tickets%rowtype;v_doc people_private.documents%rowtype;begin
 perform people_private.service_only();
 select * into v_ticket from people_private.document_tickets where id=p_ticket_id for update;
 if not found or v_ticket.user_id<>p_user_id or v_ticket.expires_at<=now() or v_ticket.consumed_at is not null
 or not people_private.user_has(v_ticket.tenant_id,v_ticket.legal_entity_id,v_ticket.branch_id,p_user_id,'people.view',v_ticket.issued_aal)
 or not people_private.user_has(v_ticket.tenant_id,v_ticket.legal_entity_id,v_ticket.branch_id,p_user_id,
 case when v_ticket.operation='upload' then 'people.hr.documents.manage' else 'people.hr.documents.view' end,v_ticket.issued_aal)
 or (v_ticket.operation='export' and not people_private.user_has(v_ticket.tenant_id,v_ticket.legal_entity_id,v_ticket.branch_id,p_user_id,'people.hr.export',v_ticket.issued_aal))
 or (v_ticket.operation in ('upload','export') and v_ticket.issued_aal<>'aal2') then
 raise exception using errcode='42501',message='HR_DOCUMENT_DENIED';end if;
 perform people_private.content_available(v_ticket.tenant_id,v_ticket.legal_entity_id,v_ticket.employee_id,v_ticket.operation='upload');
 select * into v_doc from people_private.documents where id=v_ticket.document_id;
 if v_doc.object_path is null or (v_ticket.operation<>'upload' and v_doc.status<>'active')
 or (v_ticket.operation='upload' and v_doc.status not in ('reserved','verified','active')) then
 raise exception using errcode='42501',message='HR_DOCUMENT_DENIED';end if;
 update people_private.document_tickets set consumed_at=clock_timestamp() where id=p_ticket_id;
 return jsonb_build_object('ticket_id',p_ticket_id,'operation',v_ticket.operation,'object_path',v_doc.object_path,
 'document_id',v_doc.id,'employee_id',v_doc.employee_id,'tenant_id',v_doc.tenant_id,'legal_entity_id',v_doc.legal_entity_id,
 'branch_id',v_doc.branch_id,'mime',v_doc.mime,'byte_size',v_doc.byte_size,'checksum',v_doc.checksum,'status',v_doc.status);
end $$;
create function api.people_hr_service_verify_upload(p_ticket_id uuid,p_user_id uuid,p_checksum text,p_byte_size integer)
returns jsonb language plpgsql security definer set search_path='' as $$
declare v_ticket people_private.document_tickets%rowtype;v_doc people_private.documents%rowtype;begin
 perform people_private.service_only();
 select * into v_ticket from people_private.document_tickets where id=p_ticket_id;
 if not found or v_ticket.operation<>'upload' or v_ticket.user_id<>p_user_id or v_ticket.consumed_at is null
 or v_ticket.expires_at+interval '2 minutes'<=now()
 or not people_private.user_has(v_ticket.tenant_id,v_ticket.legal_entity_id,v_ticket.branch_id,p_user_id,'people.view',v_ticket.issued_aal)
 or not people_private.user_has(v_ticket.tenant_id,v_ticket.legal_entity_id,v_ticket.branch_id,p_user_id,'people.hr.documents.manage',v_ticket.issued_aal) then
 raise exception using errcode='42501',message='HR_DOCUMENT_DENIED';end if;
 perform e.id from people.employees e where id=v_ticket.employee_id for update;
 perform pg_advisory_xact_lock(hashtextextended('people.private:'||v_ticket.tenant_id||':'||v_ticket.legal_entity_id,0));
 perform people_private.content_available(v_ticket.tenant_id,v_ticket.legal_entity_id,v_ticket.employee_id,true);
 select * into v_doc from people_private.documents where id=v_ticket.document_id;
 if v_doc.checksum is distinct from p_checksum or v_doc.byte_size is distinct from p_byte_size
 or v_doc.status not in ('reserved','verified','active') then raise exception using errcode='22023',message='HR_DOCUMENT_BYTES_MISMATCH';end if;
 if v_doc.status='reserved' then update people_private.documents set status='verified',verified_at=clock_timestamp() where id=v_doc.id;end if;
 update people_private.document_tickets set verified_at=clock_timestamp() where id=p_ticket_id;
 return jsonb_build_object('verified',true);
end $$;
create function api.people_hr_worker_register(p_artifact_digest text,p_storage_probe_digest text) returns jsonb
language plpgsql security definer set search_path='' as $$begin
 perform people_private.service_only();
 if p_artifact_digest !~ '^[a-f0-9]{64}$' or p_storage_probe_digest !~ '^[a-f0-9]{64}$'
 or p_artifact_digest is null or p_storage_probe_digest is null then raise exception using errcode='22023',message='HR_WORKER_PROOF_INVALID';end if;
 insert into people_private.worker_readiness(contract,artifact_digest,storage_probe_digest)
 values('w4-private-hr-v1',p_artifact_digest,p_storage_probe_digest)
 on conflict(contract) do update set artifact_digest=excluded.artifact_digest,
 storage_probe_digest=excluded.storage_probe_digest,verified_at=clock_timestamp();
 return jsonb_build_object('contract','w4-private-hr-v1','ready',true);
end $$;
create function api.people_hr_worker_claim(p_limit integer default 50) returns jsonb
language plpgsql security definer set search_path='' as $$
declare v_employee record;v_job people_private.purge_jobs%rowtype;v_items jsonb:='[]';v_paths jsonb;v_lease uuid;v_candidates jsonb;begin
 perform people_private.service_only();
 if p_limit is null or p_limit not between 1 and 50 then raise exception using errcode='22023',message='HR_WORKER_LIMIT';end if;
 if not exists(select 1 from people_private.worker_readiness where contract='w4-private-hr-v1'
 and verified_at>now()-interval '26 hours') then raise exception using errcode='55000',message='HR_RETENTION_WORKER_UNAVAILABLE';end if;
 -- Discover without row locks, then use the same employee -> entity order as commands.
 select coalesce(jsonb_agg(to_jsonb(x)),'[]') into v_candidates from(
 select distinct tenant_id,legal_entity_id,employee_id from(
 select j.tenant_id,j.legal_entity_id,j.employee_id from people_private.purge_jobs j
 where j.status='pending' or (j.status='leased' and j.lease_until<=now())
 union
 select s.tenant_id,s.legal_entity_id,s.employee_id from(
 select tenant_id,legal_entity_id,employee_id from people_private.profiles where erased_at is null
 union select tenant_id,legal_entity_id,employee_id from people_private.documents where status<>'erased'
 union select tenant_id,legal_entity_id,employee_id from people_private.reviews where status<>'erased'
 union select tenant_id,legal_entity_id,employee_id from people_private.account_links where status in ('pending','accepted')
 ) s join people_private.policies p using(tenant_id,legal_entity_id)
 where p.closed_at+interval '30 days'<=now()
 ) q where not exists(select 1 from people_private.policies p where p.tenant_id=q.tenant_id
 and p.legal_entity_id=q.legal_entity_id and p.hold_reason is not null)
 order by tenant_id,legal_entity_id,employee_id limit p_limit) x;
 -- Acquire the entire batch's employee locks before any entity lock. A review
 -- command can lock both subject/reviewer, so per-item interleaving would deadlock.
 perform e.id from people.employees e where e.id in(
 select x.employee_id from jsonb_to_recordset(v_candidates) as x(employee_id uuid))
 order by e.id for update;
 for v_employee in select * from jsonb_to_recordset(v_candidates)
 as x(tenant_id uuid,legal_entity_id uuid,employee_id uuid) order by tenant_id,legal_entity_id,employee_id
 loop
 perform pg_advisory_xact_lock(hashtextextended('people.private:'||v_employee.tenant_id||':'||v_employee.legal_entity_id,0));
 if exists(select 1 from people_private.policies where tenant_id=v_employee.tenant_id
 and legal_entity_id=v_employee.legal_entity_id and hold_reason is not null) then continue;end if;
 insert into people_private.purge_jobs(tenant_id,legal_entity_id,employee_id)
 values(v_employee.tenant_id,v_employee.legal_entity_id,v_employee.employee_id)
 on conflict(tenant_id,legal_entity_id,employee_id) do nothing;
 select * into v_job from people_private.purge_jobs where tenant_id=v_employee.tenant_id
 and legal_entity_id=v_employee.legal_entity_id and employee_id=v_employee.employee_id for update;
 if v_job.status='complete' or (v_job.status='leased' and v_job.lease_until>now()) then continue;end if;
 v_lease:=gen_random_uuid();
 update people_private.purge_jobs set status='leased',lease_id=v_lease,lease_until=clock_timestamp()+interval '30 minutes' where id=v_job.id;
 update people_private.documents set status='erasing' where employee_id=v_job.employee_id and status<>'erased';
 select coalesce(jsonb_agg(object_path order by id),'[]') into v_paths from people_private.documents
 where employee_id=v_job.employee_id and object_path is not null;
 v_items:=v_items||jsonb_build_array(jsonb_build_object('job_id',v_job.id,'lease_id',v_lease,'object_paths',v_paths));
 end loop;
 delete from people_private.document_tickets where id in(select id from people_private.document_tickets
 where expires_at<now()-interval '3 minutes' order by expires_at limit 500);
 update people_private.worker_readiness set verified_at=clock_timestamp() where contract='w4-private-hr-v1';
 return jsonb_build_object('items',v_items);
end $$;
create function api.people_hr_worker_complete(p_job_id uuid,p_lease_id uuid) returns jsonb
language plpgsql security definer set search_path='' as $$
declare v_job people_private.purge_jobs%rowtype;v_profiles integer;v_reviews integer;v_docs integer;begin
 perform people_private.service_only();
 select * into v_job from people_private.purge_jobs where id=p_job_id;
 if not found then raise exception using errcode='42501',message='HR_PURGE_DENIED';end if;
 perform e.id from people.employees e where id=v_job.employee_id for update;
 perform pg_advisory_xact_lock(hashtextextended('people.private:'||v_job.tenant_id||':'||v_job.legal_entity_id,0));
 select * into v_job from people_private.purge_jobs where id=p_job_id for update;
 if v_job.lease_id is distinct from p_lease_id or v_job.status not in ('leased','complete')
 or (v_job.status='leased' and v_job.lease_until<=now()) then raise exception using errcode='42501',message='HR_PURGE_DENIED';end if;
 if v_job.status='complete' then return jsonb_build_object('job_id',p_job_id,'complete',true);end if;
 if exists(select 1 from people_private.policies where tenant_id=v_job.tenant_id and legal_entity_id=v_job.legal_entity_id
 and hold_reason is not null) then raise exception using errcode='55000',message='HR_LEGAL_HOLD';end if;
 perform set_config('people_private.purging','on',true);
 update people_private.profile_revisions set body=null,reason=null,redacted_at=clock_timestamp()
 where employee_id=v_job.employee_id and redacted_at is null;get diagnostics v_profiles=row_count;
 update people_private.profiles set erased_at=clock_timestamp() where employee_id=v_job.employee_id and erased_at is null;
 update people_private.review_revisions set body=null,reason=null,redacted_at=clock_timestamp()
 where employee_id=v_job.employee_id and redacted_at is null;get diagnostics v_reviews=row_count;
 update people_private.review_events set private_text=null,redacted_at=clock_timestamp()
 where employee_id=v_job.employee_id and redacted_at is null;
 update people_private.reviews set status='erased',erased_at=clock_timestamp() where employee_id=v_job.employee_id and status<>'erased';
 update people_private.documents set status='erased',object_path=null,purpose=null,erased_at=clock_timestamp()
 where employee_id=v_job.employee_id and status<>'erased';get diagnostics v_docs=row_count;
 insert into people_private.link_events(tenant_id,legal_entity_id,employee_id,link_id,event_type,actor_kind)
 select tenant_id,legal_entity_id,employee_id,id,'retention_revoked','system' from people_private.account_links
 where employee_id=v_job.employee_id and status in ('pending','accepted');
 update people_private.account_links set status='revoked',version=version+1 where employee_id=v_job.employee_id and status in ('pending','accepted');
 insert into people_private.erasure_events(tenant_id,legal_entity_id,employee_id,job_id,requested_by,contract,
 profile_revisions,review_revisions,documents) values(v_job.tenant_id,v_job.legal_entity_id,v_job.employee_id,
 p_job_id,v_job.requested_by,'w4-private-hr-v1',v_profiles,v_reviews,v_docs);
 update people_private.purge_jobs set status='complete',completed_at=clock_timestamp() where id=p_job_id;
 perform set_config('people_private.purging','off',true);
 return jsonb_build_object('job_id',p_job_id,'complete',true);
end $$;

-- Explicit denial for every private base table/function, including service role.
do $$declare v record;begin
 for v in select tablename from pg_tables where schemaname='people_private' loop
 execute format('alter table people_private.%I enable row level security',v.tablename);
 execute format('alter table people_private.%I force row level security',v.tablename);
 execute format('revoke all on people_private.%I from public,anon,authenticated,service_role',v.tablename);
 end loop;
 for v in select p.oid::regprocedure fn from pg_proc p join pg_namespace n on n.oid=p.pronamespace
 where n.nspname='people_private' or (n.nspname='api' and p.proname like 'people_hr_%') loop
 execute format('revoke all on function %s from public,anon,authenticated,service_role',v.fn);
 end loop;
 for v in select p.oid::regprocedure fn,p.proname from pg_proc p join pg_namespace n on n.oid=p.pronamespace
 where n.nspname='api' and p.proname like 'people_hr_%' loop
 if v.proname like 'people_hr_worker_%' or v.proname like 'people_hr_service_%' then
 execute format('grant execute on function %s to service_role',v.fn);
 else execute format('grant execute on function %s to authenticated',v.fn);end if;
 end loop;
end $$;
