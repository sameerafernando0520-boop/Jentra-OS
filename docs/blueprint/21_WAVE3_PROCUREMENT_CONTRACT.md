# AC-309 procurement implementation contract

Implements approved FR-335–339 and shared FR-301–312. Development only.
This additive contract precedes code; it does not extend the approved business scope.

Requisition lines preserve stable UUID identity, optional product, description, transaction
unit, exact quantity, positive rational conversion, estimated unit price and source dimensions.
All financial transport values are decimal strings. Quantity and estimated price permit six
decimal places; conversion integers are strings. Reject excess precision rather than silently
rounding user input. Multiply with BigInt intermediates and round only the final estimate to
six places, half away from zero. No aggregation crosses currency boundaries.

RFQ comparison preserves invitation supplier identity, source requisition line identity,
quoted quantity, price, currency, direct base rate, terms and validity. Compare normalized
base values only when every required line is covered exactly once; incomplete responses
remain visible but cannot become a selected purchase order. Selection requires an attributable
reason, including for the cheapest bid. Comparisons do not send invitations externally.

Server commands use the established `p_tenant_id`, `p_legal_entity_id`, `p_branch_id`,
`p_command_id`, `p_idempotency_key`, `p_client_timestamp`, `p_expected_entity_version`,
`p_payload` envelope. New module files must not change stock-opening commands or helpers.
Named requisition/RFQ/PO saves must recalculate exact values, validate scoped references,
compare versions and atomically append receipts/audit/outbox. Submission consumes the active
workflow and sequence; approval consumes its frozen matrix and segregation rules. Material
approved PO edits create immutable revision history and return to governed approval.

Verification starts with exact line calculations, precision rejection, source identity,
duplicate/incomplete bid detection and currency normalization. Database and UI integration
must additionally prove permission denial, workflow configuration failure, self-approval
denial, stale writes, identical retry and changed-body reuse, immutable revisions and atomicity.
Domain calculations are advisory and never authorize a save, approval or posting.

## Requisition lifecycle adapter

`api.transition_purchase_requisition` uses the standard envelope with `document_id`
and exactly one of `action` (`submit`, `recall`, `cancel`) or `decision` (`approved`,
`rejected`). It is a module-owned adapter to the common workflow contract; generic
operational routing can delegate to it when shared routing is coordinated. It does
not replace or alter the stock-opening or receivables transition functions.

Submission freezes the active workflow revision and applicable matrix steps, fails
closed when required approval has no applicable step, reserves a requisition number,
and records the submitting actor. Decisions require both procurement read authority
and the frozen step's current scoped role/MFA authority. Requester, creator, latest
editor and submitter cannot approve their own request. A rejection requires a note.
Recall/cancel require reasons and allowed configured transitions. Rejected requests
must be recalled before editing. Every successful version gets append-only history
in the same transaction as the receipt, audit and outbox. No stock or GL posting
occurs for requisitions.

Cost-centre/project fields are unavailable until those masters exist. Requisition
save now resolves product-specific rational units through the new governed master.
Existing sales/stock consumers still need coordinated integration before FR-350
can be described as complete across the product.

## Sourcing commands and source versions

`upsert_request_for_quote` accepts `operation: issue | record_quote | select`.
Issue snapshots selected lines from one approved, version-checked requisition and
an explicit list of active invited suppliers. Invitations are records only.
Each response has a stable quote UUID, invited supplier, validity date, payment
and delivery terms, currency, rate identity/date and exact line inputs. Response
prices are recalculated by the server using effective input-tax definitions and
the entity rounding policy. Selection requires complete matching quantities,
unexpired response, a reason and the expected RFQ version. It retains the response
version; later corrections cannot silently replace the selected response.

RFQ source snapshots and response revisions are immutable history. The selected
response creates a PO with immutable source IDs. PO edits after approval require
an explicit reason and a new revision; current approval is invalidated. Received
or billed quantities cannot be reduced by a commercial edit. These operations
remain procurement commitments and do not create stock, payables or journals.

## Purchase-order command and revision contract

`api.upsert_purchase_order` saves a draft through the standard command envelope.
The first sourced draft includes `source_rfq_id`, `source_rfq_version`, the selected
`source_quote_id` and its version. The server locks that RFQ, copies its selected
response and source-line IDs, and allows one order per selected response. A retry
returns the original receipt. Header fields include receiving warehouse, order
date, promised date, supplier, payment/delivery terms and governed currency/rate.
Subsequent draft saves carry every stable line ID and recalculate price, discount,
input tax and totals; response snapshots remain available for comparison.

`api.transition_purchase_order` supports submit/recall/cancel/revise and approval
decisions. A submitted order freezes workflow and amount thresholds. Supplier,
creator, latest commercial editor and submitting actor are retained for audit;
the creator/editor/submitter cannot decide their own approval. Approved commercial
fields cannot be overwritten. Explicit reasoned revision returns to draft,
increments the commercial revision and requires another submission. The prior
approved document remains in immutable version history. Draft editing, revision
and cancellation lock the header before line quantities, matching receipt/bill
consumers' lock order. Commercial changes may not reduce ordered quantity below
received/billed quantities or change received products/units. Supplier/currency
changes are denied after any receipt or bill. Cancelled quantity records the
unreceived remainder; it never rewrites accepted receipts.

RFQ issue permits a selected subset of approved requisition lines. A sourced PO
includes all selected response lines. Direct creation from an approved requisition
uses an explicit supplier, currency/rate, terms and line prices; it retains the
same stable requisition source identities and follows the same approval/revision
rules. No AP/stock effects occur in this slice. Direct order creation remains in
development until its commands, UI and verification are complete.

## Product-unit dependency (FR-350)

Before goods receipts, add governed `inventory.product_unit_conversions` and its
immutable version history. An entity/product/transaction-unit pair maps to that
product's base unit through positive numerator/denominator integer strings.
The authenticated `api.upsert_product_unit_conversion` requires catalogue-manage
authority, expected version and the established command envelope. Direct writes
are denied. A changed ratio creates a new version; saved document lines retain
their original ratio, conversion version and base quantity.

`inventory.resolve_product_unit` is private and used by document commands after
their scope checks. It validates active product/unit/conversion references,
transaction and base precision, and exact divisibility at six decimal places.
Base-unit lines require 1/1. Free-text lines also require 1/1. Caller-supplied ratios
must equal the governed pair; a valid numerical ratio alone is insufficient.
Requisition and PO submission revalidate references without silently changing a
saved conversion. Integrating existing applied sales/stock paths is a later shared
compatibility change, separate from this module-owned implementation.

Dependency order adjustment: implement this portion of AC-313 before AC-310 because
receipt stock and lot/serial counts require authoritative base-unit quantities.
