# Inventory continuation review — 2026-09-17

## Findings

No remaining actionable defect was reproduced in the reviewed transfer and initial
untracked-count changes after the corrections below. This is a solo review of these
two candidate verticals, not the final AC-326 review of all remaining Wave 3 work.

## Scope and corrections

Reviewed contracts 26–27, both inventory candidate migrations, exact quantity domain,
named gateways, controller recovery, screens and permission-aware main/router/navigation
wiring. Reused existing ledger, period, command receipt, approval and encrypted-draft
primitives. No stock-opening implementation, applied migration or acceptance evidence
was changed.

Corrections made during development/review:

- A completed transfer reversal compares cumulative immutable destination issues with
  its receipt snapshot, rather than transaction timestamps. Its own reversal command
  is excluded while checking multiple lines of the same product.
- Transfer events retain each operation's reason/reference and hide private consumption
  snapshots and carrying costs from ordinary command/read projections.
- Unsaved count edits cannot submit the older server document. First capture explicitly
  initializes the physical quantity to the server's locked baseline. Later saves cannot
  replace that baseline or its line identities.
- Confirmed posting remains distinguishable from a failed register refresh or subsequent
  local persistence failure. Sealed unknown results preserve the original operation,
  command identity and expected version across controller restart.
- Count corrections start a separately approved linked document with fresh line IDs and
  cutoff. Posted source history remains immutable.
- Removed the count-reason dialog's unmanaged text controller and resolved focused
  analyzer findings. The final brace-only correction does not change runtime behavior.

## Executed verification

- 81 inventory assertions in one rollback-only synthetic transaction.
- 240 procurement assertions with all twelve procurement candidates plus both inventory
  candidates; 85 delivery/receivables assertions with the same candidate set.
- 21 inventory desktop controller/widget/recovery/golden checks.
- 21 gateway/shared encrypted draft-store checks; 3 exact quantity domain checks.
- Focused desktop/platform analysis clean after the final controller lint correction.
- Transfer and count light/dark renders inspected at 200% text scale; controls tested
  at 1024×720. No native sign-in or application launch performed.
- Isolated `build/w3` Windows release compilation passed in 145.9 seconds. Source copy
  included only Dart library files from the current workspace; no environment, auth
  store or local database copied. The later brace-only lint correction was analyzed.

The new surplus test initially encountered the fixture's earlier `SET CONSTRAINTS ALL
IMMEDIATE` checkpoint. Restoring deferred mode before constructing the next journal
fixed the fixture. All constraints were checked again afterward; no accounting helper
or applied migration was changed to accommodate the test.

## Remaining development and acceptance

Lot/serial counts fail closed pending their identity-level extension. Landed-value
allocation, complete historical balances/reservations/valuation and GL reconciliation,
tracking/disposition, remaining finance and cross-cutting requirements remain open.
Large-register paging/load, actual multi-session contention/failure, real Credential
Manager restart, authenticated native use, candidate installation and owner signoff
are not proved by these checks. Fourteen candidates remain unapplied; installation
requires compatibility review and coordination with acceptance activity.

Fresh development health remains ACTIVE_HEALTHY with 34 migrations through
`20260911130900`. The existing security advisor warning is
[leaked-password protection disabled](https://supabase.com/docs/guides/auth/password-security#password-strength-and-leaked-password-protection);
296 performance notices concern unused indexes. Neither setting nor indexes were changed.
