# Receipt quantity provenance — FR-354 / FR-359 prerequisite

Development contract, 2026-09-19. Candidate only; installation and native acceptance
remain separate. This projection explains receipt quantities; the existing movement,
stock balance, moving weighted-average valuation and journal remain authoritative.

Each new stock movement records immutable quantity attribution. A goods receipt
starts a receipt cohort. Serial issues use the exact serial; lot issues stay within
the exact lot. Within an untracked or lot pool, issues consume the oldest recorded
quantity cohort first. This is an explicit **quantity attribution convention**, not
a change to weighted-average costing or a claim about untracked physical identity.
Sequence order is assigned while holding the existing warehouse/product lock, not
inferred from transaction-start timestamps. No floating-point arithmetic is used.

Transfers carry their issue attribution through in-transit, completion and reversal.
Linked customer returns restore the original issue attribution, including partial
returns, without restoring a unit twice. Positive counts and other unknown inflows
remain unattributed, except a recount restoring the exact previously missing serial
restores its original attribution. Supplier returns prefer the linked original receipt cohort,
then consume other available cohorts if the original cohort was already issued;
their physical attribution is separate from their commercial receipt reference.

Existing stock is an explicitly unknown baseline, captured lazily under the same
stock lock. Historical receipts are not assigned today's aggregate on-hand quantity.
New movements cannot create a negative provenance position or silently repair drift.
All quantity effects, attribution entries and existing command effects roll back
together. Clients cannot write the projection or mutate its history.

The bounded native receipt trace workspace exposes original quantity, current
attributed warehouse holdings, in-transit quantity, net issued quantity and immutable
movement evidence. Its RPCs require operational scope, `inventory.valuation.post`
and `inventory.cost.view`. A receipt with holdings or history in a branch outside
the reader's scope is denied in full; totals never silently omit hidden branches.
Registers and movement history use independent 50-row keyset pages. Current holdings
are limited to 100 warehouses per receipt; larger sets reject explicitly instead of
returning incomplete totals. One movement can consume/restore at most 1,000 cohort
portions; an oversized movement rejects atomically and requires partitioned commands.
Each response
is a current read, not a sealed multi-page concurrent snapshot. Decimal quantities
cross the API as strings. Unknown historical coverage is explicit.

Landed-value posting must subsequently use this provenance under the same locks,
recalculate exact allocation and use `finance.flow_post_journal`. In-transit value
requires a governed extension to frozen transfer carrying value before it can be
adjusted. This contract does not introduce a posting API, claim FR-359 completion,
or permit a client-supplied remaining-stock amount to drive accounting.
