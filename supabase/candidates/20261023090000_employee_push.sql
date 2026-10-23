-- CANDIDATE ONLY. Not an applied migration; requires independent review and
-- explicit hosted installation approval. No plan/role grants or HR producer.
-- p_token/token are compatibility names for the opaque Firebase Installation
-- ID returned by Messaging.register(); the HTTP v1 sender uses message.fid.
create schema employee_push;
revoke all on schema employee_push from public, anon, authenticated, service_role;

create table employee_push.devices (
 installation_id uuid primary key,
 tenant_id uuid not null, legal_entity_id uuid not null, branch_id uuid not null,
 user_id uuid not null references auth.users(id) on delete cascade,
 session_id uuid not null references auth.sessions(id) on delete cascade,
 membership_id uuid not null, employee_id uuid not null, link_id uuid not null,
 link_version bigint not null, aal text not null check(aal in ('aal1','aal2')),
 platform text not null check(platform='android'),
 token text check(token is null or (length(token) between 20 and 4096 and token !~ '[[:space:][:cntrl:]]')),
 token_hash text unique check(token_hash is null or token_hash ~ '^[a-f0-9]{64}$'),
 version bigint not null default 1 check(version>0),
 status text not null check(status in ('active','removed','invalid')),
 check((status='active' and token is not null and token_hash is not null)
  or (status<>'active' and token is null and token_hash is null)),
 expires_at timestamptz not null, updated_at timestamptz not null default clock_timestamp(),
 foreign key(tenant_id,membership_id) references core.memberships(tenant_id,id),
 foreign key(tenant_id,legal_entity_id,branch_id) references core.branches(tenant_id,legal_entity_id,id),
 foreign key(tenant_id,legal_entity_id,employee_id,link_id)
  references people_private.account_links(tenant_id,legal_entity_id,employee_id,id)
);
create index employee_push_devices_recipient_idx on employee_push.devices(tenant_id,user_id,status,expires_at);

create table employee_push.receipts (
 user_id uuid not null references auth.users(id) on delete cascade,
 session_id uuid not null references auth.sessions(id) on delete cascade,
 command_id uuid not null, request_hash text not null, response jsonb not null,
 created_at timestamptz not null default clock_timestamp(),
 primary key(user_id,session_id,command_id)
);
create table employee_push.deliveries (
 id uuid primary key default gen_random_uuid(),
 notification_id uuid not null references workflow.notifications(id) on delete cascade,
 installation_id uuid not null references employee_push.devices(installation_id) on delete cascade,
 binding_version bigint not null,
 state text not null default 'pending' check(state in ('pending','leased','sent','skipped','dead')),
 attempt integer not null default 0 check(attempt between 0 and 5),
 available_at timestamptz not null default clock_timestamp(),
 lease_id uuid, lease_until timestamptz,
 result_code text check(result_code in ('sent','retry','invalid_token','permanent','binding_inactive','attempts_exhausted')),
 created_at timestamptz not null default clock_timestamp(), completed_at timestamptz,
 unique(notification_id,installation_id)
);
create index employee_push_receipts_retention_idx on employee_push.receipts(created_at);
create index employee_push_deliveries_due_idx on employee_push.deliveries(state,available_at,lease_until,id);
create index employee_push_deliveries_retention_idx on employee_push.deliveries(completed_at,id)
 where state in ('sent','skipped','dead');
alter table employee_push.devices enable row level security;
alter table employee_push.devices force row level security;
alter table employee_push.receipts enable row level security;
alter table employee_push.receipts force row level security;
alter table employee_push.deliveries enable row level security;
alter table employee_push.deliveries force row level security;
revoke all on all tables in schema employee_push from public,anon,authenticated,service_role;

-- No JWT/session supplied by the caller is trusted as an argument.
create function employee_push.session() returns uuid
language plpgsql stable security definer set search_path='' as $$
declare s uuid;begin
 if auth.uid() is null or coalesce(auth.jwt()->>'session_id','') !~
  '^[a-fA-F0-9]{8}-[a-fA-F0-9]{4}-[a-fA-F0-9]{4}-[a-fA-F0-9]{4}-[a-fA-F0-9]{12}$' then
  raise exception using errcode='42501',message='PUSH_SESSION_REQUIRED';end if;
 s:=(auth.jwt()->>'session_id')::uuid;
 if not exists(select 1 from auth.sessions a where a.id=s and a.user_id=auth.uid()
  and (a.not_after is null or a.not_after>statement_timestamp())) then
  raise exception using errcode='42501',message='PUSH_SESSION_REQUIRED';end if;
 return s;
end $$;

-- Worker-side revalidation does not impersonate a user or SET request claims.
-- Permissions and role MFA are checked against the captured verified session AAL.
create function employee_push.binding_current(d employee_push.devices) returns boolean
language sql stable security definer set search_path='' as $$
 select d.status='active' and d.expires_at>statement_timestamp()
 and exists(select 1 from auth.sessions s where s.id=d.session_id and s.user_id=d.user_id
  and (s.not_after is null or s.not_after>statement_timestamp()))
 and exists(
  select 1 from people_private.account_links l
  join core.memberships m on m.id=l.membership_id and m.tenant_id=l.tenant_id and m.user_id=l.user_id
  join core.tenants t on t.id=l.tenant_id
  join core.legal_entities e on e.tenant_id=l.tenant_id and e.id=l.legal_entity_id
  join core.branches b on b.tenant_id=l.tenant_id and b.legal_entity_id=l.legal_entity_id and b.id=l.branch_id
  where l.id=d.link_id and l.version=d.link_version and l.status='accepted'
   and l.tenant_id=d.tenant_id and l.legal_entity_id=d.legal_entity_id and l.branch_id=d.branch_id
   and l.employee_id=d.employee_id and l.user_id=d.user_id and l.membership_id=d.membership_id
   and m.status='active' and t.status in ('active','trial') and e.status='active' and b.status='active'
   and exists(select 1 from people.employment_assignments a
    where a.tenant_id=d.tenant_id and a.legal_entity_id=d.legal_entity_id and a.branch_id=d.branch_id
     and a.employee_id=d.employee_id and a.start_date<=(statement_timestamp() at time zone e.timezone)::date
     and (a.end_date_exclusive is null or a.end_date_exclusive>(statement_timestamp() at time zone e.timezone)::date))
 )
 and exists(select 1 from billing.tenant_subscriptions s join billing.plan_entitlements p on p.plan_code=s.plan_code
  where s.tenant_id=d.tenant_id and p.entitlement_code='module.people' and p.enabled
   and ((s.status='trialing' and s.trial_ends_at>statement_timestamp())
    or (s.status='active' and (s.current_period_ends_at is null or s.current_period_ends_at>statement_timestamp()))))
 and not exists(select 1 from unnest(array['people.view','people.self.view']) required(cap)
  where not exists(select 1 from core.role_assignments ra
   join core.roles r on r.tenant_id=ra.tenant_id and r.id=ra.role_id
   join core.role_permissions rp on rp.tenant_id=r.tenant_id and rp.role_id=r.id
   where ra.tenant_id=d.tenant_id and ra.membership_id=d.membership_id and rp.permission_code=required.cap
    and (ra.legal_entity_id is null or ra.legal_entity_id=d.legal_entity_id)
    and (ra.branch_id is null or ra.branch_id=d.branch_id) and (not r.requires_mfa or d.aal='aal2')))
$$;

create function api.employee_push_register(p_tenant_id uuid,p_legal_entity_id uuid,p_branch_id uuid,
 p_installation_id uuid,p_token text,p_platform text,p_command_id uuid) returns jsonb
language plpgsql security definer set search_path='' as $$
declare s uuid;l people_private.account_links%rowtype;d employee_push.devices%rowtype;
 h text;th text;cached employee_push.receipts%rowtype;answer jsonb;old_version bigint;rotate_current boolean;begin
 s:=employee_push.session();
 if p_tenant_id is null or p_legal_entity_id is null or p_branch_id is null or p_installation_id is null
  or p_command_id is null or p_platform is distinct from 'android' or p_token is null
  or length(p_token) not between 20 and 4096 or p_token ~ '[[:space:][:cntrl:]]' then
  raise exception using errcode='22023',message='PUSH_REGISTRATION_INVALID';end if;
 perform people.require_access(p_tenant_id,p_legal_entity_id,p_branch_id,'people.self.view');
 select a.* into l from people_private.account_links a join core.memberships m
  on m.id=a.membership_id and m.tenant_id=a.tenant_id and m.user_id=a.user_id and m.status='active'
  where a.tenant_id=p_tenant_id and a.legal_entity_id=p_legal_entity_id and a.branch_id=p_branch_id
   and a.user_id=auth.uid() and a.status='accepted';
 if l.id is null then raise exception using errcode='42501',message='PUSH_ACTIVE_LINK_REQUIRED';end if;
 th:=encode(extensions.digest(convert_to(p_token,'UTF8'),'sha256'),'hex');
 h:=encode(extensions.digest(convert_to(jsonb_build_array('register',p_tenant_id,p_legal_entity_id,p_branch_id,
  p_installation_id,th,p_platform)::text,'UTF8'),'sha256'),'hex');
 -- Serialize device changes and the receipt identity independently, including
 -- concurrent first use. UUID hashes are locking keys, not authentication.
 perform pg_advisory_xact_lock(hashtextextended('employee-push-command:'||auth.uid()::text||s::text||p_command_id::text,0));
 select * into cached from employee_push.receipts where user_id=auth.uid() and session_id=s and command_id=p_command_id;
 if found then
  if cached.request_hash<>h then raise exception using errcode='22023',message='PUSH_COMMAND_REUSED';end if;
  return cached.response;end if;
 perform pg_advisory_xact_lock(hashtextextended('employee-push-user:'||auth.uid()::text,0));
 perform pg_advisory_xact_lock(hashtextextended('employee-push-device:'||p_installation_id::text,0));
 select * into d from employee_push.devices where installation_id=p_installation_id for update;
 if d.installation_id is not null and d.status='active' and d.expires_at>statement_timestamp()
  and (d.user_id<>auth.uid() or d.session_id<>s) and d.token_hash<>th then
  raise exception using errcode='42501',message='PUSH_INSTALLATION_BOUND';end if;
 if exists(select 1 from employee_push.devices where token_hash=th and installation_id<>p_installation_id) then
  raise exception using errcode='42501',message='PUSH_TOKEN_BOUND';end if;
 if (d.installation_id is null or d.user_id<>auth.uid() or d.status<>'active' or d.expires_at<=statement_timestamp())
  and (select count(*) from employee_push.devices
  where user_id=auth.uid() and status='active' and expires_at>statement_timestamp())>=10 then
  raise exception using errcode='54000',message='PUSH_DEVICE_LIMIT';end if;
 old_version:=d.version;
 rotate_current:=d.user_id=auth.uid() and d.session_id=s and d.link_id=l.id and d.link_version=l.version
  and d.tenant_id=p_tenant_id and d.legal_entity_id=p_legal_entity_id and d.branch_id=p_branch_id;
 d.installation_id:=p_installation_id;d.tenant_id:=p_tenant_id;d.legal_entity_id:=p_legal_entity_id;d.branch_id:=p_branch_id;
 d.user_id:=auth.uid();d.session_id:=s;d.membership_id:=l.membership_id;d.employee_id:=l.employee_id;
 d.link_id:=l.id;d.link_version:=l.version;d.aal:=case when auth.jwt()->>'aal'='aal2' then 'aal2' else 'aal1' end;
 d.platform:='android';d.token:=p_token;d.token_hash:=th;d.version:=coalesce(d.version,0)+1;
 d.status:='active';d.expires_at:=clock_timestamp()+interval '24 hours';d.updated_at:=clock_timestamp();
 if not employee_push.binding_current(d) then raise exception using errcode='42501',message='PUSH_SCOPE_DENIED';end if;
 insert into employee_push.devices select d.* on conflict(installation_id) do update set
  tenant_id=excluded.tenant_id,legal_entity_id=excluded.legal_entity_id,branch_id=excluded.branch_id,
  user_id=excluded.user_id,session_id=excluded.session_id,membership_id=excluded.membership_id,
  employee_id=excluded.employee_id,link_id=excluded.link_id,link_version=excluded.link_version,aal=excluded.aal,
  platform=excluded.platform,token=excluded.token,token_hash=excluded.token_hash,version=excluded.version,
  status=excluded.status,expires_at=excluded.expires_at,updated_at=excluded.updated_at;
 -- Only pending wakes for this exact recipient/link/session survive rotation.
 -- Leased/in-flight sends are not retargeted to a replacement binding.
 update employee_push.deliveries x set binding_version=d.version
  from workflow.notifications n
  where x.installation_id=p_installation_id and x.binding_version=old_version and x.state='pending'
   and n.id=x.notification_id and n.recipient_id=d.user_id and n.tenant_id=d.tenant_id
   and n.legal_entity_id=d.legal_entity_id and n.branch_id=d.branch_id
   and rotate_current;
 answer:=jsonb_build_object('installation_id',d.installation_id,'version',d.version,'status','active','expires_at',d.expires_at);
 insert into employee_push.receipts(user_id,session_id,command_id,request_hash,response) values(auth.uid(),s,p_command_id,h,answer);
 return answer;
exception when unique_violation then raise exception using errcode='42501',message='PUSH_BINDING_CONFLICT';
end $$;

-- No People/link/plan check here: a signed-in actor must be able to remove their
-- own current-session binding even after HR access was revoked.
create function api.employee_push_remove(p_installation_id uuid,p_command_id uuid) returns jsonb
language plpgsql security definer set search_path='' as $$
declare s uuid;h text;r employee_push.receipts%rowtype;answer jsonb;affected integer;begin
 s:=employee_push.session();
 if p_installation_id is null or p_command_id is null then
  raise exception using errcode='22023',message='PUSH_REMOVAL_INVALID';end if;
 h:=encode(extensions.digest(convert_to(jsonb_build_array('remove',p_installation_id)::text,'UTF8'),'sha256'),'hex');
 perform pg_advisory_xact_lock(hashtextextended('employee-push-command:'||auth.uid()::text||s::text||p_command_id::text,0));
 select * into r from employee_push.receipts where user_id=auth.uid() and session_id=s and command_id=p_command_id;
 if found then
  if r.request_hash<>h then raise exception using errcode='22023',message='PUSH_COMMAND_REUSED';end if;
  perform pg_advisory_xact_lock(hashtextextended('employee-push-device:'||p_installation_id::text,0));
  -- A historic removal ACK does not prove a later registration is inactive.
  -- Refresh only this own-session proof; replay must not revoke a new binding.
  return r.response||jsonb_build_object('removed',exists(select 1 from employee_push.devices
   where installation_id=p_installation_id and user_id=auth.uid() and session_id=s and status<>'active'));
 end if;
 perform pg_advisory_xact_lock(hashtextextended('employee-push-device:'||p_installation_id::text,0));
 update employee_push.devices set status='removed',token=null,token_hash=null,version=version+1,expires_at=clock_timestamp(),updated_at=clock_timestamp()
  where installation_id=p_installation_id and user_id=auth.uid() and session_id=s;
 get diagnostics affected = row_count;
 update employee_push.deliveries x set state='skipped',result_code='binding_inactive',completed_at=clock_timestamp(),lease_id=null,lease_until=null
  from employee_push.devices d where d.installation_id=p_installation_id and d.user_id=auth.uid() and d.session_id=s
   and x.installation_id=d.installation_id and x.state in ('pending','leased');
 answer:=jsonb_build_object('installation_id',p_installation_id,'status','removed','removed',affected>0);
 insert into employee_push.receipts(user_id,session_id,command_id,request_hash,response) values(auth.uid(),s,p_command_id,h,answer);
 return answer;
end $$;

create function employee_push.enqueue_notification() returns trigger
language plpgsql security definer set search_path='' as $$begin
 if new.notification_type like 'people.%' and new.read_at is null then
  insert into employee_push.deliveries(notification_id,installation_id,binding_version)
   select new.id,d.installation_id,d.version from employee_push.devices d
   where d.tenant_id=new.tenant_id and d.legal_entity_id=new.legal_entity_id and d.branch_id=new.branch_id
    and d.user_id=new.recipient_id and employee_push.binding_current(d)
   on conflict(notification_id,installation_id) do nothing;
 end if;return new;
end $$;
create trigger employee_push_notification_insert after insert on workflow.notifications
 for each row execute function employee_push.enqueue_notification();

create function api.employee_push_claim(p_limit integer default 20) returns jsonb
language plpgsql security definer set search_path='' as $$
declare d employee_push.deliveries%rowtype;items jsonb:='[]';begin
 if auth.role() is distinct from 'service_role' then raise exception using errcode='42501',message='PUSH_WORKER_DENIED';end if;
 if p_limit is null or p_limit not between 1 and 20 then raise exception using errcode='22023',message='PUSH_BATCH_INVALID';end if;
 -- Bounded privacy maintenance: expired bindings lose their FIDs even when no
 -- notification is queued. Operational receipts are retained for seven days.
 update employee_push.devices set status='removed',token=null,token_hash=null,version=version+1,updated_at=clock_timestamp()
  where installation_id in(select installation_id from employee_push.devices
   where status='active' and expires_at<=clock_timestamp() order by expires_at for update skip locked limit 100);
 delete from employee_push.receipts where (user_id,session_id,command_id) in (
  select user_id,session_id,command_id from employee_push.receipts where created_at<clock_timestamp()-interval '7 days'
   order by created_at for update skip locked limit 200);
 delete from employee_push.deliveries where id in(select id from employee_push.deliveries
  where state in ('sent','skipped','dead') and completed_at<clock_timestamp()-interval '7 days'
   order by completed_at for update skip locked limit 200);
 update employee_push.deliveries set state='dead',result_code='attempts_exhausted',completed_at=clock_timestamp(),lease_id=null,lease_until=null
  where id in(select id from employee_push.deliveries where state='leased' and lease_until<=clock_timestamp() and attempt>=5
   order by id for update skip locked limit 100);
 for d in select * from employee_push.deliveries
  where (state='pending' and available_at<=clock_timestamp() or state='leased' and lease_until<=clock_timestamp())
   and attempt<5 order by available_at,id for update skip locked limit p_limit loop
  update employee_push.deliveries set state='leased',attempt=attempt+1,lease_id=gen_random_uuid(),
   lease_until=clock_timestamp()+interval '60 seconds' where id=d.id returning * into d;
  items:=items||jsonb_build_array(jsonb_build_object('delivery_id',d.id,'lease_id',d.lease_id));
 end loop;
 return items;
end $$;

create function api.employee_push_target(p_delivery_id uuid,p_lease_id uuid) returns jsonb
language plpgsql security definer set search_path='' as $$
declare x employee_push.deliveries%rowtype;d employee_push.devices%rowtype;n workflow.notifications%rowtype;begin
 if auth.role() is distinct from 'service_role' then raise exception using errcode='42501',message='PUSH_WORKER_DENIED';end if;
 select * into x from employee_push.deliveries where id=p_delivery_id and state='leased'
  and lease_id=p_lease_id and lease_until>clock_timestamp() for update;
 if x.id is null then return null;end if;
 select * into d from employee_push.devices where installation_id=x.installation_id;
 select * into n from workflow.notifications where id=x.notification_id;
 if d.installation_id is null or d.version<>x.binding_version or not employee_push.binding_current(d)
  or n.id is null or n.recipient_id<>d.user_id or n.tenant_id<>d.tenant_id
  or n.legal_entity_id is distinct from d.legal_entity_id or n.branch_id is distinct from d.branch_id
  or n.read_at is not null or n.notification_type not like 'people.%'
  or n.created_at<clock_timestamp()-interval '24 hours' then
  update employee_push.deliveries set state='skipped',result_code='binding_inactive',completed_at=clock_timestamp(),lease_id=null,lease_until=null where id=x.id;
  return null;end if;
 return jsonb_build_object('delivery_id',x.id,'lease_id',x.lease_id,'notification_id',n.id,'token',d.token);
end $$;

create function api.employee_push_finish(p_delivery_id uuid,p_lease_id uuid,p_outcome text) returns boolean
language plpgsql security definer set search_path='' as $$
declare x employee_push.deliveries%rowtype;begin
 if auth.role() is distinct from 'service_role' then raise exception using errcode='42501',message='PUSH_WORKER_DENIED';end if;
 if p_outcome is null or p_outcome not in ('sent','retry','invalid_token','permanent') then
  raise exception using errcode='22023',message='PUSH_OUTCOME_INVALID';end if;
 select * into x from employee_push.deliveries where id=p_delivery_id and state='leased' and lease_id=p_lease_id
  and lease_until>clock_timestamp() for update;
 if x.id is null then return false;end if;
 if p_outcome='invalid_token' then
  update employee_push.devices set status='invalid',token=null,token_hash=null,version=version+1,expires_at=clock_timestamp()
   where installation_id=x.installation_id and version=x.binding_version;
 end if;
 update employee_push.deliveries set
  state=case when p_outcome='sent' then 'sent' when p_outcome='retry' and attempt<5 then 'pending' else 'dead' end,
  available_at=clock_timestamp()+make_interval(secs=>least(3600,(30*power(2,attempt))::integer)),
  result_code=p_outcome,lease_id=null,lease_until=null,
  completed_at=case when p_outcome='retry' and attempt<5 then null else clock_timestamp() end
  where id=x.id;
 return true;
end $$;

revoke all on all functions in schema employee_push from public,anon,authenticated,service_role;
revoke all on function api.employee_push_register(uuid,uuid,uuid,uuid,text,text,uuid),api.employee_push_remove(uuid,uuid)
 from public,anon,authenticated,service_role;
grant execute on function api.employee_push_register(uuid,uuid,uuid,uuid,text,text,uuid),api.employee_push_remove(uuid,uuid) to authenticated;
revoke all on function api.employee_push_claim(integer),api.employee_push_target(uuid,uuid),api.employee_push_finish(uuid,uuid,text)
 from public,anon,authenticated,service_role;
grant execute on function api.employee_push_claim(integer),api.employee_push_target(uuid,uuid),api.employee_push_finish(uuid,uuid,text) to service_role;
