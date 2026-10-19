-- Corporate Audit & Assurance plan register candidate tests.
-- Included only by build_assurance_candidate.ps1 -Slice A6, after the
-- version-guard tests and the plan register candidate DDL. Reuses plan6.
create function pg_temp.plans(p_after uuid default null, p_branch text default 'tenant.branch') returns jsonb language sql as $$
  select api.assurance_plans(pg_temp.aid('tenant'),pg_temp.aid('tenant.entity'),pg_temp.aid(p_branch),p_after) $$;
reset role;
select ok(has_function_privilege('authenticated','api.assurance_plans(uuid,uuid,uuid,uuid)','EXECUTE')
  and not has_function_privilege('anon','api.assurance_plans(uuid,uuid,uuid,uuid)','EXECUTE'),
  'plan register: authenticated-only');
select pg_temp.actor('manager');set local role authenticated;
insert into assurance_samples values('plans.manager',pg_temp.plans());
reset role;select pg_temp.actor('owner');set local role authenticated;
insert into assurance_samples values('plans.viewer',pg_temp.plans());
reset role;
select ok((select x->>'status'='approved' and (x->>'active_items')::integer=1 and (x->>'version')::integer>1
  and x->>'approved_by'=pg_temp.aid('reviewer')::text
  from assurance_samples s, jsonb_array_elements(s.body->'items') x
  where s.label='plans.manager' and x->>'id'=pg_temp.aid('plan6')::text),
  'plan register lists the plan with status, version, approver and active items only');
select is((select body->'next_cursor' from assurance_samples where label='plans.manager'),'null'::jsonb,
  'a short register has no next page');
select is((select body from assurance_samples where label='plans.viewer'),
  (select body from assurance_samples where label='plans.manager'),'evidence viewers read the same register');
select pg_temp.actor('manager');set local role authenticated;
select is(jsonb_array_length(pg_temp.plans(pg_temp.aid('plan6'))->'items'),
  (select count(*)::integer from assurance.plans where tenant_id=pg_temp.aid('tenant') and id>pg_temp.aid('plan6')),
  'the register pages after a cursor');
reset role;select pg_temp.actor('entityviewer');set local role authenticated;
select is(jsonb_array_length(pg_temp.plans(null,'tenant.branch2')->'items'),0,'a branch register shows only that branch');
reset role;select pg_temp.actor('external');set local role authenticated;
select throws_ok($$select pg_temp.plans()$$,'42501',null,'external reviewers cannot list plans');
reset role;select pg_temp.actor('foreign');set local role authenticated;
select throws_ok($$select pg_temp.plans()$$,'42501',null,'another tenant cannot list plans');
reset role;
