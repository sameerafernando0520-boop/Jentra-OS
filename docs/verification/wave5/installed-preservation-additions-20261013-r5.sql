-- Read-only successor: explain only the five exact approved migration DML additions.
-- Historical all-row hashes remain authoritative for the rows excluding these additions.
BEGIN ISOLATION LEVEL REPEATABLE READ READ ONLY;
WITH expected_permissions AS (
 SELECT r.tenant_id,r.id AS role_id,x.code AS permission_code
 FROM core.roles r CROSS JOIN (VALUES
 ('finance.cash_flow.configure'),('finance.budgets.approve'),
 ('inventory.dispositions.post'),('inventory.stock.policy.manage')) x(code)
 WHERE r.code='tenant_owner'
), actual_permissions AS (
 SELECT tenant_id,role_id,permission_code FROM core.role_permissions
 WHERE permission_code IN ('finance.cash_flow.configure','finance.budgets.approve',
 'inventory.dispositions.post','inventory.stock.policy.manage')
), expected_entitlements AS (
 SELECT code AS plan_code,'quota.integration.commands'::text AS entitlement_code,false AS enabled FROM billing.plans
), actual_entitlements AS (
 SELECT plan_code,entitlement_code,enabled FROM billing.plan_entitlements WHERE entitlement_code='quota.integration.commands'
)
SELECT jsonb_build_object('observedAt',statement_timestamp(),
 'migrationCount',(SELECT count(*) FROM supabase_migrations.schema_migrations),
 'expectedAddedPermissionCount',(SELECT count(*) FROM expected_permissions),
 'actualAddedPermissionCount',(SELECT count(*) FROM actual_permissions),
 'permissionAdditionsExactlyMatch',NOT EXISTS(
  (SELECT * FROM expected_permissions EXCEPT SELECT * FROM actual_permissions)
  UNION ALL (SELECT * FROM actual_permissions EXCEPT SELECT * FROM expected_permissions)),
 'expectedAddedEntitlementCount',(SELECT count(*) FROM expected_entitlements),
 'actualAddedEntitlementCount',(SELECT count(*) FROM actual_entitlements),
 'entitlementAdditionsExactlyMatch',NOT EXISTS(
  (SELECT * FROM expected_entitlements EXCEPT SELECT * FROM actual_entitlements)
  UNION ALL (SELECT * FROM actual_entitlements EXCEPT SELECT * FROM expected_entitlements)),
 'priorRolePermissionCount',(SELECT count(*) FROM core.role_permissions WHERE permission_code NOT IN
 ('finance.cash_flow.configure','finance.budgets.approve','inventory.dispositions.post','inventory.stock.policy.manage')),
 'priorEntitlementCount',(SELECT count(*) FROM billing.plan_entitlements WHERE entitlement_code<>'quota.integration.commands'),
 'priorRolePermissionsSha256',encode(extensions.digest(coalesce((SELECT jsonb_agg(to_jsonb(t) ORDER BY t.tenant_id,t.role_id,t.permission_code)::text
 FROM core.role_permissions t WHERE t.permission_code NOT IN
 ('finance.cash_flow.configure','finance.budgets.approve','inventory.dispositions.post','inventory.stock.policy.manage')),'[]'),'sha256'),'hex'),
 'priorEntitlementsSha256',encode(extensions.digest(coalesce((SELECT jsonb_agg(to_jsonb(t) ORDER BY t.plan_code,t.entitlement_code)::text
 FROM billing.plan_entitlements t WHERE t.entitlement_code<>'quota.integration.commands'),'[]'),'sha256'),'hex')
) AS installed_preservation_additions;
ROLLBACK;
