# Wave 5 reusable runtime coordinator review

The new reusable coordinator is implemented and locally verified: **38/38 tests passed**, with no failures, skips, cancellations or todo cases. Node v24.11.0 ran the actual test command from 2026-10-12T07:23:44.223Z to 2026-10-12T07:23:46.355Z. It is an executable coordinator with a private-provider interface; a genuine Supabase transport/private session provider has **not** been implemented.

This separate review binds [the immutable runtime review](./complete-app-runtime-review-20261010-r5.json), bundle `db525758554036fa99ec02d00c85bd8401ef7ebce787e2a983db1c69a08baf7b`, file `b1b0cb94a8aa705b5cc6ff674ed215a8487a960ff0a594f7abffadfbc4e57cc3`. The existing operation scope `fcdab89d242dc578793eba1d520ea0251699b70b7730c02aea94232805286e63` remains unchanged. The runtime owner decision is maintained separately by the runtime owner. The same runtime decision covers the same bounded operations; technical code/preparation review creates no second owner approval for file hashes.

## Actual local evidence

- [Recorded actual Node run](./runtime-harness-local-verification-20261012-r5-a3.json) and [complete TAP](./runtime-harness-local-verification-20261012-r5-a3.tap): exit 0; 38 passed; selected source hashes unchanged before/after.
- [Earlier failing attempt](./failed-harness-tests-20261012-r5-a1.json) is preserved: 25/26 passed; its duplicate-session negative fixture was corrected, not the guard.
- [Earlier 37-test run](./runtime-harness-local-verification-20261012-r5-a2.json) and [its review](./runtime-harness-review-20261012-r5.json) remain historical. The peer's held-warmup false pass exposed a missing actual lag check; the current source and successor run fix it.
- [Public source bindings](./runtime-harness-review-20261012-r6.json) bind 7 new implementation/evidence files and 11 authoritative protocol/bootstrap/SQL dependencies.
- [Private provider contract](../../../tools/wave5/PRIVATE_PROVIDER_CONTRACT.md) defines the still-missing real Auth/transport/committed-state interfaces.

The tests exercise actual coordinator barriers and client overlap, detect serial queues, preserve uncertain mutations, enforce committed effect counts, redact arbitrary provider errors, prevent post-deadline sends and freeze source-bound contexts. The held-warmup regression rejects a 60-second evidence-queue delay before send; scheduled timing cannot claim actual warmup or hide catch-up bursts. A controlled virtual-time run checks every 2,000-session/500-scope slot and 70/20/10 scheduling; it proves no live latency or real sessions.

## Source findings carried into implementation

- Scoped delivery claim creates one lease/attempt and zero usage reservations; actual send remains separate.
- load-001 billing-admin needs genuine AAL2; two distinct genuine AAL2 executor sessions are needed for execution contention.
- Cached duplicate replies cannot identify a unique winner; aggregate committed counts establish uniqueness.
- Invitation acceptance has no caller command/idempotency input; attempt UUID is correlation only.
- Model invocation/delivery attempt rows do not count actual remote sends; a complete reviewed transport observer is required.
- Synthetic activation/admission phases must precede quota buckets; existing busy billing periods cannot be cleared to force a pass.
- One-lease preparation needs only the reviewed accept subscription registered after earlier forecast effects, before the other three receiver paths; there is no public re-enable operation after revoke.

The 367-day invalid request is feasible from the mapped API. A 10001-row cohort exceeds approved caps, and real 101-group/8MiB output fixtures remain unproven. Unsupported limits record blocked/never executed/never passed. Independently authorized race/load investigation may continue, but the complete result stays false until all four required limits have genuine evidence.

## Remaining work and gates

- Genuine private Supabase Auth/session storage and online identity/server auth.sessions proof for all 2,000 distinct sessions; real MFA.
- Actual reviewed source-listed PostgREST/worker transport with independent connections and honest start/end/response evidence.
- Concrete source-bound new-scope fixture preparation/restoration and read-only committed SQL, including denied-attempt attribution.
- Fresh installed-ledger/signature/grant/RLS/preservation proof and supported database/generator capacity for the exact rate.
- Reviewed full transport observer and online no-inflight/inactive-job proof for model/webhook exclusion during load.
- Feasible separately reviewed excessive-source/group/output fixture scope if current approved caps cannot exercise required limits.
- Source-bound independent preparation review of the real private implementation, dependencies and concrete plan.

All live gates remain false: installed SQL, genuine MFA, independent-session contention, target-scale load, invalid-limit rejection, authenticated native, actual delivery/model usage and owner acceptance. No network, SDK/native job, Auth write, installation, credential access, acceptance/session-store edit, commit or push was performed. Production and real billing remain excluded.
