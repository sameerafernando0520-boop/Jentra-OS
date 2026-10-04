-- Unapplied W4 linked-source candidate. Requires project finance and payroll
-- corrections. No API, plan, role, or entitlement grants are introduced.
create table projects.payroll_time_impacts(
 id uuid primary key default gen_random_uuid(),tenant_id uuid not null,legal_entity_id uuid not null,
 branch_id uuid not null,project_id uuid not null,entry_id uuid not null,correction_id uuid not null,
 original_revision_id uuid not null,replacement_revision_id uuid not null,mode text not null,
 body jsonb not null,actor_id uuid not null references auth.users(id),recorded_at timestamptz not null default clock_timestamp(),
 check(mode in('apply','reverse')),unique(correction_id,entry_id,mode),
 foreign key(tenant_id,legal_entity_id,project_id,entry_id,original_revision_id)
  references projects.time_revisions(tenant_id,legal_entity_id,project_id,entry_id,id),
 foreign key(tenant_id,legal_entity_id,project_id,entry_id,replacement_revision_id)
  references projects.time_revisions(tenant_id,legal_entity_id,project_id,entry_id,id),
 foreign key(tenant_id,legal_entity_id,correction_id) references people_payroll.corrections(tenant_id,legal_entity_id,id)
);
create index project_payroll_impact_scope_idx on projects.payroll_time_impacts(tenant_id,legal_entity_id,branch_id,project_id,id);
create index project_payroll_impact_original_idx on projects.payroll_time_impacts(original_revision_id);
create index project_payroll_impact_replacement_idx on projects.payroll_time_impacts(replacement_revision_id);
alter table projects.payroll_time_impacts enable row level security;
alter table projects.payroll_time_impacts force row level security;
revoke all on projects.payroll_time_impacts from public,anon,authenticated,service_role;
create trigger immutable before update or delete on projects.payroll_time_impacts
 for each row execute function projects.immutable();

create function projects.payroll_impact_guard(t uuid,e uuid,b uuid,employee uuid,claim uuid,correction uuid)
returns void language plpgsql security definer set search_path='' as $$begin
 if not exists(select 1 from people_payroll.corrections c join people_payroll.correction_sources s on s.correction_id=c.id
  where c.id=correction and c.tenant_id=t and c.legal_entity_id=e and c.branch_id=b and c.employee_id=employee
   and c.status in('approved','posted') and s.impact is not null
   and (people_payroll.correction_source_state(s.seal_id)->>'claim_id')::uuid=claim) then
  raise exception using errcode='42501',message='PAYROLL_APPROVED_LINKED_IMPACT_REQUIRED';end if;
end $$;

-- One operational revision owns all its break-separated allocations. Repeated
-- allocation callbacks append that revision once and return its frozen result.
create function projects.payroll_revision_impact(t uuid,e uuid,b uuid,employee uuid,entry_id uuid,claim uuid,
 revision_id uuid,proposal jsonb,p_mode text,direct_claim boolean) returns jsonb
language plpgsql security definer set search_path='' as $$
declare entry projects.time_entries%rowtype;r projects.time_revisions%rowtype;pr projects.register%rowtype;
 slot projects.resource_slots%rowtype;cal people.work_calendar_versions%rowtype;
 correction uuid:=(proposal->>'correction_id')::uuid;actual_mode text;
 before_body jsonb;after_body jsonb;target jsonb;change jsonb;billing jsonb;body jsonb;prior jsonb;
 allocation_ids jsonb;breaks jsonb;break_row jsonb;attendance jsonb:=proposal->'attendance_after';
 current_credit jsonb;credit_ids jsonb;
 start_local timestamp;end_local timestamp;start_utc timestamptz;end_utc timestamptz;
 cursor_utc timestamptz;break_start timestamptz;break_end timestamptz;break_seconds bigint;seconds bigint;
 bill_amount numeric;cost_amount numeric;cost_rate numeric;new_claim uuid;link uuid;allocation uuid;unit uuid;
 digest text;remove_source boolean:=false;original_revision uuid;original_effect projects.payroll_time_impacts%rowtype;
begin
 if p_mode not in('read','validate','release','apply','reverse') or proposal is null or jsonb_typeof(proposal)<>'object' then
  raise exception using errcode='22023',message='PROJECT_PAYROLL_IMPACT_INVALID';end if;
 actual_mode:=case when p_mode='reverse' or proposal->>'operational_mode'='reverse' then 'reverse' else 'apply' end;
 perform pg_advisory_xact_lock(hashtextextended('people.payroll:'||t||':'||e,0));
 perform pg_advisory_xact_lock(hashtextextended('projects:'||t||':'||e,0));
 perform pg_advisory_xact_lock(hashtextextended('service:'||t||':'||e,0));
 perform 1 from people.employees where tenant_id=t and legal_entity_id=e and id=employee for update;
 select * into entry from projects.time_entries x where x.tenant_id=t and x.legal_entity_id=e and x.branch_id=b
  and x.employee_id=employee and x.id=entry_id for update;
 if entry.id is null then raise exception using errcode='P0002',message='PROJECT_TIME_NOT_FOUND';end if;
 select * into pr from projects.register where id=entry.project_id for update;
 select * into r from projects.time_revisions where id=entry.current_revision_id;
 select * into slot from projects.resource_slots where id=r.resource_slot_id;
 select * into cal from people.work_calendar_versions where id=slot.calendar_version_id;
 perform core.wave3_require_scope(t,'projects.cost.view',e,b);
 if p_mode<>'read' then perform core.wave3_require_scope(t,'projects.time.approve',e,b);end if;
 select x.body into prior from projects.payroll_time_impacts x where x.correction_id=correction and x.entry_id=entry.id and x.mode=actual_mode;
 if prior is not null and p_mode in('apply','reverse') then
  if entry.current_revision_id is distinct from(prior->>'source_id')::uuid
   or entry.version is distinct from(prior->>'source_version')::bigint
   or claim is distinct from(prior->>'claim_id')::uuid then raise exception using errcode='40001',message='PAYROLL_CORRECTION_SOURCE_CHANGED';end if;
  return prior;
 end if;
 if entry.status<>'approved' and not(actual_mode='reverse' and entry.status='cancelled') then
  raise exception using errcode='55000',message='PROJECT_TIME_LINKED_IMPACT_REQUIRED';end if;
 select coalesce(jsonb_agg(a.allocation_id order by a.allocation_id),'[]') into allocation_ids
  from projects.time_allocations a where a.revision_id=r.id;
 select c.hourly_rate into cost_rate from projects.time_costs c where c.revision_id=r.id;
 if cost_rate is null then select c.hourly_rate into cost_rate from projects.resource_costs c where c.resource_slot_id=slot.id;end if;
 if cost_rate is null then raise exception using errcode='55000',message='PROJECT_COST_BASIS_REQUIRED';end if;
 before_body:=jsonb_build_object('revision',to_jsonb(r),'entry_id',entry.id,'entry_version',entry.version,'status',entry.status,
  'claim_id',claim,'allocation_ids',allocation_ids,'project_id',pr.id,'project_code',pr.code,'project_name',pr.name,
  'employee_id',employee,'employee_name',(select display_name from people.employees where id=employee),
  'calendar_version_id',cal.id,'timezone',cal.timezone,'cost_rate',cost_rate::text);
 if p_mode='read' then return jsonb_build_object('before',before_body,'source_id',r.id,'source_version',entry.version,
  'paid_seconds',r.payable_seconds,'claim_id',claim,'entry_id',entry.id,'project_id',pr.id,'project_code',pr.code,'project_name',pr.name);end if;
 if actual_mode='reverse' then
  select * into original_effect from projects.payroll_time_impacts x where x.tenant_id=t and x.legal_entity_id=e
   and x.branch_id=b and x.entry_id=entry.id and x.correction_id=correction and x.mode='apply';
  if original_effect.id is null or original_effect.replacement_revision_id is distinct from r.id
   or entry.version is distinct from(original_effect.body->>'source_version')::bigint
   or claim is distinct from(original_effect.body->>'claim_id')::uuid then
   raise exception using errcode='40001',message='PAYROLL_CORRECTION_SOURCE_CHANGED';end if;
  if direct_claim and(proposal->'before' is distinct from original_effect.body->'before'
    or proposal->'after' is distinct from original_effect.body->'after')
   or not direct_claim and(proposal->'allocation_impact'->'before' is distinct from original_effect.body->'before'
    or proposal->'allocation_impact'->'after' is distinct from original_effect.body->'after') then
   raise exception using errcode='40001',message='PAYROLL_CORRECTION_SOURCE_CHANGED';end if;
 end if;
 if direct_claim then
  if not exists(select 1 from people.work_claims w where w.id=claim and w.tenant_id=t and w.legal_entity_id=e
   and w.branch_id=b and w.employee_id=employee and w.source_kind='project' and w.source_id=r.id and w.active)
   or r.attendance_claim_id is not null then raise exception using errcode='40001',message='PAYROLL_CORRECTION_SOURCE_CHANGED';end if;
  if actual_mode<>'reverse' and entry.version is distinct from(proposal->>'expected_source_version')::bigint then
   raise exception using errcode='40001',message='PAYROLL_CORRECTION_SOURCE_CHANGED';end if;
  target:=case actual_mode when 'reverse' then proposal->'before'->'revision' else proposal end;
 else
  if jsonb_typeof(coalesce(proposal->'allocation_changes','[]')) is distinct from 'array'
   or jsonb_array_length(coalesce(proposal->'allocation_changes','[]'))>50 then
   raise exception using errcode='22023',message='PROJECT_ALLOCATION_CHANGE_INVALID';end if;
  if(select count(*) from jsonb_array_elements(coalesce(proposal->'allocation_changes','[]')) x where (x->>'entry_id')::uuid=entry.id)>1 then
   raise exception using errcode='22023',message='PROJECT_ALLOCATION_CHANGE_INVALID';end if;
  select value into change from jsonb_array_elements(coalesce(proposal->'allocation_changes','[]')) where (value->>'entry_id')::uuid=entry.id;
  if change is not null and change->>'mode' not in('retain','geometry','remove') then raise exception using errcode='22023',message='PROJECT_ALLOCATION_CHANGE_INVALID';end if;
  target:=case when actual_mode='reverse' then proposal->'allocation_impact'->'before'->'revision'
   when change->>'mode'='geometry' then change else to_jsonb(r) end;
  remove_source:=actual_mode<>'reverse' and coalesce(change->>'mode'='remove',false);
  revision_id:=md5(revision_id::text||':'||entry.id::text)::uuid;
 end if;
 if target is null then raise exception using errcode='22023',message='PROJECT_PAYROLL_IMPACT_INVALID';end if;
 if p_mode in('release','apply','reverse') then perform projects.payroll_impact_guard(t,e,b,employee,claim,correction);end if;
 start_local:=(target->>'start_local')::timestamp;end_local:=(target->>'end_local')::timestamp;
 if start_local is null or end_local is null or extract(second from start_local)%1<>0 or extract(second from end_local)%1<>0 then
  raise exception using errcode='22023',message='WORK_LOCAL_BOUNDARY_INVALID';end if;
 start_utc:=people.resolve_local_instant(cal.timezone,start_local,(target->>'start_offset_seconds')::integer);
 end_utc:=people.resolve_local_instant(cal.timezone,end_local,(target->>'end_offset_seconds')::integer);
 if not(tstzrange(slot.start_utc,slot.end_utc,'[)') @> tstzrange(start_utc,end_utc,'[)')) then
  raise exception using errcode='55000',message='PROJECT_TIME_OUTSIDE_RESOURCE';end if;
 perform people.work_local_coverage(t,e,b,employee,cal.id,start_local,end_local);
 breaks:=coalesce(target->'breaks','[]');break_seconds:=people.work_break_seconds(start_utc,end_utc,breaks);
 seconds:=extract(epoch from end_utc-start_utc)::bigint-break_seconds;
 if seconds not between 1 and 129600 then raise exception using errcode='22023',message='WORK_DURATION_INVALID';end if;
 -- Every new allocation segment must remain inside one payable attendance
 -- segment. An invalid interval needs an explicit removal/revision decision.
 if not direct_claim and not remove_source then
  if attendance is null or (attendance->>'calendar_version_id')::uuid<>cal.id then
   raise exception using errcode='55000',message='PROJECT_ATTENDANCE_SOURCE_INVALID';end if;
  cursor_utc:=start_utc;
  for break_row in select value from jsonb_array_elements(breaks||jsonb_build_array(jsonb_build_object('start_utc',end_utc,'end_utc',end_utc))) loop
   break_start:=(break_row->>'start_utc')::timestamptz;break_end:=(break_row->>'end_utc')::timestamptz;
   if break_start>cursor_utc and (cursor_utc<(attendance->>'start_utc')::timestamptz or break_start>(attendance->>'end_utc')::timestamptz
    or exists(select 1 from jsonb_array_elements(attendance->'breaks') z where
     tstzrange((z->>'start_utc')::timestamptz,(z->>'end_utc')::timestamptz,'[)') && tstzrange(cursor_utc,break_start,'[)'))) then
    raise exception using errcode='55000',message='PROJECT_ALLOCATION_GEOMETRY_IMPACT_REQUIRED';end if;
   cursor_utc:=break_end;
  end loop;
 end if;
 bill_amount:=case when remove_source then 0 else projects.ratio(slot.bill_rate*1000000*seconds,3600,pr.precision) end;
 cost_amount:=case when remove_source then 0 else projects.ratio(cost_rate*1000000*seconds,3600,pr.precision) end;
 if actual_mode='reverse' then
  if direct_claim then
   current_credit:=case when proposal->>'current_source_revision_id' is not null then jsonb_build_object(
    'source_revision_id',proposal->'current_source_revision_id','expected_source_version',proposal->'current_source_version',
    'billing_credit_line_ids',proposal->'current_billing_credit_line_ids') end;
  else
   select value into current_credit from jsonb_array_elements(coalesce(proposal->'current_allocation_credits','[]'))
    where (value->>'entry_id')::uuid=entry.id;
  end if;
  if current_credit is not null and ((current_credit->>'source_revision_id')::uuid is distinct from r.id
   or (current_credit->>'expected_source_version')::bigint is distinct from entry.version) then
   raise exception using errcode='40001',message='PAYROLL_CORRECTION_SOURCE_CHANGED';end if;
  credit_ids:=coalesce(current_credit->'billing_credit_line_ids',proposal->'current_billing_credit_line_ids','[]');
 else credit_ids:=coalesce(change->'billing_credit_line_ids',proposal->'billing_credit_line_ids','[]');end if;
 billing:=projects.payroll_billing_impact(t,e,b,pr.id,r.id,
  (proposal-'operational_mode')||jsonb_build_object('billing_credit_line_ids',credit_ids),'validate');
 after_body:=jsonb_build_object('start_local',start_local,'end_local',end_local,'start_offset_seconds',(target->>'start_offset_seconds')::integer,
  'end_offset_seconds',(target->>'end_offset_seconds')::integer,'start_utc',start_utc,'end_utc',end_utc,'breaks',breaks,
  'payable_seconds',seconds,'calendar_version_id',cal.id,'bill_amount',bill_amount::text,'cost_amount',cost_amount::text,
  'status',case when remove_source then 'cancelled' else 'approved' end,'billing',billing);
 if p_mode='apply' and direct_claim and (proposal->'before' is distinct from before_body or proposal->'after' is distinct from after_body) then
  raise exception using errcode='40001',message='PAYROLL_CORRECTION_SOURCE_CHANGED';end if;
 if p_mode in('release','apply','reverse') and not direct_claim and actual_mode<>'reverse' and
  (proposal->'allocation_impact'->'before' is distinct from before_body
   or proposal->'allocation_impact'->'after' is distinct from after_body) then
  raise exception using errcode='40001',message='PAYROLL_CORRECTION_SOURCE_CHANGED';end if;
 body:=jsonb_build_object('before',before_body,'after',after_body,'source_id',revision_id,'source_version',entry.version+1,
  'paid_seconds',case when remove_source then 0 else seconds end,'claim_id',claim,'entry_id',entry.id,'project_id',pr.id,
  'project_code',pr.code,'project_name',pr.name);
 if p_mode='validate' then return body;end if;
 if p_mode='release' then
  for allocation in select a.allocation_id from projects.time_allocations a join people.work_allocations w on w.id=a.allocation_id
   where a.revision_id=r.id and w.active order by a.allocation_id loop perform people.revoke_work_allocation(t,e,employee,allocation);end loop;
  return body;
 end if;
 -- Claim and history changes are in the same outer payroll posting transaction.
 if direct_claim then
  for allocation in select a.allocation_id from projects.time_allocations a join people.work_allocations w on w.id=a.allocation_id
   where a.revision_id=r.id and w.active order by a.allocation_id loop perform people.revoke_work_allocation(t,e,employee,allocation);end loop;
  new_claim:=people_payroll.replace_claim(t,e,b,employee,claim,'project',revision_id,cal.id,start_utc,end_utc,breaks,correction);
 else new_claim:=(proposal->>'new_claim_id')::uuid;
  if new_claim is null or not exists(select 1 from people.work_claims w where w.id=new_claim and w.tenant_id=t
   and w.legal_entity_id=e and w.branch_id=b and w.employee_id=employee and w.active and w.source_kind='attendance'
   and w.calendar_version_id=cal.id and w.start_utc=(attendance->>'start_utc')::timestamptz
   and w.end_utc=(attendance->>'end_utc')::timestamptz
   and w.break_seconds=people.work_break_seconds(w.start_utc,w.end_utc,attendance->'breaks')) then
   raise exception using errcode='55000',message='PROJECT_ATTENDANCE_SOURCE_INVALID';end if;
 end if;
 perform projects.payroll_billing_impact(t,e,b,pr.id,r.id,
  (proposal-'operational_mode')||jsonb_build_object('billing_credit_line_ids',credit_ids),'apply');
 digest:=encode(extensions.digest((after_body||jsonb_build_object('correction_id',correction,'revision_id',revision_id,'supersedes_id',r.id))::text,'sha256'),'hex');
 insert into projects.time_revisions(id,tenant_id,legal_entity_id,project_id,entry_id,version,plan_id,task_id,resource_slot_id,
  start_local,end_local,start_offset_seconds,end_offset_seconds,start_utc,end_utc,breaks,payable_seconds,attendance_claim_id,bill_amount,digest,reason,supersedes_id,recorded_by)
 values(revision_id,t,e,pr.id,entry.id,entry.version+1,r.plan_id,r.task_id,r.resource_slot_id,start_local,end_local,
  (target->>'start_offset_seconds')::integer,(target->>'end_offset_seconds')::integer,start_utc,end_utc,breaks,seconds,
  case when direct_claim then null else new_claim end,bill_amount,digest,'Linked sealed payroll source correction',r.id,auth.uid());
 insert into projects.time_costs values(t,e,pr.id,entry.id,revision_id,cost_rate,cost_amount);
 if not remove_source then
  cursor_utc:=start_utc;
  for break_row in select value from jsonb_array_elements(breaks||jsonb_build_array(jsonb_build_object('start_utc',end_utc,'end_utc',end_utc))) loop
   break_start:=(break_row->>'start_utc')::timestamptz;break_end:=(break_row->>'end_utc')::timestamptz;
   if break_start>cursor_utc then link:=gen_random_uuid();
    allocation:=people.allocate_work(t,e,b,employee,new_claim,'project',link,cursor_utc,break_start,auth.uid());
    insert into projects.time_allocations values(link,t,e,pr.id,entry.id,revision_id,allocation,new_claim,direct_claim);
   end if;cursor_utc:=break_end;
  end loop;
  unit:=gen_random_uuid();insert into projects.billable_units(id,tenant_id,legal_entity_id,project_id,branch_id,source_kind,source_id,
   source_version,source_digest,amount,payable_seconds) values(unit,t,e,pr.id,b,'time',revision_id,entry.version+1,digest,bill_amount,seconds);
 end if;
 perform people.consume_organization(t,e,b,employee,'project_time',revision_id,start_local::date,(end_local-interval '1 microsecond')::date+1);
 update projects.time_entries set current_revision_id=revision_id,version=version+1,status=case when remove_source then 'cancelled' else 'approved' end where id=entry.id;
 insert into projects.time_events(tenant_id,legal_entity_id,project_id,entry_id,revision_id,action,version,reason,actor_id,command_id)
 values(t,e,pr.id,entry.id,r.id,'time_cancel',entry.version+1,'Superseded by linked payroll correction',auth.uid(),gen_random_uuid());
 if not remove_source then insert into projects.time_events(tenant_id,legal_entity_id,project_id,entry_id,revision_id,action,version,reason,actor_id,command_id)
  values(t,e,pr.id,entry.id,revision_id,'time_approve',entry.version+1,'Independently approved linked payroll correction',auth.uid(),gen_random_uuid());end if;
 body:=body||jsonb_build_object('claim_id',new_claim,'replacement_unit_id',unit);
 if pr.status='closed' and not remove_source then
  update projects.register set status='open',version=version+1 where id=pr.id;
  body:=body||jsonb_build_object('project_reopened_for_financial_review',true);
 end if;
 insert into projects.payroll_time_impacts(tenant_id,legal_entity_id,branch_id,project_id,entry_id,correction_id,original_revision_id,replacement_revision_id,mode,body,actor_id)
 values(t,e,b,pr.id,entry.id,correction,r.id,revision_id,actual_mode,body,auth.uid());
 return body;
end $$;

create function projects.payroll_impact(t uuid,e uuid,b uuid,employee uuid,claim uuid,revision uuid,proposal jsonb,p_mode text)
returns jsonb language plpgsql security definer set search_path='' as $$declare entry uuid;begin
 select x.id into entry from projects.time_entries x join projects.time_revisions r on r.id=x.current_revision_id
  join people.work_claims w on w.source_id=r.id where w.id=claim and w.source_kind='project' and w.active
   and x.tenant_id=t and x.legal_entity_id=e and x.branch_id=b and x.employee_id=employee;
 if entry is null then raise exception using errcode='40001',message='PAYROLL_CORRECTION_SOURCE_CHANGED';end if;
 return projects.payroll_revision_impact(t,e,b,employee,entry,claim,revision,proposal,p_mode,true);
end $$;
create function projects.payroll_allocation_impact(t uuid,e uuid,b uuid,employee uuid,allocation_id uuid,revision uuid,proposal jsonb,p_mode text)
returns jsonb language plpgsql security definer set search_path='' as $$declare a people.work_allocations%rowtype;entry uuid;body jsonb;begin
 select * into a from people.work_allocations w where w.id=allocation_id and w.tenant_id=t and w.legal_entity_id=e
  and w.branch_id=b and w.employee_id=employee and w.source_kind='project';
 select x.entry_id into entry from projects.time_allocations x where x.allocation_id=a.id and not x.direct_claim;
 if entry is null then raise exception using errcode='55000',message='PROJECT_ATTENDANCE_SOURCE_INVALID';end if;
 body:=projects.payroll_revision_impact(t,e,b,employee,entry,
  coalesce((proposal->>'current_claim_id')::uuid,a.claim_id),revision,proposal,p_mode,false);
 return body||jsonb_build_object('allocation_id',a.id);
end $$;
revoke all on function projects.payroll_impact_guard(uuid,uuid,uuid,uuid,uuid,uuid),
 projects.payroll_revision_impact(uuid,uuid,uuid,uuid,uuid,uuid,uuid,jsonb,text,boolean),
 projects.payroll_impact(uuid,uuid,uuid,uuid,uuid,uuid,jsonb,text),
 projects.payroll_allocation_impact(uuid,uuid,uuid,uuid,uuid,uuid,jsonb,text)
 from public,anon,authenticated,service_role;
