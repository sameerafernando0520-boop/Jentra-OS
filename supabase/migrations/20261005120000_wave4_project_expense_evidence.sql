-- UNAPPLIED protected project-expense evidence candidate. No role/plan grants.
-- Separate privacy unit, bucket and worker; no core.files or private-HR linkage.
create schema expense_private;
revoke all on schema expense_private from public,anon,authenticated,service_role;
insert into core.permissions(code,module,description,privileged) values
 ('projects.expenses.evidence.view','projects','Read a scoped private expense evidence document',true),
 ('projects.expenses.evidence.export','projects','Export a scoped expense evidence document',true),
 ('projects.expenses.retention.manage','projects','Set expense evidence retention and document holds',true)
on conflict(code) do nothing;
create table expense_private.policies(
 id uuid primary key,tenant_id uuid not null,legal_entity_id uuid not null,
 retention_days integer not null check(retention_days between 1 and 3650),
 purpose text not null,digest_key bytea not null default extensions.gen_random_bytes(32),
 created_by uuid not null references auth.users(id),created_at timestamptz not null default clock_timestamp(),
 unique(tenant_id,legal_entity_id),foreign key(tenant_id,legal_entity_id) references core.legal_entities(tenant_id,id)
);
create table expense_private.documents(
 id uuid primary key,tenant_id uuid not null,legal_entity_id uuid not null,branch_id uuid not null,
 project_id uuid not null,expense_id uuid not null,policy_id uuid not null references expense_private.policies(id),
 version bigint not null default 1 check(version between 1 and 9007199254740990),
 content_version bigint not null default 1 check(content_version=1),digest text not null check(digest~'^[a-f0-9]{64}$'),
 mime text not null check(mime in('text/plain','image/png','image/jpeg','application/pdf')),
 byte_size integer not null check(byte_size between 1 and 10485760),checksum text not null check(checksum~'^[a-f0-9]{64}$'),
 purpose text not null,status text not null default 'reserved' check(status in('reserved','verified','active','retired','purging','purged')),
 created_by uuid not null references auth.users(id),created_at timestamptz not null default clock_timestamp(),
 verified_at timestamptz,activated_at timestamptz,retired_at timestamptz,purge_after timestamptz,purged_at timestamptz,
 hold_reason text,hold_review_date date,
 unique(tenant_id,legal_entity_id,branch_id,project_id,expense_id,id),
 foreign key(tenant_id,legal_entity_id,project_id) references projects.register(tenant_id,legal_entity_id,id),
 foreign key(tenant_id,legal_entity_id,branch_id) references core.branches(tenant_id,legal_entity_id,id),
 check((hold_reason is null)=(hold_review_date is null))
);
create table expense_private.events(
 id uuid primary key default gen_random_uuid(),tenant_id uuid not null,legal_entity_id uuid not null,
 document_id uuid not null references expense_private.documents(id),action text not null,
 version bigint not null,reason text,actor_id uuid references auth.users(id),recorded_at timestamptz not null default clock_timestamp()
);
create table expense_private.tickets(
 id uuid primary key default gen_random_uuid(),document_id uuid not null references expense_private.documents(id),
 user_id uuid not null references auth.users(id),operation text not null check(operation in('upload','download','export')),
 issued_aal text not null,expires_at timestamptz not null default clock_timestamp()+interval '30 seconds',
 consumed_at timestamptz,verified_at timestamptz
);
create table expense_private.worker_readiness(
 contract text primary key check(contract='w4-expense-evidence-v1'),artifact_digest text not null check(artifact_digest~'^[a-f0-9]{64}$'),
 storage_probe_digest text not null check(storage_probe_digest~'^[a-f0-9]{64}$'),verified_at timestamptz not null default clock_timestamp()
);
create table expense_private.purge_jobs(
 id uuid primary key default gen_random_uuid(),document_id uuid not null unique references expense_private.documents(id),
 lease_id uuid,lease_until timestamptz,status text not null default 'pending' check(status in('pending','complete')),
 completed_at timestamptz
);
create index expense_evidence_scope on expense_private.documents(tenant_id,legal_entity_id,branch_id,project_id,expense_id,id);
create index expense_evidence_expiry on expense_private.documents(status,purge_after,created_at);
create index expense_evidence_tickets_expiry on expense_private.tickets(expires_at);
create trigger immutable before update or delete on expense_private.policies for each row execute function projects.immutable();
create trigger immutable before update or delete on expense_private.events for each row execute function projects.immutable();
create function expense_private.document_guard() returns trigger language plpgsql set search_path='' as $$begin
 if tg_op='DELETE' or(to_jsonb(new)-array['version','status','verified_at','activated_at','retired_at','purge_after','purged_at','hold_reason','hold_review_date'])
  is distinct from(to_jsonb(old)-array['version','status','verified_at','activated_at','retired_at','purge_after','purged_at','hold_reason','hold_review_date']) then
  raise exception using errcode='55000',message='EXPENSE_EVIDENCE_IMMUTABLE';end if;
 return new;
end $$;
create trigger immutable_content before update or delete on expense_private.documents for each row execute function expense_private.document_guard();
insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types)
values('jentra-project-expense-private','jentra-project-expense-private',false,10485760,array['text/plain','image/png','image/jpeg','application/pdf']);
create policy wave4_expense_evidence_no_direct_storage on storage.objects as restrictive
 for all to anon,authenticated using(bucket_id<>'jentra-project-expense-private') with check(bucket_id<>'jentra-project-expense-private');

create function expense_private.lock_scope(t uuid,e uuid) returns void language plpgsql set search_path='' as $$begin
 perform pg_advisory_xact_lock(hashtextextended('people.payroll:'||t||':'||e,0));
 perform pg_advisory_xact_lock(hashtextextended('projects:'||t||':'||e,0));
 perform pg_advisory_xact_lock(hashtextextended('service:'||t||':'||e,0));
end $$;
create function expense_private.require_access(t uuid,e uuid,b uuid,p uuid,x uuid,cap text) returns void
language plpgsql security definer set search_path='' as $$begin
 perform projects.finance_access(t,e,b,'projects.cost.view',true);
 if cap not in('projects.cost.view','projects.expenses.manage','projects.expenses.evidence.view','projects.expenses.evidence.export','projects.expenses.retention.manage') then
  raise exception using errcode='42501',message='EXPENSE_EVIDENCE_DENIED';end if;
 perform core.wave3_require_scope(t,'projects.expenses.evidence.view',e,b);
 perform core.wave3_require_scope(t,cap,e,b);
 if p is not null and not exists(select 1 from projects.register r where r.tenant_id=t and r.legal_entity_id=e and r.branch_id=b and r.id=p) then
  raise exception using errcode='42501',message='EXPENSE_EVIDENCE_DENIED';end if;
 if x is not null and exists(select 1 from projects.expenses where id=x) and not exists(select 1 from projects.expenses z
  where z.tenant_id=t and z.legal_entity_id=e and z.branch_id=b and z.project_id=p and z.id=x) then
  raise exception using errcode='42501',message='EXPENSE_EVIDENCE_DENIED';end if;
end $$;
-- Service tickets recheck the actual human's current membership, scope, both
-- entitlements and MFA. Service credentials never stand in for human authority.
create function expense_private.user_has(t uuid,e uuid,b uuid,u uuid,cap text,aal text) returns boolean
language sql stable security definer set search_path='' as $$
 select aal='aal2' and exists(select 1 from core.memberships m join core.role_assignments a
  on a.tenant_id=m.tenant_id and a.membership_id=m.id join core.roles r on r.tenant_id=a.tenant_id and r.id=a.role_id
  join core.role_permissions rp on rp.tenant_id=r.tenant_id and rp.role_id=r.id
  where m.tenant_id=t and m.user_id=u and m.status='active' and rp.permission_code=cap
  and(a.legal_entity_id is null or a.legal_entity_id=e) and(a.branch_id is null or a.branch_id=b))
 and not exists(select 1 from unnest(array['module.projects','module.finance']) required where not exists(
  select 1 from billing.tenant_subscriptions s join billing.plan_entitlements pe on pe.plan_code=s.plan_code
  where s.tenant_id=t and pe.entitlement_code=required and pe.enabled and
  ((s.status='active' and(s.current_period_ends_at is null or s.current_period_ends_at>now())) or(s.status='trialing' and s.trial_ends_at>now()))))
 and exists(select 1 from core.tenants where id=t and status in('trial','active'))
 and exists(select 1 from core.legal_entities where tenant_id=t and id=e and status='active')
 and exists(select 1 from core.branches where tenant_id=t and legal_entity_id=e and id=b and status='active')
$$;
create function expense_private.service_only() returns void language plpgsql stable set search_path='' as $$begin
 if coalesce(auth.role(),'')<>'service_role' then raise exception using errcode='42501',message='EXPENSE_TRUSTED_SERVICE_REQUIRED';end if;
end $$;
create function expense_private.ready(t uuid,e uuid,w boolean default false) returns void language plpgsql stable security definer set search_path='' as $$begin
 if not exists(select 1 from expense_private.policies where tenant_id=t and legal_entity_id=e) then
  raise exception using errcode='55000',message='EXPENSE_RETENTION_POLICY_REQUIRED';end if;
 if w and not exists(select 1 from expense_private.worker_readiness where contract='w4-expense-evidence-v1' and verified_at>now()-interval '26 hours') then
  raise exception using errcode='55000',message='EXPENSE_RETENTION_WORKER_UNAVAILABLE';end if;
end $$;
create function expense_private.proof(d expense_private.documents) returns jsonb language sql immutable set search_path='' as $$
 select jsonb_build_object('id',d.id,'version',d.content_version,'digest',d.digest) $$;
create function expense_private.summary(d expense_private.documents) returns jsonb language sql immutable set search_path='' as $$
 select expense_private.proof(d)||jsonb_build_object('record_version',d.version,'status',d.status,'purpose',d.purpose,
  'mime',d.mime,'byte_size',d.byte_size,'checksum',d.checksum,'policy_id',d.policy_id,'retired_at',d.retired_at,
  'purge_after',d.purge_after,'hold_review_date',d.hold_review_date) $$;

-- Owner-only integration: empty evidence is explicit and remains valid for
-- synthetic narrative fixtures. Real proofs cannot be inferred from text/URLs.
create function projects.expense_evidence_assert(t uuid,e uuid,b uuid,p uuid,x uuid,proofs jsonb,mode text) returns jsonb
language plpgsql security definer set search_path='' as $$
declare v jsonb;d expense_private.documents%rowtype;outcome jsonb:='[]';seen uuid[]:='{}';begin
 if mode not in('freeze','read','decision') or jsonb_typeof(proofs) is distinct from 'array' or jsonb_array_length(proofs)>10 then
  raise exception using errcode='22023',message='EXPENSE_EVIDENCE_PROOF_INVALID';end if;
 perform projects.finance_access(t,e,b,'projects.cost.view',true);
 perform expense_private.lock_scope(t,e);
 if jsonb_array_length(proofs)=0 then return '[]';end if;
 perform expense_private.require_access(t,e,b,p,x,case when mode='freeze' then 'projects.expenses.manage' else 'projects.expenses.evidence.view' end);
 perform expense_private.ready(t,e,mode<>'read');
 for v in select value from jsonb_array_elements(proofs) loop
  if jsonb_typeof(v) is distinct from 'object' or not(v ?& array['id','version','digest'])
   or exists(select 1 from jsonb_object_keys(v) k where k<>all(array['id','version','digest']))
   or jsonb_typeof(v->'version') is distinct from 'number' or v->>'version'<>'1' or v->>'digest'!~'^[a-f0-9]{64}$' then
   raise exception using errcode='22023',message='EXPENSE_EVIDENCE_PROOF_INVALID';end if;
  if(v->>'id')::uuid=any(seen) then raise exception using errcode='22023',message='EXPENSE_EVIDENCE_PROOF_INVALID';end if;
  seen:=array_append(seen,(v->>'id')::uuid);
  select * into d from expense_private.documents where id=(v->>'id')::uuid and tenant_id=t and legal_entity_id=e
   and branch_id=b and project_id=p and expense_id=x for share;
  if d.id is null or expense_private.proof(d) is distinct from v then raise exception using errcode='40001',message='EXPENSE_EVIDENCE_CONFLICT';end if;
  -- Historical financial reads retain the original proof after an authorized
  -- retention purge; byte delivery and new decisions still require active data.
  if (mode='read' and d.status not in('active','retired','purging','purged')) or(mode<>'read' and d.status<>'active') then
   raise exception using errcode='55000',message='EXPENSE_EVIDENCE_CONTENT_UNAVAILABLE';end if;
  outcome:=outcome||jsonb_build_array(expense_private.proof(d));
 end loop;
 return(select coalesce(jsonb_agg(value order by value->>'id'),'[]') from jsonb_array_elements(outcome));
exception when invalid_text_representation then raise exception using errcode='22023',message='EXPENSE_EVIDENCE_PROOF_INVALID';
end $$;
create function api.projects_expense_evidence_access(p_tenant_id uuid,p_legal_entity_id uuid,p_branch_id uuid,p_project_id uuid,p_expense_id uuid,p_capability text default 'projects.expenses.evidence.view')
returns jsonb language plpgsql security definer set search_path='' as $$begin
 perform expense_private.require_access(p_tenant_id,p_legal_entity_id,p_branch_id,p_project_id,p_expense_id,p_capability);
 if p_project_id is null and p_capability='projects.expenses.retention.manage' then
  perform core.wave3_require_scope(p_tenant_id,'projects.expenses.retention.manage',p_legal_entity_id,null);end if;
 return jsonb_build_object('tenant_id',p_tenant_id,'legal_entity_id',p_legal_entity_id,'branch_id',p_branch_id,'project_id',p_project_id,
  'expense_id',p_expense_id,'actor_id',auth.uid(),'authorized',true,'available',exists(select 1 from expense_private.policies where tenant_id=p_tenant_id and legal_entity_id=p_legal_entity_id)
  and exists(select 1 from expense_private.worker_readiness where contract='w4-expense-evidence-v1' and verified_at>now()-interval '26 hours'));
end $$;
create function api.projects_expense_evidence_list(p_tenant_id uuid,p_legal_entity_id uuid,p_branch_id uuid,p_project_id uuid,p_expense_id uuid,p_after uuid default null)
returns jsonb language plpgsql security definer set search_path='' as $$declare rows jsonb;begin
 perform expense_private.require_access(p_tenant_id,p_legal_entity_id,p_branch_id,p_project_id,p_expense_id,'projects.expenses.evidence.view');
 select coalesce(jsonb_agg(expense_private.summary(d) order by d.id),'[]') into rows from(select * from expense_private.documents
  where tenant_id=p_tenant_id and legal_entity_id=p_legal_entity_id and branch_id=p_branch_id and project_id=p_project_id and expense_id=p_expense_id
  and(p_after is null or id>p_after) order by id limit 51) d;
 return jsonb_build_object('tenant_id',p_tenant_id,'legal_entity_id',p_legal_entity_id,'branch_id',p_branch_id,'project_id',p_project_id,
  'expense_id',p_expense_id,'items',rows-50,'next_after',case when jsonb_array_length(rows)>50 then rows->49->>'id' end);
end $$;

create function api.projects_expense_evidence_command(p_tenant_id uuid,p_legal_entity_id uuid,p_branch_id uuid,p_command_id uuid,p_idempotency_key uuid,
 p_issued_at timestamptz,p_payload jsonb,p_expected_version bigint) returns jsonb language plpgsql security definer set search_path='' as $$
#variable_conflict use_variable
declare act text:=p_payload->>'action';id uuid:=(p_payload->>'id')::uuid;p uuid:=(p_payload->>'project_id')::uuid;x uuid:=(p_payload->>'expense_id')::uuid;
 cap text;allowed text[];hash text;replay jsonb;result jsonb;d expense_private.documents%rowtype;policy expense_private.policies%rowtype;body jsonb;v_digest text;reason text;begin
 if jsonb_typeof(p_payload) is distinct from 'object' or octet_length(p_payload::text)>8192 or id is null or p_command_id is null or p_idempotency_key is null
  or p_issued_at is null or p_issued_at>clock_timestamp()+interval '5 minutes' or p_expected_version is null or p_expected_version not between 0 and 9007199254740990 then
  raise exception using errcode='22023',message='EXPENSE_EVIDENCE_COMMAND_INVALID';end if;
 cap:=case when act in('policy_create','hold','release_hold','retire') then 'projects.expenses.retention.manage'
  when act in('reserve','complete') then 'projects.expenses.manage' end;
 allowed:=case act when 'policy_create' then array['action','id','retention_days','purpose']
  when 'reserve' then array['action','id','project_id','expense_id','mime','byte_size','checksum','purpose']
  when 'complete' then array['action','id','project_id','expense_id']
  when 'hold' then array['action','id','project_id','expense_id','reason','review_date']
  when 'release_hold' then array['action','id','project_id','expense_id','reason']
  when 'retire' then array['action','id','project_id','expense_id','reason'] end;
 if cap is null or exists(select 1 from jsonb_object_keys(p_payload) k where k<>all(allowed)) or(act<>'policy_create' and(p is null or x is null)) then
  raise exception using errcode='22023',message='EXPENSE_EVIDENCE_FIELDS_INVALID';end if;
 perform expense_private.require_access(p_tenant_id,p_legal_entity_id,p_branch_id,p,x,cap);
 if act='policy_create' then perform core.wave3_require_scope(p_tenant_id,'projects.expenses.retention.manage',p_legal_entity_id,null);end if;
 perform expense_private.lock_scope(p_tenant_id,p_legal_entity_id);
 perform expense_private.require_access(p_tenant_id,p_legal_entity_id,p_branch_id,p,x,cap);
 if act='policy_create' then perform core.wave3_require_scope(p_tenant_id,'projects.expenses.retention.manage',p_legal_entity_id,null);end if;
 if act<>'policy_create' then perform expense_private.ready(p_tenant_id,p_legal_entity_id,act in('reserve','complete'));end if;
 hash:=core.wave3_request_hash('projects.expense_evidence.'||act,p_command_id,p_tenant_id,p_legal_entity_id,p_branch_id,p_payload,p_expected_version);
 -- Mutable permissions and worker readiness were checked before receipt replay.
 replay:=core.wave3_replay(p_tenant_id,'projects.expense_evidence.'||act,p_command_id,p_idempotency_key,hash);if replay is not null then return replay;end if;
 if act='policy_create' then
  if p_expected_version<>0 or jsonb_typeof(p_payload->'retention_days') is distinct from 'number' or p_payload->>'retention_days'!~'^[0-9]+$'
   or(p_payload->>'retention_days')::numeric not between 1 and 3650 or exists(select 1 from expense_private.policies where tenant_id=p_tenant_id and legal_entity_id=p_legal_entity_id) then
   raise exception using errcode='22023',message='EXPENSE_RETENTION_POLICY_INVALID';end if;
  insert into expense_private.policies(id,tenant_id,legal_entity_id,retention_days,purpose,created_by)
  values(id,p_tenant_id,p_legal_entity_id,(p_payload->>'retention_days')::integer,projects.text(p_payload->'purpose',160),auth.uid());
  result:=jsonb_build_object('id',id,'version',1,'action',act);
 else
  select * into policy from expense_private.policies where tenant_id=p_tenant_id and legal_entity_id=p_legal_entity_id;
  select * into d from expense_private.documents where documents.id=id and tenant_id=p_tenant_id and legal_entity_id=p_legal_entity_id
   and branch_id=p_branch_id and project_id=p and expense_id=x for update;
  if act='reserve' then
   if p_expected_version<>0 or d.id is not null or p_payload->>'mime' not in('text/plain','image/png','image/jpeg','application/pdf')
    or jsonb_typeof(p_payload->'byte_size') is distinct from 'number' or p_payload->>'byte_size'!~'^[0-9]+$'
    or(p_payload->>'byte_size')::numeric not between 1 and 10485760 or p_payload->>'checksum'!~'^[a-f0-9]{64}$'
    or p_payload->>'mime' is null or p_payload->>'checksum' is null then raise exception using errcode='22023',message='EXPENSE_EVIDENCE_METADATA_INVALID';end if;
   if(select count(*) from expense_private.documents where tenant_id=p_tenant_id and legal_entity_id=p_legal_entity_id and project_id=p and expense_id=x and status<>'purged')>=10 then
    raise exception using errcode='55000',message='EXPENSE_EVIDENCE_DOCUMENT_LIMIT';end if;
   if exists(select 1 from projects.expenses where expenses.id=x and status not in('draft','rejected')) then raise exception using errcode='55000',message='EXPENSE_EVIDENCE_SOURCE_IMMUTABLE';end if;
   body:=jsonb_build_object('tenant_id',p_tenant_id,'legal_entity_id',p_legal_entity_id,'branch_id',p_branch_id,'project_id',p,'expense_id',x,
    'id',id,'version',1,'mime',p_payload->>'mime','byte_size',(p_payload->>'byte_size')::integer,'checksum',p_payload->>'checksum','policy_id',policy.id);
   v_digest:=encode(extensions.hmac(convert_to(body::text,'UTF8'),policy.digest_key,'sha256'),'hex');
   insert into expense_private.documents(id,tenant_id,legal_entity_id,branch_id,project_id,expense_id,policy_id,digest,mime,byte_size,checksum,purpose,created_by)
    values(id,p_tenant_id,p_legal_entity_id,p_branch_id,p,x,policy.id,v_digest,p_payload->>'mime',(p_payload->>'byte_size')::integer,p_payload->>'checksum',projects.text(p_payload->'purpose',160),auth.uid()) returning * into d;
  else
   if d.id is null or d.version<>p_expected_version then raise exception using errcode='40001',message='EXPENSE_EVIDENCE_CONFLICT';end if;
   if d.status in('purging','purged') then raise exception using errcode='55000',message='EXPENSE_EVIDENCE_CONTENT_UNAVAILABLE';end if;
   if act='complete' then
    if d.status<>'verified' or d.verified_at is null then raise exception using errcode='55000',message='EXPENSE_EVIDENCE_VERIFICATION_REQUIRED';end if;
    update expense_private.documents set status='active',version=version+1,activated_at=clock_timestamp() where documents.id=id returning * into d;
   elsif act='hold' then
    reason:=projects.text(p_payload->'reason',1000);
    if(p_payload->>'review_date')::date<current_date or(p_payload->>'review_date')::date>current_date+366 or p_payload->>'review_date' is null then
     raise exception using errcode='22023',message='EXPENSE_RETENTION_HOLD_INVALID';end if;
    update expense_private.documents set hold_reason=reason,hold_review_date=(p_payload->>'review_date')::date,version=version+1 where documents.id=id returning * into d;
   elsif act='release_hold' then
    reason:=projects.text(p_payload->'reason',1000);
    if d.hold_reason is null then raise exception using errcode='55000',message='EXPENSE_RETENTION_HOLD_REQUIRED';end if;
    update expense_private.documents set hold_reason=null,hold_review_date=null,version=version+1 where documents.id=id returning * into d;
   elsif act='retire' then
    reason:=projects.text(p_payload->'reason',1000);
    if d.status not in('reserved','verified','active') or not exists(select 1 from projects.expenses z where z.id=x and z.tenant_id=p_tenant_id
     and z.legal_entity_id=p_legal_entity_id and z.branch_id=p_branch_id and z.project_id=p and z.status in('cancelled','rejected','reversed')) then
     raise exception using errcode='55000',message='EXPENSE_FINANCIAL_RETENTION_REQUIRED';end if;
    update expense_private.documents set status='retired',version=version+1,retired_at=clock_timestamp(),purge_after=clock_timestamp()+make_interval(days=>policy.retention_days)
     where documents.id=id returning * into d;
   end if;
  end if;
  insert into expense_private.events(tenant_id,legal_entity_id,document_id,action,version,reason,actor_id)
   values(p_tenant_id,p_legal_entity_id,id,act,d.version,reason,auth.uid());
  result:=expense_private.proof(d)||jsonb_build_object('record_version',d.version,'status',d.status,'project_id',p,'expense_id',x,'action',act);
 end if;
 result:=result||jsonb_build_object('tenant_id',p_tenant_id,'legal_entity_id',p_legal_entity_id,'branch_id',p_branch_id);
 return core.wave3_finish_command(p_tenant_id,'projects.expense_evidence.'||act,p_command_id,'projects.expense_evidence',id,p_idempotency_key,hash,'{}',result,p_legal_entity_id,p_branch_id);
exception when invalid_text_representation or invalid_datetime_format or datetime_field_overflow or numeric_value_out_of_range then
 raise exception using errcode='22023',message='EXPENSE_EVIDENCE_FIELDS_INVALID';
end $$;

create function api.projects_expense_evidence_ticket(p_tenant_id uuid,p_legal_entity_id uuid,p_branch_id uuid,p_project_id uuid,p_expense_id uuid,p_document_id uuid,p_operation text)
returns jsonb language plpgsql security definer set search_path='' as $$declare d expense_private.documents%rowtype;ticket uuid;begin
 if p_operation not in('upload','download','export') or p_operation is null then raise exception using errcode='22023',message='EXPENSE_EVIDENCE_OPERATION_INVALID';end if;
 perform expense_private.require_access(p_tenant_id,p_legal_entity_id,p_branch_id,p_project_id,p_expense_id,
  case when p_operation='upload' then 'projects.expenses.manage' when p_operation='export' then 'projects.expenses.evidence.export' else 'projects.cost.view' end);
 perform expense_private.lock_scope(p_tenant_id,p_legal_entity_id);
 perform expense_private.ready(p_tenant_id,p_legal_entity_id,p_operation='upload');
 select * into d from expense_private.documents where id=p_document_id and tenant_id=p_tenant_id and legal_entity_id=p_legal_entity_id
  and branch_id=p_branch_id and project_id=p_project_id and expense_id=p_expense_id for share;
 if d.id is null or(p_operation='upload' and d.status not in('reserved','verified','active')) or(p_operation<>'upload' and d.status<>'active') then
  raise exception using errcode='42501',message='EXPENSE_EVIDENCE_DENIED';end if;
 insert into expense_private.tickets(document_id,user_id,operation,issued_aal) values(d.id,auth.uid(),p_operation,coalesce(auth.jwt()->>'aal','aal1')) returning id into ticket;
 return jsonb_build_object('ticket_id',ticket,'expires_at',clock_timestamp()+interval '30 seconds');
end $$;
create function api.projects_expense_evidence_own_receipt(p_tenant_id uuid,p_legal_entity_id uuid,p_branch_id uuid,p_command_id uuid)
returns jsonb language plpgsql security definer set search_path='' as $$declare r core.command_receipts%rowtype;act text;cap text;begin
 perform projects.finance_access(p_tenant_id,p_legal_entity_id,p_branch_id,'projects.cost.view',true);
 select * into r from core.command_receipts where tenant_id=p_tenant_id and legal_entity_id=p_legal_entity_id and branch_id=p_branch_id
  and actor_id=auth.uid() and command_id=p_command_id and command_name like 'projects.expense_evidence.%';
 if r.command_id is null then return null;end if;
 act:=r.response->'entity'->>'action';
 cap:=case when act in('policy_create','hold','release_hold','retire') then 'projects.expenses.retention.manage' else 'projects.expenses.manage' end;
 perform expense_private.require_access(p_tenant_id,p_legal_entity_id,p_branch_id,(r.response->'entity'->>'project_id')::uuid,
  (r.response->'entity'->>'expense_id')::uuid,cap);
 if act='policy_create' then perform core.wave3_require_scope(p_tenant_id,'projects.expenses.retention.manage',p_legal_entity_id,null);end if;
 if act in('reserve','complete') then perform expense_private.ready(p_tenant_id,p_legal_entity_id,true);end if;
 return r.response;
end $$;
create function expense_private.ticket_authority(v expense_private.tickets,d expense_private.documents,u uuid) returns void language plpgsql security definer set search_path='' as $$begin
 if v.id is null or d.id is null or v.user_id is distinct from u or not expense_private.user_has(d.tenant_id,d.legal_entity_id,d.branch_id,u,'projects.view',v.issued_aal)
  or not expense_private.user_has(d.tenant_id,d.legal_entity_id,d.branch_id,u,'projects.cost.view',v.issued_aal)
  or not expense_private.user_has(d.tenant_id,d.legal_entity_id,d.branch_id,u,'projects.expenses.evidence.view',v.issued_aal)
  or not expense_private.user_has(d.tenant_id,d.legal_entity_id,d.branch_id,u,
   case when v.operation='upload' then 'projects.expenses.manage' when v.operation='export' then 'projects.expenses.evidence.export' else 'projects.cost.view' end,v.issued_aal)
  or not exists(select 1 from projects.register where tenant_id=d.tenant_id and legal_entity_id=d.legal_entity_id and branch_id=d.branch_id and id=d.project_id) then
  raise exception using errcode='42501',message='EXPENSE_EVIDENCE_DENIED';end if;
end $$;
create function api.projects_expense_evidence_service_document(p_ticket_id uuid,p_user_id uuid) returns jsonb language plpgsql security definer set search_path='' as $$
declare v expense_private.tickets%rowtype;d expense_private.documents%rowtype;begin
 perform expense_private.service_only();
 select * into v from expense_private.tickets where id=p_ticket_id;select * into d from expense_private.documents where id=v.document_id;
 perform expense_private.lock_scope(d.tenant_id,d.legal_entity_id);
 select * into v from expense_private.tickets where id=p_ticket_id for update;select * into d from expense_private.documents where id=v.document_id for share;
 perform expense_private.ticket_authority(v,d,p_user_id);
 if v.expires_at<=clock_timestamp() or v.consumed_at is not null or(v.operation='upload' and d.status not in('reserved','verified','active'))
  or(v.operation<>'upload' and d.status<>'active') then raise exception using errcode='42501',message='EXPENSE_EVIDENCE_DENIED';end if;
 perform expense_private.ready(d.tenant_id,d.legal_entity_id,v.operation='upload');
 update expense_private.tickets set consumed_at=clock_timestamp() where id=p_ticket_id;
 return expense_private.summary(d)||jsonb_build_object('ticket_id',v.id,'document_id',d.id,'tenant_id',d.tenant_id,'legal_entity_id',d.legal_entity_id,
  'branch_id',d.branch_id,'project_id',d.project_id,'expense_id',d.expense_id,'operation',v.operation,
  'object_path',d.tenant_id||'/'||d.legal_entity_id||'/'||d.project_id||'/'||d.expense_id||'/'||d.id);
end $$;
create function api.projects_expense_evidence_service_verify(p_ticket_id uuid,p_user_id uuid,p_checksum text,p_byte_size integer) returns jsonb
language plpgsql security definer set search_path='' as $$declare v expense_private.tickets%rowtype;d expense_private.documents%rowtype;begin
 perform expense_private.service_only();select * into v from expense_private.tickets where id=p_ticket_id;select * into d from expense_private.documents where id=v.document_id;
 perform expense_private.lock_scope(d.tenant_id,d.legal_entity_id);
 select * into v from expense_private.tickets where id=p_ticket_id for update;select * into d from expense_private.documents where id=v.document_id for update;
 perform expense_private.ticket_authority(v,d,p_user_id);
 if v.operation<>'upload' or v.consumed_at is null or v.expires_at+interval '2 minutes'<=clock_timestamp() or d.status not in('reserved','verified','active') then
  raise exception using errcode='42501',message='EXPENSE_EVIDENCE_DENIED';end if;
 perform expense_private.ready(d.tenant_id,d.legal_entity_id,true);
 if d.checksum is distinct from p_checksum or d.byte_size is distinct from p_byte_size then raise exception using errcode='22023',message='EXPENSE_EVIDENCE_BYTES_MISMATCH';end if;
 if d.status='reserved' then update expense_private.documents set status='verified',verified_at=clock_timestamp() where id=d.id;end if;
 update expense_private.tickets set verified_at=clock_timestamp() where id=p_ticket_id;return jsonb_build_object('verified',true);
end $$;
create function api.projects_expense_evidence_worker_register(p_artifact_digest text,p_storage_probe_digest text) returns jsonb language plpgsql security definer set search_path='' as $$begin
 perform expense_private.service_only();
 if p_artifact_digest is null or p_storage_probe_digest is null or p_artifact_digest!~'^[a-f0-9]{64}$' or p_storage_probe_digest!~'^[a-f0-9]{64}$' then
  raise exception using errcode='22023',message='EXPENSE_WORKER_PROOF_INVALID';end if;
 insert into expense_private.worker_readiness(contract,artifact_digest,storage_probe_digest) values('w4-expense-evidence-v1',p_artifact_digest,p_storage_probe_digest)
 on conflict(contract) do update set artifact_digest=excluded.artifact_digest,storage_probe_digest=excluded.storage_probe_digest,verified_at=clock_timestamp();
 return jsonb_build_object('contract','w4-expense-evidence-v1','ready',true);
end $$;
create function api.projects_expense_evidence_worker_claim(p_limit integer default 50) returns jsonb language plpgsql security definer set search_path='' as $$
declare candidate record;d expense_private.documents%rowtype;j expense_private.purge_jobs%rowtype;lease uuid;items jsonb:='[]';begin
 perform expense_private.service_only();
 if p_limit is null or p_limit not between 1 and 50 then raise exception using errcode='22023',message='EXPENSE_WORKER_LIMIT';end if;
 if not exists(select 1 from expense_private.worker_readiness where verified_at>now()-interval '26 hours') then
  raise exception using errcode='55000',message='EXPENSE_RETENTION_WORKER_UNAVAILABLE';end if;
 -- Bound the scan as well as response. No document lock precedes entity locks.
 for candidate in select id,tenant_id,legal_entity_id from expense_private.documents where hold_reason is null and
  ((status='retired' and purge_after<=clock_timestamp()) or(status in('reserved','verified') and created_at<clock_timestamp()-interval '24 hours') or status='purging')
  order by tenant_id,legal_entity_id,id limit 50 loop
  exit when jsonb_array_length(items)>=p_limit;
  perform expense_private.lock_scope(candidate.tenant_id,candidate.legal_entity_id);
  select * into d from expense_private.documents where id=candidate.id for update skip locked;
  if d.id is null or d.hold_reason is not null or not((d.status='retired' and d.purge_after<=clock_timestamp())
   or(d.status in('reserved','verified') and d.created_at<clock_timestamp()-interval '24 hours') or d.status='purging') then continue;end if;
  if exists(select 1 from projects.expenses z where z.id=d.expense_id and z.status not in('cancelled','rejected','reversed')) then continue;end if;
  insert into expense_private.purge_jobs(document_id) values(d.id) on conflict(document_id) do nothing;
  select * into j from expense_private.purge_jobs where document_id=d.id for update;
  if j.status='complete' or j.lease_until>clock_timestamp() then continue;end if;
  lease:=gen_random_uuid();update expense_private.purge_jobs set lease_id=lease,lease_until=clock_timestamp()+interval '30 minutes' where id=j.id;
  if d.status<>'purging' then update expense_private.documents set status='purging',version=version+1 where id=d.id;end if;
  items:=items||jsonb_build_array(jsonb_build_object('job_id',j.id,'lease_id',lease,'object_paths',jsonb_build_array(
   d.tenant_id||'/'||d.legal_entity_id||'/'||d.project_id||'/'||d.expense_id||'/'||d.id)));
 end loop;
 delete from expense_private.tickets where id in(select id from expense_private.tickets where expires_at<now()-interval '3 minutes' order by expires_at limit 500);
 return jsonb_build_object('items',items);
end $$;
create function api.projects_expense_evidence_worker_complete(p_job_id uuid,p_lease_id uuid) returns jsonb language plpgsql security definer set search_path='' as $$
declare j expense_private.purge_jobs%rowtype;d expense_private.documents%rowtype;begin
 perform expense_private.service_only();select * into j from expense_private.purge_jobs where id=p_job_id;select * into d from expense_private.documents where id=j.document_id;
 perform expense_private.lock_scope(d.tenant_id,d.legal_entity_id);
 select * into d from expense_private.documents where id=j.document_id for update;select * into j from expense_private.purge_jobs where id=p_job_id for update;
 if j.id is null or j.status<>'pending' or j.lease_id is distinct from p_lease_id or j.lease_until<=clock_timestamp() or d.status<>'purging' or d.hold_reason is not null then
  raise exception using errcode='42501',message='EXPENSE_WORKER_LEASE_INVALID';end if;
 update expense_private.documents set status='purged',version=version+1,purged_at=clock_timestamp() where id=d.id;
 insert into expense_private.events(tenant_id,legal_entity_id,document_id,action,version) values(d.tenant_id,d.legal_entity_id,d.id,'purged',d.version+1);
 update expense_private.purge_jobs set status='complete',completed_at=clock_timestamp(),lease_until=null where id=j.id;
 return jsonb_build_object('job_id',j.id,'complete',true);
end $$;
do $$declare v record;begin
 for v in select tablename from pg_tables where schemaname='expense_private' loop
  execute format('alter table expense_private.%I enable row level security',v.tablename);
  execute format('alter table expense_private.%I force row level security',v.tablename);
  execute format('revoke all on expense_private.%I from public,anon,authenticated,service_role',v.tablename);
 end loop;
 for v in select p.oid::regprocedure fn,p.proname,n.nspname from pg_proc p join pg_namespace n on n.oid=p.pronamespace
  where n.nspname='expense_private' or(n.nspname='api' and p.proname like 'projects_expense_evidence_%')
  or(n.nspname='projects' and p.proname='expense_evidence_assert') loop
  execute format('revoke all on function %s from public,anon,authenticated,service_role',v.fn);
  if v.nspname='api' then
   if v.proname like 'projects_expense_evidence_worker_%' or v.proname like 'projects_expense_evidence_service_%' then
    execute format('grant execute on function %s to service_role',v.fn);
   else execute format('grant execute on function %s to authenticated',v.fn);end if;
  end if;
 end loop;
end $$;
