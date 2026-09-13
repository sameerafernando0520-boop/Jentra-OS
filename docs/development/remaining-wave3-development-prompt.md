Continue the remaining approved Jentra OS development. A separate session owns stock-opening acceptance and review. This session owns the remaining Wave 3 implementation and its development verification.

Workspace: C:\Users\sheha\Desktop\Jentra OS
Last observed branch: main
Last observed HEAD: 0ac613b
Development Supabase project: xpdoufauvrbdmxgngetv
These are orientation points, not guaranteed current state. Refresh before acting.

OBJECTIVE
Finish the unimplemented or partially implemented requirements in the approved Wave 3 Integrated Commerce and Finance specification, then conduct a thorough final review and correct the findings. Work through complete vertical slices: contracts, database, exact domain logic, authenticated gateway, native UI, recovery, tests and evidence. Do the work, rather than stopping at a roadmap, schema, mock screen or tests-only implementation.

The intended next independent slice is AC-309, requisition -> RFQ/supplier quotations -> purchase order. Verify that it is still missing before starting. Complete remaining approved work in dependency order; do not redo functionality already implemented.

SCOPE AND PRESERVATION
- Work solo. Do not create other tasks or spawn subagents.
- Preserve all existing tracked/untracked work. Do not reset, clean, stash, stage, commit, push or switch branches.
- Do not touch production, real business data, external payment execution, provider credentials, billing, statutory filing or code signing.
- Applied migrations are immutable. Use named additive development migrations and documented contract changes.
- Maintain the greenfield Windows-first architecture and approved Jentra artwork/design system.
- Use exact decimal strings, rational conversions and BigInt-based handling. No double/num coercion or floating-point totals for money, quantities, rates, budgets or matching tolerances.
- Read-only verification may use available database tools. Persistent business writes must use governed authenticated application commands; do not impersonate users or seed persistent fixtures with privileged SQL.
- Authentication/MFA remains user-managed. Never ask for credentials/codes, extract tokens or automate authentication.

CONCURRENT ACCEPTANCE SESSION
The other session owns the ACPT stock-opening scenario, journal-sequence setup, workflow/matrix, test@lh.com invitation/MFA, native posting/retry/reconciliation, acceptance evidence and owner signoff.

Do not modify its saved data, users, membership/roles, periods, document sequences, workflow configuration or test opening. Do not consume/reset ACPT sequence numbers or reuse ACPT identifiers for development fixtures. Do not close/relaunch its running app, change its session or rebuild over its executable.

Treat these as acceptance-owned unless a concrete shared dependency is coordinated:
- apps/jentra_desktop/lib/src/features/stock_opening/
- apps/jentra_desktop/lib/src/features/tenant/stock_opening_access.dart
- packages/jentra_platform/lib/src/stock_opening_access_gateway.dart
- Corresponding stock-opening/access tests and applied migrations
- docs/verification/stock-opening/

At the last refresh, uncommitted invitation feedback changes existed in stock_opening_access.dart, its gateway/tests and acceptance documents. Do not overwrite them. Shared router/provider/export/setup files may also change: reread their current content before each focused edit and inspect the diff afterward.

Prefer new module-owned files and minimal additive wiring. Use separate verification outputs under docs/verification/remaining-wave3/ and separate build artifacts. If an isolated source copy is needed for builds, include necessary current uncommitted source; a HEAD-only copy/worktree may omit active fixes. Preserve the original checkout and never copy authentication stores.

The acceptance session shares the development database. Prepare migrations, review compatibility and run isolated/rollback-only checks without modifying its persistent scenario. Serialize shared database migration application and any changes to common posting helpers with active acceptance testing. If an overlap cannot be avoided, state the exact dependency and continue all independent implementation first. Do not ask repeated general permission questions.

READ AND AUDIT FIRST
Read repository instructions and:
- docs/blueprint/README.md
- docs/blueprint/00_PRODUCT_SPEC.md
- docs/blueprint/01_ARCHITECTURE.md
- docs/blueprint/02_DOMAIN_AND_PROCESS.md
- docs/blueprint/03_DATA_SECURITY.md
- docs/blueprint/04_DESIGN_SYSTEM.md
- docs/blueprint/05_TEST_AND_DELIVERY.md
- docs/blueprint/06_WAVE2_SHARED_FOUNDATION_SPEC.md
- docs/blueprint/08_WAVE3_INTEGRATED_COMMERCE_FINANCE_SPEC.md
- Relevant AC-302 through AC-308 implementation/verification documents
- docs/blueprint/16_WAVE3_NATIVE_RECOVERY_VERIFICATION.md
- docs/blueprint/17_WAVE3_STOCK_OPENING_CONTRACT.md
- Read the latest stock-opening checkpoint only to understand protected integration boundaries; do not take over its walkthrough.

Inspect current source, migrations, named RPCs, routes and tests. Refresh git state and development health, ledger, relevant definitions and advisors before database work. Do not infer missing implementation solely from old notes or infer completion from a foundation table or placeholder route.

Create docs/development/remaining-wave3-status.md with a requirement/AC matrix:
implemented and verified / partial / missing / acceptance-owned / external gate.
For each item, record concrete source/evidence, dependencies and next action. Keep it updated while implementing. This short audit is the start of implementation, not the final deliverable.

IMPLEMENTATION ORDER
1. AC-309 / FR-335–FR-339: requisitions, approval, RFQs, invited suppliers and comparable quotations, selection rationale, purchase orders, source-line traceability and material-change revisions/reapproval. Recording an RFQ invitation does not authorize sending external emails.
2. AC-310 / FR-340–FR-341: accepted/rejected/partial goods receipts, lot/serial/unit validation, remaining quantities, controlled tolerances and reversals, atomic stock and goods-received-not-invoiced journals.
3. AC-311 / FR-342–FR-345: supplier bills, supplier-reference uniqueness, three-way matching, exact tolerances and accountable exception approvals, atomic payable/tax/accrual posting without double-counting received stock value.
4. AC-312 / FR-346–FR-349: payment proposals and approval, recorded supplier payments and allocations, purchase returns/debit notes, dated supplier statements and AP aging. No external transfer of funds.
5. AC-313–AC-315 / FR-350–FR-361: complete only remaining inventory gaps—product-specific rational units, reproducible on-hand/reserved/available balances, lot/serial history and expiry, moving weighted average, transfers/in-transit, counts/variance approval, landed-value adjustments, reservation release and valuation-to-GL reconciliation. Reuse existing opening, delivery and costing foundations.
6. AC-316–AC-320 / FR-362–FR-382: remaining finance workspace—manual journals/approval/reversals, source drill-through, AR/AP control reconciliation and allocation reversal, cash/bank setup, bounded statement import, reversible bank matching, realized/unrealized FX, soft/hard period control and governed MFA reopen, trial balance/P&L/balance sheet/indirect cash flow, tax summaries, approved budgets and exact variance/lineage.
7. AC-321–AC-325: complete cross-cutting work in the new modules and close verified remaining gaps—native states/forms, keyboard/accessibility, encrypted drafts and restart recovery, conflict/scope/capability safety, pagination, dashboards, exact bounded exports, private attachments, notifications/deep links, failure handling, contention, scale and redacted observability.
8. AC-326: assemble and run the applicable full Wave 3 development verification and final integration review. Do not relabel the other session's pending authenticated acceptance as passed.

Adjust the sequence only for actual dependencies, documenting why. Integrate shared stock/journal primitives as needed before consumers; avoid duplicate business logic or a second accounting engine.

ENGINEERING CONTRACT
- Update affected public contracts and traceability before implementation.
- Test critical permission, state, money, atomicity and concurrency behavior first.
- Reuse tenant/entity/branch scope, capability resolution, named api RPCs, security_invoker reads, command envelopes, receipts, audit, workflow/approval, outbox, reference pickers and encrypted draft infrastructure.
- Server-recalculate financial truth. Guard references, fiscal periods, mappings, expected versions, immutable request hashes/idempotency keys and segregation of duties.
- Stock, costing, journals, open items, source quantities, receipts, audit and outbox must commit together or roll back together.
- Posted history is immutable. Use linked reasoned reversals/corrections.
- Preserve exact values in JSON transport, display, imports/exports and report aggregation.
- Build usable native workspaces, not placeholder facades. Include loading/error/empty/populated states, permission-aware actions, visible lifecycle distinctions, safe retries and meaningful conflict recovery.

VERIFICATION AND FINAL REVIEW
For each slice, run meaningful domain/property, platform/gateway/storage, widget/golden and rollback-only database security/invariant tests. Test cross-tenant/scope denial, unauthorized direct writes, self-approval, stale versions, identical replay, changed-body key reuse, precision/rounding, invalid references, partial failure and atomic rollback.

Test real concurrent sessions for stock exhaustion, receipt/bill/payment allocation and reconciliation races where required. Record load/query-plan and p95 evidence against the specification's actual limits. Do not call sequential or duplicate-click tests concurrency evidence.

Run formatting/analyzer, appropriate regressions and Windows release builds in isolation from the running acceptance app. Visually inspect new/changed renders in light/dark, required widths/densities and 200% text scale. Investigate every unexplained golden change.

Before applying a development migration, inspect the current ledger again, verify compatibility and transactional candidate tests, and resolve active acceptance overlap. After application, verify installed definitions/behavior and advisors. Record candidate-tested and applied status separately.

Finish with a solo review of requirement coverage, contracts, security, arithmetic, posting/reversals, approval/MFA, concurrency, durable recovery, UI/accessibility, performance, integration and migrations. Fix actionable defects, then rerun affected checks.

DELIVERABLES AND COMPLETION
Keep a living requirement matrix and per-slice verification evidence. Report:
- What functionality was completed and where.
- Tests/checks/builds/visual reviews actually performed.
- Migrations prepared versus applied.
- Integration risks, acceptance-owned checks and exact remaining external/manual gates.
- Final review findings and their resolution.

Continue beyond the first successful slice through the remaining approved Wave 3 development. Do not silently narrow the goal to AC-309 alone, stop because one test suite passed or call the entire product finished.

Waves 4–6 are later roadmap work: workforce/payroll/projects/service/assets; intelligence/control; and production hardening/release. They do not have the same approved detailed implementation contract here. List them as future phases with their next specification/approval step; do not silently implement them or treat them as completed.

If blocked, finish independent work and report the smallest concrete unblock needed. Final product acceptance remains subject to the separate acceptance session and explicit owner signoff.

Begin with the live gap audit, then implement the first missing AC-309 vertical slice.

