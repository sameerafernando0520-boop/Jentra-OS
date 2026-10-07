# Spec: W5-01 Process Metric Foundation

**Author:** Jentra OS Engineering  
**Date:** 2026-09-30  
**Status:** Approved  
**Reviewer:** Product owner; approval expressed by “continue” on 2026-09-30  
**Parent:** [Wave 5 specification](WAVE5_INTELLIGENCE_AND_CONTROL_SPEC.md)

## Context

W5-01 is the first independent implementation slice. It establishes exact,
reproducible metric values and completeness before dependent forecasts or AI
consume them. The installed source is immutable `workflow.process_events`,
exposed through a security-invoker API view. Live metadata verified its columns
and forced RLS. No change to process-event producers is authorized by this slice.

The source permits nullable workflow-instance/entity/branch/completion fields,
and active/wait minutes default to zero. It has no explicit measured-work,
stage-visit identity, handoff, or rework flag. The existing RLS policy also allows
an active member to see their own/owned events. Neither this visibility nor an
event's `to_status` proves full source-document access or a complete stage visit.
The adapter must apply the stronger source permission/scope contract before
publishing aggregate analytics.

The current CRM opportunity producer writes equal entry/completion instants
for a stage transition. Its reported event duration can therefore be a valid
zero without saying anything about time spent in the previous stage. The first
server adapter supports only `crm_opportunity`, with the existing
`crm.opportunities.view` or `crm.opportunities.manage` source permission. Other
document kinds need a reviewed source registry entry before they are enabled.

First implementation step after approval: new pure domain contracts and
calculations plus meaningful unit tests. A later additive read provider and
native screen implement this same slice. Their installation, shared navigation
integration and authenticated/runtime acceptance remain separate gates.

## Functional Requirements

- FR-551: The calculation MUST require one validated tenant/entity scope,
  optional branch, explicit UTC cohort `[windowStart, windowEnd)`, `asOf` at or
  after window end and no later than `recordedThrough`, and a captured
  `recordedThrough` cutoff.
- FR-552: The input MUST be a complete bounded authorized snapshot of events;
  source contract revision, scope, document kind, row count, immutable source
  manifest and cutoffs MUST travel with it.
  A partially fetched page MUST not be accepted as a complete calculation input.
- FR-553: Cohort membership MUST use `entered_at` within the window and
  `created_at <= recordedThrough`; only a non-null `completed_at <= asOf`
  produces a completed observation, and other eligible events remain open at cutoff.
- FR-554: Eligible completed duration MUST equal exact UTC
  `completed_at - entered_at`; P50/P90 MUST use nearest-rank
  `ceil(p * n)` over sorted duration integers, including zero-duration samples.
- FR-555: The result MUST expose source, cohort, completed, open and invalid
  counts and explicit unavailable percentile values for an empty duration sample;
  it MUST label counts as event observations rather than completed workflows.
- FR-556: Stage dwell, process throughput, handoff wait, productive-work ratio,
  and rework MUST remain unavailable without certified producer semantics;
  default-zero minute fields and repeated statuses MUST not synthesize that evidence.
- FR-557: The source adapter MUST require existing `analytics.view`,
  `workflow.process.view`, the proposed `analytics` entitlement, and the
  allowlisted source-domain permission in the requested entity/branch, and MUST
  revalidate permitted source detail before drill-through.
- FR-558: The native workspace MUST show scope/window/both cutoffs, definition
  version, population/completeness, exact duration summaries, and explained
  unavailable values; stale or denied requests MUST clear prior server evidence.
- FR-559: Saved filters and pending reads MUST preserve context and reject
  late responses after context changes; saved results MUST not authorize a
  later read, and only the existing encrypted store MAY persist filter state.
- FR-560: Development MUST use new slice-owned files first, with no edits to
  shared barrels, router, main, existing migrations, dashboard metrics, or
  process-event producers until ownership is refreshed for integration.

## Non-Functional Requirements

- NFR-551: Calculations MUST use exact integer microseconds and decimal-string
  serialization; no float-based time, percentile, or financial arithmetic is permitted.
- NFR-552: Snapshots MUST reject more than 10,000 source rows, 100 groups,
  366 UTC days, or 8 MiB output; pages MUST default to 50 and cap at 200.
- NFR-553: Every adapter MUST pass anonymous, foreign tenant/entity/branch,
  own-event-without-source-permission, revoked access, and missing entitlement
  cases with zero protected rows or aggregate leakage.
- NFR-554: Deterministic domain cases MUST cover input permutations, exact
  boundaries, duplicates and malformed source rows; native previews MUST cover
  both themes/densities and 200% text, and source analysis MUST have zero findings.

## Calculation Rules

Definition: `process.event_duration`, version `1`. This is a reported transition
duration; it is not certified stage dwell or end-to-end process cycle time.
Definition metadata is immutable code data in the first domain step.

1. Validate the complete snapshot manifest, all bounds, strict UTC instants,
   scope, document kind, source revision and unique event IDs. Missing/malformed
   required instants, an invalid minute string, duplicate identity, foreign scope,
   mismatched document kind, unsupported source contract or incomplete snapshot
   fails the request. Do not normalize malformed source payloads into missing data.
2. Retain events whose entered instant is in the half-open cohort and whose
   recorded instant is no later than `recordedThrough`. Events recorded after
   cutoff or outside the cohort count as excluded source rows, not as invalid.
3. Completion before entry or negative reported minutes counts as invalid,
   contributes no duration, and makes completeness partial. A missing completion
   or a completion after `asOf` counts as open. Required-field parse errors fail
   the entire snapshot as specified in step 1.
4. Duration samples contain all valid completed events in the cohort. Keep
   exact integer microseconds as strings at transport boundaries. For `n > 0`,
   sort ascending and choose the one-based ranks `(n + 1) ~/ 2` for P50 and
   `(9 * n + 9) ~/ 10` for P90. Empty samples produce null with
   `NO_COMPLETED_OBSERVATIONS`; a real zero remains an available zero.
5. `cohortCount = completedCount + openCount + invalidCount` and
   `sourceCount = cohortCount + excludedCount`. These counts do not imply a
   source-document count or throughput. Different events for the same document
   remain distinct observations. Input order cannot change the result.
6. Return the event-duration values with their exact source basis. Report the
   unsupported measures with `UNCERTIFIED_PROCESS_SEMANTICS`, independently of
   whether reported active/wait minutes contain zero or positive numbers.

The recorded cutoff is the source `created_at` time, not commit-order proof.
The server uses one consistent read snapshot and captures an immutable sorted
source-ID manifest plus a hash of the projected source values, scope, cutoffs,
and definition. Later commits or source backfills can produce a different
manifest even for the same timestamp cutoff. Such a result is a new snapshot,
never an update to the old one. Reproduction consumes the captured rows/manifest;
re-running a timestamp filter alone is not reproduction. Snapshot reopen always
rechecks current source permissions.

Hash format version 1 uses UTF-8 JSON with no whitespace, the top-level keys
`definitionCode`, `definitionVersion`, `sourceContractVersion`, `tenantId`,
`legalEntityId`, `branchId`, `documentType`, `windowStart`, `windowEnd`, `asOf`,
`recordedThrough`, and `observations` in that order. Observations are sorted by
event ID and use the observation interface's field order. UUIDs use lowercase
canonical form, UTC instants use six fractional digits and `Z`, and exact minute
strings use six fractional digits without leading zeros. Standard JSON escaping
applies; null stays null. SHA-256 is encoded as lowercase hexadecimal.
`snapshotId`, hash itself, counts and generation time are excluded. This freezes
both the selection and its projected values without using display formatting.

The live capability probe found `analytics.view`, `workflow.process.view`,
and CRM source permissions, but no plan entitlement with the exact code
`analytics`. This is a proposed entitlement and a server-integration gate;
no existing plan or role is changed by the domain step. Any synthetic entitlement
setup must be listed explicitly in the separately authorized installation scope.

Filtering invalidity is never permission filtering. The server enforces the
scope/permission boundary before producing a snapshot; the domain validates
scope again and cannot grant access. A readiness failure uses
`PROVIDER_UNAVAILABLE` or `CONTRACT_MISMATCH`. A caller receives no partial
aggregate when source retrieval hits a limit or loses permission.

## Acceptance Criteria

### AC-551: Explicit cohort and recorded cutoff (FR-551, FR-552, FR-553)
Given events at window start/end and events recorded before/after cutoff
When the validated snapshot is calculated
Then only the half-open entered cohort recorded by cutoff is included.

### AC-552: Exact nearest-rank duration (FR-554, NFR-551)
Given completed durations of 0, 1, 2, 3 and 10 microseconds
When P50 and P90 are calculated with every input permutation
Then the exact values are 2 and 10 microseconds with no rounding drift.

### AC-553: Open, invalid and empty are distinct (FR-555, FR-556)
Given missing/future completions, malformed durations, and default-zero work fields
When summaries are calculated for nonempty and empty completed samples
Then counts conserve population and unsupported/empty measures are unavailable, while a real zero remains available.

### AC-554: Source permission is stronger than own-event visibility (FR-557, NFR-553)
Given an event actor who lacks the underlying source-domain read permission
When an aggregate or drill-through is requested with otherwise valid IDs
Then neither the event projection nor its metric value is returned.

### AC-555: Bounded complete snapshot (FR-552, NFR-552)
Given page truncation, duplicate identities and source/group/time/output boundaries
When a snapshot is submitted
Then incomplete or over-limit input fails without a partial result and allowed boundary input succeeds.

### AC-556: Native basis and access change (FR-558, FR-559, NFR-554)
Given a rendered result and an in-flight read in each supported native variant
When context or permissions change, or an older request completes
Then prior evidence is cleared, stale output is ignored, and all basis/actions remain reachable.

### AC-557: Additive implementation ownership (FR-560)
Given concurrent Wave 3 and Wave 4 changes in the same checkout
When the first domain implementation is reviewed
Then only new W5-01 files and its owned evidence are attributable to this session.

### AC-558: Source and quality contract (FR-551, FR-552, NFR-554)
Given malformed scope/UTC/manifest data and a verified immutable definition
When domain verification and analysis run
Then invalid input is rejected deterministically and all required cases pass without analysis findings.

## Edge Cases

- EC-551: Completion at `asOf` is included, completion after it is open, and
  entry at `windowEnd` is excluded; covered by AC-551/553.
- EC-552: An earlier-entered event recorded later is excluded from the frozen
  snapshot; a late commit or backfill with an earlier source timestamp must not
  amend its frozen manifest. A fresh manifest is a new snapshot; covered by AC-551/558.
- EC-553: Duplicate IDs fail the snapshot; separate events sharing document/
  request/correlation identifiers are not collapsed; covered by AC-555.
- EC-554: Empty and zero-duration samples, repeated values and one-row samples
  preserve nearest-rank semantics; covered by AC-552/553.
- EC-555: Missing/malformed required instant fails the snapshot; completion
  before entry or negative minute fields count as invalid; uncertified work/
  rework semantics remain unavailable; covered by AC-553/558.
- EC-556: Null entity source, mismatched branch, foreign IDs, own-event RLS
  visibility, hidden source domain or capability loss does not grant analytics
  access; covered by AC-554/558.
- EC-557: Pagination loses permission or reaches a retrieval cap, malformed
  UTC, inverted window or oversized output fails without partial totals;
  covered by AC-555/558.
- EC-558: Provider absence/version drift, network loss, sign-out, context
  changes and late responses produce explained cleared states;
  covered by AC-556/558.

## API Contracts

Proposed named read: `POST /rest/v1/rpc/wave5_process_metrics`.
The pure domain step neither installs nor calls this endpoint. The additive
server provider must capture source selection in one consistent read snapshot
and filter by underlying source permissions. A caller cannot supply its own
pre-authorized source manifest to that server endpoint.

```typescript
interface ProcessMetricRequest {
  p_tenant_id: string;
  p_legal_entity_id: string;
  p_branch_id: string | null;
  p_window_start: string;       // strict UTC instant, inclusive
  p_window_end: string;         // strict UTC instant, exclusive
  p_as_of: string;              // >= window end, <= server cutoff
  p_document_type: string;      // one allowlisted compatible source kind
}
interface ProcessMetricObservation {
  id: string;
  tenantId: string;
  legalEntityId: string | null;
  branchId: string | null;
  documentType: string;
  documentId: string;
  enteredAt: string;
  completedAt: string | null;
  recordedAt: string;           // source created_at
  activeMinutes: string;
  waitMinutes: string;
}
interface ProcessSnapshotManifest {
  snapshotId: string;
  sourceManifestHash: string;    // canonical projected values/basis, SHA-256
  sourceEventIds: string[];      // immutable sorted complete authorized selection
  sourceContractVersion: string;
  tenantId: string;
  legalEntityId: string;
  branchId: string | null;
  documentType: "crm_opportunity";
  windowStart: string;
  windowEnd: string;
  asOf: string;
  recordedThrough: string;
  sourceCount: number;
  complete: boolean;
}
interface ProcessMetricSummary {
  definitionCode: "process.event_duration";
  definitionVersion: 1;
  source: ProcessSnapshotManifest;
  cohortCount: number;
  excludedCount: number;
  completedCount: number;
  openCount: number;
  invalidCount: number;
  completeness: "complete" | "partial";
  p50Microseconds: string | null;
  p90Microseconds: string | null;
  emptyDurationReason: "NO_COMPLETED_OBSERVATIONS" | null;
  unsupportedMeasures: Record<string, "UNCERTIFIED_PROCESS_SEMANTICS">;
  generatedAt: string;
}
interface ProcessMetricResult {
  requestId: string;
  data?: ProcessMetricSummary;
  warnings: string[];
  error?: {
    code: "AUTH_REQUIRED" | "PERMISSION_DENIED" | "ENTITLEMENT_REQUIRED"
      | "VALIDATION_ERROR" | "PROVIDER_UNAVAILABLE" | "CONTRACT_MISMATCH"
      | "LIMIT_EXCEEDED" | "INSUFFICIENT_EVIDENCE";
    message: string;
    retryable: boolean;
    correlationId: string;
  };
}
```

`workflow.process_events.v1` is the proposed adapter's identifier for the source
column signature verified on September 30; it is not an installed server version
stamp. The provider must compare that shape/fingerprint before asserting support.
The manifest's complete flag is an adapter assertion subject to meaningful
truncation tests, not client authority.
Duration detail uses permitted source/event references and cursor pages in a
later provider step; the aggregate does not include actors, owners or free-text
reasons. Read permission checks are online and do not require new auth settings.

## Data Models

| Value | Fields / types | Constraints |
|---|---|---|
| Process metric definition | code/version; unit `microseconds`; percentile/cohort algorithm | Immutable constant; exact nearest rank; explicit event semantics |
| Process snapshot | validated manifest plus observations | Complete authorized adapter snapshot; unique IDs/hash; sourceCount matches rows; frozen selection |
| Process observation | source UUID/context/type; UTC instants; exact minute strings | Read-only projection; no actor/private text; explicit nullable completion |
| Process summary | counts; exact percentile strings/null; basis; reasons | Population conservation; input-order invariant; zero distinct from absent |
| Saved filter | actor/context; document kind; window/asOf; local version | Existing encrypted local store; no source rows or authorization grant |

## File Ownership and Verification Sequence

After approval, reserve new paths such as
`packages/jentra_domain/lib/analytics.dart`,
`packages/jentra_domain/lib/src/analytics/process_metrics.dart`, and
`packages/jentra_domain/test/analytics/process_metrics_test.dart`, verifying
each is still unused before creation. Use the existing domain package and exact
value primitives; do not add another package or change shared export barrels.

1. Implement the domain definition, validated snapshot, exact calculation and
   meaningful AC-551/552/553/555/558 cases; run focused tests and analysis.
2. Inspect live source permission/provider signatures and define one additive
   named read candidate with RLS/scope/entitlement/truncation tests. Record the
   before/after installed ledger; execute candidate checks only with rollback.
3. Add an isolated gateway and native workspace with injected-provider tests,
   encrypted filter recovery, stale-request clearing and rendered review.
4. Refresh main/router/navigation ownership and integrate only at a stable
   handoff. Record installed-development approval, real signed-in synthetic
   access, native restart, contention/load and owner acceptance separately.

The September 30 checkpoint below preceded implementation. The October 6
continuation implements the bounded rollback read provider, gateway, domain
calculation, encrypted filters and native workspace; current evidence is linked
from `docs/development/wave5-status.md`. Installed/authenticated acceptance,
native restart, contention/load and owner signoff remain separate. Domain or
widget completion cannot satisfy those runtime gates on its own.

## Out of Scope

- OS-551: Changing, backfilling or instrumenting existing Wave 3/4 telemetry;
  producer semantic extensions require their own compatible owner contract.
- OS-552: Certified stage dwell, whole-process cycle time, productive-work,
  handoff or rework measures; source evidence is currently insufficient.
- OS-553: Financial/CRM forecasts, AI, billing/operator writes or external
  integration execution; those follow separate Wave 5 slice contracts.
- OS-554: Installing candidates, changing existing auth/entitlements, or
  editing active shared composition files without a refreshed ownership handoff.
