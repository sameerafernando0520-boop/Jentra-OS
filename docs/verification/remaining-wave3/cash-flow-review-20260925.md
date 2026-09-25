# AC-320 indirect cash-flow candidate review — 2026-09-25

The development Supabase project `xpdoufauvrbdmxgngetv` was `ACTIVE_HEALTHY`
on PostgreSQL 17.6 when this work began. The ledger was checked again after
testing: it still ends at `20260911130900_stock_opening_approver_setup` (34
installed migrations). Neither `20260925002000_wave3_financial_statements.sql`
nor `20260925003000_wave3_cash_flow.sql` was installed. Every candidate SQL
execution was enclosed in a transaction ending in `ROLLBACK`; the strict
pgTAP finish rejected failures. No production, authentication, stock-opening
acceptance record or push was changed by this cash-flow follow-up. The shared
checkout independently advanced from `d99fe10` to `307c006` while this work
ran; that commit contains the first financial-statement slice and concurrent
Wave 4 work. The new cash-flow follow-up remains unstaged.

The new migration adds dated, immutable per-account cash-flow classifications
under entity and branch scoped `finance.cash_flow.configure`, a blocked
indirect bridge built from posted financial statement evidence, comparative
classification at the earlier cutoff and frozen mapping-decision lineage.
Hard close recalculates the bridge for a posted period and records an explicit
`CASH_FLOW_UNMAPPED` exception if it cannot reconcile. The old period checks
remain in the chained function. An empty period has no cash-flow blocker.

| Check | Fresh result |
|---|---:|
| Strict combined procurement/finance rollback suite | 503/503 assertions, no failures |
| Strict inventory regression rollback suite | 105/105 assertions, no failures |
| Strict receivables regression rollback suite | `1..158`, no failures |
| Focused statement/cash-flow gateway tests | 8 passed |
| Adjacent finance gateway tests | 30 passed |
| Adjacent finance desktop and golden tests | 52 passed |
| Focused platform and desktop analyzers | No issues |
| Current-source Windows release build | Passed in 74.8 seconds; not launched |

The rollback assertions cover exact profit and cash bridges, comparison,
unmapped current and hard-close blocking, later dated mapping, stale version,
idempotent replay, immutable saved reports and mapping events, direct-table
denial, cross-actor denial and account-to-mapping evidence. The client tests
cover malformed exact amounts, hidden blocker rejection, response scope,
mapping receipt validation, encrypted retry with the identical envelope,
offline concealment and revocation. The mapping and blocked report previews
were opened and visually checked at 200% text in both light and dark themes;
the visible controls and blocker text were legible without overflow. The
report remains scrollable below the first viewport.

The prior `financial-statements-review-20260925.md` is the historical first
slice result. This entry supersedes its cash-flow-open statement, not its
record of what was tested at that earlier checkpoint.

Still open inside AC-320: tax summaries with posted tax-line provenance and
effective-dated definition history, budget approval and exact dimensional
variance, inventory/GRNI/tax/cash control consolidation, larger report/export
coverage and real load/contention. Installed behavior, a real Credential
Manager process restart, authenticated native walkthrough and owner signoff
remain unevidenced. Candidate checks cannot be called Wave 3 acceptance.
