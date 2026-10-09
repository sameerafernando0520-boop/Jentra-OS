# Worker, model and review continuation

Source continuation started October 9 and continued October 10 in Asia/Colombo. Jentra OS and Wave 5 remain incomplete. No new SQL, runtime account, secret, operator authority, worker, schedule or provider call was installed, provisioned or executed by this slice.

## Verified starting bindings

Before edits, the original unapproved review recomputed exactly to `13ffe2fdfd412fae36d3ff08c1f33bb59d9de85f20b2707e77ba6b9629eae83e`; all 71 migration and 85 artifact hashes matched. The original runtime 14-file and receiver 8-file upload bodies matched every current local file. Both retain the reviewed custom authentication with `verify_jwt=false`. The original review and upload files remain preserved. Their hash cannot approve the changed source.

All 71 migration bytes remain unchanged. The separate root live refresh records 43 migrations, 107 API functions and 120/120 unchanged provider fingerprints; it is a fresh read-only gate rather than a migration installation. The six runtime labels remain absent. The separate privately created desktop trial identity is outside this runtime bootstrap.

## Implemented defects

A byte limit alone left the runtime and receiver waiting indefinitely for an unfinished request body. The original 65-second runtime budget applied only to fetches, so a caller could retain one of eight active runtime slots by leaving its stream open. Four new tests reproduced this failure before editing; their failing output is preserved in [the red log](continuation-worker-deadline-red-20261009.log).

The shared bounded reader now cancels unfinished streams on the request/server signal and returns a static timeout without private diagnostics. Runtime request bodies and caller JWT/credential endpoints share the 65-second budget. Receiver request bodies and downstream fetches use the same bound. Receiver timeout probes preserve their durable receipt before waiting; the delay observes cancellation and cannot return a late 200 after its deadline.

Scheduled delivery/subscription batches combine the request budget with their 55-second batch budget. Delivery carries the signal through its ports: asynchronous DNS/authorization answers arriving after cancellation are discarded; the pinned HTTPS transport receives the signal. A cancelled send remains an unknown effect requiring persistent review and retains quota. Subscription activation now rechecks cancellation after awaited provider readiness and before dispatching the activation RPC. Cancellation cannot undo a business command or receipt already committed by the server.

These fixes bound the observed body, fetch, DNS, delivery transport and receiver-delay paths. Controlled ports and timers do not prove hosted scheduling, persisted races, quota contention or a deployed isolate's wall-clock behavior. Authenticated runtime and actual effects remain separate gates.

The native provisioning script already accepted an explicit review and build-manifest path. It did not bind the supplied manifest to the approved review. It now requires the exact `nativeIsolation.connectedBuildManifest` artifact/path/hash, Connected mode and project, before administrator/collision checks and any creation. It still verifies every selected source/release byte and preserves the exact new standard profile target. PowerShell parsing and Plan mode passed; Provision mode was not run.

## Fresh verification and exact artifacts

The final [r14 worker component](continuation-worker-component-20261009-r14.json) supersedes the preserved r12/r13 worker components. Worker revision r14 is independent of the root's native revision r13.

- [Current complete worker suite](complete-app-worker-tests-20261009-r14.json): **71 passed, zero failed**, controlled transports only; eight cancellation regressions. The [log](complete-app-worker-tests-20261009-r14.log) and [worker input hashes](complete-app-worker-source-20261009-r14.json) bind the run.
- [Fresh Deno checks](supabase-entrypoint-checks-20261009-r14.json): runtime and receiver exit 0 with `deno check --reload --config <per-entrypoint deno.json> <index.ts>`. JavaScript imports have `checkJs=false`; their controlled Node suite is separate verification. Deno required authorized package metadata access; no runtime/provider deployment happened. Earlier sandbox-DNS and unsupported-option attempts remain preserved.
- [Runtime upload](supabase-deploy-wave5-runtime-20261009-r14.json): 14 exact dependency files; [receiver upload](supabase-deploy-wave5-receiver-20261009-r14.json): eight exact dependency files. Both are prepared payloads, not deployed functions.
- `scripts/wave5/prepare_continuation_workers.mjs` creates new revisioned evidence/payload files, refuses old-review/migration drift, preserves earlier bytes, and permits recovery from a failed later evidence dependency only when the saved controlled source/log hashes still match.
- `scripts/wave5/prepare_continuation_runtime_review.mjs` composes a separate full review from the original exact scope/operations, current worker component, fresh live summary and root's final ordinary native builds. It accepts explicit false launch/authenticated acceptance gates, derives the worker test count, and binds the exact Connected build manifest. It refuses source/release/payload drift and uses new output paths.

Owned source: `workers/wave5/bounded_json.mjs`, `edge_runtime.mjs`, `edge_receiver.mjs`, `integration_policy.mjs`, `persistent_control.mjs`, `subscription_schedule.mjs`, `worker_runtime.mjs`, `worker_endpoints.mjs`; added `request_deadline.test.mjs`. The native provisioner and two continuation generators are separately attributable script edits/additions. No Flutter job or Git publication was performed by this slice.

## Remaining execution and acceptance

The final full refreshed runtime review must bind root's completed native report and be approved by its exact new SHA before operations. The original six installed Wave 5 migrations remain excluded. After approval, recheck collisions/ledger/source bindings, install the reviewed dependencies once, privately create/bind the six real Auth accounts, provision only the reviewed scoped plans/roles/operator and isolated profile, configure the model/Vault privately, deploy the exact worker/receiver payloads and expiring schedules, then gather genuine independent MFA and actual effects.

Required model evidence: allowlisted numeric source retrieval under real current caller authority; actual provider token counts and settlement; pending/unknown reconciliation without another send; four persistent invocation/2,000-reservation/8,000-plan caps; distinct human proposal, MFA approval and execution. Required delivery evidence: exact HMAC bytes/timestamp/event identity, committed source/lease/attempt, receipt-before-ACK, late rotation/revocation, redirect rejection, timeout unknown, durable reconciliation, dead letters/reviewed replay, restart and quota/throttle. Installed SQL, authenticated native, actual model/delivery, independent-session races, target-scale load and all 109 owner decisions remain open. Production and real billing remain excluded.

## Documents inspected

Handoff/status; original installation result; requirement-matrix status/evidence; complete remaining work and runtime review/manifest; runtime protocol; current Windows verification/account/Google/test-login records; the root fresh live summary; Wave 5 main specification, governed W5-04–07 control contract and reviewed native-model contract; review/source/upload/configuration generators; persistent-delivery/invocation/runtime-scope/Supabase runtime migration bodies and controlled worker suites. The root and provider/native agents retain ownership of finance/cash contracts, complete desktop golden investigation and heavy Flutter evidence.
