# W4-01 native acceptance checklist

**Status:** Pending. The dedicated `w4_employee_synthetic` plan has no
subscriber yet. No authenticated Windows/MFA walkthrough has been recorded.
The owner reported workspace creation, but a fresh development-database read on
2026-09-26 still found no tenant with slug `w4-employee-synthetic`; the app
result/target must be reconciled before a subscription is changed.
Use only synthetic employee data. Sign-in and MFA stay with the owner; do not
share credentials or codes with the test operator.

## Owner bootstrap of the separate tenant

Sign in with a separate test account that has no Jentra business membership.
On the dashboard, use **Create workspace** with these synthetic values:

| Field | Value |
|---|---|
| Business group name | W4 Employee Synthetic Lab |
| Workspace slug | `w4-employee-synthetic` |
| Registered entity name | W4 Synthetic Operations |
| Entity code | `W4OPS` |
| Branch name / code | Head Office / `HQ` |

The normal bootstrap creates a starter trial, owner membership and audit event.
Once this workspace exists, verify its slug and move only its subscription to
`w4_employee_synthetic`; keep Jentra Acceptance Lab on starter. The owner can
then complete MFA and add a second synthetic branch through the setup flow for
transfer tests. No account password or MFA code is needed for this handoff.

## Preconditions

1. Confirm development ledger version `20260925181927` and an enabled
   `module.people` entitlement on a dedicated synthetic test plan only.
2. Use a synthetic tenant/subscription and two authorized branches. Grant the
   test membership the exact People view/manage/history capabilities needed for
   each scenario; retain a second, denied branch/role for scope checks.
3. Build/run a Windows app from the verified source in isolation. Record build
   identity, tenant/entity/branch, actor role, MFA state and local time. Do not
   overwrite the stock-opening acceptance binary or session.

## Owner walkthrough

1. Sign in and complete MFA personally. Open **People → Employees** at
   `/people/employees`; check an empty branch/date/status and a populated branch.
2. Create a synthetic employee with a unique code, start date, job title and
   employment type. Verify one identity, version, assignment and attributable
   scoped-history event. Check search and as-of date.
3. Schedule a future assignment to the second authorized branch. Verify the
   source and destination views on dates before and after the change, then
   cancel the scheduled change with a reason. Confirm the original event stays
   in history and the corrected timeline has no gap or overlap.
4. End employment using the first day no longer employed, then record a future
   rehire. Verify the same employee ID/code and nonoverlapping spells. Check
   denied branch access returns no protected employee data.
5. Save an encrypted draft, restart Windows/app and recover it through the real
   Credential Manager path. In a controlled network-failure case, retain the
   sealed uncertain request, retry its original envelope and confirm exactly
   one server receipt. Do not reset or overwrite acceptance-owned local data.
6. On the dedicated test plan, revoke People access after data is loaded.
   Confirm the client clears the employee details and retry stays denied. After
   restoration, use the fresh retry and verify scope and history again.
7. Inspect light/dark layouts at 200% text, keyboard focus/action reachability,
   inline validation and error copy. Record screenshots and observed results.

Record each step as pass/fail with evidence. The separate
[two-session contention protocol](employee-contention-20260925.md) must also
pass before W4-01 owner signoff; this checklist alone cannot establish it.
