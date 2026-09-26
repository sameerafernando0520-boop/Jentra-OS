# Wave 3 tax controls, governed tax and recovery — 2026-09-26

Development candidate evidence only. `main` remains at `6595d14`; all changes in
this continuation are dirty and unstaged. Existing shared work, including concurrent
Wave 4 calendar work, is preserved. No migration was installed, no Git index or
commit was changed, no production action occurred, and no authentication or
stock-opening acceptance source, record, sequence or runtime was altered.

## Result and compatibility

Contract 38 now covers complete cumulative source-to-GL tax controls, with account
opening/period/closing balances and source-key differences. All posted GL activity
in proven current/historical tax accounts is considered, including undeclared manual
activity. A net-zero control balance cannot hide different source-key mismatches.
Missing source versions, journal provenance or historical return base allocations
remain explicit blockers. Bill-linked purchase returns preserve their original tax
date and exact cumulative-rounded original base, including the last cent.

Manual journals now optionally declare effective input, output or withholding tax
with exact taxable basis. Independent approval, recent MFA when configured,
version revalidation, separate atomic posting and immutable linked reversal reuse
the existing journal engine. Changing and restoring a rate still requires fresh
approval because its definition version changes. A foreign-currency tax amount of
`0.03` retains the six-place posted base `0.037037`, rather than a rounded two-place
replacement. The existing open-item and authentication engines are unchanged.

Settlements, reviewed adjustments and transfers are distinct control-only journal
source lines on proven asset/liability tax accounts. They change control balances
without reclassifying period tax accruals. The synthetic liability settlement
`10.037037` clears the declared output/withholding control; its linked reversal
restores the exact liability, preserving the tax totals and original frozen report.
This records a journal; it executes no external payment.

`/finance/tax` supplies frozen treatment, account, source, GL and difference drill.
`/finance/journals` supplies date-scoped tax choices, taxable basis and proven
control-movement choices. Gateway validation checks exact strings, arithmetic,
scope, filters and correspondence to the original command. Encrypted recovery
retains the sealed declaration/movement, and permission revocation clears evidence.

The committed base tax candidate is unchanged. Installation order, when separately
authorized, is `01000`, `02000`, `03000`, `05000`, `06000` as listed below, after
their existing journal/statement/cash-flow/budget dependencies. Version-one tax
reports remain readable; the version-two client and candidates need coordinated
installation. Concurrent Wave 4 `04000` is outside this chain.

## Verification

The final SQL compositions ran through the development Supabase connector in one
transaction each, with strict `finish(true)` and final `ROLLBACK`. Every fixture
and candidate DDL change rolled back. No migration ledger entry was added.

| Check | Observed result |
|---|---:|
| Procurement/finance rollback composition including all five tax candidates | 635/635 assertions |
| Receivables/reservations rollback composition with the same candidates | `1..169`, no failure |
| Inventory rollback composition with the same candidates | 105/105 assertions |
| Nine finance gateway/codec/encrypted-store suites | 79 passed |
| Eight adjacent desktop/recovery/golden suites | 104 passed |
| Full platform and desktop analyzers | No issues |
| Windows release compilation after final recovery corrections | Passed in 59.4 seconds; see `tax-controls-windows-build-20260926.log`; no launch |

Local execution logs are `tax-controls-platform-20260926.log`,
`tax-controls-desktop-20260926.log`, `tax-controls-platform-analyze-20260926.log`
and `tax-controls-desktop-analyze-20260926.log` in this directory. Database counts
above are the observed connector results; the checked SQL compositions below
identify the exact executed content. They are not installed-state evidence.

SQL tests include actual governed posting and reversal, scope and direct-access
denial, changed-definition approval invalidation, last-cent partial returns,
missing journals, source/account differences, FX precision, immutable saved evidence,
period-close blockers and late audit/outbox failure with complete rollback.

Ten new tax/control/journal light/dark 200% text renders were visually reviewed.
The controls, notice, exact values and confirmation remain reachable. The two
existing manual-journal baselines were reviewed and refreshed for a small border
rendering difference; their labels and amounts did not change. The tax movement
selector is also exercised at 720-pixel desktop height and 200% text.

Solo review found and corrected two client recovery races. A read started before
a disconnect can no longer restore cleared evidence after connectivity returns;
fresh verification is required. Confirmation now replaces the sealed request and
confirmed report form in one encrypted database write, preserving the original
request if writing fails and preserving the confirmed report if the route closes.
Delayed initialization, treatment/control drill, offline confirmation and route
disposal tests exercise these paths for tax reviews and financial statements.
The shared store also verifies wrong-command/scope rejection, an injected SQLite
write failure preserving the identical sealed retry, and encrypted confirmed-state
recovery after closing and reopening SQLite on disk. This is not
a Windows Credential Manager process restart.

## Exact content

SHA-256 at verification:

| Candidate file in `supabase/migrations/` | SHA-256 |
|---|---|
| `20260926001000_wave3_tax_summary.sql` | `DCEF36D0DCBF6B5277E6A79F625314D7595434CD88CED42271BAA1CFA86B4969` |
| `20260926002000_wave3_tax_summary_hardening.sql` | `7976C8C944FD776729E4C67949706C1265BB0B5DF04B076E83DB301E8164DDEE` |
| `20260926003000_wave3_tax_control_reconciliation.sql` | `51FB81AB482FDD6E2091ED46ADD2E2EFA0C377528950393469EF721F081FE17B` |
| `20260926005000_wave3_governed_journal_tax.sql` | `78AE3CF5EE32B220F164431BDC0891DC5F87E04C7EEB079AE5665A9462EE2910` |
| `20260926006000_wave3_tax_control_movements.sql` | `41C09E5C0F8B6E40C1FCA225E4F04196101B1012EBB88EF954234EEE4C1E682D` |

`supabase/tests/build_tax_summary_candidate.ps1 -Suite <suite>` constructs the
following ignored `build/` compositions. Preserve the SQL content when reproducing
the hash; the builder itself returns text and enforces the rollback boundary.

| Composition | SHA-256 |
|---|---|
| `tax-controls-procurement.sql` | `F9A207C8F94E50D9D665A4BAA3494B79FA7916D25F9533A0C4A371F72B6A870E` |
| `tax-controls-receivables.sql` | `5E7613D75C258932339B8A7B2AD3B3B93F89E0678922ED9BEEB0FCB4EE2EA990` |
| `tax-controls-inventory.sql` | `11731DBF668144BF16CEA05B3CA0DD1ACB5A81080CCE31EC6B5A0B00F4940489` |

## Ledger and remaining boundary

The successful development refresh before these rollback runs reported
`xpdoufauvrbdmxgngetv` ACTIVE_HEALTHY on PostgreSQL 17.6.1.166, with **35 installed
migrations**, ending at `20260925181927_wave4_employee_foundation`. Tax tables and
new tax RPCs were absent outside the rollback transaction at that refresh.

After the task's plugin update the Supabase connector was no longer callable.
The configured CLI health-refresh attempt returned `Unauthorized`; credentials
and authentication were not changed. A final independent ledger/catalog/advisor
refresh remains pending reconnection. Do not describe the earlier refresh as a new
installed/native verification. The next database candidate must start with that
fresh development ledger and finance-primitive check.

Wave 3 remains open. Next reporting development is GRNI source-to-GL reconciliation,
inventory/cash and operational report consolidation, governed cost-centre/project
dimensions where available, and attributable bounded report exports. Broader landed
allocation/corrections, oversized count partitioning, disposition and attachment/
source navigation also remain. Statutory rules and supplier withholding allocation
are not supplied by this journal declaration contract. Real multi-session contention,
load/query-plan proof, candidate installation, Credential Manager process recovery,
authenticated native walkthrough and owner signoff remain separate gates.

Before installation review compatibility, grants, signatures and trigger order.
Candidate rollback is the current recovery mechanism. After installation preserve
immutable history and use reviewed forward corrections; no history removal or
production rollback was performed here. The earlier `tax-review-20260926.md` is a
historical checkpoint superseded by this tax-control and recovery evidence.
