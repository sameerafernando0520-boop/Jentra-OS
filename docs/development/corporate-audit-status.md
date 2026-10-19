# Corporate Audit & Assurance — status, 18 October 2026

**Jentra OS remains incomplete. Corporate Audit & Assurance (A1–A5) is installed in the development project only (2026-10-18); nothing is in production.** The per-slice "Installed behaviour" rows below record the state at the time of each candidate run; the installation section near the end supersedes them.
Spec: [blueprint 68](../blueprint/68_CORPORATE_AUDIT_ASSURANCE_SPEC.md).

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
| Not done | not installed or deployed (bucket, policies, SQL functions and the edge function need owner approval); `supabase/tests/assurance_installed_test.sql` (CI) still generated from `-Slice A6`; no real Storage upload or edge-function run; reviewers have no in-app "verify" or byte download yet |

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
1. Install the two candidates (version guard, plan register) in the development project once approved, and decide which roles get `assurance.*` capabilities.
2. Reminder delivery through the existing Wave 3 notification channel, and scheduled monitoring/occurrence runs.
3. Tenant-configurable SLA, reminder bands and rule thresholds once as-is discovery is done.

## Blockers needing you
- **Role grants**: which tenant roles receive which `assurance.*` capabilities in the development project (none are granted, so the installed APIs refuse every real user). Production installation needs separate approval.
- **As-is process discovery**: prior PBC lists, audit calendar, report templates, the risk scale you use and the people/roles involved (blueprint §2). A3 uses a 5×5 likelihood × impact scale and once/semiannual/quarterly/monthly cadences as defaults until then.
- Genuine MFA, native Windows walkthrough and owner sign-off remain private-interaction gates.

Related: [readiness matrix](corporate-audit-readiness-matrix.md) ·
[verification plan](corporate-audit-verification-plan.md) ·
[installation runbook](corporate-audit-installation-runbook.md) ·
[native acceptance checklist](corporate-audit-native-acceptance.md)
