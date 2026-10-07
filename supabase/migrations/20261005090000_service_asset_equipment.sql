-- UNAPPLIED additive Service + Assets operational association. No capitalization.
create table service.asset_equipment_links(
 equipment_id uuid primary key,tenant_id uuid not null,legal_entity_id uuid not null,branch_id uuid not null,
 asset_id uuid not null,asset_version bigint not null check(asset_version between 1 and 9007199254740991),
 source_digest text not null check(source_digest ~ '^[0-9a-f]{64}$'),source_basis jsonb not null,
 reason text not null,created_by uuid not null references auth.users(id),created_at timestamptz not null default clock_timestamp(),
 unique(tenant_id,legal_entity_id,asset_id),
 foreign key(tenant_id,legal_entity_id,equipment_id) references service.equipment(tenant_id,legal_entity_id,id),
 foreign key(tenant_id,legal_entity_id,asset_id) references assets.register(tenant_id,legal_entity_id,id),
 foreign key(tenant_id,legal_entity_id,branch_id) references core.branches(tenant_id,legal_entity_id,id)
);
alter table service.asset_equipment_links enable row level security;
alter table service.asset_equipment_links force row level security;
revoke all on service.asset_equipment_links from public,anon,authenticated;
create trigger service_asset_link_immutable before update or delete on service.asset_equipment_links
 for each row execute function service.immutable();
alter table service.tickets alter column customer_id drop not null;

create function service.asset_source(t uuid,e uuid,b uuid,p_asset uuid,p_lock boolean default false,p_eligible boolean default true)
returns jsonb language plpgsql security definer set search_path='' as $$
declare a assets.register%rowtype;basis jsonb;begin
 perform service.require_access(t,e,b,'service.view');perform assets.require_access(t,e,b,'assets.view');
 if p_lock then select * into a from assets.register where tenant_id=t and legal_entity_id=e and id=p_asset for update;
 else select * into a from assets.register where tenant_id=t and legal_entity_id=e and id=p_asset;end if;
 if a.id is null or p_eligible and(a.status<>'active' or a.branch_id<>b) then
  raise exception using errcode='55000',message='SERVICE_ASSET_NOT_ELIGIBLE';end if;
 basis:=jsonb_build_object('id',a.id,'tenant_id',t,'legal_entity_id',e,'branch_id',a.branch_id,
  'code',a.code,'name',a.name,'ownership',a.ownership,'in_service',a.in_service,'location_id',a.location_id,
  'location_name',(select name from assets.locations where id=a.location_id),'custodian_id',a.custodian_id,
  'custodian_name',(select display_name from people.employees where tenant_id=t and legal_entity_id=e and id=a.custodian_id),
  'status',a.status,'version',a.version);
 return basis||jsonb_build_object('digest',encode(extensions.digest(basis::text,'sha256'),'hex'));
end $$;
create function service.asset_equipment_for(p_kind text,p_id uuid) returns uuid language plpgsql stable security definer set search_path='' as $$
declare eq uuid;begin
 case p_kind
 when 'equipment' then eq:=p_id;
 when 'ticket' then select equipment_id into eq from service.tickets where id=p_id;
 when 'coverage' then select equipment_id into eq from service.coverage_versions where id=p_id;
 when 'order' then select t.equipment_id into eq from service.work_orders w join service.tickets t on t.id=w.ticket_id where w.id=p_id;
 when 'labor' then select t.equipment_id into eq from service.labor l join service.work_orders w on w.id=l.order_id join service.tickets t on t.id=w.ticket_id where l.id=p_id;
 when 'plan' then select equipment_id into eq from service.maintenance_plans where id=p_id;
 when 'reading' then select equipment_id into eq from service.meter_readings where id=p_id;
 when 'occurrence' then select p.equipment_id into eq from service.maintenance_occurrences o join service.maintenance_plans p on p.id=o.plan_id where o.id=p_id;
 else eq:=null;end case;
 return eq;
end $$;
create function service.asset_equipment_guard(t uuid,e uuid,b uuid,p_equipment uuid,p_lock boolean default false,p_eligible boolean default true)
returns void language plpgsql security definer set search_path='' as $$
declare l service.asset_equipment_links%rowtype;q service.equipment%rowtype;begin
 select * into q from service.equipment where tenant_id=t and legal_entity_id=e and branch_id=b and id=p_equipment;
 if q.id is null then raise exception using errcode='P0002',message='SERVICE_NOT_FOUND';end if;
 if q.kind='asset' then
  select * into l from service.asset_equipment_links where tenant_id=t and legal_entity_id=e and branch_id=b and equipment_id=q.id and asset_id=q.provider_id;
  if l.equipment_id is null or q.customer_id is not null then raise exception using errcode='55000',message='SERVICE_ASSET_LINK_REQUIRED';end if;
  perform service.asset_source(t,e,b,l.asset_id,p_lock,p_eligible);
 end if;
end $$;

create function api.service_asset_authorize(p_tenant_id uuid,p_legal_entity_id uuid,p_branch_id uuid,p_capability text)
returns jsonb language plpgsql stable security definer set search_path='' as $$begin
 perform service.require_access(p_tenant_id,p_legal_entity_id,p_branch_id,p_capability);
 perform assets.require_access(p_tenant_id,p_legal_entity_id,p_branch_id,'assets.view');
 return jsonb_build_object('actor_id',auth.uid(),'tenant_id',p_tenant_id,'legal_entity_id',p_legal_entity_id,'branch_id',p_branch_id,'capability',p_capability,'authorized',true);
end $$;
create function api.service_asset_sources(p_tenant_id uuid,p_legal_entity_id uuid,p_branch_id uuid,p_after uuid default null)
returns jsonb language plpgsql security definer set search_path='' as $$declare items jsonb;begin
 perform service.require_access(p_tenant_id,p_legal_entity_id,p_branch_id,'service.configure');
 perform assets.require_access(p_tenant_id,p_legal_entity_id,p_branch_id,'assets.view');
 select coalesce(jsonb_agg(service.asset_source(p_tenant_id,p_legal_entity_id,p_branch_id,q.id) order by q.id),'[]') into items
 from(select a.id from assets.register a where a.tenant_id=p_tenant_id and a.legal_entity_id=p_legal_entity_id and a.branch_id=p_branch_id and a.status='active'
  and(p_after is null or a.id>p_after) and not exists(select 1 from service.asset_equipment_links l where l.tenant_id=p_tenant_id and l.legal_entity_id=p_legal_entity_id and l.asset_id=a.id)
  order by a.id limit 51) q;
 return jsonb_build_object('tenant_id',p_tenant_id,'legal_entity_id',p_legal_entity_id,'branch_id',p_branch_id,'items',items-50,
  'next_cursor',case when jsonb_array_length(items)>50 then items->49->>'id' end);
end $$;
create function api.service_asset_equipment_command(p_tenant_id uuid,p_legal_entity_id uuid,p_branch_id uuid,p_command_id uuid,p_idempotency_key uuid,
 p_issued_at timestamptz,p_payload jsonb,p_expected_version bigint) returns jsonb language plpgsql security definer set search_path='' as $$
declare id uuid;source jsonb;hash text;replay jsonb;reason text;begin
 perform service.require_access(p_tenant_id,p_legal_entity_id,p_branch_id,'service.configure');
 perform assets.require_access(p_tenant_id,p_legal_entity_id,p_branch_id,'assets.view');
 if jsonb_typeof(p_payload) is distinct from 'object' or octet_length(p_payload::text)>8192
  or p_payload->>'action' is distinct from 'equipment' or p_payload->>'kind' is distinct from 'asset' or p_payload->>'customer_id' is not null
  or p_expected_version is distinct from 0 or p_command_id is null or p_idempotency_key is null or p_issued_at is null or p_issued_at>clock_timestamp()+interval '5 minutes'
  or coalesce(p_payload->>'id','') !~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
  or coalesce(p_payload->>'provider_id','') !~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
  or exists(select 1 from jsonb_object_keys(p_payload) k where k<>all(array['action','id','reason','code','name','identity','kind','customer_id','provider_id','provider_version','provider_digest'])) then
  raise exception using errcode='22023',message='SERVICE_ASSET_COMMAND_INVALID';end if;
 id:=(p_payload->>'id')::uuid;reason:=service.text(p_payload->'reason',1000);
 perform service.text(p_payload->'name',160);perform service.text(p_payload->'identity',160);
 if coalesce(p_payload->>'code','') !~ '^[A-Z0-9][A-Z0-9_-]{0,31}$' or jsonb_typeof(p_payload->'provider_version') is distinct from 'number'
  or coalesce(p_payload->>'provider_digest','') !~ '^[0-9a-f]{64}$' then raise exception using errcode='22023',message='SERVICE_ASSET_COMMAND_INVALID';end if;
 hash:=core.wave3_request_hash('service.asset_equipment',p_command_id,p_tenant_id,p_legal_entity_id,p_branch_id,p_payload,p_expected_version);
 -- Fresh authorities above precede actor replay. Historical exact replay remains an original receipt.
 replay:=core.wave3_replay(p_tenant_id,'service.asset_equipment',p_command_id,p_idempotency_key,hash);if replay is not null then return replay;end if;
 perform pg_advisory_xact_lock(hashtextextended('people.payroll:'||p_tenant_id||':'||p_legal_entity_id,0));
 perform pg_advisory_xact_lock(hashtextextended('projects:'||p_tenant_id||':'||p_legal_entity_id,0));
 perform pg_advisory_xact_lock(hashtextextended('service:'||p_tenant_id||':'||p_legal_entity_id,0));
 source:=service.asset_source(p_tenant_id,p_legal_entity_id,p_branch_id,(p_payload->>'provider_id')::uuid,true);
 if source->'version'<>p_payload->'provider_version' or source->>'digest'<>p_payload->>'provider_digest' then raise exception using errcode='40001',message='SERVICE_ASSET_SOURCE_CHANGED';end if;
 insert into service.equipment(id,tenant_id,legal_entity_id,branch_id,code,name,identity,kind,customer_id,provider_id,created_by)
 values(id,p_tenant_id,p_legal_entity_id,p_branch_id,p_payload->>'code',p_payload->>'name',p_payload->>'identity','asset',null,(p_payload->>'provider_id')::uuid,auth.uid());
 insert into service.asset_equipment_links(equipment_id,tenant_id,legal_entity_id,branch_id,asset_id,asset_version,source_digest,source_basis,reason,created_by)
 values(id,p_tenant_id,p_legal_entity_id,p_branch_id,(source->>'id')::uuid,(source->>'version')::bigint,source->>'digest',source,reason,auth.uid());
 insert into service.events(tenant_id,legal_entity_id,branch_id,aggregate_id,kind,version,action,reason,facts,actor_id)
 values(p_tenant_id,p_legal_entity_id,p_branch_id,id,'equipment',1,'asset_equipment',reason,service.snapshot('equipment',id),auth.uid());
 return core.wave3_finish_command(p_tenant_id,'service.asset_equipment',p_command_id,'service.equipment',id,p_idempotency_key,hash,null,
  jsonb_build_object('id',id,'tenant_id',p_tenant_id,'legal_entity_id',p_legal_entity_id,'branch_id',p_branch_id,'kind','equipment','version',1,'status','active'),p_legal_entity_id,p_branch_id);
end $$;
create function api.service_asset_link(p_tenant_id uuid,p_legal_entity_id uuid,p_branch_id uuid,p_equipment_id uuid)
returns jsonb language plpgsql security definer set search_path='' as $$declare l service.asset_equipment_links%rowtype;begin
 perform service.require_access(p_tenant_id,p_legal_entity_id,p_branch_id,'service.view');perform assets.require_access(p_tenant_id,p_legal_entity_id,p_branch_id,'assets.view');
 select * into l from service.asset_equipment_links where tenant_id=p_tenant_id and legal_entity_id=p_legal_entity_id and branch_id=p_branch_id and equipment_id=p_equipment_id;
 if l.equipment_id is null then raise exception using errcode='P0002',message='SERVICE_NOT_FOUND';end if;
 return to_jsonb(l);
end $$;
create function api.service_asset_own_receipt(p_tenant_id uuid,p_legal_entity_id uuid,p_branch_id uuid,p_idempotency_key uuid)
returns jsonb language plpgsql security definer set search_path='' as $$declare r jsonb;begin
 perform service.require_access(p_tenant_id,p_legal_entity_id,p_branch_id,'service.configure');perform assets.require_access(p_tenant_id,p_legal_entity_id,p_branch_id,'assets.view');
 select response into r from core.command_receipts where tenant_id=p_tenant_id and legal_entity_id=p_legal_entity_id and branch_id=p_branch_id and actor_id=auth.uid() and command_name='service.asset_equipment' and idempotency_key=p_idempotency_key;
 if r is not null and(r->'entity'->>'legal_entity_id'<>p_legal_entity_id::text or r->'entity'->>'branch_id'<>p_branch_id::text) then return null;end if;return r;
end $$;

-- Preserve the reviewed customer implementation while governing internal sources.
alter function service.ticket_create(uuid,uuid,uuid,uuid,jsonb) rename to ticket_create_customer;
create function service.ticket_create(t uuid,e uuid,b uuid,id uuid,p jsonb) returns void language plpgsql security definer set search_path='' as $$
declare eq service.equipment%rowtype;policy service.sla_policies%rowtype;at timestamptz;begin
 select * into eq from service.equipment where tenant_id=t and legal_entity_id=e and branch_id=b and equipment.id=(p->>'equipment_id')::uuid and status='active';
 if eq.kind is distinct from 'asset' then perform service.ticket_create_customer(t,e,b,id,p);return;end if;
 perform service.asset_equipment_guard(t,e,b,eq.id,true);
 at:=service.utc(p->'observed_utc');select * into policy from service.sla_policies where tenant_id=t and legal_entity_id=e and branch_id=b and sla_policies.id=(p->>'policy_id')::uuid;
 if p->>'customer_id' is not null or p->>'contact_id' is not null or policy.id is null
  or coalesce(p->>'code','') !~ '^[A-Z0-9][A-Z0-9_-]{0,31}$' or coalesce(p->>'priority','') not in('low','normal','high','urgent') or at>clock_timestamp()+interval '5 minutes'
  or p->>'coverage_id' is not null and not exists(select 1 from service.coverage_versions c where c.tenant_id=t and c.legal_entity_id=e and c.branch_id=b and c.id=(p->>'coverage_id')::uuid and c.equipment_id=eq.id
   and daterange(c.start_date,c.end_date_exclusive,'[)') @> (at at time zone(select timezone from core.legal_entities where tenant_id=t and legal_entities.id=e))::date) then
  raise exception using errcode='22023',message='SERVICE_INTERNAL_TICKET_INVALID';end if;
 insert into service.tickets(id,tenant_id,legal_entity_id,branch_id,code,name,classification,customer_id,contact_id,equipment_id,coverage_id,policy_id,priority,owner_id,started_utc,clock_start_utc,response_due,resolution_due,created_by)
 values(id,t,e,b,p->>'code',service.text(p->'name',160),service.text(p->'classification',80),null,null,eq.id,(p->>'coverage_id')::uuid,policy.id,p->>'priority',(p->>'owner_id')::uuid,
  at,at,service.due(policy.windows,at,policy.response_seconds),service.due(policy.windows,at,policy.resolution_seconds),auth.uid());
end $$;
alter function api.service_command(uuid,uuid,uuid,uuid,uuid,timestamptz,jsonb,bigint) rename to service_command_customer_base;
create function api.service_command(p_tenant_id uuid,p_legal_entity_id uuid,p_branch_id uuid,p_command_id uuid,p_idempotency_key uuid,p_issued_at timestamptz,p_payload jsonb,p_expected_version bigint)
returns jsonb language plpgsql security definer set search_path='' as $$declare act text:=p_payload->>'action';eq uuid;original jsonb;begin
 if service.capability(act) is null or coalesce(jsonb_typeof(p_payload),'null')<>'object' or octet_length(p_payload::text)>65536 or p_command_id is null or p_idempotency_key is null
  or p_issued_at is null or p_issued_at>clock_timestamp()+interval '5 minutes' or p_expected_version is null or p_expected_version not between 0 and 9007199254740990
  or coalesce(p_payload->>'id','') !~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
  or exists(select 1 from jsonb_object_keys(p_payload) k where k<>all(service.fields(act))) then raise exception using errcode='22023',message='SERVICE_COMMAND_INVALID';end if;
 perform service.text(p_payload->'reason',1000);
 perform service.require_access(p_tenant_id,p_legal_entity_id,p_branch_id,service.capability(act));
 eq:=case when act in('ticket','coverage','plan','reading') then(p_payload->>'equipment_id')::uuid
  when act='order' then service.asset_equipment_for('ticket',(p_payload->>'ticket_id')::uuid)
  when act='labor' then service.asset_equipment_for('order',(p_payload->>'order_id')::uuid)
  else null end;
 -- The ordinary action-to-kind helper is explicit; no provider identity comes from client labels.
 if eq is null then eq:=service.asset_equipment_for(case when act in('dispatch','accept','start','complete','close','cancel_order') then 'order'
  when act in('approve_labor','cancel_labor') then 'labor' when act='generate' then 'plan' when act='defer' then 'occurrence'
  when act in('pause','resume','evaluate','reprioritize','cancel_ticket') then 'ticket' else null end,(p_payload->>'id')::uuid);end if;
 if exists(select 1 from service.equipment where tenant_id=p_tenant_id and legal_entity_id=p_legal_entity_id and branch_id=p_branch_id and id=eq and kind='asset') then
  perform assets.require_access(p_tenant_id,p_legal_entity_id,p_branch_id,'assets.view');
  original:=core.wave3_replay(p_tenant_id,'service.'||act,p_command_id,p_idempotency_key,
   core.wave3_request_hash('service.'||act,p_command_id,p_tenant_id,p_legal_entity_id,p_branch_id,p_payload,p_expected_version));
  if original is not null then return original;end if;
  perform pg_advisory_xact_lock(hashtextextended('people.payroll:'||p_tenant_id||':'||p_legal_entity_id,0));
  perform pg_advisory_xact_lock(hashtextextended('projects:'||p_tenant_id||':'||p_legal_entity_id,0));
  perform pg_advisory_xact_lock(hashtextextended('service:'||p_tenant_id||':'||p_legal_entity_id,0));
  perform service.asset_equipment_guard(p_tenant_id,p_legal_entity_id,p_branch_id,eq,true,act in('ticket','coverage','plan','reading','generate','order','dispatch','accept','start','labor'));
  if act='labor' and coalesce(p_payload->>'billing_kind','nonbillable')<>'nonbillable' then raise exception using errcode='55000',message='SERVICE_INTERNAL_NONBILLABLE';end if;
  if act='complete' and(p_payload->>'customer_confirmed' is distinct from 'false' or nullif(btrim(p_payload->>'exception_reason'),'') is null) then
   raise exception using errcode='22023',message='SERVICE_INTERNAL_CONFIRMATION_REQUIRED';end if;
 end if;
 return api.service_command_customer_base(p_tenant_id,p_legal_entity_id,p_branch_id,p_command_id,p_idempotency_key,p_issued_at,p_payload,p_expected_version);
end $$;
create or replace function api.service_list(p_tenant_id uuid,p_legal_entity_id uuid,p_branch_id uuid,p_kind text,p_after uuid default null,p_parent uuid default null) returns jsonb
language plpgsql stable security definer set search_path='' as $$declare items jsonb;tablename text:=service.table_for(p_kind);parent_column text;cost boolean;begin
 perform service.require_access(p_tenant_id,p_legal_entity_id,p_branch_id,'service.view');
 if tablename is null then raise exception using errcode='22023',message='SERVICE_KIND_INVALID';end if;
 cost:=core.has_permission(p_tenant_id,'service.cost.view',p_legal_entity_id,p_branch_id);
 parent_column:=case p_kind when 'coverage' then 'equipment_id' when 'order' then 'ticket_id' when 'labor' then 'order_id' when 'reading' then 'equipment_id' when 'occurrence' then 'plan_id' end;
 if p_parent is not null and parent_column is null then raise exception using errcode='22023',message='SERVICE_PARENT_INVALID';end if;
 execute format('select coalesce(jsonb_agg(service.public_snapshot($1,q.id,$6) order by q.id),''[]''::jsonb) from(select id from service.%I where tenant_id=$2 and legal_entity_id=$3 and branch_id=$4 and($5 is null or id>$5) and service.asset_read_allowed($2,$3,$4,$1,id)%s order by id limit 51) q',
  tablename,case when p_parent is null then '' else format(' and %I=$7',parent_column) end)
 into items using p_kind,p_tenant_id,p_legal_entity_id,p_branch_id,p_after,cost,p_parent;
 return jsonb_build_object('tenant_id',p_tenant_id,'legal_entity_id',p_legal_entity_id,'branch_id',p_branch_id,'kind',p_kind,'items',items-50,'next_cursor',case when jsonb_array_length(items)>50 then items->49->>'id' end);end $$;

-- Scope/asset authority is checked before all historical internal projections.
create function service.asset_read_allowed(t uuid,e uuid,b uuid,p_kind text,p_id uuid) returns boolean language plpgsql stable security definer set search_path='' as $$
declare eq uuid:=service.asset_equipment_for(p_kind,p_id);begin
 if not exists(select 1 from service.equipment where id=eq and kind='asset') then return true;end if;
 return core.has_permission(t,'assets.view',e,b) and exists(select 1 from billing.tenant_subscriptions s join billing.plan_entitlements p on p.plan_code=s.plan_code
  where s.tenant_id=t and p.entitlement_code='module.assets' and p.enabled and
   ((s.status='trialing' and s.trial_ends_at>now()) or(s.status='active' and(s.current_period_ends_at is null or s.current_period_ends_at>now()))));
end $$;
-- Guard snapshots centrally: customer rows remain readable; internal rows require both authorities.
alter function service.public_snapshot(text,uuid,boolean) rename to public_snapshot_customer_base;
create function service.public_snapshot(kind text,id uuid,cost boolean) returns jsonb language plpgsql stable security definer set search_path='' as $$
declare r jsonb;begin
 r:=service.public_snapshot_customer_base(kind,id,cost);
 if r is not null and not service.asset_read_allowed((r->>'tenant_id')::uuid,(r->>'legal_entity_id')::uuid,(r->>'branch_id')::uuid,kind,id) then
  raise exception using errcode='42501',message='SERVICE_ASSET_ACCESS_REQUIRED';end if;return r;
end $$;
alter function api.service_own_receipt(uuid,uuid,uuid,uuid,text) rename to service_own_receipt_customer_base;
create function api.service_own_receipt(p_tenant_id uuid,p_legal_entity_id uuid,p_branch_id uuid,p_idempotency_key uuid,p_action text)
returns jsonb language plpgsql stable security definer set search_path='' as $$declare r jsonb;begin
 r:=api.service_own_receipt_customer_base(p_tenant_id,p_legal_entity_id,p_branch_id,p_idempotency_key,p_action);
 if r is not null and not service.asset_read_allowed(p_tenant_id,p_legal_entity_id,p_branch_id,r#>>'{entity,kind}',(r#>>'{entity,id}')::uuid) then
  raise exception using errcode='42501',message='SERVICE_ASSET_ACCESS_REQUIRED';end if;return r;
end $$;
create function service.internal_ticket_invariant() returns trigger language plpgsql set search_path='' as $$declare k text;begin
 select kind into k from service.equipment where tenant_id=new.tenant_id and legal_entity_id=new.legal_entity_id and id=new.equipment_id;
 if(k='asset' and(new.customer_id is not null or new.contact_id is not null)) or(k='customer' and new.customer_id is null) then
  raise exception using errcode='22023',message='SERVICE_INTERNAL_TICKET_INVALID';end if;return new;
end $$;
create trigger service_internal_ticket_invariant before insert or update on service.tickets for each row execute function service.internal_ticket_invariant();
create function service.internal_labor_invariant() returns trigger language plpgsql set search_path='' as $$begin
 if new.billing_kind<>'nonbillable' and exists(select 1 from service.work_orders w join service.tickets t on t.id=w.ticket_id
  where w.id=new.order_id and t.customer_id is null) then raise exception using errcode='55000',message='SERVICE_INTERNAL_NONBILLABLE';end if;return new;
end $$;
create trigger service_internal_labor_invariant before insert or update on service.labor for each row execute function service.internal_labor_invariant();
alter function service.billing_source(uuid,uuid,uuid,uuid) rename to billing_source_customer_base;
create function service.billing_source(t uuid,e uuid,b uuid,p_id uuid) returns jsonb language plpgsql security definer set search_path='' as $$begin
 if exists(select 1 from service.labor l join service.work_orders w on w.id=l.order_id join service.tickets q on q.id=w.ticket_id
  where l.tenant_id=t and l.legal_entity_id=e and l.branch_id=b and l.id=p_id and q.customer_id is null) then raise exception using errcode='55000',message='SERVICE_INTERNAL_NONBILLABLE';end if;
 return service.billing_source_customer_base(t,e,b,p_id);
end $$;
revoke all on all functions in schema service from public,anon,authenticated;
revoke all on function api.service_command_customer_base(uuid,uuid,uuid,uuid,uuid,timestamptz,jsonb,bigint),api.service_own_receipt_customer_base(uuid,uuid,uuid,uuid,text),
 api.service_asset_authorize(uuid,uuid,uuid,text),api.service_asset_sources(uuid,uuid,uuid,uuid),api.service_asset_equipment_command(uuid,uuid,uuid,uuid,uuid,timestamptz,jsonb,bigint),
 api.service_asset_link(uuid,uuid,uuid,uuid),api.service_asset_own_receipt(uuid,uuid,uuid,uuid),
 api.service_command(uuid,uuid,uuid,uuid,uuid,timestamptz,jsonb,bigint),api.service_own_receipt(uuid,uuid,uuid,uuid,text) from public,anon,authenticated;
grant execute on function api.service_asset_authorize(uuid,uuid,uuid,text),api.service_asset_sources(uuid,uuid,uuid,uuid),api.service_asset_equipment_command(uuid,uuid,uuid,uuid,uuid,timestamptz,jsonb,bigint),
 api.service_asset_link(uuid,uuid,uuid,uuid),api.service_asset_own_receipt(uuid,uuid,uuid,uuid),
 api.service_command(uuid,uuid,uuid,uuid,uuid,timestamptz,jsonb,bigint),api.service_own_receipt(uuid,uuid,uuid,uuid,text) to authenticated;
