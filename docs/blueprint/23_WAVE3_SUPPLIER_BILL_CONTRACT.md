# Supplier bills and three-way matching — AC-311 / FR-342–345

Development contract, 2026-09-13. Not installed or accepted.

`api.upsert_supplier_bill` saves an exact, versioned draft. Each sourced line identifies
one accepted receipt line; product, order unit and receipt/PO snapshots remain linked.
The supplier invoice reference is normalized by trimming and case folding and is unique
per supplier/legal entity for every non-cancelled bill. A draft can be cancelled before
posting; posted bills require subsequent debit-note/correction commands. Direct bills
require bill-post authority as well as draft management, and are limited to service,
non-stocked or free-text expense lines. Stock purchases require an accepted receipt.

Pricing uses decimal strings, governed date/currency/FX/input tax and entity rounding.
The server compares invoice quantities, unit prices, discounts, tax identity/rate,
currency and proportional totals against the immutable receipt source PO snapshot.
Receipt availability is recomputed from posted bill lines, excluding the current draft.
Draft matching records bounded per-line exceptions and their exact differences.
Missing/reversed receipt or excess already-billed quantity blocks posting regardless of
approval. Commercial price/discount/tax/currency differences beyond configured exact
amount/percentage tolerances require an accountable independent match decision.

`api.approve_supplier_bill_match` requires bill-post and workflow-decision permissions,
excludes the draft creator/editor, records a reason and binds the exact bill version,
match fingerprint and control version. Editing or changed source availability invalidates
the approval. `api.post_supplier_bill` revalidates everything under locks and creates one
balanced journal and AP open item atomically with source billed counters, immutable
history, command receipt, audit and outbox. Replays return the original result.

Accrual clearing debits the original receipt GRNI account at the proportional receipt
base carrying amount. Input tax debits the configured tax asset; AP credits the invoice
gross amount. Exact net/base differences debit or credit the configured purchase variance
expense account. Stock quantity and carrying value are not duplicated by the invoice.
Direct bill net amounts debit the configured expense account. These mappings and match
tolerances are governed at legal-entity scope through an authenticated finance setup
command and immutable history. No statutory interpretation or external filing is implied.

The existing journal and open-item primitives are reused. AR read policies must be
restricted by `kind='AR'` before introducing AP; AP reads require payable/bill authority.
The additive policy change preserves existing AR predicates and needs compatibility
review before application. The separate stock-opening acceptance scenario stays untouched.

The native workspace includes sourced/direct drafts, named reference pickers, exact
editable amounts, visible match exceptions, approval/post/cancel actions, encrypted local
drafts, sealed retry, source/detail views and safe conflict recovery. Candidate tests,
installed behavior, native acceptance, real contention and external gates remain distinct.
