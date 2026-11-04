-- Read-only inspection for the owner-selected Jentra project.
-- Verify project xpdoufauvrbdmxgngetv in the dashboard before executing.
-- No user/employee/payroll/invitation/device data or secret values are selected.
begin;
set transaction read only;
set local statement_timeout = '10s';

select jsonb_build_object(
  'checked_at_utc', timezone('UTC', statement_timestamp()),
  'database', current_database(),
  'server_version', current_setting('server_version'),
  'recent_migrations', (
    select coalesce(jsonb_agg(to_jsonb(m) order by m.version desc), '[]'::jsonb)
    from (
      select version, name
      from supabase_migrations.schema_migrations
      order by version desc
      limit 20
    ) m
  ),
  'candidate_schemas', (
    select coalesce(jsonb_agg(n.nspname order by n.nspname), '[]'::jsonb)
    from pg_catalog.pg_namespace n
    where n.nspname in ('workspace_admin', 'employee_self', 'employee_push')
  ),
  'installed_apis', (
    select coalesce(jsonb_agg(jsonb_build_object(
      'name', p.proname,
      'arguments', pg_catalog.pg_get_function_identity_arguments(p.oid),
      'security_definer', p.prosecdef,
      'settings', p.proconfig,
      'anon_execute', has_function_privilege('anon', p.oid, 'EXECUTE'),
      'authenticated_execute', has_function_privilege('authenticated', p.oid, 'EXECUTE'),
      'service_execute', has_function_privilege('service_role', p.oid, 'EXECUTE')
    ) order by p.proname, p.oid), '[]'::jsonb)
    from pg_catalog.pg_proc p
    join pg_catalog.pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'api' and p.prokind = 'f'
      and (p.proname like 'workspace\_%' escape '\'
        or p.proname like 'employee\_%' escape '\'
        or p.proname = 'people_hr_service_document')
  ),
  'private_table_security', (
    select coalesce(jsonb_agg(jsonb_build_object(
      'schema', n.nspname,
      'table', c.relname,
      'rls_enabled', c.relrowsecurity,
      'rls_forced', c.relforcerowsecurity,
      'anon_select', has_table_privilege('anon', c.oid, 'SELECT'),
      'authenticated_select', has_table_privilege('authenticated', c.oid, 'SELECT')
    ) order by n.nspname, c.relname), '[]'::jsonb)
    from pg_catalog.pg_class c
    join pg_catalog.pg_namespace n on n.oid = c.relnamespace
    where n.nspname in ('employee_self', 'employee_push')
      and c.relkind in ('r', 'p')
  ),
  'administration_guards', (
    select coalesce(jsonb_agg(jsonb_build_object(
      'name', t.tgname, 'enabled', t.tgenabled
    ) order by t.tgname), '[]'::jsonb)
    from pg_catalog.pg_trigger t
    join pg_catalog.pg_class c on c.oid = t.tgrelid
    join pg_catalog.pg_namespace n on n.oid = c.relnamespace
    where n.nspname = 'core' and not t.tgisinternal
      and t.tgname in ('workspace_admin_invitation_guard',
                      'workspace_admin_membership_activation_guard')
  ),
  'scheduler_extensions', (
    select coalesce(jsonb_agg(e.extname order by e.extname), '[]'::jsonb)
    from pg_catalog.pg_extension e
    where e.extname in ('pg_cron', 'pg_net', 'supabase_vault')
  )
) as rollout_preflight;

rollback;
