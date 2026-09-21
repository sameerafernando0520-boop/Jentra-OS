# Solo receipt provenance review — 2026-09-20

Reviewed contract 29, the additive provenance candidate, trigger call sites in receipt,
delivery/return, transfer/count and opening primitives, scoped RPCs, gateway, native
viewer, navigation wiring and their tests. No agents were delegated. This is a slice
review, not the full AC-326 integration review or owner acceptance.

## Findings corrected

- **P2 — Preserve the established unavailable-serial rejection.** The new projection
  ran before the transfer command's serial disposition check and initially changed
  the public error for a repeated dispatch/missing serial. The trigger now preserves
  `TRANSFER_SERIAL_UNAVAILABLE`; both existing regression assertions pass.
- **P2 — Preserve receipt identity when a count restores a missing serial.** A
  generic positive adjustment cannot infer receipt identity, but a governed recount
  of the same serial can. It now restores the recorded negative count portion;
  ordinary count surpluses remain unknown. The tracked-count regression suite passes.
- **P2 — Bound holdings and avoid duplicate FK indexes.** Detail now fails explicitly
  above 100 warehouses rather than returning an unbounded list; FK index generation
  reuses existing nonpartial leading-column indexes. Individual movement attribution
  rejects above 1,000 consumed/restored portions atomically.

No further actionable defect was reproduced in the reviewed scope after correction.
Quantity attribution is an explicit oldest-recorded-cohort convention within each
untracked/lot pool, with exact serial identity. It does not alter moving-average
valuation and must not be presented as physical evidence for untracked stock.

## Verification

- 265 procurement/provenance rollback assertions (240 existing + 25 new), including
  partial returns, transit/completion/reversal, immutable history, 50-event paging,
  historical unknown stock, drift rollback and a real cross-branch transfer followed
  by removal of the synthetic actor's entity-wide grant.
- 105 inventory rollback assertions and 126 reservation/delivery/AR assertions with
  all sixteen candidates. Result artifacts are the three `receipt-provenance-*.json`
  files dated 20260920. Checked for `not ok`, not merely connector success.
- 53 combined inventory UI/recovery/golden checks; 41 gateway/shared encrypted-store
  checks. New trace subsets are 10 UI and 8 gateway checks.
- Focused app/platform analyzer clean. Light/dark 1024×1300 renders visually inspected
  at 200% text; history paging is reachable at 1024×720. These are widget renders.
- Isolated current-source Windows release build: **83.9 seconds**, no launch. Only
  Dart library source was copied to `build/w3`; no secrets/authentication/local DBs.
- Fresh live ledger remains 34 applied migrations through 20260911130900. Candidate
  provenance table and RPC are absent after rollback. No applied migration changed.

Initial fixture defects were corrected: mocked HTTP responses lacked their request,
the test font used the wrong family name, and the branch-denial fixture still had an
entity-wide grant. The first SQL passes also caught a product FK shape mismatch and
an ambiguous local variable; corrected before passing execution. The engineering
schema parser again reported `No tables found` for schema-qualified SQL. Its output
is not verification; actual PostgreSQL constraints and rollback suites are.

## Remaining gates

Landed-value amount allocation/posting/reversal, governed transfer-value adjustments,
full disposition and dated stock/GL reconciliation remain development work. The trace
viewer is read-only and cannot post a freight adjustment. Real contention, 1,000/1,001
portion and 100/101 warehouse boundary stress checks, p95/load, migration compatibility
and acceptance coordination, native authenticated walkthrough and owner signoff remain
open. Page reads are current committed reads, not a sealed concurrent snapshot.
