# Inventory valuation and GL reconciliation — FR-360 / FR-375 / FR-382

Candidate public contract, 2026-09-21. Reuses immutable stock movements, transfer
events and posted journal lines. No stock or accounting posting engine is added.

A user chooses an as-of posting date and an explicit set of inventory control GL
accounts (including retired historical accounts when relevant). The report covers
the entire selected legal entity, not only the current branch. Stock, cost and finance
view permission is required in every entity branch at generation, replay and read.
The selected account set and names are frozen in the result; reconciliation is only
against that disclosed set, never an implicit claim that every mapping is correct.

The authenticated `generate_inventory_valuation_report` command uses creation version
zero, request hash/idempotency, audit and outbox. A STABLE helper captures movement,
transfer and journal inputs under one statement snapshot. Its immutable stored report
can be reopened without later backdated postings changing its totals. Generation date,
posting cutoff, scope, base currency, selected account basis and report ID are visible.
Report generation writes evidence only; no quantities, valuation or journals change.

Warehouse/product quantity and carrying value sum immutable movement lines through
the as-of date, including value-only landed adjustments. Average cost exposes the
exact value/quantity ratio and a clearly rounded twelve-decimal display. Lot quantities
derive from original movement identities. Lot value is an allocation of the product's
pooled moving-average carrying value, using cumulative six-decimal rounding; it is not
separate FIFO/lot costing. Zero quantity with residual value is shown as an exception.

Dispatches not yet received/reversed at the cutoff appear as in-transit holdings.
Their frozen carrying value is included in entity inventory so a transfer neither
creates a false entity difference nor disappears from valuation. Source-command
reconciliation compares movement plus transit value with selected-control posted GL
debits minus credits. Every nonzero difference has frozen movement/journal source
evidence, including journal-only and movement-only commands. The report also shows
the aggregate exact difference. It does not repair differences or rewrite history.

Private forced-RLS immutable snapshots are read only through scoped RPCs. Registers
and snapshot sections page 50 rows; source detail can filter a selected command.
Limits: 50 selected accounts, 500 entity branches, 10,000 movement inputs, 10,000 GL
inputs, 2,000 warehouse/product result rows and 16 MiB frozen evidence. Exceeding a
limit fails explicitly, without truncation or partial report creation. Larger reports
need a later bounded asynchronous generation extension.

Native `/inventory/valuation` provides account choices, cutoff, generate/retry, saved
reports, stock/lot/transit sections, differences and source evidence. The encrypted
`inventory-valuation-report` slot retains the exact sealed generation command after
uncertain outcomes. Explicit access denial clears visible report data. No authentication
or MFA automation is permitted. Installed/native acceptance, real contention/load and
owner signoff remain separate gates.
