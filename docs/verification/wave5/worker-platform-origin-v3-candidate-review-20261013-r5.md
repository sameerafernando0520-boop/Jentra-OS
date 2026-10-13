# Wave 5 platform-origin routing candidate v3 — 2026-10-13

This is a source candidate for the two existing reviewed test workers on `xpdoufauvrbdmxgngetv`. It is not approved or deployed. The actual in-handler Request origin/path and a live fix remain unobserved. No SQL, Auth, private credentials, schedule, native UI or acceptance stores were accessed or changed by this work.

Candidate bundle SHA-256: `dc7dbd7b1c14fd3fa23560283799ac51dad7c920a84e355c7357ddcc44143627`. The adjacent JSON pins six new source/test files, the complete 16-file deployment closure, both fixed entrypoints, retained caps and original predecessor hashes. Its canonical payload remains frozen. Later verification is additive.

## Evidence and remaining inference

The saved v2 origin/version review contains six events for the same deployed runtime function, public project HTTPS requests to `/functions/v1/wave5-runtime/schedule`, response 404 and `deno_origin=https://edge-runtime.supabase.com`. The separately saved single unauthenticated HTTPS probe returned exactly `{"code":"NOT_FOUND"}` (20 bytes), matching the factory response shape. Neither artifact observes the in-handler Request URL. The logged internal origin remains a plausible routing cause.

Official [Supabase routing documentation](https://supabase.com/docs/guides/functions/routing) uses the function name as a path prefix. The [logging documentation](https://supabase.com/docs/guides/functions/logging) contains an internal runtime-host example without defining Request.url. Header/token examples are not copied here. The [404 troubleshooting guide](https://supabase.com/docs/guides/troubleshooting/edge-function-404-error-response) describes the platform error shape.

[Supabase user-worker source](https://raw.githubusercontent.com/supabase/edge-runtime/main/ext/workers/user_workers.js), lines 42–62, passes a supplied URL into its worker-fetch operation. Its [HTTP request constructor](https://raw.githubusercontent.com/supabase/edge-runtime/main/ext/runtime/js/01_http.js), lines 123–139, receives the URL from the accept operation. The [version-pinned Deno helper](https://raw.githubusercontent.com/denoland/deno/v2.1.4/ext/http/lib.rs), lines 601–653, builds the URL from connection scheme, URI authority/host or Host header/socket fallback, and path-and-query. This supports the proposed mechanism; the managed platform revision and actual input remain unknown.

## Exact proposed behavior

The fixed project origin preserves both existing URL namespace forms. Only the exact additional HTTPS origin `https://edge-runtime.supabase.com` may use the `/wave5-runtime` or `/wave5-receiver` namespace with that function’s fixed routes. Internal `/functions/v1/...` paths, bare routes, other functions/origins, lookalike hosts, other protocols/ports, userinfo, query/hash delimiters, unknown paths and alternate raw URL normalizations are rejected. The caller may narrow the fixed route list, never expand it. Normalization performed before a Request reaches the selector cannot be reconstructed from its canonical URL.

Both successor factories change only the exact route-module import. Every remaining factory byte equals v2. Custom schedule-secret hashing, caller/external authentication, server scope and lease checks, exact-byte HMAC, committed source/subscription checks, durable acknowledgement, project environment checks, request/body/batch/concurrency limits, model caps and key clearing remain in those unchanged bytes. All 11 unchanged closure dependencies still match the frozen approved inputs.

The entrypoints record one finite diagnostic per isolate: fixed kind/worker enums, fixed origin/path classifications and five booleans. The diagnostic reads only `req.url`; it never prints a URL, host, method, headers, body or credential. Concurrent calls cannot repeat it. A diagnostic sink failure does not interrupt the authenticated handler. A future specifically approved deployment may establish the bounded in-handler classification.

## Local verification

The original RED run against v2 failed all seven proposed local internal-origin routes. The new focused serial Node suite passed 135 tests, zero failures/skips. It covers route/base negatives, unsigned and server-denied schedules, forged/stale/noncanonical HMAC requests, scope denial, project pinning, request cap, diagnostic concurrency/non-read/non-leak behavior and exact import-only factory transforms. These are synthetic local fixtures.

Root’s first whole-worker suite passed 240 tests. Both first fresh Deno 2.9.7 checks failed TS7006 for an implicit callback type; the original failed logs and source hashes are preserved. The repair adds only `(classification:unknown)` in each new entrypoint. Root then reported both repaired compiler checks passing and the fresh whole suite passing 240/240, zero failures/skips. A separate additive verification record pins those exact logs. Independent peer review remains pending.

The 5,539 original approved byte bindings matched before and after the factory/router/test edits. The later annotation affects only the two new, unapproved entrypoints. Original v1/v2 sources, configuration, approved golden images, accounts, sessions, acceptance stores and concurrent Wave 3/4/Employee work remain preserved.

## Next gate

Root owns the independent peer review, final deployment packet and specific owner source decision. The existing v2 approval covers bundle `bce677a0c8e53fea2ba44c30b81e0fa2d897d8f43af5dc6d109e2a1e6feaa552`; it does not approve these v3 bytes. The candidate extends no authority or caps and adds no user/migration. Production and real billing remain excluded.

Actual delivery, trusted model usage, contention/load and native acceptance require their own runtime evidence. Owner acceptance remains 3/109, AC-551/552/553 only. The private human/UAC native-profile prerequisite and unverified native keyboard remain separate.
