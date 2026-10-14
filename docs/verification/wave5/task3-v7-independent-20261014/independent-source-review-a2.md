# Independent V7 source review

The exact frozen V7 sources and both candidate payloads pass independent source review. All 36 controlled cases pass: the author’s 21 cases and 15 additional peer cases. All seven syntax checks pass. Every bound input stayed unchanged during this run. The root and operation owner still need to decide the exact live operation.

Opaque service keys use only `apikey`. Legacy service JWT shapes keep the original `apikey` and Bearer headers. Reserved `sb_` families are checked first; malformed, unknown and publishable forms cannot use the legacy fallback. The classifier establishes format only. It does not authenticate a key, establish its role, authorize a caller or discover credentials. This transport behavior follows the [official Supabase API-key guidance](https://supabase.com/docs/guides/getting-started/api-keys#known-limitations).

Exact reverse diffs verify the original URL guard, scope allowlist, caller checks, schedule-secret hash, receiver HMAC, body limits, concurrency caps, deadlines, error mapping and finite V6 diagnostic. The privileged default and scoped ports use V7. The unchanged public model reader retains its original transport and independently sends the caller’s JWT with the public API key. Denied or stale public authority cannot fall back to the service key.

The payloads contain 17 runtime files and 10 receiver files, or 27 rows, 20 unique files and 18 source modules. Actual static and literal dynamic import graphs are 16/16 for runtime and 8/9 for receiver. The fixed lazy worker_runtime module is retained; the receiver does not invoke its delivery-batch export. Every payload row equals its current source bytes without normalization.

Additional peer cases cover invalid key types and encodings, foreign routes, exact project configuration, unsigned schedules, denied ticks, eight concurrent request slots, stream cancellation, downstream abort, private-error suppression, canonical event bytes, forged HMAC on every fault route, unknown scoped RPCs, rejected caller reads and changed public authority. All ports use controlled fake inputs; no project network or private credential operation was performed.

The first peer run is preserved with 35 passes and one fixture failure. The successor binds the actual predecessor behavior: signed whitespace and alternate key order return 400; an extra schema field returns a sanitized 503. Both versions make zero backend calls for those cases. The final case counts come from actual registered test identities and TAP results.

The original caps remain four model calls and 4,320 schedule requests, with 24 earlier requests retained. Authority still expires on October 14, 2026 at 09:57:07.481942 UTC or an earlier applicable expiry. This review adds no live authority, schedule resume, native acceptance, load result, requirement decision or production release claim.

Exact review: docs/verification/wave5/task3-v7-independent-20261014/independent-source-review-a2.json (SHA-256 f0e713a3b4e090bbc3a35d8ed0a2293600f5827c3fb35801573f89649ef5813d).
Fresh test evidence: docs/verification/wave5/task3-v7-independent-20261014/independent-local-verification-a2.json (SHA-256 2e3c3290f6140cae856d1374a2b3179ff46ae5fd7e9577da1c2338dfbfc32a81).
Fresh TAP log: docs/verification/wave5/task3-v7-independent-20261014/independent-local-verification-a2.tap (SHA-256 b4984204e853f958d5f84f9240974eacc4fb32f703ee9e72791eaba13cbc4427).
