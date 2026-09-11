# Signed-in stock-opening acceptance: prepared scenario

Date: 2026-09-11. Development project: `xpdoufauvrbdmxgngetv`.
This document is a prepared walkthrough, not a record of posted transactions.

## Observed progress

The development-connected Windows build passed in 258.2 seconds. Generated build
defines match the ignored development configuration; the native executable was
opened successfully. The user created two synthetic accounts and signed in.
Fresh native observation showed the first-workspace onboarding form, then the
user navigated to the design-system catalogue. A read-only database refresh
confirmed two users, zero verified MFA factors and zero tenants at that point.
UI input was paused to avoid competing with the user's active navigation.

The user subsequently asked the agent to fill the prepared form and reserved
creation and MFA for manual completion. Form entry could not be verified:
the Windows helper repeatedly reported user input or unavailable cached element
IDs despite fresh state/window selection and a focus retry. No Create workspace
submission occurred. The prepared values below remain the manual handoff.

Later refresh, 2026-09-11: the user has now created the workspace and completed
MFA. Read-only counts confirm two users, one verified factor, one tenant, one
active membership, one role assignment and 87 role permissions. The native
dashboard shows Jentra Acceptance Lab. Investigation of the reported inactive
controls found stale capability caching across MFA and empty Quick create
handlers; see `auth-controls-verification.md` for the repair and runtime result.

Account creation and sign-in were not automated. Governed business setup,
independent approver membership and the opening acceptance scenario remain
pending. The remaining sections describe the prepared scenario and historical
pre-build counts.

The user subsequently confirmed the repaired creation/navigation controls work
and requested the prerequisite setup. The designated independent approver is
`test@lh.com`; the account exists but has no workspace membership. The next
implementation adds the missing governed warehouse setup command and form.
That command and form are now implemented and the development release is rebuilt;
see `warehouse-setup-verification.md`. The reopened native app is at sign-in.
Actual prerequisite record creation is waiting for the owner's authenticated
session; the prepared values are also recorded in `setup-targets.json`.

## Initial prerequisites

The live read-only preflight found a healthy project with 32 migrations, latest
`20260910201410`, and zero users, verified MFA factors and tenants. The ignored
`.env.acceptance.json` selects `development`, the verified Jentra project URL
and a public publishable key. No credentials or service-role keys were read.

The desktop has sign-in controls but no account-registration form. Create two
synthetic accounts in the development project's Authentication area, then sign
in to Jentra as the owner/preparer. Keep passwords and MFA codes outside chat.
The first account creates the test workspace; its owner authority stays locked
until the session completes MFA. The independent approver must join that same
workspace and have the configured approval role and cost visibility.

Authentication and MFA are handled by the user. The Computer Use skill's required
guidance states: "Do not automate user authentication dialogs."

## Governed setup after owner sign-in

Use the existing onboarding and Business Setup Centre. These are proposed
synthetic values; no rows have been inserted by this preflight.

| Item | Proposed value |
| --- | --- |
| Business group | Jentra Acceptance Lab |
| Workspace slug | `jentra-acceptance-lab` |
| Legal entity | Jentra Acceptance Trading, code `JAT`, LKR |
| Branch | Head Office, code `HQ` |
| Warehouse | Acceptance warehouse, code `ACPT-WH` |
| Unit | Each, code `EA`, whole quantities |
| Inventory account | Active posting asset account, code `1300` |
| Equity offset | Active posting equity account, code `3100` |
| Period | Open period containing the actual opening date |
| Numbering | Active `stock_opening` and `journal` sequences |
| Workflow | `stock_opening`, independent scoped approval required |

Choose unused codes if any later user-created setup already occupies these
values. Verify product inventory mappings, currency/unit precision and the
current period before preparing the count.

## Opening scenario and expected reconciliation

| Stocked product | Tracking | Base quantity string | Base value string |
| --- | --- | --- | --- |
| `ACPT-PAPER` - acceptance office paper | None | `250` | `187500.00` |
| `ACPT-TONER` - acceptance toner | Lot `ACPT-LOT-001`, expiry `2028-09-01` | `10` | `61000.00` |

Use the actual current date in the open fiscal period and a reason such as
"Synthetic acceptance opening count". Expected total: **LKR 248,500.00**.

1. Create and locally recover the draft, then save through the opening RPC.
2. Submit as the preparer. Verify that the preparer cannot approve it.
3. Sign in as the independent approver, complete MFA and approve the count.
4. Return to the preparer, complete MFA and post the approved count once.
5. Verify quantities of 250 and 10, lot identity, aggregate valuation
   of LKR 248,500.00, an inventory debit of LKR 248,500.00 and an equity
   credit of LKR 248,500.00. Reconcile source IDs, receipt and journal references.
6. Verify identical-command retry produces no duplicate movement or journal,
   then continue the sales-to-receivables acceptance scenario.

Capture actual authenticated evidence before marking any step passed. Native
opening-specific process-kill recovery and final user signoff also remain open.

## Build and launch evidence

See `acceptance-windows-build.log` for the development-configured build and
`acceptance-start.json` for the resulting executable hash and native sign-in
observation. Earlier unconfigured release evidence remains historical.
