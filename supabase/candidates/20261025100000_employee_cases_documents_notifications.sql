-- CANDIDATE ONLY. Requires the employee self-service candidate first. No plan,
-- role, Storage or deployment changes. Existing documents remain invisible.
insert into core.permissions(code,description,module,privileged) values
 ('people.cases.manage','Own and respond to private employee HR cases with MFA','people',true),
 ('people.hr.cases.self.manage','Create and reply to own linked HR cases with MFA','people',true),
 ('people.hr.documents.publish','Explicitly publish a reviewed private document to its employee with MFA','people',true),
 ('people.hr.documents.self.view','Read explicitly published documents for the accepted employee','people',false);

create table employee_self.cases(
 id uuid primary key,tenant_id uuid not null,legal_entity_id uuid not null,branch_id uuid not null,
 employee_id uuid not null,category text not null check(category in ('general','payroll')),
 subject text check(subject is null or length(btrim(subject)) between 1 and 160),
 status text not null default 'open' check(status in ('open','in_progress','resolved','closed')),
 version bigint not null default 1 check(version between 1 and 9007199254740991),
 payslip_id uuid references people_payroll.payslips(id),payslip_revision_id uuid references people_payroll.run_revisions(id),
 owner_user_id uuid references auth.users(id),created_by uuid not null references auth.users(id),
 created_at timestamptz not null default clock_timestamp(),updated_at timestamptz not null default clock_timestamp(),erased_at timestamptz,
 foreign key(tenant_id,legal_entity_id,employee_id) references people.employees(tenant_id,legal_entity_id,id),
 foreign key(tenant_id,legal_entity_id,branch_id) references core.branches(tenant_id,legal_entity_id,id),
 check((category='payroll')=(payslip_id is not null and payslip_revision_id is not null)),
 check(category='payroll' or (payslip_id is null and payslip_revision_id is null))
);
create index employee_cases_subject_idx on employee_self.cases(tenant_id,legal_entity_id,branch_id,employee_id,id);
create table employee_self.case_messages(
 id uuid primary key default gen_random_uuid(),case_id uuid not null references employee_self.cases(id),
 body text check(body is null or length(btrim(body)) between 1 and 4000),
 author_kind text not null check(author_kind in ('employee','hr')),author_id uuid not null references auth.users(id),
 created_at timestamptz not null default clock_timestamp()
);
create index employee_case_messages_idx on employee_self.case_messages(case_id,created_at,id);
create table employee_self.case_history(
 id uuid primary key default gen_random_uuid(),case_id uuid not null references employee_self.cases(id),
 version bigint not null,status text not null,owner_user_id uuid references auth.users(id),
 actor_id uuid not null references auth.users(id),created_at timestamptz not null default clock_timestamp(),unique(case_id,version)
);
create table employee_self.case_receipts(
 actor_id uuid not null references auth.users(id),command_id uuid not null,request_hash text not null,response jsonb not null,
 created_at timestamptz not null default clock_timestamp(),primary key(actor_id,command_id)
);
create table employee_self.document_publications(
 document_id uuid primary key references people_private.documents(id),document_version bigint not null,
 version bigint not null check(version>0),visible boolean not null default false,
 label text check(label is null or length(btrim(label)) between 1 and 160),
 published_by uuid not null references auth.users(id),published_at timestamptz not null default clock_timestamp()
);
create table employee_self.document_publication_history(
 id uuid primary key default gen_random_uuid(),document_id uuid not null references people_private.documents(id),
 version bigint not null,document_version bigint not null,visible boolean not null,
 actor_id uuid not null references auth.users(id),created_at timestamptz not null default clock_timestamp(),unique(document_id,version)
);
create table employee_self.document_publish_receipts(
 actor_id uuid not null references auth.users(id),command_id uuid not null,
 request_hash text not null,response jsonb not null,created_at timestamptz not null default clock_timestamp(),
 primary key(actor_id,command_id)
);
create table employee_self.document_ticket_bindings(
 ticket_id uuid primary key references people_private.document_tickets(id) on delete cascade,
 document_version bigint not null,publication_version bigint not null,link_id uuid not null references people_private.account_links(id),
 link_version bigint not null,session_id uuid not null references auth.sessions(id) on delete cascade
);
create table employee_self.notification_events(
 id uuid primary key default gen_random_uuid(),tenant_id uuid not null,employee_id uuid not null,
 destination text not null check(destination in ('cases','documents','reviews','pay','leave','attendance')),
 source_id uuid not null,source_version bigint not null check(source_version>0),
 notification_id uuid references workflow.notifications(id) on delete set null,
 created_at timestamptz not null default clock_timestamp(),unique(tenant_id,employee_id,destination,source_id,source_version)
);
-- Only the existing private-HR erasure trigger may redact message bodies.
-- Case lifecycle and receipt metadata otherwise remain append-only.
create function employee_self.guard_case_history() returns trigger
language plpgsql set search_path='' as $$begin
 if tg_table_name='case_messages' and tg_op='UPDATE' and pg_trigger_depth()>1 then
  if new.body is null and (to_jsonb(new)-'body') is not distinct from (to_jsonb(old)-'body') then return new;end if;
 end if;
 raise exception using errcode='55000',message='EMPLOYEE_CASE_HISTORY_IMMUTABLE';
end $$;
create trigger employee_case_messages_immutable before update or delete on employee_self.case_messages
 for each row execute function employee_self.guard_case_history();
create trigger employee_case_history_immutable before update or delete on employee_self.case_history
 for each row execute function employee_self.guard_case_history();
create trigger employee_case_receipts_immutable before update or delete on employee_self.case_receipts
 for each row execute function employee_self.guard_case_history();
create trigger employee_document_publish_receipts_immutable before update or delete on employee_self.document_publish_receipts
 for each row execute function employee_self.guard_case_history();
create trigger employee_document_publication_history_immutable before update or delete on employee_self.document_publication_history
 for each row execute function employee_self.guard_case_history();
do $$declare n text;begin
 foreach n in array array['cases','case_messages','case_history','case_receipts','document_publications','document_publication_history','document_publish_receipts','document_ticket_bindings','notification_events'] loop
 execute format('alter table employee_self.%I enable row level security',n);
 execute format('alter table employee_self.%I force row level security',n);
 execute format('revoke all on employee_self.%I from public,anon,authenticated,service_role',n);
 end loop;
end $$;

-- Worker/event authority never SETs JWT claims or impersonates the employee.
create function employee_self.recipient_current(p_link uuid,p_link_version bigint,p_aal text default null,p_cap text default 'people.self.view') returns boolean
language sql stable security definer set search_path='' as $$
 select exists(select 1 from people_private.account_links l
 join core.memberships m on m.tenant_id=l.tenant_id and m.id=l.membership_id and m.user_id=l.user_id
 join core.tenants t on t.id=l.tenant_id join core.legal_entities e on e.tenant_id=l.tenant_id and e.id=l.legal_entity_id
 join core.branches b on b.tenant_id=l.tenant_id and b.legal_entity_id=l.legal_entity_id and b.id=l.branch_id
 where l.id=p_link and l.version=p_link_version and l.status='accepted' and m.status='active'
 and t.status in ('active','trial') and e.status='active' and b.status='active'
 and exists(select 1 from people.employment_assignments a join people.employment_spells s
  on s.id=a.spell_id and s.tenant_id=a.tenant_id and s.legal_entity_id=a.legal_entity_id and s.employee_id=a.employee_id
  where a.tenant_id=l.tenant_id and a.legal_entity_id=l.legal_entity_id
  and a.branch_id=l.branch_id and a.employee_id=l.employee_id and a.start_date<=(statement_timestamp() at time zone e.timezone)::date
  and (a.end_date_exclusive is null or a.end_date_exclusive>(statement_timestamp() at time zone e.timezone)::date)
  and daterange(s.start_date,s.end_date_exclusive,'[)') @> (statement_timestamp() at time zone e.timezone)::date)
 and exists(select 1 from billing.tenant_subscriptions s join billing.plan_entitlements pe on pe.plan_code=s.plan_code
  where s.tenant_id=l.tenant_id and pe.entitlement_code='module.people' and pe.enabled
   and ((s.status='trialing' and s.trial_ends_at>statement_timestamp()) or (s.status='active'
    and (s.current_period_ends_at is null or s.current_period_ends_at>statement_timestamp()))))
 and not exists(select 1 from unnest(array['people.view','people.self.view',p_cap]) cap where not exists(
  select 1 from core.role_assignments ra join core.roles r on r.tenant_id=ra.tenant_id and r.id=ra.role_id
  join core.role_permissions rp on rp.tenant_id=ra.tenant_id and rp.role_id=ra.role_id
  where ra.tenant_id=l.tenant_id and ra.membership_id=l.membership_id and rp.permission_code=cap
  and (ra.legal_entity_id is null or ra.legal_entity_id=l.legal_entity_id) and (ra.branch_id is null or ra.branch_id=l.branch_id)
  and (p_aal is null or not r.requires_mfa or p_aal='aal2'))))
$$;

-- Only source-owned triggers/functions can publish. Event identity is recorded
-- before the notification INSERT, so the existing push mirror sees one row.
create function employee_self.notify_employee(p_tenant_id uuid,p_legal_entity_id uuid,p_branch_id uuid,
 p_employee_id uuid,p_destination text,p_source_id uuid,p_source_version bigint) returns uuid
language plpgsql security definer set search_path='' as $$
declare ev uuid;l people_private.account_links%rowtype;n uuid;begin
 if p_destination not in ('cases','documents','reviews','pay','leave','attendance') or p_source_id is null
  or p_source_version is null or p_source_version<1 then raise exception using errcode='22023',message='EMPLOYEE_EVENT_INVALID';end if;
 insert into employee_self.notification_events(tenant_id,employee_id,destination,source_id,source_version)
 values(p_tenant_id,p_employee_id,p_destination,p_source_id,p_source_version)
 on conflict do nothing returning id into ev;
 if ev is null then return null;end if;
 select * into l from people_private.account_links a where a.tenant_id=p_tenant_id and a.legal_entity_id=p_legal_entity_id
 and a.branch_id=p_branch_id and a.employee_id=p_employee_id and a.status='accepted' for share;
 if l.id is null or not employee_self.recipient_current(l.id,l.version,null,case p_destination
  when 'documents' then 'people.hr.documents.self.view' when 'pay' then 'people.payroll.payslip.self' else 'people.self.view' end) then return null;end if;
 insert into workflow.notifications(tenant_id,legal_entity_id,branch_id,recipient_id,notification_type,title,body,
  aggregate_type,aggregate_id,source_context,created_by,updated_by)
 values(p_tenant_id,p_legal_entity_id,p_branch_id,l.user_id,'people.employee.'||p_destination,'Jentra Employee',
 'You have an update. Open the app to view it.','employee_'||p_destination,p_source_id,
 jsonb_build_object('destination',p_destination,'source_id',p_source_id,'source_version',p_source_version,'link_id',l.id),l.user_id,l.user_id)
 returning id into n;
 update employee_self.notification_events set notification_id=n where id=ev;
 return n;
end $$;

create function employee_self.case_summary(c employee_self.cases) returns jsonb
language sql stable set search_path='' as $$select jsonb_build_object('id',(c).id,'version',(c).version,'category',(c).category,
 'subject',(c).subject,'status',(c).status,'owner_user_id',(c).owner_user_id,'payslip_id',(c).payslip_id,'payslip_revision_id',(c).payslip_revision_id,
 'created_at',(c).created_at,'updated_at',(c).updated_at)$$;
create function employee_self.case_content(p_case uuid) returns jsonb language sql stable set search_path='' as $$
 select employee_self.case_summary(c)||jsonb_build_object('messages',coalesce((select jsonb_agg(jsonb_build_object(
 'id',m.id,'body',m.body,'author_kind',m.author_kind,'created_at',m.created_at) order by m.created_at,m.id)
 from employee_self.case_messages m where m.case_id=c.id),'[]'::jsonb),'history',coalesce((select jsonb_agg(jsonb_build_object(
 'id',h.id,'status',h.status,'owner_user_id',h.owner_user_id,'created_at',h.created_at) order by h.version)
 from employee_self.case_history h where h.case_id=c.id),'[]'::jsonb)) from employee_self.cases c where c.id=p_case
$$;
-- Ownership survives sign-out, token expiry and an absent browser session. Only
-- current durable membership/role scope determines whether another manager may
-- recover an otherwise orphaned enquiry.
create function employee_self.case_owner_available(c employee_self.cases) returns boolean
language sql stable security definer set search_path='' as $$
 select (c).owner_user_id is not null and people_private.user_has((c).tenant_id,(c).legal_entity_id,
  (c).branch_id,(c).owner_user_id,'people.cases.manage','aal2')
$$;
create function employee_self.require_hr_staff(p_tenant_id uuid,p_legal_entity_id uuid,p_branch_id uuid,p_permission text)
returns void language plpgsql stable security definer set search_path='' as $$declare s uuid;begin
 if auth.uid() is null or coalesce(auth.jwt()->>'session_id','') !~*
 '^[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12}$' then raise exception using errcode='42501',message='EMPLOYEE_SESSION_REQUIRED';end if;
 s:=(auth.jwt()->>'session_id')::uuid;
 if not exists(select 1 from auth.sessions where id=s and user_id=auth.uid() and (not_after is null or not_after>statement_timestamp()))
 then raise exception using errcode='42501',message='EMPLOYEE_SESSION_REQUIRED';end if;
 if p_permission is null or p_permission not in ('people.cases.manage','people.hr.documents.publish') then
 raise exception using errcode='42501',message='EMPLOYEE_CAPABILITY_INVALID';end if;
 perform people_private.require_access(p_tenant_id,p_legal_entity_id,p_branch_id,null,p_permission,true);
end $$;
create function api.employee_cases_list(p_tenant_id uuid,p_legal_entity_id uuid,p_branch_id uuid,p_after uuid default null)
returns jsonb language plpgsql security definer set search_path='' as $$declare v_employee uuid;items jsonb;begin
 v_employee:=employee_self.require_subject(p_tenant_id,p_legal_entity_id,p_branch_id);
 perform people_private.content_available(p_tenant_id,p_legal_entity_id,v_employee);
 if p_after is not null and not exists(select 1 from employee_self.cases c where c.id=p_after and c.tenant_id=p_tenant_id
  and c.legal_entity_id=p_legal_entity_id and c.branch_id=p_branch_id and c.employee_id=v_employee and c.erased_at is null)
 then raise exception using errcode='22023',message='EMPLOYEE_CURSOR_INVALID';end if;
 select coalesce(jsonb_agg(c.summary order by c.id),'[]') into items from(
 select x.id,employee_self.case_summary(x) as summary from employee_self.cases x where tenant_id=p_tenant_id and legal_entity_id=p_legal_entity_id
 and branch_id=p_branch_id and employee_id=v_employee and erased_at is null and (p_after is null or id>p_after) order by id limit 51)c;
 return jsonb_build_object('tenant_id',p_tenant_id,'legal_entity_id',p_legal_entity_id,'branch_id',p_branch_id,
 'employee_id',v_employee,'items',items-50,'next_cursor',case when jsonb_array_length(items)>50 then items->49->>'id' end);
end $$;
create function api.employee_case_detail(p_tenant_id uuid,p_legal_entity_id uuid,p_branch_id uuid,p_case_id uuid)
returns jsonb language plpgsql security definer set search_path='' as $$declare v_employee uuid;begin
 v_employee:=employee_self.require_subject(p_tenant_id,p_legal_entity_id,p_branch_id);
 perform people_private.content_available(p_tenant_id,p_legal_entity_id,v_employee);
 if not exists(select 1 from employee_self.cases where id=p_case_id and tenant_id=p_tenant_id and legal_entity_id=p_legal_entity_id
 and branch_id=p_branch_id and employee_id=v_employee and erased_at is null) then raise exception using errcode='42501',message='EMPLOYEE_CASE_DENIED';end if;
 return jsonb_build_object('tenant_id',p_tenant_id,'legal_entity_id',p_legal_entity_id,'branch_id',p_branch_id,
 'employee_id',v_employee,'case',employee_self.case_content(p_case_id));
end $$;
create function api.employee_case_command(p_tenant_id uuid,p_legal_entity_id uuid,p_branch_id uuid,
 p_command_id uuid,p_action text,p_payload jsonb) returns jsonb
language plpgsql security definer set search_path='' as $$
declare v_employee uuid;cid uuid;c employee_self.cases%rowtype;cached employee_self.case_receipts%rowtype;h text;answer jsonb;begin
 v_employee:=employee_self.lock_subject(p_tenant_id,p_legal_entity_id,p_branch_id,'people.hr.cases.self.manage');
 perform people_private.content_available(p_tenant_id,p_legal_entity_id,v_employee,true);
 if p_command_id is null or p_action is null or p_action not in ('create','reply') or jsonb_typeof(p_payload) is distinct from 'object'
 or p_payload->>'id' is null then raise exception using errcode='22023',message='EMPLOYEE_CASE_INVALID';end if;
 perform people_private.fields(p_payload,case when p_action='create' then array['id','category','subject','body','payslip_id','payslip_revision_id']
 else array['id','expected_version','body'] end);
 cid:=(p_payload->>'id')::uuid;
 if p_payload->>'body' is null or length(btrim(p_payload->>'body')) not between 1 and 4000 then raise exception using errcode='22023',message='EMPLOYEE_CASE_INVALID';end if;
 h:=people_private.digest(p_tenant_id,p_legal_entity_id,jsonb_build_array(p_tenant_id,p_legal_entity_id,p_branch_id,v_employee,p_action,p_payload));
 perform pg_advisory_xact_lock(hashtextextended('employee-case-command:'||auth.uid()::text||p_command_id::text,0));
 select * into cached from employee_self.case_receipts where actor_id=auth.uid() and command_id=p_command_id;
 if exists(select 1 from employee_self.abandoned_commands a where a.user_id=auth.uid() and a.command_id=p_command_id)
 then raise exception using errcode='55000',message='EMPLOYEE_COMMAND_ABANDONED';end if;
 if found then if cached.request_hash<>h then raise exception using errcode='22023',message='EMPLOYEE_COMMAND_REUSED';end if;return cached.response;end if;
 perform pg_advisory_xact_lock(hashtextextended('employee-case:'||cid::text,0));
 if p_action='create' then
  if p_payload->>'category' is null or p_payload->>'category' not in ('general','payroll') or p_payload->>'subject' is null
   or length(btrim(p_payload->>'subject')) not between 1 and 160 then raise exception using errcode='22023',message='EMPLOYEE_CASE_INVALID';end if;
  if p_payload->>'category'='payroll' then
   perform employee_self.require_subject(p_tenant_id,p_legal_entity_id,p_branch_id,'people.payroll.payslip.self',true);
   if not exists(select 1 from people_payroll.payslips p join people_payroll.employee_calculations x on x.id=p.calculation_id
    join people_payroll.runs r on r.id=p.run_id where p.id=(p_payload->>'payslip_id')::uuid and x.revision_id=(p_payload->>'payslip_revision_id')::uuid
    and p.tenant_id=p_tenant_id and p.legal_entity_id=p_legal_entity_id and p.branch_id=p_branch_id and p.employee_id=v_employee
    and r.status in ('posted','reversed')) then raise exception using errcode='42501',message='EMPLOYEE_PAYSLIP_DENIED';end if;
  elsif p_payload->>'payslip_id' is not null or p_payload->>'payslip_revision_id' is not null then
   raise exception using errcode='22023',message='EMPLOYEE_CASE_INVALID';end if;
  if exists(select 1 from employee_self.cases where id=cid) then raise exception using errcode='40001',message='VERSION_CONFLICT';end if;
  -- Bounded intake prevents employee-created unbounded rows. Closed/erased cases do not consume the active cap.
  perform pg_advisory_xact_lock(hashtextextended('employee-case-intake:'||v_employee::text,0));
  if (select count(*) from employee_self.cases where employee_id=v_employee and status in ('open','in_progress') and erased_at is null)>=20 then
   raise exception using errcode='54000',message='EMPLOYEE_CASE_LIMIT';end if;
  insert into employee_self.cases(id,tenant_id,legal_entity_id,branch_id,employee_id,category,subject,payslip_id,payslip_revision_id,created_by)
  values(cid,p_tenant_id,p_legal_entity_id,p_branch_id,v_employee,p_payload->>'category',btrim(p_payload->>'subject'),
   (p_payload->>'payslip_id')::uuid,(p_payload->>'payslip_revision_id')::uuid,auth.uid()) returning * into c;
 else
  select * into c from employee_self.cases where id=cid and tenant_id=p_tenant_id and legal_entity_id=p_legal_entity_id
   and branch_id=p_branch_id and employee_id=v_employee and erased_at is null for update;
  if not found then raise exception using errcode='42501',message='EMPLOYEE_CASE_DENIED';end if;
  if (p_payload->>'expected_version')::bigint is distinct from c.version then raise exception using errcode='40001',message='VERSION_CONFLICT';end if;
  if c.status not in ('open','in_progress') then raise exception using errcode='22023',message='EMPLOYEE_CASE_CLOSED';end if;
  if (select count(*) from employee_self.case_messages where case_id=cid)>=200 then raise exception using errcode='54000',message='EMPLOYEE_CASE_MESSAGE_LIMIT';end if;
  if (select count(*) from employee_self.case_history where case_id=cid)>=1000 then raise exception using errcode='54000',message='EMPLOYEE_CASE_HISTORY_LIMIT';end if;
  update employee_self.cases set version=version+1,updated_at=clock_timestamp() where id=cid returning * into c;
 end if;
 insert into employee_self.case_messages(case_id,body,author_kind,author_id) values(cid,btrim(p_payload->>'body'),'employee',auth.uid());
 insert into employee_self.case_history(case_id,version,status,owner_user_id,actor_id) values(cid,c.version,c.status,c.owner_user_id,auth.uid());
 answer:=employee_self.envelope(p_tenant_id,p_legal_entity_id,p_branch_id,v_employee)||jsonb_build_object('id',cid,'version',c.version,'status',c.status,'command_id',p_command_id);
 insert into employee_self.case_receipts(actor_id,command_id,request_hash,response) values(auth.uid(),p_command_id,h,answer);
 return answer;
end $$;

-- Receipt-only recovery never accepts a private body. A missing command is
-- fenced under the original command lock before the app may forget its body.
create function api.employee_case_receipt(p_tenant_id uuid,p_legal_entity_id uuid,p_branch_id uuid,
 p_command_id uuid,p_request_id uuid,p_rpc text) returns jsonb
language plpgsql security definer set search_path='' as $$
declare v_employee uuid;cached employee_self.case_receipts%rowtype;f employee_self.abandoned_commands%rowtype;begin
 v_employee:=employee_self.lock_subject(p_tenant_id,p_legal_entity_id,p_branch_id,'people.hr.cases.self.manage');
 perform people_private.content_available(p_tenant_id,p_legal_entity_id,v_employee);
 if p_command_id is null or p_request_id is null or p_rpc is distinct from 'employee_case_command'
 then raise exception using errcode='22023',message='EMPLOYEE_RECEIPT_INVALID';end if;
 perform pg_advisory_xact_lock(hashtextextended('employee-case-command:'||auth.uid()::text||p_command_id::text,0));
 select * into cached from employee_self.case_receipts where actor_id=auth.uid() and command_id=p_command_id;
 if found then
  if cached.response->>'id' is distinct from p_request_id::text or cached.response->>'tenant_id' is distinct from p_tenant_id::text
   or cached.response->>'legal_entity_id' is distinct from p_legal_entity_id::text or cached.response->>'branch_id' is distinct from p_branch_id::text
   or cached.response->>'employee_id' is distinct from v_employee::text
  then raise exception using errcode='42501',message='EMPLOYEE_RECEIPT_DENIED';end if;
  return employee_self.envelope(p_tenant_id,p_legal_entity_id,p_branch_id,v_employee)||jsonb_build_object(
   'command_id',p_command_id,'request_id',p_request_id,'rpc',p_rpc,'abandoned',false,'receipt',cached.response);
 end if;
 select * into f from employee_self.abandoned_commands where user_id=auth.uid() and command_id=p_command_id;
 if f.command_id is not null and (f.tenant_id<>p_tenant_id or f.legal_entity_id<>p_legal_entity_id or f.branch_id<>p_branch_id
  or f.employee_id<>v_employee or f.rpc<>p_rpc or f.request_id<>p_request_id)
 then raise exception using errcode='42501',message='EMPLOYEE_RECEIPT_DENIED';end if;
 insert into employee_self.abandoned_commands(user_id,command_id,tenant_id,legal_entity_id,branch_id,employee_id,rpc,request_id)
 values(auth.uid(),p_command_id,p_tenant_id,p_legal_entity_id,p_branch_id,v_employee,p_rpc,p_request_id) on conflict do nothing;
 return employee_self.envelope(p_tenant_id,p_legal_entity_id,p_branch_id,v_employee)||jsonb_build_object(
  'command_id',p_command_id,'request_id',p_request_id,'rpc',p_rpc,'abandoned',true,'receipt',null);
end $$;

-- Staff cannot silently gain self-service access to another employee. This is a
-- separate permission, explicit ownership, MFA and current subject scope.
create function api.employee_hr_cases_list(p_tenant_id uuid,p_legal_entity_id uuid,p_branch_id uuid,p_after uuid default null)
returns jsonb language plpgsql security definer set search_path='' as $$declare items jsonb;begin
 perform employee_self.require_hr_staff(p_tenant_id,p_legal_entity_id,p_branch_id,'people.cases.manage');
 select coalesce(jsonb_agg(c.summary order by c.id),'[]') into items
 from(select x.id,employee_self.case_summary(x)||jsonb_build_object('employee_id',x.employee_id,
 'owner_available',employee_self.case_owner_available(x)) as summary from employee_self.cases x where tenant_id=p_tenant_id and legal_entity_id=p_legal_entity_id and branch_id=p_branch_id
 and erased_at is null and (p_after is null or id>p_after)
 and exists(select 1 from people_private.policies p where p.tenant_id=x.tenant_id and p.legal_entity_id=x.legal_entity_id
 and (p.closed_at is null or p.closed_at+interval '30 days'>now()))
 and not exists(select 1 from people_private.purge_jobs j where j.tenant_id=x.tenant_id and j.legal_entity_id=x.legal_entity_id and j.employee_id=x.employee_id)
 order by id limit 51)c;
 return jsonb_build_object('items',items-50,'next_cursor',case when jsonb_array_length(items)>50 then items->49->>'id' end);
end $$;
create function api.employee_hr_case_detail(p_tenant_id uuid,p_legal_entity_id uuid,p_branch_id uuid,p_case_id uuid)
returns jsonb language plpgsql security definer set search_path='' as $$declare c employee_self.cases%rowtype;begin
 perform employee_self.require_hr_staff(p_tenant_id,p_legal_entity_id,p_branch_id,'people.cases.manage');
 select * into c from employee_self.cases where id=p_case_id and tenant_id=p_tenant_id and legal_entity_id=p_legal_entity_id
 and branch_id=p_branch_id and erased_at is null;
 if not found then raise exception using errcode='42501',message='EMPLOYEE_CASE_DENIED';end if;
 perform people_private.content_available(p_tenant_id,p_legal_entity_id,c.employee_id);
 return employee_self.case_content(c.id)||jsonb_build_object('employee_id',c.employee_id,
 'owner_available',employee_self.case_owner_available(c));
end $$;
create function api.employee_hr_case_owners(p_tenant_id uuid,p_legal_entity_id uuid,p_branch_id uuid,p_after uuid default null)
returns jsonb language plpgsql stable security definer set search_path='' as $$declare items jsonb;begin
 perform employee_self.require_hr_staff(p_tenant_id,p_legal_entity_id,p_branch_id,'people.cases.manage');
 if p_after is not null and not exists(select 1 from core.memberships m where m.id=p_after and m.tenant_id=p_tenant_id
  and m.status='active' and people_private.user_has(p_tenant_id,p_legal_entity_id,p_branch_id,m.user_id,'people.cases.manage','aal2')) then
  raise exception using errcode='22023',message='EMPLOYEE_CURSOR_INVALID';end if;
 -- The same public account name used by the profile screen labels an exact
 -- eligible user ID. No email, credential or private personnel profile is read.
 select coalesce(jsonb_agg(q.item order by q.id),'[]') into items from(
  select m.id,jsonb_build_object('id',m.id,'user_id',m.user_id,'label',coalesce(
   nullif(left(btrim(u.raw_user_meta_data->>'full_name'),160),''),'Member '||left(m.id::text,8))) item
  from core.memberships m join auth.users u on u.id=m.user_id
  where m.tenant_id=p_tenant_id and m.status='active' and (p_after is null or m.id>p_after)
  and people_private.user_has(p_tenant_id,p_legal_entity_id,p_branch_id,m.user_id,'people.cases.manage','aal2')
  order by m.id limit 51) q;
 return jsonb_build_object('tenant_id',p_tenant_id,'legal_entity_id',p_legal_entity_id,'branch_id',p_branch_id,
  'items',items-50,'next_cursor',case when jsonb_array_length(items)>50 then items->49->>'id' end);
end $$;
create function api.employee_hr_case_command(p_tenant_id uuid,p_legal_entity_id uuid,p_branch_id uuid,p_case_id uuid,
 p_command_id uuid,p_expected_version bigint,p_action text,p_body text default null,p_owner_user_id uuid default null) returns jsonb
language plpgsql security definer set search_path='' as $$declare c employee_self.cases%rowtype;cached employee_self.case_receipts%rowtype;h text;answer jsonb;begin
 perform employee_self.require_hr_staff(p_tenant_id,p_legal_entity_id,p_branch_id,'people.cases.manage');
 if p_command_id is null or p_action is null or p_action not in ('claim','assign','reply','resolve','close') then raise exception using errcode='22023',message='EMPLOYEE_CASE_INVALID';end if;
 h:=people_private.digest(p_tenant_id,p_legal_entity_id,jsonb_build_array('staff',p_tenant_id,p_legal_entity_id,p_branch_id,p_case_id,p_expected_version,p_action,p_body,p_owner_user_id));
 perform pg_advisory_xact_lock(hashtextextended('employee-case-command:'||auth.uid()::text||p_command_id::text,0));
 select * into cached from employee_self.case_receipts where actor_id=auth.uid() and command_id=p_command_id;
 -- Authorization and private retention are rechecked before returning a receipt.
 select * into c from employee_self.cases where id=p_case_id and tenant_id=p_tenant_id and legal_entity_id=p_legal_entity_id
 and branch_id=p_branch_id and erased_at is null for update;
 if not found then raise exception using errcode='42501',message='EMPLOYEE_CASE_DENIED';end if;
 perform people_private.content_available(p_tenant_id,p_legal_entity_id,c.employee_id,true);
 if cached.command_id is not null then if cached.request_hash<>h then raise exception using errcode='22023',message='EMPLOYEE_COMMAND_REUSED';end if;return cached.response;end if;
 if c.version is distinct from p_expected_version then raise exception using errcode='40001',message='VERSION_CONFLICT';end if;
 if (select count(*) from employee_self.case_history where case_id=c.id)>=1000 then raise exception using errcode='54000',message='EMPLOYEE_CASE_HISTORY_LIMIT';end if;
 if c.status='closed' or (p_action='claim' and employee_self.case_owner_available(c)) or (p_action<>'claim' and c.owner_user_id is distinct from auth.uid()) then
  raise exception using errcode='42501',message='EMPLOYEE_CASE_OWNER_REQUIRED';end if;
 if p_action='assign' and (p_owner_user_id is null or not people_private.user_has(p_tenant_id,p_legal_entity_id,p_branch_id,p_owner_user_id,'people.cases.manage','aal2')) then
  raise exception using errcode='42501',message='EMPLOYEE_CASE_OWNER_REQUIRED';end if;
 if p_action='reply' then
  if p_body is null or length(btrim(p_body)) not between 1 and 4000 then raise exception using errcode='22023',message='EMPLOYEE_CASE_INVALID';end if;
  if (select count(*) from employee_self.case_messages where case_id=c.id)>=200 then raise exception using errcode='54000',message='EMPLOYEE_CASE_MESSAGE_LIMIT';end if;
  insert into employee_self.case_messages(case_id,body,author_kind,author_id) values(c.id,btrim(p_body),'hr',auth.uid());
 elsif p_body is not null then raise exception using errcode='22023',message='EMPLOYEE_CASE_INVALID';end if;
 if (p_action='resolve' and c.status not in ('open','in_progress')) or (p_action='close' and c.status<>'resolved') then
  raise exception using errcode='22023',message='EMPLOYEE_CASE_TRANSITION_INVALID';end if;
 update employee_self.cases set version=version+1,updated_at=clock_timestamp(),
  owner_user_id=case p_action when 'claim' then auth.uid() when 'assign' then p_owner_user_id else owner_user_id end,
  status=case when p_action='claim' and status='open' then 'in_progress' when p_action='resolve' then 'resolved'
   when p_action='close' then 'closed' else status end
 where id=c.id returning * into c;
 insert into employee_self.case_history(case_id,version,status,owner_user_id,actor_id) values(c.id,c.version,c.status,c.owner_user_id,auth.uid());
 if p_action in ('reply','resolve','close') then perform employee_self.notify_employee(c.tenant_id,c.legal_entity_id,c.branch_id,c.employee_id,'cases',c.id,c.version);end if;
 answer:=employee_self.envelope(p_tenant_id,p_legal_entity_id,p_branch_id,c.employee_id)||jsonb_build_object('id',c.id,'version',c.version,'status',c.status,'command_id',p_command_id);
 insert into employee_self.case_receipts(actor_id,command_id,request_hash,response) values(auth.uid(),p_command_id,h,answer);
 return answer;
end $$;

create function api.employee_hr_document_publication(p_tenant_id uuid,p_legal_entity_id uuid,p_branch_id uuid,p_document_id uuid)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare d people_private.documents%rowtype;p employee_self.document_publications%rowtype;begin
 perform employee_self.require_hr_staff(p_tenant_id,p_legal_entity_id,p_branch_id,'people.hr.documents.publish');
 perform people_private.require_access(p_tenant_id,p_legal_entity_id,p_branch_id,null,'people.hr.documents.view');
 select * into d from people_private.documents where id=p_document_id and tenant_id=p_tenant_id
 and legal_entity_id=p_legal_entity_id and branch_id=p_branch_id and status='active';
 if not found then raise exception using errcode='42501',message='HR_DOCUMENT_DENIED';end if;
 perform people_private.content_available(p_tenant_id,p_legal_entity_id,d.employee_id,true);
 select * into p from employee_self.document_publications where document_id=d.id;
 return jsonb_build_object('tenant_id',p_tenant_id,'legal_entity_id',p_legal_entity_id,'branch_id',p_branch_id,
 'document_id',d.id,'document_version',d.version,'publication_version',coalesce(p.version,0),
 'visible',coalesce(p.visible and p.document_version=d.version,false),'label',case when p.document_version=d.version then p.label end);
end $$;

create function api.employee_hr_document_publish(p_tenant_id uuid,p_legal_entity_id uuid,p_branch_id uuid,p_document_id uuid,
 p_command_id uuid,p_document_version bigint,p_expected_version bigint,p_visible boolean,p_label text default null) returns jsonb
language plpgsql security definer set search_path='' as $$
declare d people_private.documents%rowtype;p employee_self.document_publications%rowtype;
 cached employee_self.document_publish_receipts%rowtype;h text;answer jsonb;begin
 perform employee_self.require_hr_staff(p_tenant_id,p_legal_entity_id,p_branch_id,'people.hr.documents.publish');
 perform people_private.require_access(p_tenant_id,p_legal_entity_id,p_branch_id,null,'people.hr.documents.view');
 if p_command_id is null or p_visible is null or p_expected_version is null or p_expected_version<0
 or (p_visible and (p_label is null or length(btrim(p_label)) not between 1 and 160))
 or (not p_visible and p_label is not null) then raise exception using errcode='22023',message='EMPLOYEE_DOCUMENT_INVALID';end if;
 h:=people_private.digest(p_tenant_id,p_legal_entity_id,jsonb_build_array('document-publication',p_tenant_id,p_legal_entity_id,p_branch_id,
 p_document_id,p_document_version,p_expected_version,p_visible,p_label));
 perform pg_advisory_xact_lock(hashtextextended('employee-document-command:'||auth.uid()::text||p_command_id::text,0));
 select * into d from people_private.documents where id=p_document_id and tenant_id=p_tenant_id and legal_entity_id=p_legal_entity_id and branch_id=p_branch_id for update;
 if not found or d.status<>'active' or d.version is distinct from p_document_version then raise exception using errcode='42501',message='HR_DOCUMENT_DENIED';end if;
 perform people_private.content_available(p_tenant_id,p_legal_entity_id,d.employee_id,true);
 select * into cached from employee_self.document_publish_receipts where actor_id=auth.uid() and command_id=p_command_id;
 if found then
  if cached.request_hash<>h then raise exception using errcode='22023',message='EMPLOYEE_COMMAND_REUSED';end if;
  return cached.response;
 end if;
 select * into p from employee_self.document_publications where document_id=d.id for update;
 if coalesce(p.version,0) is distinct from p_expected_version then raise exception using errcode='40001',message='VERSION_CONFLICT';end if;
 insert into employee_self.document_publications(document_id,document_version,version,visible,label,published_by)
 values(d.id,d.version,coalesce(p.version,0)+1,p_visible,case when p_visible then btrim(p_label) else null end,auth.uid())
 on conflict(document_id) do update set document_version=excluded.document_version,version=excluded.version,visible=excluded.visible,
 label=excluded.label,published_by=excluded.published_by,published_at=clock_timestamp() returning * into p;
 insert into employee_self.document_publication_history(document_id,version,document_version,visible,actor_id)
 values(d.id,p.version,d.version,p_visible,auth.uid());
 if p_visible then perform employee_self.notify_employee(d.tenant_id,d.legal_entity_id,d.branch_id,d.employee_id,'documents',d.id,p.version);
 else delete from workflow.notifications where notification_type='people.employee.documents' and aggregate_id=d.id;end if;
 answer:=jsonb_build_object('tenant_id',p_tenant_id,'legal_entity_id',p_legal_entity_id,'branch_id',p_branch_id,
 'id',d.id,'version',p.version,'document_version',d.version,'visible',p.visible,'command_id',p_command_id);
 insert into employee_self.document_publish_receipts(actor_id,command_id,request_hash,response)
 values(auth.uid(),p_command_id,h,answer);
 return answer;
end $$;
create function api.employee_documents_list(p_tenant_id uuid,p_legal_entity_id uuid,p_branch_id uuid,p_after uuid default null)
returns jsonb language plpgsql security definer set search_path='' as $$declare v_employee uuid;items jsonb;begin
 v_employee:=employee_self.require_subject(p_tenant_id,p_legal_entity_id,p_branch_id,'people.hr.documents.self.view');
 perform people_private.content_available(p_tenant_id,p_legal_entity_id,v_employee);
 if p_after is not null and not exists(select 1 from people_private.documents d join employee_self.document_publications p
  on p.document_id=d.id and p.document_version=d.version and p.visible where d.id=p_after and d.tenant_id=p_tenant_id
  and d.legal_entity_id=p_legal_entity_id and d.branch_id=p_branch_id and d.employee_id=v_employee and d.status='active')
 then raise exception using errcode='22023',message='EMPLOYEE_CURSOR_INVALID';end if;
 select coalesce(jsonb_agg(to_jsonb(q) order by q.id),'[]') into items from(
 select d.id,d.version,p.version as publication_version,p.label,d.mime,d.byte_size,d.checksum,p.published_at from people_private.documents d
 join employee_self.document_publications p on p.document_id=d.id and p.document_version=d.version and p.visible
 where d.tenant_id=p_tenant_id and d.legal_entity_id=p_legal_entity_id and d.branch_id=p_branch_id and d.employee_id=v_employee
 and d.status='active' and (p_after is null or d.id>p_after) order by d.id limit 51)q;
 return jsonb_build_object('tenant_id',p_tenant_id,'legal_entity_id',p_legal_entity_id,'branch_id',p_branch_id,
 'employee_id',v_employee,'items',items-50,'next_cursor',case when jsonb_array_length(items)>50 then items->49->>'id' end);
end $$;
create function api.employee_document_access_ticket(p_tenant_id uuid,p_legal_entity_id uuid,p_branch_id uuid,p_document_id uuid,p_document_version bigint,p_publication_version bigint)
returns jsonb language plpgsql security definer set search_path='' as $$
declare v_employee uuid;d people_private.documents%rowtype;p employee_self.document_publications%rowtype;l people_private.account_links%rowtype;t uuid;s uuid;begin
 v_employee:=employee_self.lock_subject(p_tenant_id,p_legal_entity_id,p_branch_id,'people.hr.documents.self.view');
 perform people_private.content_available(p_tenant_id,p_legal_entity_id,v_employee);
 s:=(auth.jwt()->>'session_id')::uuid;
 select * into d from people_private.documents where id=p_document_id and tenant_id=p_tenant_id and legal_entity_id=p_legal_entity_id
 and branch_id=p_branch_id and employee_id=v_employee and status='active' and version=p_document_version;
 select * into p from employee_self.document_publications where document_id=d.id and visible and document_version=d.version and version=p_publication_version;
 select * into l from people_private.account_links where tenant_id=p_tenant_id and legal_entity_id=p_legal_entity_id and branch_id=p_branch_id
 and employee_id=v_employee and user_id=auth.uid() and status='accepted';
 if d.id is null or p.document_id is null or l.id is null then raise exception using errcode='42501',message='HR_DOCUMENT_DENIED';end if;
 insert into people_private.document_tickets(tenant_id,legal_entity_id,branch_id,employee_id,document_id,user_id,operation,issued_aal)
 values(p_tenant_id,p_legal_entity_id,p_branch_id,v_employee,d.id,auth.uid(),'download',auth.jwt()->>'aal') returning id into t;
 insert into employee_self.document_ticket_bindings(ticket_id,document_version,publication_version,link_id,link_version,session_id)
 values(t,d.version,p.version,l.id,l.version,s);
 return jsonb_build_object('ticket_id',t,'expires_at',now()+interval '30 seconds');
end $$;

-- Preserve the installed staff implementation behind a service-only wrapper.
alter function api.people_hr_service_document(uuid,uuid) rename to people_hr_service_document_staff_v1;
create function api.people_hr_service_document(p_ticket_id uuid,p_user_id uuid) returns jsonb
language plpgsql security definer set search_path='' as $$
declare t people_private.document_tickets%rowtype;b employee_self.document_ticket_bindings%rowtype;d people_private.documents%rowtype;begin
 perform people_private.service_only();
 select * into b from employee_self.document_ticket_bindings where ticket_id=p_ticket_id;
 if not found then return api.people_hr_service_document_staff_v1(p_ticket_id,p_user_id);end if;
 select * into t from people_private.document_tickets where id=p_ticket_id for update;
 if t.user_id is distinct from p_user_id or t.operation<>'download' or t.expires_at<=clock_timestamp() or t.consumed_at is not null
 or not exists(select 1 from auth.sessions s where s.id=b.session_id and s.user_id=p_user_id and (s.not_after is null or s.not_after>statement_timestamp()))
 or not employee_self.recipient_current(b.link_id,b.link_version,t.issued_aal,'people.hr.documents.self.view')
 or not exists(select 1 from people_private.account_links l where l.id=b.link_id and l.user_id=p_user_id and l.employee_id=t.employee_id
  and l.tenant_id=t.tenant_id and l.legal_entity_id=t.legal_entity_id and l.branch_id=t.branch_id)
 then raise exception using errcode='42501',message='HR_DOCUMENT_DENIED';end if;
 perform people_private.content_available(t.tenant_id,t.legal_entity_id,t.employee_id);
 select * into d from people_private.documents where id=t.document_id and employee_id=t.employee_id and tenant_id=t.tenant_id
 and legal_entity_id=t.legal_entity_id and branch_id=t.branch_id and status='active' and version=b.document_version;
 if d.id is null or d.object_path is null or not exists(select 1 from employee_self.document_publications p where p.document_id=d.id
  and p.document_version=d.version and p.version=b.publication_version and p.visible) then raise exception using errcode='42501',message='HR_DOCUMENT_DENIED';end if;
 update people_private.document_tickets set consumed_at=clock_timestamp() where id=t.id;
 return jsonb_build_object('ticket_id',t.id,'operation','download','object_path',d.object_path,'document_id',d.id,'document_version',d.version,
 'publication_version',b.publication_version,
 'employee_id',d.employee_id,'tenant_id',d.tenant_id,'legal_entity_id',d.legal_entity_id,'branch_id',d.branch_id,
 'mime',d.mime,'byte_size',d.byte_size,'checksum',d.checksum,'status',d.status);
end $$;
revoke all on function api.people_hr_service_document_staff_v1(uuid,uuid) from public,anon,authenticated,service_role;
revoke all on function api.people_hr_service_document(uuid,uuid) from public,anon,authenticated;
grant execute on function api.people_hr_service_document(uuid,uuid) to service_role;

create function employee_self.hr_source_notification() returns trigger language plpgsql security definer set search_path='' as $$
declare p record;begin
 if tg_table_schema='people_private' and tg_table_name='reviews' then
  if new.status in ('reviewed','acknowledged','closed') and (tg_op='INSERT' or old.status is distinct from new.status or old.revision_id is distinct from new.revision_id) then
   perform employee_self.notify_employee(new.tenant_id,new.legal_entity_id,new.branch_id,new.employee_id,'reviews',new.id,new.version);end if;
 elsif tg_table_schema='people' and tg_table_name='leave_requests' then
  if new.status in ('approved','rejected','cancelled') and (tg_op='INSERT' or old.status is distinct from new.status) then
   perform employee_self.notify_employee(new.tenant_id,new.legal_entity_id,new.branch_id,new.employee_id,'leave',new.id,new.version);end if;
 elsif tg_table_schema='people_payroll' and tg_table_name='runs' then
  if new.status in ('posted','reversed') and old.status is distinct from new.status then
   for p in select * from people_payroll.payslips where run_id=new.id loop
    perform employee_self.notify_employee(p.tenant_id,p.legal_entity_id,p.branch_id,p.employee_id,'pay',p.id,new.version);
   end loop;end if;
 end if;
 return new;
end $$;
create trigger employee_review_notice after insert or update on people_private.reviews for each row execute function employee_self.hr_source_notification();
create trigger employee_leave_notice after insert or update on people.leave_requests for each row execute function employee_self.hr_source_notification();
create trigger employee_pay_notice after update on people_payroll.runs for each row execute function employee_self.hr_source_notification();
create function employee_self.revoke_recipient_notices() returns trigger language plpgsql security definer set search_path='' as $$begin
 if new.status<>'accepted' or new.version<>old.version then
 delete from workflow.notifications where tenant_id=old.tenant_id and recipient_id=old.user_id
 and notification_type like 'people.employee.%' and source_context->>'link_id'=old.id::text;end if;
 return new;
end $$;
create trigger employee_link_notice_revoke after update on people_private.account_links for each row execute function employee_self.revoke_recipient_notices();
create function employee_self.erase_case_content() returns trigger language plpgsql security definer set search_path='' as $$begin
 update employee_self.case_messages set body=null where case_id in(select id from employee_self.cases where tenant_id=new.tenant_id
  and legal_entity_id=new.legal_entity_id and employee_id=new.employee_id);
 update employee_self.cases set subject=null,erased_at=clock_timestamp() where tenant_id=new.tenant_id and legal_entity_id=new.legal_entity_id and employee_id=new.employee_id;
 update employee_self.document_publications set visible=false,label=null where document_id in(select id from people_private.documents
  where tenant_id=new.tenant_id and legal_entity_id=new.legal_entity_id and employee_id=new.employee_id);
 delete from workflow.notifications where tenant_id=new.tenant_id and notification_type like 'people.employee.%'
 and recipient_id in(select user_id from people_private.account_links where tenant_id=new.tenant_id and employee_id=new.employee_id);
 return new;
end $$;
create trigger employee_private_erasure after insert on people_private.erasure_events for each row execute function employee_self.erase_case_content();

-- Only the explicit public surface is granted; no employee role/plan is changed.
revoke all on function employee_self.recipient_current(uuid,bigint,text,text),employee_self.notify_employee(uuid,uuid,uuid,uuid,text,uuid,bigint),
 employee_self.case_summary(employee_self.cases),employee_self.case_content(uuid),employee_self.case_owner_available(employee_self.cases),
 employee_self.require_hr_staff(uuid,uuid,uuid,text),employee_self.hr_source_notification(),
 employee_self.revoke_recipient_notices(),employee_self.erase_case_content(),employee_self.guard_case_history() from public,anon,authenticated,service_role;
do $$declare f record;begin
 for f in select p.oid::regprocedure as signature from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='api'
 and p.proname in ('employee_cases_list','employee_case_detail','employee_case_command','employee_case_receipt','employee_hr_cases_list','employee_hr_case_detail',
 'employee_hr_case_command','employee_hr_case_owners','employee_hr_document_publication','employee_hr_document_publish','employee_documents_list','employee_document_access_ticket') loop
 execute format('revoke all on function %s from public,anon,authenticated,service_role',f.signature);
 execute format('grant execute on function %s to authenticated',f.signature);
 end loop;
end $$;
