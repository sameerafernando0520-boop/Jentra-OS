# Wave 3 posted tax review contract (AC-320 / FR-375, FR-381–382)

Status: additive development candidates, **UNAPPLIED**. The committed base
`20260926001000_wave3_tax_summary.sql` is unchanged. Install order, when separately
authorized, is base, `20260926002000_wave3_tax_summary_hardening.sql`,
`20260926003000_wave3_tax_control_reconciliation.sql`, then
`20260926005000_wave3_governed_journal_tax.sql` and
`20260926006000_wave3_tax_control_movements.sql`. The concurrent Wave 4 calendar
candidate is outside this contract. This extends contracts 32 and 36–37 while
preserving authentication, stock opening, immutable open items and journal posting.
Every report is **non-certified** and requires statutory review before filing.

## Provenance and treatment

`finance.tax_definition_versions` privately captures the current Wave 2 definition
at candidate installation and later inserts/updates. Code, name, kind, rate,
inclusive/recoverable flags, status and effective dates are immutable by version.
Earlier versions cannot be reconstructed from the mutable setup row.

Supplier bill normalization and posting freeze the effective definition version.
Sales sources use their existing immutable snapshots. Bill-linked purchase returns
retain the original bill tax date and snapshot; a before-insert trigger freezes the
original tax journal's cumulative-rounded returned base amount. This preserves the
last cent across partial returns. A historical return without this base evidence
records `RETURN_TAX_BASE_UNVERIFIED`; current FX is never substituted for it.
Definitions are validated at the original tax date for sales/purchase returns and
linked journal reversals, so later retirement does not reclassify prior treatment.

`api.generate_tax_summary` accepts the normal command envelope, report UUID,
active fiscal period, cutoff within the period and optional branch filter. The
filter is the requesting branch or null for the entity. Entity and requesting
branch `finance.view` are both required. Saved requesting-branch reports are
immutable with receipt/audit/outbox evidence and exact six-place amount strings.
Version-two reports include current-period posted sales invoices/returns, supplier
bills, purchase returns and declared manual-journal tax lines. Totals distinguish
input, output, withholding, zero/exempt taxable bases and unverified tax. Different
transaction currencies are retained per source and never summed together.

Missing/ineffective versions, changed snapshots, missing journals, incorrect
amounts or source/treatment pairings create named blockers. Missing journals retain
the source date, currency and rate; expected exposure does not become zero. A
blocked report is saved for review, excludes blocked lines from treatment totals,
and always states `NON-CERTIFIED • STATUTORY REVIEW REQUIRED`.

## Governed journal tax

Manual journal lines can optionally supply `tax_definition_id` and exact
`taxable_amount` excluding tax. Effective active input/output/withholding
definitions are available through `api.manual_journal_tax_options`, a 50-row
UUID-paged, date-scoped API requiring finance read and journal permission.

The server freezes version, code, kind, rate, inclusive flag, original tax date,
rounding scale, signed direction and expected base amount on the source line.
The tax amount must equal taxable basis × configured rate / 100, rounded at the
entity's tax precision. Input requires an asset debit; output/withholding require
a liability credit. Existing AR/AP control restrictions still apply. Declaring a
tax does not execute a payment or alter an invoice/open item.

The journal's existing independent approval, MFA, separate posting, period lock,
atomic ledger, replay and immutability rules apply. Definition/rate/version changes
before posting require recall, save and fresh approval; restoring the old rate
does not restore its old version. Linked reversals ignore client replacement
metadata, negate the original direction and retain the original definition/date
and exact base allocation. Draft and approved declarations do not enter reports.

The `/finance/journals` editor selects tax treatment and taxable basis. Its
existing encrypted `manual-journal-editor` slot seals the full tax payload during
an uncertain command, including after controller recovery. Gateway confirmation
checks exact tax arithmetic, definition identity, scope and request correspondence.
Statutory rules, filing and supplier withholding allocation are separate work.

Tax-control settlements, reviewed adjustments and transfers use an optional
`tax_control_movement` on a journal line. The scoped
`api.manual_journal_tax_controls` picker supplies active posting asset/liability
accounts proven by current/historical input/output mappings or posted tax
declarations, including declarations whose tax definition has since retired.
An unrelated account cannot be relabelled as a tax control. An accrual declaration
and control-only movement cannot coexist on one line.

Control-only lines freeze their own signed direction and exact six-place source
base, follow the same independent journal approval/posting and linked reversal,
and reconcile against actual GL without entering period tax-accrual totals. A
recorded settlement can clear the liability while its period withholding/output
tax remains unchanged. Its reversal restores that liability and retains the
original movement classification. A journal record does not execute an external
payment. Plain, undeclared manual activity on a tax control remains visible as
unattributed evidence and a review difference.

## Cumulative control reconciliation and drill

The tax review compares supported immutable source amounts with **all** posted
activity through the cutoff in proven source accounts, current output mappings,
current/historical input controls and retired declared journal tax accounts.
Signed base amounts are debit positive and credit negative. Each account exposes
opening, period and closing source/GL amounts and their exact difference. Differences
are also retained by account and source/document/line key, including unassigned
sources and unattributed manual GL activity. Net-zero account balances cannot hide
different source-key differences. Assigned summary balances exclude unassigned
sources; their separate count and drill remain visible.

`api.tax_summary_reports` lists 50 requesting-branch summaries per UUID page.
`api.tax_summary_page` returns 50 frozen treatment lines per offset with optional
source-line filter. `api.tax_control_page` returns 50 rows from `controls`,
`control_sources`, `control_journals` or `control_differences`, optionally filtered
by account and immutable evidence key. Journal drill preserves command, source,
line, branch, currencies, transaction sides and signed base amounts. Another
requesting branch cannot open a saved report. Version-one reports remain readable;
their absent control evidence requires a newly generated version-two review.

Limits are 10,000 cumulative sources, 10,000 tax-control GL lines, 10,000 difference
rows, 50 accounts and 16 MiB evidence. Exceeding a limit fails atomically rather than
truncating totals. Direct private-table and helper access is denied. Ended-period
close checks retain previous AR/AP/bank/cash-flow exceptions and add a tax blocker
or explicit check failure, including manual-only mapped tax-control activity.

The `/finance/tax` workspace uses its distinct encrypted `tax-summary-editor`.
It exposes control totals, exact differences, scoped source and GL drill, paging
and review reasons. Offline or revoked access clears posted evidence while
encrypted work is retained. Source/journal validation and sealed retry prevent
accepting a changed scope, amount, filter or command.
Late responses from before a disconnect cannot restore cleared evidence, even
after connectivity returns; a fresh access verification is required. A confirmed
generation atomically replaces the encrypted sealed request with its confirmed
report form. Confirmation after route disposal preserves the report identity for
recovery, without displaying evidence until the next scoped read.

## Compatibility, rollback and acceptance

The rollback builder composes the ordered candidates after the existing journal,
statement, cash-flow and budget candidates. Strict `finish(true)` and `ROLLBACK`
verify synthetic fixtures without installing migrations or retaining business data.
Existing journals without optional tax fields preserve their original behavior.
Existing report versions remain immutable; coordinate the version-two client and
candidate installation rather than rewriting old reports or migrations.

Before installation, review the actual ledger, function signatures/grants, trigger
order and existing client compatibility. Transaction rollback is the candidate
recovery path. After installation, preserve posted source/version/report history
and use a reviewed forward correction; dropping history is not an acceptable undo.
No installation or production rollback is executed by this development session.

Source treatment, cumulative controls, exact FX, independent approval, late-failure
rollback, reversal, scope, encrypted retry and 200% light/dark rendering have
development tests. Unsupported or undeclared tax-control source types remain
unattributed and need review; statutory rules, export, large-data
and multi-session proof remain open. Installed behavior, Windows Credential Manager
process restart, authenticated native acceptance and owner signoff are separate
gates. The stock-opening acceptance boundary remains unchanged.
