# Runtime renewal controller: source-only integration contract

This document describes reviewed inputs that must exist before a future execution. It is not an owner decision, execution plan, renewal, fresh owner refresh, or requirement acceptance. No live/private action was performed to prepare it. The controller is frozen at the hashes in `renewal-controller-source-proof-a1.json`; independent review remains a separate gate.

## Sources and existing records

- Controller: `tools/wave5/renew_runtime_authority_20261015_r5_a1.mjs`, SHA-256 `b3d8d2dda66e0945b1451d2d5f57d4daefbdf00cb2799d59543220a7d952956d`.
- Controlled tests: `docs/verification/wave5/root-runtime-renewal-20261015/renew_runtime_authority_20261015_r5_a1.test.mjs`, SHA-256 `f55039fe103b78487c96ae132d567d3c56c079cffd88fe1c3940b2d7ce08d79d`.
- All 115 tests passed in `controlled-tests-a3.tap`. The earlier 100-test and 112-test runs and the initial unfinished source checkpoint are retained. Both final sources pass `node --check`.
- The exact a3 SQL remains unchanged: `task3-runtime-renewal-20261014/renewal-preflight-read-a3.sql` (`546b3490cccecb4ae46740d4960dd64a919e35ba813261fefc17725d5afbae93`) and `renewal-expiry-update-template-a3.sql` (`ba2d17a9d47b64974d6086a16aaa25f3c04efbed60344ba18ba09fc8d543eeff`). Paths in this paragraph are relative to `docs/verification/wave5/`.
- Historical proposal a2 and dependency134 remain immutable historical inputs. The new source-derived accounting ledger is `docs/verification/wave5/task3-export-renewal-20261016/recorded-call-accounting-137-a1.json`, SHA-256 `f74dc940a839267f8d1d19982f08b122a43455b911d93dab9be85604050d1963`. It binds the actual Oct16 database read and two advisor reads. The controller independently reads all six pinned raw/attempt/verifier files.

The current recorded charge is 137. The proposed continuation is owner refresh 138, renewal preflight 139, one expiry write 140, and renewal readback 141. Exports then allow 24 ordinary calls through 165 and one reserved resolution through 166; health 5 and scheduler 3 yield 174 overall. Those future counts remain proposals. Any failed or conservatively charged attempt stays counted and stops this one-use continuation; no retry resets accounting.

## Fixed integration locations

All paths are workspace-root relative.

| Input or output | Path |
| --- | --- |
| Actual generated plan | `docs/verification/wave5/root-runtime-renewal-20261015/execution-plan-a1.json` |
| Actual final independent operation review | `docs/verification/wave5/root-runtime-renewal-20261015/final-operation-review-a1.json` |
| Independent source review | `docs/verification/wave5/root-runtime-renewal-20261015/independent-source-review-a1.json` |
| Exclusive actual intent | `docs/verification/wave5/root-runtime-renewal-20261015/actual-renewal-once-a1.json` |
| Actual successful two-row readback | `docs/verification/wave5/runtime-renewal-two-row-readback-20261016-r5-a7.json` |
| Direct human decision | `docs/verification/wave5/runtime-renewal-export-owner-decision-20261016-r5-a7.json` |
| Source policy | `docs/verification/wave5/task3-export-renewal-20261016/source-policy-a1.json` |
| Independent policy review | `docs/verification/wave5/task3-export-renewal-20261016/independent-policy-review-a1.json` |
| Actual A10 metadata | `docs/verification/wave5/private-owner-input-ready-20261014-r5-a10.json` |
| Actual A10 refresh evidence | `docs/verification/wave5/private-owner-scope-refresh-20261014-r5-a10.json` |
| Actual management adapter | `scripts/wave5/run_private_health_scheduler_20261015_r5_a1.ps1` |

The Oct14 A10 filenames are retained because the existing helper emits them. Freshness is determined by their actual content. Metadata must name `metadata-renewed-a10.json`, match the original explicit credential reuse authorization, and bind the actual one-GET identity refresh for project `xpdoufauvrbdmxgngetv`, organization `kuzlgtbvfmxqcodmicoy`, and status `ACTIVE_HEALTHY`. Both metadata and refresh must bind existing helper `tools/wave5/refresh_private_owner_scope_20261014_r5_a10.mjs` at `a3fe771a022dac5ba3a81a33591e7017fb6f446a2e813affd09fc6e40738d07a`.

## Public preflight and file-lock contract

`node <controller> --preflight <finalReviewSha256>` performs the complete public validation and prints exactly five fields: `passed:true`, `networkCalls:0`, `privateInputsRead:false`, `planSha256`, and `finalReviewSha256`. It reads neither stdin nor private input, creates no intent, and makes no network call. An absent or invalid review fails closed.

`--execute <same finalReviewSha256>` performs this validation before stdin, accepts only `{projectId,bundleSha256,ownerToken}`, and repeats public validation after stdin and before transport/intent creation. Public source checks alone never grant execution authority.

The plan has kind `source-bound-two-row-runtime-renewal-plan`, fixed project/runtime/original bundle identities, `maximumManagementAttempts:3`, `recordedPrior:137`, `actualPriorAfterOwnerRefresh:138`, `cumulativeAfterRenewal:141`, `maximumRequestMs:45000`, `maximumRunMs:900000`, `ordinaryReserveMs:90000`, `maximumWindowMinutes:120`, `automaticRetries:0`, `otherCallsSinceDependency:3`, `otherCallsSinceCurrentCharge:0`, and `liveExecutionAuthorizedByPreparation:false`. Its `window` must equal `{notBefore:actualMetadata.createdAt,expiresAt:actualMetadata.expiresAt}` with positive TTL no longer than two hours. The source exports the exact remaining fixed path and SQL fields.

`controlBindings` contains exactly the ten exported names: `sourcePolicy`, `policyReview`, `ownerDecision`, `metadata`, `refresh`, `proposal`, `sourceRepair`, `dependency`, `currentCharge`, `staticReview`. Each is `{path,sha256}`. `sourceBindings` contains exactly controller then test. `publicBindings` is the exact path-sorted closure of these ten controls, two a3 SQL bindings, six recorded-call evidence bindings, and the pinned A10 helper: 19 entries. No missing, extra, changed, or duplicate bindings are accepted.

The private launcher must hold read-only file handles that deny writes for this public closure, the two source bindings, the plan, final review, and its own actual adapter from before public preflight through child exit. It must verify hashes while acquiring those handles. The controller performs hash and path checks; the launcher provides the cross-process replacement protection.

The final review has kind `independent-runtime-renewal-final-operation-review`, `technicalDecision:"approve"`, `executionPermitted:true`, exact identity fields, `generatedPlan:{path,sha256}`, identical `controlBindings`, `sourceBindings`, `publicBindings`, `sqlBindings`, and `window`, and `privateAdapter:{path,afterSha256}` for the actual adapter. It also requires `directHumanDecisionVerified:true`, `maximumManagementAttempts:3`, and `cumulativeAfterRenewal:141`.

Source policy and independent policy review must include `renewalControllerSourceBindings`, `renewalSqlBindings`, and exact `currentChargeBinding`. The policy must additionally bind historical `renewalProposalBinding` and `renewalSourceRepairBinding`. The independent controller source review must bind both controller sources, both SQL sources, proposal, and source repair. The direct owner record must contain the actual exact reply `Approve the exact two-row runtime renewal and export a7 continuation`, its actual question ID and timestamp, and exact reviewed source-policy/review/operation-bundle bindings. Controlled fixtures containing that text are not human authorization.

## Execution and evidence contract

The controller permits exactly the existing runtime `778237e3-3d4e-4871-8cc9-e08b07b989c7` and original synthetic tenant/entity/branch. The only write is the exact a3 transaction with five validated NULL input slots substituted. All other SQL bytes remain identical. The SQL changes only the existing scope and authority `expires_at`; it preserves original `issued_at`, all non-window hashes, seven function/ACL bindings, schema contracts, counters, key references, and three paused jobs.

Each attempt is charged and its attempt record acknowledged before transport. Raw response bytes and a response receipt are acknowledged durably before status, JSON, or semantic validation. Main execution uses exclusive file creation and fsync. HTTP is limited to the project management database-query endpoint, verified TLS, 45 second requests, 2 MiB responses, no redirects, and no retries. The approved window is copied immutably into both execution and transport checks.

The renewal expiry is `min(actualPreflightServerTime +120 minutes, actualOwnerMetadataExpiry)`. The first server observation must be fresh and follow metadata creation. The genuine a3 application response must report `applicationTimestampProvenance:"server-post-commit-observation"` and `appliedAt` no later than 45 seconds after preflight. The final server readback must follow it within 45 seconds. No future timestamps are accepted. The original UTC 13 issued timestamps remain unchanged; an actual reviewed window may cross UTC midnight.

Successful readback has kind `actual-two-row-runtime-expiry-renewal-readback`, `actual:true`, `committed:true`, both rows/counts/old and new expiry/hash fields, preserved-state flags, and:

- `preflightObservedAt`, `serverExpiryAnchor`, and `serverWindowAnchor`: identical actual first snapshot timestamp.
- `appliedAt`: only the actual a3 `renewal_application.appliedAt`, a server observation after COMMIT, not a precise commit timestamp or a client estimate.
- `observedAt`: actual third snapshot timestamp.
- `applicationTimestampProvenance:"server-post-commit-observation"`.
- `controlCallAccounting:{attempts:3,failedAttempts:0,automaticRetries:0,receipts:[...]}`. Receipts have ordinals 139/140/141, phases `preflight`/`two-row-expiry-write`/`readback`, `successful:true`, and raw `responseSha256`.
- `actualCumulativeChargedCalls:141`.
- `renewalPreflightResponseBinding`, `renewalWriteResponseBinding`, `renewalReadbackResponseBinding`: actual durable `{path,sha256}` for the three raw `.bin` responses beneath a fresh `root-runtime-renewal-20261015/actual-<uuid>/` directory. Health/scheduler `controlBindings.renewalWriteResponse` must bind the second one.

An uncertain write permits the single third read only. Even if that read observes renewed rows, missing genuine post-commit application evidence blocks a7 continuation; the controller never replays the write or invents `appliedAt`. Stop evidence preserves the charged total, failure, and resolution status. Native checks, exports, actual delivery, contention/load, owner acceptance, production, and real billing are not claimed by this controller.

## Remaining integration gates

Independent source/adapter review, the exact new human renewal decision and operation bundle, an actual fresh A10 refresh, actual generated plan/final operation review, and actual three-call renewal evidence are still required. The a7 profile/accounting and health/scheduler follow-on checks may be assembled only from their actual successful upstream records. The frozen controller is ready for those source-level reviews; it has not been executed against Supabase.
