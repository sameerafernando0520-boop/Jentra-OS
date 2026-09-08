# AC-305–AC-308 delivery and receivables implementation

Status: implementation in progress, authorized 2026-09-07 under the approved Wave 3 specification.

Scope: FR-326–FR-334 plus the shared posting, exact-value, authorization, and
recovery requirements needed by these four acceptance criteria. AC-304 is being
implemented concurrently by the user.

## Integration boundary

- Consume existing `sales.sales_orders`, `sales.sales_order_lines`,
  `inventory.stock_balances`, and `inventory.stock_reservations` identities.
- Deliveries consume base quantities and reservations under the same order and
  product locks used by AC-304. They update delivered quantities and order versions.
- Invoices update invoiced quantities. Receivables provide the current credit
  exposure projection consumed by order confirmation.
- Keep quotation/order desktop files and existing published migrations intact.
- New code lives in delivery/receivables files, with narrowly scoped route/export
  integration after checking the latest shared working tree.

## Verification sequence

1. Add failing SQL contracts and behavior tests for AC-305–AC-308.
2. Add backward-compatible schema and private posting helpers. Implement named
   permission-checked commands, immutable source-linked ledgers, and bounded reads.
3. Verify synthetic fixtures in a transaction ending in rollback against development
   project `xpdoufauvrbdmxgngetv`. Inspect compatibility before applying a migration.
4. Implement exact Dart contracts, gateway, durable command recovery, and desktop
   workflows; test capability, offline, retry, scope changes, and conflicts.
5. Verify rendered states, regression, Windows build, SQL/RLS, and ledger integrity.

## Required accounting behavior

- Delivery issues costed stock and balances inventory/COGS in one transaction.
- Invoice uses immutable source quantities and governed pricing/tax snapshots;
  direct stocked invoices are rejected. Partial amounts use cumulative rounding.
- Receipt posts cash/bank and AR, retaining a visible unreconciled state.
- Allocation locks both items, preserves source and target base amounts, and posts
  authorized settlement adjustments and realized FX separately.
- Return and credit consume only eligible original quantities and carrying values.
  Original delivery and invoice remain unchanged.
- As-of statements reconstruct balances from original open items and dated,
  append-only allocations; subsequent receipts and credits do not rewrite history.

## Development migration rollback runbook

Before application: candidate DDL and all synthetic fixtures run inside one
rollback transaction. Any assertion failure aborts the candidate. Verify that no
candidate objects, fixture rows, or ledger entries persist afterward.

After application: preserve applied SQL, documents, and ledgers. If validation
fails, stop using the affected new posting commands and prepare an additive
correction. Do not drop financial records or restore a permissive implementation.
The existing AC-304 command surface remains available throughout the expansion.

Development application and complete acceptance are recorded only after evidence
exists. This document is not a completion or deployment claim.
