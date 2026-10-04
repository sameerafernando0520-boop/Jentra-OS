# W4-08 contention, load and native acceptance protocol

Prepared 2026-10-04; not executed. Sequential rollback assertions, native test
fixtures and builds do not satisfy these gates. Use the separately bootstrapped
synthetic workspace with verified owner attribution, exact test plan and scoped
roles. Preserve Jentra Acceptance Lab and all ACPT-* data. Sign-in/MFA stays with
the owner. Candidate installation and provider readiness must be verified first.

## Separate overlapping database sessions

Use two independent authorized database connections in an isolated synthetic
environment. Record backend PID, transaction/command start, command finish and
commit times from each connection. In session A, BEGIN, invoke the real named
command, retain the transaction briefly, then COMMIT. Start B's competing command
before A commits. A third read-only connection must record B waiting on A's lock
or unique constraint. Repeat each race with actor/order reversed and fresh IDs.
Do not claim overlap from adjacent connector requests. Database role fixtures
prove transaction behavior only; authenticated user acceptance is separate.

Read-only observation query, run while the second command is waiting:

```sql
select pid, xact_start, query_start, wait_event_type, wait_event,
       pg_blocking_pids(pid) blocking_pids
from pg_stat_activity
where datname = current_database()
  and pid = any(:recorded_test_backend_pids);
```

Store no credentials, bearer tokens, private source bodies or salaries in evidence.
Retain the exact non-sensitive command IDs/keys/versions and expected scope.
Use the actual envelope fields from the typed gateways and current reviewed SQL.

| Race | Competing real commands | Required result |
|---|---|---|
| Employee code | people_employee_command create, distinct IDs with same code | One identity/spell/assignment/event/receipt; loser safe unique conflict. |
| Employment timeline | assignment versus end/correct at same version | One next version, no overlap or deleted history; stale loser no effects. |
| Department/manager graph | competing organization parent/manager changes creating a joint cycle | At most one compatible change; no cycle at any affected date. |
| Consumption versus timeline | common work/source approval versus employment/org cancellation | Original consumed basis retained or explicit impact required; no invalid eligibility. Historical enabling stays blocked until this passes. |
| Leave balance | independent leave approvals competing for same remaining balance | Balance never exceeds approved policy; one safe loser, original cancellation exact. |
| Work ownership | attendance/project/service approvals overlapping one employee interval | One payable owner; project/service allocation never doubles payable seconds. |
| Payroll posting | same approved run/correction post from two keys | One complete journal, obligations, payslips and source seals; no duplicate effects. |
| Payroll reversal | post/settle versus original-effect reverse | Serialized version/period/settlement decision, balanced immutable lineage. |
| Linked source correction | source billing reservation/post versus linked correction/reverse | Reserved source requires resolution; billed source requires actual full posted current credits; no restored historical unit. |
| Project billing | overlapping reservation batches with at least one shared unit | One unit consumed once; losing batch has no invoice/receipt/partial reservation. |
| Milestone approval | plan/progress change versus milestone decision/billing | Frozen eligible approved basis or safe stale decision, one whole source unit. |
| Service dispatch | dispatch/employee timeline or competing resource reservations | Valid employment/calendar/equipment/capacity, no incompatible assignment. |
| Parts | two real stock reservation/issue/return commands for the last quantity | Installed provider conserves issued/returned stock and cost; absent provider is unavailable. |
| Maintenance | duplicate calendar/meter occurrence commands | One occurrence/order, original reset/rollover/deferral retained. |
| Assets | duplicate capitalization or depreciation versus disposal | One ownership claim; no duplicate stock/asset cost or post-disposal depreciation. |
| Revoked replay | committed module/role/MFA revocation followed by original receipt/replay | Denied without old private response; restoration recovers only the exact original envelope. |

For every losing command, check absence of new module event/history, journal,
obligation, source consumption, receipt, redacted audit and required outbox rows.
An injected late failure must roll back all those effects. Compare row totals and
immutable lineage with the winning confirmed receipt. Store observations and
postcondition queries/results as attributable evidence, not a prepared pass.

## Reproducible load workload

Record source and installed migration hashes, project/region, dataset size,
page/filter mix, authenticated role/MFA, warm-up, request count and concurrency.
Use at least 100 measured observations per ordinary-read/command family after
20 warm-up observations; report failures separately rather than dropping them.
Use the sorted nearest-rank p95 observation at ceil(0.95 * n), in milliseconds.
Targets are 500 ms ordinary reads and 1,500 ms ordinary commands. Record cold and
warm runs separately and include server-side lock waits where available.

Measure directory/detail/history/pickers for employee, calendar/organization,
private review, attendance/leave, payroll/corrections, projects/finance/milestones,
service/equipment/maintenance and assets. Measure only explicitly authorized
synthetic writes and original idempotent retries. No private export or bank
execution is implied. Test default 50-row pages, upper bounds, literal search,
foreign/stale cursors, empty result and denied scope. Verify payroll's 200-employee
and 100-component limits, project 200-task/366-slot limits, and correction's
50-linked-entry bound fail before effects. Missing providers are recorded as
unavailable, not latency successes.

## Authenticated Windows walkthrough

Build a separate verified source snapshot and record its binary/source hashes.
Configure it through the owner-managed development workflow. Do not replace the
acceptance binary or copy its local authentication/draft stores. The owner signs
in, completes MFA and selects the verified synthetic scope. A second independent
authorized actor performs decisions requiring independence.

1. Exercise each real workspace's empty/populated/loading/error/denied/unavailable
   state, filters, named choices, detail, original history and permitted actions.
2. Create/schedule/end/rehire synthetic employment, original calendar/organization
   assignments and private review/link flows. Verify private worker readiness,
   legal hold and byte/export/erasure authorization before private content.
3. Approve attendance and leave, inspect common ownership, post exact synthetic
   payroll and recorded settlements, then linked corrections and reversals.
4. Plan projects with owners/dependencies/resources, approve/reject the complete
   original plan, record exact time/expense/milestone and bill through the actual
   invoice workflow. Reconcile dated cost/revenue/credits and immutable lineage.
5. Complete service triage/SLA/dispatch/work/customer confirmation/closure,
   equipment/maintenance occurrence and actual installed parts behavior. Exercise
   asset capitalization, independently governed depreciation/disposal/reversal.
6. Lose a command response, close and restart the real Windows app, recover its
   exact sealed request through Credential Manager, and reconcile one receipt.
   Repeat confirmed cleanup/storage failure and current access revocation. Never
   regenerate a request or clear a store to make the test pass.
7. Inspect both themes/densities at 1024x720 and 1920x1080, 200 percent text,
   keyboard/focus/tab traversal and all scrolled controls. Record actual screenshots
   and observed outcomes; rendered test previews alone are insufficient.

Attach pass/fail/evidence for AC-401 through AC-420 and EC-401 through EC-416.
The owner reviews actual evidence and unresolved exceptions. Keep Wave 4 open
until installation, runtime, real contention/load, restart and signoff evidence
are present. This protocol is runnable preparation, not their completion.
