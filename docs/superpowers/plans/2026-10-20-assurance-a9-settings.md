# Assurance A9 — Settings and Plan Revision Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Reminder bands, the finding-response deadline, risk-rating bands and monitoring-rule thresholds become per-tenant (optionally per-entity) settings with today's values as defaults, and an approved plan can be revised through a superseding draft.

**Architecture:** One candidate migration adds `assurance.settings` (+ immutable `assurance.settings_events`), tenant-aware helpers, read/write APIs, and replaces the functions that hard-code today's values: `assurance.work_items`, `api.assurance_overview`, `api.assurance_evidence_command` (A4b body, monitoring now settings-aware) and `api.assurance_plan_command` (version-guard body, settings-aware rating plus `supersede_plan`). Bodies are copied from the installed/candidate source with marked minimal edits so review is a diff. Dart gets a settings model, settings-aware rating/reminder helpers, `PlanStatus.superseded` and the new action; the desktop planning page gains a Settings section and a Revise action.

**Tech Stack:** PostgreSQL / Supabase, Dart 3, Flutter, Riverpod.

**Spec:** `docs/superpowers/specs/2026-10-20-assurance-completion-design.md` (section A9)

## Global Constraints

- Defaults: `due_soon_days` 3 (1–30), `escalate_after_days` 7 (1–90), `finding_response_days` 14 (1–90), rating bands critical ≥ 20, high ≥ 10, medium ≥ 5 (strictly descending, each 2–25), every monitoring rule enabled with `min_count` 1 (1–10000). Rule codes: `ACCESS_PRIVILEGED_NO_MFA`, `P2P_MATCH_OVERRIDE`, `P2P_OVERRIDE_BY_CREATOR`, `HR_ATTENDANCE_SELF_APPROVAL`.
- Entity row overrides the tenant row; no row → defaults. Existing risk assessments keep their recorded rating.
- Settings writes: `assurance.plan.manage`, recent MFA, idempotency key, expected version (0 creates the row at that level; null rejected).
- Settings read: `assurance.evidence.view` or `assurance.plan.manage`.
- `supersede_plan` is a creation (version 0) of a new draft plan that copies the approved plan's period and active items; at most one open revision per approved plan; approving the revision moves the old plan to terminal `superseded` in the same transaction. Engagements already created are untouched; a superseded plan creates no new occurrences.
- Same API contract, error codes and desktop sealed-draft flow as A8.
- Candidate file `supabase/candidates/20261020120000_assurance_settings.sql`; requires A1–A5, the version guard and A8 ordering in the builder (`-Slice A9` = A8 + this).

## Review Focus

1. Tenant row and entity row both present — expected: entity values win field-by-field only when the entity row exists (whole row, not per field); test in Task 1.
2. Rating bands edited after assessments exist — expected: old assessments unchanged, new ones use new bands; test in Task 1.
3. Two revisions of the same approved plan — expected: second refused `23505 ASSURANCE_PLAN_REVISION_OPEN`; test in Task 1.
4. A monitoring rule disabled after a candidate was already raised — expected: existing candidate untouched, no new one; test in Task 1.
5. Settings form with escalate days below due-soon days — allowed (different axes: before vs after due); Dart preview must still order levels correctly; test in Task 2.

---

### Task 1: Candidate migration and rollback suite

**Files:**
- Create: `supabase/candidates/20261020120000_assurance_settings.sql`
- Create: `supabase/assurance_tests/assurance_settings_test.sql`
- Modify: `supabase/tests/build_assurance_candidate.ps1` (`A9` in `ValidateSet` and every A8 condition; A9 appends this candidate and fragment), regenerate `supabase/tests/assurance_installed_test.sql` from `-Slice A9 -Pgtap`

**Interfaces (SQL, produced):**
- `assurance.settings(id uuid pk, tenant_id, legal_entity_id uuid null, due_soon_days, escalate_after_days, finding_response_days, band_critical, band_high, band_medium int, monitoring jsonb, version bigint, updated_by, updated_at)`, unique `(tenant_id, legal_entity_id) nulls not distinct`; `assurance.settings_events` immutable.
- `assurance.effective_settings(p_tenant_id uuid, p_legal_entity_id uuid) returns jsonb` → `{source:'default'|'tenant'|'entity', due_soon_days, escalate_after_days, finding_response_days, rating_bands:{critical,high,medium}, monitoring:{CODE:{enabled,min_count}}}`.
- `assurance.reminder_level(p_tenant_id, p_legal_entity_id, p_due date, p_today date) returns text`; `assurance.response_days(p_tenant_id, p_legal_entity_id) returns integer`; `assurance.risk_rating_for(p_tenant_id, p_legal_entity_id, p_score integer) returns text`; `assurance.monitoring_rules(p_kind text, p_content jsonb, p_settings jsonb)` (filters the existing two-argument rules by `enabled` and `count >= min_count`; the count is the leading integer of each rule's description source field).
- Replaced (same signatures): `assurance.work_items`, `api.assurance_overview` (adds `reminder_bands:{due_soon_days, escalate_after_days}`; `response_sla_days` now effective), `api.assurance_evidence_command`, `api.assurance_plan_command`, `assurance.plan_fixed` (allows only `approved → superseded`), `assurance.plan_action_permission`, `assurance.plan_action_fields`. Dropped: `assurance.reminder_level(date,date)`, `assurance.response_sla_days()`.
- `assurance.plans`: status check adds `superseded`; column `supersedes_plan_id uuid` (FK to plans); partial unique index one open revision per `supersedes_plan_id`.
- `api.assurance_settings(p_tenant_id, p_legal_entity_id, p_branch_id) returns jsonb` → `{effective, tenant:{version}|null, entity:{version}|null, rules:[{code, description}]}`.
- `api.assurance_settings_command(p_tenant_id, p_legal_entity_id, p_branch_id, p_idempotency_key, p_payload, p_expected_version) returns jsonb` → `{level, version, effective}`; payload exactly `level, due_soon_days, escalate_after_days, finding_response_days, rating_bands, monitoring`.

- [ ] **Step 1: Write the fragment** (≈35 assertions): defaults with no rows; tenant row overrides; entity row overrides tenant; reminder levels for due today/3 days/4 days ahead and 1/7/8 days late under defaults and under `due_soon_days 5, escalate_after_days 10`; overview `response_sla_days` follows settings; `assess_risk` with bands `{20,12,6}` rates score 10 `medium` while an earlier assessment keeps `high`; monitoring rule disabled → no new candidate, `min_count 3` with count 2 → none, count 3 → one; settings write needs `plan.manage` (auditor refused), recent MFA, version 0 then 1, stale version `40001`, null version `22023`, out-of-range values and non-descending bands `22023`, unknown monitoring rule `22023`; replay same key; `supersede_plan` on a draft → `55000`; on approved → new draft with copied items and `supersedes_plan_id`; second revision → `23505`; approve revision → old plan `superseded`, version +1, its event recorded; superseded plan cannot instantiate (`55000 ASSURANCE_PLAN_NOT_APPROVED`); `plan_fixed` still refuses any other change to an approved plan.
- [ ] **Step 2: Run the reduced suite (A1 fixtures + A3 plan fixtures from `assurance_planning_test.sql` + version guard + A4b fixture block + candidate + fragment) on the development project — expect failure (functions absent).**
- [ ] **Step 3: Write the candidate.** Copy `api.assurance_plan_command` from `20261019090000_assurance_version_guard.sql` and `api.assurance_evidence_command` from `20261018154450_assurance_adapters_monitoring.sql` verbatim, then apply only: rating via `risk_rating_for`, the `supersede_plan` branch and the approval side effect, and the three-argument `monitoring_rules` call with `assurance.effective_settings(...)->'monitoring'`. Mark each edit with `-- A9:`.
- [ ] **Step 4: Re-run; expect all pass.** Expected: `assertions = passed`.
- [ ] **Step 5: Commit** `Add assurance A9 settings candidate: tenant settings and plan revision`.

### Task 2: Domain settings and plan revision

**Files:**
- Create: `packages/jentra_domain/lib/src/assurance_settings.dart` (export it)
- Modify: `packages/jentra_domain/lib/src/assurance_planning.dart` (`PlanStatus.superseded`, `approved → {superseded}`; `supersede_plan` capability `assurance.plan.manage`, fields `plan_id, supersedes_plan_id, name`, `creates` true, validate ids + name 3–160; `assuranceRiskRating(l, i, {RatingBands bands = RatingBands.standard})`)
- Modify: `packages/jentra_domain/lib/src/assurance_workspace.dart` (`assuranceReminderLevel(due, today, {int dueSoonDays = 3, int escalateAfterDays = 7})`; `AssuranceOverview` reads optional `reminder_bands`)
- Test: `packages/jentra_domain/test/assurance_settings_test.dart`

**Interfaces (produced):**
- `final class RatingBands { const RatingBands(this.critical, this.high, this.medium); static const standard = RatingBands(20, 10, 5); AssuranceSeverity rate(int score); }` (constructor asserts nothing; `AssuranceSettings.validate` checks order).
- `typedef MonitoringThreshold = ({bool enabled, int minCount});`
- `final class AssuranceSettings { AssuranceSettings.fromJson(Map); final String source; final int dueSoonDays, escalateAfterDays, findingResponseDays; final RatingBands bands; final Map<String, MonitoringThreshold> monitoring; static const defaults; ReminderLevel level(DateTime? due, DateTime today); Map<String, Object?> toPayload(String level); }`
- `final class AssuranceSettingsPage { fromJson; final AssuranceSettings effective; final int? tenantVersion, entityVersion; final List<({String code, String description})> rules; }`
- `abstract final class AssuranceSettingsCommands { static const fields = ['level','due_soon_days','escalate_after_days','finding_response_days','rating_bands','monitoring']; static void validate(Map<String, Object?>); }`
- `bool assuranceSettingsReceiptConfirms(Map<String, Object?> r, String level, int expectedVersion)`
- `const assuranceMonitoringRuleCodes = ['ACCESS_PRIVILEGED_NO_MFA','P2P_MATCH_OVERRIDE','P2P_OVERRIDE_BY_CREATOR','HR_ATTENDANCE_SELF_APPROVAL'];`

- [ ] **Step 1: Failing tests**: defaults equal today's behaviour (existing `assuranceRiskRating` and `assuranceReminderLevel` tests still pass unchanged); custom bands rate 10 as medium under `{20,12,6}`; custom reminder bands; validation rejects out-of-range, non-descending bands, unknown rule code, extra field; `supersede_plan` creates, validates, and `PlanStatus.approved.next == {superseded}`; settings page parse rejects malformed monitoring.
- [ ] **Step 2: Run, expect failures. Step 3: Implement. Step 4: Run file and full `dart test`, `dart analyze`. Step 5: Commit** `Add assurance settings domain model and plan revision`.

### Task 3: Platform settings gateway

**Files:**
- Create: `packages/jentra_platform/lib/src/supabase_assurance_settings_gateway.dart` (export)
- Modify: `packages/jentra_platform/lib/src/supabase_assurance_gateway.dart` (messages: `ASSURANCE_PLAN_REVISION_OPEN` → "This plan already has an open revision.", `ASSURANCE_SETTINGS_INVALID` → "Check the highlighted settings.")
- Test: `packages/jentra_platform/test/assurance_settings_gateway_test.dart`

**Interfaces:** `abstract interface class AssuranceSettingsGateway { Future<AssuranceSettingsPage> settings(TenantContext scope); Future<Map<String, Object?>> saveSettings(CommandEnvelope<Map<String, Object?>> command); }` and `SupabaseAssuranceSettingsGateway` (same `_call`/denial pattern as A8; refuses null version and unconfirmed receipts).

- [ ] TDD as in A8 Task 3 (scope params, invalid read model, confirmed write, unconfirmed → `UNCERTAIN_RESULT`, invalid payload never sent, error mapping). Commit `Add assurance settings gateway`.

### Task 4: Desktop settings section and plan revision

**Files:**
- Create: `apps/jentra_desktop/lib/src/features/assurance/assurance_settings_controller.dart`, `assurance_settings_panel.dart`
- Modify: `assurance_planning_screen.dart` (section chip **Settings**; risk preview uses effective bands; approved plan shows **Revise plan**), `assurance_planning_controller.dart` (`_generated['supersede_plan'] = ['plan_id']`; open the new plan after `supersede_plan`; `settings` passed in for the rating preview), `lib/main.dart` (override `assuranceSettingsGatewayProvider`)
- Test: `apps/jentra_desktop/test/assurance_settings_test.dart`, goldens `audit_settings_{light,dark}_200.png`; extend `assurance_planning_test.dart` for revise.

**Interfaces:** `assuranceSettingsGatewayProvider`, `assuranceSettingsControllerProvider`; `AssuranceSettingsController` with `initialize()`, `edit(String level)`, `field(String key, Object? value)`, `submit()`, `discardDraft()`, `preview` (an `AssuranceSettings` built from the form for the live timeline), slot `assurance-settings-command`.

- [ ] **Failing tests**: settings show defaults with "Default" source; editing tenant level seals version 0 with whole numbers; invalid band order shows inline error and is not sent; MFA keeps the sealed request; the reminder timeline preview reflects edited days; revise on an approved plan seals `supersede_plan` at version 0 with a new `plan_id` and opens it; goldens; keyboard reaches every field.
- [ ] Implement; run file, full desktop suite, analyzer. Commit `Add audit settings and plan revision to the desktop`.

### Task 5: Docs and PR

- [ ] Status doc "Slice A9" table, verification JSON with hashes; commit; push `assurance/a9-settings`; PR against `assurance/a8-access`.
