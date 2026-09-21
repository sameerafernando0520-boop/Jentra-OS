# Stock counts and approved quantity adjustments — AC-315 / FR-358

Development contract, 2026-09-16. Candidate scope; no installation or native
acceptance claim. Separate from the protected stock-opening aggregate.

`api.upsert_stock_count` creates/edits a governed count using the standard command
envelope, `inventory.adjustments.post` and `inventory.cost.view`. The first save
locks each selected warehouse/product, captures current on-hand quantity and stock
version, and records a server cutoff timestamp. Counted quantities describe the
physical count at that cutoff. Later edits preserve the baseline; removing/replacing
baseline lines requires a new count. Quantities use decimal strings in the product's
active base unit; alternate units must first be converted through governed exact units.

The count workspace supports untracked, lot-tracked and serial-tracked stocked
products. Tracked products require capture mode on first save. The server captures
every existing lot balance or eligible serial in the warehouse (maximum 500
identities per product); oversized identity sets fail explicitly and require a
separately designed partitioned count, never silent truncation. Lot quantities and
serial presence are entered against these frozen identities. The entire document is
also capped at 500 identities. Registers return 50 summaries per page; scoped detail
is fetched separately through `api.stock_count_detail`, never multiplied into register
pages. Product totals are
server-derived from identity counts, not trusted from the caller. Unknown identities
require their governed receipt/master workflow before counting.

Each lot delta preserves its original lot, expiry and disposition. A shortage cannot
consume a lot's later balance; aggregate availability still protects reservations.
Serial counts capture available and quarantined serials plus serials previously marked
missing by a count. A missing serial enters `count_missing`, which cannot be issued or
transferred. Its prior available/quarantine disposition is retained. A later independently
approved count can restore that same identity and disposition. Issued, disposed,
in-transit, moved or otherwise changed serials cannot be resurrected by a stale count.
Every nonzero identity delta appears on an immutable stock movement line. The existing
inventory movement, balance, valuation and journal tables remain authoritative.

Tracked valuation allocates the exact product variance value across identity deltas
using deterministic cumulative rounding; signed identity values sum exactly to the
product delta. Approval uses the sum of absolute identity values, including offsetting
lot changes. Posting processes increases before decreases so an approved redistribution
does not temporarily exhaust a balance or introduce rounding residue.

`api.transition_stock_count` submits, recalls, cancels or records independent
approval against an active `stock_count` workflow and amount/currency matrix.
The preparer/creator/submitter cannot approve. Submission freezes exact absolute
variance value, inventory account, expense variance account and posting basis.
Editing requires recall/reapproval. No configuration or role assignment is created
implicitly by these commands.

`api.post_stock_adjustment` requires approval, expected version, an open posting date
and the original immutable request identity. It applies counted minus cutoff quantity
to current stock under the existing sorted inventory locks, rather than replacing
stock that moved after the count. Negative adjustments cannot consume reservations.
Value uses pre-adjustment weighted average; a positive adjustment into empty stock
requires an explicitly approved exact unit cost. If valuation changed from the approved
basis, posting fails and requires recall/reapproval. Zero variances create no movement.

Nonzero adjustments atomically post inventory and expense variance through the existing
`finance.flow_post_journal`, with source-line drill-through, audit, receipt and outbox.
Any stock, account, tracking, period or numbering failure rolls back all effects.
Posted count and line snapshots are immutable. Corrections require a new linked,
reasoned count/adjustment; no destructive edits or automatic stock-opening reuse.

The native workspace must select named warehouse/product/account references, expose
cutoff/baseline/count/variance, support draft save, configured approval and posting,
and retain encrypted uncertain commands across restart. It must distinguish a local
unsaved form from a server draft and approved/posted state. Candidate tests, installation,
real contention, native recovery and owner acceptance remain separate evidence.
