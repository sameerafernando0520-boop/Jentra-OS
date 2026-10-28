# Employee HR event producers candidate — 27 October 2026

This is additive, uninstalled candidate source. No migration was installed and no
sender, scheduler, role assignment or plan entitlement was activated. The original
[employee push candidate](../../supabase/candidates/20261023090000_employee_push.sql)
and the existing self-service/cases candidates are read-only prerequisites for
this change.

## Selected gaps

The [cases/documents candidate](../../supabase/candidates/20261025100000_employee_cases_documents_notifications.sql)
already produces leave outcomes, review publication, normal payroll posting and
reversal, HR replies and explicit document publication. These do not need a second
producer. The new [HR event candidate](../../supabase/candidates/20261027100000_employee_hr_event_producers.sql)
adds the following missing employee outcomes, in priority order:

| Producer | Authoritative source | Employee value and event identity |
| --- | --- | --- |
| Attendance decisions and corrections | Insert into immutable `people.attendance_events`, after canonical entry/revision changes | Approval, rejection, cancellation, reopening of approved attendance, and approved geometry corrections affect the employee's attendance/pay inputs. Uses the current entry ID and version. Draft edits and submissions stay quiet. |
| Payroll correction publication and reversal | Transition of `people_payroll.corrections` to `posted` or `reversed`, joined to the already-issued scoped correction payslip | A corrected or reversed pay result is visible through the existing own correction-payslip API. Uses correction payslip ID and correction version, avoiding collisions with normal payslips or another correction. |
| Employee request decisions | Insert into immutable `employee_self.request_resolutions` | Employees learn when staff resolve or decline attendance evidence and decline a leave cancellation. Uses resolution ID at version 1. |

Resolved attendance intake is a separate decision from canonical attendance
approval: the approval can happen before staff link the employee's evidence.
Both outcomes can produce a generic notice. A resolved leave cancellation uses
the existing canonical leave cancellation notice, avoiding a second wake from
the resolution row. This also covers staff linking an already-cancelled request;
no old history is backfilled.

Calendar/organization changes, raw clock imports, draft records, preparation and
approval of unpublished payroll corrections are outside this focused slice.
Calendar/organization fan-out needs a separate effective-date and recipient
policy; draft changes are not published employee outcomes.

## Authority and preservation

All three producers call the unchanged `employee_self.notify_employee` helper.
It records the event identity, checks the accepted account link, current scoped
employment, membership, People entitlement and recipient permissions, then inserts
one generic `people.employee.attendance`, `people.employee.leave` or
`people.employee.pay` notification. Pay retains the existing payslip permission
gate. It does not impersonate the employee or change JWT claims.

The unchanged `employee_push.enqueue_notification` trigger mirrors that insert
to the exact recipient's current devices in the same entity and branch. Dispatch
still rechecks recipient/session authorization. No trigger calls the sender or
makes a network request. No attendance reason, decision note, salary, calculation
or employee identity is copied into notification content or push payloads.

Attendance and correction-payslip lookups bind tenant, legal entity, branch,
employee and source identity. Event deduplication remains owned by
`employee_self.notification_events`. Replaying the canonical command creates no
additional source event; repeating an event for the same entry/version cannot
create another inbox row or outbox delivery. Events suppressed by recipient
revocation are consumed without historical delivery when access returns.

The candidate adds only three internal trigger functions and three triggers;
all function execution privileges are revoked from `public`, `anon`,
`authenticated` and `service_role`. It adds no API, table, permission, grant,
role assignment, entitlement, receipt mutation or migration-ledger entry. It
does not replace any existing function, trigger or migration.

## Rollback-only verification

The [focused harness](../../supabase/candidates/tests/employee_hr_event_producers_test.sql)
composes, in order, the existing push, self-service and cases/documents candidates
and the new HR event candidate inside a single `BEGIN` / `ROLLBACK` transaction.
It runs outside default database test discovery. The
[local-only runner](../../supabase/candidates/run-employee-hr-events-test.mjs)
inlines these exact files and reuses the existing owned-directory cleanup and
`supabase test db --local` lifecycle. It refuses linked projects, database URLs,
extra includes and candidate transaction controls.

```text
node --test supabase/candidates/tests/employee_hr_events_runner.test.mjs
node supabase/candidates/run-employee-hr-events-test.mjs --check
node supabase/candidates/run-employee-hr-events-test.mjs --run-local
```

The runtime suite exercises authenticated canonical attendance commands with
independent staff actors, staff request decisions, command replay, event
deduplication, exact recipient outbox delivery, privacy and recipient revocation.
Payroll correction fixtures exercise trigger timing and identities using
synthetic source transitions; they do not establish financial posting correctness.
Preservation assertions compare existing function definitions, permissions, role
assignments, entitlement and migration-ledger state across candidate creation.
CI runs the new suite on its already-migrated isolated database after the existing
candidate suites. No default migration directory is changed.

Current verification on 27 October 2026:

| Check | Result |
| --- | --- |
| New runner safety tests, including actual source composition | 5/5 passed |
| Existing sender, push-contract, push-runner, self-service-runner and cases-runner regression tests | 25/25 passed |
| Focused PostgreSQL suite | 75 assertions prepared; **not executed** |
| Original push and self-service candidate SHA-256 comparison | Both unchanged |
| Scoped whitespace check | Passed |

The cases/documents prerequisite received concurrent case-owner changes during
this task. Those edits were retained; this producer change edits none of that
file. Its notification helper and source triggers remain the existing authority,
and composition was rechecked against the current prerequisite source.

The installed CLI 2.75.0 rejected the workspace's newer configuration keys before
connecting. Retrying with the already-present bundled CLI 2.122.0-beta.14 and
telemetry disabled reached the local-only connection, which failed with
`ECONNREFUSED 127.0.0.1:54322`. No local database was running, and no stack was
created, migration installed or sender deployed. The staged suite was cleaned up
after both attempts. The new isolated CI step is configured but has not been run
as part of this workspace task.

SQL execution requires a running isolated local Supabase stack with a compatible
CLI. Source assembly and Node tests alone do not establish PostgreSQL execution,
hosted installation, FCM delivery, concurrent worker behavior or employee acceptance.

## 28 October CI preservation correction

The subsequent [CI run for `b842954`](https://github.com/sameerafernando0520-boop/Jentra-OS/actions/runs/40453773904)
executed the original 75-assertion HR suite: 74 passed and assertion 8, existing
function preservation, failed. In the same run, the existing database suite
(42 files / 7,369 assertions), push (47), self service (121) and cases (91)
passed. These are historical CI results for that committed source, not a passing
result for the current workspace.

The preservation comparison called `pg_get_functiondef` under different caller
search paths before and after candidate creation. PostgreSQL can qualify names
differently when deparsing an unchanged SQL function. The harness now uses a
temporary helper with a fixed empty search path for both snapshots. Function
body and execution-grant comparisons remain mandatory. Two focused assertions
verify stable deparsing and detection of a real body change; the suite now plans
**77 assertions**. This changes only the verification harness; the HR producer
candidate and original push candidate remain unchanged.

The [local preservation probe](../verification/launch-readiness-20261028/verify-function-preservation.mjs)
uses the exact helper from the harness in an isolated, in-memory PostgreSQL
engine (PGlite 0.5.12 / PostgreSQL 18.6). It reproduced the original false
difference and passed 5 checks: stable helper output, detection of real body
changes, detection of real ACL changes, and rollback of its own fixtures.
The [result](../verification/launch-readiness-20261028/function-preservation-result.json)
does not execute the full 77-assertion Supabase suite or establish PostgreSQL 17
compatibility. That full suite remains a required CI gate. No migration was
installed, no company deleted, and no sender deployed.

## Removal if later approved and installed

No persistent rollback is needed for the test suite: its transaction rolls back
candidate DDL, fixtures, notifications and deliveries together. A failed runner
connection closes the transaction without committing it.

For a future reviewed installation, pause the approved dispatch schedule before
removing this slice. In a reviewed transaction, drop only
`employee_attendance_event_notice` on `people.attendance_events`,
`employee_payroll_correction_notice` on `people_payroll.corrections`, and
`employee_request_resolution_notice` on `employee_self.request_resolutions`, then
drop their three matching `employee_self.notify_*` functions without `CASCADE`.
Retain existing inbox/outbox/event receipts and all HR data. Removing the triggers
stops future production; it does not recall a notification already queued or in
flight. Handling an existing queue remains an explicit operational decision.
The three prerequisite candidates and their original triggers remain intact.
