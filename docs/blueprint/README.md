# Jentra OS Blueprint Dossier

**Status:** Approved through Wave 2 implementation; Wave 3 specification approved and foundation implementation in progress
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

## Change control

- Approved requirements use `FR-*`, `NFR-*`, `AC-*`, and `EC-*` identifiers.
- A change that affects a public contract, permission rule, data model, or acceptance
  criterion must update this dossier before its implementation.
- Database changes are migration-only. Published migrations are immutable.
- Posted financial, inventory, payroll, and approval records are corrected by reversal,
  never by destructive mutation.
- No push, production deployment, billing activation, or real-data migration is authorized
  by this dossier.
