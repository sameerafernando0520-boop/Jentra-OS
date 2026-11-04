-- Fixed, read-only field-sales rollout preflight. No account identifiers or secrets.
select jsonb_build_object(
 'server_version',current_setting('server_version'),
 'field_sales_installed',to_regnamespace('field_sales') is not null,
 'migration_count',(select count(*) from supabase_migrations.schema_migrations),
 'latest_migration',(select max(version) from supabase_migrations.schema_migrations),
 'migration_versions_md5',(select md5(string_agg(version,',' order by version)) from supabase_migrations.schema_migrations),
 'core_permission_function',to_regprocedure('core.has_permission(uuid,text,uuid,uuid)') is not null,
 'commerce_command',to_regprocedure('api.sales_order_command(uuid,uuid,uuid,uuid,uuid,timestamp with time zone,text,jsonb,bigint)') is not null,
 'auth_sessions',to_regclass('auth.sessions') is not null,
 'private_hr',to_regnamespace('people_private') is not null,
 'extensions',(select jsonb_agg(extname order by extname) from pg_extension)
) as field_sales_readiness;
