# Purchase returns and supplier debit notes — AC-312 / FR-348

Approved Wave 3 implementation contract; synthetic development only. Candidate
migrations and automated verification do not establish installation or acceptance.

`api.post_purchase_return` uses the standard authenticated command envelope and
`procurement.returns.post`. One immutable source document per return, either a posted
supplier bill or a non-reversed goods receipt, with 1–500 distinct source lines.
Payload: `id`, `source_kind` (`bill`/`receipt`), `source_id`, `document_date`, `reason`,
`reference`, and lines containing `line_id`, `source_line_id`, decimal-string
`quantity`, and selected `serial_ids` where applicable. Expected version is null;
source eligibility is recalculated under aggregate locks. A sealed local draft keeps
the identical command across uncertain sends and restart.

Bill returns consume original bill-line quantities and reverse their frozen net and
tax amounts by cumulative proportional rounding, never repricing at current prices.
The resulting negative AP open item can be allocated using the supplier settlement
workspace. Already paid bills remain eligible; settlement and physical return are
separate events. Original bill-level base rounding is distributed cumulatively, so
complete returns exhaust its exact carrying value. Tax base amounts follow original
tax journal lines. Current valid posting accounts are required; source AP, tax and
expense accounts are retained, with explicit variance for stock cost differences.

Receipt-only returns consume accepted quantities not already billed or returned
unbilled. They reverse the corresponding original GRNI amount and do not create AP
or reverse tax that was never posted. Bill matching subtracts these returned quantities
and shares cumulative accrual rounding with them. Every physical return also consumes
the receipt's overall return allowance; billed and unbilled paths cannot double return.

Stocked lines issue available unreserved stock from the original receipt warehouse,
using its frozen rational unit conversion and original lot/selected original serials.
The active product-unit master must still match that frozen conversion at posting.
Disposed, moved or unavailable serials cannot be returned again. Expired lots may be
returned to their supplier; this does not make them saleable. Moving weighted average
uses the existing six-decimal carrying-value policy and consumes the full remaining
value for a complete stock issue. The difference from supplier credit/original accrual
is posted to the configured variance expense account. Nonstock returns reverse expense.

Locks follow bill, sorted purchase orders/lines, period, sorted warehouse/product,
balance/valuation, tracking. Receipt reversal and bill posting share the order locks.
No future posting; source and later stock/return events prevent unsafe backdating.
Stock, tracking, valuation, journals, AP, return lines, command receipt, audit and outbox
commit atomically. Posted return headers/lines are immutable and link original sources;
PO received/billed history is not rewritten or automatically reopened by a return.

Read APIs: permission-scoped keyset return register and bounded source picker/detail.
Native workspace exposes receipt versus bill source, eligible quantities, reason,
reference, tracking, encrypted local save, sealed retry and posted source evidence.
An advisory BigInt amount preview uses the same cumulative source rounding; posting
recalculates it under source locks. Current moving-average cost stays in the protected
stock movement ledger, rather than being duplicated in a return poster's response.
Financial and quantity JSON values remain decimal strings. No supplier email or funds
are sent. Wider concurrency/load/native acceptance remain separately evidenced gates.
