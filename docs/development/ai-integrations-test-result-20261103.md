# Jentra free test profile and hosted AI attempt — 3 November 2026

The approved test setup is installed. The temporary profile completed normal
password sign-in and the app's authenticator check, then connected to Synthetic
RT1. The single authenticated AI attempt returned HTTP 503. A subsequent hosted
read at `2026-11-02T20:57:28.059733Z` found no invocation, reservation, model
outcome or usage event for that attempt. Successful Jentra AI output and usage
settlement remain unverified.

The [protected login file](../../build/temp-test-profile-20261102/TEST-LOGIN-PRIVATE.md)
contains the temporary email, password, inbox credentials and authenticator
setup. It is ignored by Git and restricted to the local owner, SYSTEM and
Administrators. Do not copy its contents into reports or source control.

## Completed approved setup

- Recovered only the synthetic billing actor `w5-billing-admin@jentra.invalid`:
  rotated its password, removed its unavailable authenticator and verified a
  new factor through the real Auth challenge flow. Other users were unchanged.
- Created the reviewed reader role and used ordinary invitation/acceptance
  APIs with genuine MFA. The new profile has exactly `analytics.view`,
  `crm.opportunities.view` and `ai.proposals.view` on Synthetic RT1.
- Verified genuine web password sign-in, app MFA and the RT1 workspace.
  [Dashboard evidence](../verification/ai-integrations-test-20261103/test-profile-rt1-connected.png).
- Renewed the existing synthetic subscription and runtime scope for the
  approved 30 minutes. The plan remained `w5_runtime_20261008`, with five seats
  and unchanged usage limits. Both windows subsequently expired naturally.
  The read membership remains until revoked.
- Verified Workers Free active with no payment method before the test.
  The deployed provider has no paid fallback. Its daily free allowance is
  finite; this is not an unlimited free service.

The trial ended at **02:14:41 on 3 November, Asia/Colombo**. The runtime scope
ended at **02:16:56**. Neither was extended again. Schedule authority was not
renewed.

## Actual AI result and accounting

The controlled request used the new profile's real Auth/MFA session and the
existing synthetic forecast. Target-scope authorization passed and sibling
RT2 authorization was denied. The profile retained its three read permissions.
The app requires `ai.proposals.manage` for its model submission button, so this
was an authenticated API test; ordinary UI model submission was not verified.

| Field | Actual result |
| --- | --- |
| HTTP method / endpoint | POST `/functions/v1/wave5-runtime/model/suggestion` |
| Invocation | `bf887435-88db-4a1f-9df9-2e9ec326f9b4` |
| Usage event | `287f1f6a-fe5d-4cfe-aec0-bbe710eb8e9d` |
| Response | HTTP 503, `WORKER_PROVIDER_UNAVAILABLE` |
| Hosted invocation / reservation / outcome / usage | All absent in the final read |
| Tenant model invocation count / quota periods | 0 / empty |
| Automatic retries | 0 |

The original intent receipt incorrectly labels its `method` field
`genuine_authenticated_api`; the operator source and actual request use HTTP
POST. The frozen receipt is preserved, and this report clarifies that label.

The deployed flow creates its durable invocation and reservation before
calling the provider. Their absence points to a failure before the provider
send. This is an inference from code order and hosted accounting, not a
successful provider or usage claim. The earlier direct Cloudflare probe's
223 tokens remain separate from Jentra's ledger.

Read-only runtime readiness returned HTTP 200. A clearly labeled SQL rollback
diagnostic passed `model.begin` without retaining an invocation. A local run
of the canonical reader with genuine MFA read the hosted forecast (HTTP 200),
passed redaction and passed the provider's no-I/O input check. These checks
have not identified the hosted request's exact failure. The first rollback
fixture used an invalid manifest hash; its constraint error is preserved and
is not the root cause of the real 503. The corrected fixture passed.

The original external delivery remains `retry`, attempt 1, with zero receiver
receipts. It was not resent or replaced; external delivery acceptance remains
open.

## Prepared diagnostic change and next approval

The diagnostic-only candidate adds a fetch wrapper to the worker entrypoint.
For three fixed Supabase RPC names it records only the RPC name, transport
error kind, HTTP status and recognized machine error code when a call fails.
It does not log credentials, headers, request bodies, SQL messages, model
content or caller IDs, and never retries a request. Logger errors are ignored
so they cannot replace the original HTTP response or transport exception.

All **309 worker tests passed**, including six diagnostic tests. Deno checks
passed for the normal and frozen entrypoints. The initial Deno implicit-type
error and its corrected check are retained as separate logs.

- Candidate directory: `build/wave5-rpc-diagnostics-20261103/candidate`
- Manifest SHA-256: `ac569ac07bf537c47163fdbee531bb25e16aecaca0df3769bc5d3e877a03afd6`
- Inputs: 18 files, including 17 executable modules.
- [Candidate evidence](../verification/ai-integrations-test-20261103/diagnostics-candidate.json)
- [Diagnostic source](../../workers/wave5/rpc_failure_diagnostics.mjs)
- [Runtime entrypoint](../../supabase/functions/wave5-runtime/index.ts)

The candidate is **not deployed**. It changes no database function, permission,
provider, billing plan, receiver or schedule.

The proposed next action is to deploy this exact candidate, verify deployed
readback, renew only the same Synthetic RT1 trial/runtime for a new 30-minute
window and make one controlled attempt with the same invocation and usage
event IDs. A fresh hosted read must first confirm all four ledger records are
absent and the forecast identity/hash is unchanged. The new approved window
would be recorded in a successor intent; the failed original intent stays
immutable. Any existing pending or unknown state stops processing. No new
invocation identity or external delivery resend is included.

Automatic approval review rejected an invalid-caller diagnostic that reused
the original payload because it could risk duplicate hosted processing. That
action was not sent. A fresh explicit approval is required before reopening
that request, and the elapsed 30-minute authority must not be reused. A later
browser approval-review usage-limit interruption cleared; the final hosted
accounting query then completed normally.

Full dated receipts, source checks and accounting are in
[the verification directory](../verification/ai-integrations-test-20261103/README.md).
