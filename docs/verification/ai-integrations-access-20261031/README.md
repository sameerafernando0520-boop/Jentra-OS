# Hosted AI and integrations continuation — 31 October 2026

Supabase access was restored through the official CLI browser login. The exact
Jentra project `xpdoufauvrbdmxgngetv` is confirmed `ACTIVE_HEALTHY`. The saved CLI
credential works when the stale process environment override is omitted. No
credential values are recorded in these artifacts. User or machine environment
variables were not changed globally.

## Actual hosted observations

| Observation | Result | Artifact |
| --- | --- | --- |
| Current project and functions, 13:01:30 UTC / 18:31:30 Asia/Colombo | Healthy project; both Wave 5 workers remain ACTIVE at V7; existing People/Assurance metadata unchanged | `hosted-project-metadata-refresh.json` |
| Required provider secret | `W5_OPENAI_API_KEY` absent; no model-related custom secret names | Same metadata; secret values were not retrieved |
| Catalog/runtime checkpoint, 04:49:05 UTC | 130 migrations; 389 API functions; runtime authority expired 14 October; zero receiver receipts | `hosted-preflight.json`, `hosted-preflight.png` |
| Exact read-only reconciliation, 12:59:44 UTC / 18:29:44 Asia/Colombo | No model invocations or quota periods in the named runtime scope; one retry delivery at attempt 1, with no outcome, reservation, settlement or receipt; authority inactive | `hosted-accounting-snapshot.json`, provenance JSON and `hosted-accounting.png` |
| Ledger assessment | Fails with inactive runtime, unresolved delivery and missing nonempty model/quota evidence | `hosted-accounting-assessment.json` |
| Fresh unsigned HTTP checks, 13:07:56 UTC / 18:37:56 Asia/Colombo | Schedule/external/receiver return expected 403 denials; model returns 503 `MODEL_PROVIDER_UNAVAILABLE` | [Actual four-request report](../ai-integrations/2026-10-31T13-07-56-047Z-e55d0468-989e-4b0f-a576-185b2d558dbf/report.json) |

These are current administration/read-only observations. They do not establish a
successful authenticated business-user model request, billable provider usage,
signed delivery or human MFA approval/execution. Empty model/quota arrays cannot
pass positive acceptance. The unresolved delivery retains its original state;
there was no replay or replacement invocation.

## Deployed source readback

Both deployed workers were downloaded into new, isolated evidence folders using
the official CLI and its server-side unbundler. All 25 returned modules are
hashed in `deployed-source-comparison.json`. Twenty-three exactly match current
local bytes. The runtime's two differences are:

- `model_runtime.mjs`: the deployed V7 copy predates local checks that reject an
  untrusted usage provider before sending evidence/reserving quota, validate
  settled recovery tokens before settlement, and recheck authorization afterward.
- `persistent_control.mjs`: the deployed copy retains the older unconditional
  service Bearer headers and matches the workspace base commit. The local copy
  now handles opaque server keys correctly. V7's separate versioned control is
  already present in the returned source.

This is not a full current-source match. The current local fixes have not been
deployed. The source downloads are read-only rollback/reference artifacts; the
People and Assurance functions were not changed.

## SQL correction and verification

The first hosted accounting attempt returned PostgreSQL `25001`. The error and
original query remain in `accounting-first-hosted-failure.json` and
`hosted-accounting-before-editor-fix.sql`. Native editor value insertion also
appended to its existing buffer, so the successful observation used a verified
empty in-app browser snippet containing only the corrected query.

The query now explicitly enables transaction read-only mode without changing
isolation after an earlier statement. All reconciliation projections remain in
one SQL statement and final rollback is retained. This follows PostgreSQL's
[transaction-setting restrictions](https://www.postgresql.org/docs/current/sql-set-transaction.html)
and [statement snapshot behavior](https://www.postgresql.org/docs/current/transaction-iso.html).

The exact corrected query passes nine accounting checks and four additional
transaction regressions in isolated PostgreSQL 18.6 / PGlite 0.5.12. The latter
reproduce the old 25001 failure, run within an existing transaction, reject a
write with 25006, and verify rollback preserves records and restores the
connection setting. The original failed and passing logs remain separate.
The existing 287 worker tests and two Deno checks concern unchanged worker code;
they were not relabeled as provider or delivery acceptance.

## Remaining input and live gates

The authenticated Secrets page is open at the exact project, with the name
`W5_OPENAI_API_KEY` filled and its value left empty. No secret was saved.
Neither of the named OpenAI variables is present in the current local process
environment. The owner must supply an approved provider credential privately or
identify its approved private source; it must not be pasted into chat.

After provider configuration, complete the current source review/deployment,
bounded runtime authority and genuine caller setup before a model invocation.
Reconcile actual provider tokens under the original invocation/event identities,
then verify signed delivery and its acknowledgement/settlement. The existing
unresolved delivery needs review before any resend. Old expired authority and
old model-call limits are not renewed by these reads.

No migration, function deployment, runtime/role/entitlement change, background
activation, model call or signed event was performed in this continuation.
The Supabase login itself was refreshed as requested. The earlier failed login
checks and provisional PowerShell parsing results are retained; the later
fixed-project Node collector is the authoritative project confirmation.
