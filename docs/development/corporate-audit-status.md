# Corporate Audit & Assurance — status, 18 October 2026

**Jentra OS remains incomplete. Corporate Audit & Assurance is candidate source only; nothing is installed.**
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

The candidate is deliberately in `supabase/candidates/`, not `supabase/migrations/`,
so the local migration folder still matches the live 115-migration ledger.

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
| Candidate database evidence | 208/208 (55 A1 + 43 A2 + 31 A4 + 24 A4b + 55 A3) in one rollback transaction, exact build text ([record](../verification/assurance/a3-candidate-rollback-20261018.json)); earlier slice builds byte-identical |
| Installed behaviour | none; post-run 2026-10-18 09:01 UTC: 115 / 363, no assurance objects or synthetic data left |
| Automated tests | 36 assurance domain tests; full `jentra_domain` suite 434/434; analyzer clean |
| Not covered | reminders, escalations and overdue dashboards; occurrences are instantiated by explicit command (no scheduler); plan amendment after approval needs a new plan; risk scale and frequencies are defaults pending as-is discovery |

## Slice A5 — Governance & Audit desktop workspace

| Category | Result |
|---|---|
| Source changes | `supabase/candidates/20261018210000_assurance_workspace.sql` (read-only `api.assurance_engagements`, `api.assurance_overview`; no tables); `supabase/tests/assurance_workspace_test.sql`; builder `-Slice A5`; Dart `assurance_workspace.dart` (`ReminderLevel`, `AssuranceOverview`, `AssuranceEngagementPage`); platform `SupabaseAssuranceGateway`; desktop `features/assurance/` (controller, screen), route `/governance/audit`, navigation entry gated by `assurance.evidence.view` |
| Candidate database evidence | 228/228 (… + 20 A5) in one rollback transaction, exact build text ([record](../verification/assurance/a5-candidate-rollback-20261018.json)); earlier slice builds byte-identical |
| Installed behaviour | none; post-run 2026-10-18 11:59 UTC: 115 / 363, no assurance objects or synthetic data left |
| Automated tests | 40 assurance domain tests (full `jentra_domain` 438/438); platform assurance gateway 6/6; desktop `assurance_workspace_test.dart` 13/13 including 200% light/dark goldens produced by this work; full desktop suite 2039/2039; analyzers clean on changed files |
| What the workspace does | My work (own requests and findings with reminder levels), overdue team work, engagement register, read-only engagement detail, and the finding owner's management response (encrypted local draft, sealed request retried with the same key on an uncertain outcome; version conflicts require a refresh) |
| Not covered | reminders and escalations are shown, not delivered (no notifications or scheduler); all other assurance commands (planning, evidence, testing, reporting, export) have no desktop screens yet; no authenticated Windows walkthrough; no accessibility review beyond automated renders |

## Next unblocked slices
1. Desktop screens for the remaining assurance roles: auditor evidence requests and review, testing, findings issue, planning (A3) and audit-pack export with the platform verifier.
2. Reminder delivery through the existing Wave 3 notification channel, and scheduled monitoring/occurrence runs.
3. Tenant-configurable SLA, reminder bands and rule thresholds once as-is discovery is done.

## Blockers needing you
- **Installation approval** for the candidate (runbook below). Not requested yet; it would cover A1 + A2 + A4 + A4b + A3 + A5 together.
- **As-is process discovery**: prior PBC lists, audit calendar, report templates, the risk scale you use and the people/roles involved (blueprint §2). A3 uses a 5×5 likelihood × impact scale and once/semiannual/quarterly/monthly cadences as defaults until then.
- Genuine MFA, native Windows walkthrough and owner sign-off remain private-interaction gates.

Related: [readiness matrix](corporate-audit-readiness-matrix.md) ·
[verification plan](corporate-audit-verification-plan.md) ·
[installation runbook](corporate-audit-installation-runbook.md) ·
[native acceptance checklist](corporate-audit-native-acceptance.md)
