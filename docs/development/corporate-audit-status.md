# Corporate Audit & Assurance — status, 21 October 2026

**Assurance installation is recorded through A14 on development project `xpdoufauvrbdmxgngetv`; A16 presentation changes are built. Production deployment and acceptance remain open.** The per-slice rows below are historical; the installation sections supersede their original candidate-only state. No production change was made in the 21 October completion work.
Spec: [blueprint 68](../blueprint/68_CORPORATE_AUDIT_ASSURANCE_SPEC.md).

## Completion verification, 21 October 2026

- The intermittent PKCE test now controls deadline expiry after the real local
  connection reaches the stalled phase. Exact error, no-session and no-late-sign-in
  assertions remain; production authentication code is unchanged. Focused tests
  passed twice (6/6 each), the full platform suite passed 1,198/1,198 and domain
  tests passed 500/500. The complete desktop suite passed 2,145/2,145 including
  goldens; all 460 pre-existing failure images match their before-run hashes.
  Analysis of all source and tests in the desktop, domain and platform packages
  returned no issues (exit 0).
- A fresh development Windows release was built and [packaged](../../build/assurance-release-20261021/Jentra-OS-Assurance-development-Windows.zip).
  All 35 runtime files in the ZIP matched the build hashes. This is build evidence;
  authenticated native use remains pending.
- [Live development endpoint checks](../verification/assurance/dev-endpoints-20261021.json)
  passed 4/4: both evidence functions returned 401 for missing and invalid bearer
  tokens. These checks do not establish successful authenticated storage operations.
- The Firebase admin key is ignored by `*firebase-adminsdk*.json`, and is untracked.
  No credentials were read, staged or included in the package. Applied migration
  text and ledger history were preserved; the recorded final-newline difference is
  documented as nonfunctional.
- [Screen references for review](../verification/assurance/screen-review-20261021.html)
  contain 12 offline widget-test images. A focused assurance UI run passed 98 tests.
  Screen-reader, authenticated native and owner acceptance remain separate.
- The [production review packet](../verification/assurance/production-promotion-20261021.md)
  includes ordered hashes for 15 migrations and the function bundles. Production
  target, approval and acceptance are pending.

The owner authorized creating development test accounts on 21 October. The
provisioning attempt could not complete: the token environment override is invalid;
with that override temporarily omitted, the saved login receives HTTP 403 for the
explicit development project. No Supabase database tools are exposed in this chat,
and the browser dashboard connection timed out. Public
Auth settings were checked: email confirmation is required and anonymous sign-in
is disabled. Restore the administration connection before provisioning confirmed
accounts in a dedicated synthetic tenant. Do not alter existing business members
or weaken Auth settings. A resumable [fixture script](../../tools/assurance/create_dev_test_account.ps1)
retains a Windows-DPAPI-protected checkpoint under ignored `build/assurance-private/`;
it was syntax-checked and stops when project administration is unavailable. The
role/catalogue counts below were not refreshed today.

## Current-state inventory (read-only, dev project `xpdoufauvrbdmxgngetv`)

| Observed | Value |
|---|---|
| Before run | 2026-10-17 18:43:36 UTC: 115 migrations (latest `20261013184757`), 363 `api` functions, no `assurance` schema |
| After run | 2026-10-18 03:37:20 UTC: 115 / 363, no `assurance` schema, no assurance permissions, no pgTAP extension, no fixture users |
| Checkout | `main`, clean except an untracked, empty nested `Jentra-OS/` git repo (owner unknown; left untouched) |

## Slice A1 — engagement core (this session)

| Category | Result |
|---|---|
| Source changes | `supabase/candidates/20261018090000_assurance_engagement_core.sql`; `supabase/tests/assurance_core_test.sql`; `supabase/tests/build_assurance_candidate.ps1`; `packages/jentra_domain/lib/jentra_assurance.dart`, `lib/src/assurance.dart`, `test/assurance_test.dart` |
| Candidate database evidence | 55/55 pgTAP assertions in one `begin … rollback` transaction ([record](../verification/assurance/a1-candidate-rollback-20261018.json)). First attempt 53/54: one test expectation was wrong (API correctly checks authority before existence); fixed and an extra isolation case added |
| Installed behaviour | none |
| Automated tests / analyzer | `dart analyze` clean on new files; `assurance_test.dart` 19/19; full `jentra_domain` suite 417/417 |
| Native authenticated evidence | none |
| Contention / load | none |
| Visual / accessibility | none (no UI yet) |

The candidate was kept in `supabase/candidates/` until installation; it is now also in
`supabase/migrations/` under its ledger version (see the installation section).

## Slice A2 — testing and carry-forward

| Category | Result |
|---|---|
| Source changes | `supabase/candidates/20261018120000_assurance_testing_carry_forward.sql` (additive on A1); `supabase/tests/assurance_testing_test.sql`; builder `-Slice A2`; Dart `AssuranceTestCommands`, integer-exact systematic sampling, `test/assurance_testing_test.dart` |
| Candidate database evidence | 98/98 (55 A1 + 43 A2) in one rollback transaction ([record](../verification/assurance/a2-candidate-rollback-20261018.json)); first attempt aborted on a duplicated test id, fixed in the test only |
| Installed behaviour | none; post-run check 2026-10-18 04:08 UTC: 115 migrations / 363 API functions, no assurance objects |
| Automated tests | 24 assurance domain tests; full `jentra_domain` suite 422/422; analyzer clean |
| Native / contention / visual | none |

## Slice A4 — evidence adapters and audit-pack export

| Category | Result |
|---|---|
| Source changes | `supabase/candidates/20261018150000_assurance_evidence_adapters_export.sql`; `supabase/tests/assurance_evidence_test.sql`; builder `-Slice A4`; Dart `assurance_evidence.dart` (source kinds, commands, `AuditPackManifest`, `EvidenceVerification`); platform `AssurancePackVerifier` (`jentra_assurance_platform.dart`) |
| Candidate database evidence | 129/129 (55 A1 + 43 A2 + 31 A4) in one rollback transaction ([record](../verification/assurance/a4-candidate-rollback-20261018.json)); an earlier 128/128 run preceded the `manifest_text` addition and is superseded |
| Installed behaviour | none; post-run 2026-10-18 04:52 UTC: 115 / 363, no assurance objects, no synthetic finance reports left |
| Automated tests | 29 assurance domain tests (full `jentra_domain` suite green); platform verifier 3/3; analyzers clean |
| Not covered | no on-device download (adapter kinds, procurement/workforce and monitoring gaps closed in A4b below) |

## Slice A4b — procurement/workforce adapters and continuous monitoring

| Category | Result |
|---|---|
| Source changes | `supabase/candidates/20261018170000_assurance_adapters_monitoring.sql` (period snapshots `procurement.three_way_match` and `workforce.attendance_approvals`, `assurance.monitoring_hits`, four monitoring rules, `run_monitoring`); `supabase/tests/assurance_monitoring_test.sql`; builder `-Slice A4b`; Dart `assuranceSnapshotKinds`, `assuranceMonitoringRules`, `run_monitoring` contract |
| Candidate database evidence | 153/153 (55 A1 + 43 A2 + 31 A4 + 24 A4b) in one rollback transaction ([record](../verification/assurance/a4b-candidate-rollback-20261018.json)); earlier slice builds byte-identical |
| Installed behaviour | none; post-run 2026-10-18 08:26 UTC: 115 / 363, no assurance objects, no synthetic bills, suppliers, employees or periods left |
| Automated tests | 31 assurance domain tests; full `jentra_domain` suite 429/429; analyzer clean |
| Not covered | monitoring is on demand per snapshot (no scheduler); rule thresholds fixed in source; no rules for finance/inventory snapshots; real data volumes not measured |

## Slice A3 — audit universe, risk assessment, plans, templates, recurring engagements

| Category | Result |
|---|---|
| Source changes | `supabase/candidates/20261018190000_assurance_universe_plans.sql` (7 tables, `api.assurance_plan_command` with 11 actions, `api.assurance_universe`, `api.assurance_plan`); `supabase/tests/assurance_planning_test.sql`; builder `-Slice A3`; Dart `assurance_planning.dart` (`assuranceRiskRating`, `AuditFrequency`, `assuranceOccurrencePeriod`, `PlanStatus`, `assuranceTemplateValid`, `AssurancePlanCommands`) |
| Candidate database evidence | 208/208 (55 A1 + 43 A2 + 31 A4 + 24 A4b + 55 A3) in one rollback transaction, build text with comment lines removed ([record](../verification/assurance/a3-candidate-rollback-20261018.json)); earlier slice builds byte-identical |
| Installed behaviour | none; post-run 2026-10-18 09:01 UTC: 115 / 363, no assurance objects or synthetic data left |
| Automated tests | 36 assurance domain tests; full `jentra_domain` suite 434/434; analyzer clean |
| Not covered | reminders, escalations and overdue dashboards; occurrences are instantiated by explicit command (no scheduler); plan amendment after approval needs a new plan; risk scale and frequencies are defaults pending as-is discovery |

## Slice A5 — Governance & Audit desktop workspace

| Category | Result |
|---|---|
| Source changes | `supabase/candidates/20261018210000_assurance_workspace.sql` (read-only `api.assurance_engagements`, `api.assurance_overview`; no tables); `supabase/tests/assurance_workspace_test.sql`; builder `-Slice A5`; Dart `assurance_workspace.dart` (`ReminderLevel`, `AssuranceOverview`, `AssuranceEngagementPage`); platform `SupabaseAssuranceGateway`; desktop `features/assurance/` (controller, screen), route `/governance/audit`, navigation entry gated by `assurance.evidence.view` |
| Candidate database evidence | 228/228 (… + 20 A5) in one rollback transaction, build text with comment lines removed ([record](../verification/assurance/a5-candidate-rollback-20261018.json)); earlier slice builds byte-identical |
| Installed behaviour | none; post-run 2026-10-18 11:59 UTC: 115 / 363, no assurance objects or synthetic data left |
| Automated tests | 40 assurance domain tests (full `jentra_domain` 438/438); platform assurance gateway 6/6; desktop `assurance_workspace_test.dart` 13/13 including 200% light/dark goldens produced by this work; full desktop suite 2039/2039; analyzers clean on changed files |
| What the workspace does | My work (own requests and findings with reminder levels), overdue team work, engagement register, read-only engagement detail, and the finding owner's management response (encrypted local draft, sealed request retried with the same key on an uncertain outcome; version conflicts require a refresh) |
| Not covered | reminders and escalations are shown, not delivered (no notifications or scheduler); all other assurance commands (planning, evidence, testing, reporting, export) have no desktop screens yet; no authenticated Windows walkthrough; no accessibility review beyond automated renders |

## Slice A6a — auditor actions on the engagement view (desktop)

| Category | Result |
|---|---|
| Source changes | Domain `assurance_auditor.dart` (`AuditorAction` catalogue routing seven commands to `api.assurance_command` / `api.assurance_evidence_command`, receipt confirmation by aggregate and version; `AuditorEngagementView` with state- and capability-based availability that mirrors the server rules); `AssuranceEvent` now accepts the A2 test and A4/A4b evidence actions that engagement histories already contain (previously an engagement with testing or collection could not be opened). Platform `auditorCommand` and `auditPack` (manifest read and hashed on device); independence refusals map to `SEGREGATION_OF_DUTIES_VIOLATION` instead of lost access. Desktop: request evidence, collect a system snapshot, review evidence, record/dismiss exceptions, issue findings and export the audit pack from the engagement view; each is an encrypted draft sealed with generated ids and the engagement version and retried with the same key; only a pack that hashes to its recorded digest can be saved |
| Candidate / installed database evidence | none new — no SQL changed; uses the installed A1–A5 APIs |
| Automated tests | domain 446/446 (8 new); platform assurance gateway 9/9; desktop `assurance_workspace_test.dart` 22/22 including new 200% light/dark goldens `governance_engagement_*_200.png` produced by this work; analyzers clean on changed files |
| Not covered | test design/execution/review screens, planning screens, freeze/issue report/risk decision/retest screens, non-snapshot evidence sources (need a source picker); reminder delivery; no authenticated Windows walkthrough, genuine MFA or accessibility review |

## Slice A7 — audit planning screens (desktop)

| Category | Result |
|---|---|
| Source changes | New desktop page **Audit planning** (`/governance/audit/planning`, shown with `assurance.plan.manage` or `assurance.evidence.view`): audit universe with ratings (register area, assess risk with a live rating preview, retire area), current engagement templates, the plan register, and plan detail (add/remove areas, submit, maker-checker decide with MFA, cancel, create the next planned occurrence as an engagement). Every change is an encrypted draft sealed with generated ids and the aggregate's version (0 to create), retried with the same key. Domain `assurance_plan_view.dart` (`AssuranceUniverse`, `AssurancePlanPage`, `AssurancePlanDetail`, availability rules, receipt confirmation); platform `universe`, `plans`, `plan`, `planCommand` |
| Candidate database evidence | `supabase/candidates/20261019130000_assurance_plan_register.sql` adds read-only `api.assurance_plans` (paged, scope-bound, same authority as `api.assurance_plan`); no table or existing function changes. Its 8 assertions run in CI inside `assurance_installed_test.sql` (`-Slice A6 -Pgtap`, 244 assertions). **Not installed**: until it is, the plan register is empty in the development project |
| Automated tests | domain 6 new planning-view tests; platform assurance gateway 11/11; desktop `assurance_planning_test.dart` 9/9 including new 200% light/dark goldens `audit_planning_*_200.png` produced by this work |
| Not covered | template authoring (templates are listed and referenced, not created); owners and lead auditors are entered as user IDs because no member directory API exists; no authenticated Windows walkthrough or genuine MFA |

## Slice A6b — engagement stages, tests, reports and finding decisions (desktop)

| Category | Result |
|---|---|
| Source changes | Domain `AuditorAction` gains `transition`, `freeze_evidence`, `issue_report`, `reopen_report`, `decide_risk`, `retest`, `reopen_finding` (engagement API) and `design_test`, `execute_test`, `review_test` (test API); `AuditorEngagementView` reads findings, the lead auditor and test procedures (`api.assurance_tests`) and mirrors the server rules (lead-only freeze once requests are settled; report issued by someone other than the lead after candidate exceptions are resolved; owners never decide, retest or reopen their own findings; tests run only on frozen fieldwork evidence, cover the recorded sample, and are reviewed by someone other than the runner). Platform `tests()` read. Desktop: stage, freeze and report actions on the engagement, a Tests section, finding actions, and the matching sealed command forms (whole-number fields sent as numbers) |
| Database evidence | none new — no SQL changed; uses the installed A1/A2 APIs |
| Automated tests | domain 454/454 (7 new A6b tests); platform assurance gateway 10/10; desktop `assurance_workspace_test.dart` 25/25, engagement 200% light/dark goldens regenerated for the new Design test action and Tests section |
| Not covered | planning screens (universe, risk assessment, plans, templates, instantiation); digests for workpapers and retest evidence are typed, not computed from a chosen file; reminder delivery; no authenticated Windows walkthrough or genuine MFA |

## PR #1 review and first CI run (19 October 2026)

| Category | Result |
|---|---|
| Version guard | Review found that a null `p_expected_version` skipped every version check (`version <> null` is null). Candidate `supabase/candidates/20261019090000_assurance_version_guard.sql` replaces `api.assurance_command`, `assurance.prepare_command` and `api.assurance_plan_command` with the installed bodies changed only to reject a null version (creation requires exactly 0). **Not installed**; the development project still has the bypass until an installation is approved |
| CI pgTAP | `supabase test db` runs each file alone, so the assurance fragments moved to `supabase/assurance_tests/` and the builder generates `supabase/tests/assurance_installed_test.sql` (`-Slice A6 -Pgtap`: installed A1–A5 suites plus the guard candidate and its 8 assertions, 236 in all, ending in rollback). 94 older Wave 3–5 pgTAP files also fail under `supabase test db` (no plan / per-statement transactions); they are not changed here |
| Formatting | 80 older Dart files reformatted (formatting only) plus braces on two `if` statements the reformat wrapped, so the format and analyze steps pass |
| Metrics | evidence-stage durations now count system collection as the submission |
| Export | the desktop offers audit-pack export for issued engagements only; archived engagements stay read-only |
| Known gap | manual `submit_evidence` records a caller-supplied digest without a stored object; no storage bucket or upload verification exists yet. Addressed by the A7 candidate below (not installed) |

## Slice A7 — evidence storage and byte verification (candidate, 19 October 2026)

| Category | Result |
|---|---|
| Problem | PR #1 thread 4309904782: manual `submit_evidence` recorded a caller-supplied SHA-256 and size for `assurance/{tenant}/{engagement}/{evidence}` with no bucket, no `storage.objects` policy and no check that bytes existed, so never-stored evidence could be accepted, frozen and exported |
| Mechanism | Candidate `supabase/candidates/20261019120000_assurance_evidence_storage.sql`. Private bucket `jentra-assurance-evidence` (100 MiB) whose object names are exactly the generated references. `storage.objects` policies: only the request owner, holding `assurance.evidence.submit`, may insert — once — at the path of their own submitted, unfrozen, unverified item; restrictive guards forbid client update/delete and keep other policies from opening the bucket; only the uploader can see the row. SQL cannot read Storage bytes, so edge function `assurance-evidence-verify` downloads the object with the service key, hashes every byte (streamed) and calls service-only `api.assurance_evidence_service_verify`, using a five-minute one-use ticket the human obtained through `api.assurance_evidence_verification_ticket` with their own session (request owner, or lead/auditor/reviewer with `assurance.test.review`; external reviewers refused). The immutable `assurance.evidence_verifications` row records the outcome (`verified` / `mismatch`), observed digest and size, and the object's id, version and update time |
| Gate | Triggers refuse `review_evidence` acceptance (and `freeze_evidence`) for any item on the upload path unless a `verified` record matches the claimed digest and size and the current object is still the one that was hashed (`55000 ASSURANCE_EVIDENCE_UNVERIFIED`). Server-collected adapter evidence never uses the upload path and is unaffected. `api.assurance_command` is not replaced, so the candidate is independent of the version-guard candidate. The item is still created at submission (the path embeds its id, which the upload policy needs); what the review asked to prevent — acceptance, freeze and export of unstored evidence — is blocked at acceptance |
| Client | Domain `assurance_evidence_upload.dart` (`manualEvidencePayload`, `StoredEvidenceVerification`, `EvidenceVerificationStatus`, bucket MIME list; `AssuranceWorkItem.canSubmitEvidence`). Platform `submitManualEvidence` (sealed command → `uploadBinary` with `upsert: false`, an existing object continues to verification → verify), `verifyEvidence`, `evidenceVerification`, native picker `NativeAssuranceEvidenceFiles`; the unverified refusal maps to a clear validation message. Desktop: "Upload evidence" on the owner's open requests, sealed in the `assurance-evidence-upload` draft slot; a retry must use the same file and reuses the same key |
| Candidate database evidence | reduced rollback suite on the development project, 39/39, nothing installed ([record](../verification/assurance/a7-evidence-storage-rollback-20261019.json)); builder slice `-Slice A7` added (full A1–A6 + guard + A7 output generated, not executed) |
| Automated tests | edge function `node --test supabase/functions/tests/` 32/32 (7 new); domain, platform and desktop suites — see the PR description for the run |
| Not done | not installed or deployed (bucket, policies, SQL functions and the edge function need owner approval); no real Storage upload or edge-function run; reviewers have no in-app "verify" or byte download yet. CI moved to `-Slice A8` in slice A8 below |

## Slice A8 — access (candidate, 20 October 2026)

Design: [completion spec](../superpowers/specs/2026-10-20-assurance-completion-design.md) · plan: [A8 plan](../superpowers/plans/2026-10-20-assurance-a8-access.md).

| Category | Result |
|---|---|
| Problem | Tenants created before assurance was installed held no `assurance.*` permission on any role (development: the one `tenant_owner` role held 0), so every real user was refused; the desktop had no way to give an existing member a role |
| Mechanism | Candidate `supabase/candidates/20261020090000_assurance_access.sql`. `assurance.seed_roles(tenant)` grants every assurance permission to the tenant's `tenant_owner` role and seeds five system roles — Audit lead, Auditor, Reviewer (MFA), Process owner, External reviewer (no MFA) — run for every trial or active tenant and by a trigger on new tenants. Every seeded role that holds a privileged permission requires MFA. `api.assurance_access` pages members (50) with their assurance roles and scope (tenant-wide role managers, or planners and engagement managers read-only, e.g. for people pickers); labels are the linked employee name or "Unlinked member ····1234", never a login e-mail. `api.assurance_set_role` grants or revokes one of the five roles organisation-wide, entity-wide or for the current branch: tenant-wide `core.roles.manage`, recent MFA, idempotent receipt, per-membership version in `assurance.access_versions`, one immutable `assurance.access_events` row per change |
| Client | Domain `assurance_access.dart` (`AssuranceRole`, `AccessScope`, `AssuranceAccess`, `AssuranceAccessCommands`, receipt confirmation). Platform `AssuranceAccessGateway` / `SupabaseAssuranceAccessGateway` (separate from `AssuranceGateway`). Desktop page **Audit access** (`/governance/audit/access`, shown with `core.roles.manage`): role cards with plain descriptions and MFA badges, member list with role chips, a change card (give/remove, role, scope, consequence text) sealed in the `assurance-access-command` draft slot |
| Candidate database evidence | reduced rollback suite on the development project: 40/41, the failure was a test defect (it matched a hand-made development role, see below); corrected assertion re-checked 1/1, so 41/41; nothing installed ([record](../verification/assurance/a8-access-rollback-20261020.json)). The full cumulative suite runs in CI: `assurance_installed_test.sql` is now generated from `-Slice A8 -Pgtap`, which also brings the A7 evidence-storage assertions into CI |
| Automated tests | domain 472/472 (5 new); platform 1173/1173 + 7 new access gateway tests; desktop assurance 48/48 (10 new, 200% light/dark goldens, keyboard focus); analyzers clean |
| Observed on development | role `assurance_all_dev` (not a system role, no MFA) grants every privileged assurance permission; the `ACCESS_PRIVILEGED_NO_MFA` monitoring rule would report it. Left untouched |
| A7 defect found by CI | moving CI to `-Slice A8` ran the A7 evidence-storage candidate in full for the first time: `assurance.live_object` was delimited with `$` instead of `$$` (a syntax error; the candidate's earlier reduced run did not include it as committed). Fixed in the candidate; the corrected definitions were compiled on the development project in a rolled-back transaction. The A7 rollback record's hash refers to the pre-fix file |
| Not done | not installed; no real member has been given a role yet |

## Slice A9 — tenant settings and plan revision (candidate, 20 October 2026)

Plan: [A9 plan](../superpowers/plans/2026-10-20-assurance-a9-settings.md).

| Category | Result |
|---|---|
| Problem | Reminder bands (3/7 days), the 14-day finding-response deadline, risk-rating bands (20/10/5) and monitoring triggers (any occurrence) were fixed in source; an approved plan could only be replaced by a new plan |
| Mechanism | Candidate `supabase/candidates/20261020120000_assurance_settings.sql`. `assurance.settings` per tenant with an optional legal-entity row that replaces it as a whole; no row means today's values. `assurance.effective_settings`, tenant-aware `reminder_level`, `response_days`, `risk_rating_for` and a three-argument `monitoring_rules` (rule on/off and minimum occurrences). `api.assurance_settings` (planners or evidence viewers) and `api.assurance_settings_command` (planners, recent MFA, versioned, immutable `assurance.settings_events`). Replaced with marked `-- A9` edits only: `assurance.work_items`, `api.assurance_overview` (adds `reminder_bands`), `api.assurance_evidence_command` (monitoring thresholds), `api.assurance_plan_command` (version-guard body: settings-aware rating, `supersede_plan`). Risk assessments now record the bands they were rated with (`rating_bands`) and the rating check validates against them. Plans gain `superseded` and `supersedes_plan_id`; one open revision per approved plan; approving the revision supersedes the original in the same transaction |
| Client | Domain `assurance_settings.dart` (`AssuranceSettings`, `AssuranceSettingsPage`, commands, receipt check), `RatingBands`, settings-aware `assuranceReminderLevel`; the overview parser accepts tenant deadlines (1–90 days) and verifies levels with the reported bands, so a tenant that changes its settings keeps a working workspace; `PlanStatus.superseded`, `supersede_plan`, `AssurancePlanDetail.canRevise`. Platform `AssuranceSettingsGateway`. Desktop: Audit planning **Settings** section (summary with source badge; editor for the organisation or this entity with inline validation and a live reminder/rating preview, sealed in `assurance-settings-command`) and **Revise plan** on approved plans |
| Candidate database evidence | reduced rollback suite on the development project: first run aborted on the installed fixed-band rating check (fixed as above), second run 44/44; nothing installed ([record](../verification/assurance/a9-settings-rollback-20261020.json)). CI generated from `-Slice A9 -Pgtap` |
| Automated tests | domain 481/481; platform 1179/1179; desktop assurance 59/59 (new settings goldens at 200% light/dark, keyboard reaches every field); analyzers clean |
| Not done | not installed; defaults stay until a planner saves settings; as-is discovery may change the defaults themselves |

## Slice A10 — reminders and the notification inbox (candidate, 20 October 2026)

Plan: [A10 plan](../superpowers/plans/2026-10-20-assurance-a10-reminders.md).

| Category | Result |
|---|---|
| Problem | Reminder levels were only shown on the workspace; nothing reached the people responsible, and the shell's notification bell was a placeholder (always showing a dot, never clickable) with a hard-coded "SA" avatar |
| Mechanism | Candidate `supabase/candidates/20261020150000_assurance_reminders.sql`: `api.assurance_scan_reminders` (engagement managers in scope) pages the scope's due-soon, overdue and escalated work (A9 `work_items`, 100 per call) into `workflow.notifications` of type `assurance.reminder`, one per item, level and recipient (partial unique index `assurance_reminder_identity`): the owner always, the engagement lead too for escalations; titles and bodies name the engagement and item kind only and link to the engagement (`aggregate_type = 'assurance_engagement'`); idempotent receipts |
| Client | Domain `InboxNotice`, `ReminderScan`. Platform `NotificationInboxGateway` (`api.my_notifications`, `api.mark_notification_read`) and `AssuranceReminderGateway`. Desktop: shell **inbox** (unread badge, newest-first list, mark read / mark all read, reminders open their engagement via `/governance/audit?engagement=…`), avatar with the signed-in person's initials and name/e-mail tooltip; Governance & Audit **Overdue** summary cards (replacing the duplicate count chips), **Send reminders** for engagement leads, and an automatic scan on the first visit of the day per scope (device-local log) |
| Candidate database evidence | reduced rollback suite on the development project: 15/15 after a test-precedence fix; nothing installed ([record](../verification/assurance/a10-reminders-rollback-20261020.json)). CI generated from `-Slice A10 -Pgtap` |
| Automated tests | domain and platform inbox/scan tests; desktop workspace 35/35 (reminders, deep link) and inbox 9/9 with 200% light/dark goldens; workspace goldens refreshed for the summary cards; analyzers clean |
| Not done | not installed; no scheduler — reminders go out when a lead opens the workspace or presses Send reminders; e-mail delivery is out of scope |

## Slice A11 — process metrics (candidate, 20 October 2026)

Plan: [A11 plan](../superpowers/plans/2026-10-20-assurance-a11-metrics.md).

| Category | Result |
|---|---|
| Problem | Nothing measured how audits run: time in each stage, how long evidence waits, how much work is finished, how findings age, or who holds the open work (blueprint §9, FR-6825) |
| Mechanism | Candidate `supabase/candidates/20261020180000_assurance_metrics.sql`: `api.assurance_metrics(tenant, entity, branch, from, to)` (`assurance.evidence.view`; a range of at most 366 days, else `ASSURANCE_RANGE_INVALID`) over the engagements whose period overlaps the range, from immutable events and current state. Stage, issuance, evidence waiting and review times as nearest-rank median and 90th percentile; first-time-right, test completion, control coverage, retest pass rate and recurrence as rates; open-request ageing bands; finding age by severity; overdue remediation and open high-risk counts; workload for up to ten owners labelled by name or "Unlinked member ····1234", never an e-mail. Every value carries its sample count, and no samples means null ("not measured"), never zero |
| Client | Domain `AssuranceMetrics` (fails closed on a value without samples, percentiles out of order, a rate out of range, ageing that does not add up, or an e-mail label). Platform `AssuranceMetricsGateway` (checks the range before sending and that the answer is for the period asked). Desktop **Audit metrics** (`/governance/audit/metrics`, evidence viewers): 30-day / 90-day / 12-month periods ending today, sections for stages, evidence, testing, findings and workload; each card shows the value with its unit, the samples behind it and a one-line definition; columns narrow as text grows so nothing truncates at 200% |
| Candidate database evidence | reduced rollback suite on the development project: 24/24 at the first GREEN run; nothing installed ([record](../verification/assurance/a11-metrics-rollback-20261020.json)). CI generated from `-Slice A11 -Pgtap` |
| Automated tests | domain 4/4, platform gateway 4/4, desktop metrics 11/11 (period dates, stale answers discarded, access loss, offline, unmeasured values, empty period, keyboard reach, 200% light/dark goldens); analyzers clean |
| Not done | not installed; metrics are computed on request (no snapshots or trend lines); engagement-level drill-down is left for later |

## Slice A12 — reviewer evidence (candidate, 20 October 2026)

Plan: [A12 plan](../superpowers/plans/2026-10-20-assurance-a12-reviewer-evidence.md).

| Category | Result |
|---|---|
| Problem | Reviewers could see an uploaded file's digest but never the file, and the desktop had no way to ask the server to re-hash a submission before accepting it |
| Mechanism | Candidate `supabase/candidates/20261020210000_assurance_evidence_download.sql`: `api.assurance_evidence_download_ticket` (evidence viewers, or a current external team member through the A1 time-bound path; authority before lookup) issues a five-minute, one-use ticket only for an uploaded item whose stored object is still the `verified` version. Edge function `assurance-evidence-download` redeems it with the service key through `api.assurance_evidence_service_download`, which re-checks the ticket, membership and verification, and signs a 60-second URL for the generated path. Tickets are the download log (consume-only, never deleted) |
| Client | Domain `EvidenceDownloadTicket` (https only, at most five minutes, size bounded) and `assuranceEvidenceFileName` (last path segment, Windows-safe). Platform `AssuranceEvidenceDownloadGateway` fetches the signed URL without the session header, reads at most one byte past the recorded size, hashes on the device and returns the bytes only on an exact SHA-256 and size match, also against the digest the reviewer saw. Desktop engagement view: uploaded evidence rows show the file name, **Verify file** (owner or reviewer, while submitted) and **Download** (viewers); a mismatch saves nothing and says so |
| Candidate database evidence | reduced rollback suite on the development project: 59/59 (39 A7 storage, 20 A12) after a test-ordering fix; nothing installed ([record](../verification/assurance/a12-reviewer-evidence-rollback-20261020.json)). CI generated from `-Slice A12 -Pgtap` |
| Automated tests | edge functions `node --test` 12/12; domain download 3/3 and auditor view (upload fields, verify/download rules); platform download 4/4; desktop workspace 39/39; full desktop suite 2115/2115; analyzers clean |
| Not done | not installed; the edge function is not deployed and has no `config.toml` entry yet (installation step); external reviewers cannot open the desktop workspace, so their download path is server-side only |

## Slice A13 — digest domain tests (20 October 2026)

Plan: [A13 plan](../superpowers/plans/2026-10-20-assurance-a13-digests.md).

| Category | Result |
|---|---|
| Problem | The evidence cutoff digest (FR-6809) and the issued report digest (FR-6818) existed only in SQL; no client could recompute them |
| Mechanism | `jentra_domain` builds the exact texts the server hashes: `assuranceFreezeDigestText` (`id:sha256:byte_size`, ordered by id, comma-joined; refuses an empty set as the server does) and `assuranceReportDigestText` (the `jsonb::text` of the report document through `assuranceJsonbText`, which follows PostgreSQL's key order and string escaping). `jentra_platform` hashes them: `assuranceFreezeDigest`, `assuranceReportDigest` |
| Evidence | expected texts and digests produced by the server's own SQL over literal fixtures (quotes, backslashes, tabs, newlines, a control character, non-ASCII), read-only on the development project ([record](../verification/assurance/a13-digests-20261020.json)); domain 4/4 equal texts, platform 2/2 equal digests |
| Not done | the desktop does not yet recompute a report digest on screen (the engagement view carries current findings, not the issued snapshot) |

## Slice A14 — UI/UX and accessibility pass (20 October 2026)

Plan and findings: [A14 plan](../superpowers/plans/2026-10-20-assurance-a14-ux.md) (design critique and WCAG 2.1 AA review of the Governance workspace, engagement detail, Audit planning, Audit access, Audit metrics and the inbox).

| Category | Result |
|---|---|
| Problem | Planning asked for raw user IDs; engagement detail printed full 64-character digests, raw status codes and ISO timestamps; reminder chips used colours unlike the summary cards; an uncovered high-risk area was shown by red text only; section titles were not announced as headings; discarding an encrypted draft did not ask |
| Mechanism | Candidate `supabase/candidates/20261020230000_assurance_people.sql`: `api.assurance_people` (planners, engagement managers or role managers) lists the tenant's active members as `{user_id, label}`, labels being employee names or "Unlinked member ····1234", never e-mails, at most 500 |
| Client | Domain `AssurancePeople`; platform `AssurancePeopleGateway`. Desktop: area owner and lead auditor are chosen by name (typed id only if the list cannot be read); `assurance_format.dart` gives one date style ("8 Oct 2026"), UTC-labelled event times, sentence-case labels and `DigestText` (short digest, full value in a tooltip and selectable, announced as "SHA-256 starting …"); reminder badges use the summary card tones; "Not covered" warning badge; "Approve or return"; section headings carry header semantics; "Discard draft" confirms what is lost |
| Candidate database evidence | reduced rollback suite on the development project: 9/9; nothing installed ([record](../verification/assurance/a14-people-rollback-20261020.json)). CI generated from `-Slice A14 -Pgtap` |
| Automated tests | domain people 2/2 (500 in total); platform people 2/2; desktop format 3/3, workspace 42/42, planning 12/12; goldens refreshed only for the intentional changes (governance work and engagement, audit planning; light and dark) |
| Not done | contrast was checked from tokens, not on a device; no screen-reader walkthrough (NVDA/Narrator) yet |

## Installation — development project, 20 October 2026 (A15)

Plan: [A15 plan](../superpowers/plans/2026-10-20-assurance-a15-install.md).

| Category | Result |
|---|---|
| Authority | owner decision in this session: development project `xpdoufauvrbdmxgngetv` only, after each slice's rollback suite; production not touched |
| Installed | nine migrations through `apply_migration`, in candidate order: `20261020072622` version guard, `20261020072800` evidence storage, `20261020072901` plan register, `20261020073016` access (A8), `20261020073524` settings (A9), `20261020093705` reminders (A10), `20261020093743` metrics (A11), `20261020093817` evidence download (A12), `20261020093822` people (A14). Ledger text equals each candidate byte for byte (plan register: except the final newline); repository copies in `supabase/migrations/` |
| Edge functions | `assurance-evidence-verify` and `assurance-evidence-download` deployed (version 1). Authentication happens inside the function (`withSupabase({ auth: "user" })`), as for the deployed people-private functions; an unauthenticated call returns 401. `config.toml` entries added |
| Post-install check | 130 migrations; 31 assurance tables, all forcing RLS, no client table grants; 26 `api.assurance*` functions, none executable by `anon`, the three service steps service-only; no assurance helper callable by clients; assurance roles seeded in all 501 trial or active tenants and the new-tenant trigger present; private 100 MiB evidence bucket with its six storage policies; security advisor: only the informational "RLS enabled, no policy" on assurance tables (by design) ([record](../verification/assurance/installation-dev-20261020.json)) |
| Installed suite | `build_assurance_candidate.ps1 -Installed` now strips every installed candidate and expects 31 tables; CI runs it against the migrations |
| Not established | no member holds an assurance role yet (seeded, not granted); no native authenticated walkthrough, genuine MFA, real upload through the functions, contention/load or owner acceptance |

## Slice A16 — UI/UX polish (20 October 2026)

Plan: [A16 plan](../superpowers/plans/2026-10-20-assurance-a16-ux-polish.md). Owner's review of the built product chose four changes (date pickers, card layouts, empty and error states, header consistency); roles, settings, reminders and metrics stay as built.

| Category | Result |
|---|---|
| Problem | Dates were typed as `YYYY-MM-DD`; the work queue, engagement register, engagement detail and planning lists were plain text rows; access loss, no data, offline and failed loads were single lines of text; the workspace and planning headers differed from Audit access and Audit metrics |
| Client | `assurance_widgets.dart`: `AuditDateField` (calendar picker shown as "8 Oct 2026", stores the same civil date, opens from the keyboard, an end date never before its start), `AuditScreenHeader` (title, description, refresh icon button with tooltip, section chips) now used by all four audit screens, `AuditItemPanel` (design-system panel with status badges, details, digest and actions; openable items are one keyboard-reachable button), `auditTone`/`auditBadge` (one tone per status), `AuditNotice` (wrapping offline, error and confirmation lines) and `AuditNotLoaded`. Workspace and planning use `JentraEmptyState` for no access, access changed, nothing assigned, no overdue team work, no engagements, no audit areas, no plans, offline and failed loads, each with a next step. `JentraSectionHeader` titles now carry header semantics |
| Behaviour | unchanged: the same commands, payloads, drafts and dates (`YYYY-MM-DD`) |
| Automated tests | desktop widgets 11/11, workspace 48/48, planning 17/17; goldens refreshed only for the intentional changes (governance work and engagement, audit planning; light and dark) |
| Not done | no screen-reader walkthrough (NVDA/Narrator) yet; not checked on a native Windows build |

## Installation — development project, 18 October 2026

| Category | Result |
|---|---|
| Authority | owner approval given in the development session; development project `xpdoufauvrbdmxgngetv` only |
| Preconditions | ledger 115 (latest `20261013184757`); candidate hashes matched; A5 rollback suite 228/228 the same day |
| Installed | six migrations through `apply_migration`: `20261018153931` A1, `20261018154123` A2, `20261018154309` A4, `20261018154450` A4b, `20261018155008` A3, `20261018155041` A5; repository copies in `supabase/migrations/` (byte-identical to the candidates). Ledger text equals the files except SQL comments (executable text identical) |
| Post-install check | 121 migrations; 24 assurance tables all forcing RLS, no table grants; 12 `api.assurance*` functions, authenticated only; 375 `api` functions; 15 `assurance.*` permissions, granted to no role; helpers not client-callable; no pgTAP |
| Installed suite | `build_assurance_candidate.ps1 -Slice A5 -Installed`: 228/228 against the installed schema, rolled back; no fixtures, engagements, receipts or universe items left ([record](../verification/assurance/installation-dev-20261018.json)) |
| Not established | real users still have no assurance capability (no role grants); no native authenticated use, genuine MFA, contention/load or owner acceptance; production not touched |

## Next unblocked slices
1. Give real members assurance roles in the development project (Audit access, or the seeded roles directly) and walk through plan → engagement → evidence upload → verify → accept → freeze → report → export natively.
2. Scheduled reminders and monitoring runs (reminders go out today when a lead opens the workspace or presses Send reminders).
3. Report-digest check on screen (A13 gives the client the digest; the engagement view would need the issued findings snapshot).

## Blockers needing you
- **Production installation** needs its own approval and window.
- **As-is process discovery**: prior PBC lists, audit calendar, report templates, the risk scale you use and the people/roles involved (blueprint §2). Defaults are configurable per tenant and entity (A9) until then.
- Genuine MFA, native Windows walkthrough and owner sign-off remain private-interaction gates.

Related: [readiness matrix](corporate-audit-readiness-matrix.md) ·
[verification plan](corporate-audit-verification-plan.md) ·
[installation runbook](corporate-audit-installation-runbook.md) ·
[native acceptance checklist](corporate-audit-native-acceptance.md)
