# Inventory reference and value recovery review — 2026-10-01

The shared checkout remains at `f9cc342815e2446fb3f26204d5e65e03c1b2a140` with
concurrent Wave 4/5 work. This continuation changed contract 51 before correcting
the client behavior. No migration, authentication, acceptance executable or
Credential Manager operation was performed.

## Confirmed defects and corrections

Reference and serial dialogs now bind their originating controller and access
epoch even on the root navigator. Disconnect, disposal and definite permission,
MFA or authentication denial hide cached choices and reject late replies.
Reconnect requires a fresh selector. The three inventory read adapters preserve
known authentication failures and redact transport details without changing
command error precedence. Exact inputs and sealed pending command identities are
retained. The adapter run passes 35 tests; reference/access tests pass 51 cases,
including keyboard Escape/Enter and sixteen 200% renders.

Review then confirmed that saved count and disposition forms retained monetary
server previews after disconnect. Five new regression tests failed against that
behavior in [the red run](../../../build/remaining-wave3/inventory-value-recovery-red-20261001.log).
The shared recovery transform now excludes `grand_total`, `variance_value`,
`carrying_value`, posted valuation state, journal and movement evidence. Exact user
inputs, including `empty_unit_cost`, quantity, tracking identities, cutoff,
document/version and linked correction IDs remain unchanged. Live scoped replies
can still display exact permitted values. The client never recomputes a server
carrying value.

Old encrypted envelopes are sanitized for presentation. A pending envelope is
never rewritten or resealed. The existing atomic `confirm` persists the original
command acknowledgement with an input-only form even after disconnect/disposal.
An explicit permitted detail reload restores server evidence only for an unchanged
saved document. Dirty inputs and pending commands prevent that reload; disconnected
or replaced replies are ignored. No store schema or shared command protocol changed.

## Fresh verification and failures retained

- [Inventory recovery/workspace/access run](../../../build/remaining-wave3/inventory-value-recovery-final-20261001.log):
  91 passes, four existing stock-count golden failures; no functional failure.
- [Recovery rendering and keyboard run](../../../build/remaining-wave3/inventory-value-render-final-20261001.log):
  55 passes, including 23 exact recovery/access cases and 32 renders for both
  workspaces across 1024×720, 1440×900, 1920×1080 and 3840×2160, light/dark,
  compact/comfortable, 200% text and reduced-motion settings. Enter activates the
  permitted reload after reconnect; offline controls remain disabled.
- [Initial render harness failure](../../../build/remaining-wave3/inventory-value-render-failed-20261001.log):
  scrolling attempted to locate lazy-built controls too early, and the semantics
  handle was released too late. The corrected harness scrolls until the control
  exists and disposes semantics inside the test body. Product behavior was unchanged.
- [Full current desktop](../../../build/remaining-wave3/desktop-value-full-20261001.log):
  852 passes and 81 retained approved-golden failures. This includes concurrent
  Wave 4/5 tests and does not assign their implementation ownership to Wave 3.
- [Final desktop analyzer](../../../build/remaining-wave3/desktop-value-recovery-analyze-final-20261001.log):
  clean. Its prior run found four new missing-brace style findings, now corrected.
  The preceding inventory-only whole analyzer found concurrent asset-test imports;
  that work was corrected separately and was not edited by this continuation.
- [AP interaction checks](../../../build/remaining-wave3/ap-inventory-interaction-final-20261001.log):
  38 combined passes, including four exact proposal/dated statement/allocation
  correction/reversal UI cases. The first AP fixture used `return` where the public
  source kind is `credit`; the fixture correction and initial failure are retained.
- The preview startup test passes with an unconfigured backend and zero HTTP,
  secure-store or path-provider calls. This is a test-engine preview, not native
  cold launch, installed authentication or Credential Manager acceptance.

## Inspected rendered evidence

Eight fresh recovery PNGs were inspected: count 1024 dark compact, 1440 dark
comfortable, 1920 light compact and 3840 light comfortable; disposition 1024 light
compact, 1440 light comfortable, 1920 dark compact and 3840 dark comfortable.
The inputs, quantity precision and user-entered empty-stock cost remain legible;
server approval/carrying values are absent offline. The reload and local-save
controls fit or remain reachable by scrolling at the minimum size. A scrolled
viewport intentionally crops content above it. This is synthetic widget rendering;
complete native keyboard, screen-reader and owner visual acceptance remain open.

All 32 PNGs are under `build/remaining-wave3/visual/inventory_recovery_*.png`.
The sixteen reference-dialog PNGs are `inventory_access_*.png` in the same folder.
The full source fingerprint, render byte hashes and source/query hashes are linked
from the current checkpoint. Approved goldens were preserved.

## Database and external boundary

[Fresh ledger/catalogue/helper evidence](refresh-value-recovery-20261001.json)
records 37 installed migrations through private HR, 85 API functions and unchanged
finance helper fingerprints at 07:28:58 UTC. All 45 Wave 3 candidates remain
unapplied. The latest strict candidate suites pass 991 finance/procurement,
155 inventory and 182 AR assertions, each ending in `finish(true)` and rollback.
The separate [representative-plan run](representative-plans-final-20261001.json)
passes 1,005 assertions; these overlap the finance suite and must not be added to
1,328 as independent tests. It records eleven small-fixture plans and metadata.
Two private bank bases use a separately labelled privileged fixture role; their
authenticated direct SELECT remains denied. The reservation basis has zero rows.
Nested report plans, populated target-scale plans, real load/p95 and genuinely
independent authenticated sessions remain open.

The input-only client correction adds no migration dependency or database helper
change. The existing 45-candidate ordered manifest and eight-phase rollback plan
remain the installation proposal. Eight potential compatibility findings require
written owner acceptance under migration-architect. Installation, native checks,
target load/contention and owner signoff remain separate approvals. The required
80% changed-overall code coverage and existing approved-golden failures are open
development verification gates. Wave 3 is not fully complete.
