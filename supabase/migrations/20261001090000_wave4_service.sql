-- W4-06 UNAPPLIED synthetic service candidate. No plan/role grants or provider activation.
revoke all on schema service from public,anon,authenticated;
insert into core.permissions(code,module,description,privileged) values
 ('service.configure','service','Configure synthetic equipment, coverage, SLA and maintenance',true),
 ('service.triage','service','Create and triage scoped service tickets',true),
 ('service.dispatch','service','Dispatch eligible service personnel',true),
 ('service.work','service','Accept, work and complete scoped work orders',true),
 ('service.approve','service','Independently approve service labor and close work orders',true),
 ('service.cost.view','service','Read scoped internal service cost',true),
 ('service.maintenance','service','Record readings and generate original maintenance occurrences',true),
 ('service.billing','service','Consume approved service billing sources',true)
on conflict(code) do nothing;
create table service.equipment(
 id uuid primary key,tenant_id uuid not null,legal_entity_id uuid not null,branch_id uuid not null,
 code text not null check(code ~ '^[A-Z0-9][A-Z0-9_-]{0,31}$'),name text not null,
 identity text not null,kind text not null check(kind in('customer','asset','stock')),
 customer_id uuid,provider_id uuid,version bigint not null default 1,status text not null default 'active',
 created_by uuid not null references auth.users(id),created_at timestamptz not null default clock_timestamp(),
 unique(tenant_id,legal_entity_id,id),unique(tenant_id,legal_entity_id,code),unique(tenant_id,legal_entity_id,identity),
 foreign key(tenant_id,legal_entity_id,branch_id) references core.branches(tenant_id,legal_entity_id,id),
 check(length(name) between 1 and 160 and name=btrim(name) and name !~ '[[:cntrl:]]'),
 check(length(identity) between 1 and 160 and identity=btrim(identity) and identity !~ '[[:cntrl:]]'),
 check((kind='customer' and customer_id is not null and provider_id is null) or(kind in('asset','stock') and provider_id is not null)),
 check(version between 1 and 9007199254740991 and status in('active','retired'))
);
create table service.coverage_versions(
 id uuid primary key,tenant_id uuid not null,legal_entity_id uuid not null,branch_id uuid not null,equipment_id uuid not null,
 kind text not null check(kind in('contract','warranty')),start_date date not null,end_date_exclusive date not null,
 name text not null,evidence_reference text not null,created_by uuid not null references auth.users(id),created_at timestamptz not null default clock_timestamp(),
 unique(tenant_id,legal_entity_id,id),foreign key(tenant_id,legal_entity_id,equipment_id) references service.equipment(tenant_id,legal_entity_id,id),
 foreign key(tenant_id,legal_entity_id,branch_id) references core.branches(tenant_id,legal_entity_id,id),check(end_date_exclusive>start_date)
);
create table service.sla_policies(
 id uuid primary key,tenant_id uuid not null,legal_entity_id uuid not null,branch_id uuid not null,
 name text not null,calendar_version_id uuid not null,start_date date not null,end_date_exclusive date not null,
 response_seconds bigint not null check(response_seconds between 1 and 31622400),resolution_seconds bigint not null check(resolution_seconds between 1 and 31622400),
 windows jsonb not null,independent_closure boolean not null,created_by uuid not null references auth.users(id),created_at timestamptz not null default clock_timestamp(),
 unique(tenant_id,legal_entity_id,id),foreign key(tenant_id,legal_entity_id,calendar_version_id) references people.work_calendar_versions(tenant_id,legal_entity_id,id),
 foreign key(tenant_id,legal_entity_id,branch_id) references core.branches(tenant_id,legal_entity_id,id),
 check(end_date_exclusive>start_date and end_date_exclusive-start_date<=366 and response_seconds<=resolution_seconds and jsonb_typeof(windows)='array' and jsonb_array_length(windows) between 1 and 2000)
);
create table service.tickets(
 id uuid primary key,tenant_id uuid not null,legal_entity_id uuid not null,branch_id uuid not null,code text not null,
 name text not null,classification text not null,customer_id uuid not null,contact_id uuid,equipment_id uuid not null,coverage_id uuid,
 policy_id uuid not null,priority text not null check(priority in('low','normal','high','urgent')),owner_id uuid,
 status text not null default 'open' check(status in('open','paused','resolved','closed','cancelled')),version bigint not null default 1,
 started_utc timestamptz not null,clock_start_utc timestamptz not null,consumed_seconds bigint not null default 0,
 response_due timestamptz not null,resolution_due timestamptz not null,response_at timestamptz,resolution_at timestamptz,
 response_breached boolean not null default false,resolution_breached boolean not null default false,
 created_by uuid not null references auth.users(id),created_at timestamptz not null default clock_timestamp(),
 unique(tenant_id,legal_entity_id,id),unique(tenant_id,legal_entity_id,code),
 foreign key(tenant_id,legal_entity_id,branch_id) references core.branches(tenant_id,legal_entity_id,id),
 foreign key(tenant_id,legal_entity_id,equipment_id) references service.equipment(tenant_id,legal_entity_id,id),
 foreign key(tenant_id,legal_entity_id,coverage_id) references service.coverage_versions(tenant_id,legal_entity_id,id),
 foreign key(tenant_id,legal_entity_id,policy_id) references service.sla_policies(tenant_id,legal_entity_id,id),
 check(version between 1 and 9007199254740991 and consumed_seconds>=0)
);
create table service.work_orders(
 id uuid primary key,tenant_id uuid not null,legal_entity_id uuid not null,branch_id uuid not null,ticket_id uuid not null,
 status text not null default 'planned' check(status in('planned','dispatched','accepted','working','completed','closed','cancelled')),
 version bigint not null default 1,employee_id uuid,accepted_by uuid,completed_by uuid,closed_by uuid,
 accepted_utc timestamptz,work_started_utc timestamptz,completed_utc timestamptz,closed_at timestamptz,
 resolution text,customer_confirmed boolean,exception_reason text,created_by uuid not null references auth.users(id),created_at timestamptz not null default clock_timestamp(),
 unique(tenant_id,legal_entity_id,id),foreign key(tenant_id,legal_entity_id,branch_id) references core.branches(tenant_id,legal_entity_id,id),
 foreign key(tenant_id,legal_entity_id,ticket_id) references service.tickets(tenant_id,legal_entity_id,id),
 foreign key(tenant_id,legal_entity_id,employee_id) references people.employees(tenant_id,legal_entity_id,id),
 check(version between 1 and 9007199254740991)
);
create table service.dispatch_bookings(
 id uuid primary key,tenant_id uuid not null,legal_entity_id uuid not null,branch_id uuid not null,order_id uuid not null,employee_id uuid not null,
 calendar_version_id uuid not null,start_utc timestamptz not null,end_utc timestamptz not null,active boolean not null default true,
 created_by uuid not null references auth.users(id),created_at timestamptz not null default clock_timestamp(),
 unique(tenant_id,legal_entity_id,id),foreign key(tenant_id,legal_entity_id,order_id) references service.work_orders(tenant_id,legal_entity_id,id),
 foreign key(tenant_id,legal_entity_id,employee_id) references people.employees(tenant_id,legal_entity_id,id),
 foreign key(tenant_id,legal_entity_id,calendar_version_id) references people.work_calendar_versions(tenant_id,legal_entity_id,id),
 foreign key(tenant_id,legal_entity_id,branch_id) references core.branches(tenant_id,legal_entity_id,id),
 check(end_utc>start_utc and end_utc-start_utc<=interval '36 hours' and extract(epoch from start_utc)%1=0 and extract(epoch from end_utc)%1=0),
 exclude using gist(employee_id with =,tstzrange(start_utc,end_utc,'[)') with &&) where(active)
);
create table service.labor(
 id uuid primary key,tenant_id uuid not null,legal_entity_id uuid not null,branch_id uuid not null,order_id uuid not null,employee_id uuid not null,
 calendar_version_id uuid not null,start_utc timestamptz not null,end_utc timestamptz not null,breaks jsonb not null,
 seconds bigint not null,claim_id uuid,allocation_ids uuid[] not null default '{}',owns_claim boolean not null default false,
 hourly_cost numeric(20,6) not null,amount numeric(20,6) not null,currency_code text not null references core.currencies(code),precision integer not null,
 billing_kind text not null default 'nonbillable' check(billing_kind in('billable','nonbillable')),
 hourly_billing numeric(20,6) not null default 0,billable_amount numeric(20,6) not null default 0,billing_reference text not null default 'Synthetic nonbillable work',
 digest text not null,status text not null default 'submitted' check(status in('submitted','approved','cancelled')),
 version bigint not null default 1,submitted_by uuid not null references auth.users(id),approved_by uuid references auth.users(id),
 billing_consumption_id uuid,reason text not null,created_at timestamptz not null default clock_timestamp(),
 current_revision_id uuid,
 unique(tenant_id,legal_entity_id,id),foreign key(tenant_id,legal_entity_id,order_id) references service.work_orders(tenant_id,legal_entity_id,id),
 foreign key(tenant_id,legal_entity_id,employee_id) references people.employees(tenant_id,legal_entity_id,id),
 foreign key(tenant_id,legal_entity_id,calendar_version_id) references people.work_calendar_versions(tenant_id,legal_entity_id,id),
 foreign key(tenant_id,legal_entity_id,branch_id) references core.branches(tenant_id,legal_entity_id,id),
 check(seconds between 1 and 129600 and hourly_cost>=0 and amount>=0 and hourly_billing>=0 and billable_amount>=0 and precision between 0 and 6 and digest ~ '^[a-f0-9]{64}$'),
 check(length(billing_reference) between 1 and 160 and billing_reference=btrim(billing_reference) and billing_reference !~ '[[:cntrl:]]'),
 check(billing_kind='billable' or hourly_billing=0 and billable_amount=0)
);
create table service.labor_revisions(
 id uuid primary key,tenant_id uuid not null,legal_entity_id uuid not null,branch_id uuid not null,
 labor_id uuid not null,employee_id uuid not null,version bigint not null,correction_id uuid not null,
 supersedes_id uuid,snapshot jsonb not null,recorded_by uuid not null references auth.users(id),recorded_at timestamptz not null default clock_timestamp(),
 unique(tenant_id,legal_entity_id,labor_id,version),unique(tenant_id,legal_entity_id,labor_id,id),
 foreign key(tenant_id,legal_entity_id,labor_id) references service.labor(tenant_id,legal_entity_id,id),
 foreign key(tenant_id,legal_entity_id,employee_id) references people.employees(tenant_id,legal_entity_id,id),
 foreign key(tenant_id,legal_entity_id,branch_id) references core.branches(tenant_id,legal_entity_id,id),
 foreign key(supersedes_id) references service.labor_revisions(id),
 check(version between 1 and 9007199254740991 and jsonb_typeof(snapshot)='object')
);
alter table service.labor add foreign key(tenant_id,legal_entity_id,id,current_revision_id)
 references service.labor_revisions(tenant_id,legal_entity_id,labor_id,id) deferrable initially deferred;
create index service_revision_scope on service.labor_revisions(tenant_id,legal_entity_id,branch_id,labor_id,id);
-- Allocation identity survives release/removal and points to one labor revision.
create table service.labor_allocations(
 allocation_id uuid primary key references people.work_allocations(id),tenant_id uuid not null,legal_entity_id uuid not null,
 branch_id uuid not null,labor_id uuid not null,revision_id uuid not null,claim_id uuid not null references people.work_claims(id),direct_claim boolean not null,
 foreign key(tenant_id,legal_entity_id,labor_id) references service.labor(tenant_id,legal_entity_id,id),
 foreign key(tenant_id,legal_entity_id,branch_id) references core.branches(tenant_id,legal_entity_id,id)
);
create index service_allocation_revision on service.labor_allocations(tenant_id,legal_entity_id,labor_id,revision_id,allocation_id);
create table service.payroll_labor_impacts(
 id uuid primary key default gen_random_uuid(),tenant_id uuid not null,legal_entity_id uuid not null,branch_id uuid not null,
 labor_id uuid not null,correction_id uuid not null,original_revision_id uuid not null,replacement_revision_id uuid not null,
 mode text not null check(mode in('apply','reverse')),approved_body jsonb not null,body jsonb not null,actor_id uuid not null references auth.users(id),recorded_at timestamptz not null default clock_timestamp(),
 unique(tenant_id,legal_entity_id,correction_id,labor_id,mode),
 foreign key(tenant_id,legal_entity_id,labor_id) references service.labor(tenant_id,legal_entity_id,id),
 foreign key(tenant_id,legal_entity_id,labor_id,replacement_revision_id) references service.labor_revisions(tenant_id,legal_entity_id,labor_id,id),
 foreign key(tenant_id,legal_entity_id,branch_id) references core.branches(tenant_id,legal_entity_id,id)
);
create index service_payroll_impact_scope on service.payroll_labor_impacts(tenant_id,legal_entity_id,branch_id,labor_id,correction_id);
create table service.maintenance_plans(
 id uuid primary key,tenant_id uuid not null,legal_entity_id uuid not null,branch_id uuid not null,equipment_id uuid not null,policy_id uuid not null,
 name text not null,basis text not null check(basis in('calendar','meter')),interval_units bigint not null,
 next_date date,next_meter bigint,version bigint not null default 1,created_by uuid not null references auth.users(id),created_at timestamptz not null default clock_timestamp(),
 unique(tenant_id,legal_entity_id,id),foreign key(tenant_id,legal_entity_id,equipment_id) references service.equipment(tenant_id,legal_entity_id,id),
 foreign key(tenant_id,legal_entity_id,policy_id) references service.sla_policies(tenant_id,legal_entity_id,id),
 foreign key(tenant_id,legal_entity_id,branch_id) references core.branches(tenant_id,legal_entity_id,id),
 check(interval_units between 1 and 9007199254740991 and (basis='calendar' and interval_units<=366 and next_date is not null and next_meter is null or basis='meter' and next_meter>0 and next_date is null))
);
create table service.meter_readings(
 id uuid primary key,tenant_id uuid not null,legal_entity_id uuid not null,branch_id uuid not null,equipment_id uuid not null,
 kind text not null check(kind in('initial','reading','reset','rollover')),raw_value bigint not null,logical_value bigint not null,
 previous_id uuid,rollover_max bigint,observed_utc timestamptz not null,reason text not null,recorded_by uuid not null references auth.users(id),
 created_at timestamptz not null default clock_timestamp(),unique(tenant_id,legal_entity_id,id),
 foreign key(tenant_id,legal_entity_id,equipment_id) references service.equipment(tenant_id,legal_entity_id,id),
 foreign key(tenant_id,legal_entity_id,previous_id) references service.meter_readings(tenant_id,legal_entity_id,id),
 foreign key(tenant_id,legal_entity_id,branch_id) references core.branches(tenant_id,legal_entity_id,id),
 check(raw_value between 0 and 9007199254740991 and logical_value between 0 and 9007199254740991)
);
create unique index service_meter_initial on service.meter_readings(equipment_id) where previous_id is null;
create unique index service_meter_successor on service.meter_readings(previous_id) where previous_id is not null;
create table service.maintenance_occurrences(
 id uuid primary key,tenant_id uuid not null,legal_entity_id uuid not null,branch_id uuid not null,plan_id uuid not null,plan_version bigint not null,
 occurrence_key text not null,original_due_date date,original_due_meter bigint,deferred_until date,
 ticket_id uuid not null,order_id uuid not null,reading_id uuid,version bigint not null default 1,reason text not null,created_by uuid not null references auth.users(id),created_at timestamptz not null default clock_timestamp(),
 unique(tenant_id,legal_entity_id,id),unique(plan_id,occurrence_key),
 foreign key(tenant_id,legal_entity_id,plan_id) references service.maintenance_plans(tenant_id,legal_entity_id,id),
 foreign key(tenant_id,legal_entity_id,ticket_id) references service.tickets(tenant_id,legal_entity_id,id),
 foreign key(tenant_id,legal_entity_id,order_id) references service.work_orders(tenant_id,legal_entity_id,id),
 foreign key(tenant_id,legal_entity_id,reading_id) references service.meter_readings(tenant_id,legal_entity_id,id),
 foreign key(tenant_id,legal_entity_id,branch_id) references core.branches(tenant_id,legal_entity_id,id)
);
create table service.events(
 id uuid primary key default gen_random_uuid(),tenant_id uuid not null,legal_entity_id uuid not null,branch_id uuid not null,
 aggregate_id uuid not null,kind text not null,version bigint not null,action text not null,reason text not null,
 facts jsonb not null,actor_id uuid not null references auth.users(id),recorded_at timestamptz not null default clock_timestamp(),
 unique(tenant_id,legal_entity_id,id),foreign key(tenant_id,legal_entity_id,branch_id) references core.branches(tenant_id,legal_entity_id,id)
);
create index service_equipment_scope on service.equipment(tenant_id,legal_entity_id,branch_id,id);
create index service_policy_scope on service.sla_policies(tenant_id,legal_entity_id,branch_id,id);
create index service_coverage_scope on service.coverage_versions(tenant_id,legal_entity_id,branch_id,equipment_id,id);
create index service_ticket_scope on service.tickets(tenant_id,legal_entity_id,branch_id,id);
create index service_order_scope on service.work_orders(tenant_id,legal_entity_id,branch_id,ticket_id,id);
create index service_dispatch_scope on service.dispatch_bookings(tenant_id,legal_entity_id,branch_id,order_id,id);
create index service_labor_scope on service.labor(tenant_id,legal_entity_id,branch_id,order_id,id);
create index service_plan_scope on service.maintenance_plans(tenant_id,legal_entity_id,branch_id,id);
create index service_meter_scope on service.meter_readings(tenant_id,legal_entity_id,branch_id,equipment_id,observed_utc desc,id);
create index service_occurrence_scope on service.maintenance_occurrences(tenant_id,legal_entity_id,branch_id,plan_id,id);
create index service_event_scope on service.events(tenant_id,legal_entity_id,branch_id,aggregate_id,id);
do $$declare r record;begin for r in select tablename from pg_tables where schemaname='service' loop
 execute format('alter table service.%I enable row level security',r.tablename);
 execute format('alter table service.%I force row level security',r.tablename);end loop;end $$;
revoke all on all tables in schema service from public,anon,authenticated;
create function service.immutable() returns trigger language plpgsql set search_path='' as $$begin
 raise exception using errcode='55000',message='SERVICE_HISTORY_IMMUTABLE';end $$;
create trigger service_coverage_immutable before update or delete on service.coverage_versions for each row execute function service.immutable();
create trigger service_policy_immutable before update or delete on service.sla_policies for each row execute function service.immutable();
create trigger service_meter_immutable before update or delete on service.meter_readings for each row execute function service.immutable();
create trigger service_event_immutable before update or delete on service.events for each row execute function service.immutable();
create trigger service_labor_revision_immutable before update or delete on service.labor_revisions for each row execute function service.immutable();
create trigger service_labor_allocation_immutable before update or delete on service.labor_allocations for each row execute function service.immutable();
create trigger service_payroll_impact_immutable before update or delete on service.payroll_labor_impacts for each row execute function service.immutable();
create function service.require_access(t uuid,e uuid,b uuid,cap text) returns void language plpgsql security definer set search_path='' as $$begin
 if cap is null or cap not in('service.view','service.configure','service.triage','service.dispatch','service.work','service.approve','service.cost.view','service.maintenance','service.billing') then
  raise exception using errcode='42501',message='SERVICE_SCOPE_DENIED';end if;
 perform core.wave3_require_scope(t,'service.view',e,b);perform core.wave3_require_scope(t,cap,e,b);
 if not exists(select 1 from billing.tenant_subscriptions s join billing.plan_entitlements p on p.plan_code=s.plan_code where s.tenant_id=t and p.entitlement_code='module.service' and p.enabled
  and(s.status='trialing' and s.trial_ends_at>now() or s.status='active' and(s.current_period_ends_at is null or s.current_period_ends_at>now()))) then
  raise exception using errcode='42501',message='SERVICE_ENTITLEMENT_REQUIRED';end if;
 if cap<>'service.view' and coalesce(auth.jwt()->>'aal','aal1')<>'aal2' then raise exception using errcode='42501',message='SERVICE_MFA_REQUIRED';end if;
end $$;
create function service.payroll_source(p_t uuid,p_e uuid,p_b uuid,p_employee uuid,p_claim uuid) returns jsonb
language plpgsql stable security definer set search_path='' as $$declare l service.labor%rowtype;begin
 select x.* into l from service.labor x join people.work_claims c on c.id=x.claim_id where x.tenant_id=p_t and x.legal_entity_id=p_e and x.branch_id=p_b and x.employee_id=p_employee
  and x.claim_id=p_claim and x.status='approved' and x.owns_claim and c.active and c.source_kind='service' and c.source_id=coalesce(x.current_revision_id,x.id) and c.employee_id=x.employee_id and c.branch_id=x.branch_id
  and c.payable_seconds=(service.snapshot('labor',x.id)->>'seconds')::bigint;
 if l.id is null then raise exception using errcode='55000',message='PAYROLL_APPROVED_SOURCE_PROVIDER_REQUIRED';end if;
 return jsonb_build_object('source_id',coalesce(l.current_revision_id,l.id),'source_version',l.version,'paid_seconds',(service.snapshot('labor',l.id)->>'seconds')::bigint);end $$;
create function service.billing_source(p_t uuid,p_e uuid,p_b uuid,p_id uuid) returns jsonb
language plpgsql stable security definer set search_path='' as $$declare l service.labor%rowtype;customer uuid;begin
 select x.* into l from service.labor x join service.work_orders w on w.id=x.order_id where x.tenant_id=p_t and x.legal_entity_id=p_e and x.branch_id=p_b and x.id=p_id
  and x.status='approved' and x.billing_kind='billable' and x.billing_consumption_id is null and w.status in('completed','closed');
 if l.id is null then raise exception using errcode='55000',message='SERVICE_BILLING_SOURCE_UNAVAILABLE';end if;
 select t.customer_id into customer from service.tickets t join service.work_orders w on w.ticket_id=t.id where w.id=l.order_id;
 return jsonb_build_object('source_id',coalesce(l.current_revision_id,l.id),'provider_source_id',l.id,'source_version',l.version,'digest',service.snapshot('labor',l.id)->>'digest','customer_id',customer,'seconds',(service.snapshot('labor',l.id)->>'seconds')::bigint,'amount',service.snapshot('labor',l.id)->>'billable_amount','currency_code',l.currency_code,'order_id',l.order_id);end $$;
create function service.consume_billing_source(p_t uuid,p_e uuid,p_b uuid,p_id uuid,p_version bigint,p_digest text,p_consumption uuid) returns void
language plpgsql security definer set search_path='' as $$declare l service.labor%rowtype;begin
 select * into l from service.labor where tenant_id=p_t and legal_entity_id=p_e and branch_id=p_b and id=p_id for update;
 if l.id is null or l.status<>'approved' or l.billing_kind<>'billable' or l.version<>p_version or service.snapshot('labor',l.id)->>'digest'<>p_digest or l.billing_consumption_id is not null or p_consumption is null
  or not exists(select 1 from service.work_orders where id=l.order_id and status in('completed','closed')) then raise exception using errcode='55000',message='SERVICE_BILLING_SOURCE_UNAVAILABLE';end if;
 update service.labor set billing_consumption_id=p_consumption where id=p_id;end $$;
create function service.public_snapshot(kind text,id uuid,p_cost boolean) returns jsonb language plpgsql stable security definer set search_path='' as $$declare r jsonb:=service.snapshot(kind,id);begin
 if kind='policy' then r:=r-'windows';end if;
 if kind='labor' and not p_cost then r:=r-array['hourly_cost','amount'];end if;return r;end $$;
create function service.table_for(kind text) returns text language sql immutable set search_path='' as $$select case kind
 when 'equipment' then 'equipment' when 'coverage' then 'coverage_versions' when 'policy' then 'sla_policies' when 'ticket' then 'tickets' when 'order' then 'work_orders'
 when 'labor' then 'labor' when 'plan' then 'maintenance_plans' when 'reading' then 'meter_readings' when 'occurrence' then 'maintenance_occurrences' end $$;
create function api.service_list(p_tenant_id uuid,p_legal_entity_id uuid,p_branch_id uuid,p_kind text,p_after uuid default null,p_parent uuid default null) returns jsonb
language plpgsql stable security definer set search_path='' as $$declare items jsonb;tablename text:=service.table_for(p_kind);parent_column text;cost boolean;begin
 perform service.require_access(p_tenant_id,p_legal_entity_id,p_branch_id,'service.view');
 if tablename is null then raise exception using errcode='22023',message='SERVICE_KIND_INVALID';end if;
 cost:=core.has_permission(p_tenant_id,'service.cost.view',p_legal_entity_id,p_branch_id);
 parent_column:=case p_kind when 'coverage' then 'equipment_id' when 'order' then 'ticket_id' when 'labor' then 'order_id' when 'reading' then 'equipment_id' when 'occurrence' then 'plan_id' end;
 if p_parent is not null and parent_column is null then raise exception using errcode='22023',message='SERVICE_PARENT_INVALID';end if;
 execute format('select coalesce(jsonb_agg(service.public_snapshot($1,q.id,$6) order by q.id),''[]''::jsonb) from(select id from service.%I where tenant_id=$2 and legal_entity_id=$3 and branch_id=$4 and($5 is null or id>$5)%s order by id limit 51) q',
  tablename,case when p_parent is null then '' else format(' and %I=$7',parent_column) end)
 into items using p_kind,p_tenant_id,p_legal_entity_id,p_branch_id,p_after,cost,p_parent;
 return jsonb_build_object('tenant_id',p_tenant_id,'legal_entity_id',p_legal_entity_id,'branch_id',p_branch_id,'kind',p_kind,'items',items-50,'next_cursor',case when jsonb_array_length(items)>50 then items->49->>'id' end);end $$;
create function api.service_detail(p_tenant_id uuid,p_legal_entity_id uuid,p_branch_id uuid,p_kind text,p_id uuid,p_after uuid default null) returns jsonb
language plpgsql stable security definer set search_path='' as $$declare r jsonb;events jsonb;cost boolean;begin
 perform service.require_access(p_tenant_id,p_legal_entity_id,p_branch_id,'service.view');cost:=core.has_permission(p_tenant_id,'service.cost.view',p_legal_entity_id,p_branch_id);
 r:=service.public_snapshot(p_kind,p_id,cost);
 if r is null or r->>'tenant_id'<>p_tenant_id::text or r->>'legal_entity_id'<>p_legal_entity_id::text or r->>'branch_id'<>p_branch_id::text then raise exception using errcode='P0002',message='SERVICE_NOT_FOUND';end if;
 select coalesce(jsonb_agg(to_jsonb(x)||jsonb_build_object('facts',case when x.kind='labor' and not cost then x.facts-array['hourly_cost','amount'] when x.kind='policy' then x.facts-'windows' else x.facts end) order by x.id),'[]') into events
 from(select * from service.events where tenant_id=p_tenant_id and legal_entity_id=p_legal_entity_id and branch_id=p_branch_id and aggregate_id=p_id and kind=p_kind and(p_after is null or id>p_after) order by id limit 51) x;
 return jsonb_build_object('record',r,'events',events-50,'next_cursor',case when jsonb_array_length(events)>50 then events->49->>'id' end);end $$;
create function api.service_choices(p_tenant_id uuid,p_legal_entity_id uuid,p_branch_id uuid,p_kind text,p_after uuid default null,p_parent uuid default null) returns jsonb
language plpgsql stable security definer set search_path='' as $$declare items jsonb;begin
 perform service.require_access(p_tenant_id,p_legal_entity_id,p_branch_id,'service.view');
 if p_kind='customer' then select coalesce(jsonb_agg(to_jsonb(q) order by q.id),'[]') into items from(select id,display_name name,version from crm.parties where tenant_id=p_tenant_id and status='active' and kind in('customer','both') and(p_after is null or id>p_after) order by id limit 51) q;
 elsif p_kind='contact' then select coalesce(jsonb_agg(to_jsonb(q) order by q.id),'[]') into items from(select id,name,version from crm.contacts where tenant_id=p_tenant_id and party_id=p_parent and status='active' and(p_after is null or id>p_after) order by id limit 51) q;
 elsif p_kind='employee' then select coalesce(jsonb_agg(to_jsonb(q) order by q.id),'[]') into items from(select x.id,x.display_name name,x.version from people.employees x where x.tenant_id=p_tenant_id and x.legal_entity_id=p_legal_entity_id and exists(select 1 from people.employment_assignments a where a.employee_id=x.id and a.branch_id=p_branch_id and daterange(a.start_date,a.end_date_exclusive,'[)') @> current_date) and(p_after is null or x.id>p_after) order by x.id limit 51) q;
 elsif p_kind='calendar' then select coalesce(jsonb_agg(to_jsonb(q) order by q.id),'[]') into items from(select v.id,c.name||' / '||v.start_date::text name,c.version from people.work_calendar_versions v join people.work_calendars c on c.id=v.calendar_id where v.tenant_id=p_tenant_id and v.legal_entity_id=p_legal_entity_id and(p_after is null or v.id>p_after) order by v.id limit 51) q;
 elsif p_kind='claim' then
  perform service.require_access(p_tenant_id,p_legal_entity_id,p_branch_id,'service.work');
  select coalesce(jsonb_agg(to_jsonb(q) order by q.id),'[]') into items from(
   select x.id,employee.display_name||' / '||to_char(x.start_utc at time zone cal.timezone,'YYYY-MM-DD HH24:MI')||' to '||to_char(x.end_utc at time zone cal.timezone,'HH24:MI')||' / approved attendance' name,1::bigint version
   from people.work_claims x join people.employees employee on employee.id=x.employee_id join people.work_calendar_versions cal on cal.id=x.calendar_version_id
   join people.attendance_entries a on a.active_claim_id=x.id and a.status='approved'
   where x.tenant_id=p_tenant_id and x.legal_entity_id=p_legal_entity_id and x.branch_id=p_branch_id and x.employee_id=p_parent and x.active and x.source_kind='attendance'
    and(p_after is null or x.id>p_after) order by x.id limit 51) q;
 else raise exception using errcode='22023',message='SERVICE_CHOICE_INVALID';end if;
 return jsonb_build_object('tenant_id',p_tenant_id,'legal_entity_id',p_legal_entity_id,'branch_id',p_branch_id,'kind',p_kind,'items',items-50,'next_cursor',case when jsonb_array_length(items)>50 then items->49->>'id' end);end $$;
create function api.service_own_receipt(p_tenant_id uuid,p_legal_entity_id uuid,p_branch_id uuid,p_idempotency_key uuid,p_action text) returns jsonb
language plpgsql stable security definer set search_path='' as $$declare r core.command_receipts%rowtype;begin
 perform service.require_access(p_tenant_id,p_legal_entity_id,p_branch_id,service.capability(p_action));
 select * into r from core.command_receipts where tenant_id=p_tenant_id and legal_entity_id=p_legal_entity_id and branch_id=p_branch_id and actor_id=auth.uid() and idempotency_key=p_idempotency_key and command_name='service.'||p_action;
 return case when r.idempotency_key is not null then r.response end;end $$;
create function service.text(p jsonb,n integer) returns text language plpgsql immutable set search_path='' as $$declare s text;begin
 if p is null or jsonb_typeof(p)<>'string' then raise exception using errcode='22023',message='SERVICE_TEXT_INVALID';end if;s:=p#>>'{}';
 if s<>btrim(s) or length(s) not between 1 and n or s ~ '[[:cntrl:]]' then raise exception using errcode='22023',message='SERVICE_TEXT_INVALID';end if;return s;end $$;
create function service.integer(p jsonb,maximum bigint,p_min bigint default 0) returns bigint language plpgsql immutable set search_path='' as $$begin
 if p is null or jsonb_typeof(p)<>'number' or p::text !~ '^(0|[1-9][0-9]*)$' or p::text::numeric not between p_min and maximum then
  raise exception using errcode='22023',message='SERVICE_INTEGER_INVALID';end if;return p::text::bigint;end $$;
create function service.utc(p jsonb) returns timestamptz language plpgsql immutable set search_path='' as $$begin
 if p is null or jsonb_typeof(p)<>'string' or p#>>'{}' !~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$' then
  raise exception using errcode='22023',message='SERVICE_UTC_INVALID';end if;return (p#>>'{}')::timestamptz;end $$;
create function service.amount(p jsonb) returns numeric language plpgsql immutable set search_path='' as $$begin
 if p is null or jsonb_typeof(p)<>'string' or p#>>'{}' !~ '^(0|[1-9][0-9]{0,13})(\.[0-9]{1,6})?$' then
  raise exception using errcode='22023',message='SERVICE_AMOUNT_INVALID';end if;return (p#>>'{}')::numeric;end $$;
create function service.round_ratio(n numeric,d numeric,p integer) returns numeric language plpgsql immutable set search_path='' as $$declare q numeric;r numeric;den numeric;begin
 if n<0 or d<=0 or p not between 0 and 6 or n<>trunc(n) or d<>trunc(d) then raise exception using errcode='22023',message='SERVICE_RATIO_INVALID';end if;
 den:=d*power(10::numeric,6-p);q:=div(n,den);r:=mod(n,den);if r*2>den or r*2=den and mod(q,2)=1 then q:=q+1;end if;
 return q*power(10::numeric,6-p)/1000000;end $$;
create function service.windows(t uuid,e uuid,p_calendar uuid,p_start date,p_end date,offsets jsonb) returns jsonb
language plpgsql stable security definer set search_path='' as $$declare c people.work_calendar_versions%rowtype;d date;daypart date;x jsonb;o jsonb;boundary jsonb;sl timestamp;el timestamp;ps timestamp;pe timestamp;su timestamptz;eu timestamptz;so integer;eo integer;result jsonb:='[]';begin
 select * into c from people.work_calendar_versions where tenant_id=t and legal_entity_id=e and id=p_calendar;
 if c.id is null or p_end<=p_start or p_end-p_start>366 or p_start<c.start_date or p_end>c.end_date_exclusive or coalesce(jsonb_typeof(offsets),'null')<>'array' or jsonb_array_length(offsets)>2000 then
  raise exception using errcode='22023',message='SERVICE_CALENDAR_INVALID';end if;
 if exists(select 1 from jsonb_array_elements(offsets) q where jsonb_typeof(q)<>'object' or not(q ?& array['date','start_minute','start_offset_seconds','end_offset_seconds'])
  or exists(select 1 from jsonb_object_keys(q) k where k<>all(array['date','start_minute','start_offset_seconds','end_offset_seconds']))
  or q->>'date' !~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}$' or jsonb_typeof(q->'start_minute')<>'number' or q->>'start_minute' !~ '^[0-9]+$'
  or (q->>'start_minute')::integer not between 0 and 1439 or jsonb_typeof(q->'start_offset_seconds')<>'number' or jsonb_typeof(q->'end_offset_seconds')<>'number'
  or q->>'start_offset_seconds' !~ '^-?[0-9]+$' or q->>'end_offset_seconds' !~ '^-?[0-9]+$'
  or (q->>'start_offset_seconds')::integer not between -86400 and 86400 or (q->>'end_offset_seconds')::integer not between -86400 and 86400)
  or exists(select 1 from jsonb_array_elements(offsets) q group by q->>'date',q->>'start_minute' having count(*)>1) then raise exception using errcode='22023',message='SERVICE_CALENDAR_OFFSET_INVALID';end if;
 for d in select g::date from generate_series(greatest(p_start-1,c.start_date)::timestamp,(p_end-1)::timestamp,interval '1 day') g loop
  for x in select value from jsonb_array_elements(c.weekly_intervals) where(value->>'day_of_week')::integer=extract(isodow from d)::integer loop
   sl:=d::timestamp+(x->>'start_minute')::integer*interval '1 minute';el:=d::timestamp+(x->>'end_day_offset')::integer*interval '1 day'+(x->>'end_minute')::integer*interval '1 minute';
   select q into o from jsonb_array_elements(offsets) q where q->>'date'=d::text and(q->>'start_minute')::integer=(x->>'start_minute')::integer;
   for daypart in select g::date from generate_series(greatest(sl::date,p_start)::timestamp,least((el-interval '1 microsecond')::date,p_end-1)::timestamp,interval '1 day') g loop
    if exists(select 1 from jsonb_array_elements(c.date_overrides) q where q->>'date'=daypart::text and not(q->>'is_working_day')::boolean) then continue;end if;
    ps:=greatest(sl,daypart::timestamp);pe:=least(el,(daypart+1)::timestamp);so:=null;eo:=null;
    if ps=sl then so:=(o->>'start_offset_seconds')::integer;else
     select q into boundary from jsonb_array_elements(offsets) q where q->>'date'=ps::date::text and(q->>'start_minute')::integer=0;so:=(boundary->>'start_offset_seconds')::integer;end if;
    if pe=el then eo:=(o->>'end_offset_seconds')::integer;else
     select q into boundary from jsonb_array_elements(offsets) q where q->>'date'=pe::date::text and(q->>'start_minute')::integer=0;eo:=(boundary->>'start_offset_seconds')::integer;end if;
    su:=people.resolve_local_instant(c.timezone,ps,so);eu:=people.resolve_local_instant(c.timezone,pe,eo);
    if eu<=su or eu-su>interval '36 hours' then raise exception using errcode='22023',message='SERVICE_CALENDAR_INVALID';end if;
    result:=result||jsonb_build_array(jsonb_build_object('start_utc',to_char(su at time zone 'UTC','YYYY-MM-DD"T"HH24:MI:SS"Z"'),'end_utc',to_char(eu at time zone 'UTC','YYYY-MM-DD"T"HH24:MI:SS"Z"'),
     'start_local',ps,'end_local',pe,'timezone',c.timezone,'start_offset_seconds',extract(epoch from ps-(su at time zone 'UTC'))::integer,'end_offset_seconds',extract(epoch from pe-(eu at time zone 'UTC'))::integer));
   end loop;
  end loop;
 end loop;
 if jsonb_array_length(result)=0 or jsonb_array_length(result)>2000 then raise exception using errcode='22023',message='SERVICE_CALENDAR_EMPTY';end if;
 if exists(with spans as(select value,lag(value->>'end_utc') over(order by value->>'start_utc') previous from jsonb_array_elements(result)) select 1 from spans where value->>'start_utc'<previous) then raise exception using errcode='22023',message='SERVICE_CALENDAR_OVERLAP';end if;
 return (select jsonb_agg(value order by value->>'start_utc') from jsonb_array_elements(result));end $$;
create function service.elapsed(w jsonb,s timestamptz,e timestamptz) returns bigint language sql immutable set search_path='' as $$
 select coalesce(sum(greatest(0,extract(epoch from least(e,(x->>'end_utc')::timestamptz)-greatest(s,(x->>'start_utc')::timestamptz)))::bigint),0) from jsonb_array_elements(w) x $$;
create function service.due(w jsonb,s timestamptz,remaining bigint) returns timestamptz language plpgsql immutable set search_path='' as $$declare x jsonb;a timestamptz;b timestamptz;seconds bigint;begin
 if remaining<=0 then return s;end if;
 for x in select value from jsonb_array_elements(w) loop a:=greatest(s,(x->>'start_utc')::timestamptz);b:=(x->>'end_utc')::timestamptz;
  if b<=a then continue;end if;seconds:=extract(epoch from b-a)::bigint;if remaining<=seconds then return a+remaining*interval '1 second';end if;remaining:=remaining-seconds;end loop;
 raise exception using errcode='55000',message='SERVICE_SLA_HORIZON_EXHAUSTED';end $$;
create function service.check_customer(t uuid,customer uuid,contact uuid) returns void language plpgsql stable security definer set search_path='' as $$begin
 if not exists(select 1 from crm.parties where tenant_id=t and id=customer and status='active' and kind in('customer','both')) or contact is not null and not exists(select 1 from crm.contacts where tenant_id=t and id=contact and party_id=customer and status='active') then
  raise exception using errcode='22023',message='SERVICE_CUSTOMER_INVALID';end if;end $$;
create function api.service_authorize(p_tenant_id uuid,p_legal_entity_id uuid,p_branch_id uuid,p_capability text) returns jsonb
language plpgsql stable security definer set search_path='' as $$begin perform service.require_access(p_tenant_id,p_legal_entity_id,p_branch_id,p_capability);
 return jsonb_build_object('actor_id',auth.uid(),'tenant_id',p_tenant_id,'legal_entity_id',p_legal_entity_id,'branch_id',p_branch_id,'capability',p_capability,'authorized',true,
  'parts_provider',false,'billing_provider',false,'asset_provider',false,
  'currency_code',(select currency_code from core.legal_entities where tenant_id=p_tenant_id and id=p_legal_entity_id),
  'precision',(select rounding_scale from core.legal_entities where tenant_id=p_tenant_id and id=p_legal_entity_id));end $$;
create function service.capability(act text) returns text language sql immutable set search_path='' as $$select case
 when act in('equipment','coverage','policy','plan') then 'service.configure'
 when act in('ticket','pause','resume','reprioritize','evaluate','cancel_ticket') then 'service.triage'
 when act in('order','dispatch','cancel_order') then 'service.dispatch'
 when act in('accept','start','complete','labor') then 'service.work'
 when act in('approve_labor','cancel_labor','close') then 'service.approve'
 when act in('reading','generate','defer') then 'service.maintenance'
 when act in('parts_reserve','parts_issue','parts_return','bill') then 'service.billing' end $$;
create function service.fields(act text) returns text[] language sql immutable set search_path='' as $$select array['action','id','reason']||case act
 when 'equipment' then array['code','name','identity','kind','customer_id','provider_id']
 when 'coverage' then array['equipment_id','kind','name','start_date','end_date_exclusive','evidence_reference']
 when 'policy' then array['name','calendar_version_id','start_date','end_date_exclusive','response_seconds','resolution_seconds','independent_closure','offsets']
 when 'ticket' then array['code','name','classification','customer_id','contact_id','equipment_id','coverage_id','policy_id','priority','owner_id','observed_utc']
 when 'order' then array['ticket_id'] when 'dispatch' then array['employee_id','calendar_version_id','start_utc','end_utc','booking_id']
 when 'complete' then array['observed_utc','resolution','customer_confirmed','exception_reason']
 when 'accept' then array['observed_utc'] when 'start' then array['observed_utc']
 when 'labor' then array['order_id','employee_id','calendar_version_id','start_utc','end_utc','breaks','claim_id','hourly_cost','currency_code','precision','billing_kind','hourly_billing','billing_reference']
 when 'plan' then array['equipment_id','policy_id','name','basis','interval_units','next_date','next_meter']
 when 'reading' then array['equipment_id','kind','raw_value','rollover_max','observed_utc']
 when 'generate' then array['ticket_id','order_id','occurrence_id','observed_utc']
 when 'defer' then array['deferred_until'] when 'reprioritize' then array['policy_id','priority','observed_utc']
 when 'pause' then array['observed_utc'] when 'resume' then array['observed_utc'] when 'evaluate' then array['observed_utc']
 else '{}'::text[] end $$;
create function service.ticket_create(t uuid,e uuid,b uuid,id uuid,p jsonb) returns void language plpgsql security definer set search_path='' as $$
declare policy service.sla_policies%rowtype;equipment service.equipment%rowtype;at timestamptz:=service.utc(p->'observed_utc');begin
 perform service.check_customer(t,(p->>'customer_id')::uuid,(p->>'contact_id')::uuid);
 select q.* into equipment from service.equipment q where q.tenant_id=t and q.legal_entity_id=e and q.branch_id=b and q.id=(p->>'equipment_id')::uuid and q.status='active';
 select * into policy from service.sla_policies where tenant_id=t and legal_entity_id=e and branch_id=b and sla_policies.id=(p->>'policy_id')::uuid;
 if equipment.id is null or policy.id is null or equipment.customer_id is distinct from (p->>'customer_id')::uuid
  or(p->>'coverage_id') is not null and not exists(select 1 from service.coverage_versions c where c.tenant_id=t and c.legal_entity_id=e and c.branch_id=b and c.id=(p->>'coverage_id')::uuid and c.equipment_id=equipment.id
    and daterange(c.start_date,c.end_date_exclusive,'[)') @> (at at time zone (select timezone from core.legal_entities where tenant_id=t and legal_entities.id=e))::date)
  or p->>'code' !~ '^[A-Z0-9][A-Z0-9_-]{0,31}$' or p->>'priority' not in('low','normal','high','urgent') or at>clock_timestamp()+interval '5 minutes' then
  raise exception using errcode='22023',message='SERVICE_TICKET_INVALID';end if;
 insert into service.tickets(id,tenant_id,legal_entity_id,branch_id,code,name,classification,customer_id,contact_id,equipment_id,coverage_id,policy_id,priority,owner_id,started_utc,clock_start_utc,response_due,resolution_due,created_by)
 values(id,t,e,b,p->>'code',service.text(p->'name',160),service.text(p->'classification',80),(p->>'customer_id')::uuid,(p->>'contact_id')::uuid,equipment.id,(p->>'coverage_id')::uuid,policy.id,p->>'priority',(p->>'owner_id')::uuid,
  at,at,service.due(policy.windows,at,policy.response_seconds),service.due(policy.windows,at,policy.resolution_seconds),auth.uid());end $$;
create function service.snapshot(kind text,id uuid) returns jsonb language plpgsql stable security definer set search_path='' as $$declare r jsonb;begin
 case kind when 'equipment' then select to_jsonb(x) into r from service.equipment x where x.id=snapshot.id;
 when 'coverage' then select to_jsonb(x)||jsonb_build_object('version',1) into r from service.coverage_versions x where x.id=snapshot.id;
 when 'policy' then select to_jsonb(x)||jsonb_build_object('version',1) into r from service.sla_policies x where x.id=snapshot.id;
 when 'ticket' then select to_jsonb(x) into r from service.tickets x where x.id=snapshot.id;
 when 'order' then select to_jsonb(x) into r from service.work_orders x where x.id=snapshot.id;
 when 'labor' then select to_jsonb(x)||jsonb_build_object('hourly_cost',x.hourly_cost::text,'amount',x.amount::text,'hourly_billing',x.hourly_billing::text,'billable_amount',x.billable_amount::text)
  ||coalesce((select v.snapshot from service.labor_revisions v where v.id=x.current_revision_id),'{}')
  ||jsonb_build_object('version',x.version,'claim_id',x.claim_id,'allocation_ids',x.allocation_ids,'current_revision_id',x.current_revision_id,'billing_consumption_id',x.billing_consumption_id,'status',x.status) into r from service.labor x where x.id=snapshot.id;
 when 'plan' then select to_jsonb(x) into r from service.maintenance_plans x where x.id=snapshot.id;
 when 'reading' then select to_jsonb(x)||jsonb_build_object('version',1) into r from service.meter_readings x where x.id=snapshot.id;
 when 'occurrence' then select to_jsonb(x) into r from service.maintenance_occurrences x where x.id=snapshot.id;
 end case;return r;end $$;
create function api.service_command(p_tenant_id uuid,p_legal_entity_id uuid,p_branch_id uuid,p_command_id uuid,p_idempotency_key uuid,p_issued_at timestamptz,p_payload jsonb,p_expected_version bigint)
returns jsonb language plpgsql security definer set search_path='' as $$
#variable_conflict use_variable
<<command_work>>
declare act text:=p_payload->>'action';cap text:=service.capability(act);id uuid;kind text;hash text;replay jsonb;reason text;before_state jsonb;after_state jsonb;event_state jsonb;
 t service.tickets%rowtype;w service.work_orders%rowtype;policy service.sla_policies%rowtype;eq service.equipment%rowtype;labor service.labor%rowtype;plan service.maintenance_plans%rowtype;meter service.meter_readings%rowtype;
 observed timestamptz;start_utc timestamptz;end_utc timestamptz;segment_cursor timestamptz;employee uuid;calendar uuid;claim uuid;allocation uuid;allocations uuid[]:='{}';owns boolean:=false;
 calendar_row people.work_calendar_versions%rowtype;seconds bigint;cost numeric;amount numeric;billrate numeric;billamount numeric;billkind text;billref text;precision integer;currency text;digest text;raw bigint;logical bigint;delta bigint;rollmax bigint;
 windows jsonb;segment record;occurrence_key text;occurrence uuid;newticket uuid;neworder uuid;version bigint:=1;begin
 if cap is null or coalesce(jsonb_typeof(p_payload),'null')<>'object' or octet_length(p_payload::text)>65536 or p_command_id is null or p_idempotency_key is null
  or p_issued_at is null or p_issued_at>clock_timestamp()+interval '5 minutes' or p_expected_version is null or p_expected_version not between 0 and 9007199254740990
  or coalesce(p_payload->>'id','') !~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
  or exists(select 1 from jsonb_object_keys(p_payload) k where k<>all(service.fields(act))) then raise exception using errcode='22023',message='SERVICE_COMMAND_INVALID';end if;
 perform service.require_access(p_tenant_id,p_legal_entity_id,p_branch_id,cap);
 id:=(p_payload->>'id')::uuid;reason:=service.text(p_payload->'reason',1000);
 hash:=core.wave3_request_hash('service.'||act,p_command_id,p_tenant_id,p_legal_entity_id,p_branch_id,p_payload,p_expected_version);
 replay:=core.wave3_replay(p_tenant_id,'service.'||act,p_command_id,p_idempotency_key,hash);if replay is not null then return replay;end if;
 if act in('parts_reserve','parts_issue','parts_return') then raise exception using errcode='55000',message='SERVICE_PARTS_PROVIDER_UNAVAILABLE';end if;
 if act='bill' then raise exception using errcode='55000',message='SERVICE_BILLING_ADAPTER_UNAVAILABLE';end if;
 if act in('dispatch','labor') then employee:=(p_payload->>'employee_id')::uuid;
 elsif act in('approve_labor','cancel_labor') then select l.employee_id into employee from service.labor l where l.tenant_id=p_tenant_id and l.legal_entity_id=p_legal_entity_id and l.branch_id=p_branch_id and l.id=command_work.id;
 elsif act in('accept','start','complete','close','cancel_order') then select employee_id into employee from service.work_orders where tenant_id=p_tenant_id and legal_entity_id=p_legal_entity_id and branch_id=p_branch_id and work_orders.id=command_work.id;end if;
 perform pg_advisory_xact_lock(hashtextextended('people.payroll:'||p_tenant_id||':'||p_legal_entity_id,0));
 perform pg_advisory_xact_lock(hashtextextended('projects:'||p_tenant_id||':'||p_legal_entity_id,0));
 perform pg_advisory_xact_lock(hashtextextended('service:'||p_tenant_id||':'||p_legal_entity_id,0));
 if employee is not null then perform 1 from people.employees where tenant_id=p_tenant_id and legal_entity_id=p_legal_entity_id and employees.id=employee for update;end if;
 -- Entity serialization gives one lock order for ticket/order and meter/occurrence work.
 perform pg_advisory_xact_lock(hashtextextended('service:'||p_tenant_id||':'||p_legal_entity_id,0));
 if act in('equipment','coverage','policy','ticket','order','labor','plan','reading') and p_expected_version<>0 then raise exception using errcode='40001',message='SERVICE_VERSION_CONFLICT';end if;
 if act='equipment' then kind:='equipment';perform service.text(p_payload->'name',160);perform service.text(p_payload->'identity',160);
  if p_payload->>'kind'<>'customer' then raise exception using errcode='55000',message='SERVICE_EQUIPMENT_PROVIDER_UNAVAILABLE';end if;
  perform service.check_customer(p_tenant_id,(p_payload->>'customer_id')::uuid,null);
  insert into service.equipment(id,tenant_id,legal_entity_id,branch_id,code,name,identity,kind,customer_id,provider_id,created_by)
   values(id,p_tenant_id,p_legal_entity_id,p_branch_id,p_payload->>'code',p_payload->>'name',p_payload->>'identity',p_payload->>'kind',(p_payload->>'customer_id')::uuid,(p_payload->>'provider_id')::uuid,auth.uid());
 elsif act='coverage' then kind:='coverage';
  if not exists(select 1 from service.equipment where tenant_id=p_tenant_id and legal_entity_id=p_legal_entity_id and branch_id=p_branch_id and equipment.id=(p_payload->>'equipment_id')::uuid and status='active') then raise exception using errcode='42501',message='SERVICE_SCOPE_DENIED';end if;
  insert into service.coverage_versions(id,tenant_id,legal_entity_id,branch_id,equipment_id,kind,start_date,end_date_exclusive,name,evidence_reference,created_by)
  values(id,p_tenant_id,p_legal_entity_id,p_branch_id,(p_payload->>'equipment_id')::uuid,p_payload->>'kind',(p_payload->>'start_date')::date,(p_payload->>'end_date_exclusive')::date,
   service.text(p_payload->'name',160),service.text(p_payload->'evidence_reference',160),auth.uid());
 elsif act='policy' then kind:='policy';windows:=service.windows(p_tenant_id,p_legal_entity_id,(p_payload->>'calendar_version_id')::uuid,(p_payload->>'start_date')::date,(p_payload->>'end_date_exclusive')::date,p_payload->'offsets');
  if jsonb_typeof(p_payload->'independent_closure') is distinct from 'boolean' then raise exception using errcode='22023',message='SERVICE_POLICY_INVALID';end if;
  insert into service.sla_policies(id,tenant_id,legal_entity_id,branch_id,name,calendar_version_id,start_date,end_date_exclusive,response_seconds,resolution_seconds,windows,independent_closure,created_by)
  values(id,p_tenant_id,p_legal_entity_id,p_branch_id,service.text(p_payload->'name',160),(p_payload->>'calendar_version_id')::uuid,(p_payload->>'start_date')::date,(p_payload->>'end_date_exclusive')::date,
  service.integer(p_payload->'response_seconds',31622400,1),service.integer(p_payload->'resolution_seconds',31622400,1),windows,(p_payload->>'independent_closure')::boolean,auth.uid());
 elsif act='ticket' then kind:='ticket';perform service.ticket_create(p_tenant_id,p_legal_entity_id,p_branch_id,id,p_payload);
 elsif act in('pause','resume','evaluate','reprioritize','cancel_ticket') then kind:='ticket';
  select * into t from service.tickets where tenant_id=p_tenant_id and legal_entity_id=p_legal_entity_id and branch_id=p_branch_id and tickets.id=command_work.id for update;
  if t.id is null then raise exception using errcode='P0002',message='SERVICE_NOT_FOUND';end if;
  if t.version<>p_expected_version then raise exception using errcode='40001',message='SERVICE_VERSION_CONFLICT';end if;before_state:=service.snapshot(kind,id);
  if t.status in('closed','cancelled','resolved') then raise exception using errcode='55000',message='SERVICE_STATE_CONFLICT';end if;
  observed:=case when act='cancel_ticket' then date_trunc('second',clock_timestamp()) else service.utc(p_payload->'observed_utc') end;
  if observed<t.clock_start_utc or observed>clock_timestamp()+interval '5 minutes' then raise exception using errcode='22023',message='SERVICE_CLOCK_INVALID';end if;
  select * into policy from service.sla_policies where sla_policies.id=t.policy_id;
  t.response_breached:=t.response_breached or(t.response_at is null and t.status='open' and observed>t.response_due);
  t.resolution_breached:=t.resolution_breached or(t.resolution_at is null and t.status='open' and observed>t.resolution_due);
  if t.status='open' then t.consumed_seconds:=t.consumed_seconds+service.elapsed(policy.windows,t.clock_start_utc,observed);end if;
  if act='pause' then if t.status<>'open' then raise exception using errcode='55000',message='SERVICE_STATE_CONFLICT';end if;t.status:='paused';
  elsif act='resume' then if t.status<>'paused' then raise exception using errcode='55000',message='SERVICE_STATE_CONFLICT';end if;t.status:='open';
  elsif act='reprioritize' then
   select * into policy from service.sla_policies where tenant_id=p_tenant_id and legal_entity_id=p_legal_entity_id and branch_id=p_branch_id and sla_policies.id=(p_payload->>'policy_id')::uuid;
   if policy.id is null or p_payload->>'priority' not in('low','normal','high','urgent') then raise exception using errcode='22023',message='SERVICE_POLICY_INVALID';end if;t.policy_id:=policy.id;t.priority:=p_payload->>'priority';
  elsif act='cancel_ticket' then
   if exists(select 1 from service.work_orders where ticket_id=t.id and status<>'cancelled') then raise exception using errcode='55000',message='SERVICE_DEPENDENT_WORK';end if;t.status:='cancelled';end if;
  t.response_breached:=t.response_breached or(t.response_at is null and t.consumed_seconds>policy.response_seconds);
  t.resolution_breached:=t.resolution_breached or(t.resolution_at is null and t.consumed_seconds>policy.resolution_seconds);
  if t.status='open' then t.response_due:=case when t.response_at is null then service.due(policy.windows,observed,policy.response_seconds-t.consumed_seconds) else t.response_due end;
   t.resolution_due:=service.due(policy.windows,observed,policy.resolution_seconds-t.consumed_seconds);end if;
  update service.tickets set status=t.status,policy_id=t.policy_id,priority=t.priority,clock_start_utc=observed,consumed_seconds=t.consumed_seconds,response_due=t.response_due,resolution_due=t.resolution_due,
   response_breached=t.response_breached,resolution_breached=t.resolution_breached,version=tickets.version+1 where tickets.id=id;
 elsif act='order' then kind:='order';
  select * into t from service.tickets where tenant_id=p_tenant_id and legal_entity_id=p_legal_entity_id and branch_id=p_branch_id and tickets.id=(p_payload->>'ticket_id')::uuid for update;
  if t.id is null or t.status<>'open' then raise exception using errcode='55000',message='SERVICE_STATE_CONFLICT';end if;
  insert into service.work_orders(id,tenant_id,legal_entity_id,branch_id,ticket_id,created_by) values(id,p_tenant_id,p_legal_entity_id,p_branch_id,t.id,auth.uid());
 elsif act in('dispatch','accept','start','complete','close','cancel_order') then kind:='order';
  select ticket_id into newticket from service.work_orders where tenant_id=p_tenant_id and legal_entity_id=p_legal_entity_id and branch_id=p_branch_id and work_orders.id=command_work.id;
  select * into t from service.tickets where tickets.id=newticket for update;
  select * into w from service.work_orders where tenant_id=p_tenant_id and legal_entity_id=p_legal_entity_id and branch_id=p_branch_id and work_orders.id=command_work.id for update;
  if w.id is null then raise exception using errcode='P0002',message='SERVICE_NOT_FOUND';end if;
  if w.version<>p_expected_version then raise exception using errcode='40001',message='SERVICE_VERSION_CONFLICT';end if;before_state:=service.snapshot(kind,id);
  select * into policy from service.sla_policies where sla_policies.id=t.policy_id;
  if act='dispatch' then
   if w.status<>'planned' then raise exception using errcode='55000',message='SERVICE_STATE_CONFLICT';end if;
   calendar:=(p_payload->>'calendar_version_id')::uuid;start_utc:=service.utc(p_payload->'start_utc');end_utc:=service.utc(p_payload->'end_utc');
   select * into calendar_row from people.work_calendar_versions where tenant_id=p_tenant_id and legal_entity_id=p_legal_entity_id and work_calendar_versions.id=calendar;
   perform people.work_local_coverage(p_tenant_id,p_legal_entity_id,p_branch_id,employee,calendar,start_utc at time zone calendar_row.timezone,end_utc at time zone calendar_row.timezone);
   if t.status<>'open' or service.elapsed(service.windows(p_tenant_id,p_legal_entity_id,calendar,(start_utc at time zone calendar_row.timezone)::date,((end_utc-interval '1 microsecond') at time zone calendar_row.timezone)::date+1,'[]'),start_utc,end_utc)<>extract(epoch from end_utc-start_utc)::bigint
    or exists(select 1 from service.maintenance_occurrences where order_id=w.id and deferred_until>(start_utc at time zone calendar_row.timezone)::date) then raise exception using errcode='55000',message='SERVICE_STAFF_UNAVAILABLE';end if;
   if exists(select 1 from people.work_claim_segments s where s.tenant_id=p_tenant_id and s.legal_entity_id=p_legal_entity_id and s.employee_id=employee and s.active and tstzrange(s.start_utc,s.end_utc,'[)') && tstzrange(start_utc,end_utc,'[)')
    and exists(select 1 from people.work_claims c where c.id=s.claim_id and c.source_kind='leave')) then raise exception using errcode='55000',message='SERVICE_STAFF_UNAVAILABLE';end if;
   insert into service.dispatch_bookings(id,tenant_id,legal_entity_id,branch_id,order_id,employee_id,calendar_version_id,start_utc,end_utc,created_by)
    values((p_payload->>'booking_id')::uuid,p_tenant_id,p_legal_entity_id,p_branch_id,id,employee,calendar,start_utc,end_utc,auth.uid());w.status:='dispatched';w.employee_id:=employee;
  elsif act='accept' then
   if w.status<>'dispatched' then raise exception using errcode='55000',message='SERVICE_STATE_CONFLICT';end if;
   observed:=service.utc(p_payload->'observed_utc');if t.status<>'open' or observed<t.clock_start_utc or observed>clock_timestamp()+interval '5 minutes' then raise exception using errcode='22023',message='SERVICE_CLOCK_INVALID';end if;
   w.status:='accepted';w.accepted_by:=auth.uid();w.accepted_utc:=observed;
   update service.tickets set response_at=coalesce(response_at,observed),response_breached=response_breached or(response_at is null and observed>response_due and status='open'),version=tickets.version+1 where tickets.id=t.id;
  elsif act='start' then if w.status<>'accepted' or t.status<>'open' then raise exception using errcode='55000',message='SERVICE_STATE_CONFLICT';end if;
   observed:=service.utc(p_payload->'observed_utc');if observed<t.clock_start_utc or observed<w.accepted_utc or observed>clock_timestamp()+interval '5 minutes' then raise exception using errcode='22023',message='SERVICE_CLOCK_INVALID';end if;w.status:='working';w.work_started_utc:=observed;
  elsif act='complete' then
   if w.status not in('accepted','working') or exists(select 1 from service.labor where order_id=w.id and status='submitted') then raise exception using errcode='55000',message='SERVICE_PENDING_WORK';end if;
   observed:=service.utc(p_payload->'observed_utc');if t.status<>'open' or observed<t.clock_start_utc or observed<coalesce(w.work_started_utc,w.accepted_utc) or observed>clock_timestamp()+interval '5 minutes'
    or exists(select 1 from service.labor where order_id=w.id and status='approved' and end_utc>observed) then raise exception using errcode='22023',message='SERVICE_CLOCK_INVALID';end if;
   if jsonb_typeof(p_payload->'customer_confirmed') is distinct from 'boolean' then raise exception using errcode='22023',message='SERVICE_CONFIRMATION_INVALID';end if;
   w.customer_confirmed:=(p_payload->>'customer_confirmed')::boolean;w.exception_reason:=case when w.customer_confirmed then null else service.text(p_payload->'exception_reason',1000) end;
   w.resolution:=service.text(p_payload->'resolution',1000);w.completed_by:=auth.uid();w.status:='completed';w.completed_utc:=observed;
   update service.dispatch_bookings set active=false where order_id=w.id and active;
   if not exists(select 1 from service.work_orders where ticket_id=t.id and work_orders.id<>w.id and status not in('completed','closed','cancelled')) then
    update service.tickets set resolution_at=observed,resolution_breached=resolution_breached or(observed>resolution_due and status='open'),status='resolved',version=tickets.version+1 where tickets.id=t.id;end if;
  elsif act='close' then
   if w.status<>'completed' or policy.independent_closure and w.completed_by=auth.uid() or exists(select 1 from service.dispatch_bookings where order_id=w.id and active)
    or exists(select 1 from service.labor where order_id=w.id and(status='submitted' or status='approved' and billing_kind='billable' and billing_consumption_id is null)) then
    raise exception using errcode='55000',message='SERVICE_INDEPENDENT_CLOSURE_REQUIRED';end if;w.status:='closed';w.closed_by:=auth.uid();w.closed_at:=date_trunc('second',clock_timestamp());
   if not exists(select 1 from service.work_orders where ticket_id=t.id and work_orders.id<>w.id and status not in('closed','cancelled')) then update service.tickets set status='closed',version=tickets.version+1 where tickets.id=t.id;end if;
  elsif act='cancel_order' then
   if w.status in('completed','closed','cancelled') or exists(select 1 from service.labor where order_id=w.id and status<>'cancelled') then raise exception using errcode='55000',message='SERVICE_DEPENDENT_WORK';end if;
   w.status:='cancelled';update service.dispatch_bookings set active=false where order_id=w.id and active;end if;
  update service.work_orders set status=w.status,employee_id=w.employee_id,accepted_by=w.accepted_by,completed_by=w.completed_by,closed_by=w.closed_by,resolution=w.resolution,
   customer_confirmed=w.customer_confirmed,exception_reason=w.exception_reason,accepted_utc=w.accepted_utc,work_started_utc=w.work_started_utc,completed_utc=w.completed_utc,closed_at=w.closed_at,version=work_orders.version+1 where work_orders.id=id;
 elsif act='labor' then kind:='labor';
  select * into w from service.work_orders where tenant_id=p_tenant_id and legal_entity_id=p_legal_entity_id and branch_id=p_branch_id and work_orders.id=(p_payload->>'order_id')::uuid for update;
  calendar:=(p_payload->>'calendar_version_id')::uuid;start_utc:=service.utc(p_payload->'start_utc');end_utc:=service.utc(p_payload->'end_utc');
  if w.id is null or w.status not in('accepted','working') or w.employee_id is distinct from employee then raise exception using errcode='55000',message='SERVICE_STATE_CONFLICT';end if;
  if not exists(select 1 from service.dispatch_bookings s where s.order_id=w.id and s.employee_id=employee and s.active and tstzrange(s.start_utc,s.end_utc,'[)') @> tstzrange(command_work.start_utc,command_work.end_utc,'[)')) then
   raise exception using errcode='55000',message='SERVICE_LABOR_BOOKING_REQUIRED';end if;
  select * into calendar_row from people.work_calendar_versions where tenant_id=p_tenant_id and legal_entity_id=p_legal_entity_id and work_calendar_versions.id=calendar;
  perform people.work_local_coverage(p_tenant_id,p_legal_entity_id,p_branch_id,employee,calendar,start_utc at time zone calendar_row.timezone,end_utc at time zone calendar_row.timezone);
  seconds:=extract(epoch from end_utc-start_utc)::bigint-people.work_break_seconds(start_utc,end_utc,p_payload->'breaks');cost:=service.amount(p_payload->'hourly_cost');precision:=service.integer(p_payload->'precision',6)::integer;
  select currency_code into currency from core.legal_entities where tenant_id=p_tenant_id and legal_entities.id=p_legal_entity_id;
  if p_payload->>'currency_code' is distinct from currency then raise exception using errcode='22023',message='SERVICE_CURRENCY_INVALID';end if;
  billkind:=coalesce(p_payload->>'billing_kind','nonbillable');billrate:=case when p_payload ? 'hourly_billing' then service.amount(p_payload->'hourly_billing') else 0 end;
  billref:=case when p_payload ? 'billing_reference' then service.text(p_payload->'billing_reference',160) else 'Synthetic nonbillable work' end;
  if billkind not in('billable','nonbillable') or billkind='nonbillable' and billrate<>0 then raise exception using errcode='22023',message='SERVICE_BILLING_TERMS_INVALID';end if;
  amount:=service.round_ratio(cost*1000000*seconds,3600,precision);billamount:=service.round_ratio(billrate*1000000*seconds,3600,precision);
  digest:=encode(extensions.digest(p_payload::text||':'||seconds::text||':'||amount::text||':'||billkind||':'||billamount::text||':'||billref,'sha256'),'hex');
  insert into service.labor(id,tenant_id,legal_entity_id,branch_id,order_id,employee_id,calendar_version_id,start_utc,end_utc,breaks,seconds,claim_id,hourly_cost,amount,currency_code,precision,digest,submitted_by,reason,billing_kind,hourly_billing,billable_amount,billing_reference)
  values(id,p_tenant_id,p_legal_entity_id,p_branch_id,w.id,employee,calendar,start_utc,end_utc,p_payload->'breaks',seconds,(p_payload->>'claim_id')::uuid,cost,amount,currency,precision,digest,auth.uid(),reason,billkind,billrate,billamount,billref);
 elsif act in('approve_labor','cancel_labor') then kind:='labor';
  select l.* into labor from service.labor l where l.tenant_id=p_tenant_id and l.legal_entity_id=p_legal_entity_id and l.branch_id=p_branch_id and l.id=command_work.id for update;
  if labor.id is null then raise exception using errcode='P0002',message='SERVICE_NOT_FOUND';end if;if labor.version<>p_expected_version then raise exception using errcode='40001',message='SERVICE_VERSION_CONFLICT';end if;before_state:=service.snapshot(kind,id);
  if act='approve_labor' then
 if labor.status<>'submitted' or labor.submitted_by=auth.uid() or not exists(select 1 from service.work_orders where work_orders.id=labor.order_id and status in('accepted','working')) then raise exception using errcode='55000',message='SERVICE_INDEPENDENT_APPROVAL_REQUIRED';end if;
   select * into calendar_row from people.work_calendar_versions where work_calendar_versions.id=labor.calendar_version_id;
   perform people.work_local_coverage(p_tenant_id,p_legal_entity_id,p_branch_id,employee,labor.calendar_version_id,labor.start_utc at time zone calendar_row.timezone,labor.end_utc at time zone calendar_row.timezone);
   claim:=labor.claim_id;
   if claim is null then owns:=true;claim:=people.make_work_claim(p_tenant_id,p_legal_entity_id,p_branch_id,employee,'service',labor.id,labor.start_utc,labor.end_utc,labor.breaks,labor.calendar_version_id,auth.uid());
    for segment in select s.start_utc,s.end_utc from people.work_claim_segments s where s.claim_id=claim and s.active order by s.start_utc loop
     allocation:=people.allocate_work(p_tenant_id,p_legal_entity_id,p_branch_id,employee,claim,'service',gen_random_uuid(),segment.start_utc,segment.end_utc,auth.uid());allocations:=array_append(allocations,allocation);end loop;
   else
    if not exists(select 1 from people.work_claims x where x.id=claim and x.tenant_id=p_tenant_id and x.legal_entity_id=p_legal_entity_id and x.branch_id=p_branch_id and x.employee_id=employee and x.source_kind='attendance' and x.active and x.calendar_version_id=labor.calendar_version_id
     and exists(select 1 from people.attendance_entries a where a.active_claim_id=x.id and a.status='approved')) then raise exception using errcode='55000',message='SERVICE_ATTENDANCE_SOURCE_INVALID';end if;
    segment_cursor:=labor.start_utc;
    for segment in select (value->>'start_utc')::timestamptz start_utc,(value->>'end_utc')::timestamptz end_utc from jsonb_array_elements(labor.breaks||jsonb_build_array(jsonb_build_object('start_utc',labor.end_utc,'end_utc',labor.end_utc))) loop
     if segment.start_utc>segment_cursor then
      allocation:=people.allocate_work(p_tenant_id,p_legal_entity_id,p_branch_id,employee,claim,'service',gen_random_uuid(),segment_cursor,segment.start_utc,auth.uid());allocations:=array_append(allocations,allocation);
     end if;segment_cursor:=segment.end_utc;
    end loop;
   end if;
   foreach allocation in array allocations loop
    insert into service.labor_allocations values(allocation,p_tenant_id,p_legal_entity_id,p_branch_id,labor.id,labor.id,claim,owns);
   end loop;
   perform people.consume_organization(p_tenant_id,p_legal_entity_id,p_branch_id,employee,'service_time',labor.id,(labor.start_utc at time zone calendar_row.timezone)::date,((labor.end_utc-interval '1 microsecond') at time zone calendar_row.timezone)::date+1);
   update service.labor set claim_id=claim,allocation_ids=allocations,owns_claim=owns,status='approved',approved_by=auth.uid(),version=service.labor.version+1 where service.labor.id=id;
  else
   if labor.status='cancelled' or labor.billing_consumption_id is not null then raise exception using errcode='55000',message='SERVICE_CONSUMED_IMPACT_REQUIRED';end if;
   perform service.assert_billing_mutable(p_tenant_id,p_legal_entity_id,labor.id);
   if exists(select 1 from people.work_input_seals where claim_id=labor.claim_id) then raise exception using errcode='55000',message='PAYROLL_INPUT_SEALED';end if;
   foreach allocation in array labor.allocation_ids loop perform people.revoke_work_allocation(p_tenant_id,p_legal_entity_id,employee,allocation);end loop;
   if labor.owns_claim then perform people.revoke_work_claim(p_tenant_id,p_legal_entity_id,employee,labor.claim_id);end if;
   update service.labor set status='cancelled',version=service.labor.version+1 where service.labor.id=id;
   if to_regprocedure('projects.service_payroll_cost_impact(uuid,uuid,uuid,uuid,uuid)') is not null then
    execute 'select projects.service_payroll_cost_impact($1,$2,$3,$4,$5)' using p_tenant_id,p_legal_entity_id,p_branch_id,labor.id,coalesce(labor.current_revision_id,labor.id);
   end if;
  end if;
 elsif act='plan' then kind:='plan';
  select * into eq from service.equipment where tenant_id=p_tenant_id and legal_entity_id=p_legal_entity_id and branch_id=p_branch_id and equipment.id=(p_payload->>'equipment_id')::uuid and status='active';
  select * into policy from service.sla_policies where tenant_id=p_tenant_id and legal_entity_id=p_legal_entity_id and branch_id=p_branch_id and sla_policies.id=(p_payload->>'policy_id')::uuid;
  if eq.id is null or policy.id is null then raise exception using errcode='42501',message='SERVICE_SCOPE_DENIED';end if;
  insert into service.maintenance_plans(id,tenant_id,legal_entity_id,branch_id,equipment_id,policy_id,name,basis,interval_units,next_date,next_meter,created_by)
  values(id,p_tenant_id,p_legal_entity_id,p_branch_id,eq.id,policy.id,service.text(p_payload->'name',160),p_payload->>'basis',service.integer(p_payload->'interval_units',9007199254740991,1),
   (p_payload->>'next_date')::date,case when p_payload->'next_meter'<> 'null'::jsonb then service.integer(p_payload->'next_meter',9007199254740991,1) end,auth.uid());
 elsif act='reading' then kind:='reading';
  select * into eq from service.equipment where tenant_id=p_tenant_id and legal_entity_id=p_legal_entity_id and branch_id=p_branch_id and equipment.id=(p_payload->>'equipment_id')::uuid and status='active' for update;
  if eq.id is null then raise exception using errcode='42501',message='SERVICE_SCOPE_DENIED';end if;
  raw:=service.integer(p_payload->'raw_value',9007199254740991);observed:=service.utc(p_payload->'observed_utc');
  select * into meter from service.meter_readings where equipment_id=eq.id order by observed_utc desc,id desc limit 1;
  if observed>clock_timestamp()+interval '5 minutes' or meter.id is not null and observed<=meter.observed_utc then raise exception using errcode='22023',message='SERVICE_METER_CLOCK_INVALID';end if;
  if meter.id is null then if p_payload->>'kind'<>'initial' then raise exception using errcode='22023',message='SERVICE_METER_INITIAL_REQUIRED';end if;logical:=raw;
  elsif p_payload->>'kind'='reading' then if raw<meter.raw_value then raise exception using errcode='22023',message='SERVICE_METER_DECREASE';end if;logical:=meter.logical_value+raw-meter.raw_value;
  elsif p_payload->>'kind'='reset' then logical:=meter.logical_value+raw;
  elsif p_payload->>'kind'='rollover' then rollmax:=service.integer(p_payload->'rollover_max',9007199254740991,1);
   if raw>=meter.raw_value or rollmax<meter.raw_value or raw>rollmax then raise exception using errcode='22023',message='SERVICE_METER_ROLLOVER_INVALID';end if;logical:=meter.logical_value+(rollmax-meter.raw_value)+1+raw;
  else raise exception using errcode='22023',message='SERVICE_METER_KIND_INVALID';end if;
  insert into service.meter_readings(id,tenant_id,legal_entity_id,branch_id,equipment_id,kind,raw_value,logical_value,previous_id,rollover_max,observed_utc,reason,recorded_by)
  values(id,p_tenant_id,p_legal_entity_id,p_branch_id,eq.id,p_payload->>'kind',raw,logical,meter.id,rollmax,observed,reason,auth.uid());
 elsif act='generate' then kind:='plan';
  select * into plan from service.maintenance_plans where tenant_id=p_tenant_id and legal_entity_id=p_legal_entity_id and branch_id=p_branch_id and maintenance_plans.id=command_work.id for update;
  if plan.id is null then raise exception using errcode='P0002',message='SERVICE_NOT_FOUND';end if;if plan.version<>p_expected_version then raise exception using errcode='40001',message='SERVICE_VERSION_CONFLICT';end if;before_state:=service.snapshot(kind,id);
  observed:=service.utc(p_payload->'observed_utc');select * into eq from service.equipment where equipment.id=plan.equipment_id and status='active';
  if eq.id is null or observed>clock_timestamp()+interval '5 minutes' then raise exception using errcode='55000',message='SERVICE_MAINTENANCE_NOT_DUE';end if;
  if plan.basis='calendar' then
   if (observed at time zone(select timezone from core.legal_entities where legal_entities.id=p_legal_entity_id))::date<plan.next_date then raise exception using errcode='55000',message='SERVICE_MAINTENANCE_NOT_DUE';end if;
   occurrence_key:='date:'||plan.next_date::text;
  else select * into meter from service.meter_readings where equipment_id=eq.id and observed_utc<=observed order by observed_utc desc,id desc limit 1;
   if meter.id is null or meter.logical_value<plan.next_meter then raise exception using errcode='55000',message='SERVICE_MAINTENANCE_NOT_DUE';end if;occurrence_key:='meter:'||plan.next_meter::text;end if;
  newticket:=(p_payload->>'ticket_id')::uuid;neworder:=(p_payload->>'order_id')::uuid;occurrence:=(p_payload->>'occurrence_id')::uuid;
  perform service.ticket_create(p_tenant_id,p_legal_entity_id,p_branch_id,newticket,jsonb_build_object('code','PM-'||upper(substr(occurrence::text,1,8)),
    'name',plan.name,'classification','preventive-maintenance','customer_id',eq.customer_id,'equipment_id',eq.id,'policy_id',plan.policy_id,'priority','normal','observed_utc',p_payload->'observed_utc'));
  insert into service.work_orders(id,tenant_id,legal_entity_id,branch_id,ticket_id,created_by) values(neworder,p_tenant_id,p_legal_entity_id,p_branch_id,newticket,auth.uid());
  insert into service.maintenance_occurrences(id,tenant_id,legal_entity_id,branch_id,plan_id,plan_version,occurrence_key,original_due_date,original_due_meter,ticket_id,order_id,reading_id,reason,created_by)
   values(occurrence,p_tenant_id,p_legal_entity_id,p_branch_id,id,plan.version,occurrence_key,plan.next_date,plan.next_meter,newticket,neworder,meter.id,reason,auth.uid());
  update service.maintenance_plans set next_date=case when basis='calendar' then next_date+interval_units::integer else null end,next_meter=case when basis='meter' then next_meter+interval_units else null end,version=maintenance_plans.version+1 where maintenance_plans.id=id;
 elsif act='defer' then kind:='occurrence';
  before_state:=service.snapshot(kind,id);if before_state is null or before_state->>'tenant_id'<>p_tenant_id::text or before_state->>'legal_entity_id'<>p_legal_entity_id::text or before_state->>'branch_id'<>p_branch_id::text then raise exception using errcode='P0002',message='SERVICE_NOT_FOUND';end if;
  if p_expected_version<>(before_state->>'version')::bigint then raise exception using errcode='40001',message='SERVICE_VERSION_CONFLICT';end if;
  if (p_payload->>'deferred_until') is null or (p_payload->>'deferred_until')::date<=coalesce((before_state->>'deferred_until')::date,(before_state->>'original_due_date')::date,'0001-01-01'::date) or exists(select 1 from service.work_orders where work_orders.id=(before_state->>'order_id')::uuid and status<>'planned') then raise exception using errcode='55000',message='SERVICE_DEFERRAL_INVALID';end if;
  update service.maintenance_occurrences set deferred_until=(p_payload->>'deferred_until')::date,version=maintenance_occurrences.version+1 where maintenance_occurrences.id=id;
 end if;
 after_state:=service.snapshot(kind,id);version:=(after_state->>'version')::bigint;
 if act in('accept','complete','close') and (select x.version from service.tickets x where x.id=t.id)>t.version then
  insert into service.events(tenant_id,legal_entity_id,branch_id,aggregate_id,kind,version,action,reason,facts,actor_id)
   select p_tenant_id,p_legal_entity_id,p_branch_id,t.id,'ticket',x.version,act,reason,service.snapshot('ticket',t.id),auth.uid() from service.tickets x where x.id=t.id;
 end if;
 if act='generate' then
  insert into service.events(tenant_id,legal_entity_id,branch_id,aggregate_id,kind,version,action,reason,facts,actor_id)
   select p_tenant_id,p_legal_entity_id,p_branch_id,x.id,x.kind,1,act,reason,service.snapshot(x.kind,x.id),auth.uid()
   from(values(newticket,'ticket'),(neworder,'order'),(occurrence,'occurrence')) x(id,kind);
 end if;
 event_state:=after_state;
 insert into service.events(tenant_id,legal_entity_id,branch_id,aggregate_id,kind,version,action,reason,facts,actor_id)
  values(p_tenant_id,p_legal_entity_id,p_branch_id,id,kind,version,act,reason,event_state,auth.uid());
 -- Telemetry is deliberately minimal; rich facts are service-scoped read projections.
 return core.wave3_finish_command(p_tenant_id,'service.'||act,p_command_id,'service.'||kind,id,p_idempotency_key,hash,
  case when before_state is not null then jsonb_build_object('id',id,'version',before_state->'version') end,
  jsonb_build_object('id',id,'tenant_id',p_tenant_id,'legal_entity_id',p_legal_entity_id,'branch_id',p_branch_id,'kind',kind,'version',version,'status',after_state->>'status'),p_legal_entity_id,p_branch_id);
end $$;
-- Owner-only linked payroll impacts preserve original geometry, allocation identity,
-- invoices and credits. One labor revision owns every payable segment.
create function service.assert_billing_mutable(t uuid,e uuid,p_id uuid) returns void language plpgsql security definer set search_path='' as $$
declare blocked boolean;rid uuid;begin
 select coalesce(current_revision_id,id) into rid from service.labor where tenant_id=t and legal_entity_id=e and id=p_id;
 if to_regclass('projects.billable_units') is not null then
  if exists(select 1 from pg_attribute where attrelid=to_regclass('projects.billable_units') and attname='provider_source_id' and not attisdropped) then
   execute 'select exists(select 1 from projects.billable_units where tenant_id=$1 and legal_entity_id=$2 and source_kind=''service'' and provider_source_id=$3 and source_id=$4 and status in(''reserved'',''billed''))' into blocked using t,e,p_id,rid;
  else
   execute 'select exists(select 1 from projects.billable_units where tenant_id=$1 and legal_entity_id=$2 and source_kind=''service'' and source_id=$3 and status in(''reserved'',''billed''))' into blocked using t,e,rid;
  end if;
  if blocked then raise exception using errcode='55000',message='SERVICE_BILLED_IMPACT_REQUIRED';end if;
 end if;
end $$;
create function service.payroll_billing_impact(t uuid,e uuid,b uuid,p_id uuid,rid uuid,proposal jsonb,p_mode text)
returns jsonb language plpgsql security definer set search_path='' as $$
declare result jsonb;begin
 if to_regprocedure('projects.service_payroll_billing_impact(uuid,uuid,uuid,uuid,uuid,jsonb,text)') is not null then
  execute 'select projects.service_payroll_billing_impact($1,$2,$3,$4,$5,$6,$7)' into result using t,e,b,p_id,rid,proposal,p_mode;
  return result;
 end if;
 perform service.assert_billing_mutable(t,e,p_id);
 if exists(select 1 from service.labor where tenant_id=t and legal_entity_id=e and branch_id=b and id=p_id and billing_consumption_id is not null) then
  raise exception using errcode='55000',message='SERVICE_BILLED_IMPACT_REQUIRED';end if;
 return jsonb_build_object('status','unimported','source_id',rid);
end $$;
create function service.payroll_impact_guard(t uuid,e uuid,b uuid,employee uuid,claim uuid,cid uuid,direct_claim boolean)
returns void language plpgsql security definer set search_path='' as $$begin
 if not exists(select 1 from people_payroll.corrections q join people_payroll.correction_sources x on x.correction_id=q.id
  where q.id=cid and q.tenant_id=t and q.legal_entity_id=e and q.branch_id=b and q.employee_id=employee
   and q.status in('approved','posted') and x.source_kind=case when direct_claim then 'service' else 'attendance' end
   and x.impact is not null and (people_payroll.correction_source_state(x.seal_id)->>'claim_id')::uuid=claim) then
  raise exception using errcode='42501',message='PAYROLL_APPROVED_LINKED_IMPACT_REQUIRED';end if;
end $$;
create function service.payroll_revision_impact(t uuid,e uuid,b uuid,employee uuid,entry uuid,claim uuid,
 revision uuid,proposal jsonb,p_mode text,direct_claim boolean) returns jsonb
language plpgsql security definer set search_path='' as $$
declare l service.labor%rowtype;c people.work_calendar_versions%rowtype;w service.work_orders%rowtype;ticket service.tickets%rowtype;
 before_body jsonb;after_body jsonb;target jsonb;change jsonb;result jsonb;approved_result jsonb;billing jsonb;billing_proposal jsonb;current_credit jsonb;
 previous service.payroll_labor_impacts%rowtype;original service.payroll_labor_impacts%rowtype;
 attendance jsonb:=proposal->'attendance_after';br jsonb;breaks jsonb;cid uuid:=(proposal->>'correction_id')::uuid;
 actual_mode text;rid uuid;oldrid uuid;new_claim uuid;allocation uuid;allocs uuid[]:='{}';
 s timestamptz;z timestamptz;sl timestamp;el timestamp;cursor_utc timestamptz;bs timestamptz;be timestamptz;seconds bigint;
 remove_source boolean:=false;order_reopened boolean:=false;
begin
 if p_mode not in('read','validate','release','apply','reverse') or revision is null or proposal is null or jsonb_typeof(proposal)<>'object' then
  raise exception using errcode='22023',message='SERVICE_PAYROLL_IMPACT_INVALID';end if;
 actual_mode:=case when p_mode='reverse' or proposal->>'operational_mode'='reverse' then 'reverse' else 'apply' end;
 perform service.require_access(t,e,b,case when p_mode='read' then 'service.view' else 'service.approve' end);
 perform service.require_access(t,e,b,'service.cost.view');
 perform pg_advisory_xact_lock(hashtextextended('people.payroll:'||t||':'||e,0));
 perform pg_advisory_xact_lock(hashtextextended('projects:'||t||':'||e,0));
 perform pg_advisory_xact_lock(hashtextextended('service:'||t||':'||e,0));
 perform 1 from people.employees where tenant_id=t and legal_entity_id=e and id=employee for update;
 select x.* into l from service.labor x where x.tenant_id=t and x.legal_entity_id=e and x.branch_id=b and x.employee_id=employee and x.id=entry;
 if l.id is null or l.owns_claim is distinct from direct_claim then raise exception using errcode='40001',message='PAYROLL_CORRECTION_SOURCE_CHANGED';end if;
 select x.* into ticket from service.tickets x join service.work_orders q on q.ticket_id=x.id where q.id=l.order_id for update of x;
 select * into w from service.work_orders where id=l.order_id for update;
 select * into l from service.labor where id=l.id for update;
 oldrid:=coalesce(l.current_revision_id,l.id);
 select * into previous from service.payroll_labor_impacts x where x.tenant_id=t and x.legal_entity_id=e and x.branch_id=b and x.labor_id=l.id and x.correction_id=cid and x.mode=actual_mode;
 if previous.id is not null and p_mode in('apply','reverse') then
  if l.current_revision_id is distinct from previous.replacement_revision_id or l.version is distinct from(previous.body->>'source_version')::bigint
   or l.claim_id is distinct from(previous.body->>'claim_id')::uuid then raise exception using errcode='40001',message='PAYROLL_CORRECTION_SOURCE_CHANGED';end if;
  return previous.body;
 end if;
 if l.status<>'approved' and not(actual_mode='reverse' and l.status='cancelled') or l.claim_id is distinct from claim then
  raise exception using errcode='40001',message='PAYROLL_CORRECTION_SOURCE_CHANGED';end if;
 select * into c from people.work_calendar_versions where tenant_id=t and legal_entity_id=e and id=l.calendar_version_id;
 before_body:=service.snapshot('labor',l.id);
 before_body:=before_body||jsonb_build_object('start_local',to_char((before_body->>'start_utc')::timestamptz at time zone c.timezone,'YYYY-MM-DD"T"HH24:MI:SS'),
  'end_local',to_char((before_body->>'end_utc')::timestamptz at time zone c.timezone,'YYYY-MM-DD"T"HH24:MI:SS'),
  'start_offset_seconds',extract(epoch from ((before_body->>'start_utc')::timestamptz at time zone c.timezone)-((before_body->>'start_utc')::timestamptz at time zone 'UTC'))::integer,
  'end_offset_seconds',extract(epoch from ((before_body->>'end_utc')::timestamptz at time zone c.timezone)-((before_body->>'end_utc')::timestamptz at time zone 'UTC'))::integer);
 if p_mode='read' then
  if not exists(select 1 from people.work_claims x where x.id=claim and x.tenant_id=t and x.legal_entity_id=e and x.branch_id=b and x.employee_id=employee and x.active
   and x.source_kind=case when direct_claim then 'service' else 'attendance' end and(not direct_claim or x.source_id=oldrid)) then
   raise exception using errcode='40001',message='PAYROLL_CORRECTION_SOURCE_CHANGED';end if;
  return jsonb_build_object('before',before_body,'source_id',oldrid,'source_version',l.version,'paid_seconds',(before_body->>'seconds')::bigint,
   'claim_id',claim,'entry_id',l.id,'order_id',w.id,'order_name',ticket.code||' / '||ticket.name,
   'ticket_id',ticket.id,'ticket_code',ticket.code,'ticket_name',ticket.name);
 end if;
 if actual_mode='reverse' then
  select * into original from service.payroll_labor_impacts x where x.tenant_id=t and x.legal_entity_id=e and x.branch_id=b and x.labor_id=l.id and x.correction_id=cid and x.mode='apply';
  if original.id is null or original.replacement_revision_id is distinct from l.current_revision_id
   or (original.body->>'source_version')::bigint is distinct from l.version or (original.body->>'claim_id')::uuid is distinct from claim then
   raise exception using errcode='40001',message='PAYROLL_CORRECTION_SOURCE_CHANGED';end if;
  if direct_claim then
   if proposal->'before' is distinct from original.approved_body->'before' or proposal->'after' is distinct from original.approved_body->'after' then
    raise exception using errcode='40001',message='PAYROLL_CORRECTION_SOURCE_CHANGED';end if;
   target:=proposal->'before';
  else
   if ((proposal->'allocation_impact')-'allocation_id') is distinct from original.approved_body then
    raise exception using errcode='40001',message='PAYROLL_CORRECTION_SOURCE_CHANGED';end if;
   target:=proposal->'allocation_impact'->'before';
  end if;
  if direct_claim then
   current_credit:=jsonb_build_object('source_revision_id',proposal->'current_source_revision_id','expected_source_version',proposal->'current_source_version','billing_credit_line_ids',coalesce(proposal->'current_billing_credit_line_ids','[]'));
  else
   if jsonb_typeof(coalesce(proposal->'current_allocation_credits','[]')) is distinct from 'array' or jsonb_array_length(coalesce(proposal->'current_allocation_credits','[]'))>50
    or(select count(*) from jsonb_array_elements(coalesce(proposal->'current_allocation_credits','[]')) x where(x->>'entry_id')::uuid=l.id)>1 then
    raise exception using errcode='22023',message='SERVICE_CURRENT_CREDIT_INVALID';end if;
   select value into current_credit from jsonb_array_elements(coalesce(proposal->'current_allocation_credits','[]')) where(value->>'entry_id')::uuid=l.id;
  end if;
  if current_credit is not null and(current_credit->>'source_revision_id' is not null or jsonb_array_length(coalesce(current_credit->'billing_credit_line_ids','[]'))>0)
   and((current_credit->>'source_revision_id')::uuid is distinct from oldrid or(current_credit->>'expected_source_version')::bigint is distinct from l.version) then
   raise exception using errcode='40001',message='PAYROLL_CORRECTION_SOURCE_CHANGED';end if;
 else
  if direct_claim then
   if l.version is distinct from(proposal->>'expected_source_version')::bigint or proposal->>'mode' is distinct from 'geometry'
    or not exists(select 1 from people.work_claims x where x.id=claim and x.tenant_id=t and x.legal_entity_id=e and x.branch_id=b and x.employee_id=employee
     and x.active and x.source_kind='service' and x.source_id=oldrid) then raise exception using errcode='40001',message='PAYROLL_CORRECTION_SOURCE_CHANGED';end if;
   target:=proposal;
  else
   if jsonb_typeof(coalesce(proposal->'allocation_changes','[]')) is distinct from 'array' or jsonb_array_length(coalesce(proposal->'allocation_changes','[]'))>50 then
    raise exception using errcode='22023',message='SERVICE_ALLOCATION_CHANGE_INVALID';end if;
   if(select count(*) from jsonb_array_elements(coalesce(proposal->'allocation_changes','[]')) x where(x->>'entry_id')::uuid=l.id)>1 then
    raise exception using errcode='22023',message='SERVICE_ALLOCATION_CHANGE_INVALID';end if;
   select value into change from jsonb_array_elements(coalesce(proposal->'allocation_changes','[]')) where(value->>'entry_id')::uuid=l.id;
   if change is not null and(change->>'mode' not in('retain','geometry','remove') or exists(select 1 from jsonb_object_keys(change) k
    where k<>all(array['entry_id','mode','start_local','end_local','start_offset_seconds','end_offset_seconds','breaks','billing_credit_line_ids']))) then
    raise exception using errcode='22023',message='SERVICE_ALLOCATION_CHANGE_INVALID';end if;
   target:=case when change->>'mode'='geometry' then change else before_body end;
   remove_source:=change->>'mode'='remove';
   remove_source:=coalesce(remove_source,false);
  end if;
 end if;
 if not direct_claim then revision:=md5(revision::text||':'||l.id::text||':service-allocation')::uuid;end if;
 rid:=revision;
 sl:=(target->>'start_local')::timestamp;el:=(target->>'end_local')::timestamp;
 if sl is null or el is null or extract(second from sl)%1<>0 or extract(second from el)%1<>0 then raise exception using errcode='22023',message='WORK_LOCAL_BOUNDARY_INVALID';end if;
 s:=people.resolve_local_instant(c.timezone,sl,(target->>'start_offset_seconds')::integer);
 z:=people.resolve_local_instant(c.timezone,el,(target->>'end_offset_seconds')::integer);
 perform people.work_local_coverage(t,e,b,employee,c.id,sl,el);
 breaks:=coalesce(target->'breaks','[]');seconds:=extract(epoch from z-s)::bigint-people.work_break_seconds(s,z,breaks);
 if seconds not between 1 and 129600 then raise exception using errcode='22023',message='WORK_DURATION_INVALID';end if;
 if not exists(select 1 from service.dispatch_bookings x where x.order_id=l.order_id and x.employee_id=employee and x.calendar_version_id=c.id and tstzrange(x.start_utc,x.end_utc,'[)') @> tstzrange(s,z,'[)')) then
  raise exception using errcode='55000',message='SERVICE_LABOR_BOOKING_REQUIRED';end if;
 if w.status in('completed','closed') and z>w.completed_utc then raise exception using errcode='55000',message='SERVICE_COMPLETION_IMPACT_REQUIRED';end if;
 if not direct_claim and not remove_source then
  if attendance is null or(attendance->>'calendar_version_id')::uuid is distinct from c.id then raise exception using errcode='55000',message='SERVICE_ATTENDANCE_SOURCE_INVALID';end if;
  cursor_utc:=s;
  for br in select value from jsonb_array_elements(breaks||jsonb_build_array(jsonb_build_object('start_utc',z,'end_utc',z))) loop
   bs:=(br->>'start_utc')::timestamptz;be:=(br->>'end_utc')::timestamptz;
   if bs>cursor_utc and(cursor_utc<(attendance->>'start_utc')::timestamptz or bs>(attendance->>'end_utc')::timestamptz
    or exists(select 1 from jsonb_array_elements(attendance->'breaks') x where tstzrange((x->>'start_utc')::timestamptz,(x->>'end_utc')::timestamptz,'[)') && tstzrange(cursor_utc,bs,'[)'))) then
    raise exception using errcode='55000',message='SERVICE_ALLOCATION_GEOMETRY_IMPACT_REQUIRED';end if;
   cursor_utc:=be;
  end loop;
 end if;
 billing_proposal:=(proposal-'operational_mode')||jsonb_build_object('current_source_revision_id',oldrid,
  'billing_credit_line_ids',case when actual_mode='reverse' then coalesce(current_credit->'billing_credit_line_ids','[]') else coalesce(change->'billing_credit_line_ids',proposal->'billing_credit_line_ids','[]') end);
 billing:=service.payroll_billing_impact(t,e,b,l.id,oldrid,billing_proposal,'validate');
 after_body:=before_body||jsonb_build_object('start_local',to_char(sl,'YYYY-MM-DD"T"HH24:MI:SS'),'end_local',to_char(el,'YYYY-MM-DD"T"HH24:MI:SS'),
  'start_offset_seconds',(target->>'start_offset_seconds')::integer,'end_offset_seconds',(target->>'end_offset_seconds')::integer,
  'start_utc',to_char(s at time zone 'UTC','YYYY-MM-DD"T"HH24:MI:SS"Z"'),'end_utc',to_char(z at time zone 'UTC','YYYY-MM-DD"T"HH24:MI:SS"Z"'),
  'breaks',breaks,'seconds',case when remove_source then 0 else seconds end,'amount',case when remove_source then 0 else service.round_ratio(l.hourly_cost*1000000*seconds,3600,l.precision) end::numeric(20,6)::text,
  'billable_amount',case when remove_source then 0 else service.round_ratio(l.hourly_billing*1000000*seconds,3600,l.precision) end::numeric(20,6)::text,
  'billing_consumption_id',null,'status',case when remove_source then 'cancelled' else 'approved' end);
 after_body:=after_body||jsonb_build_object('digest',encode(extensions.digest((after_body-array['digest','current_revision_id','version','claim_id','allocation_ids','billing_consumption_id'])::text||':'||cid||':'||rid,'sha256'),'hex'));
 result:=jsonb_build_object('before',before_body,'after',after_body,'billing',billing,'source_id',rid,'source_version',l.version+1,
  'paid_seconds',case when remove_source then 0 else seconds end,'claim_id',claim,'entry_id',l.id,'order_id',w.id,
  'order_name',ticket.code||' / '||ticket.name,'ticket_id',ticket.id,'ticket_code',ticket.code,'ticket_name',ticket.name);
 if p_mode='validate' then return result;end if;
 perform service.payroll_impact_guard(t,e,b,employee,claim,cid,direct_claim);
 if actual_mode<>'reverse' then
  if direct_claim and(proposal->'before' is distinct from before_body or proposal->'after' is distinct from after_body)
   or not direct_claim and((proposal->'allocation_impact')-'allocation_id') is distinct from result then
   raise exception using errcode='40001',message='PAYROLL_CORRECTION_SOURCE_CHANGED';end if;
 end if;
 if p_mode='release' then
  -- Release all segments once; repeated callbacks see identical immutable IDs.
  update people.work_allocations set active=false,revoked_at=clock_timestamp() where id=any(l.allocation_ids) and active;
  return result;
 end if;
 approved_result:=result;
 if direct_claim then
  update people.work_allocations set active=false,revoked_at=clock_timestamp() where id=any(l.allocation_ids) and active;
  if exists(select 1 from people.work_allocations where claim_id=claim and active) then raise exception using errcode='55000',message='WORK_ALLOCATION_IMPACT_REQUIRED';end if;
  new_claim:=people_payroll.replace_claim(t,e,b,employee,claim,'service',rid,c.id,s,z,breaks,cid);
 else
  new_claim:=(proposal->>'new_claim_id')::uuid;
  if exists(select 1 from people.work_allocations where id=any(l.allocation_ids) and active)
   or not exists(select 1 from people.work_claims x where x.id=new_claim and x.tenant_id=t and x.legal_entity_id=e and x.branch_id=b and x.employee_id=employee and x.source_kind='attendance' and x.active
    and x.calendar_version_id=c.id and x.start_utc=(attendance->>'start_utc')::timestamptz and x.end_utc=(attendance->>'end_utc')::timestamptz
    and x.break_seconds=people.work_break_seconds(x.start_utc,x.end_utc,attendance->'breaks')) then
   raise exception using errcode='40001',message='PAYROLL_CORRECTION_SOURCE_CHANGED';end if;
 end if;
 perform service.payroll_billing_impact(t,e,b,l.id,oldrid,billing_proposal,'apply');
 if not remove_source then
  cursor_utc:=s;
  for br in select value from jsonb_array_elements(breaks||jsonb_build_array(jsonb_build_object('start_utc',z,'end_utc',z))) loop
   bs:=(br->>'start_utc')::timestamptz;be:=(br->>'end_utc')::timestamptz;
   if bs>cursor_utc then
    allocation:=people.allocate_work(t,e,b,employee,new_claim,'service',gen_random_uuid(),cursor_utc,bs,auth.uid());
    allocs:=array_append(allocs,allocation);
    insert into service.labor_allocations values(allocation,t,e,b,l.id,rid,new_claim,direct_claim);
   end if;cursor_utc:=be;
  end loop;
 end if;
 after_body:=after_body||jsonb_build_object('version',l.version+1,'current_revision_id',rid,'claim_id',new_claim,'allocation_ids',to_jsonb(allocs));
 insert into service.labor_revisions(id,tenant_id,legal_entity_id,branch_id,labor_id,employee_id,version,correction_id,supersedes_id,snapshot,recorded_by)
  values(rid,t,e,b,l.id,employee,l.version+1,cid,l.current_revision_id,after_body,auth.uid());
 update service.labor set version=version+1,current_revision_id=rid,claim_id=new_claim,allocation_ids=allocs,billing_consumption_id=null,status=case when remove_source then 'cancelled' else 'approved' end where id=l.id;
 if to_regprocedure('projects.service_payroll_cost_impact(uuid,uuid,uuid,uuid,uuid)') is not null then
  execute 'select projects.service_payroll_cost_impact($1,$2,$3,$4,$5)' using t,e,b,l.id,rid;
 end if;
 perform people.consume_organization(t,e,b,employee,'service_time',rid,sl::date,((el-interval '1 microsecond')::date)+1);
 if w.status='closed' and not remove_source and l.billing_kind='billable' then
  update service.work_orders set status='completed',closed_by=null,closed_at=null,version=version+1 where id=w.id;
  update service.tickets set status='resolved',version=version+1 where id=ticket.id and status='closed';
  insert into service.events(tenant_id,legal_entity_id,branch_id,aggregate_id,kind,version,action,reason,facts,actor_id)
   select t,e,b,x.id,x.kind,(service.snapshot(x.kind,x.id)->>'version')::bigint,'payroll_reopen','Linked revision requires separate financial review',service.snapshot(x.kind,x.id),auth.uid()
    from(values(w.id,'order'),(ticket.id,'ticket')) x(id,kind);
  order_reopened:=true;
 end if;
 insert into service.events(tenant_id,legal_entity_id,branch_id,aggregate_id,kind,version,action,reason,facts,actor_id)
  values(t,e,b,l.id,'labor',l.version+1,case when direct_claim then 'payroll_' else 'attendance_' end||actual_mode,
   'Independently approved linked payroll source correction',service.snapshot('labor',l.id),auth.uid());
 result:=result||jsonb_build_object('after',after_body,'claim_id',new_claim,'order_reopened_for_financial_review',order_reopened);
 insert into service.payroll_labor_impacts(tenant_id,legal_entity_id,branch_id,labor_id,correction_id,original_revision_id,replacement_revision_id,mode,approved_body,body,actor_id)
  values(t,e,b,l.id,cid,oldrid,rid,actual_mode,approved_result,result,auth.uid());
 return result;
end $$;
create function service.payroll_impact(t uuid,e uuid,b uuid,employee uuid,claim uuid,revision uuid,proposal jsonb,p_mode text)
returns jsonb language plpgsql security definer set search_path='' as $$declare entry uuid;begin
 select x.id into entry from service.labor x join people.work_claims c on c.id=x.claim_id where x.tenant_id=t and x.legal_entity_id=e and x.branch_id=b and x.employee_id=employee
  and x.claim_id=claim and x.owns_claim and c.active and c.source_kind='service' and c.source_id=coalesce(x.current_revision_id,x.id);
 if entry is null then raise exception using errcode='40001',message='PAYROLL_CORRECTION_SOURCE_CHANGED';end if;
 return service.payroll_revision_impact(t,e,b,employee,entry,claim,revision,proposal,p_mode,true);
end $$;
create function service.payroll_allocation_impact(t uuid,e uuid,b uuid,employee uuid,p_allocation uuid,revision uuid,proposal jsonb,p_mode text)
returns jsonb language plpgsql security definer set search_path='' as $$
declare a people.work_allocations%rowtype;entry uuid;body jsonb;begin
 select * into a from people.work_allocations x where x.id=p_allocation and x.tenant_id=t and x.legal_entity_id=e and x.branch_id=b and x.employee_id=employee and x.source_kind='service';
 select x.labor_id into entry from service.labor_allocations x where x.allocation_id=a.id and x.tenant_id=t and x.legal_entity_id=e and x.branch_id=b and not x.direct_claim;
 if entry is null then raise exception using errcode='40001',message='PAYROLL_CORRECTION_SOURCE_CHANGED';end if;
 -- Original inactive IDs remain usable only with the frozen reversal lineage.
 if not a.active and p_mode='read' then raise exception using errcode='40001',message='PAYROLL_CORRECTION_SOURCE_CHANGED';end if;
 body:=service.payroll_revision_impact(t,e,b,employee,entry,coalesce((proposal->>'current_claim_id')::uuid,a.claim_id),revision,proposal,p_mode,false);
 return body||jsonb_build_object('allocation_id',a.id);
end $$;
revoke all on all functions in schema service from public,anon,authenticated;
revoke all on function api.service_authorize(uuid,uuid,uuid,text),api.service_command(uuid,uuid,uuid,uuid,uuid,timestamptz,jsonb,bigint),
 api.service_list(uuid,uuid,uuid,text,uuid,uuid),api.service_detail(uuid,uuid,uuid,text,uuid,uuid),api.service_choices(uuid,uuid,uuid,text,uuid,uuid),api.service_own_receipt(uuid,uuid,uuid,uuid,text) from public,anon,authenticated;
grant execute on function api.service_authorize(uuid,uuid,uuid,text),api.service_command(uuid,uuid,uuid,uuid,uuid,timestamptz,jsonb,bigint),
 api.service_list(uuid,uuid,uuid,text,uuid,uuid),api.service_detail(uuid,uuid,uuid,text,uuid,uuid),api.service_choices(uuid,uuid,uuid,text,uuid,uuid),api.service_own_receipt(uuid,uuid,uuid,uuid,text) to authenticated;
