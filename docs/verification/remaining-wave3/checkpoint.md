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
  97-check evidence did not cover this corrected rule. It passed in the subsequent
  133-check suite and the 170-check suite recorded below.

## Supplier settlement continuation — 2026-09-15

- Checkout refresh found clean `main` at `b0aa757`; this session did not commit or
  stage anything. Dev project remains ACTIVE_HEALTHY with 34 applied migrations.
  Common scope/replay/finish-command/lifecycle helper fingerprints are unchanged.
- Ten candidate migrations remain unapplied. The settlement candidate now includes
  proposal submission, frozen amount/currency workflow, role/MFA and independent
  approval, recall/rejection/cancellation claim release, and atomic recorded payments.
  No bank transfer is executed. Payments retain immutable references and allocations.
- All 170 combined rollback assertions pass. New checks cover due-date eligibility,
  decimal-string validation, exclusive claims, blocked self-approval, MFA, partial
  payment residuals, replay, failed-numbering atomic rollback, immutable payment history,
  claim reacquisition after recall, AP privacy and authenticated direct-write denial.
  Dated statements exclude later payments/allocations and place a thirteen-day overdue
  item in a configured 8–14-day bucket. Sequential claim tests are not contention proof.
- All 43 procurement controller/widget/golden checks and 27 gateway/encrypted-storage
  regressions pass. The payment subset has nine checks, including controller restart
  with the identical sealed recording command/reference, branch isolation, exact
  amounts beyond binary integer precision and success with failed register refresh.
  The first storage invocation named two nonexistent files; corrected paths were rerun
  successfully. This was a command selection error, not a product failure.
- Payment editor light/dark 1024×1100 renders at 200% were visually inspected; all
  fields and actions fit and remain reachable. This is widget rendering evidence,
  not authenticated native acceptance or Credential Manager restart proof.
- Review tightened bank locking and frozen FX-rate comparison. Procurement entry
  navigation now lists every workspace the user may access. The payment reference
  prompt has its own field label and 140-character limit.
- Independent allocation commands/reversal, purchase returns/debit notes, complete
  FX/concurrency/performance checks, updated isolated build, installation and the
  later inventory/finance/cross-cutting requirements remain open. Final Wave 3 review
  and product/owner acceptance have not been completed.

## Allocation corrections and isolated build — 2026-09-15

- Eleven unapplied candidates pass 194 combined rollback assertions. Independent AP
  allocation and linked reasoned reversal preserve dated balances and immutable history.
  Source residual carrying values are allocated proportionally, including final cents.
  A 200.00 FX loss reverses exactly; a later cross-currency allocation posts a 5.00
  difference. Future posting and active proposal claims block conflicting corrections.
- All 85 existing delivery/receivables assertions pass with the candidate residual
  helper. This is compatibility regression evidence, not concurrent-session evidence.
- 29 platform/storage checks and 15 payment controller/recovery/golden checks pass.
  Both allocation operations retain the original sealed RPC envelope after uncertain
  sends and controller restart. Statement and allocation renders at 1024x1300 and
  200% text were inspected; review fixed restored report filters and allocation title.
- An isolated Windows release build at `build/w3` passed in 184.1 seconds with payment
  allocation source included. The earlier longer isolation path failed MSB3501 in
  generated secure-storage plugin build state; the shorter independent path builds.
  No executable was launched, auth store copied, or acceptance executable replaced.
- Shared `finance.flow_residual` now excludes linked AP allocation reversals only as
  of their posting date. Persistent application still requires acceptance-overlap
  coordination and a fresh ledger/compatibility check. Purchase returns and subsequent
  Wave 3 requirements remain unfinished; no native acceptance or final signoff claimed.

## Purchase return/debit continuation — 2026-09-15

- Added contract 25 and unapplied candidate `20260915002000_procurement_purchase_returns`.
  One scoped receipt or bill supplies each return; source quantities and history stay
  immutable. Unbilled returns reverse GRNI; billed returns reverse frozen net/tax and
  create a negative AP item for the existing allocation workspace. Stock issues use
  pre-issue moving-average cost, original lot/serial identity and matched frozen units.
- All 240 combined procurement rollback assertions pass with twelve candidates.
  Coverage includes partial/final cent rounding, exact base units, over-return and
  duplicate serial denial, expired-lot supplier disposition, reservation protection,
  immutable history, MFA/scope denial, source-picker eligibility and later bill matching.
  A failure after stock and journal construction leaves stock, carrying value and
  journal count unchanged. These are sequential assertions, not real contention proof.
- Native `/procurement/returns` includes bill/receipt source selection, remaining
  quantities, lot/serial choice, reason/reference, exact advisory amount preview,
  encrypted local drafts, identical uncertain retries and posted source evidence.
  The full selected procurement UI/recovery suite passes 56 checks. Seven return
  checks include scope isolation, restart retry and offline navigation persistence.
  Light/dark 1024x1300 renders at 200% were reviewed; preview is LKR 16.67 for the
  synthetic 0.15-carton return. Widget proof does not establish native acceptance.
- Twelve domain checks pass, including 200 partial returns of a value above binary
  integer precision and preservation of separate net/tax half-cent rounding. Thirty-one
  gateway and encrypted-storage regressions pass. Initial gateway test setup errors
  (helper declaration order, incomplete mocked command receipt and two misnamed test
  paths) were corrected before this passing run.
- Solo slice review fixed the prelock query alias, active conversion/base-currency
  guards, amount preview and button wording. A redundant moving-average cost field
  was removed from return responses; cost stays behind `inventory.cost.view` in the
  movement ledger. Two explicit assertions verify this boundary.
- One expanded database run suffered a connector transport failure. A subsequent
  read confirmed the unchanged 34-migration ledger; the full rollback suite then passed.
  The initial isolated return Windows build passed in 68 seconds. No native app was
  launched or authentication state copied. Latest preview build/analyzer follow below.
- Real multi-session contention, full source drill-through, scale/performance,
  Credential Manager restart, candidate installation and authenticated acceptance
  remain unverified. Inventory transfers/counts/adjustments, remaining finance and
  cross-cutting requirements are still pending; this is not final Wave 3 completion.

Final slice checks: all 85 delivery/receivables assertions also pass with all twelve
candidates. The isolated exact-preview Windows build passed in 46.6 seconds. Source
and focused test analysis reports no issues after resolving three brace-style findings.
Both final amount-preview renders were inspected at 200% text scale. Source
diff checks are clean; `main` remains at `b0aa757` and no acceptance-owned paths were
changed. No staging, commit, migration application, production or auth action occurred.
