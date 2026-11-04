# Diagnostic reopen result — 3 November 2026

The approved diagnostic V10 worker is deployed, with all 17 executable modules
matching hosted readback and the receiver unchanged. The single approved
controlled retry returned HTTP 503 / `WORKER_PROVIDER_UNAVAILABLE`. There were
no automatic retries. Successful Jentra AI output and trusted usage settlement
remain unverified.

The [test profile and private login handoff](ai-integrations-test-result-20261103.md)
remain available. The profile has the same three read permissions on Synthetic
RT1; no proposal-management right was added. Ordinary web password/MFA sign-in
was verified earlier. The model attempt was through the genuine authenticated
API, not the UI management-only submission button.

## Approved actions and actual result

- Owner reply: **Approve diagnostics and one free test**, question
  `call_70abeb9294864e04bdf45ef6a97cf929`.
- V10 was deployed after the approved manifest and test hashes were checked.
  Hosted metadata and all 17 executable module hashes passed readback.
- Fresh hosted preflight confirmed all four records for the preserved request
  were absent, model invocation count 0, five active members/five seats and
  exactly `ai.proposals.view`, `analytics.view`, `crm.opportunities.view`.
- Normal billing MFA/CAS APIs renewed the same synthetic plan to subscription
  version 4, with a 30-minute trial ending **03:05:10, 3 November, Asia/Colombo**
  (`2026-11-02T21:35:10Z`). The RT1 runtime window ends **03:05:44**. Schedule
  authority was unchanged and remains expired.
- Workers Free active and no payment method were checked again before the
  controlled attempt. No upgrade, paid fallback, seat or usage-cap change was
  made.
- The attempt reused invocation `bf887435-88db-4a1f-9df9-2e9ec326f9b4` and usage
  event `287f1f6a-fe5d-4cfe-aec0-bbe710eb8e9d`. Only the explicitly approved
  period window changed in the successor intent; the original receipt remains
  immutable.
- Actual response at `2026-11-02T21:07:11.486Z`: **HTTP 503**,
  `WORKER_PROVIDER_UNAVAILABLE`.
- Hosted accounting at `21:07:45.589255Z`: invocation, reservation, outcome and
  usage all absent; model invocation count 0; quota periods empty. The reader
  permissions and original delivery remained unchanged, with zero receiver
  receipts.

The original delivery remains `retry`, attempt 1. It has not been resent or
replaced. The two real authenticated model endpoint sends comprise the original
failed attempt and this explicitly approved controlled retry, both with the
same identities. They do not prove an AI provider call or usage settlement.

## Diagnosis and prepared follow-up

The V10 transport diagnostics recorded no RPC failure event in the visible
runtime logs. A local Deno run using a genuine MFA caller successfully read the
hosted forecast, passed the provider's no-I/O input check and reached an
intentional stop before any invocation write. This sent no request to the
hosted model endpoint or provider and is not hosted worker acceptance.

The next diagnostic candidate adds fixed execution stages, credential-kind
enums and a restricted source basename/line frame for otherwise hidden local
failures. It never logs credential values, headers, payloads, SQL messages,
model content, full file paths or caller IDs. It preserves client error codes,
request validation, invocation identities, model manifests and business
permissions. It never retries a request. Consumer errors cannot change the
ordinary response or transport exception.

- Candidate: `build/wave5-rpc-diagnostics-20261103/complete-candidate/`
- Manifest: `f1caa27d3b7661b6689de174e8f8b11fc2793f4ef6cd67e353aeec2034e254fa`
- Baseline / proposed runtime: V10 / V11.
- Inputs: 18 files, including 17 executable modules.
- Changed source: runtime entrypoint, edge runtime, model endpoint and model
  runtime. All other frozen inputs match V10.
- Verification: **313 worker tests passed**, normal and frozen Deno checks
  passed. No model/provider/database/permission policy changes.
- [Candidate record](../verification/ai-integrations-test-20261103/complete-diagnostic-candidate.json)
- [Endpoint diagnostics](../../workers/wave5/worker_endpoints.mjs)
- [Stage markers](../../workers/wave5/model_runtime.mjs)
- [Runtime diagnostics](../../workers/wave5/edge_runtime.mjs)

**This candidate is not deployed.** The proposed immediate action is only to
deploy this exact snapshot, verify readback and send one empty-object request
with a deliberately invalid caller. Its missing fields stop processing at
validation, before any forecast read, invocation write or AI provider call.
The original request payload and invocation IDs are not transmitted by that
probe. It does not need to renew trial/runtime authority.

Automatic approval review rejected an attempted additional diagnostic
deployment because the specific approved V10 patch and single retry were
already consumed. That command was not executed: no additional deployment or
hosted probe occurred. A fresh explicit approval is pending for the prepared
V11 snapshot and malformed-input check. No further genuine AI attempt is
included in this next diagnostic action.

Receipts and logs are listed in the
[verification index](../verification/ai-integrations-test-20261103/README.md).
