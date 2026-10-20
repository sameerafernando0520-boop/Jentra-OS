# Corporate Audit & Assurance — completion design (A8–A15)

Date: 2026-10-20 · Base: `assurance/a7-planning-screens` (PR #5) ·
Spec: [blueprint 68](../../blueprint/68_CORPORATE_AUDIT_ASSURANCE_SPEC.md) ·
Status before: [corporate-audit-status.md](../../development/corporate-audit-status.md)

## Intent

Make the assurance module usable by real people in the development project and
finish the remaining requirements, with a desktop app that is analyzer-clean
and fully tested, and with a deliberate UI/UX pass.

Decisions made by the owner (2026-10-20):

| Question | Decision |
|---|---|
| Installation | Install each candidate and the evidence edge functions to the **development project only** (`xpdoufauvrbdmxgngetv`) after its rollback suite passes; never production |
| Role grants | Existing tenant owners get every assurance permission (as a new tenant's owner already does) **and** five assignable assurance roles are seeded |
| Reminder scheduling | On demand (button) plus an automatic, idempotent scan when an authorised user opens the workspace; no new infrastructure |
| As-is defaults | Keep today's values as defaults, made configurable per tenant |

Out of reach for this work (stay with the owner): genuine MFA, signing in to the
native app with real credentials, owner sign-off, production, contention/load
tests against the shared project, as-is process discovery content.

## Delivery shape

One stacked branch and pull request per slice, in this order, each with its own
candidate migration (`supabase/candidates/`), rollback pgTAP fragment
(`supabase/assurance_tests/`), builder slice in `build_assurance_candidate.ps1`,
Dart tests and 200% light/dark goldens where it adds UI. A slice is installed
to the development project only after its rollback suite passes there.

| Slice | Branch | Depends on |
|---|---|---|
| A8 Access | `assurance/a8-access` | A7 (PR #5) |
| A9 Settings and plan revision | `assurance/a9-settings` | A8 |
| A10 Reminders and notification inbox | `assurance/a10-reminders` | A9 (levels read settings) |
| A11 Process metrics | `assurance/a11-metrics` | A9 |
| A12 Reviewer evidence | `assurance/a12-evidence-review` | A7 evidence storage |
| A13 Digest domain tests | `assurance/a13-digests` | — |
| A14 UI/UX pass | `assurance/a14-ux` | A8–A12 screens |
| A15 Finish and install | `assurance/a15-install` | all |

Shared contract for every new API (unchanged from A1–A7): `security definer`,
`search_path = ''`, authority checked before existence and before idempotent
replay, forced RLS, no table grants, `authenticated`-only execute. Errors:
`22023` validation, `42501` authority/independence/MFA, `55000` state,
`40001` version conflict, `P0002` not found, `23505` duplicate. Writes take an
idempotency key and expected version (0 to create; null rejected, as in the
version-guard candidate). Desktop writes are encrypted drafts sealed with
generated ids and the aggregate version, retried with the same key, confirmed
by the receipt's aggregate and version.

## A8 — Access

**Problem.** Tenants created before assurance was installed have no
`assurance.*` permission on any role, so every real user is refused. New
tenants' owners already receive every permission at onboarding. The desktop
has no screen to give an existing member a role (roles are only given through
invitations or onboarding).

**Database (candidate `20261020090000_assurance_access.sql`).**
- Grant every `assurance.*` permission to each existing `tenant_owner` role
  (`on conflict do nothing`), matching onboarding.
- Seed five system roles per tenant (`is_system = true`), for existing tenants
  and, through an `after insert` trigger on `core.tenants`, for new ones:

| Code | Name | Permissions | `requires_mfa` |
|---|---|---|---|
| `assurance_lead` | Audit lead | plan.manage, engagement.manage, evidence.request, evidence.view, test.perform, test.review, finding.issue, engagement.close, report.export, retention.manage | true |
| `assurance_auditor` | Auditor | evidence.request, evidence.view, test.perform, finding.issue | true |
| `assurance_reviewer` | Reviewer | evidence.view, test.review, retest.perform, engagement.close | true |
| `assurance_process_owner` | Process owner | evidence.submit, evidence.view, response.manage, remediation.manage | false |
| `assurance_external` | External reviewer | external_review | false |

  Every role holding a privileged permission requires MFA, so the existing
  `ACCESS_PRIVILEGED_NO_MFA` monitoring rule stays quiet for seeded roles.
  Independence rules (issuer ≠ recorder, owner never decides own finding,
  reviewer ≠ runner) are enforced per engagement by the existing commands, not
  by role separation.
- `api.assurance_access(tenant)` — read. Requires `core.roles.manage`. Returns
  active members (`membership_id`; the linked employee's display name when the
  account is linked through `people_private.account_links`, otherwise
  "Unlinked member" and the last four characters of the membership id — never
  a login e-mail, following `api.people_hr_memberships`; status) with the
  assurance role codes they hold and the scope of each assignment, plus the
  five role definitions. Paged by membership id (50).
- `api.assurance_set_role(tenant, idempotency_key, payload{membership_id, role_code, granted, legal_entity_id?, branch_id?}, expected_version)`
  — requires `core.roles.manage` and recent MFA; `role_code` must be one of the
  five; granting is idempotent per (membership, role, scope); revoking an
  absent assignment is `P0002`. Writes one receipt and one audit event.
  Version is the membership's assurance-access version (stored in a new
  `assurance.access_versions` row per membership, 0 when none).

**Desktop.** New page **Audit access** (`/governance/audit/access`, shown with
`core.roles.manage`): member list with role chips, a role legend explaining
what each role can do, grant/revoke through a sealed command, MFA prompt on
`42501` MFA refusal, empty state when the tenant has one member.

**Tests.** Rollback fragment `assurance_access_test.sql` (owner backfill,
seeded roles and MFA flags, new-tenant trigger, read/write authority, MFA,
idempotency, version conflict, non-assurance role refused, branch scope).
Domain parser and command tests; platform gateway tests; desktop controller,
widget and goldens.

## A9 — Tenant settings and plan revision

**Settings table** `assurance.settings` (tenant, optional legal entity;
entity row overrides tenant row; defaults apply when no row exists):

| Field | Default | Range |
|---|---|---|
| `due_soon_days` | 3 | 1–30 |
| `escalate_after_days` | 7 | 1–90 |
| `finding_response_days` | 14 | 1–90 |
| `rating_bands` | critical ≥ 20, high ≥ 10, medium ≥ 5 | strictly descending, 2–25 |
| `monitoring` | every rule enabled, `min_count` 1 | per rule code: enabled bool, min_count 1–10000 |

- `assurance.effective_settings(tenant, entity)` resolves defaults.
- `assurance.reminder_level(tenant, entity, due, today)` replaces the two-argument
  version; `api.assurance_engagements` and `api.assurance_overview` are
  recreated with identical output shape using it. The old function is dropped
  after its callers move.
- Risk rating in `assess_risk` uses the effective bands; existing assessments
  keep the rating they were recorded with (no recomputation).
- `assurance.monitoring_rules` gains a settings argument; disabled rules and
  counts below `min_count` produce no candidate.
- `api.assurance_settings(tenant, entity)` read (`assurance.evidence.view`);
  `api.assurance_settings_command(... payload, expected_version)` write
  (`assurance.plan.manage`, recent MFA), with exact allow-listed fields.

**Plan revision.** New plan action `supersede_plan` (`assurance.plan.manage`)
on an approved plan creates a new draft plan with the same period and a copy
of its active items, `supersedes_plan_id` set. When that draft is approved the
old plan moves to a new terminal status `superseded` in the same transaction.
An approved plan may have at most one open revision. Engagements already
instantiated from the old plan are untouched.

**Desktop.** Audit planning gains a **Settings** tab (form with inline
validation, live preview of a reminder timeline and rating bands) and a
**Revise plan** action on approved plans. The Dart rating preview and
reminder-level helpers read the effective settings.

## A10 — Reminders and notification inbox

**Database.** `api.assurance_scan_reminders(tenant, entity, branch, command_id, idempotency_key, client_timestamp, payload{as_of, after_id?})`,
modelled on `api.scan_wave3_due_notifications`:
- Requires `assurance.engagement.manage` in scope.
- Scans open evidence requests and unanswered or open findings in scope (100
  per call, cursor `after_id`), computes the level from effective settings,
  and for `due_soon`, `overdue` and `escalated` inserts one
  `workflow.notifications` row of type `assurance.reminder` to the item owner;
  `escalated` also notifies the engagement lead.
- Unique index on (tenant, recipient, type, `source_context->>'due_key'`) with
  `due_key = item_id:level` — each item notifies each recipient once per level.
- Notice text names the engagement and item kind only; no evidence content.
- Receipt returns `examined`, `emitted`, `has_more`, `next_after`.

**Desktop shell (app-wide).**
- The notification bell becomes a real inbox: unread count badge (hidden at
  0), a popover list from `api.my_notifications` (newest first, 20 per page),
  mark-as-read via `api.mark_notification_read`, "mark all read", and a link
  that opens the engagement for `assurance.reminder` notices.
- The hard-coded avatar initials are replaced by the signed-in user's
  initials, with their name and e-mail in a tooltip.

**Workspace.** An **Overdue** summary card (counts by level from the existing
overview), a **Send reminders** button for leads, and an automatic scan at most
once per day per scope when a lead opens the workspace (last run date kept per
scope on the device; the server is idempotent regardless).

## A11 — Process metrics (FR-6825)

`api.assurance_metrics(tenant, entity, branch, from, to)` (requires
`assurance.evidence.view`) derives every blueprint §9 metric from immutable
events and current state, over engagements whose period overlaps `[from, to]`:

- cycle time per engagement stage, P50 and P90 (nearest rank, `percentile_disc`);
- evidence waiting vs review time (request → first submission → acceptance);
- evidence first-time-right (accepted with zero rework ÷ accepted);
- request ageing buckets (0–7, 8–30, 31+ days open);
- test completion (reviewed runs ÷ designed tests);
- finding ageing by severity, overdue remediation count;
- retest pass rate; recurrence (reopen count);
- control coverage by risk (controls with at least one reviewed test ÷ controls);
- open high-risk findings; report issuance time after fieldwork;
- workload / WIP per assignee (open requests and findings).

Every metric returns `{value, samples}`; `value` is null when `samples = 0`.
Dart parser mirrors the shape and keeps `assurancePercentile` as the reference
implementation (cross-checked against SQL in tests). Desktop page **Audit
metrics** (`/governance/audit/metrics`): period picker, metric cards grouped
by stage, "Not measured" for null values (never 0), and plain-language
definitions on each card.

## A12 — Reviewer evidence

- `api.assurance_evidence_download_ticket(tenant, entity, branch, engagement_id, evidence_id)`
  — evidence viewers on the engagement (external reviewers through the
  existing time-bound path); only uploaded items with a `verified` record;
  returns a five-minute one-use ticket.
- Edge function `assurance-evidence-download` redeems the ticket with the
  service key, checks the stored object is still the verified version and
  returns a 60-second signed URL. Node tests in `supabase/functions/tests/`.
- Desktop: on each uploaded evidence item, **Verify** (calls the existing
  `verifyEvidence`) and **Download** (fetch, hash on device, save only when the
  SHA-256 and size match the recorded digest, else a clear mismatch error).
- CI: `assurance_installed_test.sql` is generated from the latest slice
  (A7 and later) so evidence-storage assertions run in CI.

## A13 — Digest domain tests

Dart functions `assuranceFreezeDigest` (sorted `id:sha256:byte_size` of
accepted current evidence) and `assuranceReportDigest` (canonical JSON of
engagement id, report version, cutoff, period, findings snapshot, summary)
with fixtures whose expected digests are produced by the SQL in a rollback run
and recorded in the test. Closes the domain gap for FR-6809 and FR-6818.

## A14 — UI/UX pass

Run the design-critique and accessibility-review skills over Governance
workspace, engagement detail, Audit planning, Audit access, Audit metrics and
the shell inbox. Fix in place:
- empty, loading and error states with a next step on every screen;
- keyboard order and visible focus; every icon button has a tooltip and
  semantics label;
- 200% text scale without clipping; light and dark contrast at WCAG AA;
- consistent use of `jentra_design_system` spacing, status colours and chips;
- destructive or MFA actions confirm with the consequence stated.
Goldens refreshed only for intentional changes.

## A15 — Finish and install

- Every package: analyzer clean, full test suites passing
  (`jentra_domain`, `jentra_platform`, `jentra_design_system`,
  `jentra_desktop`, `jentra_employee`), edge-function node tests passing.
- Development project, in order: version guard (`20261019090000`), evidence
  storage (`20261019120000`), plan register (`20261019130000`), then A8–A12
  candidates and the two edge functions. For each: rollback suite first,
  `apply_migration`, repository copy in `supabase/migrations/`, then the
  installed suite rolled back; record JSON under
  `docs/verification/assurance/`.
- Update the status doc and readiness matrix.

## Testing summary

| Layer | Evidence per slice |
|---|---|
| SQL | rollback pgTAP fragment, cumulative builder slice, CI generated from the latest slice |
| Edge functions | `node --test supabase/functions/tests/` |
| Domain | parser, command allow-lists, calculations |
| Platform | gateway request/response mapping, error mapping |
| Desktop | controller tests, widget tests, 200% light/dark goldens, keyboard focus |
