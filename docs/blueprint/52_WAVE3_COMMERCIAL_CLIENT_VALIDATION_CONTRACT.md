# Wave 3 commercial client validation

This contract clarifies the existing FR-308, FR-319–320 and FR-385 requirements;
it adds no posting rule or statutory requirement. Database recalculation and
authorization remain authoritative.

A quotation or order draft validates header discounts before submission. A
header amount must be nonnegative exact Money in the document currency. A header
percentage must be an exact six-place value between zero and 100 inclusive.
Amount and percentage remain mutually exclusive. Invalid fields return
`header_discount_amount`, `header_discount_percent` or `header_discount` validation
issues. Server-owned price/tax/rate calculations and maximum discount-versus-value
checks remain authoritative and unchanged. No floating-point arithmetic is used.

The draft codec preserves both explicitly entered discount fields so validation
can reject conflicting intent. Immutable server snapshots may contain a calculated
amount alongside the original percentage; only snapshot reconstruction prefers
the percentage to prevent applying the same discount twice. This distinction
also applies to line discounts and to order drafts that reuse the quotation codec.

Local validation failure preserves encrypted inputs, creates no command receipt
or success state, and does not alter a posted document. Tests include negative,
wrong-currency, wrong-scale, over-100 and mutual-exclusive cases, as well as exact
zero and 100 boundaries. A linked correction remains a distinct governed command.

## Existing commercial dialog access and recovery boundary

This section consolidates the clarification published before the corresponding
changes in `docs/verification/remaining-wave3/requirements-dialog-findings-20261003.md`.
It applies the approved FR-386 offline authoritative-command boundary, FR-388
server-resolved capability/scope boundary, FR-395 distinct actionable failure
states and NFR-313 sensitive local-payload boundary. It adds no accounting rule,
domain protocol, installation authority or native acceptance claim.

A governed reference, private credit preview or server action confirmation retains
its originating scope, capabilities and access epoch throughout provider
notifications, async reads, root-route return and the caller continuation that
consumes its result. Restoring identical access after an intervening loss cannot
revive old private rows, previews or accepted results. Loading, failed and unknown
capability/connection observations are unavailable even when an AsyncValue retains
previous data. Live server confirmations require settled, error-free online
connection and matching server-resolved capabilities. Current document/version,
command identity and workflow checks remain independently authoritative.

The originating widget owns the existing access token when a root selector can
outlive that widget without a parent-route pop. State disposal invalidates its
logical epoch synchronously; safely deferred listener notification clears the
surviving private presentation. The token stays alive until the async dialog and
caller cleanup finish, and subscriptions are closed exactly once. Every awaited
result is rechecked before applying it; a route-pop check alone does not establish
authorization for a later caller microtask. This uses existing client lifetime
guards without frame polling or a new domain/posting protocol.

A typed current authentication or permission denial invalidates the selector
after checking its original request generation and access epoch. It removes
private evidence and retry affordances until a fresh authorized selector is
opened. An obsolete denial cannot invalidate a replacement request or token.
Transient network failures retain their distinct retry guidance.

Local encrypted discard, conflict resolution and recovery remain available
offline under their current matching scope/capabilities. Their confirmations
validate the originating scope/capability lifetime and existing slot/document
checks after return without adding an online requirement to local input handling.
These local actions create no authoritative command or posted ledger effect.
