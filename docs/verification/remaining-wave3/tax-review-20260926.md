# AC-320 posted tax review candidate — 2026-09-26

Historical checkpoint. The subsequent tax controls, governed journal tax,
settlements and recovery corrections are recorded in
[tax-controls-review-20260926.md](tax-controls-review-20260926.md).

The development Supabase project `xpdoufauvrbdmxgngetv` was `ACTIVE_HEALTHY` on PostgreSQL 17.6.1 at the final read. Its ledger still had **35 installed migrations**, ending at `20260925181927_wave4_employee_foundation`. Read-only catalog checks found no `finance.tax_reports`, `finance.tax_definition_versions`, `finance.budget_versions` or `finance.financial_reports` outside the rollback tests. The tax, budget, cash-flow and financial-statement migrations remain **unapplied**. No production system, authentication configuration or stock-opening acceptance record was changed.

The committed, unapplied `20260926001000_wave3_tax_summary.sql` candidate freezes effective-dated tax definitions and bill-line treatment, then saves a permission-scoped review of posted invoice, return and supplier bill source lines with their journal lines. The additive, unapplied `20260926002000_wave3_tax_summary_hardening.sql` preserves that committed migration, enforces the requesting-branch filter, adds report version one and retains the source document's date, currency and exchange rate when a journal is missing. The review uses exact base-currency decimal strings, reverses return output tax, separates zero/exempt taxable basis, and blocks unsupported historical or mismatched provenance. Every result displays `NON-CERTIFIED • STATUTORY REVIEW REQUIRED`; it is not a statutory filing. The public contract is `docs/blueprint/38_WAVE3_TAX_SUMMARY_CONTRACT.md`.

`/finance/tax` exposes the frozen source and journal drill under `finance.view`. Its separate encrypted `tax-summary-editor` slot retains a sealed uncertain request across controller restart. Permission revocation clears viewed evidence. The four light/dark 200% text previews were rendered and visually reviewed: `apps/jentra_desktop/test/goldens/tax_review_light_200.png`, `tax_review_dark_200.png`, `tax_review_drill_light_200.png` and `tax_review_drill_dark_200.png`. The blocked review notice, exact totals and source drill remain visible without overflow. The adjacent cash-flow golden test now uses an injected fixed clock, so a calendar rollover cannot invalidate its baseline.

| Check | Fresh result |
|---|---:|
| Strict procurement/finance candidate, one transaction ending in `ROLLBACK` | 563/563 assertions |
| Strict receivables candidate, ending in `ROLLBACK` | `1..169`, no failures |
| Strict inventory candidate, ending in `ROLLBACK` | 105/105 assertions |
| Seven adjacent finance platform/file test suites | 47 passed |
| Seven adjacent desktop/recovery/golden test suites | 72 passed |
| Full desktop and platform Dart analyzers | No issues |
| Current-source Windows release compile | Passed in 75.2 seconds; executable not launched |

The SQL tests exercise posted input/output tax, a sales return reversal, zero/exempt basis, immutable definition history, old unversioned bills, missing journals, branch and actor scope, direct table denial, frozen receipts and evidence. The client tests cover exact-string and scope validation, lineage, encrypted uncertain retry, revocation and rendered layouts. These are synthetic single-transaction tests, not real multi-session contention, an installed candidate, a Windows Credential Manager process restart, an authenticated native walkthrough or owner signoff.

Open AC-320 work remains: reconcile all tax-control GL activity including manual adjustments, originate and govern withholding treatment, complete inventory/GRNI/cash and operational report consolidation, and provide governed cost-centre/project posting dimensions and large-data/export behavior. The wider AC-321–326 verification and native acceptance gates also remain open. Candidate-tested source should not be described as complete Wave 3 or production-ready.
