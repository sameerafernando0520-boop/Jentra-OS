# AC-319 period and FX candidate review — 2026-09-25

## Boundary and source

The development Supabase project `xpdoufauvrbdmxgngetv` was `ACTIVE_HEALTHY`
on PostgreSQL 17.6. Its ledger still listed 34 installed migrations through
`20260911130900_stock_opening_approver_setup`; neither AC-318 nor AC-319 was
installed. The security advisor retained the earlier leaked-password-protection
warning, and the performance advisor reported unused indexes. Authentication,
production and the stock-opening acceptance boundary were not changed.

The initial bank and period/FX source was committed by concurrent checkout
activity at `d99fe10` during this review. Subsequent AC-319 control-valuation,
test, gateway, status and contract corrections remain working-tree changes.
No staging, commit, push or migration application was performed in this review.
Concurrent Wave 4 files were left to their owner.

## Candidate verification

`supabase/tests/build_period_candidate.ps1` composes the prior candidates and
ends in `ROLLBACK`; it rejects a `COMMIT`. The AC-319 migration and focused
period tests are appended after the historical procurement assertions because
the historical suite writes period state directly, which governance now
deliberately prohibits. The focused tests therefore exercise the new behavior
after the candidate is created. Historical inventory and receivables suites
also execute in rollback transactions with the candidate at the end; their
historical assertions run before that insertion. This is a compatibility and
DDL check, not a claim of complete post-migration regression coverage.

Latest strict rollback outcomes: procurement/finance **445/445**, inventory
**105/105**, receivables **158/158**. Focused AC-319 assertions cover entity
permission, direct state-bypass denial, ordinary posting under soft/hard lock,
exact FX journal/base delta and zero transaction principal, immutable snapshot,
automatic prior-run reversal, explicit reversal, sealed replay, bounded reads,
blocked close evidence, a genuine configured clean hard close, recent-MFA
request with independent approval, immutable prior hard-close event and private
table access. The replacement `finance.flow_post_journal` body was normalized
against the installed definition: the only functional difference is the
source-aware period selector.

Client checks: **6/6** period/FX gateway tests pass, covering scoped reads,
bounded detail, exact decimal strings, receipt mismatch and recent-MFA mapping.
**8/8** desktop tests pass, covering encrypted draft restart with identical
sealed retry, current-version soft lock, offline evidence hiding, permission
revocation, view-only denial and light/dark 200% text goldens. I inspected
both period goldens and fixed a field-label spacing collision. The adjacent
bank and AR/AP control suites also pass together: **22/22** gateway and
**33/33** desktop checks. Two existing AR/AP control goldens were rebaselined
after a 0.08% border-only renderer difference was visually reviewed; no
control UI or business logic changed. Platform and desktop
`flutter analyze --no-pub` both reported no issues before the golden-only
client test change. These are synthetic client checks; they do not prove a
real Credential Manager restart or native click path.

The close check independently recomputes FX deltas from frozen source snapshots
and compares each account/command pair against AC-317 control differences.
Unrelated differences remain blockers. A prior active run is required again
at cutoff even when its original foreign items are now settled; the current
snapshot and latest active closing rate must match. A blocked close leaves
the period soft locked and saves exception evidence. A clean past-period
fixture reaches a real hard lock without a forged transition.

## Outstanding before acceptance

The migration is not installed. Real two-session contention and sustained
load/failure testing remain, especially simultaneous FX replacement, bank
matching against close, rate publication during close, and reopen races.
Full post-migration regression against all historical source commands is
not yet established. No authenticated desktop walkthrough, real Credential
Manager restart, installed contract check or owner signoff was performed.
AC-320 reporting/budgets and AC-321–326 cross-cutting acceptance remain open.
