-- Hash-only preservation query. Compare to the immediately preinstall live read.
BEGIN ISOLATION LEVEL REPEATABLE READ READ ONLY;
SELECT jsonb_build_object('observedAt',statement_timestamp(),
 'accessCounts',jsonb_build_object('rolePermissions',(SELECT count(*) FROM core.role_permissions),'roleAssignments',(SELECT count(*) FROM core.role_assignments),'entitlements',(SELECT count(*) FROM billing.plan_entitlements),'memberships',(SELECT count(*) FROM core.memberships)),
 'accessRowFingerprints',(SELECT jsonb_object_agg(x.name,x.fingerprint ORDER BY x.name) FROM (
 SELECT 'core.role_permissions' AS name,encode(extensions.digest(coalesce((SELECT jsonb_agg(to_jsonb(t) ORDER BY t.tenant_id,t.role_id,t.permission_code)::text FROM core.role_permissions t),'[]'),'sha256'),'hex') AS fingerprint
 UNION ALL SELECT 'core.role_assignments',encode(extensions.digest(coalesce((SELECT jsonb_agg(to_jsonb(t) ORDER BY t.id)::text FROM core.role_assignments t),'[]'),'sha256'),'hex')
 UNION ALL SELECT 'billing.plan_entitlements',encode(extensions.digest(coalesce((SELECT jsonb_agg(to_jsonb(t) ORDER BY t.plan_code,t.entitlement_code)::text FROM billing.plan_entitlements t),'[]'),'sha256'),'hex')
 UNION ALL SELECT 'core.memberships',encode(extensions.digest(coalesce((SELECT jsonb_agg(to_jsonb(t) ORDER BY t.id)::text FROM core.memberships t),'[]'),'sha256'),'hex')
 ) x),
 'protectedProviders',(SELECT jsonb_agg(jsonb_build_object('schema',n.nspname,'name',p.proname,'arguments',pg_get_function_identity_arguments(p.oid),'definitionSha256',encode(extensions.digest(pg_get_functiondef(p.oid),'sha256'),'hex')) ORDER BY n.nspname,p.proname,pg_get_function_identity_arguments(p.oid))
 FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE p.prokind='f' AND (n.nspname='api' OR (n.nspname='core' AND p.proname IN ('has_permission','require_permission','wave2_assert_expected_version','wave2_derived_uuid','wave2_finish_command','wave2_permission','wave2_replay','wave2_request_hash','wave3_assert_expected_version','wave3_finish_command','wave3_replay','wave3_request_hash','wave3_require_scope')))),
 'existingDesktopAccount',(SELECT jsonb_build_object('authId',u.id,'confirmed',u.email_confirmed_at IS NOT NULL,'membershipCount',(SELECT count(*) FROM core.memberships m WHERE m.user_id=u.id)) FROM auth.users u WHERE u.id='c0ab44a9-7385-4d9c-94f2-4df3efaa453f'::uuid AND u.email='desktop-test-20261009@jentra.invalid'),
 'plannedRuntimeAccountCount',(SELECT count(*) FROM auth.users WHERE email IN ('w5-proposer@jentra.invalid','w5-approver@jentra.invalid','w5-executor@jentra.invalid','w5-billing-admin@jentra.invalid','w5-operator@jentra.invalid','w5-foreign-member@jentra.invalid')),
 'migrationCount',(SELECT count(*) FROM supabase_migrations.schema_migrations)
) AS installed_preservation;
ROLLBACK;
