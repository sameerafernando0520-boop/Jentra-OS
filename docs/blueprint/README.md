# Jentra OS Blueprint Dossier

**Status:** Approved through Wave 2 implementation
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

## Change control

- Approved requirements use `FR-*`, `NFR-*`, `AC-*`, and `EC-*` identifiers.
- A change that affects a public contract, permission rule, data model, or acceptance
  criterion must update this dossier before its implementation.
- Database changes are migration-only. Published migrations are immutable.
- Posted financial, inventory, payroll, and approval records are corrected by reversal,
  never by destructive mutation.
- No push, production deployment, billing activation, or real-data migration is authorized
  by this dossier.
