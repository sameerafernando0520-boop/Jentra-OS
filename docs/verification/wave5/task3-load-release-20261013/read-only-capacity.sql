with reviewed_auth(label,user_id) as (values
('proposer','8b740ab8-24f7-4455-a78b-aea0d99d20f6'::uuid),
('approver','0635081d-08ea-4ad1-b7f2-ad2f8721f67d'::uuid),
('executor','75e6edec-382b-4ad5-96d8-c622a527921c'::uuid),
('billing-admin','c6aa32c0-d91f-4555-8687-e77fdf878e0c'::uuid),
('operator','c7618974-5d45-4c9c-886b-9e4986379d51'::uuid),
('foreign-member','cb1e2d20-08b0-44f0-b012-a76c47d0255a'::uuid)),
product_tables as (select c.oid,c.relrowsecurity,c.relforcerowsecurity,n.nspname from pg_class c join pg_namespace n on n.oid=c.relnamespace where c.relkind in ('r','p') and n.nspname in ('analytics','assets','billing','core','crm','delivery','expense_private','finance','hr_private','intelligence_control','inventory','operator_private','payroll_private','people','platform_private','procurement','projects','receivables','sales'))
select jsonb_build_object(
'observedAt',statement_timestamp(),'postgresVersion',current_setting('server_version'),
'maxConnections',current_setting('max_connections')::int,'sharedBuffers',current_setting('shared_buffers'),
'databaseBytes',pg_database_size(current_database()),'serverConnections',(select count(*) from pg_stat_activity),
'activeQueries',(select count(*) from pg_stat_activity where state='active'),
'lockWaiters',(select count(*) from pg_stat_activity where wait_event_type='Lock'),
'authSessionsTotal',(select count(*) from auth.sessions),
'reviewedActorSessions',(select jsonb_agg(jsonb_build_object('label',a.label,'serverSessionRows',(select count(*) from auth.sessions s where s.user_id=a.user_id)) order by a.label) from reviewed_auth a),
'eligibleReviewedLoadSessionRows',(select count(*) from auth.sessions s join reviewed_auth a on a.user_id=s.user_id where a.label<>'operator'),
'productTables',(select count(*) from product_tables),
'productTablesRlsDisabled',(select count(*) from product_tables where not relrowsecurity),
'productTablesAnonOrAuthenticatedDirectAccess',(select count(*) from product_tables where has_table_privilege('anon',oid,'SELECT,INSERT,UPDATE,DELETE') or has_table_privilege('authenticated',oid,'SELECT,INSERT,UPDATE,DELETE')),
'apiFunctionsAnonCanExecute',(select count(*) from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='api' and has_function_privilege('anon',p.oid,'EXECUTE')),
'readOnlyStatement',true,'connectorCommittedRepeatableReadProof',false
) as audit;
