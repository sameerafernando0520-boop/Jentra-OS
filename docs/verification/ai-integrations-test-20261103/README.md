# Hosted AI and external-delivery verification

Client date: **3 November 2026, Asia/Colombo**. Machine receipts use UTC.

Current: [successful V12 hosted result](../../development/ai-integrations-v12-hosted-result-20261103.md).
The approved V12 repair is deployed and all 17 executable modules matched
hosted readback. The genuine authenticated request returned HTTP 200. Actual
hosted accounting confirms 247 trusted tokens, 247 usage tokens, zero reserved
quota and one settled invocation; all 18 reconciliation checks passed.
The AI trial/runtime windows expired by 12:04:17 PM local time on 3 November.
The later [approved external-delivery result](../../development/ai-integrations-external-delivery-result-20261103.md)
confirms one signed request returned HTTP 200, the original delivery is
acknowledged at attempt 2, one exact-payload receiver receipt exists, one webhook
unit is settled and no webhook reservation remains. All 18 delivery reconciliation
checks passed. The 247-token AI result is unchanged. The delivery trial ends at
1:38:04 PM and its runtime/edge authority at 1:38:37 PM local time. Scheduled
jobs remain paused. The [preapproval review](../../development/ai-integrations-external-delivery-review-20261103.md)
preserves the earlier rollback trial, 13 focused runner tests and 28 checks.

Earlier: the [diagnostic reopen result](../../development/ai-integrations-diagnostic-reopen-result-20261103.md)
records the V10 retry and the prepared V11 state before its later approval.

Historical: the [result and next-action review](../../development/ai-integrations-test-result-20261103.md)
records the earlier state before the successful V12 repair.
The approved test profile and bounded setup are installed. The real AI attempt
returned 503; exact usage and external delivery remain unverified.

| Evidence | Meaning |
| --- | --- |
| `owner-approval.json` | Exact scoped setup approval |
| `billing-recovered.json` | Real billing test-user credential/MFA recovery |
| `reader-role-created.json`, `reader-membership-created.json` | Committed three-permission role, normal invitation and acceptance |
| `viewer-mfa-verified.json`, `app-session-verification.json` | Genuine profile MFA and ordinary web-app sign-in |
| `test-profile-rt1-connected.png` | Visible RT1 dashboard |
| `synthetic-trial-activated.json`, `runtime-scope-renewed.json` | Actual approved 30-minute windows |
| `cloudflare-free-plan-before-test.json`, `.png` | Workers Free and no payment method before the attempt |
| `intent-model-invocation.json`, `response-model-invocation.json` | Original identities and actual 503; zero automatic retries |
| `model-accounting-final.sql`, `.json`, `.png` | Final hosted read: four absent records, count 0, expired windows, unchanged original delivery |
| `runtime-model-readiness.json` | Read-only readiness HTTP 200 |
| `model-begin-rollback-diagnostic.sql`, `.json` | Diagnostic simulated service role, successful begin, rolled back; no provider I/O |
| `model-begin-diagnostic-invalid-fixture.json` | Initial invalid diagnostic hash; not the real worker's error |
| `source-transport-diagnostic.json` | Local canonical reader with genuine Auth reads hosted forecast; not hosted worker acceptance |
| `credential-metadata-check-corrected.json` | Digest comparison; supersedes first report's unrecognized digest field, and does not identify the root cause |
| `worker-tests.log` | 309 passing worker tests |
| `deno-check.log`, `deno-check-corrected.log`, `deno-check-staged.log` | Initial type error, successful corrected check, successful frozen-source check |
| `diagnostics-candidate.json` | Original frozen V10 candidate, subsequently approved and deployed |
| `diagnostics-owner-approval.json`, `diagnostics-deployed.json` | Later explicit V10 approval, actual deployment and 17-module hosted readback |
| `reopen-trial-activated.json`, `reopen-runtime-scope-renewed.json` | Approved replacement 30-minute windows, five-seat plan unchanged |
| `cloudflare-free-before-reopen.json`, `.png` | Workers Free and no payment method immediately before the retry |
| `intent-reopen-model-invocation.json`, `response-reopen-model-invocation.json` | One explicit controlled retry with the same IDs; actual 503 |
| `model-accounting-after-reopen.json` | Hosted four absent records, count 0, unchanged original delivery |
| `model-accounting-after-diagnostic-preparation.json`, `.png` | Later hosted read at 21:21:44 UTC again confirms four absent records and count 0 |
| `local-deno-read-only-diagnostic.json` | Local Deno with a genuine hosted forecast read, intentional stop before any invocation write; no hosted model/provider call |
| `complete-diagnostic-candidate.json` | Original prepared V11 snapshot, subsequently approved and deployed |
| `complete-diagnostic-worker-tests.log`, `complete-diagnostic-deno.log`, `complete-diagnostic-deno-staged.log` | 313 passing tests and passing normal/frozen Deno checks |
| `v11-owner-approval.json`, `v11-deployed.json` | Later explicit V11 approval and actual verified deployment |
| `v11-empty-body-check.json`, `v11-hosted-diagnostic-event.json`, `v11-hosted-diagnostic.png` | Approved validation-only probe and actual opaque publishable-key kind; no AI call |
| `publishable-reader-before-fix.log`, `publishable-reader-after-fix.log` | Reproduced incompatibility and passing targeted regressions |
| `publishable-reader-worker-tests.log`, `publishable-reader-deno.log`, `publishable-reader-deno-staged.log` | 319 passing worker tests and normal/frozen Deno checks |
| `publishable-reader-live-expired-trial-denial.json` | Actual public-key HTTP transport and preserved entitlement denial under genuine MFA; not hosted AI acceptance |
| `publishable-repair-accounting-before-approval.json` | Current four absent records, count 0, expired version-4 trial and runtime window |
| `cloudflare-free-before-publishable-repair.json`, `.png` | Current Workers Free active / no payment method |
| `publishable-reader-repair-candidate.json`, `publishable-reader-operation-plan.json` | Original prepared V12 snapshot and plan, subsequently approved/applied |
| `publishable-repair-owner-approval.json` | Exact V12 repair, 30-minute RT1 windows and one preserved-ID model-test approval |
| `publishable-repair-deployed.json` | V12 ACTIVE and all 17 executable module hashes verified; receiver unchanged |
| `publishable-repair-trial-activated.json`, `publishable-repair-runtime-renewed.json` | Actual approved 30-minute windows, plan/five seats unchanged |
| `publishable-repair-preflight-before-model.json`, `cloudflare-free-before-publishable-repair-test.json` | Fresh empty ledger/source/permissions and Workers Free/no payment method before the request |
| `intent-publishable-repair-model-invocation.json`, `publishable-repair-model-response-verified.json` | One V12 request with original IDs; real MFA, HTTP 200 and source-bound suggestion |
| `publishable-repair-accounting.sql`, `.json`, `.png` | Actual hosted settled outcome/247 tokens, matching usage event, quota reserved 0/settled 247 and unchanged original delivery |
| `publishable-repair-usage-reconciled.json` | All 18 reconciliation checks passed; persistedUsageVerified true |
| `external-delivery-preflight.json`, `external-delivery-preflight-exact.json` | Actual retry/attempt 1, absent delivery ledger/receipts, expired windows and exact database function bytes |
| `external-receiver-readback.json` | ACTIVE receiver V8, all nine modules match reviewed source; read-only download |
| `external-function-byte-binding.json`, `external-function-guard-check.json` | Exact server digest/base64 binding after accessibility whitespace normalization |
| `external-delivery-rollback-first-stop.json`, `external-delivery-after-rollback-read-first-stop.json` | Preserved source-capture guard stop and corrected read-only query-generation failure |
| `external-delivery-recovery-candidate.json` | Frozen six-artifact/eleven-source recovery plan; approval pending |
| `external-delivery-rollback-final-result.json` | Frozen candidate authorized only the original event in a rolled-back transaction; no send |
| `external-delivery-preapproval-final.json`, `.png` | Independent final hosted read confirms retry/attempt 1, no delivery usage or receipts, paused jobs, unchanged 247-token AI result |
| `external-delivery-review-verified.json` | All 28 preservation/review checks passed; 13 focused runner tests passed; no committed recovery |
| `external-delivery-owner-approval.json` | Explicit owner approval of the frozen recovery, 30-minute windows and one signed request |
| `external-delivery-before-trial.json`, `external-delivery-billing-mfa.json` | Fresh unchanged preflight and genuine billing test-actor MFA |
| `external-delivery-trial-activated.json`, `external-delivery-authority-renewed.json` | Committed version-6 trial and existing RT1 runtime/edge renewal; jobs paused |
| `external-delivery-lease-intent.json`, `external-delivery-leased-job.json` | Exact original head repaired and leased at attempt 2; no replacement identities |
| `external-delivery-signed-request-intent.json`, `external-delivery-send-result.json` | Exactly one controlled signed request and actual HTTP 200 acknowledgement |
| `external-delivery-accounting.sql`, `.json`, `.png` | Independent hosted receipt with exact bytes/digest, acknowledged outcome and webhook quota reserved 0/settled 1 |
| `external-delivery-usage-reconciled.json` | All 18 delivery reconciliation checks passed; persistedReceiptAndAccountingVerified true |

Private passwords, factor secrets, invitation tokens and operational captures
remain under ignored `build/temp-test-profile-20261102`, with protected ACLs.
Do not commit those files. No commit, push, receiver replay or schema migration
was performed. Approved V10 and V11 deployments are recorded separately above.
The V12 reader repair is now deployed and verified; earlier receipts retain
their capture-time status.
