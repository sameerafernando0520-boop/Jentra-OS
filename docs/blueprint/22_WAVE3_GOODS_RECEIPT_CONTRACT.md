# Goods receipts — AC-310 / FR-340–341

Development contract, 2026-09-13. Candidate work; no installed or native acceptance claim.

An encrypted local receipt draft selects one approved PO revision, its receiving warehouse,
posting date and source lines. `api.post_goods_receipt` uses the established authenticated
command envelope. Its expected version is the source PO version. Each line carries an
immutable client UUID, PO line ID, exact accepted/rejected quantities, rejection reason and
lot or serial identities. Product, unit, conversion and net price come from the locked PO.
Do not accept client totals or replace a historic PO ratio with a changed conversion.
EC-320 requires the active master to still agree with the frozen ratio at posting;
drift blocks receipt until the governed master is restored or a new document basis is approved.

Only accepted quantities consume the PO remaining quantity and enter stock. Rejections
require a reason and remain visible without stock or journal value. Partial receipt values
use the frozen net line value and cumulative proportional rounding at the entity precision;
the last normal receipt receives the exact remaining net value. Input tax belongs to the
supplier bill, preventing receipt/bill value duplication. Currency and FX use the approved
PO snapshot; differences at invoice/settlement belong to the subsequent finance slice.

Posting locks the PO header, source lines in ID order, the fiscal period, then sorted
warehouse/product keys and stock rows using the established inventory lock namespace.
It increments operational received quantities and PO version, retaining a history snapshot;
it does not change commercial prices or the approved revision. Movement, value, tracking,
GRNI journal, command receipt, audit and outbox commit together. All-rejected receipts
have no movement or journal. Zero-cost accepted goods may move without monetary lines.

`procurement.receipt_controls` holds entity-wide GRNI and default non-stock expense
accounts, governed by an authenticated `finance.setup.manage` command with entity-level
authority and immutable control history. Accounts must be active posting accounts of the
right type and currency. No changes to acceptance-owned finance setup are made.

`api.reverse_goods_receipt` requires receipt posting permission, a reason, an open posting
date and expected receipt version. It writes an immutable, uniquely linked reversal,
opposite movement and original-account journal, and restores PO remaining quantity.
Original receipt rows stay unchanged. A billed or consumed receipt is blocked and must
use the governed purchase-return/bill-correction flow. Reversal cannot consume reserved
stock or leave a zero-quantity nonzero carrying value. Serial identities remain in history.

Reads are scoped security-invoker views with exact decimal strings. Native receipt drafts
use a separate encrypted slot, retain the sealed command after uncertain results, and retry
the same request body/key. Named reference reads expose eligible POs and active mappings.

The next tolerance extension adds an exact entity maximum percentage, default zero.
A receipt poster who also has workflow decision authority may approve a reasoned extra
quantity for one line and exact PO version, excluding the PO creator/editor/submitter.
The approver cannot post using their own allowance. The command freezes an absolute
received-quantity ceiling within the configured percentage, and posting rechecks the
current control and source version. One post advances the PO version, expiring unused
allowances. Applied extra quantities are explicit operational counters; they do not
rewrite approved commercial quantity. Until this extension is verified, excess fails closed.

Real multi-session races, native authenticated acceptance and scale measurements remain
separate verification gates. Backdated stock receipts behind a later movement are blocked
pending governed cost review; no retrospective recosting is silently performed.
