# Remaining Wave 3 development status

Refreshed 2026-09-15 against `main` at `b0aa757`, source and development API catalog.
Development ledger: 34 migrations through `20260911130900_stock_opening_approver_setup`.
No migration applied by this session. Existing acceptance changes preserved.

| Requirement / AC | Status | Concrete implementation / evidence | Dependency and next action |
|---|---|---|---|
| FR-301–312 / AC-301 | Partial | `20260904121647_wave3_operational_foundation.sql`; command hashes, scope, receipts, audit, workflow helpers | Reuse and verify for each new aggregate |
| FR-313–318 / AC-302 | Implemented with recorded development verification | CRM domain/gateway/screen; blueprint 09 | Preserve; include regression; native acceptance remains separate |
| FR-319–321 / AC-303 | Implemented with recorded development verification | quotation workspace/domain/gateway; blueprint 10 and 12 | Preserve; include regression |
| FR-322–325 / AC-304 | Implemented with recorded development verification | sales order workspace; blueprint 13 and 14 | Preserve source tracing and reservations |
| FR-326–334 / AC-305–308 | Partial | receivables workspace and `20260910135010_complete_delivery_receivables.sql`; blueprint 15–16 | Existing development evidence; authenticated acceptance and contention remain open |
| FR-335–339 / AC-309 | Partial | Requisition, sourcing, direct requisition/selected-RFQ PO and product-unit modules; seven unapplied candidate migrations; 67 rollback database checks, 8 domain tests, 21 controller/widget checks and 22 platform/recovery regression checks pass | Wider security/recovery/scale coverage and review; isolated Windows compile passed before latest direct-PO UI additions; install only after compatibility review |
| FR-340–341 / AC-310 | Partial | Receipt/reversal and independent exact allowance candidate, authenticated gateway, native workspace, encrypted recovery; 7 receipt UI/recovery and 3 receipt domain tests passed | EC-320 conversion-drift guard corrected in final blueprint review; broader scope/FX/cost regressions, installation and native acceptance remain |
| FR-342–345 / AC-311 | Partial | Supplier bill drafts, matching/independent exception decision, atomic GRNI/tax/AP, direct expenses, cancellation, native editor and encrypted recovery; combined procurement/bill suite 132 rollback assertions passed before latest EC-320 addition; 6 bill UI/recovery checks pass | Broader FX/permissions tests, bounded detail performance and installation; AR helper narrowing requires compatibility review |
| FR-346–349 / AC-312 | Partial | Native supplier payment proposals/approval, recorded payments, independent allocation/reversal, dated statements/aging, purchase returns/debit notes and encrypted retry; contracts 24–25. Twelve candidates pass 240 rollback assertions; 56 procurement UI/recovery checks, 31 platform/storage checks and 12 domain checks pass | Richer source navigation, wider FX/scale and real contention checks, installation and native acceptance remain |
| FR-350–353 / AC-313 | Partial | Existing stock foundations; new governed product-unit master and native editor, exact requisition→RFQ→PO conversion chain tested | Integrate frozen conversions with receipts and remaining stock consumers; shared sales/stock changes need compatibility review |
| Stock-opening native acceptance | Acceptance-owned | `features/stock_opening`, access gateway, `docs/verification/stock-opening` | Do not alter ACPT records, sequences, authentication or running executable |
| FR-354–355 / AC-314 | Partial | Opening/delivery/receipt/return lot and serial paths; return tests prove expired-lot supplier disposition and unique serial receipt→return history | Transfer/disposition workspace, full trace report and concurrent tracking checks remain |
| FR-356–361 / AC-315 | Partial | moving average, sales reservation/cancellation and movements | Missing transfer/count/value-adjustment commands; dated valuation/GL reconciliation and release gaps |
| FR-362–366 / AC-316 | Partial | posted journals from lead-to-cash | Manual journals, approval and full source drill-through |
| FR-367–369 / AC-317 | Partial | AR open items and cash/bank setup within receivables | AP control reconciliation and allocation reversal |
| FR-370–371 / AC-318 | Missing | No bank import/matching workspace | Bounded statement imports, matching and reasoned reversal |
| FR-372–374 / AC-319 | Partial | exact FX values and open-period lock helper | FX revaluation, period governance and contention verification |
| FR-375–382 / AC-320 | Missing | Finance route placeholder | Financial statements, tax summaries, approved budgets and exact variance |
| FR-383–395 / AC-321–324 | Partial | existing shared design, encrypted drafts, reference pickers, reports | Integrate new modules; test scope revocation, retry, accessibility and bounded export |
| NFR-307–320 / AC-325 | Partial | historical per-slice logs | New real concurrency, performance and rendered UI evidence required |
| AC-326 | Missing | No complete remaining-Wave-3 verification | Final solo review, fix findings, full applicable development checks |
| Native walkthrough / owner signoff | External gate | Separate acceptance session | Never substitute automated tests for native acceptance |
| Waves 4–6 | External gate | Roadmap in blueprint 05 | Separate detailed specification and approval; outside this implementation |

Historical test records are not fresh execution in this session. An API catalog absence is
corroborated by source searches; foundation permissions do not establish feature completion.
Security advisor refresh reports leaked-password protection disabled; no auth configuration
was changed. Persistent business writes remain authenticated application commands only.

Current automated checkpoint: 240 rollback-only procurement database assertions,
56 procurement UI/recovery/golden checks, 31 platform/gateway/storage checks and
12 exact domain checks pass. All 85 delivery/receivables regression assertions also
pass with all twelve candidates. Twelve candidates remain unapplied. Isolated Windows
release builds passed for allocations (184.1 seconds), initial returns (68 seconds)
and the exact return preview (46.6 seconds). No executable was launched.

Remaining: broader AC-312 verification and source navigation; transfers/in-transit,
counts, adjustments, tracking/valuation reports, the missing finance and cross-cutting
requirements above, installation coordination and final complete Wave 3 solo review.
