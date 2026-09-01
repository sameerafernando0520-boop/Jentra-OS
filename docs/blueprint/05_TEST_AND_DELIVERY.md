# Test, Delivery, and Operations Blueprint

## Traceability

Every automated test names at least one requirement or acceptance criterion. A change to a
contract updates the spec and affected tests before implementation. Critical domain invariants
receive property tests in addition to examples.

## Test layers

| Layer | Purpose | Wave 1 evidence |
|---|---|---|
| Pure Dart unit | Money, context, errors, command envelopes, versions | Domain package tests |
| Widget | Shell, tokens, route state, auth/config states | Flutter widget tests |
| Golden | Theme, density, and target viewports | Versioned PNG baselines |
| Platform integration | Secure drafts, settings persistence, connectivity | Windows-compatible tests/fakes |
| Database | Constraints, RLS, grants, idempotency, audit | pgTAP SQL suite |
| End-to-end | Auth → tenant → shell → draft → restart | Local/dev Supabase test run |
| Security | Advisors, dependency/secret scanning, cross-tenant matrix | CI gates |
| Performance | Frame timings, p95 RPC/read latency, pagination | Profile/load evidence |

## Delivery waves

### Wave 0 — Blueprint

Exit: approved spec dossier, traceability rules, data/RLS/RPC design, design system, roadmap.

### Wave 1 — Foundation and shell

Exit: Windows shell, component catalogue, configuration/auth entry, tenant hierarchy/RBAC,
entitlements, audit/idempotency, encrypted drafts, tests, analyzer, Windows build, and visual QA.

### Wave 2 — Shared business foundation

Parties, products/UOM, currencies/rates, tax definitions, chart of accounts, fiscal periods,
numbering, workflows, approvals, files, notifications, import/export, reporting primitives.

### Wave 3 — Integrated commerce and finance

CRM, lead-to-cash, procure-to-pay, warehouse, weighted-average inventory, AR/AP, bank/cash,
reconciliation, atomic ledgers, statements, aged balances, valuation, budgets and variance.

### Wave 4 — Workforce and delivery

HR, attendance, leave, payroll, projects, time/expense, service/SLA/work orders, equipment,
maintenance, fixed assets and depreciation.

### Wave 5 — Intelligence and control

Cycle-time analytics, pipeline/forecast metrics, financial ratios, cash forecast, AI proposals
and approvals, webhooks/API, plans, trials, metering, operator dashboards.

### Wave 6 — Production hardening

Separate staging/production, migration rehearsal, restore drill, monitoring, performance and
accessibility certification, signed MSIX, controlled pilot, and general release.

## Database release gate

1. Create a named migration through the Supabase CLI.
2. Validate SQL locally or in an isolated environment when available.
3. Run pgTAP security and invariant tests.
4. Apply to the connected development project only.
5. Run a verification query and Supabase security/performance advisors.
6. Record migration ledger state and generated client contract evidence.

No dashboard-authored production DDL is permitted. A published migration is never rewritten.

## CI gates

- Dart/Flutter format check and analyzer with no warnings.
- Unit, widget, golden, and integration tests.
- SQL lint/parse where available plus pgTAP in a test database.
- Dependency and secret scan.
- Windows release build.
- Explicit artifact report separating code checks, package build, runtime launch, and visual QA.

## Operational signals

- Authentication failure and MFA-enforcement rates.
- RLS/permission denials and suspicious cross-tenant identifiers.
- Command latency, conflict, duplicate, and failure rates.
- Local sync backlog and oldest unsynchronized draft.
- Outbox retry/dead-letter depth.
- AI approvals, denials, token usage, and tool errors.
- Database advisor findings, slow queries, storage growth, backup/restore evidence.

## Rollout boundaries

- The current Supabase project is development and uses synthetic data only.
- Staging and production require separate authorization and projects.
- Google OAuth credentials, mail provider, production domains, billing, code-signing certificate,
  and real statutory rules are explicit external gates.
- A qualified Sri Lankan finance/payroll reviewer must approve statutory configurations before
  a real payroll or tax period is processed.
