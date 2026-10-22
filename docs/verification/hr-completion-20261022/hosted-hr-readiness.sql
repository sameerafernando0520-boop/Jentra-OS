-- Hosted HR readiness: bounded, read-only owner follow-up.
-- Prepared from repository contracts on 22 October 2026; NOT executed against
-- a hosted database. This file establishes no current hosted readiness result.
--
-- Before running, independently verify the selected Supabase dashboard/project
-- connection is the owner-selected xpdoufauvrbdmxgngetv project. PostgreSQL's
-- database name, this file's labels and the tenant slug CANNOT prove project URL
-- or project identity. Do not treat a matching tenant as that verification.
--
-- Run sections individually as a database administrator. Missing metadata,
-- relation/column errors or permission errors are findings to review, never
-- instructions to install, grant, enable, assign roles or repair production.
-- Only SELECT/WITH statements are included. No business RPC is invoked, including
-- the command/mark-read endpoints whose catalog metadata is inspected below.
-- No auth users, sessions, tokens, employee/account-link rows, payslip rows,
-- notification contents, function bodies or function configuration secrets are
-- selected. Private table names and policy predicates below are metadata only.
--
-- Source validation:
-- * 20260831193714_create_greenfield_foundation.sql: core.tenants and billing
--   plans/plan_entitlements/tenant_subscriptions columns.
-- * 20261006140000_wave5_process_metrics.sql: trial_started_at addition.
-- * 20260925181927_wave4_employee_foundation.sql: people.require_access window.
-- * 20260929224939_wave4_private_hr.sql: exact private-HR API signatures,
--   authenticated API grants and denied private-table direct access.
-- * 20260930070000_wave4_synthetic_payroll.sql: self-payslip summary signature.
-- * 20260901090420_expose_wave2_versioned_api.sql: mark_notification_read.
-- * 20260904121647_wave3_operational_foundation.sql: security-invoker inbox view.
-- * 20260901090317_create_wave2_shared_foundation_schema.sql:
--   notifications_recipient_read policy.
-- See hr-capability-matrix.md for employee-safe limitations and missing slices.

-- 1. Required billing/tenant columns: 20 expected rows, including missing ones.
-- Do not run section 2 if a required column is absent. Source presence is not
-- proof that the later Wave 5 trial_started_at migration is installed.
WITH expected(schema_name, table_name, column_name) AS (
  VALUES
    ('core', 'tenants', 'id'),
    ('core', 'tenants', 'slug'),
    ('core', 'tenants', 'status'),
    ('billing', 'plans', 'code'),
    ('billing', 'plans', 'status'),
    ('billing', 'plan_entitlements', 'plan_code'),
    ('billing', 'plan_entitlements', 'entitlement_code'),
    ('billing', 'plan_entitlements', 'enabled'),
    ('billing', 'plan_entitlements', 'numeric_limit'),
    ('billing', 'tenant_subscriptions', 'id'),
    ('billing', 'tenant_subscriptions', 'tenant_id'),
    ('billing', 'tenant_subscriptions', 'plan_code'),
    ('billing', 'tenant_subscriptions', 'status'),
    ('billing', 'tenant_subscriptions', 'seats'),
    ('billing', 'tenant_subscriptions', 'trial_started_at'),
    ('billing', 'tenant_subscriptions', 'trial_ends_at'),
    ('billing', 'tenant_subscriptions', 'current_period_ends_at'),
    ('billing', 'tenant_subscriptions', 'created_at'),
    ('billing', 'tenant_subscriptions', 'updated_at'),
    ('billing', 'tenant_subscriptions', 'version')
)
SELECT e.schema_name, e.table_name, e.column_name,
       a.attnum IS NOT NULL AS column_installed,
       pg_catalog.format_type(a.atttypid, a.atttypmod) AS installed_type
FROM expected e
LEFT JOIN pg_catalog.pg_namespace n ON n.nspname = e.schema_name
LEFT JOIN pg_catalog.pg_class c
  ON c.relnamespace = n.oid AND c.relname = e.table_name
LEFT JOIN pg_catalog.pg_attribute a
  ON a.attrelid = c.oid AND a.attname = e.column_name
 AND a.attnum > 0 AND NOT a.attisdropped
ORDER BY e.schema_name, e.table_name, e.column_name
LIMIT 20;

-- 2. Exactly the approved empty QA tenant and its unique subscription.
-- No personal name, creator, membership, email or employee data is returned.
-- The boolean reproduces the source People/Assets/Projects/Service subscription
-- time test, not their permission/MFA/employment checks or a full authorization.
-- trial_started_at is reported separately; that older People predicate does not
-- check it. No start date for a paid current period exists in this source table.
WITH target AS (
  SELECT id, slug, status FROM core.tenants WHERE slug = 'jentra-qa-221022'
)
SELECT statement_timestamp() AS observed_at,
       'jentra-qa-221022' AS requested_tenant_slug,
       t.id IS NOT NULL AS tenant_found,
       t.id AS tenant_id, t.status AS tenant_status,
       s.id IS NOT NULL AS subscription_found,
       s.id AS subscription_id, s.plan_code, p.status AS plan_status,
       s.status AS subscription_status, s.seats, s.version,
       s.created_at, s.updated_at, s.trial_started_at, s.trial_ends_at,
       s.current_period_ends_at,
       coalesce(
         (s.status = 'trialing' AND s.trial_ends_at > statement_timestamp())
         OR (s.status = 'active' AND
             (s.current_period_ends_at IS NULL OR
              s.current_period_ends_at > statement_timestamp())),
         false
       ) AS source_people_subscription_time_test
FROM (VALUES (1)) AS anchor(value)
LEFT JOIN target t ON true
LEFT JOIN billing.tenant_subscriptions s ON s.tenant_id = t.id
LEFT JOIN billing.plans p ON p.code = s.plan_code
LIMIT 1;

-- 3. People and other module flags on THIS tenant's current plan only.
-- Missing entitlement row differs from a stored false. A stored true alone
-- does not grant employee capabilities, satisfy MFA, or establish a valid link.
-- The all-plan false seeds must never be changed as an assumed next action.
WITH target AS (
  SELECT s.plan_code
  FROM core.tenants t
  JOIN billing.tenant_subscriptions s ON s.tenant_id = t.id
  WHERE t.slug = 'jentra-qa-221022'
), required(entitlement_code) AS (
  VALUES ('module.people'), ('module.assets'), ('module.projects'),
         ('module.service'), ('module.finance'), ('module.ai')
), codes AS (
  SELECT entitlement_code FROM required
  UNION
  SELECT e.entitlement_code
  FROM billing.plan_entitlements e
  JOIN target t ON t.plan_code = e.plan_code
  WHERE e.entitlement_code LIKE 'module.%'
)
SELECT t.plan_code, c.entitlement_code,
       e.entitlement_code IS NOT NULL AS entitlement_row_installed,
       e.enabled, e.numeric_limit
FROM codes c
LEFT JOIN target t ON true
LEFT JOIN billing.plan_entitlements e
  ON e.plan_code = t.plan_code AND e.entitlement_code = c.entitlement_code
ORDER BY c.entitlement_code
LIMIT 64;

-- 4. Exact API identities and effective anon/authenticated grants.
-- Metadata inspection ONLY: do not call any endpoint here. people_hr_command
-- is a multi-action write API, and people_hr_reviews can take a staff branch;
-- their existence/grants do not make every action/result employee-safe.
-- Signature matching uses argument TYPES, while installed_identity_arguments
-- also reports installed argument NAMES for review. No prosrc/function body is
-- read; metadata cannot certify accepted-link derivation or self-only semantics.
WITH expected(function_name, argument_types, purpose) AS (
  VALUES
    ('people_payroll_self_payslips', 'uuid, uuid, uuid, uuid', 'own synthetic payslip summary'),
    ('people_hr_self', 'uuid, uuid, uuid', 'accepted own identity'),
    ('people_hr_link_inbox', 'uuid, uuid, uuid, uuid', 'own pending account links'),
    ('people_hr_access', 'uuid, uuid, uuid, uuid, text', 'capability/subject authority check'),
    ('people_hr_reviews', 'uuid, uuid, uuid, uuid, uuid', 'conditional own/staff review projection'),
    ('people_hr_own_receipt', 'uuid, uuid, uuid, uuid', 'actor-scoped command recovery'),
    ('people_hr_command', 'uuid, uuid, uuid, uuid, uuid, timestamp with time zone, jsonb, bigint', 'multi-action command; catalog only'),
    ('mark_notification_read', 'uuid, uuid, bigint, uuid', 'recipient mark-read command; catalog only')
), roles AS (
  SELECT oid, rolname FROM pg_catalog.pg_roles
  WHERE rolname IN ('anon', 'authenticated')
)
SELECT e.function_name, e.argument_types AS expected_argument_types, e.purpose,
       p.oid IS NOT NULL AS exact_signature_installed,
       pg_catalog.pg_get_function_identity_arguments(p.oid) AS installed_identity_arguments,
       pg_catalog.pg_get_function_result(p.oid) AS installed_result_type,
       p.prosecdef AS security_definer, p.provolatile AS volatility,
       (SELECT option FROM unnest(p.proconfig) AS settings(option)
        WHERE option LIKE 'search_path=%' LIMIT 1) AS configured_search_path,
       (SELECT pg_catalog.has_function_privilege(r.oid, p.oid, 'EXECUTE')
        FROM roles r WHERE r.rolname = 'anon') AS anon_can_execute,
       (SELECT pg_catalog.has_function_privilege(r.oid, p.oid, 'EXECUTE')
        FROM roles r WHERE r.rolname = 'authenticated') AS authenticated_can_execute,
       (SELECT pg_catalog.has_schema_privilege(r.oid, n.oid, 'USAGE')
        FROM roles r WHERE r.rolname = 'authenticated') AS authenticated_api_schema_usage,
       coalesce((
         SELECT jsonb_agg(jsonb_build_object(
           'grantee', CASE WHEN grants.grantee = 0 THEN 'PUBLIC'
                           ELSE pg_catalog.pg_get_userbyid(grants.grantee) END,
           'privilege', grants.privilege_type, 'grantable', grants.is_grantable
         ) ORDER BY grants.grantee, grants.privilege_type)
         FROM pg_catalog.aclexplode(coalesce(
           p.proacl, pg_catalog.acldefault('f'::"char", p.proowner)
         )) AS grants
       ), '[]'::jsonb) AS function_grants
FROM expected e
LEFT JOIN pg_catalog.pg_namespace n ON n.nspname = 'api'
LEFT JOIN pg_catalog.pg_proc p
  ON p.pronamespace = n.oid AND p.proname = e.function_name
 AND pg_catalog.oidvectortypes(p.proargtypes) = e.argument_types
ORDER BY e.function_name
LIMIT 8;

-- 5. Inbox view/table identity, security-invoker option, RLS and direct SELECT
-- grants. Private HR/payroll tables normally deny direct authenticated access;
-- do not add policies/grants just because a private table has zero policies.
-- The notifications security-invoker view depends on its base table's RLS.
WITH expected(schema_name, relation_name) AS (
  VALUES ('api', 'my_notifications'), ('workflow', 'notifications'),
         ('people_private', 'account_links'), ('people_private', 'reviews'),
         ('people_private', 'review_revisions'), ('people_private', 'review_events'),
         ('people_payroll', 'payslips')
), roles AS (
  SELECT oid, rolname FROM pg_catalog.pg_roles
  WHERE rolname IN ('anon', 'authenticated')
)
SELECT e.schema_name, e.relation_name, c.oid IS NOT NULL AS relation_installed,
       c.relkind, c.relrowsecurity AS row_security_enabled,
       c.relforcerowsecurity AS force_row_security,
       coalesce('security_invoker=true' = ANY(c.reloptions), false)
         AS security_invoker_option,
       (SELECT pg_catalog.has_table_privilege(r.oid, c.oid, 'SELECT')
        FROM roles r WHERE r.rolname = 'anon') AS anon_can_select,
       (SELECT pg_catalog.has_table_privilege(r.oid, c.oid, 'SELECT')
        FROM roles r WHERE r.rolname = 'authenticated') AS authenticated_can_select,
       (SELECT pg_catalog.has_schema_privilege(r.oid, n.oid, 'USAGE')
        FROM roles r WHERE r.rolname = 'authenticated') AS authenticated_schema_usage,
       (SELECT count(*) FROM pg_catalog.pg_policy pol WHERE pol.polrelid = c.oid)
         AS policy_count
FROM expected e
LEFT JOIN pg_catalog.pg_namespace n ON n.nspname = e.schema_name
LEFT JOIN pg_catalog.pg_class c
  ON c.relnamespace = n.oid AND c.relname = e.relation_name
ORDER BY e.schema_name, e.relation_name
LIMIT 7;

-- 6. Every policy on the notification base table and the five inspected private
-- HR/payroll tables above. These are catalog predicates, never employee rows.
-- Review ALL returned notification SELECT policies: an extra permissive policy
-- can broaden access even when notifications_recipient_read still exists.
-- Expected recipient predicate derives auth.uid() and tenant membership.
SELECT n.nspname AS schema_name, c.relname AS relation_name,
       pol.polname AS policy_name, pol.polcmd AS command,
       pol.polpermissive AS permissive,
       ARRAY(SELECT CASE WHEN role_oid = 0 THEN 'PUBLIC'
                         ELSE pg_catalog.pg_get_userbyid(role_oid) END
             FROM unnest(pol.polroles) AS policy_roles(role_oid)
             ORDER BY role_oid) AS roles,
       pg_catalog.pg_get_expr(pol.polqual, pol.polrelid) AS using_predicate,
       pg_catalog.pg_get_expr(pol.polwithcheck, pol.polrelid) AS check_predicate
FROM pg_catalog.pg_policy pol
JOIN pg_catalog.pg_class c ON c.oid = pol.polrelid
JOIN pg_catalog.pg_namespace n ON n.oid = c.relnamespace
WHERE (n.nspname, c.relname) IN (
  ('workflow', 'notifications'), ('people_private', 'account_links'),
  ('people_private', 'reviews'), ('people_private', 'review_revisions'),
  ('people_private', 'review_events'), ('people_payroll', 'payslips')
)
ORDER BY n.nspname, c.relname, pol.polname
LIMIT 64;

-- 7. Confirm the installed inbox view depends on workflow.notifications without
-- selecting its rows or dumping the view/function definitions. Dependencies and
-- security-invoker metadata do not replace a controlled recipient-isolation test.
SELECT v.oid IS NOT NULL AS inbox_view_installed,
       EXISTS (
         SELECT 1
         FROM pg_catalog.pg_rewrite rewrite
         JOIN pg_catalog.pg_depend dependency
           ON dependency.classid = 'pg_catalog.pg_rewrite'::regclass
          AND dependency.objid = rewrite.oid
          AND dependency.refclassid = 'pg_catalog.pg_class'::regclass
         JOIN pg_catalog.pg_class base ON base.oid = dependency.refobjid
         JOIN pg_catalog.pg_namespace base_schema ON base_schema.oid = base.relnamespace
         WHERE rewrite.ev_class = v.oid AND rewrite.rulename = '_RETURN'
           AND base_schema.nspname = 'workflow' AND base.relname = 'notifications'
       ) AS depends_on_notifications
FROM (VALUES (1)) AS anchor(value)
LEFT JOIN pg_catalog.pg_namespace n ON n.nspname = 'api'
LEFT JOIN pg_catalog.pg_class v
  ON v.relnamespace = n.oid AND v.relname = 'my_notifications' AND v.relkind = 'v'
LIMIT 1;

-- Interpretation: record externally verified project identity, query timestamp,
-- metadata findings and exact tenant/plan separately. Neither green metadata nor
-- a trial/owner role proves the full HR blueprint, correct installed function
-- semantics, accepted employee identity, MFA completion, delivery or real payroll.
-- No output from this script authorizes a hosted mutation or a role assignment.
