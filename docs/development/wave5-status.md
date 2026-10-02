# Wave 5 session status

Updated 2026-09-30, Asia/Colombo. The owner approved the Wave 5 and W5-01
contracts by requesting “continue”. The isolated W5-01 domain calculation and
platform SHA-256 adapter are implemented and verified. No full Wave 5 or W5-01
native/installed acceptance is claimed.

## Reviewable starting point

- [Wave 5 intelligence and control specification](../blueprint/wave5/WAVE5_INTELLIGENCE_AND_CONTROL_SPEC.md)
  defines scope, exact evidence, permissions, human AI approval, integrations,
  synthetic SaaS control, operator isolation, and eight delivery slices.
- [W5-01 process metric contract](../blueprint/wave5/W5_01_PROCESS_METRICS_CONTRACT.md)
  starts with independent exact domain calculations. Both documents are Approved.

The engineering spec-driven workflow's approval gate is satisfied for this
specification and W5-01. Later slices still require their detailed contracts;
installation, external services and production retain their stated boundaries.

## Parallel-session ownership

At kickoff, the existing chats `Start Wave` (Wave 4) and `Complete Wave 3
verification` were active. The continuation snapshot found Wave 4 interrupted/
idle and Wave 3 active; both chats' source ownership remains protected. This
session inspected state without messaging either chat.
The shared checkout is dirty and must be preserved. The source preflight was
`main`, HEAD `f9cc342815e2446fb3f26204d5e65e03c1b2a140`.
HEAD and provider fingerprints must be refreshed before implementation because
other chats can continue changing them.

This session owns new paths in `docs/blueprint/wave5/`,
`docs/development/wave5-status.md`, `docs/verification/wave5/`,
`packages/jentra_domain/lib/analytics.dart`, the domain `src/analytics/` and
`test/analytics/` directories, `packages/jentra_platform/lib/analytics_platform.dart`,
and the platform `src/analytics/` and `test/analytics/` directories.
Existing Wave 3/4 source, migrations, docs, tests, evidence, running app,
authentication and shared main/router/navigation remain under their current
owners. No stage, commit, push, migration application or deployment occurred
in this session.

## September 30 live development preflight

Read-only Supabase checks against `xpdoufauvrbdmxgngetv` found 37 installed
migrations, last `20260929224939_wave4_private_hr`. The installed ledger includes
process telemetry, CRM pipeline, employee/calendar and private-HR foundations.

`workflow.process_events` and `api.process_events` exist. The base table has
enabled/forced RLS; the view has `security_invoker=true`. The API includes
`get_crm_pipeline_summary`. Basic billing plans, entitlements and subscriptions
exist. The `ai` schema exists; its presence is not proof of Wave 5 AI delivery.
No `analytics` schema was present. Specific probes for supplier-bill controls,
attendance intervals and payroll runs returned absent. Provider completeness,
semantic completeness, authenticated access and runtime remain unverified.
The capability probe verified `analytics.view`, `workflow.process.view` and CRM
source permissions. It found no entitlement using the proposed exact code
`analytics`; synthetic setup remains a named server-integration gate.

## Proceeding order

| Work | Current state / next step |
|---|---|
| Wave 5 contract | Approved by owner “continue” on September 30 |
| W5-01 exact process domain | Implemented; 25 focused tests, full domain regression 194/194, clean analysis; 95.06% branch coverage |
| W5-01 SHA-256 adapter | Implemented using existing cryptography dependency; 8/8 platform tests including independent Python vectors and tampering |
| W5-01 adapter/native | Follow domain, producer semantic/permission checks and additive candidate tests |
| Pipeline forecasts | New slice contract and verified historical CRM basis required |
| Financial ratios/cash forecast | Exact domain design can proceed after approval; installed authoritative finance/obligation providers gate integration |
| AI proposal controls | Provider-neutral contract/state machine first; live provider/execution remains explicitly gated |
| Webhook/API | Injected tests first; credentials/egress and real deliveries need separate authorization |
| Plans/trials/metering | Synthetic controls only; existing billing authority remains the provider |
| Operator dashboard | Separate access/health contract required; tenant owner access is insufficient |
| Full acceptance | Installed providers, authenticated native/restart, real contention/load, workers and owner signoff remain open |

Document-validation evidence is kept in [the Wave 5 verification folder](../verification/wave5/).
Specification validation is evidence about documentation, not deployed behavior.

Strict validation passed for both contracts at 100/100 with zero findings.
All 46 functional and 14 non-functional requirements map to the 25 acceptance
criteria; both documents define 24 edge cases in total. Identifier continuity,
Given/When/Then structure, all 12 local links and conflict-marker checks passed.
The report is `spec-validation-20260930.json` in the verification folder.
The calculation validates complete immutable source manifests, exact UTC and
numeric(20,6) minute strings, scope, row/window bounds, unique identities and
canonical SHA-256 evidence before computing nearest-rank P50/P90 in BigInt
microseconds. Empty, zero, open, invalid and excluded observations remain
distinct. Stage dwell/throughput/work/rework measures remain explicitly
uncertified. Verification does not grant source permissions.

The platform uses the existing `cryptography` dependency through a pure domain
hashing port. No dependency manifest or lockfile was changed. Full domain
regression passed 194 tests with zero failures/skips; focused platform passed
8 tests. New domain/platform analysis has zero findings. Coverage of the new
calculation is 242/246 lines (98.37%) and 77/81 branches (95.06%).

The refreshed before/after installed ledger remains at 37 migrations through
`20260929224939_wave4_private_hr`. This session made no database mutation.
The next step is the bounded permission-aware server provider and its candidate
tests, followed by the native workspace and recovery. SQL, native widget/render,
Windows build, installation, real authenticated runtime and target-scale load
are not yet verified for W5-01.

See [the process-foundation checkpoint](../verification/wave5/process-foundation-20260930.md)
for commands, exact source evidence and remaining acceptance gates.
