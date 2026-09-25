# W4-01 development installation review

**Decision:** Pending owner authorization. No migration or People plan entitlement
has been installed/enabled.

## Exact proposed change

- Target: Supabase development project `xpdoufauvrbdmxgngetv`, not production.
- Candidate: `supabase/migrations/20260925001000_wave4_employee_foundation.sql`.
- Reviewed SHA-256: `CF87FF4FEF5041394D28FAAF265D98762D90FCC14FE1B0DE4A6828477D695BFC`.
- Apply the candidate once through the migration ledger. It creates the People
  employee schema, scoped API, permissions and audit/event contracts. It inserts
  `module.people` disabled for every existing plan. Installation alone does not
  grant role capabilities or make the module available to subscribers.

## Current evidence and checks after installation

The live ledger currently has 34 installed migrations through `20260911130900`;
`people.employees` and the employee command RPC are absent. The candidate plus
49 pgTAP assertions passed inside a transaction ending in `ROLLBACK`. Four
domain, one encrypted restart and nine desktop/controller/UI tests passed;
focused analysis and an isolated Windows release build passed. The plan-denial
view was visually inspected at 200% text. This is development candidate evidence,
not proof of installed or authenticated behavior.

After authorized installation, verify the new ledger entry and object definitions,
rerun advisors, and prove every existing plan remains disabled. Use only a
coordinated synthetic test plan/tenant for access tests, then run the
[two-session contention protocol](employee-contention-20260925.md) and the
user-managed authenticated Windows/MFA walkthrough. Record each as a separate
result before W4-01 acceptance.

## Risk and coordination

The target is a shared development database with other Wave 3 candidate
migrations in the checkout. Installation creates persistent schema and ledger
state; it is not undone by a rollback of later tests. Coordinate migration order
with the concurrent Wave 3 owner before installation. If an installed migration
needs repair, use a new forward migration or a disposable branch; never edit an
applied migration in place. No plan should be enabled as part of installation.

The Supabase SQL connector did not establish two overlapping sessions, so
installation by itself cannot close the contention gate. A separate pair of
independent database/API sessions is required for that evidence.
