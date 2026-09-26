# Remaining Wave 3 development status

Refreshed 2026-09-26 against `main` at `6595d14`. AC-317 was committed at
`4e0a244`; AC-318 and the first AC-319 candidate at `d99fe10`; the first
AC-320 statement slice at `307c006`. The cash-flow, budget and concurrent Wave 4
source updates were committed at `6595d14`. The tax-control/governed-tax follow-ups
and report-recovery corrections are dirty and unstaged, together with the GRNI
extension. Concurrent Wave 4 work is separate. The latest scoped results are 671
procurement/finance, 169 receivables and 105 inventory strict rollback assertions;
83 platform/storage and 116 desktop tests pass with clean full analyzers. See
`docs/verification/remaining-wave3/grni-review-20260926.md` for this continuation.
Earlier transfer/journal checkpoints are historical.
Supabase reconnection and the required development refresh are complete. The ledger
started at 35 installed migrations; the final 09:10 UTC refresh reports 36 through
`20260926082441_wave4_calendar_versions`, a concurrent Wave 4 change. No migration
was applied by this Wave 3 continuation. GRNI/procurement/control/tax candidates
remain absent outside rollback, and all four shared finance fingerprints match.
Acceptance-owned work and authentication configuration are preserved.

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
| FR-354–355 / AC-314 | Partial | Contracts 26 and 29; original lot/serial transfers and receipt quantity trace across issues/returns/transit with a native bounded viewer in `features/receipt_trace/` | Full disposition, historical coverage, installation and concurrent tracking checks remain |
| FR-356–361 / AC-315 | Partial | Contracts 26–31; transfers, tracked counts, reservation release/dated allocations, receipt provenance, single-receipt landed-value posting/reversal and immutable dated inventory/lot/transit valuation with selected-control GL source reconciliation. Fresh 105 inventory, 318 procurement/valuation and 126 reservation/delivery/AR rollback assertions; 75 UI/recovery and 63 gateway/store checks pass. Seven prior exact domain checks remain recorded evidence | Broader landed allocation bases, transit value treatment, correction after later consumption, automatic expiry/retirement and disposition integration remain. Counts cap identities at 500; oversized partitioning, native acceptance, contention and installation are open |
| FR-362–366 / AC-316 | Partial | Contract 32; `20260921041348_manual_journals.sql`, native `features/manual_journal/`, `supabase_manual_journal_gateway.dart`; exact FX, configured independent approval/MFA, separate posting, source evidence and linked reversals. Fresh 348 combined procurement/valuation/journal, 105 inventory and 126 AR/reservation rollback assertions pass with nineteen candidates. 13 journal UI/recovery and 10 gateway checks pass | Broader automatic-source drill-through, attachments upload integration, control mapping contention, installation and native acceptance remain |
| FR-367–369 / AC-317 | AR/AP and GRNI candidates implemented and tested; acceptance open | Contracts 33 and 39; original AR/AP controls/corrections plus additive `20260926007000_wave3_grni_control_reconciliation.sql`. GRNI freezes original receipt accounts, compares dated independent bill/return/reversal amounts against all original/current/historical control GL, retains net-zero source differences, bounds evidence and reuses `/finance/controls`. Confirmation is atomic and evidence clears across disconnect, permission/MFA changes and stale reads. Current combined evidence: 671 procurement/finance, 169 receivables and 105 inventory strict rollback assertions; 83 platform/storage and 116 desktop checks; clean analyzers. See the GRNI review. | All Wave 3 candidates remain UNAPPLIED. Broader supported-source attribution/retired AR/AP mappings, consolidated close/report integration, entity consolidation/export, real contention/load, installation and native/owner acceptance remain |
| FR-370–371 / AC-318 | Candidate implemented and tested; acceptance open | Contract 34; additive `20260923225202_bank_reconciliation.sql`; `/finance/bank` exact CSV/XLSX import, scoped 50-row pages, one-to-one/one-to-many/many-to-one matching, governed tolerance/adjustment, immutable linked reversal and encrypted recovery. Fresh 405 procurement/finance, 105 inventory and 158 AR rollback assertions; 29 platform/codec and 11 desktop tests; analyzers and light/dark 200% visual review pass. See `docs/verification/remaining-wave3/bank-review-20260925.md` | Candidate source committed at `d99fe10`, migration UNAPPLIED. Real multi-session contention, installed behavior, Credential Manager restart, native walkthrough and owner acceptance remain |
| FR-372–374 / AC-319 | Candidate implementation; acceptance open | Contract 35; additive `20260924185321_wave3_period_governance.sql`; period events/reopen requests, independent recent-MFA approval, genuine hard close and immutable blocked exceptions, exact frozen FX valuation with linked reversals and control-difference overlay; `/finance/periods`, scoped RPC gateway and encrypted recovery. Latest strict rollback procurement/finance 445, inventory 105 and AR 158 assertions pass; 22 adjacent gateway and 33 adjacent desktop tests pass, including 8 period/FX tests and light/dark 200% goldens; both analyzers pass. See `docs/verification/remaining-wave3/period-fx-review-20260925.md` | Initial candidate source committed at `d99fe10`; follow-up corrections dirty; migration UNAPPLIED. Real multi-session contention/load, Credential Manager restart, installed/native walkthrough and owner signoff remain |
| FR-375–382 / AC-320 | Partial candidate; acceptance open | Contracts 36–39; statement/cash-flow/budget, five ordered tax candidates and the GRNI extension. Posted TB/P&L/balance sheet/cash flow, approved budgets/frozen variance, versioned posted-tax review, complete cumulative tax controls, original-date/version returns and governed journal tax/control movements remain preserved. GRNI adds independent exact receipt/match/return/reversal reconciliation. `/finance/tax`, `/finance/journals` and `/finance/controls` retain frozen scoped evidence and encrypted recovery. Current combined verification: 671 procurement/finance, 105 inventory and 169 receivables assertions; 83 platform/storage and 116 desktop checks; clean full analyzers. Tax-only historical build evidence remains in its Sep 26 review; current GRNI compilation is recorded separately. | Candidates UNAPPLIED. Consolidated inventory/GRNI/cash and operational reports with close integration, governed cost-centre/project dimensions, attributable bounded exports, supplier withholding allocation/statutory rules, load/contention and native/owner acceptance remain. |
| FR-383–395 / AC-321–324 | Partial | existing shared design, encrypted drafts, reference pickers, reports | Integrate new modules; test scope revocation, retry, accessibility and bounded export |
| NFR-307–320 / AC-325 | Partial | historical per-slice logs | New real concurrency, performance and rendered UI evidence required |
| AC-326 | Partial development verification; full release gate open | Current GRNI/tax/journal/report review preserves exact source control, original account/FX/rounding and encrypted confirmation/access boundaries. 945 rollback database assertions and 199 local platform/desktop checks pass. Current development advisors and unchanged finance fingerprints are recorded. | Full remaining-source coverage, advisor review, real contention/load and all separate installed/native/owner checks remain |
| Native walkthrough / owner signoff | External gate | Separate acceptance session | Never substitute automated tests for native acceptance |
| Waves 4–6 | External gate | Roadmap in blueprint 05 | Separate detailed specification and approval; outside this implementation |

Historical test records are not fresh execution in this session. An API catalog absence is
corroborated by source searches; foundation permissions do not establish feature completion.
The current advisor refresh retains the leaked-password warning and reports seven
RLS-enabled private Wave 4 tables without policies. Performance reports ten
unindexed foreign keys and 297 unused indexes. These are recorded review items,
not fixes or acceptance claims; authentication and concurrent Wave 4 work are untouched.
Persistent business writes remain authenticated application commands only.

Historical procurement automated checkpoint: 240 rollback-only procurement database assertions,
56 procurement UI/recovery/golden checks, 31 platform/gateway/storage checks and
12 exact domain checks pass. All 85 delivery/receivables regression assertions also
pass with all twelve candidates. Twelve candidates remain unapplied. Isolated Windows
release builds passed for allocations (184.1 seconds), initial returns (68 seconds)
and the exact return preview (46.6 seconds). No executable was launched.

Remaining: broader AC-312 verification and source navigation; oversized count partitioning,
broader landed adjustments, disposition, large report extensions, remaining AC-320 control and operational reporting,
AC-321–326 cross-cutting checks, installation coordination and final complete Wave 3 solo review.

## Next development sequence after the GRNI continuation

1. Completed in this continuation: development ledger/catalog/advisor and shared
   finance refresh; original-account GRNI receipt/bill/return/reversal reconciliation,
   frozen scoped drill, bounded failure and encrypted recovery. Preserve these
   unapplied candidates and acceptance-owned work.
2. Consolidate inventory, GRNI and cash controls/operational reports, including
   close-review integration, entity-wide reporting and supported-source attribution.
3. Complete supported posting/budget dimensions and attributable CSV/XLSX report
   exports with exact strings, scope/cutoff/filter metadata and bounded failure.
4. Finish the wider landed-value allocation/correction, oversized count, disposition,
   attachment/source navigation, dashboard/deep-link and cross-module recovery work.
5. Run remaining meaningful security, rollback, query-plan/scale and real concurrent
   development tests. Installation coordination, authenticated native acceptance,
   Credential Manager process restart and owner signoff remain separate gates.

This sequence is unfinished work, not a Wave 3 completion claim. No candidate
installation or production/authentication action is authorized by this continuation.

## Inventory continuation — 2026-09-17

Historical checkpoint; the Sep 19 reservation/tracked-count results in the matrix
and current verification checkpoint supersede the limitations below.

Warehouse transfer implementation now covers dispatch/in-transit, immediate transfer,
receipt and linked reasoned reversal, with frozen value conservation and scoped
lot/serial identity. Dated holdings preserve the original posting-date history and
restrict carrying values to cost-authorized users in both branches. Principal files:
`apps/jentra_desktop/lib/src/features/inventory_transfer/`,
`packages/jentra_domain/lib/src/inventory_transfer.dart`,
`packages/jentra_platform/lib/src/supabase_inventory_transfer_gateway.dart`, and
`supabase/migrations/20260916001000_inventory_transfers.sql`.

The transfer and stock-count candidates are UNAPPLIED, in addition to the twelve procurement candidates.
Its builder is `supabase/tests/build_inventory_candidate.ps1`; it includes the existing
product-unit candidate and ends in rollback. Fresh project health/ledger and both
advisors were checked. No acceptance-owned data, source or runtime was altered.

Stock counts now capture an immutable cutoff, preserve intervening movements, require
independent configured approval, revalidate exact valuation and reservations, and post
quantity/valuation/journal effects atomically. Corrections create a linked new count.
At this Sep 17 checkpoint, the count contract rejected lot/serial products pending their identity-level
extension. Source: `apps/jentra_desktop/lib/src/features/stock_count/`,
`packages/jentra_platform/lib/src/supabase_stock_count_gateway.dart` and
`supabase/migrations/20260916002000_inventory_stock_counts.sql`.

Fresh database checks: 81 combined inventory rollback assertions, 240 procurement
and 85 delivery/receivables regressions with both inventory candidates. Latest completed
client runs: 21 inventory UI/recovery/golden checks, 21 gateway/shared encrypted
storage checks and 3 exact domain tests. Focused analyzer clean after review fixes.
Isolated Windows release build passed in 145.9 seconds; no executable launched.
The subsequent brace-only lint correction is behavior-preserving and analyzed.
See `docs/verification/remaining-wave3/inventory-review-20260917.md` for the solo
review and residual gaps. Real contention, scale, native walkthrough and owner
acceptance are not established by these checks. See the current verification checkpoint.

## Reservation and dated allocation continuation — 2026-09-19

Contract 28, `supabase/migrations/20260918001000_inventory_reservation_release.sql`,
`apps/jentra_desktop/lib/src/features/reservations/`,
`packages/jentra_platform/lib/src/supabase_reservation_gateway.dart` and corresponding
tests add explicit/expired/retired release, immutable version history and bounded
as-of held quantities. The native workspace is `/inventory/reservations`; its editor
uses the isolated encrypted `reservation-release-editor` slot. Only the original
sealed request can resolve an uncertain release. A report cutoff is pinned across
pages and cannot predate history coverage.

All fifteen candidates remain UNAPPLIED. Final fresh checks are in
`docs/verification/remaining-wave3/reservation-review-20260919.md` and the current
checkpoint: 126 reservation/delivery/AR, 105 inventory and 240 procurement rollback
assertions; 43 inventory UI/recovery, 33 gateway/store and 7 domain checks; clean
focused analyzer; isolated Windows release build 48.7 seconds without launch.
The tracked count cap now has explicit 500/501 boundary tests.

Next inventory dependencies are receipt provenance for exact landed-value allocation,
landed-value posting through the existing journal engine, full dated stock valuation
and movement-to-GL reconciliation, then remaining finance in the approved dependency
order. Do not infer original receipt stock remaining from a current aggregate balance.
Automatic expiry/retirement processing, sealed concurrent report snapshots, real
contention/load, native authenticated recovery and owner acceptance remain open.

## Receipt provenance continuation — 2026-09-20

Contract 29 and candidate `20260919181407_inventory_receipt_provenance.sql` implement
exact quantity attribution beside existing stock movements. New receipts retain
traceable cohorts; existing stock starts as unknown. Tracked identity, partial return
restoration, transfer transit/completion/reversal and missing-serial recounts preserve
receipt links. Untracked/lot-pool issues use the documented oldest-recorded-cohort
convention; moving-average costing is unchanged.

The `/inventory/receipt-trace` workspace, `features/receipt_trace/`, and
`packages/jentra_platform/lib/src/supabase_receipt_trace_gateway.dart` expose scoped
current holdings and immutable movement pages, not a landed-value posting form.
Source quantity totals are decimal strings and history cursors preserve bigint values.
Scope revocation clears prior data; historical receipts never claim aggregate stock.

Sixteen candidates are unapplied. New verification: 265 procurement/provenance,
105 inventory, 126 reservation/delivery/AR rollback assertions; 53 inventory UI/recovery
and 41 gateway/store checks; focused analyzer clean; visually reviewed light/dark
200% renders; isolated Windows release in 83.9 seconds without launch. Review and
exact evidence paths are in the current checkpoint. Boundaries and remaining work
are unchanged: next is landed-value allocation/posting/correction, including explicit
handling of transit and returned/adjusted quantities, then dated valuation-to-GL and
the remaining finance requirements. No native acceptance or owner signoff is claimed.

## Landed-value continuation — 2026-09-21

Contract 30, candidate `20260919185538_inventory_landed_value.sql`, native
`apps/jentra_desktop/lib/src/features/landed_value/` and platform
`supabase_landed_value_gateway.dart` now implement an end-to-end single-receipt landed
adjustment. It reclassifies previously recorded freight expense using exact received
quantity, splits remaining inventory from consumed variance, balances journals per
warehouse/branch and supports linked reversal before intervening valuation changes.
It creates no new payable or payment. Register, named pickers, sealed uncertain retry,
stale-preview recovery and permission-revocation clearing are tested.

Seventeen migration candidates remain UNAPPLIED. Fresh checks: 294 combined procurement/
landed, 105 inventory and 126 reservation/delivery/AR rollback assertions; 64 UI/recovery/
golden and 54 gateway/shared-store checks; focused analyzer clean. Light/dark 200% text
renders reviewed. Final isolated current-source Windows release build passed in 49.7
seconds, without launch. Exact evidence and review findings are in the latest checkpoint
and `docs/verification/remaining-wave3/landed-value-review-20260921.md`.

Broader landed allocation bases, in-transit value and corrections after subsequent
consumption remain open, followed by full dated valuation/GL reconciliation, disposition,
remaining finance and cross-cutting work. Native authenticated acceptance, real
Credential Manager recovery, contention/load and owner signoff are separate gates.
