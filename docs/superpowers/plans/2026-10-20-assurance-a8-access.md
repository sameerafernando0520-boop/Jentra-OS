# Assurance A8 — Access Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Real members can be given assurance access: existing tenant owners get every assurance permission, five assurance roles exist in every tenant, and a desktop **Audit access** page grants and revokes them.

**Architecture:** One candidate migration adds the owner backfill, role seeding (backfill plus a trigger on new tenants), an immutable access event log with a per-membership version, a read API (`api.assurance_access`) and a write API (`api.assurance_set_role`). A new domain file parses the read model and validates commands; a separate platform gateway (`AssuranceAccessGateway`) keeps the existing `AssuranceGateway` and its fakes untouched; a new desktop page follows the Audit planning controller pattern (encrypted draft, sealed retry).

**Tech Stack:** PostgreSQL / Supabase (plpgsql, pgTAP via builder), Dart 3, Flutter, Riverpod, go_router.

**Spec:** `docs/superpowers/specs/2026-10-20-assurance-completion-design.md` (section A8)

## Global Constraints

- APIs: `security definer`, `set search_path = ''`, revoke from `public, anon, service_role`, grant execute to `authenticated` only; authority before existence and before idempotent replay.
- Errors: `22023` validation, `42501` authority/MFA, `55000` state, `40001` version conflict, `P0002` not found.
- Writes take `p_idempotency_key` and `p_expected_version` (null rejected with `22023 ASSURANCE_VERSION_REQUIRED`); receipts in `assurance.command_receipts` keyed `(actor_id, idempotency_key)`.
- Member labels: linked employee display name when an `accepted` `people_private.account_links` row exists, otherwise `Unlinked member ····<last 4 of membership id>`; never a login e-mail.
- Role table (codes, names, permissions, `requires_mfa`) exactly as in the spec's A8 table.
- Candidate file `supabase/candidates/20261020090000_assurance_access.sql`, marked "CANDIDATE ONLY. Not installed."
- Desktop: every write is an encrypted draft sealed with the expected version and retried with the same key.

## Review Focus

1. Revoking a role from yourself that is your only route to `core.roles.manage` — expected: allowed only for assurance roles (never touches `tenant_owner`), so the manager cannot lock themselves out; test in Task 1.
2. Granting the same role at the same scope twice (null entity/branch) — expected: second grant is a no-op receipt, not a duplicate row (unique index treats nulls as distinct); test in Task 1.
3. Branch-scoped role manager — expected: refused (`core.roles.manage` must be tenant-wide); test in Task 1.
4. Member list larger than one page — expected: cursor paging, "More members" in the UI; test in Tasks 1 and 4.
5. Access revoked while the page is open — expected: data cleared, "Recheck access" shown, sealed request kept; test in Task 4.

---

### Task 1: Candidate migration and rollback suite

**Files:**
- Create: `supabase/candidates/20261020090000_assurance_access.sql`
- Create: `supabase/assurance_tests/assurance_access_test.sql`
- Modify: `supabase/tests/build_assurance_candidate.ps1` (add `A8` to `ValidateSet`; include A7 for `A8`; append the candidate and fragment for `A8`)

**Interfaces:**
- Produces (SQL):
  - `assurance.seed_roles(p_tenant_id uuid) returns void` — idempotent; inserts the five roles and their permissions.
  - trigger `assurance_seed_roles_on_tenant` `after insert on core.tenants`.
  - table `assurance.access_versions(tenant_id, membership_id, version bigint)` and immutable `assurance.access_events(id, tenant_id, membership_id, version, action 'grant'|'revoke', role_code, legal_entity_id, branch_id, actor_id, occurred_at)`, both forced RLS, no grants.
  - `api.assurance_access(p_tenant_id uuid, p_legal_entity_id uuid, p_branch_id uuid, p_after uuid) returns jsonb` → `{can_manage bool, roles:[{code,name,description,requires_mfa,permissions[]}], members:[{membership_id,label,linked bool,version,assignments:[{role_code,scope:'tenant'|'entity'|'branch',legal_entity_id,branch_id}]}], next_cursor}`; 50 members per page ordered by membership id. Allowed for tenant-wide `core.roles.manage`, or `assurance.plan.manage` / `assurance.engagement.manage` in scope (then `can_manage = false`).
  - `api.assurance_set_role(p_tenant_id uuid, p_legal_entity_id uuid, p_branch_id uuid, p_idempotency_key uuid, p_payload jsonb, p_expected_version bigint) returns jsonb` → `{membership_id, version, role_code, granted, scope}`. Payload fields exactly `membership_id, role_code, granted, scope` (`scope` in `tenant|entity|branch`, resolved against the call's entity/branch). Requires tenant-wide `core.roles.manage` and recent MFA (`ASSURANCE_RECENT_MFA_REQUIRED`). Unknown role → `22023 ASSURANCE_ROLE_UNKNOWN`; inactive/foreign membership → `P0002 ASSURANCE_MEMBER_NOT_FOUND`; revoke of absent assignment → `P0002 ASSURANCE_ASSIGNMENT_NOT_FOUND`; grant of an existing assignment → success without a new row, version still advances (one event).

- [ ] **Step 1: Write the rollback fragment** `assurance_access_test.sql` using the A1 fixtures (`pg_temp.aid`, `pg_temp.actor`). Add a `tenant_owner` role for `tenant` assigned tenant-wide to `manager` with `core.roles.manage` only (pre-candidate state), then the candidate DDL runs before the fragment (builder order). Assertions (≈30), including:
  - `ok` every existing `tenant_owner` role holds all 15 `assurance.*` permissions after the backfill;
  - `is` five `assurance_*` roles exist in `tenant` and `other`; `requires_mfa` true for lead, auditor, reviewer and false for process owner, external; permission sets match the spec table exactly;
  - inserting a new tenant row seeds the five roles (trigger);
  - `ok` no seeded role with a privileged permission has `requires_mfa = false`;
  - manager reads access: `can_manage` true, member labels never contain `@`; planner (`lead` fixture) reads with `can_manage` false; `outsider` and `foreign` get `42501`;
  - grant `assurance_auditor` at `entity` scope to `owner` → version 1, assignment visible; same idempotency key replays the same receipt; same key with a changed body → `IDEMPOTENCY_MISMATCH`;
  - second grant at the same scope with a new key → no duplicate `core.role_assignments` row, version 2;
  - revoke → assignment gone, version 3; revoke again → `P0002`;
  - stale version → `40001`; null version → `22023`; no recent MFA (`pg_temp.actor('manager', true, 2000)`) → `42501`;
  - `role_code = 'tenant_owner'` → `22023 ASSURANCE_ROLE_UNKNOWN`;
  - branch-scoped role manager → `42501`;
  - 51 synthetic memberships page as 50 + 1 with `next_cursor`;
  - `access_events` rejects update and delete.

- [ ] **Step 2: Build and run on the development project; expect failure**

Run: `pwsh supabase/tests/build_assurance_candidate.ps1 -Slice A8 -Installed > $scratch/a8.sql` then execute `$scratch/a8.sql` with the Supabase `execute_sql` tool on `xpdoufauvrbdmxgngetv`.
Expected: error — `function api.assurance_access does not exist` (candidate not yet written).

- [ ] **Step 3: Write the candidate** with the interfaces above. Reuse `assurance.recent_mfa()`, `assurance.require_scope`, `assurance.deny`, `assurance.forbid_mutation` (for the event table). Request hash as in `assurance.prepare_command`. Lock the membership's `access_versions` row (`for update`, insert at version 0 when absent) before comparing versions.

- [ ] **Step 4: Re-run the slice; expect all assertions to pass**

Expected: final row `assertions = passed`, `failures` null; transaction rolled back.

- [ ] **Step 5: Commit**

```bash
git add supabase/candidates/20261020090000_assurance_access.sql supabase/assurance_tests/assurance_access_test.sql supabase/tests/build_assurance_candidate.ps1
git commit -m "Add assurance A8 access candidate: owner backfill, seeded roles, access API"
```

### Task 2: Domain access model

**Files:**
- Create: `packages/jentra_domain/lib/src/assurance_access.dart`
- Modify: `packages/jentra_domain/lib/jentra_assurance.dart` (export)
- Test: `packages/jentra_domain/test/assurance_access_test.dart`

**Interfaces:**
- Produces:
  - `enum AssuranceRole { lead, auditor, reviewer, processOwner, external }` with `String code` (`assurance_lead` …), `String label`, `String summary` (one plain sentence of what the role can do), `bool requiresMfa`, `static AssuranceRole parse(Object?)`.
  - `enum AccessScope { tenant, entity, branch }` with `parse`.
  - `typedef AccessAssignment = ({AssuranceRole role, AccessScope scope, String? legalEntityId, String? branchId});`
  - `typedef AccessMember = ({String membershipId, String label, bool linked, int version, List<AccessAssignment> assignments});`
  - `final class AssuranceAccess { AssuranceAccess.fromJson(Map<String, Object?>); final bool canManage; final List<AccessMember> members; final String? nextCursor; bool holds(AccessMember, AssuranceRole, AccessScope); }`
  - `abstract final class AssuranceAccessCommands { static const fields = ['membership_id','role_code','granted','scope']; static void validate(Map<String, Object?> payload); }`
  - `bool assuranceAccessReceiptConfirms(Map<String, Object?> receipt, Map<String, Object?> payload, int expectedVersion)` — membership, role, granted match and `version == expectedVersion + 1`.

- [ ] **Step 1: Write failing tests**: parses a two-member fixture (one linked, one unlinked) with assignments; rejects an unknown role code, a label containing `@`, a negative version, a member list that is not a list; `AssuranceRole.values.map((r) => r.code)` equals the five spec codes and `requiresMfa` matches the spec table; `validate` rejects extra fields, a non-boolean `granted`, an unknown scope; `assuranceAccessReceiptConfirms` true only for `version == expected + 1` and matching fields.
- [ ] **Step 2: Run** `dart test test/assurance_access_test.dart` in `packages/jentra_domain` — expect failures (missing file).
- [ ] **Step 3: Implement** `assurance_access.dart` using `assuranceId` / `assuranceText` from `assurance.dart`; export it.
- [ ] **Step 4: Run** the test file and the full `dart test` — expect all pass; `dart analyze` clean.
- [ ] **Step 5: Commit** `git commit -m "Add assurance access domain model"`.

### Task 3: Platform access gateway

**Files:**
- Create: `packages/jentra_platform/lib/src/supabase_assurance_access_gateway.dart`
- Modify: `packages/jentra_platform/lib/jentra_assurance_platform.dart` (export)
- Test: `packages/jentra_platform/test/assurance_access_gateway_test.dart`

**Interfaces:**
- Consumes: Task 2 types; `SupabaseAssuranceGateway.assuranceDenial` for error mapping.
- Produces:
  - `abstract interface class AssuranceAccessGateway { Future<AssuranceAccess> access(TenantContext scope, {String? after}); Future<Map<String, Object?>> setRole(CommandEnvelope<Map<String, Object?>> command); }`
  - `final class SupabaseAssuranceAccessGateway implements AssuranceAccessGateway` calling `api.assurance_access` and `api.assurance_set_role`; refuses a null expected version and an unconfirmed receipt (`UNCERTAIN_RESULT`), validates with `AssuranceAccessCommands.validate` before sending.
  - New `_validation` messages in `SupabaseAssuranceGateway`: `ASSURANCE_ROLE_UNKNOWN` → "Only assurance roles can be given here.", `ASSURANCE_ASSIGNMENT_NOT_FOUND` handled as `NOT_FOUND` with "That role is no longer assigned. Refresh access."

- [ ] **Step 1: Write failing tests** following `assurance_gateway_test.dart` (same fake client approach): sends tenant/entity/branch, `p_after`; invalid response rejected before use; a receipt with the wrong version maps to `UNCERTAIN_RESULT`; `42501` with `MFA` maps to `MFA_REQUIRED`; extra payload field is rejected before sending.
- [ ] **Step 2: Run** `flutter test --no-pub test/assurance_access_gateway_test.dart` — expect failures.
- [ ] **Step 3: Implement** the gateway and export.
- [ ] **Step 4: Run** the file, the full platform suite and `flutter analyze --no-pub` — expect pass / clean.
- [ ] **Step 5: Commit** `git commit -m "Add assurance access gateway"`.

### Task 4: Desktop Audit access page

**Files:**
- Create: `apps/jentra_desktop/lib/src/features/assurance/assurance_access_controller.dart`
- Create: `apps/jentra_desktop/lib/src/features/assurance/assurance_access_screen.dart`
- Modify: `apps/jentra_desktop/lib/src/router.dart` (route `/governance/audit/access` with `onExit → canLeave()`), `apps/jentra_desktop/lib/src/shell/navigation.dart` (destination "Audit access", icon `Icons.admin_panel_settings_outlined`, section `GOVERNANCE`, visible with `core.roles.manage`), `apps/jentra_desktop/lib/main.dart` (override `assuranceAccessGatewayProvider` with `SupabaseAssuranceAccessGateway`)
- Test: `apps/jentra_desktop/test/assurance_access_test.dart`, goldens `test/goldens/audit_access_{light,dark}_200.png`

**Interfaces:**
- Consumes: Task 3 gateway; `QuotationDraftStore`, `encryptedDraftRepositoryProvider`, `activeTenantContextProvider`, `businessCapabilitiesProvider`, `connectivityStateProvider` (as in `assurance_planning_controller.dart`).
- Produces:
  - `final assuranceAccessGatewayProvider = Provider<AssuranceAccessGateway?>((ref) => null);`
  - `final assuranceAccessControllerProvider` (autoDispose; null without `core.roles.manage`).
  - `final class AssuranceAccessController extends ChangeNotifier` with `static const slot = 'assurance-access-command'`, `initialize()`, `refresh()`, `more()`, `startChange(AccessMember member, AssuranceRole role, AccessScope scope, {required bool grant})`, `submit()`, `discardDraft()`, `canLeave()`; fields `access`, `busy`, `error`, `message`, `accessDenied`, `pending`, `conflicted`, `form`.

- [ ] **Step 1: Write failing tests** with a `FakeAccessGateway`:
  - lists members with role chips and labels, never an `@`;
  - granting seals `{membership_id, role_code, granted: true, scope}` with the member's version and confirms;
  - MFA refusal keeps the sealed request and shows "Retry saved request";
  - a version conflict asks for a refresh and blocks resend;
  - permission loss clears members and shows "Recheck access";
  - more than one page shows "More members" and appends;
  - the role legend lists all five roles with their summaries;
  - 200% light and dark goldens; keyboard focus reaches every grant/revoke control.
- [ ] **Step 2: Run** `flutter test --no-pub test/assurance_access_test.dart` — expect failures.
- [ ] **Step 3: Implement** controller (copy the planning controller's draft/seal/retry flow; payload from `startChange`) and screen: header and one-line purpose, role legend (five cards), member table (label, linked badge, role chips per scope), per-member "Change access" opening a card with role choice chips, scope choice (whole organisation / this entity / this branch), grant/revoke, MFA note for roles that require it, consequence text before sending.
- [ ] **Step 4: Run** the file with `--update-goldens` once, inspect the PNGs, then without; run full desktop suite and `flutter analyze --no-pub`.
- [ ] **Step 5: Commit** `git commit -m "Add Audit access desktop page"`.

### Task 5: Docs and PR

**Files:**
- Modify: `docs/development/corporate-audit-status.md` (new "Slice A8 — access" table: source, candidate evidence with counts, tests, not done)
- Create: `docs/verification/assurance/a8-access-rollback-20261020.json` (kind, slice, project, tool, executed, assertions, passed, candidate sha256)

- [ ] **Step 1:** Record the Task 1 run and candidate hash; update the status doc.
- [ ] **Step 2:** Commit, push `assurance/a8-access`, open a PR against `assurance/a7-planning-screens`.
