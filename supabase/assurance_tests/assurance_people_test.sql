-- Corporate Audit & Assurance A14 people-picker candidate tests. Included by
-- build_assurance_candidate.ps1 -Slice A14 after the A12 tests and the A14
-- DDL. Reuses the A1 actors, tenant and roles.
create function pg_temp.people(p_branch text default 'tenant.branch') returns jsonb language sql as $$
  select api.assurance_people(pg_temp.aid('tenant'),pg_temp.aid('tenant.entity'),pg_temp.aid(p_branch)) $$;

select ok(has_function_privilege('authenticated','api.assurance_people(uuid,uuid,uuid)','EXECUTE')
  and not has_function_privilege('anon','api.assurance_people(uuid,uuid,uuid)','EXECUTE'),
  'A14: people are read by authenticated sessions only');

select pg_temp.actor('manager');set local role authenticated;
insert into assurance_samples values('a14.people',pg_temp.people());
reset role;select pg_temp.actor('owner');set local role authenticated;
select throws_ok($$select pg_temp.people()$$,'42501',null,'A14: people are for planners and engagement managers');
reset role;select pg_temp.actor('outsider');set local role authenticated;
select throws_ok($$select pg_temp.people()$$,'42501',null,'A14: non-members cannot list people');
reset role;select pg_temp.actor('foreign');set local role authenticated;
select throws_ok($$select pg_temp.people()$$,'42501',null,'A14: another tenant cannot list people');
reset role;

select is((select jsonb_array_length(body->'members') from assurance_samples where label='a14.people'),
  (select count(*)::integer from core.memberships where tenant_id=pg_temp.aid('tenant') and status='active'),
  'A14: every active member of the tenant is listed');
select ok((select bool_and(exists(select 1 from core.memberships m where m.tenant_id=pg_temp.aid('tenant')
    and m.user_id=(p->>'user_id')::uuid and m.status='active'))
  from assurance_samples, jsonb_array_elements(body->'members') p where label='a14.people'),
  'A14: each entry is an active member user id');
select ok((select not bool_or(p->>'label' like '%@%') and bool_and(length(p->>'label')>0)
  from assurance_samples, jsonb_array_elements(body->'members') p where label='a14.people'),
  'A14: labels are names or masked ids, never e-mails');
select ok((select array_agg(p->>'label' order by n)=array_agg(p->>'label' order by p->>'label', p->>'user_id')
  from assurance_samples, jsonb_array_elements(body->'members') with ordinality x(p,n) where label='a14.people'),
  'A14: people are ordered by label');
select is((select body->>'truncated' from assurance_samples where label='a14.people'),'false',
  'A14: a small tenant is listed in full');
