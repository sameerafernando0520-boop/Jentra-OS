# Remaining Wave 3 verification checkpoint

2026-09-13. Work in progress; no feature or acceptance completion claim.

- Development project `xpdoufauvrbdmxgngetv` ACTIVE_HEALTHY; 34 applied migrations
  through `20260911130900`. Procurement schema remains empty after rollback checks.
- Nine procurement/product-unit/receipt/bill candidate migrations prepared, none applied. No persistent
  synthetic business records created. All test identities use the separate
  `remaining-wave3-procurement-20260913` namespace in a rolled-back transaction.
- Procurement database suite: 67/67 passed. Exact server totals, immutable replay,
  changed-body rejection, stale versions, numeric JSON denial, atomic failed saves,
  workflow/matrix fail-closed, sequence rollback, submitted edit denial, SOD, MFA,
  independent approval, immutable history, no GL effects, receipt counts, outsider
  RLS and direct-write denial. Sourcing adds invited supplier checks, partial response
  eligibility, governed pricing/FX, selection reasons and immutable response snapshots.
  PO checks cover source tracing, one order per selected RFQ, exact create replay,
  independent approval, immutable approved fields/history, reasoned revision and
  repeat approval after price change. This is candidate verification, not installation.
  Product-unit checks cover positive integer strings, exact base quantities,
  invented-ratio/precision denial, versioned immutable masters and non-base
  quantities carried through requisition→RFQ→quotation→PO. A master ratio edit
  does not rewrite the saved PO. `supabase/tests/build_procurement_candidate.ps1`
  now assembles the fresh rollback transaction without connecting to a database.
- Domain: 8 tests passed, including 500 exact arithmetic inputs and comparable supplier
  totals. The attempted
  preimplementation test process did not return before code was added; no proven
  red-phase result is claimed.
- Platform: scoped procurement HTTP transport, recovery and quotation/order draft regressions, 22/22
  passed from `packages/jentra_platform`. Running from workspace root failed due
  to unresolved SQLite native assets; package-root execution resolves that issue.
- Desktop: 4 requisition, 6 sourcing, 7 PO and 4 product-unit controller/widget checks passed. These
  cover uncertain exact replay, controller restart recovery, offline navigation save,
  request-body sanitization and confirmed-save/failed-refresh feedback. Light/dark
  renders at 200% text were inspected with real fonts (requisition 1024x900;
  quotation 1024x1100); sourcing save/discard controls are verified reachable.
  PO checks verify restart-safe lifecycle retry, conflict retention, SOD and offline
  save; product-unit checks verify sealed integer-string commands and validation.
  Light/dark PO and product-unit renders were also inspected at 1024x1100 and 200%.
- Review corrections so far: display-only nested fields removed from quotation
  command payloads; register refresh failure separated from confirmed save;
  selected supplier activity rechecked server-side; approved PO recall cannot bypass
  reasoned revision. Initial test fixture issues were corrected before recording passes.
- Isolated unconfigured Windows release compile under `build/remaining-wave3/checkout`
  passed in 126.4 seconds. The source copy excludes environment files and authentication
  stores. This build predates the latest direct requisition-to-PO UI addition; its
  updated controller recovery check passes. The executable was not launched.
- No native launch, authenticated procurement transaction, real
  multi-session concurrency test, full scale test or owner acceptance performed.
- Acceptance task `Continue Jentra stock opening` is not running at this refresh;
  its last completed turn awaits user connectivity feedback. Its native executable,
  dialog, source edits, invitations, roles, sequences, workflow and ACPT data were
  not altered. Minimal additive main/router wiring was reviewed separately.

Remaining: complete AC-309 vertical workflow and sourcing, all later missing matrix
items, applicable regression/security/performance/build checks, and final solo review.

## Receipt slice checkpoint

- Combined procurement/receipt rollback suite: 97 assertions passed before the latest
  tolerance-control extension. This includes tracked lot/serial receipts, duplicate serial
  atomic rollback, reserved-stock reversal denial, original journal reversal, all-rejected
  receipts and forced deferred journal/FK checks. Stale-version tests are sequential,
  not real concurrency evidence.
- Three exact-quantity domain tests passed, including 500 large rational inputs.
- Six receipt controller/widget checks passed, including sealed posting and reversal
  retries after controller restart, validation and offline save. Light/dark 1024x1100
  renders at 200% text were inspected; posting controls remain reachable by scrolling.
- Review corrected balance/valuation-before-tracking lock order, and replaced transaction
  timestamp consumption detection with immutable negative-movement quantity snapshots.
- Receipt build, authenticated walkthrough, genuine contention, tolerance approval,
  supplier bills and the remaining Wave 3 modules are not yet complete.

## Supplier bill and receipt continuation

- Combined candidate suite reached 132 passing rollback assertions, covering direct
  expense/input tax, case-insensitive supplier reference uniqueness, matching approval,
  edit invalidation, receipt overbilling denial, atomic AP and no duplicated stock value.
  Initial direct-tax fixture expectations were corrected: 250.25 × 18% rounds half-away
  from 45.045 to 45.05. A text-padding comparison bug in bill repricing was fixed.
- Supplier bill editor/recovery: six passing checks; both 1024x1100 light/dark renders at
  200% inspected. Received bill posting retries retain their operation after restart.
- Procurement and receipt regression: 28 UI/recovery checks and 24 platform/storage
  checks passed before adding the bill gateway check. Receipt allowance approval now
  has a restart test. Build evidence remains the earlier isolated source snapshot only.
- AP privacy review narrowed the existing AR residual helper and AR view to kind AR;
  new rollback assertions verify AR-only actors cannot read AP through direct RLS,
  a known-ID helper call or the AR register. This additive shared change is unapplied
  and requires compatibility review before installation.
- Final blueprint comparison found EC-320 drift handling was too permissive in the
  receipt candidate. A new guard retains the PO ratio while rejecting a changed active
  master; the new regression requires a governed restoration before receipt. Earlier
  97-check evidence did not cover this corrected rule. Fresh verification is pending.
