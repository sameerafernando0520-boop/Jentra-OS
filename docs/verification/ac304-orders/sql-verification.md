# AC-304 SQL verification

2026-09-07. Only development project `xpdoufauvrbdmxgngetv` was used.

The live ledger and existing function definitions were queried before constructing
the additive migration. Initial assertions reproduced the missing coherent detail
view and inactive-customer confirmation gap. The candidate migration was tested
inside explicit transactions and rolled back before development application.

| Strict pgTAP suite | Assertions |
| --- | ---: |
| Foundation | 30 |
| Wave 2 | 99 |
| Operational foundation | 50 |
| CRM workspace | 88 |
| Lead to cash | 46 |
| Quotation workspace | 43 |
| Order workspace | 28 |
| **Total** | **384** |

All six baseline suites passed with the candidate DDL in their rolled-back
transactions. The new order suite passed with the candidate and passed again after
the migration was applied. Strict `finish(true)` makes a failed assertion an SQL
error; each suite's fixtures were rolled back.

The new suite exercises coherent RLS detail reads, exact credit exposure and
overdue-subset handling, missing projection disclosure, currency mismatch,
preview/decision agreement, inactive customer/product/warehouse rejection,
already-delivered remaining demand, cancellation/release quantities, unchanged
on-hand stock, traced immutable conversion, fulfillment allowlisting,
optimistic-version conflict, replay, role/tenant denial and injected late-outbox
failure with complete rollback.

`plpgsql_check` returned zero findings for the credit preview, fulfillment update,
operational transition and stock reservation functions. Its extension was created
in a transaction that was rolled back. Fresh security advisors had zero findings.

Applied migration: `20260907044241_complete_sales_order_workspace.sql`.
Applied SQL MD5: `158d3661ed7a61784963c8142a9c163d`. The local file and applied
statement are identical after CRLF/LF normalization; no prior migration was edited.

Final read: `2026-09-07 11:13:42.536716 UTC`, migration count 29, latest version
`20260907044241`, quotations 0, sales orders 0. Production was not accessed and no
permanent business fixtures were retained.
