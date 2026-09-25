# AC-320 financial statements and indirect cash flow: candidate slices

Status: synthetic-development candidate, 2026-09-25. This covers the FR-376
trial balance, profit and loss, balance sheet and the FR-378 indirect cash-flow
bridge. It does not complete
FR-375–382 or authorize migration installation or native acceptance.

## Scope and source of truth

`finance.financial_reports` stores one immutable snapshot per successful
`api.generate_financial_statement` command. Only posted journal lines in the
selected legal entity and dated on or before the chosen cutoff contribute.
The requested branch identifies the working context and is permission checked;
the statements themselves consolidate every branch of that legal entity. Both
entity-level and requested-branch `finance.view` are required for generation,
list and detail reads. Direct table access is denied to application roles.
Reports remain visible to an authorized entity-level viewer even if generated
from a different branch. Another entity or tenant can never read them.

The server checks that the cutoff lies within an active fiscal period and is
not in the future. A comparative period, when requested, must be an earlier
active period of the same entity. The comparison is frozen in the same report.
No report mutates journals, accounts, allocations or prior statements. A later
posting, including a backdated one, requires a new report to affect totals.

The snapshot includes posting account identity/code/name/type, opening signed
balance, current period debits and credits, closing balance, statement amount,
and comparative closing/statement amounts. Source drill-through includes the
posted journal and line IDs, document/source IDs, command ID, posting date,
period, branch, party, currency and exact transaction/base debits and credits.
The report stores at most 5,000 posting accounts, 10,000 journal lines and 16 MiB
of evidence; excess fails atomically. Read pages contain at most 50 rows.

## Arithmetic

All financial values travel as decimal strings with at most six fractional
digits. No client floating-point calculation is used. Trial balance reports
period and cumulative debits/credits and requires both to balance exactly.
Profit and loss takes revenue credits less debits and expense debits less
credits in the selected period; comparative profit uses only movements in the
earlier comparative period. Balance sheet maps cumulative assets, liabilities
and equity by debit/credit sign and adds cumulative unclosed revenue less
expense as current earnings. Current and comparative equations must be zero.
The client independently validates the exact summary arithmetic before it
accepts a read page or command receipt.

Indirect cash flow starts with the same posted P&L movement. A permissioned
`finance.cash_flow_mapping_events` decision classifies each balance account as
cash/bank, noncash adjustment, working capital, investing or financing from
its effective date. The decision is immutable, has a per-account version and
reason, and is audited through the shared command engine. Cash classification
requires an existing bank/cash register account. A later or future mapping
never rewrites a saved report or an earlier as-of classification. Each frozen
account row includes the selected mapping ID, effective date and version (and
the comparative decision when requested). Revenue and
expense movement contributes profit without a mapping. Other moving accounts
without a dated mapping appear by code/name in at most 50 warning rows; the
total missing count is exact even if the list is longer. No mapped cash,
unclassified movement, or a nonzero difference blocks the report. The bridge
must satisfy profit + noncash + working capital = operating cash, operating +
investing + financing = net cash, and net cash = closing minus opening mapped
cash. Comparatives are separately classified at their own cutoff and a
blocked comparison blocks the whole saved statement. Period hard-close adds a
live `CASH_FLOW_UNMAPPED` exception whenever a posted period has an incomplete
bridge. A period without posted movement does not require cash-flow mapping.

## Public API and desktop behavior

| API RPC | Behavior |
|---|---|
| `api.generate_financial_statement` | Idempotent command with command ID, key, expected version 0, kind, period, cutoff and optional comparative period; returns a scoped receipt. |
| `api.financial_statement_reports` | Entity-scoped immutable report summaries, UUID cursor, 50 rows. |
| `api.financial_statement_page` | Frozen account or journal evidence, optional account filter, integer offset, 50 rows. |
| `api.period_governance_options` | Existing scoped period picker reused by the desktop. |
| `api.cash_flow_mapping_options` | Entity/branch-checked, bounded account page at an explicit as-of date; supplies the latest account version even when a later mapping is not yet effective. |
| `api.configure_cash_flow_mapping` | Idempotent, version-checked, audited dated decision requiring `finance.cash_flow.configure` at entity and branch scope. |

The `/finance/statements` workspace exposes the four statement kinds,
period/comparison selectors, as-of date, saved reports, exact totals and
account-to-journal drill-through. Local editor state and a prepared command
use the existing encrypted, actor/entity/branch scoped draft store. An
uncertain outcome can retry only the same sealed envelope. Offline mode hides
server evidence until a fresh authenticated read, and permission revocation
clears visible report data. The client does not change authentication.
The separate `/finance/cash-flow-mappings` workspace requires both
`finance.view` and `finance.cash_flow.configure`, supports encrypted draft and
identical-envelope retry, and hides account evidence offline or after access
revocation. The generated report shows the bridge, named blockers and frozen
account-to-journal evidence.

## Boundary for the remaining AC-320 work

This slice does not implement tax returns/summaries,
budget setup and approved versions, budget-to-actual variance, or every
FR-375/377 control and operational report. The journal schema does not yet
carry budget cost-centre/project dimensions. These require additive, separately
verified contracts. Development rollback and widget results are evidence of a
candidate only; installation, real multi-session contention, Credential
Manager restart, native walkthrough and owner signoff remain separate.
