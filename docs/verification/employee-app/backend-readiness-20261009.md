# Employee companion backend boundary

Read-only installed-catalog check: 9 October 2026, Jentra development project `xpdoufauvrbdmxgngetv`. This build did not install migrations, change permissions, create accounts or perform employee commands against that database. Automated adapter tests use synthetic HTTP responses.

| App surface | First-build behavior | Backend boundary |
| --- | --- | --- |
| Sign-in and workplace choice | Uses existing account and active memberships/entities/branches | Installed foundation APIs; every start requires online account validation |
| Accepted employee identity | Resolves the account's accepted employee link | Installed `people_hr_self`; no email matching or arbitrary employee input |
| Pending account link | Explicitly review employer, branch and employee before responding | Installed own `people_hr_link_inbox`; legacy `people.view` requirement can prevent onboarding and must be handled by HR |
| Shared reviews | Read resolved employee's reviewed, acknowledged and closed records; explicitly acknowledge receipt | Installed private-HR APIs; dedicated server employee-only projection is still a release hardening dependency |
| Leave | Prepare/edit/delete one protected local draft per employee/workplace | No installed employee leave balance or submission API; no leave approval or balance change is claimed |
| My work | Explains current availability and HR contact path | Employee attendance and schedule contracts are absent from the installed catalog |
| Pay | Explains payroll availability; no amounts or paid status | Employee payslip/detail/export contracts are absent; staff payroll APIs are not used |
| Documents and HR requests | Explain current availability and HR contact path | Employee-safe document/case services are not integrated |
| HR actions | Derives acknowledgement actions from current shared review pages | This is not a durable recipient notification inbox or push service |

## Before employee rollout

Run an authenticated walkthrough with existing approved employee accounts in the intended company and branch. Verify accepted-link identity, denial/revocation, MFA policy where required, exact command receipts after interrupted connectivity, protected storage/restart/expiry and native app-switcher behavior on physical Android/iPhone devices.

Provide the employee-only server review projection before enabling accounts with staff review rights for rollout. The current adapter discards draft/submitted records before producing UI models, but the legacy wire page can include those records under staff rights. App-side filtering is not a replacement for server data minimization.

Add the reviewed employee-safe attendance, leave, payroll, documents/cases and recipient inbox contracts from the mobile blueprint. Payroll rules, employer policy and payroll-owner acceptance remain separate from app packaging. No additional staff grants should be used to bypass a missing employee contract.

The deliverable here is the first development app slice. The full E1/E2 roadmap, native acceptance, release signing and owner signoff remain open.
