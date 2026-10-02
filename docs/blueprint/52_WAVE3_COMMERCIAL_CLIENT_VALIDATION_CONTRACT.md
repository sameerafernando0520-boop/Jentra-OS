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
