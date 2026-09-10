# AC-305–AC-308 delivery and receivables implementation

Status: implemented and deployed to synthetic development, verified 2026-09-10.
Authenticated native acceptance and production release are not claimed. See
[the verification and remaining-work handoff](15_WAVE3_AC305_AC308_VERIFICATION.md).

Scope: FR-326–FR-334 plus the shared posting, exact-value, authorization, and
recovery requirements needed by these four acceptance criteria. AC-304 was
implemented concurrently by the user; its files and applied migration are preserved.

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

Deployment plan (2026-09-10): consolidate the seven un-applied AC-305–AC-308
candidates into one atomic expansion migration. No SQL from the applied AC-304
migration is edited. The credit-exposure integration preserves its API signatures
and fails closed if the expected live function definitions have changed.

1. Preflight: confirm development project health and migration ledger; compare
   live schema with the complete rollback-tested candidate; require the
   compatibility checker to exit zero. Failure means no application.
2. Atomic application: apply the entire expansion with the migration service.
   A SQL error must roll back the transaction. If the transport outcome is unclear,
   inspect the ledger and object definitions before retrying; do not blindly replay.
3. Verification: rerun strict SQL suites against the applied objects in rollback
   transactions, inspect RLS/security advisors, reconcile source with the ledger,
   and confirm synthetic fixtures did not persist. On failure, keep new posting
   workflows out of use and prepare a tested additive correction.
4. Client handoff: use the tested desktop build for synthetic review only. If
   runtime verification fails, return to the prior client release while retaining
   the compatible database expansion and all posted data. Native authenticated
   walkthrough and user acceptance remain separate gates.

The compatibility tool's generated SQL and DROP suggestions are analysis
artifacts, not approved executable migration or rollback scripts.

Advisor follow-up phase: apply a second atomic, additive migration after the
85-assertion candidate passes in rollback. It adds leading-reference FK indexes
only on the twenty new relations and combines the two cash/bank SELECT predicates
with exactly the same OR semantics. The column/API schema is unchanged. Existing
tenant-leading indexes remain intact. If the transaction fails, it rolls back;
after success, retain the indexes and use an additive correction if required.
Do not rewrite the first applied migration or drop indexes based solely on the
empty development database's unused-index counters.

Before application: candidate DDL and all synthetic fixtures run inside one
rollback transaction. Any assertion failure aborts the candidate. Verify that no
candidate objects, fixture rows, or ledger entries persist afterward.

After application: preserve applied SQL, documents, and ledgers. If validation
fails, stop using the affected new posting commands and prepare an additive
correction. Do not drop financial records or restore a permissive implementation.
The existing AC-304 command surface remains available throughout the expansion.

Development application is recorded in the verification handoff with live ledger
versions and source fingerprints. User acceptance and production release remain
separate gates; neither is inferred from continuation messages.
