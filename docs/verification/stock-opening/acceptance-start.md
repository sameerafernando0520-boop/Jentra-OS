# Signed-in stock-opening acceptance: prepared scenario

Date: 2026-09-11. Development project: `xpdoufauvrbdmxgngetv`.
This document is a prepared walkthrough, not a record of posted transactions.

## Latest continuation checkpoint

16 September review: live connectivity restored; 120 rollback-only database
assertions and 46 focused application tests passed. Still zero invitations,
stock-opening workflows, openings and journals; both sequences remain next 1.
No persistent acceptance action occurred. See [fresh review](review-20260916.md).
The actual client invitation failure remains unresolved pending its exact response.

Journal sequence follow-up: the user saved the journal sequence. Fresh native
list and database reads confirm `a908a53c-8b7f-421b-a02f-1922e8d9f9ce`, `journal`,
`ACPT-JRN-`, blank suffix, padding 5, next 1, never reset, active, JAT/HQ.
The agent observed the saved result, not the user's save click. Both numbering
prerequisites are complete. Next is the scoped independent approver invitation.

Continuation refresh, 2026-09-12 12:44–12:48 UTC: clean `main` at
`0ac613b1563f8edfeb8e5f75061f7ab79867af36`; the previous continuation changes
are now committed by prior work. No Git mutation was performed this session.
Development remains ACTIVE_HEALTHY, 34 migrations/latest `20260911130900`.
All saved prerequisite UUIDs and values in setup-targets.json were reverified.
Journal sequence, workflows, approval steps, invitations and stock openings
remain absent; the independent approver still has zero memberships.

The existing development executable was launched and the owner session restored.
Observed Jentra Acceptance Lab / JAT / Head Office and the saved opening sequence.
Opened New document sequence; confirmed document-type focus, then attempted
`journal` using supported `sky.type_text`. The field remained visibly blank.
No save was submitted. The form remains open for manual Document type `journal`
and Prefix `ACPT-JRN-`; defaults are blank suffix, padding 5, next 1, Never, Active.
The user was asked to enter those values and Save to server. Requery before any
creation attempt; do not reset existing numbering.

See [continuation refresh](continuation-refresh-20260912.md) for migration/build
identity and setup-contract review. No source or database correction was required
by the observations so far. Transaction acceptance, recovery, contention,
reconciliation and owner signoff remain pending.

Handoff refresh at 2026-09-12 12:37 UTC: clean health, main `e307d15` with
all continuation work still uncommitted, 34 migrations/latest `20260911130900`.
Persistent counts: warehouse 1, unit 1, accounts 2, period 1, products 2,
stock_opening sequence 1 (next 1). Journal sequence, workflows, approval steps,
invitations and stock openings remain zero. `test@lh.com` has zero memberships.
The last observed native screen was a blank New document sequence form for the
journal. Reobserve on resume. Full continuation instructions are in
[next-session-prompt.md](next-session-prompt.md).

Stock-opening sequence saved by the user and verified in native list/database:
UUID `1cdca8f2-d57c-4133-b7e3-54ca38f71756`, document type `stock_opening`,
prefix `ACPT-OPEN-`, blank suffix, padding 5, next value 1, never reset, active.
The journal sequence is still absent. Opened a fresh New document sequence
form for `journal` / `ACPT-JRN-`; the same default numeric/reset/status values apply.

Sequence continuation: database still has zero document sequences. Navigated
native Governance / Document numbering and opened New document sequence.
Defaults observed: padding 5, next number 1, Never, Active, blank suffix.
Typing `stock_opening` through the helper left the focused field blank. No save
was attempted; manual document type and prefix entry is needed in this form.

Warehouse saved by the user and verified in the native list and database:
`ACPT-WH` / `Acceptance warehouse`, active, correct JAT/HQ scope, UUID
`ae045bc4-3851-4861-9eaf-fb6a8cf6ba75`. Read-only sequence refresh returned no
rows. Next: stock_opening and journal sequences, then workflow/matrix and
independent approver access. Native navigation attempts repeatedly reported
user input; no sequence mutation was attempted.

Native unit and product imports are complete: the agent selected the CSVs,
reviewed the full accessible preview fields, clicked Apply import and verified
the saved UI lists and database records. EA is Each / ea / quantity / precision
0, UUID `991c28ad-80b9-4201-8e60-952eac63e912`. ACPT-PAPER is stocked/untracked,
UUID `10436803-0bd6-4498-8653-14c327551b9d`; ACPT-TONER is stocked/lot,
UUID `432539d4-0375-4e1b-8a1b-e7fc7c9405e2`. Both reference the saved EA and
1300 account UUIDs. All are active. The file-picker modal screenshot coordinates
worked once the prepared folder was open; ordinary text entry still did not.
The New warehouse form is open at HQ/Active; an attempted ACPT-WH text input
left its code blank. No warehouse save was attempted. Remaining setup:
warehouse, sequences, workflow/matrix and independent approver access.

The fiscal period has also been saved through native setup. UI and read-only
database inspection agree: `Acceptance September 2026`, JAT, 2026-09-01 through
2026-09-30, open and active, UUID `fd5ffd17-7ad1-4a7c-9c47-0d2094f05b3d`.
The user completed the import while the agent was observing; the agent did not
observe the preview/apply clicks. Next prerequisite is the EA unit.

September 12 account import follow-up: the user completed CSV import. Native
Chart of accounts shows exactly two active records. Read-only database inspection
confirms the expected JAT entity, LKR currency and posting flags: 1300 Acceptance
inventory is asset/debit, UUID `2c3f29b0-575b-492b-99d6-e4214cbc6019`; 3100
Acceptance opening equity is equity/credit, UUID
`bfa59c6f-2937-4829-95d9-4b199d22d3ce`. The agent observed the saved result,
not the user's preview/apply clicks. Next: native fiscal-period CSV import, then
EA unit. Product references must use these saved IDs and the eventual unit ID.

September 12 local refresh (2026-09-11 19:10:36 UTC): development remains
ACTIVE_HEALTHY with 34 migrations, latest `20260911130900`. Warehouses, units,
accounts, products, periods, sequences, workflows, approval steps, invitations
and openings are still zero. Relaunched the existing build and observed the
restored owner session and JAT/HQ scope. Reopened the account import picker;
the helper's Alt+N input did not change focus to File name. Manual file selection
is still needed. No setup mutation was submitted. Use the actual local opening
date when creating the draft; September 2026 still covers September 12.

2026-09-11, after 13:11 UTC: the checkout was refreshed as clean `main` at
`e307d15`, ahead of the original handoff. The missing governed stock-opening
approver invitation and in-app recipient acceptance flow is now implemented.
Development migration `20260911130900` is applied (34 migrations total).
See [approver setup verification](approver-setup-verification.md) for the 40
rollback database assertions, 159 desktop tests, three API tests, compatibility,
analyzer, rendered form and development Windows build evidence.

The updated release built in 58.1 seconds and reopened with the owner's session
restored. Native observation confirms Jentra Acceptance Lab / JAT / Head Office
and the new invitation action. Session restoration does **not** establish
stock-opening draft/retry recovery. Windows helper text entry and accessibility
input still fail; even the native import file picker cannot be filled reliably.
The account import picker is open pending manual selection of
`prepared-imports/accounts.csv`, after which the agent can inspect/apply the
governed preview. No import was applied by this checkpoint.

All prepared business prerequisites and `test@lh.com` membership remain absent.
The approver role is created only when the authenticated invitation command is
used; the migration did not seed it. Accounts, unit and fiscal-period CSVs are
prepared; product UUID references still depend on actual saved records.

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
