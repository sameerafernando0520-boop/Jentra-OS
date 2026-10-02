-- Unapplied Wave 3 candidate. In-app notice creation remains in the source
-- command transaction; external delivery workers are never in the posting path.
create table core.wave3_notification_subscriptions (
 id uuid primary key, tenant_id uuid not null, legal_entity_id uuid, branch_id uuid,
 recipient_id uuid not null, event_class text not null check(event_class in
  ('submission','decision','posting','exception','due','allocation','reconciliation','close','reversal')),
 enabled boolean not null, version bigint not null check(version>0),
 created_by uuid not null references auth.users(id), updated_by uuid not null references auth.users(id),
 created_at timestamptz not null default clock_timestamp(),
 updated_at timestamptz not null default clock_timestamp(),
 unique(tenant_id,id),
 unique nulls not distinct(tenant_id,legal_entity_id,branch_id,recipient_id,event_class),
 foreign key(tenant_id,legal_entity_id) references core.legal_entities(tenant_id,id),
 foreign key(tenant_id,branch_id) references core.branches(tenant_id,id),
 foreign key(tenant_id,recipient_id) references core.memberships(tenant_id,user_id),
 check(branch_id is null or legal_entity_id is not null)
);
alter table core.wave3_notification_subscriptions enable row level security;
alter table core.wave3_notification_subscriptions force row level security;
revoke all on core.wave3_notification_subscriptions from public,anon,authenticated;
create index wave3_notification_subscriptions_delivery on core.wave3_notification_subscriptions
 (tenant_id,event_class,enabled,legal_entity_id,branch_id,recipient_id);
create index wave3_notification_subscriptions_actor on core.wave3_notification_subscriptions(updated_by);
create index wave3_notification_subscriptions_creator on core.wave3_notification_subscriptions(created_by);
create index wave3_notification_subscriptions_member on core.wave3_notification_subscriptions(tenant_id,recipient_id);
create index wave3_notification_subscriptions_branch on core.wave3_notification_subscriptions(tenant_id,branch_id);
create index wave3_notification_subscriptions_entity on core.wave3_notification_subscriptions(tenant_id,legal_entity_id);
create unique index wave3_notification_command_recipient_class on workflow.notifications
 (tenant_id,command_id,recipient_id,notification_type)
 where command_id is not null and notification_type like 'wave3.%'
  and not (notification_type='wave3.due' and source_context ? 'due_key');

create function api.configure_wave3_notification_subscription(
 p_tenant_id uuid,p_legal_entity_id uuid,p_branch_id uuid,p_command_id uuid,
 p_idempotency_key uuid,p_client_timestamp timestamptz,p_payload jsonb,
 p_expected_entity_version bigint default null) returns jsonb
language plpgsql security definer set search_path='' as $$
declare v_id uuid:=(p_payload->>'id')::uuid;recipient uuid:=(p_payload->>'recipient_id')::uuid;
 cls text:=p_payload->>'event_class';v_enabled boolean;old_row core.wave3_notification_subscriptions%rowtype;
 new_row core.wave3_notification_subscriptions%rowtype;h text;replay jsonb;before_row jsonb;result jsonb;
begin
 perform core.wave3_require_scope(p_tenant_id,'core.roles.manage',p_legal_entity_id,p_branch_id);
 if v_id is null or recipient is null or cls is null or cls not in
  ('submission','decision','posting','exception','due','allocation','reconciliation','close','reversal')
  or jsonb_typeof(p_payload->'enabled') is distinct from 'boolean'
  or jsonb_typeof(p_payload) is distinct from 'object'
  or exists(select 1 from jsonb_object_keys(p_payload) x where x not in('id','recipient_id','event_class','enabled')) then
  raise exception using errcode='22023',message='NOTIFICATION_SUBSCRIPTION_INVALID';end if;
 v_enabled:=(p_payload->>'enabled')::boolean;
 h:=core.wave3_request_hash('workflow.wave3.notification.configure',p_command_id,p_tenant_id,
  p_legal_entity_id,p_branch_id,p_payload,p_expected_entity_version);
 replay:=core.wave3_replay(p_tenant_id,'workflow.wave3.notification.configure',p_command_id,p_idempotency_key,h);
 if replay is not null then return replay;end if;
 perform pg_advisory_xact_lock(hashtextextended(p_tenant_id::text||':wave3-notification:'||cls,0));
 if not exists(select 1 from core.memberships where tenant_id=p_tenant_id and user_id=recipient
  and (not v_enabled or status='active')) then
  raise exception using errcode='42501',message='NOTIFICATION_RECIPIENT_UNAVAILABLE';end if;
 select * into old_row from core.wave3_notification_subscriptions
  where tenant_id=p_tenant_id and id=v_id for update;
 if old_row.id is not null and
  (old_row.recipient_id<>recipient or old_row.event_class<>cls
   or old_row.legal_entity_id is distinct from p_legal_entity_id
   or old_row.branch_id is distinct from p_branch_id) then
  raise exception using errcode='22023',message='NOTIFICATION_SUBSCRIPTION_IDENTITY_IMMUTABLE';end if;
 perform core.wave3_assert_expected_version(coalesce(old_row.version,0),p_expected_entity_version,
  case when old_row.id is null then '{}'::jsonb else to_jsonb(old_row) end);
 if v_enabled and (old_row.id is null or not old_row.enabled)
  and (select count(*) from core.wave3_notification_subscriptions
    where tenant_id=p_tenant_id and event_class=cls and enabled)>=100 then
  raise exception using errcode='54000',message='NOTIFICATION_RECIPIENT_LIMIT';end if;
 before_row:=case when old_row.id is null then null else to_jsonb(old_row) end;
 if old_row.id is null then
  insert into core.wave3_notification_subscriptions(id,tenant_id,legal_entity_id,branch_id,
   recipient_id,event_class,enabled,version,created_by,updated_by)
   values(v_id,p_tenant_id,p_legal_entity_id,p_branch_id,recipient,cls,v_enabled,1,auth.uid(),auth.uid())
   returning * into new_row;
 else
  update core.wave3_notification_subscriptions set enabled=v_enabled,version=version+1,
   updated_by=auth.uid(),updated_at=clock_timestamp()
   where id=v_id returning * into new_row;
 end if;
 result:=jsonb_build_object('tenant_id',p_tenant_id,'legal_entity_id',p_legal_entity_id,'branch_id',p_branch_id,
  'id',v_id,'recipient_id',recipient,'event_class',cls,
  'enabled',new_row.enabled,'version',new_row.version);
 return core.wave3_finish_command(p_tenant_id,'workflow.wave3.notification.configure',p_command_id,
  'wave3_notification_subscription',v_id,p_idempotency_key,h,before_row,result,
  p_legal_entity_id,p_branch_id,'{}',jsonb_build_object('to_status',case when v_enabled then 'enabled' else 'disabled' end));
end $$;
revoke all on function api.configure_wave3_notification_subscription(uuid,uuid,uuid,uuid,uuid,timestamptz,jsonb,bigint)
 from public,anon,authenticated;
grant execute on function api.configure_wave3_notification_subscription(uuid,uuid,uuid,uuid,uuid,timestamptz,jsonb,bigint)
 to authenticated;

create function core.wave3_notification_classes(topic text) returns text[]
language sql immutable set search_path='' as $$
 select array_remove(array[
  case when topic ~ '(^|[.])(submit|submitted|issue|issued)$' then 'submission' end,
  case when topic ~ '(^|[.])(approve|approved|reject|rejected|decide|decision)$' then 'decision' end,
  case when topic ~ '(^|[.])(post|posted|record|recorded|confirm|confirmed|received|dispatch|dispatched|convert|converted|adjust)$' then 'posting' end,
  case when topic ~ '(^|[.])(exception|variance|shortage|failed|blocked)$' then 'exception' end,
  case when topic ~ '(^|[.])(overdue|due)$' then 'due' end,
  case when topic ~ '(^|[.])(allocate|allocated|reserve|reserved|release|released|maintained)$' then 'allocation' end,
  case when topic ~ '(^|[.])(reconcile|reconciled|match|matched|unmatch|unmatched)$' then 'reconciliation' end,
  case when topic ~ '(^|[.])(close|closed|reopen|reopened|reviewed)$' then 'close' end,
  case when topic ~ '(^|[.])(reverse|reversed|recall|recalled)$' then 'reversal' end
 ],null)::text[]
$$;
revoke all on function core.wave3_notification_classes(text) from public,anon,authenticated;

create function core.wave3_notify_command() returns trigger
language plpgsql security definer set search_path='' as $$
declare cfg jsonb;classes text[]:='{}';cls text;recipient record;v_topic text;event_status text;
 v_kind text;v_permission text;
begin
 if new.command_id is null or new.aggregate_id is null or new.legal_entity_id is null
  or new.command_name like 'people.%' or new.aggregate_type='wave3_notification_subscription' then
  return new;end if;
 v_kind:=case new.aggregate_type when 'request_for_quote' then 'rfq' else new.aggregate_type end;
 cfg:=core.wave3_source_descriptor(v_kind);
 v_permission:=coalesce(cfg->>'permission',case new.aggregate_type
  when 'stock_reservation' then 'inventory.stock.view'
  when 'close_control_review' then 'finance.view'
  when 'fiscal_period_event' then 'finance.view'
  when 'fx_revaluation' then 'finance.view'
  when 'customer_allocation' then 'finance.receipts.view'
  when 'customer_allocation_reversal' then 'finance.receipts.view'
  when 'supplier_allocation' then 'finance.payments.manage'
  when 'supplier_allocation_reversal' then 'finance.payments.manage'
  when 'bank_unmatch' then 'finance.view' end);
 if v_permission is null then
  return new;end if;
 for v_topic in select distinct o.topic from core.outbox_events o
  where o.tenant_id=new.tenant_id and o.command_id=new.command_id loop
  classes:=classes||core.wave3_notification_classes(v_topic);
 end loop;
 for event_status in select distinct to_status from workflow.process_events
  where tenant_id=new.tenant_id and command_id=new.command_id loop
  classes:=classes||core.wave3_notification_classes(coalesce(event_status,''));
 end loop;
 if new.aggregate_type='supplier_bill' and
  (coalesce((new.response#>>'{entity,match,blocked}')::boolean,false)
   or jsonb_array_length(coalesce(new.response#>'{entity,match,exceptions}','[]'))>0) then
  classes:=classes||array['exception'];end if;
 if new.response#>>'{entity,reverse_of}' is not null then
  classes:=classes||array['reversal'];end if;
 for cls in select distinct x from unnest(classes) x loop
  for recipient in
   select distinct s.recipient_id from core.wave3_notification_subscriptions s
   join core.memberships m on m.tenant_id=s.tenant_id and m.user_id=s.recipient_id and m.status='active'
   where s.tenant_id=new.tenant_id and s.event_class=cls and s.enabled
    and (s.legal_entity_id is null or s.legal_entity_id=new.legal_entity_id)
    and (s.branch_id is null or s.branch_id=new.branch_id)
    and exists(
     select 1 from core.role_assignments ra join core.role_permissions rp
      on rp.tenant_id=ra.tenant_id and rp.role_id=ra.role_id
     where ra.tenant_id=new.tenant_id and ra.membership_id=m.id
      and rp.permission_code=v_permission
      and (ra.legal_entity_id is null or ra.legal_entity_id=new.legal_entity_id)
      and (ra.branch_id is null or ra.branch_id=new.branch_id))
    and (cfg is null or not (cfg->>'cost')::boolean or not exists(
     select 1 from unnest(array['inventory.stock.view','inventory.cost.view']) required(permission)
     where not exists(select 1 from core.role_assignments ra join core.role_permissions rp
      on rp.tenant_id=ra.tenant_id and rp.role_id=ra.role_id
      where ra.tenant_id=new.tenant_id and ra.membership_id=m.id
       and rp.permission_code=required.permission
       and (ra.legal_entity_id is null or ra.legal_entity_id=new.legal_entity_id)
       and (ra.branch_id is null or ra.branch_id=new.branch_id))))
  loop
   insert into workflow.notifications(tenant_id,recipient_id,notification_type,title,body,
    aggregate_type,aggregate_id,legal_entity_id,branch_id,actor_id,request_id,command_id,
    correlation_id,source_context,created_by,updated_by)
   values(new.tenant_id,recipient.recipient_id,'wave3.'||cls,'Wave 3 '||initcap(cls),
    'A subscribed business event is ready for review.',
    case when cfg is null then null else v_kind end,
    case when cfg is null then null else new.aggregate_id end,
    new.legal_entity_id,new.branch_id,new.actor_id,new.request_id,new.command_id,
    new.correlation_id,jsonb_build_object('event_class',cls),new.actor_id,new.actor_id)
   on conflict do nothing;
  end loop;
 end loop;
 return new;
end $$;
revoke all on function core.wave3_notify_command() from public,anon,authenticated;
create trigger wave3_notify_command after insert on core.command_receipts
 for each row execute function core.wave3_notify_command();

create index wave3_due_notification_scan on finance.open_items
 (tenant_id,legal_entity_id,branch_id,kind,id) include(due_date,posting_date,source_type,source_id)
 where original_amount>0;
create unique index wave3_due_notification_identity on workflow.notifications
 (tenant_id,recipient_id,notification_type,(source_context->>'due_key'))
 where notification_type='wave3.due' and source_context ? 'due_key';

create function api.scan_wave3_due_notifications(
 p_tenant_id uuid,p_legal_entity_id uuid,p_branch_id uuid,p_command_id uuid,
 p_idempotency_key uuid,p_client_timestamp timestamptz,p_payload jsonb,
 p_expected_entity_version bigint default null) returns jsonb
language plpgsql security definer set search_path='' as $$
declare v_kind text:=p_payload->>'kind';v_cutoff date:=(p_payload->>'as_of')::date;
 v_after uuid:=(p_payload->>'after_id')::uuid;v_last uuid;v_count int:=0;v_emitted int:=0;
 v_more boolean:=false;v_row finance.open_items%rowtype;v_cfg jsonb;v_recipient record;
 v_residual numeric;v_hash text;v_replay jsonb;v_result jsonb;v_inserted int;
 v_request uuid:=gen_random_uuid();v_due_key text;
begin
 perform core.wave3_require_scope(p_tenant_id,'core.roles.manage',p_legal_entity_id,p_branch_id);
 if jsonb_typeof(p_payload) is distinct from 'object' or v_kind is null or v_kind not in('AR','AP')
  or v_cutoff is null or (p_payload->>'as_of') !~ '^\d{4}-\d{2}-\d{2}$'
  or v_cutoff>(clock_timestamp() at time zone 'UTC')::date
  or p_expected_entity_version is not null
  or exists(select 1 from jsonb_object_keys(p_payload) x where x not in('kind','as_of','after_id')) then
  raise exception using errcode='22023',message='NOTIFICATION_DUE_SCAN_INVALID';end if;
 perform core.wave3_require_scope(p_tenant_id,case v_kind when 'AR' then 'finance.receipts.view'
  else 'finance.payments.manage' end,p_legal_entity_id,p_branch_id);
 v_hash:=core.wave3_request_hash('workflow.wave3.due.scan',p_command_id,p_tenant_id,
  p_legal_entity_id,p_branch_id,p_payload,p_expected_entity_version);
 v_replay:=core.wave3_replay(p_tenant_id,'workflow.wave3.due.scan',p_command_id,p_idempotency_key,v_hash);
 if v_replay is not null then return v_replay;end if;
 perform pg_advisory_xact_lock(hashtextextended(p_tenant_id::text||':'||p_legal_entity_id::text||':'||
  p_branch_id::text||':wave3-due:'||v_kind||':'||v_cutoff::text,0));
 for v_row in select o.* from finance.open_items o where o.tenant_id=p_tenant_id
  and o.legal_entity_id=p_legal_entity_id and o.branch_id=p_branch_id and o.kind=v_kind
  and o.original_amount>0 and o.posting_date<=v_cutoff and o.due_date<=v_cutoff
  and (v_after is null or o.id>v_after) order by o.id limit 101
 loop
  if v_count=100 then v_more:=true;exit;end if;
  v_count:=v_count+1;v_last:=v_row.id;
  v_residual:=(finance.flow_residual(p_tenant_id,v_row.id,v_cutoff)->>'amount')::numeric;
  if v_residual<=0 then continue;end if;
  v_cfg:=core.wave3_source_descriptor(v_row.source_type);
  if v_cfg is null then raise exception using errcode='55000',message='NOTIFICATION_DUE_SOURCE_UNSUPPORTED';end if;
  perform core.wave3_source_header(p_tenant_id,p_legal_entity_id,p_branch_id,v_row.source_type,v_row.source_id);
  v_due_key:=v_row.id::text||':'||v_cutoff::text;
  for v_recipient in select distinct s.recipient_id from core.wave3_notification_subscriptions s
   join core.memberships m on m.tenant_id=s.tenant_id and m.user_id=s.recipient_id and m.status='active'
   where s.tenant_id=p_tenant_id and s.event_class='due' and s.enabled
    and (s.legal_entity_id is null or s.legal_entity_id=p_legal_entity_id)
    and (s.branch_id is null or s.branch_id=p_branch_id)
    and exists(select 1 from core.role_assignments ra join core.role_permissions rp
     on rp.tenant_id=ra.tenant_id and rp.role_id=ra.role_id
     where ra.tenant_id=p_tenant_id and ra.membership_id=m.id
      and rp.permission_code=v_cfg->>'permission'
      and (ra.legal_entity_id is null or ra.legal_entity_id=p_legal_entity_id)
      and (ra.branch_id is null or ra.branch_id=p_branch_id))
  loop
   insert into workflow.notifications(tenant_id,recipient_id,notification_type,title,body,
    aggregate_type,aggregate_id,legal_entity_id,branch_id,actor_id,request_id,command_id,
    correlation_id,source_context,created_by,updated_by)
   values(p_tenant_id,v_recipient.recipient_id,'wave3.due','Wave 3 due item',
    'A subscribed business item is due for review.',v_row.source_type,v_row.source_id,
    p_legal_entity_id,p_branch_id,auth.uid(),v_request,p_command_id,v_request,
    jsonb_build_object('event_class','due','as_of',v_cutoff,'due_key',v_due_key),auth.uid(),auth.uid())
   on conflict do nothing;
   get diagnostics v_inserted=row_count;v_emitted:=v_emitted+v_inserted;
  end loop;
 end loop;
 v_result:=jsonb_build_object('tenant_id',p_tenant_id,'legal_entity_id',p_legal_entity_id,'branch_id',p_branch_id,
  'id',p_command_id,'kind',v_kind,'as_of',v_cutoff,
  'examined',v_count,'emitted',v_emitted,'has_more',v_more,
  'next_after',case when v_more then v_last else null end);
 return core.wave3_finish_command(p_tenant_id,'workflow.wave3.due.scan',p_command_id,
  'wave3_due_scan',p_command_id,p_idempotency_key,v_hash,null,v_result,p_legal_entity_id,p_branch_id,
  '{}',jsonb_build_object('to_status','scanned'),'[]','[]',v_request,v_request);
end $$;
revoke all on function api.scan_wave3_due_notifications(uuid,uuid,uuid,uuid,uuid,timestamptz,jsonb,bigint)
 from public,anon,authenticated;
grant execute on function api.scan_wave3_due_notifications(uuid,uuid,uuid,uuid,uuid,timestamptz,jsonb,bigint)
 to authenticated;
create function api.wave3_notification_admin_page(p_tenant_id uuid,p_legal_entity_id uuid,p_branch_id uuid,
 p_resource text,p_after uuid default null) returns jsonb
language plpgsql stable security definer set search_path='' as $$declare rows jsonb;cursor uuid;begin
 perform core.wave3_require_scope(p_tenant_id,'core.roles.manage',p_legal_entity_id,p_branch_id);
 if p_legal_entity_id is null or p_branch_id is null or p_resource is null or p_resource not in('members','subscriptions') then
  raise exception using errcode='22023',message='NOTIFICATION_ADMIN_PAGE_INVALID';end if;
 if p_resource='members' then
  select coalesce(jsonb_agg(x.row order by x.id),'[]') into rows from(
   select m.user_id id,jsonb_build_object('id',m.user_id,'status',m.status) row
   from core.memberships m where m.tenant_id=p_tenant_id and m.status='active'
    and (p_after is null or m.user_id>p_after) order by m.user_id limit 51)x;
 else
  select coalesce(jsonb_agg(x.row order by x.id),'[]') into rows from(
   select s.id,jsonb_build_object('id',s.id,'recipient_id',s.recipient_id,'event_class',s.event_class,
    'enabled',s.enabled,'version',s.version,'recipient_status',m.status) row
   from core.wave3_notification_subscriptions s join core.memberships m on m.tenant_id=s.tenant_id and m.user_id=s.recipient_id
   where s.tenant_id=p_tenant_id and s.legal_entity_id=p_legal_entity_id and s.branch_id=p_branch_id
    and (p_after is null or s.id>p_after) order by s.id limit 51)x;
 end if;
 if jsonb_array_length(rows)>50 then cursor:=(rows->49->>'id')::uuid;rows:=rows-50;end if;
 return jsonb_build_object('tenant_id',p_tenant_id,'legal_entity_id',p_legal_entity_id,'branch_id',p_branch_id,
  'resource',p_resource,'items',rows,'next_cursor',cursor);
end $$;
revoke all on function api.wave3_notification_admin_page(uuid,uuid,uuid,text,uuid) from public,anon,authenticated;
grant execute on function api.wave3_notification_admin_page(uuid,uuid,uuid,text,uuid) to authenticated;
notify pgrst,'reload schema';
