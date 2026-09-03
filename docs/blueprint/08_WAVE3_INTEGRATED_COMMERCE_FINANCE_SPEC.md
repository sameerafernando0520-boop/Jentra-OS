# Spec: Wave 3 Integrated Commerce and Finance

**Author:** Jentra OS Engineering  
**Date:** 2026-09-03  
**Status:** In Review  
**Reviewer:** Product owner  
**Related specs:** `00_PRODUCT_SPEC.md`, `01_ARCHITECTURE.md`, `02_DOMAIN_AND_PROCESS.md`,
`03_DATA_SECURITY.md`, `04_DESIGN_SYSTEM.md`, `05_TEST_AND_DELIVERY.md`,
`06_WAVE2_SHARED_FOUNDATION_SPEC.md`, `07_WAVE2_VERIFICATION.md`

## Context

Wave 2 established the shared records and platform contracts required by operational work:
parties, products and units, currencies and rates, taxes, chart of accounts, fiscal periods,
document numbering, workflow configuration, approvals, attachments, notifications, imports,
exports, reports, audit, idempotency, encrypted drafts, and capability-aware desktop routing.
Wave 3 turns that foundation into an integrated operating system for commerce, inventory, and
finance.

The release must cover a coherent lead-to-cash, procure-to-pay, inventory-to-ledger, and
record-to-report loop. A commercial posting is not complete unless its stock, receivable or
payable, tax, journal, audit, command-receipt, process-telemetry, and outbox effects either all
commit or all roll back. Posted business truth is immutable; corrections use linked reversals,
returns, credit/debit notes, or adjustment documents.

Wave 3 remains Windows-first and targets the synthetic-data-only development environment.
Existing published migrations remain immutable. Tax treatment is driven by effective-dated Wave
2 configuration and must not be presented as certified Sri Lankan statutory logic. Production
deployment, payment execution, statutory filing, and real customer data remain separately
authorized work.

### Decision baseline

- Inventory is perpetual and uses moving weighted-average cost per legal entity, warehouse, and
  product in the legal entity base currency.
- Commercial documents use one transaction currency, persist their selected exchange rate, and
  record both transaction and base-currency values where financially material.
- Drafts may be composed offline, but submission, approval, allocation, stock reservation,
  posting, settlement, reconciliation, close, reopen, and reversal require live server
  confirmation.
- Wave 2 parties are the customer and supplier source of truth; products, tax definitions,
  accounts, periods, sequences, workflow definitions, attachments, and notifications are reused
  rather than duplicated.
- Bank statements enter through bounded manual CSV/XLSX import. Live bank feeds and outbound
  payments are not part of this wave.

## Functional Requirements

### Shared operational document and command behavior

- FR-301: Every Wave 3 tenant record MUST carry tenant identity, UUID identity, UTC timestamps,
  attributable actor fields, status, and optimistic version where it is mutable.
- FR-302: Client reads MUST use tenant-filtered `security_invoker` API views and client mutations
  MUST use named, authenticated, idempotent `api` RPCs; direct private-table mutation MUST remain
  unavailable to desktop roles.
- FR-303: Draft document headers and lines MUST be mutable only in editable lifecycle states,
  compare expected versions on save, and return a structured conflict containing the current
  server version when stale.
- FR-304: A document MUST reserve its permanent number from the matching Wave 2 sequence when it
  first leaves Draft; retries MUST return the same number and a reserved number MUST never be
  reassigned to another document.
- FR-305: Submission and approval MUST consume the active Wave 2 workflow and approval-matrix
  version selected for the document scope and amount, record each decision, and enforce
  segregation of duties.
- FR-306: Posting MUST require an online authenticated command, an open fiscal period, active and
  correctly scoped master references, complete accounting mappings, and an approved state where
  the active workflow requires approval.
- FR-307: Posted documents and ledger movements MUST NOT be edited or deleted; a correction MUST
  create an attributable, reasoned document linked to the original and reverse or adjust the
  original effects exactly once.
- FR-308: The server MUST recalculate quantities, prices, discounts, taxes, subtotals, totals,
  allocations, and base-currency amounts from canonical line inputs using exact decimals and the
  legal entity rounding policy; client totals are advisory only.
- FR-309: A foreign-currency document MUST persist currency, exchange-rate identifier or approved
  manual rate, rate date, direct rate, transaction amounts, and base amounts without later rate
  changes altering posted history.
- FR-310: Posting MUST validate product, tax, inventory, revenue, expense, COGS, receivable,
  payable, cash/bank, rounding, and exchange-difference mappings required by that document before
  any side effect is committed.
- FR-311: Every successful mutation MUST atomically create or reuse one command receipt, append
  attributable audit context, emit process telemetry for lifecycle changes, and enqueue required
  outbox events with the same correlation identifier.
- FR-312: Wave 3 aggregates MUST reuse Wave 2 private attachments and user notifications with
  aggregate allowlisting and permission checks; an attachment or notification MUST NOT authorize
  access to its underlying aggregate.

### CRM and pipeline

- FR-313: A permitted user MUST create and revise tenant-scoped leads with code, person or
  organization name, optional party/contact, source, owner, stage, expected value/currency,
  expected close date, loss reason, status, and version.
- FR-314: A permitted user MUST record timestamped CRM activities for a lead, opportunity, party,
  or contact with activity type, subject, owner, due/completed time, outcome, and notes.
- FR-315: Lead stage changes MUST follow the active scoped workflow, record entered/completed
  times and reason, and require qualification data before a lead becomes qualified.
- FR-316: A permitted user MUST create and revise opportunities with customer or prospect,
  owner, stage, probability from 0 to 100, exact expected value, currency, expected close date,
  next action, products of interest, and won/lost reason.
- FR-317: Lead conversion MUST be idempotent and MUST create or link one party/contact and one
  opportunity without duplicating an existing party selected by the user.
- FR-318: Pipeline reads MUST expose stage totals, weighted value, aging, conversion, win/loss,
  activity recency, and forecast buckets using persisted exact values and explicit as-of dates.

### Lead-to-cash

- FR-319: A permitted user MUST create and revise quotations with customer, contact, entity,
  branch, currency/rate, validity, payment and delivery terms, salesperson, header discounts,
  notes, and versioned product/service lines.
- FR-320: Quotation lines MUST preserve quantity, unit, conversion, unit price, line discount,
  tax definition, inclusive/exclusive behavior, exact calculated totals, and revision history;
  expired quotations MUST NOT be accepted without a new revision.
- FR-321: Quotation submission, approval, rejection, recall, acceptance, expiry, and cancellation
  MUST follow the configured workflow and preserve all decisions and customer-facing revisions.
- FR-322: An accepted quotation MUST convert idempotently into one sales order with traceable
  source lines; repeated conversion MUST return the existing order.
- FR-323: A permitted user MUST create and revise sales orders with promised dates, ship-to data,
  fulfillment warehouse, exact commercial terms, and ordered/cancelled/allocated/delivered/
  invoiced quantities per source line.
- FR-324: Sales-order confirmation MUST evaluate the customer's active status, due and overdue
  exposure, credit limit, order exposure, and privileged override reason before commitment.
- FR-325: A permitted online command MUST reserve available stock for eligible order lines,
  release or reduce reservations on cancellation and fulfillment, and never make the reservation
  itself an accounting or stock movement.
- FR-326: Posting a delivery MUST validate fulfilled quantities and tracking data, consume the
  related reservation, create immutable inventory issues, update order fulfillment, and create
  balanced inventory/COGS journals in one transaction.
- FR-327: Partial deliveries and invoices MUST be supported without exceeding the remaining
  approved order quantity unless a separately permitted and audited tolerance override applies.
- FR-328: A permitted user MUST draft, submit, approve where configured, and post sales invoices
  from delivered/order lines or, for service and non-stocked products, as authorized direct
  invoices, with customer, due date, currency, tax, discounts, terms, and source traceability.
- FR-329: Sales-invoice posting MUST atomically create the immutable invoice, customer receivable
  open item, tax/revenue journal effects, due balance, audit, receipt, telemetry, and outbox event.
- FR-330: A permitted user MUST record customer receipts against a configured cash or bank
  account with receipt date, currency/rate, external reference, tender metadata, and unapplied
  amount.
- FR-331: Customer-receipt posting MUST create balanced cash/bank and receivable-control journal
  effects and MUST NOT mark funds bank-reconciled before an explicit reconciliation.
- FR-332: Receipt allocation MUST support one-to-many and many-to-one invoice allocation,
  preserve exact residuals, prevent over-allocation, and create explicit discount, write-off, or
  realized exchange-difference lines only with the required permission and reason.
- FR-333: Sales returns and credit notes MUST reference eligible delivered or invoiced quantities,
  prevent excess return/credit, restore saleable stock at the required cost where applicable,
  reverse revenue/tax/COGS/AR effects, and retain the original document unchanged.
- FR-334: Customer statements and aged receivables MUST reconcile to AR open items as of a chosen
  date, expose current and configurable overdue buckets, and support drill-through to source,
  allocation, credit, and receipt records.

### Procure-to-pay

- FR-335: A permitted user MUST create and revise purchase requisitions with requester, entity,
  branch, need-by date, cost centre/project where available, justification, and exact product or
  free-text lines.
- FR-336: Requisition submission and decision MUST use the active workflow and approval matrix;
  the requester MUST NOT approve their own requisition when segregation of duties is enabled.
- FR-337: A permitted user MUST issue an RFQ from approved requisition lines, record invited
  suppliers and comparable supplier quotations, and retain the selection rationale.
- FR-338: A permitted user MUST create and revise purchase orders with supplier, currency/rate,
  terms, receiving warehouse, promised dates, tax, ordered/cancelled/received/billed quantities,
  and source requisition or RFQ links.
- FR-339: A material change to an approved purchase order MUST create a new revision and repeat
  approval when configured thresholds, supplier, currency, quantity, price, tax, or total change.
- FR-340: Posting a goods receipt MUST validate purchase-order eligibility, received quantities,
  warehouse, units, lots/serials, and acceptance/rejection quantities, then create immutable stock
  receipts and accrued-receipt journal effects atomically.
- FR-341: Partial receipts, approved over-receipt tolerances, rejected quantities, and receipt
  reversals MUST update remaining quantities without rewriting the purchase order or prior receipt.
- FR-342: A permitted user MUST draft and post supplier bills against purchase orders and goods
  receipts or as authorized direct bills, with invoice reference uniqueness per supplier, due
  date, tax, currency/rate, and exact line totals.
- FR-343: Three-way matching MUST compare purchase-order, accepted receipt, and supplier-bill
  quantities, unit prices, discounts, taxes, and totals and MUST identify each exception.
- FR-344: Match exceptions beyond configured exact quantity or amount tolerances MUST block posting
  until a permitted approval records the exception, reason, and accountable actor.
- FR-345: Supplier-bill posting MUST atomically create the payable open item and balanced expense/
  inventory/accrual, input-tax, and AP-control journal effects without duplicating receipt value.
- FR-346: A permitted user MUST create payment proposals from due supplier open items, select
  invoices and credits, and submit the proposal through configured payment approval without
  executing an external bank payment.
- FR-347: Posting a supplier payment MUST record the approved payment, allocate exact amounts,
  create balanced AP and cash/bank journal effects, and leave bank reconciliation pending.
- FR-348: Purchase returns and supplier debit notes MUST reference eligible receipts or bills,
  prevent excess quantities/amounts, issue stock where applicable, reverse tax/accrual/AP effects,
  and preserve the source documents.
- FR-349: Supplier statements and aged payables MUST reconcile to AP open items as of a chosen
  date, expose configurable aging buckets, and drill through to bills, credits, allocations, and
  payments.

### Warehouse, stock, and valuation

- FR-350: Transaction quantities MUST use exact base-unit values; non-base transaction units MUST
  use an active product-specific rational conversion whose numerator and denominator are persisted
  on the document line.
- FR-351: Every receipt, issue, transfer, return, or adjustment MUST create immutable stock
  movement headers and lines with source type/id/line, warehouse, product, base quantity, value,
  actor, posting time, and correlation identifier.
- FR-352: On-hand, reserved, and available balances MUST be derived from posted movements and
  active reservations and MUST be reproducible for a requested as-of time.
- FR-353: A posting that would make on-hand or available quantity negative MUST be rejected unless
  the legal entity has an active negative-stock policy and the actor has the override capability;
  every override MUST be separately audited.
- FR-354: Lot-tracked products MUST require tenant/product-scoped lot identity and applicable
  manufacture/expiry metadata on movement; expired lots MUST be blocked from saleable issue unless
  a separately permitted disposition command is used.
- FR-355: Serial-tracked products MUST record one unique serial per base unit, prevent a serial
  from being available in two places, and preserve the complete receipt, transfer, delivery,
  return, and disposition history.
- FR-356: Moving weighted-average cost MUST update atomically for positive receipts and value
  adjustments, price issues at the pre-issue carrying cost, preserve exact intermediate precision,
  and post rounding differences to the configured account.
- FR-357: A warehouse transfer MUST post one atomic source issue and destination receipt at the
  same carrying value, retain in-transit state when locations differ operationally, and complete or
  reverse without creating or losing aggregate value.
- FR-358: A permitted user MUST create stock counts and adjustments; variances MUST require a
  reason and configured approval and MUST post quantity, value, and inventory variance journals
  together.
- FR-359: A permitted value-adjustment command MUST allocate freight or other landed value to
  eligible received stock using an explicit exact basis and post the amount to remaining inventory
  and consumed-stock variance without changing historical quantities.
- FR-360: Inventory valuation and inventory-to-GL reconciliation MUST reproduce quantity, moving
  average, and carrying value by entity, warehouse, product, lot where applicable, and as-of time,
  with every difference linked to its movement or journal source.
- FR-361: Reservations MUST be uniquely linked to demand lines, bounded by remaining demand, and
  released on expiry, cancellation, delivery, reversal, product retirement, or explicit permitted
  release without altering posted stock.

### General ledger, AR/AP, cash, bank, and reporting

- FR-362: Every journal entry MUST carry tenant, legal entity, fiscal period, posting date,
  currency context, source type/id, immutable sequence number, description, status, reversal link,
  and two or more journal lines.
- FR-363: Journal lines MUST reference active posting accounts and carry exact transaction and
  base debit/credit amounts; a posted entry MUST balance base debits and credits exactly and MUST
  never contain a line with both debit and credit.
- FR-364: Delivery, invoice, receipt, goods receipt, bill, payment, return, credit/debit note, stock
  adjustment, landed-value adjustment, bank adjustment, and exchange revaluation commands MUST
  use versioned server-owned posting rules and produce deterministic balanced entries.
- FR-365: A permitted user MUST draft and submit manual journals with lines, dimensions,
  attachments, and reason; posting MUST require configured approval, segregation of duties, an
  open period, and exact balance.
- FR-366: Journal entries MUST retain source-document and source-line drill-through; direct client
  creation of posted journal lines or mutation of any posted journal MUST be denied.
- FR-367: AR and AP open items MUST be created only by posting or reversal, track original, open,
  due, allocated, written-off, and base amounts, and reconcile exactly to their control accounts.
- FR-368: Reversing an allocation MUST require permission and reason, reopen affected items by the
  exact amount, create any required exchange reversal, and retain both allocation records.
- FR-369: A permitted finance administrator MUST configure operational cash and bank accounts that
  reference one legal entity, currency, posting GL account, optional branch, reconciliation rules,
  and active status.
- FR-370: A permitted user MUST import at most 2,000 bank-statement rows from bounded CSV/XLSX,
  preview normalized dates/references/exact amounts, reject duplicate statement identities, and
  apply the valid statement atomically without posting accounting entries.
- FR-371: Bank reconciliation MUST support one-to-one, one-to-many, and many-to-one matches between
  statement lines and posted cash/bank transactions, exact tolerance rules, permitted adjustments,
  lock concurrent matches, and preserve a reversible audit trail.
- FR-372: Settlement and period-end foreign-currency processing MUST calculate realized and
  unrealized exchange differences from persisted rates, create deterministic journals, and reverse
  prior unrealized entries when required without changing source amounts.
- FR-373: Soft-locked periods MUST reject ordinary posting but allow explicitly permitted close
  adjustments; hard-locked periods MUST reject all Wave 3 posting, allocation, reconciliation
  adjustment, and reversal commands.
- FR-374: Closing a fiscal period MUST verify required subledger and bank reconciliations and record
  exceptions; reopening a hard-locked period MUST require `finance.period.reopen`, recent MFA,
  reason, approval, audit, and a new version without deleting the prior close event.
- FR-375: AR-control, AP-control, inventory-control, tax, cash/bank, and goods-received-not-invoiced
  reconciliations MUST compare subledger totals with the GL as of a period and drill through every
  difference.
- FR-376: Trial balance, profit and loss, balance sheet, and indirect cash-flow statements MUST be
  generated from posted journals for a legal entity, explicit period/as-of date, and base currency,
  with comparative periods and account drill-through.
- FR-377: Aged receivables, aged payables, customer statements, supplier statements, tax summaries,
  inventory valuation, and bank reconciliation reports MUST use posted as-of truth and reconcile
  to their governing subledger or ledger totals.
- FR-378: The indirect cash-flow statement MUST start from posted profit, classify non-cash
  adjustments and working-capital changes, present investing and financing cash movements through
  configured account mappings, reconcile closing cash to mapped cash/bank GL balances, and expose
  unmapped items as blocking close warnings.
- FR-379: A permitted user MUST create versioned annual or period budgets by legal entity, account,
  branch, cost centre, project where available, and currency with exact amounts and workflow state.
- FR-380: Budget-versus-actual reporting MUST compare the selected approved budget version with
  posted actuals by period and dimension and expose exact amount and percentage variances.
- FR-381: Tax summaries MUST derive from posted tax lines and effective-dated Wave 2 definitions,
  distinguish input/output/withholding/zero/exempt treatment, and display an explicit
  non-certified/statutory-review-required notice.
- FR-382: Every financial and operational report MUST expose its tenant/entity scope, as-of or
  period basis, base/transaction currency meaning, generation time, filters, and drill-through
  lineage; mutable current-state data MUST NOT be substituted for requested as-of truth.

### Desktop, offline, and operational experience

- FR-383: The desktop shell MUST expose capability-gated CRM, Sales, Purchasing, Inventory, and
  Finance workspaces through routes, primary navigation, and command-palette destinations.
- FR-384: Each workspace MUST provide accessible loading, error, empty, and populated states plus
  a dense list/detail/timeline layout that keeps source, lifecycle, approval, posting, allocation,
  attachment, and audit context visible.
- FR-385: Wave 3 forms MUST provide field and cross-line validation, keyboard traversal, visible
  focus, exact decimal/date entry, server-recalculated previews, unsaved-change confirmation, and
  a clear distinction between Save Draft, Submit, Approve, Post, Reverse, and Cancel.
- FR-386: Offline users MAY read encrypted cached references and edit encrypted drafts, but every
  authoritative lifecycle, reservation, allocation, posting, reconciliation, close, reopen,
  reversal, and import command MUST be disabled until live confirmation.
- FR-387: A server version conflict MUST preserve the encrypted local draft, display current and
  local material fields, and require explicit reload, copy, or merge; no automatic last-write-wins
  behavior is permitted.
- FR-388: Routes, fields, prices/costs, margins, actions, approval controls, posting controls, and
  report/export controls MUST respect server-resolved capability and scope; the database remains
  authoritative and segregation-of-duty failures MUST be explained without leaking hidden data.
- FR-389: Operational lists MUST provide literal search, status and date filters, stable sorting,
  bounded cursor pagination, saved view state, and refresh without using Realtime as transaction
  truth.
- FR-390: Role-appropriate dashboards MUST surface actionable pipeline, quotation, order,
  fulfillment, procurement, stock, AR/AP aging, cash, bank reconciliation, close, budget, and
  exception states using explicit timestamps and scopes.
- FR-391: Users MUST attach and retrieve permitted Wave 2 files from Wave 3 detail screens without
  public URLs, and posted-document attachments MUST remain append-only unless a privileged audited
  rejection marks a file unavailable.
- FR-392: Submission, decision, posting, exception, due, allocation, reconciliation, close, and
  reversal events MUST create in-app notification records for configured recipients without making
  external delivery a posting dependency.
- FR-393: Deep links and command-palette actions MUST restore tenant/entity context and open the
  permitted aggregate or a non-disclosing not-found/forbidden state.
- FR-394: A permitted user MUST export the currently filtered bounded view or generated report to
  UTF-8 CSV/XLSX with stable columns, exact decimal strings, scope/as-of metadata, and an
  attributable Wave 2 export job.
- FR-395: Retryable network, validation, permission, conflict, closed-period, insufficient-stock,
  match, and posting failures MUST have distinct actionable states; a failed command MUST not leave
  a success indicator or partial local/server effect.

## Non-Functional Requirements

- NFR-301: Each posting, reversal, allocation, and reconciliation command MUST be one database
  transaction covering domain state, stock, subledger, journal, audit, receipt, telemetry, and
  outbox effects; injected failure at any step MUST roll back all effects.
- NFR-302: Money, quantity, rates, discounts, tax, costs, and percentages MUST use PostgreSQL
  `numeric` and decimal-string/`BigInt`-backed Dart values; binary floating point MUST NOT cross a
  public contract.
- NFR-303: Every tenant-bearing Wave 3 table MUST enable and force RLS, and database tests MUST
  prove tenant, legal-entity, branch, warehouse, ownership, and capability boundaries for reads and
  commands.
- NFR-304: Every privileged function MUST use an empty search path, fully qualified objects,
  explicit authentication/capability/scope checks, and no execution grant to `PUBLIC` or `anon`.
- NFR-305: Approval, price override, cost visibility, stock override, posting, payment, bank
  adjustment, period close/reopen, and reversal MUST support distinct capabilities; configured
  high-risk actions MUST require recent MFA and segregation-of-duty checks.
- NFR-306: One hundred percent of successful Wave 3 mutations MUST be attributable by tenant,
  actor, request, command, aggregate, source, before/after context, correlation ID, and UTC time;
  audit and posted ledger history MUST be append-only.
- NFR-307: Ordinary indexed list/detail reads MUST meet p95 under 500 ms at target scale, excluding
  generated reports, file transfer, and external providers.
- NFR-308: Draft/save/transition commands MUST meet p95 under 1.5 seconds and single-document
  posting commands p95 under 3 seconds at target scale, excluding user approval wait and external
  delivery.
- NFR-309: Verification data MUST exercise at least 500 tenants, 10 legal entities per tenant,
  25 warehouses per entity, 100,000 products per large tenant, 10 million stock movements, and 20
  million journal lines without cross-tenant scans.
- NFR-310: Tenant-leading indexes MUST cover foreign keys, lifecycle queues, source links, cursor
  lists, open-item aging, stock as-of, bank matching, and journal/report filters; representative
  plans MUST avoid unbounded sequential scans on high-volume tables.
- NFR-311: Interactive list limits MUST be 1–200, detail child pages 1–500, bank imports at most
  2,000 rows and 10 MiB, and synchronous report results at most 10,000 rows; larger work MUST be a
  separately specified background job.
- NFR-312: Concurrent number reservation, order allocation, stock issue, receipt, matching,
  allocation, posting, close, and reversal MUST use deterministic lock ordering or equivalent
  constraints and return a stable retryable conflict instead of overselling or double posting.
- NFR-313: Local drafts and cached sensitive payloads MUST remain inside the Wave 1 AES-256-GCM and
  Windows Credential Manager boundary and MUST exclude posted ledger truth, full bank statements,
  and unmasked cost data not permitted to the current user.
- NFR-314: Wave 3 desktop flows MUST meet WCAG 2.2 AA, full keyboard operation, visible focus,
  semantic status/error text, screen-reader labels, reduced motion, and 200% text scaling.
- NFR-315: Wave 3 screens MUST render without overflow at 1024×720, 1440×900, 1920×1080, and 4K in
  light/dark and compact/comfortable modes; tables MUST retain reachable horizontal scrolling and
  frozen identity columns where necessary.
- NFR-316: Logs and telemetry MUST carry correlation and scoped identifiers while excluding
  secrets, bank credentials, raw attachment contents, and unnecessary PII; posting latency,
  conflicts, stock denials, reconciliation gaps, close blockers, and dead-letter depth MUST be
  observable.
- NFR-317: Pure domain, calculation, allocation, matching, lifecycle, valuation, and posting-rule
  code MUST maintain at least 90% branch coverage; changed overall code MUST preserve the project
  80% target and critical invariants MUST have property tests.
- NFR-318: Database tests MUST prove RLS/grants, exact calculations, idempotency, optimistic
  conflicts, atomic rollback, concurrency, stock/serial uniqueness, weighted-average valuation,
  balanced journals, subledger reconciliation, closed-period rejection, reversal, and audit
  immutability.
- NFR-319: The Windows release build MUST complete and cold-launch without an immediate crash;
  critical lead-to-cash, procure-to-pay, inventory, reconciliation, and close paths MUST receive
  rendered visual and keyboard QA in addition to automated tests.
- NFR-320: Trial balance, aged balances, inventory valuation, and subledger reconciliation MUST
  meet p95 under 2 seconds for one ordinary entity/period at target scale; bounded complex reports
  MAY take up to 10 seconds and MUST expose progress and cancellation.

## Acceptance Criteria

### AC-301: Scoped and atomic operational commands (FR-301–FR-312, NFR-301–NFR-306)
**Covers:** FR-301, FR-302, FR-303, FR-304, FR-305, FR-306, FR-307, FR-308,
FR-309, FR-310, FR-311, FR-312.

Given two tenants, scoped users, active Wave 2 setup, and an injectable posting failure
When users read, save, submit, replay, post, and attempt cross-tenant or direct-table actions
Then only permitted scoped records are visible and only named RPCs mutate business data
And a replay returns the original result without duplicate effects
And an injected failure leaves no document, stock, journal, audit, receipt, telemetry, or outbox
partial effect.

### AC-302: CRM pipeline and lead conversion (FR-313–FR-318)
**Covers:** FR-313, FR-314, FR-315, FR-316, FR-317, FR-318.

Given a new prospect lead with activities and an active qualification workflow
When a permitted user qualifies and converts the lead twice
Then one linked party/contact and one opportunity exist with complete stage telemetry
And the second conversion returns the same aggregates
And pipeline totals preserve exact expected and probability-weighted values for the selected as-of
date.

### AC-303: Versioned quotation (FR-319–FR-321, NFR-302)
**Covers:** FR-319, FR-320, FR-321.

Given an active customer, products, taxes, prices, currency rate, and approval workflow
When a user drafts, revises, submits, and accepts a quotation
Then the server-calculated exact inclusive/exclusive taxes and totals match the rounding policy
And each customer-facing revision and approval decision remains readable
And an expired unrevised quotation cannot be accepted.

### AC-304: Quote-to-order and credit control (FR-322–FR-325)
**Covers:** FR-322, FR-323, FR-324, FR-325.

Given an accepted quotation and customer exposure near the credit limit
When conversion is replayed and the order is confirmed and reserved
Then exactly one traced sales order exists
And confirmation is blocked or records a permitted override according to exposure
And stock reservations are bounded by available stock and remaining demand without creating a
journal or stock movement.

### AC-305: Delivery and partial fulfillment (FR-326–FR-327)
**Covers:** FR-326, FR-327.

Given an approved order with reserved stocked, lot-tracked, and service lines
When a permitted user posts a partial delivery
Then eligible stock is issued at carrying cost, reservations and remaining quantities update, and
inventory/COGS journals balance in the same transaction
And an excess or invalid-lot delivery is rejected without partial effects.

### AC-306: Sales invoice posting (FR-328–FR-329)
**Covers:** FR-328, FR-329.

Given delivered lines and an open fiscal period
When a permitted user posts the sales invoice and replays the command
Then one immutable invoice, one AR open item, one balanced revenue/tax journal, one audit event, and
one command receipt result exist
And the customer balance equals the invoice residual exactly.

### AC-307: Customer receipt and allocations (FR-330–FR-332)
**Covers:** FR-330, FR-331, FR-332.

Given two open invoices in a foreign currency and one customer receipt
When the receipt is posted and allocated one-to-many
Then cash/bank and AR journal effects balance, invoice residuals are exact, and the receipt remains
unreconciled with its unapplied amount visible
And over-allocation or an unauthorized write-off is rejected.

### AC-308: Sales return, credit, and customer aging (FR-333–FR-334)
**Covers:** FR-333, FR-334.

Given a delivered and invoiced sale included in a prior aging report
When an eligible partial return and credit note are posted
Then stock and financial effects reverse only the eligible amount with links to the source
And a new as-of aging report reconciles to AR while the earlier as-of report remains unchanged.

### AC-309: Requisition, RFQ, and purchase order (FR-335–FR-339)
**Covers:** FR-335, FR-336, FR-337, FR-338, FR-339.

Given an approved requisition and supplier responses
When a user selects a supplier, creates a purchase order, and materially changes its price
Then source links and selection rationale remain visible
And the changed revision returns to approval according to the configured threshold
And the requester cannot self-approve when segregation of duties applies.

### AC-310: Goods receipt (FR-340–FR-341)
**Covers:** FR-340, FR-341.

Given an approved purchase order with tracked stock
When a user posts accepted, rejected, and partial receipt quantities
Then only accepted quantities enter stock with required lot/serial identity and accrued-receipt
journals
And excess or duplicate receipt posting is rejected or requires the configured audited tolerance.

### AC-311: Supplier bill and three-way match (FR-342–FR-345)
**Covers:** FR-342, FR-343, FR-344, FR-345.

Given purchase-order, goods-receipt, and supplier-bill values inside and outside tolerance
When the bills are matched and posted
Then the within-tolerance bill creates one AP item and balanced accounting without duplicating
receipt value
And the outside-tolerance bill is blocked until a permitted exception decision is recorded.

### AC-312: Supplier payment, return, and aging (FR-346–FR-349)
**Covers:** FR-346, FR-347, FR-348, FR-349.

Given approved payable items, a payment proposal, and an eligible received item
When payment and a partial purchase return/debit note are posted
Then AP, cash/bank, tax, accrual, and stock effects remain exact and source-linked
And supplier aging reconciles to AP with the payment still pending bank reconciliation.

### AC-313: Exact units and stock balances (FR-350–FR-353, NFR-302, NFR-312)
**Covers:** FR-350, FR-351, FR-352, FR-353.

Given a product with a rational transaction-unit conversion and two concurrent issue commands
When both commands compete for the final available quantity
Then base quantity conversion is exact and at most one issue succeeds when negative stock is off
And on-hand, reserved, and available balances reproduce from posted movements and reservations.

### AC-314: Lot and serial traceability (FR-354–FR-355)
**Covers:** FR-354, FR-355.

Given lot-tracked and serial-tracked products across two warehouses
When they are received, transferred, delivered, returned, and dispositioned
Then every unit has one unbroken tenant/product/location history
And duplicate serial availability, missing tracking data, and expired saleable issues are rejected.

### AC-315: Weighted average, transfers, counts, and valuation (FR-356–FR-361)
**Covers:** FR-356, FR-357, FR-358, FR-359, FR-360, FR-361.

Given receipts at different costs, an issue, transfer, count variance, landed-value adjustment, and
active demand reservations
When all permitted commands post
Then moving average and carrying value follow the specified order with exact rounding
And transfers conserve aggregate value, adjustments balance to the GL, and as-of valuation
reconciles to movement history without altering quantities for a value-only adjustment.

### AC-316: Balanced and immutable journals (FR-362–FR-366)
**Covers:** FR-362, FR-363, FR-364, FR-365, FR-366.

Given mapped source documents and a submitted manual journal
When automatic and manual postings run
Then every entry has at least two valid posting-account lines and exact equal base debits/credits
And source drill-through is complete
And direct, unbalanced, self-approved, duplicate, closed-period, and posted-line mutations are
rejected.

### AC-317: Open items and operational accounts (FR-367–FR-369)
**Covers:** FR-367, FR-368, FR-369.

Given posted AR/AP items, allocations, and configured cash/bank accounts
When an authorized allocation is reversed
Then the exact residuals and any exchange effect reopen through linked immutable records
And AR/AP control accounts still reconcile
And cross-entity or inactive operational account mappings are rejected.

### AC-318: Bank import and reconciliation (FR-370–FR-371, NFR-311–NFR-312)
**Covers:** FR-370, FR-371.

Given a bounded statement file and posted bank transactions
When a user previews, imports, and reconciles one-to-many while another user attempts the same match
Then one statement is stored without accounting effects and one match wins under lock
And duplicates, malformed exact amounts, out-of-tolerance matches, and unauthorized adjustments are
rejected without partial reconciliation.

### AC-319: Foreign currency and period control (FR-372–FR-374)
**Covers:** FR-372, FR-373, FR-374.

Given foreign open items and an open period moving through soft and hard lock
When settlement, revaluation, close, ordinary posting, and an approved MFA-backed reopen are
attempted
Then realized/unrealized entries are deterministic and reversible
And lock rules reject prohibited commands
And reopen preserves the prior close event, reason, approval, actor, and version.

### AC-320: Reconciliation, statements, budgets, and lineage (FR-375–FR-382, NFR-320)
**Covers:** FR-375, FR-376, FR-377, FR-378, FR-379, FR-380, FR-381, FR-382.

Given posted subledgers, mapped cash flows, tax lines, an approved budget, and comparative periods
When reconciliation and financial/operational reports run
Then trial balance, statements, aging, inventory, tax, bank, budget variance, and control-account
totals agree exactly for their declared scope and as-of basis
And every total drills to immutable source lines within the performance bounds
And unmapped cash-flow items and the tax-review notice are visible.

### AC-321: Desktop workspaces and forms (FR-383–FR-385, NFR-314–NFR-315)
**Covers:** FR-383, FR-384, FR-385.

Given each Wave 3 workspace is loading, failed, empty, or populated
When it renders at every target viewport, theme, density, keyboard path, and 200% text scale
Then the correct semantic state appears without unreachable controls or data loss
And users can distinguish every draft, lifecycle, approval, posting, and corrective action.

### AC-322: Offline, conflict, and capability safety (FR-386–FR-388, NFR-313)
**Covers:** FR-386, FR-387, FR-388.

Given offline, stale-version, view-only, cost-hidden, approver, and poster user states
When users edit drafts and invoke commands directly or through the UI
Then encrypted drafts survive restart and conflict resolution is explicit
And no authoritative command runs offline
And UI visibility and database authorization enforce scope, cost, action, MFA, and segregation rules.

### AC-323: Lists, dashboards, exports, and recovery (FR-389–FR-390, FR-394–FR-395)
**Covers:** FR-389, FR-390, FR-394, FR-395.

Given representative operational volume, filters, retryable failures, and exact financial values
When users search, page, refresh, view dashboards, export, and retry
Then ordering and cursors remain stable, timestamps/scopes are explicit, and exports preserve exact
strings and selected as-of metadata
And failed attempts show no success state or partial server effect.

### AC-324: Files, notifications, and deep links (FR-391–FR-393)
**Covers:** FR-391, FR-392, FR-393.

Given permitted and forbidden users, posted documents, event recipients, and aggregate deep links
When files are added/read, events occur, and links open under different tenant contexts
Then private file rules and append-only posted context hold, configured notifications are created,
and links restore permitted context or return a non-disclosing denied/not-found state.

### AC-325: Scale, security, and observability (NFR-307–NFR-312, NFR-316)
Given representative target-scale data and concurrent critical commands
When read, save, post, report, allocation, stock, and reconciliation benchmarks and plans run
Then documented p95 and bounded-work targets are met without cross-tenant or unbounded high-volume
scans
And contention returns stable conflicts without duplicate effects
And diagnostics contain correlation data but no prohibited secrets or raw sensitive content.

### AC-326: Complete Wave 3 release gate (FR-301–FR-395, NFR-301–NFR-320)
Given the complete Wave 3 implementation and an isolated database environment
When format, analysis, coverage, unit, property, widget, golden, platform, pgTAP, concurrency,
end-to-end, advisor, Windows release build, cold-launch, keyboard, and rendered visual checks run
Then all executable checks pass with no unresolved security findings
And performance evidence meets the documented targets
And backend contract, migration-ledger, runtime, and residual external gaps are recorded without
deploying to staging or production.

## Edge Cases and Error Scenarios

- EC-301: Reused idempotency key with a different command or payload -> return
  `IDEMPOTENCY_MISMATCH`; create no new effect.
- EC-302: Expected document version is stale -> return `VERSION_CONFLICT` with current material
  fields; preserve the local draft.
- EC-303: Connectivity drops after request send -> a retry returns the original committed result or
  a safe retryable error, never a duplicate post.
- EC-304: A sequence, workflow, approval matrix, tax, exchange rate, account, product, party,
  warehouse, or period changes after draft creation -> submission/posting revalidates and returns a
  field/source-specific error.
- EC-305: Workflow has no matching amount step or has ambiguous active versions -> block submission
  with `WORKFLOW_CONFIGURATION_ERROR`.
- EC-306: Submitter, approver, poster, payment releaser, or period reopener violates configured
  segregation -> return `SEGREGATION_OF_DUTIES_VIOLATION`.
- EC-307: Server totals differ from client preview after rate/tax/rounding revalidation -> return
  recalculated values and require explicit confirmation before posting.
- EC-308: Manual exchange rate is non-positive, wrong-direction, too imprecise, or actor lacks
  permission -> reject without changing the draft's prior approved rate.
- EC-309: Quote expires during acceptance or conversion -> lock/recheck prevents conversion and
  requires a new revision.
- EC-310: Credit exposure changes concurrently with order confirmation -> locked recalculation
  applies the latest posted/open exposure before approval or rejection.
- EC-311: Two orders reserve the last stock concurrently -> at most one reservation succeeds;
  neither available balance nor demand may become negative.
- EC-312: Delivery references inactive warehouse, insufficient reservation, missing lot/serial,
  expired lot, or excess quantity -> reject the entire delivery.
- EC-313: Direct invoice contains a stocked product that has not been delivered -> reject; direct
  invoices in this wave are limited to eligible service and non-stocked products.
- EC-314: Receipt or payment currency differs from allocated open item -> require a persisted rate
  and explicit exchange-difference treatment.
- EC-315: Allocation amount exceeds either item residual or is applied to another party/entity ->
  reject without changing any allocation.
- EC-316: Return or credit/debit note exceeds original eligible quantity/value or is repeated ->
  return `SOURCE_QUANTITY_EXCEEDED` or the original idempotent result.
- EC-317: Supplier invoice reference duplicates an active/posted bill for that supplier/entity ->
  reject unless it is an explicitly linked correction.
- EC-318: Three-way match has missing receipt, price variance, quantity variance, tax mismatch, or
  currency mismatch -> record bounded exceptions and block outside-tolerance posting.
- EC-319: Payment proposal contains already settled, soft-locked, foreign-entity, or concurrently
  selected items -> remove/reject invalid lines and require a new approval version.
- EC-320: Product-unit conversion is zero, negative, cyclic, inactive, or changes after document
  approval -> reject or require a new document revision.
- EC-321: Stock receipt quantity is positive but value is negative, or issue quantity is negative
  under an issue type -> reject sign-inconsistent movement.
- EC-322: Moving-average denominator would become zero -> preserve zero quantity and zero carrying
  value, posting any approved residual rounding/variance explicitly.
- EC-323: Negative stock override produces a later receipt -> value the interim issue and subsequent
  correction according to the versioned negative-stock policy and expose the variance.
- EC-324: Serial is duplicated, already issued, in transit, disposed, or belongs to another product
  or tenant -> reject the entire movement without revealing foreign serial details.
- EC-325: Transfer source posts but destination step fails -> roll back both sides; an in-transit
  transfer exists only when the explicit atomic dispatch command succeeds.
- EC-326: Count occurs while later movements exist -> require a count cutoff/as-of time and apply
  variance against that snapshot under lock.
- EC-327: Landed-value allocation basis sums to zero or references consumed/foreign receipt lines ->
  reject with line-specific errors.
- EC-328: Journal has one line, both debit and credit on a line, no account, non-posting/inactive
  account, unequal base totals, or unapproved rounding difference -> reject atomically.
- EC-329: Source posting mapping resolves to a foreign entity, inactive account, or account with the
  wrong control purpose -> return `ACCOUNT_MAPPING_INVALID`.
- EC-330: A hard lock races with posting -> deterministic locks allow either the posting before
  close or close before rejection, never a post inside a closed snapshot.
- EC-331: Reversal is attempted twice or after an incompatible later correction -> return the first
  reversal or `REVERSAL_NOT_ALLOWED` without a second effect.
- EC-332: Bank file is malformed, formula-bearing, encrypted, macro-enabled, duplicate, over 2,000
  rows/10 MiB, or contains ambiguous locale dates/amounts -> reject preview/apply safely.
- EC-333: Bank statement contains duplicate external identities or identical repeated lines ->
  require an explicit duplicate-resolution decision before apply.
- EC-334: Two users match the same statement or ledger line -> one match succeeds and the other
  receives `MATCH_CONFLICT` with refreshed candidates.
- EC-335: Reconciliation tolerance would create an adjustment without permission/mapping -> keep
  unmatched and require a permitted adjustment command.
- EC-336: Period close has unreconciled controls, unmapped cash flows, draft postings, or unposted
  approved documents -> report blockers and do not hard lock.
- EC-337: Reopen lacks recent MFA, approval, reason, or capability -> deny without changing period
  state or prior close evidence.
- EC-338: As-of report is requested before entity inception, after an unsupported future date, or
  across entities/currencies without consolidation -> reject or return an explicit empty scoped
  result, never silently combine books.
- EC-339: Report exceeds synchronous bounds -> return `LIMIT_EXCEEDED` with narrowed-filter guidance;
  do not silently truncate financial totals.
- EC-340: Local encrypted storage is unavailable or full -> retain in-memory draft edits, block
  offline persistence, and show `LOCAL_STORAGE_FULL` without attempting an authoritative command.

## API Contracts

All commands are invoked in the exposed `api` schema and retain the Wave 1 `CommandEnvelope<T>`,
`CommandResult<T>`, `DomainError`, `TenantContext`, and `CursorPage<T>` semantics. Field names below
show the serialized boundary; decimal values are strings and identifiers are UUID strings.

Transport uses `POST /rest/v1/rpc/{function_name}` for commands and bounded
`GET /rest/v1/{api_view}` requests for read models.

```typescript
type DecimalString = string; // canonical signed decimal, never IEEE-754 JSON number
type DateString = string; // YYYY-MM-DD
type TimestampString = string; // UTC RFC 3339

interface OperationalCommand<T> {
  command_id: string;
  idempotency_key: string;
  tenant_id: string;
  legal_entity_id: string;
  branch_id?: string;
  expected_entity_version?: number;
  client_timestamp: TimestampString;
  payload: T;
}

interface MoneyValue {
  amount: DecimalString;
  currency_code: string;
  base_amount?: DecimalString;
  exchange_rate_id?: string;
  exchange_rate?: DecimalString;
  rate_date?: DateString;
}

interface QuantityValue {
  quantity: DecimalString;
  unit_id: string;
  base_quantity: DecimalString;
  conversion_numerator: string; // positive integer string
  conversion_denominator: string; // positive integer string
}

interface CommercialLineInput {
  line_id: string;
  product_id?: string;
  description: string;
  quantity: QuantityValue;
  unit_price: DecimalString;
  discount_amount?: DecimalString;
  discount_percent?: DecimalString;
  tax_definition_id?: string;
  warehouse_id?: string;
  source_line_id?: string;
  dimensions?: { branch_id?: string; cost_centre_id?: string; project_id?: string };
}

interface DocumentResult {
  id: string;
  document_type: string;
  document_number?: string;
  status: string;
  version: number;
  transaction_currency: string;
  subtotal: DecimalString;
  discount_total: DecimalString;
  tax_total: DecimalString;
  grand_total: DecimalString;
  base_total: DecimalString;
  warnings: string[];
}

interface PostingResult {
  request_id: string;
  document: DocumentResult;
  stock_movement_ids: string[];
  journal_entry_ids: string[];
  open_item_ids: string[];
  allocation_ids: string[];
  warnings: string[];
}

interface TrackingInput {
  product_id: string;
  lot_id?: string;
  serial_ids?: string[];
  base_quantity: DecimalString;
  manufacture_date?: DateString;
  expiry_date?: DateString;
}

interface AllocationInput {
  source_open_item_id: string;
  target_open_item_id: string;
  transaction_amount: DecimalString;
  base_amount: DecimalString;
  exchange_difference?: DecimalString;
  write_off?: DecimalString;
  reason?: string;
}

interface JournalLineInput {
  line_id: string;
  account_id: string;
  transaction_currency: string;
  transaction_debit: DecimalString;
  transaction_credit: DecimalString;
  base_debit: DecimalString;
  base_credit: DecimalString;
  description?: string;
  party_id?: string;
  branch_id?: string;
  cost_centre_id?: string;
  project_id?: string;
}

interface BankStatementImportRequest {
  bank_account_id: string;
  statement_external_id: string;
  opening_balance: DecimalString;
  closing_balance: DecimalString;
  currency_code: string;
  rows: Array<{
    external_line_id?: string;
    booked_date: DateString;
    value_date?: DateString;
    reference?: string;
    description: string;
    amount: DecimalString;
  }>;
}

interface ReconciliationMatchInput {
  bank_account_id: string;
  statement_line_ids: string[];
  ledger_transaction_ids: string[];
  statement_total: DecimalString;
  ledger_total: DecimalString;
  adjustment?: { amount: DecimalString; account_id: string; reason: string };
}

interface BudgetLineInput {
  period_id: string;
  account_id: string;
  amount: DecimalString;
  currency_code: string;
  branch_id?: string;
  cost_centre_id?: string;
  project_id?: string;
}
```

### Named RPC commands

| Function | Required permission | Purpose |
|---|---|---|
| `api.upsert_lead` | `crm.leads.manage` | Save a versioned lead draft |
| `api.record_crm_activity` | `crm.activities.manage` | Record lead/opportunity/party activity |
| `api.upsert_opportunity` | `crm.opportunities.manage` | Save pipeline opportunity |
| `api.convert_lead` | `crm.leads.convert` | Idempotently link party/contact/opportunity |
| `api.upsert_sales_quotation` | `sales.quotations.manage` | Save quotation header and lines |
| `api.convert_quotation_to_order` | `sales.orders.manage` | Create one traced sales order |
| `api.upsert_sales_order` | `sales.orders.manage` | Save order and revisions |
| `api.reserve_sales_order_stock` | `inventory.reservations.manage` | Reserve bounded available stock |
| `api.post_delivery` | `sales.deliveries.post` | Atomically fulfill, issue stock, and post COGS |
| `api.upsert_sales_invoice` | `sales.invoices.manage` | Save invoice draft and lines |
| `api.post_sales_invoice` | `sales.invoices.post` | Create invoice, AR, tax/revenue journal |
| `api.post_customer_receipt` | `finance.receipts.post` | Post cash/bank and AR receipt |
| `api.allocate_customer_receipt` | `finance.receipts.allocate` | Allocate receipt to AR items |
| `api.post_sales_return` | `sales.returns.post` | Post return and linked credit effects |
| `api.upsert_purchase_requisition` | `procurement.requisitions.manage` | Save requisition and lines |
| `api.upsert_request_for_quote` | `procurement.rfq.manage` | Save RFQ, invitations, and responses |
| `api.upsert_purchase_order` | `procurement.orders.manage` | Save PO and revisions |
| `api.post_goods_receipt` | `procurement.receipts.post` | Receive stock and post accrual effects |
| `api.upsert_supplier_bill` | `procurement.bills.manage` | Save supplier bill and match inputs |
| `api.post_supplier_bill` | `procurement.bills.post` | Validate match and create AP/journal effects |
| `api.upsert_payment_proposal` | `finance.payments.manage` | Select AP items for approval |
| `api.post_supplier_payment` | `finance.payments.post` | Allocate AP and post cash/bank effects |
| `api.post_purchase_return` | `procurement.returns.post` | Post stock return and debit effects |
| `api.transition_operational_document` | document transition capability | Submit, recall, cancel, or accept |
| `api.decide_operational_approval` | document approval capability | Record configured approval decision |
| `api.transfer_stock` | `inventory.transfers.post` | Dispatch/receive or reverse traced transfer |
| `api.post_stock_adjustment` | `inventory.adjustments.post` | Post approved count/adjustment |
| `api.post_inventory_value_adjustment` | `inventory.valuation.post` | Allocate landed/value changes |
| `api.post_manual_journal` | `finance.journals.post` | Post approved balanced manual journal |
| `api.reverse_posted_document` | aggregate reversal capability | Create one linked corrective posting |
| `api.upsert_cash_bank_account` | `finance.bank.manage` | Configure operational cash/bank account |
| `api.import_bank_statement` | `finance.bank.import` | Apply bounded statement without posting GL |
| `api.reconcile_bank_transactions` | `finance.bank.reconcile` | Match statement and ledger transactions |
| `api.reverse_bank_reconciliation` | `finance.bank.reconcile` | Reverse a prior match with reason |
| `api.close_fiscal_period` | `finance.period.close` | Verify controls and soft/hard lock period |
| `api.reopen_fiscal_period` | `finance.period.reopen` + recent MFA | Reopen with approval and reason |
| `api.post_exchange_revaluation` | `finance.fx.post` | Post/reverse period-end FX effects |
| `api.upsert_budget` | `finance.budgets.manage` | Save versioned budget and lines |

Common errors extend the Wave 1–2 contract with `WORKFLOW_CONFIGURATION_ERROR`,
`SEGREGATION_OF_DUTIES_VIOLATION`, `PERIOD_CLOSED`, `ACCOUNT_MAPPING_INVALID`,
`INSUFFICIENT_STOCK`, `SOURCE_QUANTITY_EXCEEDED`, `SERIAL_CONFLICT`, `MATCH_EXCEPTION`,
`MATCH_CONFLICT`, `UNBALANCED_JOURNAL`, `REVERSAL_NOT_ALLOWED`, and
`STATUTORY_REVIEW_REQUIRED`.

## Data Models

All mutable headers also carry `id UUID`, `tenant_id`, applicable legal entity/branch scope,
`version BIGINT > 0`, status/lifecycle fields, actor fields, and UTC timestamps. Posted line and
movement tables are append-only. Financial values use `numeric(20,6)` unless a higher intermediate
scale is explicitly required; exchange rates use at least `numeric(20,10)`.

| Entity | Schema/table | Required fields and constraints | Primary indexes |
|---|---|---|---|
| Lead | `crm.leads` | code, names, optional party/contact, source, owner, stage, expected value/currency/date, reason, status; unique tenant/code | tenant/owner/stage/status/date/id |
| CRM activity | `crm.activities` | aggregate type/id, activity type, subject, owner, due/completed, outcome, notes; scoped aggregate | tenant/aggregate/time/id; tenant/owner/due/id |
| Opportunity | `crm.opportunities` | code, party/prospect, owner, stage, probability, expected value/currency/date, forecast bucket, reason; unique tenant/code | tenant/owner/stage/date/id |
| Workflow event | `workflow.process_events` | workflow instance, document, from/to stage, actor/owner, entered/completed, active/wait minutes, reason, correlation; append-only | tenant/document/time/id; tenant/stage/time/id |
| Approval decision | `workflow.approval_decisions` | existing request, matrix/version/step, actor, decision, note, amount/currency, decided time; append-only and one decision per step/actor rule | tenant/request/step/time/id |
| Quotation | `sales.quotations`, `sales.quotation_lines`, `sales.quotation_revisions` | customer, terms, currency/rate, validity, exact totals, lifecycle, revision; lines preserve unit conversion/tax/source | tenant/entity/status/date/id; customer/status/id |
| Sales order | `sales.sales_orders`, `sales.sales_order_lines` | customer, source quote, terms, warehouse, dates, exact totals and ordered/cancelled/allocated/delivered/invoiced quantities | tenant/entity/status/date/id; customer/status/id |
| Delivery | `sales.deliveries`, `sales.delivery_lines` | order/source lines, warehouse, tracking inputs, posted time, movement/journal links; immutable after post | tenant/entity/posting/date/id; source line/id |
| Sales invoice | `sales.sales_invoices`, `sales.sales_invoice_lines` | customer, order/delivery sources, dates, currency/rate, tax/totals, due/open amount, journal links; unique scoped number | tenant/entity/status/date/id; customer/due/id |
| Customer receipt | `sales.customer_receipts` | customer, cash/bank account, date, currency/rate, reference, amount/unapplied, journal/reconciliation state | tenant/entity/customer/date/id; bank/date/id |
| Sales return/credit | `sales.sales_returns`, `sales.sales_return_lines` | original delivery/invoice line, eligible quantity/value, reason, disposition, movement/journal/open-item links | tenant/entity/status/date/id; source line/id |
| Purchase requisition | `procurement.requisitions`, `procurement.requisition_lines` | requester, dates, justification, dimensions, exact quantities/estimates, lifecycle | tenant/entity/requester/status/date/id |
| RFQ and supplier response | `procurement.rfqs`, `procurement.rfq_lines`, `procurement.supplier_quotes`, `procurement.supplier_quote_lines` | requisition sources, invited supplier, terms, currency/rate, comparable exact values, selection rationale | tenant/entity/status/date/id; supplier/status/id |
| Purchase order | `procurement.purchase_orders`, `procurement.purchase_order_lines`, `procurement.purchase_order_revisions` | supplier, source, terms, warehouse, dates, exact totals and ordered/cancelled/received/billed quantities | tenant/entity/status/date/id; supplier/status/id |
| Goods receipt | `procurement.goods_receipts`, `procurement.goods_receipt_lines` | PO/source line, accepted/rejected quantities, warehouse/tracking, movement/accrual links; immutable after post | tenant/entity/posting/date/id; source line/id |
| Supplier bill | `procurement.supplier_bills`, `procurement.supplier_bill_lines`, `procurement.match_exceptions` | supplier/reference, PO/receipt sources, due date, currency/rate, tax/totals, match status/decisions, AP/journal links | tenant/entity/supplier/reference; due/status/id |
| Payment proposal/payment | `procurement.payment_proposals`, `procurement.supplier_payments` | selected AP items, approval version, bank account, currency/rate, amount, reference, posting/reconciliation state | tenant/entity/status/date/id; bank/date/id |
| Purchase return/debit | `procurement.purchase_returns`, `procurement.purchase_return_lines` | original receipt/bill line, eligible quantity/value, reason, movement/journal/open-item links | tenant/entity/status/date/id; source line/id |
| Product unit conversion | `inventory.product_unit_conversions` | product, transaction unit, positive integer numerator/denominator, validity/status; unique active product/unit | tenant/product/status/unit |
| Lot | `inventory.lots` | product, lot code, manufacture/expiry, disposition/status; unique tenant/product/code | tenant/product/status/expiry/id |
| Serial | `inventory.serials` | product, serial code, current warehouse/status, lot optional, last movement; unique tenant/product/code | tenant/product/status/id; tenant/warehouse/status/id |
| Stock movement | `inventory.stock_movements`, `inventory.stock_movement_lines` | type, source, posted time, warehouse/from/to, exact quantity/value/cost, lot/serial links, reversal; append-only | tenant/entity/warehouse/product/time/id; source/id |
| Stock balance | `inventory.stock_balances` | entity, warehouse, product, on-hand, moving-average cost, carrying value, last movement/version; maintained transactionally and reproducible | tenant/entity/warehouse/product unique |
| Reservation | `inventory.stock_reservations` | demand source line, warehouse/product/lot optional, exact reserved/fulfilled/released, expiry/status/version | tenant/entity/warehouse/product/status; demand/id |
| Stock count/value adjustment | `inventory.stock_counts`, `inventory.stock_count_lines`, `inventory.value_adjustments` | cutoff, counted/system quantity, variance, allocation basis/value, reason, approval, movement/journal links | tenant/entity/warehouse/status/date/id |
| Journal entry | `finance.journal_entries` | period, sequence, posting date, source/reversal, currency context, description, status/poster; unique scoped sequence; append-only after post | tenant/entity/period/date/id; source/id |
| Journal line | `finance.journal_lines` | journal, posting account, transaction/base debit/credit, party and dimensions, source line; debit/credit exclusivity | tenant/entity/account/date/id; journal/ordinal |
| Open item | `finance.open_items` | AR/AP kind, party, source, currency/rate, original/open/due/base amounts, due date/status; source uniqueness | tenant/entity/kind/party/due/status/id |
| Allocation | `finance.open_item_allocations` | source/target items, transaction/base amount, exchange/write-off, reversal link, actor/time; append-only | tenant/entity/source/time/id; target/time/id |
| Cash/bank account | `finance.cash_bank_accounts` | entity, currency, GL account, optional branch, reconciliation rules, status; unique scoped code | tenant/entity/status/code/id |
| Bank statement | `finance.bank_statements`, `finance.bank_statement_lines` | account, external statement/line identities, dates, exact amounts/balances, import job, match status; unique account/external IDs | tenant/account/date/id; unmatched/date/id |
| Bank reconciliation | `finance.bank_reconciliations`, `finance.bank_matches` | account/period, statement and ledger line sets, totals, adjustment, status, reversal, actors/times; append-only after completion | tenant/account/status/date/id; statement line/id; ledger line/id |
| Budget | `finance.budgets`, `finance.budget_lines` | entity, year/period set, version, workflow status, account/dimensions, exact currency amount; unique versioned scope | tenant/entity/status/year/id; account/period/id |

### Ledger invariants

- A stock movement line has one source, one product, one signed base quantity, and one exact base
  value; headers and lines are immutable after posting.
- A journal line has exactly one positive debit or credit side in base currency. Zero-value
  memorandum lines do not belong in the posted journal.
- AR/AP control accounts are system-controlled: commercial posting, allocation, reversal, and
  approved migration commands are their only mutation paths.
- Cached `stock_balances` and open-item residuals are transactional projections. Verification MUST
  reproduce them from append-only movements/allocations and fail the release gate on divergence.
- Every posted operational document points to its journal and stock/open-item effects, and every
  effect points back to its source document and source line.

## Out of Scope

- OS-301: Point of sale, e-commerce storefronts, marketplace connectors, customer/supplier portals,
  EDI, and electronic invoicing delivery.
- OS-302: Manufacturing, bills of material, routings, MRP, production orders, quality management,
  and advanced demand/replenishment planning.
- OS-303: Live bank feeds, payment-gateway capture, cheque printing, bank-file generation, and
  execution or release of funds to an external provider.
- OS-304: OCR, automated invoice extraction, external email/SMS/push workers, public attachments,
  and antivirus-provider integration.
- OS-305: Certified Sri Lankan tax determination, statutory return preparation/filing, government
  connectors, or legal/accounting assurance; Wave 3 provides configurable non-certified summaries.
- OS-306: Multi-entity consolidation, eliminations, intercompany settlement, group currency, and
  translation of foreign subsidiaries; reports remain one legal entity at a time.
- OS-307: Payroll, workforce, projects/time billing, service/SLA/work orders, fixed assets,
  depreciation, and maintenance, which remain Wave 4.
- OS-308: AI forecasting, autonomous recommendations/actions, external webhooks/API, SaaS billing,
  operator controls, and advanced intelligence, which remain Wave 5.
- OS-309: Arbitrary SQL/BI, scheduled report delivery, background exports above defined bounds, PDF
  statement rendering, and high-volume partial-success imports.
- OS-310: Staging or production projects, real customer data, deployment, domain/provider
  credentials, billing activation, code signing, or statutory configuration approval.

## Traceability and Test Plan

| Requirement range | Acceptance criteria | Primary evidence |
|---|---|---|
| FR-301–FR-312 | AC-301, AC-324 | pgTAP grants/RLS/idempotency/rollback plus audit/outbox/attachment tests |
| FR-313–FR-318 | AC-302 | domain workflow/forecast tests, RPC tests, CRM widget tests |
| FR-319–FR-334 | AC-303–AC-308 | exact pricing/tax, lifecycle, credit, fulfillment, AR and reversal tests |
| FR-335–FR-349 | AC-309–AC-312 | approval, match/tolerance, receipt, AP/payment and return tests |
| FR-350–FR-361 | AC-313–AC-315 | property tests, concurrent pgTAP, valuation fixtures and traceability tests |
| FR-362–FR-382 | AC-316–AC-320 | balanced-ledger, open-item, bank, FX, period, report and reconciliation tests |
| FR-383–FR-395 | AC-321–AC-324 | widget/golden/platform/offline/capability/export/deep-link tests |
| NFR-301–NFR-306 | AC-301, AC-316, AC-326 | fault injection, security matrix, audit immutability and advisor evidence |
| NFR-307–NFR-313 | AC-313, AC-318, AC-325 | load/query plans, contention, bounds and encrypted-draft tests |
| NFR-314–NFR-320 | AC-320–AC-326 | accessibility/goldens, coverage, pgTAP, report benchmarks, build and launch |

### Approval gate

This specification is **In Review**. Wave 3 implementation is blocked until the product owner
approves this scope or records amendments. Approval authorizes implementation in the existing
synthetic-data development boundary only; it does not authorize deployment, real data, external
providers, payment execution, production secrets, or statutory claims.
