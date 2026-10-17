# Area 5: subscriptions, trusted usage, quotas and seats

The desktop allowance gateway now rejects a response whose authoritative period is empty or ends before it starts. Previously both malformed responses were displayed as available allowance. The fix retains valid historical allowance reads observed after their period end, exact integer arithmetic and microsecond precision.

The focused five-case Flutter regression first reproduced two failures and three passing controls, then passed all five after the fix. Scoped analysis found no issues. Actual logs and the original source bytes are retained here; `sourceproof.json` binds their hashes. The initial SDK lockfile failure and automatic approval-review usage failure were infrastructure failures, not test results. No backend, billing provider, role, private input or live data changed.

The existing October 6 rollback suites contain 124/124 and 126/126 recorded passing assertions. Their dates and rollback scope are preserved. They cover synthetic scheduling, replay, MFA authority, versioning, immutable history, metering settlement/correction, seat denial and private grants. These saved results are not a new database execution or independent overlapping-transaction proof.

All six complete requirements remain open:

| Requirement | Remaining evidence |
|---|---|
| FR-524 | Resolve current effective capabilities across plan, trial and seat changes with immutable versions, original actor/audit/receipt provenance and no paid billing. One retained activation case is narrower than the full criterion. |
| FR-525 | Execute duplicate trusted reservation/settlement and linked reasoned correction through the actual adapter; read back the original event unchanged, correction counted once and denied client authority. |
| FR-526 | Execute independent overlapping final-seat, admission-versus-activation and hard-quota transactions. Prove no overshoot and zero business/usage/receipt/audit/outbox effects for every denied attempt. |
| AC-512 | Read actual capabilities immediately before and after scheduled start and trial expiry using server UTC. Preserve unsupported-provider unavailable states and exact revision provenance. |
| AC-513 | Combine actual deduplication/correction readbacks with the independent cap races and committed allowance arithmetic; controlled source tests alone are insufficient. |
| EC-511 | Verify server UTC/effective-version boundaries alongside overlapping seat/usage reservations and a correction of prior usage. |

Use the existing reviewed runtime fixture and coordinator contracts rather than a second race implementation. The safe sequence is: verify exact synthetic target/authority and paused jobs; activate the reviewed revision before any busy quota period exists; run final-seat and admission/activation races; restore the original seat cap to four before restoring both original memberships; then execute twenty independent quota reservations against cap ten. Exactly ten apply, ten deny with `QUOTA_EXCEEDED`, reserved units become ten and all unrelated committed counters remain unchanged. Preserve every invocation, denial and committed-state binding. A sequential replay loop is not a substitute for independent overlapping connections.

Trial-boundary and correction testing requires separately bounded synthetic fixtures and the owning coordinator. Never move the active runtime's trial dates or reset its counters to manufacture a boundary. The root observed unavailable private PostgreSQL transport and expired worker authority; this area performed no additional live query. Current readiness must be refreshed by the root before execution.

A separate source-only concern was referred to the analytics owner: historical `process_access` and `pipeline_access` source mixes statement time with transaction-start expiry checks. Installed definitions require inspection before treating this as a current live defect. No migration was edited for that concern.

Applied skills: Supabase and Engineering Advanced API Test Suite Builder. Official references: [database testing](https://supabase.com/docs/guides/local-development/testing/overview) and [RLS](https://supabase.com/docs/guides/database/postgres/row-level-security). The lightweight changelog fetch failed with unsupported markdown content type; no undocumented Supabase API or schema change was introduced.
