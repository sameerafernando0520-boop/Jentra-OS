# AI and integrations verification — 31 October 2026

Development is implemented locally, Supabase CLI/browser access is restored, and
the read-only accounting query has now run against the hosted development
project. Actual hosted model responses, trusted usage and signed delivery remain
open: the model still returns `503 MODEL_PROVIDER_UNAVAILABLE`, the required
`W5_OPENAI_API_KEY` secret is absent, and runtime authority expired on 14 October.
The [hosted continuation record](../verification/ai-integrations-access-20261031/README.md)
contains the actual database results, source readback and private setup handoff.
No provider secret, worker deployment, runtime authority or schedule was changed.

## Current source

The normal runtime/receiver entrypoints now retain the previously reviewed V6/V7
managed-hop routing and service credential behavior. Previously the ordinary
source still required the public URL shape and treated every server key as a
Bearer JWT. Redeployment from that source could reintroduce the earlier 404 and
opaque-secret failures. Historical versioned worker files remain unchanged.

Opaque server keys now use only the `apikey` header; legacy service JWTs retain
their existing headers. This matches [Supabase's API key migration guidance](https://supabase.com/docs/guides/getting-started/migrating-to-new-api-keys).
The requesting user's JWT, scoped worker RPC, schedule authorization, HMAC,
canonical event bytes and durable acknowledgement requirements remain enforced.

The new public probe sends exactly four fixed unsigned HTTPS requests with `{}`.
It records a durable intent before each request, request IDs, status, allowlisted
codes and response hashes. It limits time and response size, follows no redirect,
never retries and writes a new evidence directory each run. Provider responses,
credentials and arbitrary error text are not written to that evidence.

```powershell
node tools/wave5/verify_hosted.mjs
```

The command exits nonzero when all four exact authentication denials are not
verified. In particular, the model's current 503 is recorded as provider absence,
and cannot pass authentication or positive model readiness.

## Actual hosted observation

The latest four-request observation ran from **2026-10-31 13:07:56 UTC**
(**31 October, 18:37:56 Asia/Colombo**). See the
[actual HTTP report](../verification/ai-integrations/2026-10-31T13-07-56-047Z-e55d0468-989e-4b0f-a576-185b2d558dbf/report.json)
and its adjacent request journal, source manifest and SHA-256 file.

| Endpoint | Actual response | Evidence established |
| --- | --- | --- |
| Schedule | 403 `WORKER_ACCESS_DENIED` | Unsigned request denied |
| External forecast | 403 `AUTH_REQUIRED` | Missing caller authentication denied |
| Model suggestion | 503 `MODEL_PROVIDER_UNAVAILABLE` | Hosted provider unavailable for this request |
| Receiver | 403 `INTEGRATION_ACCESS_DENIED` | Unsigned receiver request denied |

These responses do not establish installed source equality, an authenticated
model result, successful quota settlement, signed delivery, current runtime
authority or human proposal approval/execution. An unsigned denial is not an
external delivery test. The earlier sandbox DNS failure and earlier successful
public observation are preserved as separate runs, not relabeled.

## Usage and delivery reconciliation

[The fixed read-only SQL](../../tools/wave5/hosted_accounting_readonly.sql) is ready
for the renewed, project-confirmed connection to `xpdoufauvrbdmxgngetv`. It runs in
a read-only transaction with a ten-second statement timeout and
final rollback. It returns bounded projections for the exact named runtime, with
no credential, model suggestion, request body or receiver payload content.
All projections use the snapshot of one SQL statement. The transaction wrapper
also supports SQL Editor callers that have already executed a query.

The query reconciles model outcome tokens with the original reservation/event,
quota period and immutable source hash. Delivery checks correlate acknowledged
attempts, HTTP status, receiver receipt, payload digest, recorded signing-key
attempt and one settled webhook unit. Quota counters are independently summed
from reservations, events and corrections; unknown outcomes retain reservations.
Historical scopes are inspected, while expired authority blocks a current pass.

Save the returned `hosted_accounting_snapshot` JSON and assess it within five
minutes of its database observation:

```powershell
node tools/wave5/check_hosted_accounting.mjs <saved-snapshot.json>
```

Empty, stale, truncated, expired, inconsistent or unresolved evidence cannot
pass. The assessor preserves exact integer quantities. It reports ledger
consistency only: a supplied JSON file is not authenticated database evidence,
and database rows cannot replace actual provider and outbound HTTP observations.
The corrected SQL ran against the hosted database at **12:59:44 UTC**. Its named
runtime projection contains no model invocations or quota periods and one
unresolved retry delivery without receipt/settlement; authority is inactive.
The [actual snapshot](../verification/ai-integrations-access-20261031/hosted-accounting-snapshot.json)
fails positive ledger acceptance as expected. This is no substitute for an
actual provider response or signed HTTP delivery.

## Checks and evidence

- 287 worker tests pass, including the existing model/delivery/quota coverage and
  new canonical deployment, public probe and ledger checks.
- Nine checks pass for the exact read-only SQL in isolated PostgreSQL 18.6 /
  PGlite 0.5.12: known token/webhook totals, corrections, retained reservations,
  key rotation, unknown outcomes, receipt corruption, expiry, counter drift and
  foreign-tenant exclusion. These use minimal synthetic contract-shaped tables;
  installed Supabase schema, RLS, grants and Auth are separate checks.
- Both ordinary Edge entrypoints pass Deno checks.
- The hosted SQL Editor continuation adds four passing transaction regressions
  and reruns the nine accounting checks against the corrected read-only wrapper.
  It preserves the original error and query. All projections still share one
  statement snapshot; a write is rejected in the regression transaction.
- The initial ten routing/credential regressions, the first synthetic engine
  preparation failure and the sandbox subprocess failures remain preserved.
  Test fixture credentials were corrected to the newly enforced server-key
  format; genuine behavior assertions were retained.

See [the evidence record](../verification/ai-integrations-20261031/README.md).

## Remaining live sequence

1. **Completed:** Supabase authentication is renewed and the exact healthy
   development project is confirmed. Read-only catalog/runtime/accounting and
   deployed-source observations are recorded. Existing migrations were not
   replayed. Repeat the necessary preflight immediately before a live operation.
2. Review the current provider/model configuration, private key availability,
   exact worker source and bounded synthetic runtime authority. The previous
   authority and its original model-call cap do not authorize a new run after
   expiry. Provider keys stay in the approved private configuration path.
3. Under a current reviewed run, retrieve a permitted numeric source using a
   genuine caller, invoke one suggestion within its approved reservation, bind
   the actual provider result/usage to its original invocation and usage event,
   and verify same-identity recovery without a second provider invocation.
4. Deliver a committed event to the approved test receiver. Match actual signed
   HTTP bytes, receipt/acknowledgement, attempt and settlement. Verify rotation,
   revocation, timeout/unknown reconciliation, retries, dead letters and reviewed
   replay with each existing boundary retained.
5. Reconcile a fresh database snapshot and complete separate human MFA proposal
   approval/execution, native recovery, contention/load and owner acceptance.

This continuation deployed nothing, installed no migration, issued no model
request and sent no signed event. Source changes remain uncommitted in the
existing checkout; concurrent application and release work is preserved.
