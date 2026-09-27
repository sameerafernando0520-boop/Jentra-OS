-- Included only inside a caller-owned BEGIN ... ROLLBACK. Never an owner bootstrap.
create function pg_temp.wid(p text) returns uuid language sql immutable as
  $$select md5('wave4-integrated-rollback-20260926:'||p)::uuid$$;
create function pg_temp.wdate() returns date language sql stable as
  $$select (now() at time zone 'Asia/Colombo')::date$$;
create function pg_temp.wactor(p text,p_aal text default 'aal2') returns void language plpgsql as $$begin
  perform set_config('request.jwt.claims',jsonb_build_object('sub',pg_temp.wid(p),'role','authenticated','aal',p_aal)::text,true);
  perform set_config('request.jwt.claim.sub',pg_temp.wid(p)::text,true);
end $$;
insert into auth.users(id,instance_id,aud,role,email,encrypted_password,email_confirmed_at,created_at,updated_at)
select pg_temp.wid(x),'00000000-0000-0000-0000-000000000000','authenticated','authenticated',
  x||'@wave4.rollback.jentra.test','',now(),now(),now()
from unnest(array['creator','reviewer','reader','branch-manager','outsider']) x;
insert into core.tenants(id,name,slug,created_by) values
  (pg_temp.wid('tenant'),'Wave 4 Rollback','w4-integrated-rollback',pg_temp.wid('creator')),
  (pg_temp.wid('other-tenant'),'Other Rollback','w4-other-integrated-rollback',pg_temp.wid('outsider'));
insert into core.legal_entities(id,tenant_id,name,code,currency_code,timezone,rounding_scale,created_by) values
  (pg_temp.wid('entity'),pg_temp.wid('tenant'),'Synthetic Operations','W4OPS','LKR','Asia/Colombo',2,pg_temp.wid('creator')),
  (pg_temp.wid('entity2'),pg_temp.wid('tenant'),'Other Operations','W4OTHER','LKR','Asia/Colombo',2,pg_temp.wid('creator'));
insert into core.branches(id,tenant_id,legal_entity_id,name,code,created_by) values
  (pg_temp.wid('branch'),pg_temp.wid('tenant'),pg_temp.wid('entity'),'Head Office','HQ',pg_temp.wid('creator')),
  (pg_temp.wid('branch2'),pg_temp.wid('tenant'),pg_temp.wid('entity'),'Second Branch','B2',pg_temp.wid('creator')),
  (pg_temp.wid('entity2-branch'),pg_temp.wid('tenant'),pg_temp.wid('entity2'),'Other HQ','HQ',pg_temp.wid('creator'));
insert into billing.plans(code,name) values('w4_integrated_rollback','Wave 4 rollback');
insert into billing.plan_entitlements(plan_code,entitlement_code,enabled) values('w4_integrated_rollback','module.people',true);
insert into billing.tenant_subscriptions(tenant_id,plan_code,status,seats,trial_ends_at)
values(pg_temp.wid('tenant'),'w4_integrated_rollback','trialing',10,now()+interval '30 days');
insert into core.memberships(id,tenant_id,user_id,status)
select pg_temp.wid(x||'.membership'),pg_temp.wid('tenant'),pg_temp.wid(x),'active'
from unnest(array['creator','reviewer','reader','branch-manager']) x;
insert into core.roles(id,tenant_id,code,name,requires_mfa)
select pg_temp.wid(x||'.role'),pg_temp.wid('tenant'),x,x,true
from unnest(array['creator','reviewer','reader','branch-manager']) x;
insert into core.role_permissions(tenant_id,role_id,permission_code)
select pg_temp.wid('tenant'),pg_temp.wid(x||'.role'),p.code
from unnest(array['creator','reviewer','branch-manager']) x cross join core.permissions p
where p.module='people';
insert into core.role_permissions(tenant_id,role_id,permission_code)
select pg_temp.wid('tenant'),pg_temp.wid('reader.role'),p.code
from unnest(array['people.view','people.employees.view','people.employees.history.view',
  'people.calendars.view','people.organization.view']) p(code)
join core.permissions c on c.code=p.code;
insert into core.role_assignments(tenant_id,membership_id,role_id,legal_entity_id,branch_id,created_by)
select pg_temp.wid('tenant'),pg_temp.wid(x||'.membership'),pg_temp.wid(x||'.role'),pg_temp.wid('entity'),
  case when x in ('creator','reviewer') then null else pg_temp.wid('branch') end,pg_temp.wid('creator')
from unnest(array['creator','reviewer','reader','branch-manager']) x;
create function pg_temp.wemployee(p text) returns jsonb language sql as $$
  select api.people_employee_command(pg_temp.wid('tenant'),pg_temp.wid('entity'),pg_temp.wid('branch'),
    pg_temp.wid(p||'.create'),pg_temp.wid(p||'.create'),now(),jsonb_build_object('action','create',
      'id',pg_temp.wid(p),'code',upper(p),'display_name','Synthetic '||p,'work_email',null,
      'start_date',pg_temp.wdate()-10,'job_title','Synthetic role','employment_type','permanent'),0)
$$;
select pg_temp.wactor('creator');
select pg_temp.wemployee('employee');
select pg_temp.wemployee('manager');
select pg_temp.wemployee('third');
insert into people.work_calendars(id,tenant_id,legal_entity_id,code,name,created_by,updated_by)
values(pg_temp.wid('calendar'),pg_temp.wid('tenant'),pg_temp.wid('entity'),'W4CAL','Synthetic Calendar',pg_temp.wid('creator'),pg_temp.wid('creator'));
insert into people.work_calendar_versions(id,tenant_id,legal_entity_id,calendar_id,start_date,end_date_exclusive,
  timezone,weekly_intervals,date_overrides,published_by)
values(pg_temp.wid('calendar-version'),pg_temp.wid('tenant'),pg_temp.wid('entity'),pg_temp.wid('calendar'),
  pg_temp.wdate()-10,pg_temp.wdate()+400,'Asia/Colombo',
  '[{"day_of_week":1,"start_minute":540,"end_minute":1020,"end_day_offset":0}]','[]',pg_temp.wid('creator'));
