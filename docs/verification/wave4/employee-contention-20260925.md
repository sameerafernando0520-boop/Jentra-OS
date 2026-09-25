# W4-01 employee contention protocol

**Status:** Prepared, not executed. The employee migration is installed in
development as `20260925181927`; `w4_employee_synthetic` has People enabled but
no tenant is subscribed. The three original plans remain disabled.
**Target:** A coordinated synthetic tenant on a dedicated test plan, or a
disposable development branch, with `module.people` enabled only on that test
plan and two independent authenticated PostgreSQL or API connections. A plan
entitlement affects every subscriber to that plan; do not enable a shared plan
just for this test. Do not use real employee data.

## Establish genuinely overlapping sessions

Record `pg_backend_pid()` or distinct authenticated request IDs, transaction start,
command start and commit/finish times for each connection. Start session B after A
enters its command but before A commits. For a database-client test, A may hold its
transaction open briefly after the command returns; B must be observed waiting on
the employee row or unique code before A commits. A sequential pair of RPC calls
does not meet this criterion.

The read-only connector probe on 2026-09-25 returned different backends (2466249
and 2466263), but their two-second query intervals were 03:09:25.102–27.105 UTC
and 03:09:28.588–30.590 UTC. They **did not overlap**, so it is not contention
evidence. The available connector cannot establish this gate by parallel calls.

## Required races and postconditions

| Race | Session A | Session B | Required result |
|---|---|---|---|
| Same employee code | Create UUID A with `EMP-RACE-01` and version 0; hold transaction before commit | Create UUID B with the same code and a different command/key | Exactly one create commits; the other gets code uniqueness conflict. One employee, spell, assignment, event and receipt exist for the code. |
| Same aggregate version | Schedule a future assignment from version N; hold transaction before commit | End the same employment spell from version N | Exactly one command commits; the other gets `VERSION_CONFLICT` after the lock releases. Employee version is N+1, timeline has no gap/overlap, and only the winner has a new event/receipt. Repeat with the order reversed. |
| Revocation and replay | Revoke the destination branch role or disable `module.people` and commit | Replay the original confirmed transfer envelope | Replay is denied with no old response exposed. Restoring access permits the identical sealed envelope to recover its original receipt; a changed body does not. |

Check the losing transaction's absence from `people.employment_events`,
`core.command_receipts` and downstream outbox/audit rows. Compare the winning
receipt's command ID, request ID, scope and version with the employee detail.
Use fresh synthetic IDs and clean the isolated fixture after recording evidence.

No attendance, payroll or work-allocation consumer exists yet. The W4-01
command conservatively rejects historical changes. A downstream-consumption
versus correction race remains an integrated acceptance gate once a governed
consumer is installed, and must pass before historical correction is enabled.
The lack of this later provider does not count as a passed race.

## Installation and acceptance boundary

The candidate's 49 pgTAP assertions passed before installation and the same 49
passed against the installed schema, each inside a separate rollback transaction.
They validate logic but do not establish this protocol's two-session result.
No tenant has People access yet. Once the dedicated synthetic tenant is
subscribed to the test plan and independent sessions are available, run the races
above, then perform the
user-managed authenticated Windows/MFA walkthrough before owner signoff.
