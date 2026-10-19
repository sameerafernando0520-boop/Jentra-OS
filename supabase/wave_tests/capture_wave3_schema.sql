-- Metadata only. Run after the candidate DDL, before strict finish and rollback.
select jsonb_build_object(
 'database','jentra-development','schema_version','observed-20260930-45',
 'tables',coalesce((select jsonb_object_agg(n.nspname||'.'||c.relname,jsonb_build_object(
   'columns',coalesce((select jsonb_object_agg(a.attname,jsonb_build_object(
     'type',format_type(a.atttypid,a.atttypmod),'nullable',not a.attnotnull,
     'default',pg_get_expr(d.adbin,d.adrelid)))
     from pg_attribute a left join pg_attrdef d on d.adrelid=a.attrelid and d.adnum=a.attnum
     where a.attrelid=c.oid and a.attnum>0 and not a.attisdropped),'{}'::jsonb),
   'constraints',coalesce((select jsonb_object_agg(kind,definitions) from (
     select case contype when 'p' then 'primary_key' when 'u' then 'unique'
       when 'f' then 'foreign_key' when 'c' then 'check' when 'x' then 'exclusion' end kind,
       jsonb_agg(pg_get_constraintdef(oid) order by conname) definitions
     from pg_constraint where conrelid=c.oid and contype in ('p','u','f','c','x') group by contype)q),'{}'::jsonb)))
   from pg_class c join pg_namespace n on n.oid=c.relnamespace
   where c.relkind in ('r','p') and n.nspname in ('core','crm','sales','inventory','procurement','finance','workflow','people')),'{}'::jsonb),
 'functions',coalesce((select jsonb_object_agg(p.oid::regprocedure::text,jsonb_build_object(
   'acl',p.proacl::text,'return_type',pg_get_function_result(p.oid),'source_md5',md5(pg_get_functiondef(p.oid))))
   from pg_proc p join pg_namespace n on n.oid=p.pronamespace
   where p.prokind='f' and n.nspname in ('api','core','crm','sales','inventory','procurement','finance','workflow','people')),'{}'::jsonb),
 'views',coalesce((select jsonb_object_agg(n.nspname||'.'||c.relname,jsonb_build_object(
   'options',c.reloptions,'source_md5',md5(pg_get_viewdef(c.oid))))
   from pg_class c join pg_namespace n on n.oid=c.relnamespace
   where c.relkind='v' and n.nspname='api'),'{}'::jsonb)
) as schema_evidence;
