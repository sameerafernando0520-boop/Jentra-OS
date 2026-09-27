# Posted journal evidence candidate review — 2026-09-28

Contract [48](../../blueprint/48_WAVE3_POSTED_JOURNAL_EVIDENCE_CONTRACT.md) adds
permission-scoped exact posted-journal drill-through from control reconciliation,
consolidated close review and financial statement journal rows. The route binds
the originating tenant/entity/working branch and refuses a mismatched context.
The API separately checks the actual journal branch, including historical inactive
branches, and current cost/view access for command-linked stock movement branches.
The viewer shows immutable journal/source/command identities, exact six-place
money, ten-place FX, whole-journal balance and frozen dimension attribution.
Account/branch labels are explicitly from the current catalogue. It exposes no
attachment body or inferred source-document permission.

All 36 ordered Wave 3 candidates precede synthetic fixtures. JIT is enabled and
strict `finish(true)` ends in `rollback;`: **801 finance/procurement, 105 inventory
and 169 receivables assertions pass (1,075 total)**. The 26 new assertions cover
exact FX/money, original dimension versions after retirement and reversal, legacy
unassigned history, unavailable IDs/entities, current/revoked scope, actual branch
permission, stock cost denial, bounded 102-line paging and unchanged RLS/direct
write restrictions. Raw final results are `journal-procurement-final-release-candidate-20260928.json`,
`journal-inventory-release-candidate-20260928.json` and
`journal-receivables-release-candidate-20260928.json`. The earlier 800-assertion
result is retained as an intermediate checkpoint. Builder/source/query SHA-256
files identify the reviewed candidate and exact executed transactions.

The 12 gateway tests validate the protocol, lossless amounts above JavaScript-safe
numeric precision, ten-place FX, branch-bound dimensions, row order, complete
balances/cursors and permission/MFA outcomes. Twelve desktop tests cover page
replacement, context-bound links, no-read mismatched scope, denial/offline clearing,
late success/disposal and obsolete denial after reconnect. Four full-scaffold
light/dark 1024×720 previews at 200% text were inspected, including scrolled journal
lines. No overflow was observed. These previews are automated rendering evidence;
keyboard/native acceptance remains separate.

The pre-slice full desktop and platform analyzers both passed after the earlier
automatic approval-review usage-limit failure cleared. The new gateway/test and
desktop feature/test analyzers and final full desktop/platform analyzers pass. Adjacent
regression passes **135 platform/storage and 181 desktop tests (316 total)**,
including existing allocation, close, export, dimension and encrypted retry flows.
The first desktop regression exposed two 201-pixel budget preview differences
caused by the current UTC date advancing. Visual comparison identified only that
date digit; the test fixture now pins its original Sep 26 cutoff without changing
the approved images. The final full regression passes without golden regeneration.

An isolated source-only copy at `build/w3je28` passes cached offline dependency
resolution and Windows release compilation in **309.8 seconds**. All **28 relevant
source hashes match** the compiled copy (`journal-build-source-hashes-20260928.json`).
No executable was launched or installed, and no environment, authentication,
Credential Manager or acceptance store was copied. The compile validates source
integration, not authenticated/native acceptance.

The 19:29:55 UTC Sep 27 post-test catalog reports 36 installed migrations through
`20260926082441`; the new journal API, dimension tables and read-plan index are
absent. All four installed shared finance MD5 fingerprints match the opening
refresh. Development is ACTIVE_HEALTHY on PostgreSQL 17.6.1.166. Current advisors
report seven private Wave 4 RLS/no-policy entries, the existing leaked-password
warning, ten unindexed foreign keys and 294 unused indexes. These are recorded
baseline review items; no authentication or concurrent Wave 4 change was made.

Repeated warm account-basis reads in the complete synthetic fixture take 20.377,
16.455 and 15.398 ms. They are not real-load, multi-session or p95 evidence.
See [compatibility/rollback review](journal-compatibility-rollback-20260928.md).
The checkout stays unstaged at `b51eec0dce3a73236f3460325394a4dc19e7a2ce`,
with an empty index and no stock-opening acceptance changes. All candidates remain
unapplied. Remaining source-document navigation, operational exports, inventory
extensions and separate installed/native/owner gates stay in the status register.
