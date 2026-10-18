# 68 — Corporate Audit & Assurance

Candidate specification, 18 October 2026. Cross-cutting capability over the
existing platform foundations. **Status: slice A1 is candidate source with
rollback-only database evidence. Nothing is installed.** See
[corporate-audit-status.md](../development/corporate-audit-status.md).

## 1. Purpose and boundary

Corporate Audit & Assurance manages business audit engagements: plans, scope,
evidence/PBC requests, test work, exceptions, findings, management responses,
remediation, independent retest, issued reports, retention and legal holds.

It is **not** the technical `audit.events` table. `audit.events` records low-level
platform actions; the new `assurance` schema records governed audit work and its
own append-only `assurance.events` history.

Reused foundations: `core.require_permission` / `core.has_permission`
(scoped role authority), JWT `aal`/`amr` claims for recent MFA, the command
receipt/idempotency pattern, forced RLS with API-only security-definer access
(as in `expense_private`), protected private storage paths, retention/legal-hold
patterns and governed export patterns.

## 2. As-is discovery (to be completed with the organisation)

The current audit process has **not** been observed. The intended workflow below
must not be assumed to describe how audits run today. Before claiming efficiency
gains, record:

| Topic | What to capture | Source |
|---|---|---|
| Audit types | internal, external, statutory, financial, operational, IT, compliance | audit charter, calendar |
| Frequency | annual plan, quarterly/monthly cycles, ad hoc | prior plans |
| Universe | auditable entities, processes, responsible departments | org chart, risk register |
| People | auditors, control owners, management reviewers, final approvers | RACI |
| Evidence | what is requested today by email/spreadsheet, formats, volumes | 2–3 prior PBC lists |
| Handoffs | approval queues, who waits on whom | interviews |
| Timing | P50/P90 processing vs waiting time per stage | prior engagement mail/dates; else instrument first |
| Quality | rework rate, most common missing evidence | prior PBC trackers |
| Retention | statutory periods, legal-hold practice | legal/compliance |
| Outputs | report templates, management-response format | prior reports |

If measured cycle times are unavailable, the stage timestamps in
`assurance.events` (FR-6812) are the instrumentation; efficiency claims wait for
real engagements.

## 3. Lifecycle

Universe & risk assessment → approved plan → engagement (entity, branch, period,
scope) → independent lead and team → control mapping → evidence/PBC requests →
collection → **freeze at explicit cutoff with digest** → testing and samples →
exceptions (not findings) → findings issued → management response / risk
acceptance → remediation → independent retest → close or reopen → immutable
report version → archive under retention and holds → unresolved findings carried
forward.

### Engagement states
`planning → fieldwork → reporting → issued → archived`; `planning|fieldwork|reporting → cancelled`;
`issued → reporting` only via `reopen_report`. `reporting → issued` only via `issue_report`.
Archiving requires every open finding to be closed, risk-accepted or carried forward.

### Evidence request states
`open → submitted → accepted`; `submitted → open` on rejection (rework counted);
`open → cancelled`. No submission or review after freeze.

### Exception states
`candidate → promoted` (by issuing a finding) or `candidate → dismissed`.

### Finding states
`issued → remediating | risk_pending`; `risk_pending → risk_accepted | remediating`;
`remediating → retest_pending`; `retest_pending → closed | remediating`;
`closed | risk_accepted → remediating` (reopen).

## 4. Functional requirements

| ID | Requirement | A1 |
|---|---|---|
| FR-6801 | Maintain audit universe items with risk assessments | open (A3) |
| FR-6802 | Approve annual/periodic audit plans with maker-checker | open (A3) |
| FR-6803 | Create engagements bound to tenant, legal entity, optional branch and period | source + rollback |
| FR-6804 | Assign lead auditor and team; external members time-bound ≤ 90 days | source + rollback |
| FR-6805 | Map controls (code, owner, risk) into an engagement | source + rollback |
| FR-6806 | Issue evidence/PBC requests with owner and due date | source + rollback |
| FR-6807 | Submit evidence metadata: source module/reference, cutoff, method, query version, SHA-256, size, classification, generated protected path | source + rollback |
| FR-6808 | Review evidence; rejection reopens and counts rework | source + rollback |
| FR-6809 | Freeze evidence at an explicit cutoff with a reproducible digest | source + rollback |
| FR-6810 | Test procedures, sample selection and test runs | domain only (sampling); tables open (A2) |
| FR-6811 | Record exceptions without auto-creating findings; continuous monitoring may only create candidates | source + rollback |
| FR-6812 | Every command writes one ordered, attributable event with from/to status and timestamp | source + rollback |
| FR-6813 | Issue findings from exceptions by someone other than the recorder | source + rollback |
| FR-6814 | Management response by the finding owner with due date; explicit risk-acceptance request | source + rollback |
| FR-6815 | Independent risk-acceptance decision | source; rollback partial (not exercised) |
| FR-6816 | Remediation evidence by owner; independent retest; failed retests retained | source + rollback |
| FR-6817 | Reopen closed or risk-accepted findings | source + rollback |
| FR-6818 | Issue immutable, versioned report with digest over cutoff, findings snapshot and summary; reopen/reissue | source + rollback |
| FR-6819 | Legal holds with segregated release | source + rollback |
| FR-6820 | Carry unresolved findings into the next cycle (`carried_from_finding_id`) | column + archive guard; rollover command open |
| FR-6821 | Automated evidence adapters (finance, procurement, inventory, workforce, IT) | open (A4) |
| FR-6822 | Governed audit-pack export with download/hash/reopen verification | open (A4) |
| FR-6823 | Templates, recurring engagements, reminders, escalations, overdue dashboards | open (A3/A5) |
| FR-6824 | Desktop "Governance & Audit" workspace | open (A5) |
| FR-6825 | Process metrics (§9) | domain calculations only |

## 5. Non-functional requirements

| ID | Requirement |
|---|---|
| NFR-6801 | Server-authoritative authorization; forced RLS; no direct table grants to `anon`, `authenticated` or `service_role` |
| NFR-6802 | Authority is checked before existence and before idempotent replay |
| NFR-6803 | High-risk commands require AAL2 with an MFA `amr` entry no older than 15 minutes |
| NFR-6804 | Every command idempotent per (actor, key) with request-hash mismatch rejection; optimistic engagement version |
| NFR-6805 | Evidence provenance, retests, report versions, events and receipts are update/delete-immutable; current-state rows are never deleted |
| NFR-6806 | No document bytes, secrets or private HR content in assurance rows; only metadata and digests |
| NFR-6807 | External reviewers never receive storage references |
| NFR-6808 | Target-scale p95 for engagement detail ≤ 500 ms at 500 tenants (to be measured) |
| NFR-6809 | Desktop: keyboard, focus, 200% text, light/dark, loading/empty/denied/error/offline states; encrypted draft recovery; no protected-evidence caching |

## 6. Permission matrix

| Capability | Actions | MFA |
|---|---|---|
| assurance.plan.manage | universe, risk assessment, plans (A3) | plan approval |
| assurance.engagement.manage | create, team add/revoke, map control, transition, freeze | freeze |
| assurance.evidence.request | request, cancel request | – |
| assurance.evidence.submit | submit evidence (request owner only) | – |
| assurance.evidence.view | read engagement detail | – |
| assurance.test.perform | record exception | – |
| assurance.test.review | review evidence, dismiss exception | – |
| assurance.finding.issue | issue finding | yes |
| assurance.response.manage | respond (finding owner only) | – |
| assurance.remediation.manage | submit remediation (finding owner only) | – |
| assurance.retest.perform | retest | yes |
| assurance.engagement.close | decide risk, reopen finding, issue/reopen report | yes |
| assurance.report.export | governed export (A4) | yes |
| assurance.retention.manage | place / release hold | release |
| assurance.external_review | time-bound read-only engagement detail | – |

The candidate grants **no business role** any of these capabilities.

### Segregation of duties (server-enforced)
- Audit team members cannot own in-scope controls or receive evidence requests; control owners cannot join the team.
- Evidence submitter ≠ evidence reviewer. Exception recorder ≠ finding issuer.
- Finding owner, remediation submitter and control owner cannot retest.
- Risk decision ≠ finding owner and ≠ issuer. Report issuer ≠ lead auditor. Hold releaser ≠ placer.
- External members are read-only regardless of role grants; expiry or revocation denies immediately.

## 7. Data contracts

API (candidate):
- `api.assurance_command(tenant, entity, branch, idempotency_key, payload, expected_version) → {engagement_id, version, status, action, aggregate_type, aggregate_id, to_status}`
- `api.assurance_engagement(tenant, entity, branch, engagement_id) → {engagement, controls, requests[evidence metadata], exceptions, findings, reports, events}`

Payload fields per action are exact allow-lists (`assurance.action_fields`,
mirrored in `AssuranceCommands.fields`). Error codes: `22023` validation,
`42501` authority/independence/MFA, `55000` state, `40001` version conflict,
`P0002` not found, `23505` duplicate.

Evidence metadata: `source_module`, `source_reference`, `source_as_of`,
`collection_method`, `query_version`, `sha256`, `byte_size` (1 B–100 MiB),
`classification`, `storage_ref = assurance/{tenant}/{engagement}/{evidence}`,
`collected_by`, `collected_at`. Chain of custody = the ordered events.

Report digest = SHA-256 of `{engagement_id, report_version, cutoff, period, findings snapshot, summary}`.
Freeze digest = SHA-256 of sorted `id:sha256:byte_size` of accepted current evidence.

## 8. Retention and privacy
- Assurance rows hold metadata and digests only; bytes live in a private bucket path generated from scope (bucket provisioning is A4).
- Workforce/HR evidence must come through existing private HR contracts and be classified `restricted`; no private HR content in event details.
- Retention policy per entity and purge are out of A1; holds block any future purge.

## 9. Process metrics
Cycle time and P50/P90 per stage (nearest-rank), processing vs waiting time,
evidence first-time-right, request aging, test completion, finding aging by
severity, overdue remediation, retest pass rate, recurrence (reopen count),
control coverage by risk, open high-risk findings, report issuance time after
fieldwork, workload/WIP. All derived from event timestamps; a metric with no
measured samples reports "not measured", never zero.

## 10. Edge cases
Missing fields fail (not skip); impossible dates; future evidence cutoff; client-chosen
storage path; duplicate idempotency key with changed body; stale version; revoked
permission replay; expired external access; freeze with outstanding requests; report
issue with unresolved candidate exceptions; reopen after issue; failed retest
followed by pass; hold release by placer; branch-scoped role reading another branch;
entity-wide viewer through wrong branch.

## 11. Out of scope for A1
Universe/plans/risk assessments, test procedure/run tables, automated adapters,
export, storage bucket, notifications/reminders, desktop UI, installation,
production deployment, real MFA, contention/load, owner sign-off.

## 12. Evidence and release matrix

| Gate | State |
|---|---|
| Domain tests | 19 pass (`test/assurance_test.dart`) |
| Candidate pgTAP rollback | 55/55, rolled back ([evidence](../verification/assurance/a1-candidate-rollback-20261018.json)) |
| Installation | not performed; requires explicit approval |
| Desktop widget/accessibility | not started |
| Export/download/reopen | not started |
| Independent-session contention | not run |
| Target-scale latency | not measured |
| Authenticated native walkthrough | not run |
| Owner sign-off | not requested |
