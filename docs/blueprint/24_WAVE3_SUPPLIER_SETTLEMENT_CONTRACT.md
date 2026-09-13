# Supplier settlement — AC-312 / FR-346–349

Development contract, 2026-09-14. No external payment execution.

Payment proposals reserve selected due AP items for one supplier, branch and payment
currency. Exact allocations and the configured cash/bank account are reviewed together.
Submission uses the active payment workflow and amount/currency matrix, freezes the
approval steps and prevents creator/editor/submitter self-approval. Recall, rejection and
cancellation release operational claims; posted payment history is immutable. Changes
to dates, account, amounts or allocations require a new approval version.

Claims serialize competing proposals and keep the selected amounts unavailable to another
active proposal. Posting rechecks open-item residuals under deterministic row locks;
settled, reversed, changed or incompatible items invalidate the proposal. The bank account
must be active, scoped and use the payment currency. A stored payment FX rate determines
cash base value. AP clearing uses original carrying amounts; realized differences post to
governed exchange gain/loss mappings, never float arithmetic.

`api.upsert_payment_proposal` persists the governed proposal. `api.post_supplier_payment`
records the approved proposal and supplied payment reference
without contacting a bank. It atomically creates the AP/cash journal, a negative AP open
item, allocations against the approved bills, command receipt, audit and outbox. The
payment remains pending bank reconciliation. Identical retries return the prior receipt.

Independent allocation commands apply existing unapplied supplier credits/payments to
eligible bills with exact residual limits, party/entity/branch checks and governed rates
when currencies differ. Allocation reversals retain the original links and restore dated
residuals; they never delete posted history. Supplier statements and configurable AP aging
use posting dates and allocation dates, with credits visible separately and source links.

Purchase returns and debit notes must reference received/billed quantities and preserve
the original receipt, invoice and valuation history. These follow recorded payments in
the implementation order; their exact inventory/GL contract will be added before coding.

Native workspace requirements include due-item selection, proposal approval, recorded
payment references, allocations and statements, with encrypted drafts, durable uncertain
commands, exact strings, visible lifecycle, loading/error/empty states and bounded paging.
Automated verification, installed migrations, native acceptance and external gates remain
separate. No stock-opening acceptance records, sequences or auth state are used.
