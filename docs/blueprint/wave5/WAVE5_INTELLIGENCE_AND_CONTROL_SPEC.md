# Spec: Wave 5 Intelligence and Control

**Author:** Jentra OS Engineering  
**Date:** 2026-09-30  
**Status:** Approved  
**Reviewer:** Product owner; approval expressed by “continue” on 2026-09-30  
**Environment:** Synthetic development only; `xpdoufauvrbdmxgngetv`  
**Related documents:** [Roadmap](../05_TEST_AND_DELIVERY.md),
[architecture](../01_ARCHITECTURE.md), [security](../03_DATA_SECURITY.md),
[process blueprint](../02_DOMAIN_AND_PROCESS.md),
[Wave 3](../08_WAVE3_INTEGRATED_COMMERCE_FINANCE_SPEC.md),
[Wave 4](../40_WAVE4_WORKFORCE_AND_DELIVERY_SPEC.md),
[first slice](W5_01_PROCESS_METRICS_CONTRACT.md),
[session status](../../development/wave5-status.md).

## Context

The approved roadmap assigns Wave 5 cycle-time analytics, pipeline and forecast
metrics, financial ratios, cash forecasts, AI proposals and approvals, webhooks
and APIs, plans, trials, metering, and operator dashboards. The owner asked to
start this wave while Waves 3 and 4 continue in separate sessions. This document
turns that roadmap into a development contract. The owner's subsequent
“continue” approves this specification and W5-01 implementation. This approval
does not change the acceptance status of earlier waves.

The September 30 read-only preflight found 37 installed development migrations,
including employee/calendar foundations and specifically approved private HR.
`workflow.process_events` and its security-invoker `api.process_events` view,
`api.get_crm_pipeline_summary`, and basic billing plan/subscription/entitlement
tables are installed. The process table has enabled and forced RLS. No
`analytics` schema was present. Checked supplier-bill controls, attendance
intervals, and payroll-run relations were absent. Relation names are contract
probes, not an exhaustive assertion that an entire module is absent.

This supports parallel specification and isolated domain development. It does
not establish the completeness of process timing data, historical opportunity
values, authenticated access, or candidate finance/workforce providers. Wave 3
already owns operational dashboard counts, dated aging and control reports;
Wave 5 consumes those contracts rather than building another ledger or taking
over their files. New reports distinguish unavailable data from a valid zero.

The active chats share `C:\Users\sheha\Desktop\Jentra OS`. Their source,
migrations, runtime, authentication, and evidence remain owned by those chats.
This session initially adds only Wave 5 documents. After approval, it starts
with new process-metric domain files; composition-root changes wait for a
stable integration boundary.

## Functional Requirements

### Shared evidence and analytics

- FR-501: Every query, job, proposal, integration, and command MUST carry a
  tenant and its applicable entity/branch scope, resolved against live
  membership rather than client-supplied actor or role claims.
- FR-502: Every authoritative command MUST reuse the existing authenticated
  command, optimistic-version, receipt, audit, and outbox infrastructure;
  identical retries MUST not duplicate its effects.
- FR-503: Each metric MUST require its analytics capability, entitlement, and
  every underlying source permission; lost access MUST invalidate displayed
  evidence and prevent saved-result reopen or drill-through.
- FR-504: Analytics projections MUST exclude private HR, credentials, payment
  details, unrestricted audit payloads, and raw free-text reasons by default;
  authorized private data MUST require a separately reviewed projection.
- FR-505: Every metric result MUST identify definition version, unit, scope,
  filters, business cutoff, recorded cutoff, source versions, generation time,
  population counts, completeness, and drill-through basis.
- FR-506: Process analytics MUST use immutable recorded transitions and an
  explicit cohort; events recorded after the captured cutoff MUST not alter
  that result, and current document status MUST not substitute for history.
- FR-507: Duration percentiles MUST use the published percentile definition;
  open, invalid, missing, and unsupported observations MUST remain visible in
  completeness counts, and default-zero activity fields MUST not imply measured
  productive work, rework, or waiting.
- FR-508: Analytics reads MUST bound time range, source rows, groups, output,
  and pages; a limit breach MUST fail explicitly without a partial total.

### Pipeline, finance, and forecasts

- FR-509: Pipeline conversion, aging, coverage, velocity, and owner metrics
  MUST publish their cohorts and history basis; unavailable historical amount,
  probability, ownership, or stage evidence MUST block the affected metric.
- FR-510: Pipeline forecasts MUST freeze opportunity revisions, explicit
  probability/close-date assumptions, currency, and any approved FX-rate version;
  different currencies MUST not be silently summed.
- FR-511: Forecast accuracy MUST compare a frozen forecast with a defined
  realized-result cohort and horizon; zero denominators and missing mappings
  MUST produce a named unavailable state rather than infinity or fabricated zero.
- FR-512: Financial ratios MUST reference exact authoritative statement
  snapshots, governed account classifications, and versioned formulas using the
  same scope, period, currency, and publication basis.
- FR-513: Cash forecasts MUST consume verified bank/cash controls and dated
  remaining obligations, excluding duplicate allocations and explicitly
  separating receivables, payables, payroll, and unsupported obligation kinds.
- FR-514: Forecast scenarios MUST preserve immutable versions of assumptions
  and overrides; a projected balance MUST never post or amend a journal,
  obligation, stock movement, or source document.
- FR-515: Frozen metric/forecast exports MUST reuse governed report/export
  infrastructure and recheck current permissions on creation, download, and
  reopen; every export MUST preserve its calculation and source basis.

### Human-controlled AI

- FR-516: AI retrieval MUST use an allowlist of scoped read tools and redact
  disallowed fields before any provider invocation; retrieved text MUST not
  grant permissions, choose tools, or override the application policy.
- FR-517: An AI action MUST first create an immutable proposal revision
  containing its allowlisted command, target revisions, parameter hash,
  evidence references, explanation, expiry, and estimated resource budget.
- FR-518: Proposal approval MUST be an explicit online human decision bound
  to that exact revision/hash; a distinct approver with the required capability
  and MFA MUST approve a material mutation, and any edit MUST invalidate approval.
- FR-519: Execution MUST recheck approval, expiry, live source revisions,
  scope, permissions, entitlement, and limits, then invoke the existing business
  command once; AI MUST not run arbitrary SQL or bypass its posting checks.
- FR-520: AI quota reservations and usage settlement MUST be recorded by a
  trusted worker using a unique invocation identity; provider retries and
  uncertain completion MUST not silently double-charge usage or execute twice.

### Integrations and SaaS control

- FR-521: Webhook endpoints MUST have scoped registration, allowlisted event
  types, versioned contracts, server-held rotating secrets, and validated HTTPS
  destinations that exclude private, loopback, metadata, and redirected unsafe
  addresses.
- FR-522: Webhook deliveries MUST derive from committed outbox events, keep
  stable event and attempt identities, sign the exact payload, use bounded
  retries, and retain dead-letter/replay evidence without promising exactly-once
  receipt by an external consumer.
- FR-523: External API requests MUST use revocable, expiring, scoped server
  credentials and named allowlisted commands; schema/version validation,
  idempotency, throttling, and live entitlement checks MUST precede mutation.
- FR-524: Plan, trial, seat, and entitlement changes MUST be versioned,
  effective-dated, privileged and audited; synthetic trials MUST have an
  explicit start/end and MUST not enable real subscriptions or paid billing.
- FR-525: Metering MUST use append-only trusted-source usage events with
  deduplicated event identities and reasoned correction records; client reports
  MUST not be authoritative billable usage.
- FR-526: Enforced quotas and seats MUST use atomic reservations/settlement
  and explicit over-limit states; concurrent requests MUST not exceed a hard
  limit, and a denied command MUST not consume a business effect.
- FR-527: Operator dashboards MUST expose only a separately authorized
  operational projection; a tenant owner role MUST not grant cross-tenant
  operator access, and business rows MUST remain outside default health views.
- FR-528: Operator access to a selected tenant MUST require an explicit
  reasoned, expiring, MFA-protected access grant with immutable access audit;
  service-role credentials MUST remain absent from the desktop application.
- FR-529: Operator health MUST show bounded worker lag, retry/dead-letter
  counts, quota states, and contract readiness with generation timestamps;
  missing probes MUST be labelled unknown and MUST not imply healthy delivery.

### Native delivery and concurrency

- FR-530: Native Analytics, AI, integration, subscription, and authorized
  operator workspaces MUST offer scoped filters, source explanations, keyboard
  access, and distinct empty, denied, conflict, stale, and unavailable states.
- FR-531: Saved filters, scenario drafts, and uncertain command envelopes
  MUST use the existing encrypted actor/context-bound recovery store; sign-out
  or access loss MUST lock them, and offline recovery MUST not authorize execution.
- FR-532: Every provider adapter MUST advertise its supported contract
  revision and readiness; missing or incompatible providers MUST block only
  dependent operations and MUST not turn fixture data into live evidence.
- FR-533: Wave 5 development MUST use additive owned paths, preserve concurrent
  Wave 3/4 work, and refresh source ownership before changing any shared
  composition, authorization, report, workflow, or finance contract.
- FR-534: Candidate SQL verification MUST capture the installed ledger and
  provider fingerprints and end with `rollback;`; installation/deployment MUST
  have a separately recorded owner-authorized target and migration/function list.
- FR-535: Analytics/AI notifications and delivery exports MUST reuse existing
  workflow/file/outbox contracts and preserve source permissions; an outbox row
  MUST not be presented as proof of external delivery.
- FR-536: Completion reports MUST distinguish source checks, domain/platform/
  SQL/widget verification, Windows build, installed state, authenticated runtime,
  actual contention/load, external workers, and owner acceptance.

## Non-Functional Requirements

- NFR-501: Every tenant-bearing base table MUST enable and force RLS; every
  new view/RPC/job/export MUST pass foreign-ID, cross-tenant, cross-branch,
  source-permission-loss, and anonymous-denial cases with zero leaked results.
- NFR-502: Monetary values, ratios, probabilities, usage amounts, and durations
  MUST use decimal strings and exact integer/decimal arithmetic; zero binary
  floating-point financial calculations are permitted.
- NFR-503: Interactive pages MUST default to 50 rows and cap at 200;
  synchronous calculations MUST cap at 10,000 source rows, 100 groups, 366 days,
  and 8 MiB serialized output, unless a later approved slice sets tighter bounds.
- NFR-504: Indexed ordinary reads MUST meet p95 below 500 ms and ordinary
  commands below 1.5 s at the published workload on the reference environment;
  target-scale evidence MUST cover 500 tenants and 2,000 concurrent sessions.
- NFR-505: Larger allowed work MUST use bounded resumable jobs with explicit
  cancellation/failure state and at most 1,000 rows per committed chunk;
  synchronous bounded analytic calculations MUST target p95 below 3 s.
- NFR-506: At least 100 duplicate requests and independent overlapping-session
  tests MUST demonstrate one authoritative effect per command/invocation/event
  and no hard-quota overshoot; sequential SQL MUST not count as contention proof.
- NFR-507: Secret/PII checks of client binaries, exports, prompts and logs MUST
  find zero prohibited fields; access-revocation tests MUST clear visible evidence
  before another protected read or action is possible.
- NFR-508: Native views MUST support light/dark, both densities, keyboard focus,
  and 200% text at 1024x720, 1440x900, and 1920x1080 without inaccessible actions.
- NFR-509: Analysis MUST report zero warnings/errors; critical changed domain
  branches MUST target at least 90% coverage, with deterministic fixtures for
  every acceptance criterion and edge case.
- NFR-510: Identical validated source snapshots and definition versions MUST
  reproduce identical metric values irrespective of input ordering; historical
  replay MUST preserve recorded cutoff and current authorization checks.

## Acceptance Criteria

### AC-501: Scoped source access (FR-501, FR-503, FR-504, NFR-501, NFR-507)
Given permitted and forbidden identities across two tenants and branches
When a metric, job, drill-through, or saved result is requested and access changes
Then only currently permitted projections are returned and protected evidence is cleared.

### AC-502: Reproducible metric basis (FR-505, FR-506, FR-507, NFR-502, NFR-510)
Given a fixed transition cohort with late records, open events, and missing timing semantics
When duration metrics are calculated twice with reordered inputs
Then values and completeness counts match and unsupported measures remain unavailable.

### AC-503: Bounded calculations (FR-508, NFR-503, NFR-504, NFR-505)
Given limit-boundary datasets and a published reference workload
When reads, calculations, or jobs execute
Then limits reject excess atomically and measured latency meets the stated budget.

### AC-504: Pipeline evidence and accuracy (FR-509, FR-510, FR-511, NFR-502)
Given frozen opportunities, currencies, assumptions, forecasts, and realized cohorts
When conversion, forecast, and accuracy are requested
Then totals follow the published basis and missing history or zero denominators are explicit.

### AC-505: Financial ratios (FR-512, NFR-502)
Given authoritative statement snapshots with matching scope and formula revisions
When a ratio is calculated
Then its exact numerator, denominator, value, and source evidence are reproducible.

### AC-506: Cash scenarios and governed export (FR-513, FR-514, FR-515)
Given verified dated controls, residual obligations, and an editable scenario
When a forecast is frozen and exported and permission is later revoked
Then projected cash reconciles to its inputs without ledger effects and reopen is denied.

### AC-507: Scoped AI retrieval (FR-516, NFR-507)
Given malicious source text, private fields, and an unconfigured model provider
When scoped retrieval and a model request are attempted
Then only allowlisted redacted evidence is eligible and absent providers do not fabricate output.

### AC-508: Approval binds the proposed action (FR-517, FR-518)
Given a proposal with target versions, expiry and exact parameter hash
When the proposer self-approves, another user approves, or an approved revision is edited
Then self-approval is denied and only the unchanged separately approved revision is executable.

### AC-509: Safe execution and AI usage (FR-502, FR-519, FR-520, NFR-506)
Given an approved proposal, retries, uncertain provider completion, and a stale target
When overlapping execution requests occur
Then the existing business command validates live state and creates at most one effect/usage settlement.

### AC-510: Webhook delivery (FR-521, FR-522, FR-535)
Given a committed event, invalid destinations, rotating keys, and a failing consumer
When delivery, retry and authorized replay run
Then unsafe targets are rejected and signed bounded attempts retain one stable event identity.

### AC-511: External API access (FR-523, NFR-501)
Given expiring scoped credentials, a foreign target and duplicate named commands
When API requests arrive
Then invalid credentials/scopes fail before mutation and valid retries share the original receipt.

### AC-512: Synthetic plans and trials (FR-524, FR-532)
Given a synthetic tenant, scheduled plan changes and trial expiry
When effective capabilities are resolved before and after the boundary
Then entitlements follow audited versions and unsupported providers remain unavailable.

### AC-513: Metering and hard limits (FR-525, FR-526, NFR-506)
Given duplicate trusted usage events, correction records, and concurrent quota reservations
When usage and remaining allowance are resolved
Then history stays immutable and counted effects do not exceed the configured hard cap.

### AC-514: Operator isolation (FR-527, FR-528, FR-529, NFR-501, NFR-507)
Given a tenant owner, an operator and an expiring tenant-access grant
When each opens health or tenant evidence
Then only permitted projections appear and unknown probes remain unknown with audited access.

### AC-515: Native recovery and usability (FR-530, FR-531, NFR-508)
Given pending filters/scenario/command drafts and native theme/density/text variants
When the app restarts, changes context, loses access, or disconnects
Then encrypted recovery and reachable actions preserve scope without executing an offline mutation.

### AC-516: Concurrent development boundary (FR-533, FR-534)
Given an active Wave 3/4 checkout and installed-development ledger
When Wave 5 changes and candidate verification occur
Then owned paths remain attributable and candidate effects roll back without implicit installation.

### AC-517: Honest evidence report (FR-536, NFR-509)
Given the slice's source, automated, build, runtime, worker, and owner evidence
When its completion status is reported
Then each gate is named separately and unsupported acceptance claims are absent.

## Edge Cases

- EC-501: Tenant/entity/branch mismatch or permission loss during a running job
  causes denial/cleared evidence, including report download; verify with AC-501.
- EC-502: A late-recorded event, an unclosed event, tied timestamps, or a
  zero-duration event follows explicit cutoff/cohort rules; verify with AC-502.
- EC-503: Telemetry lacks certified stage-visit, active-work, or rework semantics;
  unavailable measures remain distinct from reported zero; verify with AC-502.
- EC-504: Empty samples, mixed currencies, negative/zero denominator, missing
  FX or historical opportunity revision do not fabricate ratios; verify with AC-504/505.
- EC-505: A settlement, reversal, credit, payroll liability or absent AP provider
  would double-count or omit an obligation; fail the affected forecast basis;
  verify with AC-506.
- EC-506: Changed scenario inputs or report permissions invalidate reuse and
  download, while earlier frozen authorized evidence remains unchanged;
  verify with AC-506/501.
- EC-507: Retrieved prompt injection, unavailable model, exhausted quota, or
  unknown provider outcome cannot authorize execution; verify with AC-507/509.
- EC-508: Approval expires, proposer equals approver, target changes, or MFA
  assurance drops; deny execution and retain proposal/decision; verify with AC-508/509.
- EC-509: Consumer timeout, duplicate success, invalid signature, DNS rebinding,
  or a redirect to a private address retains bounded delivery evidence;
  verify with AC-510.
- EC-510: Credential rotation/revocation, stale schema, and replay with changed
  payload reject safely before a domain effect; verify with AC-511.
- EC-511: Trial expiry and overlapping seat/usage reservations use server UTC
  and live effective versions, including a correction of prior usage;
  verify with AC-512/513.
- EC-512: Operator grant expires mid-read or health probes stop reporting;
  deny tenant evidence and display unknown readiness; verify with AC-514.
- EC-513: Secure store failure, sign-out, context switch, stale response or
  disk-full preserves recoverable ciphertext without stale protected display;
  verify with AC-515.
- EC-514: Date-range/source/group/output limit, job crash, cancellation or
  unavailable database worker returns a named state without partial total;
  verify with AC-503.
- EC-515: A parallel chat changes a shared provider signature or source file;
  refresh ownership/fingerprint before integration; verify with AC-516.
- EC-516: A passing fixture suite lacks installed, authenticated, external or
  contention proof; status retains these open gates; verify with AC-517.

## API Contracts

These are proposed contracts, not claims of deployed endpoints. Existing command
envelope/error conventions remain authoritative. Detailed downstream slice
contracts must define their exact permission codes, payloads, state machine,
bounds, and provider compatibility before those slices are implemented.

```typescript
interface Wave5Scope {
  tenantId: string;
  legalEntityId: string;
  branchId: string | null;
}
interface MetricBasis {
  definitionCode: string;
  definitionVersion: number;
  scope: Wave5Scope;
  filters: Record<string, string | null>;
  asOf: string;                 // UTC instant / explicit dated-report basis
  recordedThrough: string;      // captured statement/recorded cutoff
  generatedAt: string;
  sourceContractVersions: Record<string, string>;
  unit: string;
  currencyCode: string | null;
  populationCount: number;
  eligibleCount: number;
  excludedCount: number;
  completeness: "complete" | "partial" | "unavailable";
  reasons: string[];
}
interface MetricValue {
  code: string;
  exactValue: string | null;
  state: "available" | "unavailable";
  reason: string | null;
  numerator: string | null;
  denominator: string | null;
  basis: MetricBasis;
}
interface Wave5Result<T> {
  requestId: string;
  data?: T;
  warnings: string[];
  error?: {
    code: string;
    message: string;
    retryable: boolean;
    correlationId: string;
    currentVersion?: number;
  };
}
interface Wave5Command<T> {
  scope: Wave5Scope;
  commandId: string;
  idempotencyKey: string;
  expectedVersion: number | null;
  clientOccurredAt: string;
  payload: T;                   // no authoritative actor/role claim
}
interface ProposalRevision {
  id: string;
  version: number;
  scope: Wave5Scope;
  commandCode: string;
  parameters: Record<string, unknown>; // validated allowlisted schema
  parametersHash: string;
  targetVersions: Record<string, number>;
  evidenceReferences: string[];
  expiresAt: string;
  status: "proposed" | "approved" | "rejected" | "expired" | "executed";
}
interface UsageEvent {
  eventId: string;
  tenantId: string;
  sourceInvocationId: string;
  metricCode: string;
  quantity: string;
  occurredAt: string;
  recordedAt: string;
  correctionOf: string | null;
}
```

| Proposed endpoint | Contract / readiness |
|---|---|
| `POST /rest/v1/rpc/wave5_process_metrics` | W5-01 scope/cutoff/bounded definition; named read RPC |
| `POST /rest/v1/rpc/wave5_pipeline_metrics` | Versioned cohort; consumes compatible CRM history |
| `POST /rest/v1/rpc/wave5_financial_ratios` | Consumes authoritative statement snapshots |
| `POST /rest/v1/rpc/create_cash_forecast` | Idempotently freezes scenario/source versions |
| `POST /rest/v1/rpc/create_ai_proposal` | Allowlisted evidence and command; provider optional |
| `POST /rest/v1/rpc/decide_ai_proposal` | Online human decision bound to revision/hash |
| `POST /rest/v1/rpc/execute_ai_proposal` | Trusted dispatch through existing domain commands |
| `POST /rest/v1/rpc/register_webhook` | Scoped destination metadata; secret managed server-side |
| `POST /rest/v1/rpc/change_synthetic_subscription` | Privileged audited synthetic plan/trial transition |
| `POST /rest/v1/rpc/get_usage_allowance` | Scoped read, authoritative usage basis |
| `POST /rest/v1/rpc/get_operator_health` | Separate operator capability, redacted projection |
| `POST /functions/v1/wave5-integration-command` | Later reviewed credential-bound integration gateway |

Stable errors include `AUTH_REQUIRED`, `PERMISSION_DENIED`, `ENTITLEMENT_REQUIRED`,
`VALIDATION_ERROR`, `CONFLICT`, `PROVIDER_UNAVAILABLE`, `CONTRACT_MISMATCH`,
`LIMIT_EXCEEDED`, `INSUFFICIENT_EVIDENCE`, `APPROVAL_REQUIRED`,
`APPROVAL_EXPIRED`, `QUOTA_EXCEEDED`, and `OUTCOME_UNKNOWN`. Missing/foreign/
forbidden target identities must not disclose which private record exists.
Domain-level unavailable metric values are successful explained results;
authorization, malformed input, or incomplete bounded-source retrieval fail
the request. Existing business command errors remain intact.

## Data Models

All rows below are proposed aggregates. Initial W5-01 definitions/results are
pure domain values; no new persistent analytics table is needed for that step.
Tenant-bearing persisted models use scoped composite foreign keys, forced RLS,
versions where mutable, and immutable recorded history where authoritative.

| Entity | Fields / types | Constraints and ownership |
|---|---|---|
| Metric definition | code text; version integer; unit/cohort/formula/provider contract text | Immutable definition revision; no arbitrary SQL |
| Process observation | event UUID; scoped source; UTC entered/completed/recorded; exact active/wait | Read projection of existing `workflow.process_events`; no edits/backfill |
| Metric result | basis object; exact values; counts; reasons | Pure value first; no missing-data coercion to zero |
| Metric snapshot/job | scoped UUID; definition version; cutoffs; filters; source manifest; status | Immutable ready evidence; resumable bounded job state; authorization on reopen |
| Pipeline forecast | scoped UUID; horizon; opportunity revisions; currency; exact assumptions/results | Immutable approved/frozen versions; forecast and realized populations distinct |
| Ratio calculation | statement refs; formula version; exact numerator/denominator; unit | Same period/scope/currency; null with reason for undefined result |
| Cash scenario | scoped UUID/version; horizon; controls/obligation refs; dated buckets; overrides | Pure draft then immutable frozen version; no authoritative postings |
| AI invocation | scoped UUID; tool/policy revisions; quota reservation; redacted evidence manifest | Unique trusted invocation; secret/provider payloads excluded from client views |
| Proposal revision | scoped UUID/version; allowed command/parameters/hash; targets; expiry | Immutable once submitted; no executable free text or arbitrary SQL |
| Proposal decision/execution | proposal/hash; actor; assurance; decision; command receipt | Append-only; separate proposer/approver; exactly one command identity per execution |
| Webhook subscription/delivery | scope; endpoint ref; allowed events; key version; event/attempt IDs; status | Secret outside exposed rows; unique event/subscription delivery; append-only attempts |
| Integration credential | hashed credential ref; scope/capabilities; expiry; revocation | Server-only issuance/storage; no service role in desktop |
| Subscription revision/trial | tenant; plan/version; effective interval; trial bounds; reason | Extends existing billing authority; no second entitlement engine |
| Usage/reservation/correction | event/invocation UUID; tenant; metric; exact quantity; UTC bounds; original ref | Trusted append-only usage; atomic allowance; unique consumption identity |
| Operator grant/health | actor; capability; tenant optional; reason; expiry; aggregate probe values | Separate operator authority; no implicit cross-tenant membership privilege |
| Local Wave 5 draft | actor/context; definition/scenario revision; encrypted payload/envelope | Existing secure store; live revalidation before action; no credentials or source PII |

## Delivery Slices and Dependencies

| Slice | Work | What can proceed in parallel | Integration gate |
|---|---|---|---|
| W5-01 | Metric basis, exact process event durations/completeness, bounded read, native workspace | New pure domain files first; new gateway/UI files after contract approval | Event producer semantics; scoped source permissions; shared composition ownership |
| W5-02 | Pipeline cohorts, forecasts, realized accuracy | Domain formulas and frozen synthetic fixtures | Verified CRM historical revisions; finance mapping for realized amounts |
| W5-03 | Financial ratios and cash scenarios | Formula/scenario domain contracts and fixtures | Installed authoritative statements, cash controls, AR/AP and supported Wave 4 obligations |
| W5-04 | Scoped AI evidence and human proposal lifecycle | Provider-neutral proposal state machine and injected-worker tests | Approved tools, commands, security contract and separately configured provider |
| W5-05 | Webhook/API delivery contracts | Destination/payload/state-machine logic with injected dependencies | Reviewed credentials/egress worker; installed outbox producer; external test target |
| W5-06 | Synthetic plans, trials, usage and quotas | Effective-time and exact allowance logic | Existing billing authority; privileged command/worker contract; overlap tests |
| W5-07 | Operator projections and access grants | Redacted health DTOs and explicit unavailable states | Separate operator permission model/MFA/grant approval; trusted probes |
| W5-08 | Integrated native/runtime/security/load acceptance | Maintain evidence and source ownership throughout | Installed providers, real signed-in synthetic users, native restart, target-scale evidence and owner signoff |

No entire-wave finish prerequisite applies to isolated domain work. A source
provider's installed contract and acceptance evidence are required before its
dependent feature can claim integration. W5-02 through W5-07 need their own
detailed slice contracts; approval of this specification does not authorize
production, paid services, secret provisioning, or unrestricted external access.

## Out of Scope

- OS-501: Production, real customer/employee data, signed releases, live paid
  subscriptions, real payments, and statutory claims; separate Wave 6/owner gates.
- OS-502: Autonomous AI business mutations, arbitrary SQL, unapproved commands,
  self-approved material actions, and provider secrets in Flutter; human command
  governance remains mandatory.
- OS-503: A second ledger, aging engine, workflow history, entitlement engine,
  or takeover of Wave 3 operational dashboards and Wave 4 source ownership.
- OS-504: Treating generic process events as certified stage visits, employee
  productivity, wait measurements or rework labels without an approved producer contract.
- OS-505: Silent installation of candidates, model/worker/key provisioning,
  external messages/webhook delivery, or alteration of authentication settings.
- OS-506: Unrestricted operator access, real billing collection, arbitrary
  tenant data exploration, and cross-tenant AI retrieval.
- OS-507: Full BI SQL authoring, warehouse replication, mobile implementation,
  or training a forecasting/model service; bounded native decision support first.
