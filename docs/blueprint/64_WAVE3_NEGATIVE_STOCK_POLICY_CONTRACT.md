# Versioned negative stock — FR-353 / EC-323

Approved interim basis, 2026-10-03: issue at the last authoritative positive
moving-average cost, reject an unknown basis, and post linked later-receipt
variance corrections. This is an additive development candidate. Production
installation, authenticated native acceptance, load proof and owner signoff are
separate gates.

## Policy and reachability

The entity policy is OFF when no version exists. A scoped privileged command
appends an immutable version, active or inactive, with an attributable reason.
Existing versions, issue quantities, costs and journals are never edited. The
policy fixes the approved basis and FIFO deficit cover order. Activation does
not itself authorize an issue. Configuration atomically records the version,
before/after audit, typed active/inactive process event, outbox and command
receipt. A same-state version keeps the process event's previous status empty
instead of creating an invalid transition from a status to itself. Identical
replay cannot append a second version or event; a late failure rolls them back.

`api.reserve_sales_order_stock` retains its existing eight-field command envelope.
An optional `negative_stock_override` object contains a decimal-string
`policy_version` and a nonempty `reason`. Without that object, the established
positive-only reservation path remains in force. A shortage override requires
the current active policy version and scoped `inventory.stock.override` in
addition to reservation capability. Delivery rechecks that policy version,
actor capability and original reservation authorization before posting a
deficit. A deficit requires matching immutable reservation authorization for
the same stock balance, order line, reservation command, policy and original
authorizing actor. Reservation records its author from the authenticated server
session in canonical override metadata, overwriting any client-supplied author.
A partial delivery may update the reservation's last editor without changing
that original authorization. Client source metadata cannot substitute for the
matching immutable authorization evidence.
The normal path rejects a client-supplied reserved authorization key.
Reservation and actual deficit issue have distinct immutable audit
events. Exact command replay cannot create a second reservation, deficit or
audit event.

A reservation command can leave its sales-order status unchanged when demand
or availability is already fully allocated. Its receipt, audit and outbox remain
attributable; the process event retains the resulting status with an empty
previous status so it cannot create a prohibited transition to itself. This
applies equally to ordinary positive-only reservations and explicit overrides.

The candidate permits shortages only for products whose actual tracking mode is
`none`. Lot and serial shortages remain rejected; an override cannot invent a
lot, serial or physical identity. This is a documented conditional limit of the
enabled policy, not a claim that arbitrary tracked negative stock is supported.

## Basis and accounting

Policy configuration requires entity-wide policy permission; a branch-only
assignment cannot change the policy of every other entity branch. The
tenant/entity/branch/warehouse/product stream uses the existing deterministic
advisory lock and balance-before-valuation lock order. A basis records the exact
positive quantity and carrying value, the balance and valuation versions and
the source evidence. A current locked positive snapshot can establish a basis
before exhaustion. A zero or negative stream without a previously retained
authoritative positive snapshot rejects with `NEGATIVE_STOCK_COST_BASIS_UNKNOWN`.
No historical receipt or client-supplied cost substitutes for that snapshot.
Ordinary positive receipt/transfer/count movements retain their aligned final
positive snapshot. Before ordinary consumption exhausts a positive stream, its
quantity and valuation are captured while both still describe the same state;
there is no snapshot between the quantity change and its valuation change.

A positive quantity with an authoritative zero carrying value is a known
zero-cost basis and is allowed. The physical positive portion is issued at its normal moving-average value.
The uncovered portion is recorded as an immutable deficit with its provisional
cost and policy/basis identities. Stock and carrying value can be signed; the
legacy physical receipt positions cannot be negative. Protected internal
projection authorization and immutable evidence distinguish a permitted
deficit from an ordinary insufficient-stock operation.

Eligible positive goods receipts cover open deficits in immutable deficit ledger
order. Within a receipt and within each deficit, cumulative rational allocation
rounded to six decimal places assigns every final minor unit exactly. Each
cover links the receipt movement line, original issue and policy version and
records covered quantity, actual receipt value, provisional issue value and
variance. Inventory is adjusted by provisional minus actual value; original
COGS is adjusted by actual minus provisional value. The correction journal uses
the original issue's account identities and the receipt date in an open period.
Retiring a product's current mapping does not redirect that correction. If the
original posting account itself has been made inactive, the established journal
guard rejects the entire correction until a governed account decision restores
its eligibility; there is no fallback to a different active account.
Partial and full receipts, subsequent issues, and exact retries preserve the
original movement and journal rows.

A source-linked saleable customer return cancels still-uncovered units first at
their provisional basis, then restores covered units at their linked actual
receipt cost, and finally restores the original positive portion. Immutable
return allocations prevent double restoration. No-restock returns retain their
established behavior. A receipt already used for a deficit cover cannot be
reversed as an unused receipt; it fails atomically with an explicit governed
correction-required error. Remaining ordinary supplier return, transfer and
stock count guards retain their physical availability requirements.
Unsupported transfer, count, disposition and supplier-return postings into an
open-deficit or oversubscribed stream reject atomically rather than filling a
deficit without cover lineage. A return from another original issue while this
stream has an open deficit requires a governed correction; it does not silently
settle someone else's deficit.

## Evidence and reads

Scoped policy and deficit pages require operational scope; cost-bearing evidence
also requires `inventory.cost.view`. Pages are bounded and use server-assigned
ledger order. Valuation and close-control reports include dated cover corrections
in inventory value and command reconciliation, with explicit provisional deficit
evidence. They do not calculate an ordinary moving average through a zero or
negative denominator. Saved historical reports are immutable.

All policy versions, overrides, deficits, covers, return allocations and basis
snapshots deny direct authenticated writes and history mutation. Existing tenant,
entity, branch, MFA and configured approval boundaries remain applicable. The
reservation, issue, receipt, provenance, correction journal, audit, command
receipt and outbox must succeed or roll back in one transaction.

The uniquely dated pgTAP suite is synthetic, strict `finish(true)` plus rollback
evidence. It does not establish a persistent installation, simultaneous sessions,
native visual acceptance or production accounting approval.

## Client policy commands and evidence

The client reads an absent policy as inactive version zero. Stored and absent
policy responses carry the requested tenant and legal entity;
the client rejects mismatched read or receipt scope. A confirmed configuration
also requires the policy identity to equal the saved command and its author to
equal the original authenticated actor. The configuring branch does not limit
the policy to that branch.
Policy versions and evidence cursors are exact decimal integer strings;
quantity and value fields
use exact six-place decimals. Policy replies include the requested tenant and
legal entity even when the policy is absent. A confirmed configuration identifies
its command as the policy ID and its original actor as the creator; client reply
validation checks these identities and entity scope before accepting success.
The entity-wide policy does not require matching its original configuring branch.
The scoped policy editor requires both stock-view
and policy-management capabilities. Configuration appends a version using the
existing eight-field command envelope and an explicit reason. The server also
requires entity-wide policy-management assignment. The client does not infer
that branch access grants entity-wide authority.

The encrypted policy draft stores the original command before transmission.
Refreshing current policy waits for queued encrypted input writes and preserves
dirty inputs, including a failed save. Recovery retains the input draft's original
expected policy version. A newer policy cannot silently rebase those inputs;
the original version participates in the server's optimistic conflict check.
Unknown replies keep the same command identity, timestamp, version and payload
for explicit retry. Confirmed failures preserve editable inputs; current typed
access denial clears private presentation without deleting the encrypted draft.
Every awaited read, encryption, prepare, reload and transmission step retains
its original access epoch. Scope, capabilities, uncertain connection and widget
disposal invalidate that epoch; reconnect cannot authorize an old continuation.
After transmission, a confirmed receipt that independently matches the original
scoped command completes that original encrypted pending request even if access
was lost while waiting. A failed durable completion retains it for exact replay.
The acknowledged input cannot become a second editable request. Private success
presentation still requires its original access epoch. A historical replay
receipt triggers a fresh current-policy read before another configuration is
available; failed refresh leaves current policy explicitly unavailable.

Deficit and linked correction evidence are bounded to fifty records per page,
with explicit loading of every remaining page and a server ledger cursor.
Cost evidence is unavailable without cost-view capability. Reservations remain
positive-only unless a current active policy, the existing stock-override
capability, and an entered reason explicitly select an override. The normal
reservation payload is unchanged when override is off. The reservation dialog
and caller retain their original authority until the result is consumed; the
server independently validates policy, tracking mode and authoritative basis.
