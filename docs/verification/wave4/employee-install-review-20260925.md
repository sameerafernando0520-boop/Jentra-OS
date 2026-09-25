# W4-01 development installation record

**Decision:** The owner replied “continue” to the specific development-install
approval request on 2026-09-25. The W4-01 migration was installed on the named
development project with every People plan disabled. No production change.

## Exact installed change

- Target: Supabase development project `xpdoufauvrbdmxgngetv` (ACTIVE_HEALTHY).
- Ledger: `20260925181927_wave4_employee_foundation`; migration count 34 to 35.
- Local file aligned to the recorded ledger version:
  `supabase/migrations/20260925181927_wave4_employee_foundation.sql`.
- Reviewed and installed SHA-256:
  `CF87FF4FEF5041394D28FAAF265D98762D90FCC14FE1B0DE4A6828477D695BFC`.
- The migration creates the scoped People employee schema, five API functions,
  permissions and event contracts. It seeds `module.people` disabled on all
  three current plans. No role capabilities were granted by this installation.

## Verification

Before installation, the candidate and 49 pgTAP assertions passed inside a
transaction ending in `ROLLBACK`; the ledger had 34 migrations and no People
objects. After installation, the same 49 assertions passed against the installed
schema in a separate rollback transaction (`1..49`). A subsequent read found
zero persistent People employees, spells, assignments or events; 35 migrations;
all three People plan entitlements disabled; four base tables with forced RLS;
five security-definer API functions; the entitlement check in the installed
function; and no `authenticated` base-table SELECT grant.

Four domain, one encrypted restart and nine desktop/controller/UI tests passed;
focused analysis and an isolated Windows release build passed. The
[plan-denial view](../../../apps/jentra_desktop/test/goldens/employee_plan_denied_light_200.png)
was visually inspected at 200% text. These checks do not prove a signed-in
Windows session or two-session contention.

Post-DDL advisors added four informational `rls_enabled_no_policy` findings on
the deliberately API-only People base tables and ten informational unindexed
People foreign keys. The prior leaked-password-protection warning remains;
no auth setting was changed. Review the [RLS advisor](https://supabase.com/docs/guides/database/database-linter?lint=0008_rls_enabled_no_policy)
and [foreign-key advisor](https://supabase.com/docs/guides/database/database-linter?lint=0001_unindexed_foreign_keys)
before wider data/load rollout. Applied SQL is immutable; any needed index or
contract repair must use a new forward migration.

## Synthetic test-plan fixture and open gates

On 2026-09-26 the owner chose a separate synthetic W4 tenant and test plan.
A DML transaction copied starter's basic limits to
`w4_employee_synthetic`, enabled `module.people` only on that new plan, and
committed after a self-rolling-back preflight. A persistent read confirmed the
test plan has four entitlements and zero subscribers; `starter` still has one
subscriber (Jentra Acceptance Lab) and all three original plans remain People
disabled. This fixture did not add a migration or change the lab subscription.

The synthetic tenant still needs to be created through the signed-in setup
flow. That flow creates the owner membership, role and audit event from the real
authenticated actor. After its new starter subscription exists, move only that
tenant to `w4_employee_synthetic`, verify the original plans stay disabled, and run the
[two-session contention protocol](employee-contention-20260925.md) using
independent connections, then the user-managed
[Windows/MFA walkthrough](employee-native-acceptance-20260926.md) and owner
signoff. The Supabase SQL connector serialized the attempted dual-query
probe, so it cannot establish the contention gate by itself.

Other Wave 3 candidate migrations in the checkout have earlier timestamps but
remain uninstalled. Coordinate their eventual application with the recorded
W4-01 ledger version; do not edit the applied W4-01 SQL or assume a normal
timestamp-ordered bulk push will reconcile them automatically. Concurrent Wave 3
source and acceptance-owned work were left untouched.
