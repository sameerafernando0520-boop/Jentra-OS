# Solo inventory valuation review — 2026-09-21

Reviewed contract 31, candidate SQL, original movement/journal/transfer consumers,
scope checks, gateway, desktop controller/screens, shared navigation and encrypted
recovery. No agents delegated. This is a slice review, not final AC-326 acceptance.

## Corrections made

- **P1 — Preserve unfinished inputs when viewing a saved report.** Selecting a report
  now leaves the current unsubmitted form intact. Restart and selection tests cover
  both unsent inputs and sealed uncertain generation requests.
- **P1 — Reject mismatched generation acknowledgments.** Identity, scope, date,
  selected accounts and exact summary equations are checked before completing the
  sealed request. Numeric financial payloads and malformed totals remain uncertain.
- **P2 — Make source filtering verifiable.** Difference rows now carry the same
  evidence key used by movement/journal filters. The SQL test compares actual matching
  source rows; it no longer succeeds by comparing two accidentally empty lists.
- **P2 — Fail invalid evidence section requests.** Null as well as unknown sections
  are rejected. Explicit permission rejection clears visible evidence and requires
  online revalidation before redisplay.
- **P2 — Preserve editor usability after loading failures.** Capability loading errors
  have a retry action; date input trims whitespace before command sealing.

Transfers reconcile as one source group across dispatch, completion and reversal,
including dated transit value. Report generation does not mutate inventory or GL.
Whole-entity reads require stock, cost and finance permission in every entity branch.
Private forced-RLS immutable evidence has explicit input, output and byte limits.

## Verification

- 318 combined procurement/valuation, 105 inventory and 126 AR/reservation rollback
  assertions pass with all eighteen candidates. They cover late outbox rollback,
  backdated posting stability, fresh regeneration, dated transit before/after receipt,
  source differences, pooled lot conservation, permissions, replay and immutability.
- 75 combined inventory UI/recovery/golden and 63 gateway/shared-store checks pass;
  valuation subsets are 11 and 9. Deterministic light/dark renders were inspected at
  200% text. Minimum desktop source navigation is exercised by a real widget tap.
- Isolated current-source Windows release compilation: 127.9 seconds. No executable
  launched or acceptance runtime replaced. Final catalog: 34 applied migrations,
  latest 20260911130900, no valuation candidate table or RPC.
- Focused app/platform analyzer completed with no issues after the final brace fix.
- The engineering schema analyzer could not parse schema-qualified DDL and returned
  “No tables found”; this is not counted as verification. Actual PostgreSQL rollback
  execution is the schema/function validation evidence.

## Residual gates

As-of is a posting-date cutoff with a frozen generation timestamp. Selected control
accounts are an explicit report basis. Lot value is pooled average allocation, not
independent lot costing. Reports above the documented bounds fail explicitly; large
asynchronous report generation, exact boundary stress, real multi-session contention,
query-load/p95, native authentication/Credential Manager restart and owner signoff are
unverified. No installation, production action or Git write.
