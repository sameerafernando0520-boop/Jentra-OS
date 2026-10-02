# Synthetic payroll development checkpoint

Date: 2026-09-30. Development project: `xpdoufauvrbdmxgngetv`.

## Scope and current state

The W4-04 contract is `docs/blueprint/53_WAVE4_SYNTHETIC_PAYROLL_CONTRACT.md`.
The new source candidate is
`supabase/migrations/20260930070000_wave4_synthetic_payroll.sql`.
It remains **unapplied**. The refreshed development ledger has 37 migrations
through the specifically approved private HR installation `20260929224939`.
`people_payroll.runs` is absent in development. The synthetic tenant is absent
and private worker readiness has zero rows. Existing acceptance data is preserved.

The candidate provides 15 API-only forced-RLS payroll tables, distinct payroll
capabilities and no existing plan/role grants. Exact fixed/hourly/ratio rules,
rounding, caps, scoped employee assignments and separate liability settings feed
immutable revisions. Preparation freezes employee/calendar/attendance/leave facts.
Posting rechecks those facts under deterministic locks and atomically writes
input seals, organization consumption, balanced journal lines, immutable payslips,
separate obligations, audit/outbox and minimal command receipts. Independent
approval is required. Original-basis reversal and exact partial settlements have
their own journal/effect history. Payslip and actor-bound export reads require
separate capabilities. No bank execution or statutory certification is provided.

The installed finance journal and open-period providers were inspected. Payroll
uses its own obligations, without fabricating supplier/customer transactions.
Installed AR controls are checked; the AP control guard checks the actual provider
only when present. The Wave 3 AP candidate is not installed to unblock payroll.

## Current focused verification

- The rollback-only builder and SQL suite pass **72 assertions**. Checks include
  exact rounding, RLS/grants, config, source changes/repreparation, independent
  approval, named attendance consumption, transactional late failure, posting
  attribution, immutable payslips, replay, permission/MFA revocation, settlement
  overpayment/reversal and export actor binding. Constraints are forced before
  the final rollback. The candidate builder ends in `rollback;`.
- The domain suite passes **13 tests**: seven exact calculations and six repository
  contracts. Platform checks pass **19 tests**: 11 gateway and 8 encrypted recovery,
  including deep snapshots, forged receipts/immutable source pages, action-capability
  separation, fixed expiry and minimal receipt reconciliation.
- Native tests pass **20** in `C:\jw4-payroll-20260930-c`. They cover uncertainty,
  scope/access loss, expiry, confirmed writes followed by failed reads, independent
  approval, rule editing, self-only access, named pickers and responsive layouts.
  Light/dark workspace/editor previews were inspected at 200% text. Both densities
  and 1920-wide layouts passed. This uses test repositories, not a signed-in app.
- Focused domain/platform/native and shared-integration analyzers report no issues.
- The isolated Windows release build passed in **451.8 seconds**. AOT SHA-256:
  `0275EB2C265B2D8B36EA5DC2532CA31DCE81A346946AC4DE8A0571D4E85FE9E6`;
  EXE SHA-256: `F424CE412FDC786F867D0B0E797700E57A52982C029EE0F554AC94805FFEB26A`.
  Source/build manifests are the sibling payroll JSON artifacts. No app was
  installed or launched. The later settings-comparison access guard and bounded
  settlement scan passed two regressions and are included in the refreshed clock/
  payroll build, which passed in 91.3 seconds with AOT SHA-256
  `79231DD66508DB7D37B016BA2ACC506D2A06F7BB00A8FD178F2ECC6594DB131D`.
- The later original-basis correction domain engine passes five focused tests and
  analysis; the combined payroll domain run now passes **18**. It reproduces whole
  original-rule calculations before subtracting prior rounded/capped amounts,
  supports signed differences and immutable revision chains, and rejects stale/
  duplicate input seals. It is not yet integrated into the authoritative off-cycle
  database/native vertical and is not part of the current Windows artifact.

These are synthetic SQL role fixtures and client test harnesses. They are not
installed payroll, authenticated native acceptance, real contention/load,
Credential Manager restart or owner signoff. The earlier isolated People Windows
build predates payroll UI and is not payroll build evidence.

## Required work remaining

Implement linked
off-cycle corrections and project/service input adapters. Harden and test account
provider integration and bounded reads, then run fresh full client/native/build
and rollback suites before asking for this candidate's specific installation
approval. Auth, real contention/load and owner acceptance remain separate gates.
Wave 4 is not complete.
