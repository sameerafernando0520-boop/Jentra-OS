# Governed AR/AP opening-document import

User requirement, 4 November: import existing unpaid customer and supplier documents from CSV/Excel for company accounts cutover.

## User workflow

Finance selects the company/entity/branch, cutoff, AR or AP, transaction currency, source-system name, control account and equity opening-clearing account. Download a template, select CSV/XLSX, inspect row issues and exact totals, correct the file, save a draft, submit it, obtain independent approval and explicitly post. Show immutable imported source details and resulting open items/journals. A failed row prevents posting the entire batch.

The initial batch contains at most 500 rows, one branch/kind/transaction currency and one cutoff. Reuse `SetupTabularCodec` and `SetupFileService`: 5 MiB input, safe bounded XLSX, exact decimal strings, no formulas/macros/external links. Do not add another spreadsheet parser.

Required columns: `external_document_key`, `party_code`, `document_number`, `document_date`, `due_date`, `currency`, `outstanding_amount`, `carrying_base_amount`. Preserve optional legacy gross/settled amounts as source metadata. Reject unsupported/missing/duplicate columns, malformed dates, future original-document dates relative to cutoff, empty/duplicate external keys, unknown parties, zero residuals, inconsistent signs/currencies and amounts outside exact numeric limits. Report row and field; never silently round excess input precision or guess locale/date formats.

## Accounting boundary

`finance.open_items.original_amount/original_base_amount` represent the imported remaining balance at cutoff. Retain the original document date and history in immutable source metadata and the original due date for ageing. Do not invent historical sales/purchases, receipts, tax or allocations.

Post one two-line journal per opening item. Existing control-basis discovery compares a journal's account-type sum to a single item's original base amount, so one aggregate batch journal is not compatible. Positive AR debits control/credits clearing; positive AP credits control/debits clearing; negative residuals reverse those signs. Use an equity clearing account, exact imported carrying value, existing period locking/posting helpers, scoped permissions and MFA. Preserve manual-journal AR/AP-control denial.

Use explicit source types `opening_receivable` and `opening_payable`, with the opening line as source ID. Integrate source-detail routing instead of coercing these into sales-invoice enums. Refresh AR credit exposure. Existing reconciliation, allocations and FX must consume the resulting source correctly.

The full opening trial-balance process excludes controls already supplied by AR/AP, stock and asset opening workflows. Reconcile combined opening clearing to zero before declaring cutover complete. Statement history currently caps at 10,000 journal lines and FX snapshots at 1,000 foreign open items; expose limits and resolve expected company volume.

## Server contract

Add private RLS-protected `finance.opening_batches` and `finance.opening_lines` with scoped paginated facade reads. Persist file digest, cutoff, source-system identity, stable line IDs, row numbers, normalized source metadata, approved account/party versions, immutable content hash and resulting journal/open-item IDs.

Proposed public seams:

- `api.upsert_finance_opening_batch`: validate and save a draft with optimistic version and stable command identity.
- `api.transition_finance_opening_batch`: submit, recall/reject, independently approve and cancel before posting.
- `api.post_finance_opening_batch`: reauthorize after deterministic locks, validate unchanged approval/period/source, reject duplicates across batches, and atomically post all rows.
- Scoped batch/line/source-detail and reference reads through the API schema.

State: draft → pending approval → approved → posted. Editing invalidates approval. Posted imports are immutable; corrections require an explicit reviewed compensating command with settlement-history guards. No row deletion or journal rewriting.

Duplicate identity covers tenant/entity/branch/kind/source-system/party/external document key across cutoffs and batches. Preserve existing idempotent envelope/replay contracts; changed payload replay fails. Lock batches, duplicate identities, periods and affected credit records in deterministic order. Execute final permission/MFA checks after locks and before replay or mutation.

## Verification boundaries

Use the user-facing CSV/Excel preview boundary and the public save/approval/posting/read APIs. Meaningful cases include partial legacy residuals; positive/negative AR and AP; exact decimal/FX/base values; original ageing; duplicate files/documents; changed replay; row-error atomicity; self-approval, foreign scope and revoked access; stale approval/accounts; closed periods; subsequent settlement/correction; control/GL reconciliation; concurrent post and acknowledgement recovery.

Existing stock-opening, period, AR/AP control, tabular codec and local candidate harnesses provide the starting fixtures. Pure/local results do not establish hosted rollout or company cutover acceptance. The production feature remains unavailable until the reviewed server/client combination and signed company opening reconciliation are accepted.
