begin read only;
set local transaction_read_only=on;
set local search_path='';
select jsonb_build_object('observedAt',statement_timestamp(),'name',p.proname,'args',pg_catalog.pg_get_function_identity_arguments(p.oid),'md5',md5(p.prosrc),'lfMd5',md5(replace(p.prosrc,chr(13)||chr(10),chr(10))),'length',length(p.prosrc),'config',to_jsonb(p.proconfig),'acl',p.proacl::text,'argsMatch',pg_catalog.pg_get_function_identity_arguments(p.oid)='p_runtime_id uuid, p_action text, p_payload jsonb','bodyMatch',md5(p.prosrc)='c75771a9fec7d5b4f514023e97f8e8b5','configMatch',to_jsonb(p.proconfig)='["search_path=\"\""]'::jsonb,'aclMatch',p.proacl::text='{postgres=X/postgres,service_role=X/postgres}') as verified_evidence from pg_catalog.pg_proc p join pg_catalog.pg_namespace n on n.oid=p.pronamespace where n.nspname='api' and p.proname='wave5_edge_control';
rollback;
