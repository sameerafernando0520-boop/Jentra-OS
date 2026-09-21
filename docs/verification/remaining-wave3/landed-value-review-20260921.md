# Solo landed-value review — 2026-09-21

Reviewed contract 30, candidate `20260919185538_inventory_landed_value.sql`, existing
movement/valuation/journal and transfer/reversal call sites, scoped RPCs, gateway,
native workspace, encrypted command recovery and navigation. No agents delegated.
This is a slice review, not the final AC-326 integration review or owner acceptance.

## Corrections made

- **P1 — Do not acknowledge inconsistent financial results.** The gateway now checks
  receipt/document/reversal identity, journal identities, signed posting direction,
  exact inventory plus variance totals, warehouse totals and quantity conservation.
  BigInt-backed six-decimal comparisons preserve values beyond binary integer precision.
  Incomplete or inconsistent posting evidence retains the sealed uncertain request.
- **P1 — Do not classify missing valuation projections as consumed stock.** The
  allocation must account for the full provenance-held quantity. A missing warehouse
  valuation fails atomically instead of silently increasing consumed variance.
- **P2 — Clear visible cost information after permission rejection.** Register/reference
  rows and preview clear, the workspace hides retained form evidence, and online scope
  revalidation is required before redisplay. Encrypted work remains intact.
- **P2 — Keep stale previews invalid across restart.** A recorded version conflict
  restores no usable preview; only a fresh server preview resolves the conflict.
- **P2 — Require a preview before the posting dialog.** A local adjustment without an
  exact preview cannot open a confirmation containing missing amounts.

Cross-warehouse journals use distinct movement identities and retain the adjustment
identity on their lines. Linked corrections negate the exact original allocation;
intervening valuation versions reject. Original receipt reversal and frozen-cost
transfer reversal cannot strand active landed value. Posted history is immutable.

## Verification

- **294** combined procurement/provenance/landed rollback assertions, including exact
  partial-consumption rounding, late journal failure, replay, original receipt guards,
  transit rejection, two warehouses in different branches, branch-scope revocation,
  linked reversal, missing projection and subsequent valuation conflict.
- **105** inventory and **126** reservation/delivery/receivables rollback assertions
  pass with all seventeen candidates. Evidence is in `landed-value-*-20260921.json`.
  The receivables fixture uses `finish(true)`, which raises on failed pgTAP assertions.
- **64** combined inventory UI/recovery/golden checks pass. The landed subset is 11.
  **54** combined gateway/shared encrypted-store checks pass (13 new landed checks).
  They cover malformed success, exact decimals, paging bounds, signed reversal,
  actor identity and sealed recovery.
- Focused app/platform analyzer clean. Light/dark 1024×1800 widget renders reviewed
  at 200% text; posting remains reachable at 1024×720. This is not native acceptance.
- Isolated Windows release compilation completed; final timing is in the checkpoint.
  Only Dart library source copied to `build/w3`; no executable launched or auth copied.
- Fresh project ACTIVE_HEALTHY; 34 applied migrations through 20260911130900. Candidate
  table/RPC absent after rollback. Security advisor retains leaked-password protection
  warning and performance advisor reports 294 unused-index notices. No settings changed.

Initial fixture/setup issues were corrected before passing runs: deferred constraints
needed restoring after the preceding fixture, destination journal numbering needed a
synthetic branch sequence, the synthetic receipt movement kind needed an allowed value,
and a synchronous permission rejection needed a callback matcher. The new transfer
guard was tested with unrelated destination stock so the pre-existing empty-warehouse
value guard could not mask it. All privileged fixture changes remained rollback-only.

## Remaining development and acceptance

This bounded implementation reclassifies previously recorded freight expense for one
covered receipt line, using original base quantity as the explicit basis. It creates
no AP or payment. Multi-receipt/weight/value bases, in-transit value adjustment and
correction after later consumption remain open. Full dated stock valuation and
valuation-to-GL reconciliation, disposition, automatic expiry/retirement, finance
and cross-cutting work remain. No full FR-359, Wave 3, native or owner completion claim.

Real multi-session contention, p95/load/failure testing, 100/101 and 500/501 warehouse
boundary stress, migration compatibility/acceptance coordination and actual Credential
Manager restart remain unverified. Configuration mutation races require contention
verification alongside the shared journal engine. No migration installed or Git write.
