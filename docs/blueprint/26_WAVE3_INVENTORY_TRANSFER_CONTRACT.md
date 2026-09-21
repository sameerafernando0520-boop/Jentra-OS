# Warehouse transfers — AC-313–315 / FR-350–357

Development contract, 2026-09-16. Additive candidate; installation and native
acceptance are separate gates. The stock-opening acceptance surface is protected.

`api.transfer_stock` uses the standard authenticated command envelope and
`inventory.transfers.post` in both source and destination branches of one legal
entity. Operations are `dispatch`, `receive`, `reverse`, and `immediate`.
Dispatch/immediate require a new UUID and null expected version. Receive/reverse
require the current transfer version. All operations require an open posting date,
reason and reference. No external transport or payment is executed.

One transfer contains 1–500 immutable lines. Each carries a stable line UUID,
product, transaction unit, exact decimal quantity, governed rational numerator and
denominator, optional lot and explicit serial IDs. Dispatch freezes the resolved
base quantity, conversion version and carrying value. Receive/reverse use those
snapshots rather than repricing. A changed active conversion blocks a new dispatch.

Immediate transfer posts source issue and destination receipt atomically at equal
six-decimal carrying value. Dispatch posts the source issue plus immutable transit
holdings; holdings are not available warehouse stock. Receipt clears all holdings
into the destination. An in-transit reversal restores all holdings to the source.
A completed reversal issues the frozen quantity/value from the destination and
restores it to the source only when available quantity/value and original tracking
remain recoverable. Consumed destination stock requires a separate correction;
history is never deleted. Partial receipt is not supported in this first contract:
split dispatches represent separately received shipments.

Source and destination must differ, be active and belong to the same entity.
Warehouse/product advisory locks use the existing inventory namespace and sorted
keys, followed by balance/valuation and tracking locks. Negative available stock,
future dates, backdating behind later stock movements, duplicate serials and
unavailable tracking fail atomically. In-transit serials cannot be sold or transferred.
Lot saleability and expiry are checked at dispatch; receipt preserves tracking even
if a lot expires in transit, without making the expired lot saleable.

Existing stock balances, valuations, movements, lots and serials remain authoritative.
Transfers within one entity retain the product inventory account and conserve total
value including transit holdings; no expense, AP or new accounting engine is created.
Any future cross-entity transfer requires a separate approved financial contract.

Transfer state/version is operational; lines and operation events are immutable.
Movement, holdings, state, audit, command receipt and outbox commit together.
Read APIs are bounded and scoped; carrying values require `inventory.cost.view`.
Cost must not leak through command receipts or ordinary transfer details.

`api.inventory_transfer_holdings` reproduces outstanding shipments at the end of
a requested UTC posting date. A dispatch contributes only while no receipt or
reversal has posted on or before that date. Later corrections do not erase earlier
holdings. Results page by transfer UUID, retain source/destination names and exact
line quantities, and reveal line carrying values only when the actor has cost-view
permission in both branches. The workspace can view this dated report while keeping
the editor draft intact. This is a dependency for full valuation-to-GL reporting,
not a claim that the remaining reconciliation requirements are complete.

The native workspace must provide named warehouse/product/tracking choices, exact
quantity entry, visible state and source evidence, receive/reverse actions, encrypted
drafts and sealed retry across uncertain results and controller restart. It must
preserve unsaved work on navigation/storage failure and invalidate scope access.

Verification covers value/quantity conservation, reservation and tracking protection,
both-branch authorization/MFA, exact strings, stale versions, changed-key replay,
atomic failure, immutable history and UI recovery. Sequential checks do not establish
real contention, installed behavior, native acceptance or owner signoff.
