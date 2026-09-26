# Jentra OS Blueprint Dossier

**Status:** Approved through Wave 2 implementation; Wave 3 implementation and acceptance in progress; Wave 4 approved for synthetic development
**Approved:** 2026-09-01
**Product:** Jentra OS — Windows-first business operating system for Sri Lankan SMEs

This dossier is the implementation contract for the greenfield Jentra OS product. The
previous application and visual language are intentionally excluded. Requirements,
interfaces, schema changes, tests, and delivered behavior must remain traceable to these
documents.

## Documents

1. [00_PRODUCT_SPEC.md](00_PRODUCT_SPEC.md) — approved Wave 1 requirements and acceptance criteria.
2. [01_ARCHITECTURE.md](01_ARCHITECTURE.md) — system topology, package boundaries, and architecture decisions.
3. [02_DOMAIN_AND_PROCESS.md](02_DOMAIN_AND_PROCESS.md) — product modules, shared lifecycle, and canonical workflows.
4. [03_DATA_SECURITY.md](03_DATA_SECURITY.md) — tenant hierarchy, data contracts, RLS matrix, audit, and RPC rules.
5. [04_DESIGN_SYSTEM.md](04_DESIGN_SYSTEM.md) — corporate desktop visual tokens, layout, components, and accessibility.
6. [05_TEST_AND_DELIVERY.md](05_TEST_AND_DELIVERY.md) — test layers, release waves, rollout gates, and operations.
7. [06_WAVE2_SHARED_FOUNDATION_SPEC.md](06_WAVE2_SHARED_FOUNDATION_SPEC.md) — approved Wave 2 requirements, contracts, acceptance criteria, edge cases, and traceability.
8. [07_WAVE2_VERIFICATION.md](07_WAVE2_VERIFICATION.md) — stage-by-stage Wave 2 test, database, performance, Windows, visual, and residual-gate evidence.
9. [08_WAVE3_INTEGRATED_COMMERCE_FINANCE_SPEC.md](08_WAVE3_INTEGRATED_COMMERCE_FINANCE_SPEC.md) — approved Wave 3 requirements, operational and ledger contracts, acceptance criteria, edge cases, and traceability.
10. [17_WAVE3_STOCK_OPENING_CONTRACT.md](17_WAVE3_STOCK_OPENING_CONTRACT.md) — governed opening-stock commands, applied development evidence, and native integration contract.
11. [18_WAVE3_STOCK_OPENING_NATIVE_VERIFICATION.md](18_WAVE3_STOCK_OPENING_NATIVE_VERIFICATION.md) — native opening register/editor, approval and posting recovery, visual and Windows verification, and remaining authenticated acceptance.
12. [Controls after MFA](../verification/stock-opening/auth-controls-verification.md) — permission refresh, implemented Quick create navigation, regression tests and native runtime verification.
13. [19_WAREHOUSE_SETUP_CONTRACT.md](19_WAREHOUSE_SETUP_CONTRACT.md) — governed warehouse creation and editing for the stock-opening prerequisites.

14. [26_WAVE3_INVENTORY_TRANSFER_CONTRACT.md](26_WAVE3_INVENTORY_TRANSFER_CONTRACT.md) — candidate warehouse transfer, in-transit, reversal and dated-holdings contract.
15. [27_WAVE3_STOCK_COUNT_CONTRACT.md](27_WAVE3_STOCK_COUNT_CONTRACT.md) — cutoff counts, independent approval and atomic quantity/valuation adjustments.
16. [28_WAVE3_RESERVATION_RELEASE_CONTRACT.md](28_WAVE3_RESERVATION_RELEASE_CONTRACT.md) — governed allocation release, immutable reservation history and encrypted retry.
17. [29_WAVE3_RECEIPT_PROVENANCE_CONTRACT.md](29_WAVE3_RECEIPT_PROVENANCE_CONTRACT.md) — exact receipt quantity attribution, transfer/return trace and historical coverage boundaries.
18. [30_WAVE3_LANDED_VALUE_CONTRACT.md](30_WAVE3_LANDED_VALUE_CONTRACT.md) — exact receipt-based freight allocation, value-only posting and linked reversal.
19. [31_WAVE3_INVENTORY_VALUATION_REPORT_CONTRACT.md](31_WAVE3_INVENTORY_VALUATION_REPORT_CONTRACT.md) — immutable dated stock, lot and transit valuation with selected-control GL reconciliation and source evidence.
20. [32_WAVE3_MANUAL_JOURNAL_CONTRACT.md](32_WAVE3_MANUAL_JOURNAL_CONTRACT.md) — exact manual journal drafts, configured independent approval, posting, source evidence and linked reversals.

21. [40_WAVE4_WORKFORCE_AND_DELIVERY_SPEC.md](40_WAVE4_WORKFORCE_AND_DELIVERY_SPEC.md) — proposed Wave 4 scope, requirements, acceptance criteria, dependencies and delivery sequence.
22. [41_WAVE4_EMPLOYEE_FOUNDATION_CONTRACT.md](41_WAVE4_EMPLOYEE_FOUNDATION_CONTRACT.md) — proposed first vertical: employee directory, dated employment, scoped commands, native UI and recovery.
23. [42_WAVE4_PRIVATE_HR_ORGANIZATION_CALENDAR_CONTRACT.md](42_WAVE4_PRIVATE_HR_ORGANIZATION_CALENDAR_CONTRACT.md) — W4-02 private HR, organization, calendars, reviews and account-link security contract.

Current [Wave 4 delivery status](../development/wave4-status.md) distinguishes specification work from implementation and acceptance.

Additional Wave 3 finance candidate contracts:

- [33_WAVE3_AR_AP_CONTROL_RECONCILIATION_CONTRACT.md](33_WAVE3_AR_AP_CONTROL_RECONCILIATION_CONTRACT.md) — scoped immutable AR/AP controls and governed allocation corrections.
- [34_WAVE3_BANK_RECONCILIATION_CONTRACT.md](34_WAVE3_BANK_RECONCILIATION_CONTRACT.md) — exact imports, governed matching, adjustments and reversals.
- [35_WAVE3_PERIOD_FX_GOVERNANCE_CONTRACT.md](35_WAVE3_PERIOD_FX_GOVERNANCE_CONTRACT.md) — period close/reopen decisions and frozen FX valuation.
- [36_WAVE3_FINANCIAL_STATEMENTS_CONTRACT.md](36_WAVE3_FINANCIAL_STATEMENTS_CONTRACT.md) — posted statements, indirect cash flow, source drill and encrypted recovery.
- [37_WAVE3_BUDGET_VARIANCE_CONTRACT.md](37_WAVE3_BUDGET_VARIANCE_CONTRACT.md) — approved exact budget versions and immutable actual variance.
- [38_WAVE3_TAX_SUMMARY_CONTRACT.md](38_WAVE3_TAX_SUMMARY_CONTRACT.md) — posted tax review, complete control reconciliation, governed tax declarations and control movements.
- [39_WAVE3_GRNI_CONTROL_RECONCILIATION_CONTRACT.md](39_WAVE3_GRNI_CONTROL_RECONCILIATION_CONTRACT.md) — original-account receipt accrual, dated bill/return/reversal evidence and immutable GRNI source-to-GL differences.

The [remaining Wave 3 status](../development/remaining-wave3-status.md) separates
candidate development/test evidence from installed and native acceptance.

## Change control

- Approved requirements use `FR-*`, `NFR-*`, `AC-*`, and `EC-*` identifiers.
- A change that affects a public contract, permission rule, data model, or acceptance
  criterion must update this dossier before its implementation.
- Database changes are migration-only. Published migrations are immutable.
- Posted financial, inventory, payroll, and approval records are corrected by reversal,
  never by destructive mutation.
- No push, production deployment, billing activation, or real-data migration is authorized
  by this dossier.
