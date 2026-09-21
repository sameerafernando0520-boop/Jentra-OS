# Landed value — FR-359 / AC-315

Candidate development contract, 2026-09-20. Uses contract 29 receipt provenance and
the existing stock valuation, stock movement and `finance.flow_post_journal` engines.

The first bounded posting accepts one eligible receipt movement line per adjustment.
The explicit basis is its original accepted base quantity. Enter a positive exact
base-currency amount, posting date, reference, reason, freight expense clearing
account and consumed-stock expense account. This reclassifies a previously recorded
freight expense; it does not create AP, pay a supplier or duplicate a supplier bill.
Multi-receipt charges must first be split explicitly; automatic weight/value allocation
across multiple receipts is not implemented by this contract.

The server preview shows received, held and consumed quantities, per-warehouse
inventory value and consumed-stock variance. Each warehouse share uses cumulative
six-decimal rounding in warehouse-id order over the original quantity. Consumed
variance receives the exact remainder. All displayed quantities/amounts are strings.
Only covered, unreversed receipts with some stock remaining are eligible. Outstanding
transit, supplier returns, receipt reversals and count effects on the cohort reject
with a receipt-specific error, rather than misclassifying those quantities as expense.
Normal deliveries and linked customer returns are supported. Inventory held in other
branches requires valuation and cost permissions there; each branch receives its own
balanced journal. Historical quantities and earlier valuation entries stay immutable.

Preview freezes a server hash of receipt/provenance and current valuation versions.
`api.post_inventory_value_adjustment` uses the standard authenticated command envelope,
`inventory.valuation.post`, `inventory.cost.view`, expected creation version zero,
immutable request hash and idempotency. Posting takes the existing sorted warehouse/
product locks, recalculates and rejects a stale preview. No client-supplied allocation
is authoritative. A value-only movement changes carrying value but no quantity, lot,
serial or reservation. Stock value, journals, posted evidence, receipt, audit and
outbox commit atomically. A closed period, inactive account or late numbering failure
rolls back everything. No workflow/role/period is configured implicitly.

A linked reasoned reversal uses expected version one of the original adjustment and
posts its exact negative legs through the same engine. It requires every affected
valuation version to match the original posting result; intervening receipts, issues,
counts, transfers or value adjustments require accounting review, not a fabricated
reversal. Original evidence is immutable; the reversal is a new document and a unique
link prevents a second reversal. A receipt with an unreversed landed adjustment cannot
use original-cost goods-receipt reversal. Existing transfer reversal must likewise
reject if its frozen cost no longer matches subsequent value adjustments.

Native `/inventory/landed-value` selects named receipt and expense accounts, previews
exact legs, confirms posting, lists immutable evidence and supports reasoned reversal.
Its encrypted scope-isolated `landed-value-editor` preserves the identical sealed
command through uncertain outcomes and restart. Register pages contain 50 rows.
An explicit permission rejection clears visible costs and reference results; a fresh
online scope check is required to redisplay the retained encrypted work.
Current limits: 100 affected warehouses and 500 entity warehouses for sorted locking;
oversized scopes fail explicitly. Installation, real contention/load, native Credential
Manager recovery and owner acceptance remain separate gates. Full FR-359 completion
still requires broader allocation bases, transit value treatment and corrections after
subsequent consumption.
