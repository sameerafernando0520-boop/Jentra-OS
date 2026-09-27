# Wave 3 governed financial dimensions — 2026-09-27

Development candidate evidence. Work continues on `main` at
`b51eec0dce3a73236f3460325394a4dc19e7a2ce`. The index is empty;
stock-opening acceptance source is unchanged. Existing Wave 3 work and concurrent
Wave 4 changes are preserved. No commit, push, migration installation, production
action, authentication change or application launch occurred.

Contract 46 and additive candidate `20260926010000` supply scoped cost-centre and
project-tag masters with immutable identities, optimistic versions, retirement
and immutable reasoned events. Management requires current entity/branch
`finance.dimensions.manage`; reading requires `finance.view`. Permission and MFA
are rechecked before replay. New masters are not seeded or assigned to roles.

Manual journals freeze the chosen master identity, label, scope and version.
Posting uses the existing exact journal engine; a private insertion trigger
derives ledger dimensions from the approved source. Existing posted rows are not
backfilled. Original retired identities survive linked reversals; material master
changes invalidate journal approval. Legacy descriptive labels remain unassigned.
Budgets accept repeated accounts only for disjoint dimension combinations. A null
dimension means all values. Submission and approval reject changed master basis;
variance retains exact source identities and excludes guessed historical actuals.
Named desktop pickers and `/finance/dimensions` use current capabilities, bounded
pages and encrypted recovery. Disconnect/MFA/scope changes reject stale reads.

| Check | Result |
|---|---:|
| Final-stack procurement/finance, strict rollback | 772/772 |
| Final-stack inventory, strict rollback | 105/105 |
| Final-stack receivables/reservations, strict rollback | 169/169 |
| Affected platform/finance/codec/recovery tests | 123 passed |
| Affected desktop/recovery/widget tests | 169 passed |
| Changed Wave 3 platform and desktop analyzers | No issues |
| New light/dark dimension, journal and budget renders | Six inspected at 200% text |
| Isolated Windows release compilation | Passed in 112.7 seconds; no launch |

The three `dimensions-*-release-candidate-20260927.json` files contain the passing
strict results. `build_wave3_finance_stack_candidate.ps1` places all 34 candidates
before the first synthetic fixture, so the new dimension guard is exercised by
the earlier procurement, inventory, manual-journal and receivables commands.
Foreign-key index coverage caught two partial-only dimension indexes; the final
candidate supplies full supporting indexes. Both zero-sum GRNI damage and large
source paging use explicitly synthetic source types, rather than impersonating
approved manual sources.

The final-stack builder preserves intentional historical compatibility fixtures:
earlier bills are seeded without the newly added tax provenance trigger, which is
enabled before prospective tax/GRNI/dimension tests. Source immutability, dimension,
journal and authorization guards remain enabled. Posting-only period fixtures
seed immutable period events; those seed events are excluded from genuine
hard-close assertions. The real clean-close fixture now configures GRNI as well.
Cash flow is supported, so the invalid-kind test uses an unsupported identifier.
All fixture setup disappears at rollback; it is not installed/native acceptance.

The large synthetic final-stack transaction explicitly disables JIT to avoid
compilation noise. A default-JIT diagnostic timed out in the oversized close
inventory-basis probe. The subsequent
[control-read-review-20260927.md](control-read-review-20260927.md) records the
additive repair and passing JIT-enabled fixture. Broader query-plan/performance
evidence remains open; synthetic suites do not establish p95 or load acceptance.
Diagnostic runs with non-strict `finish()` are not release evidence. The named
final files use strict `finish(true)` and end in `rollback;`.

Tests exercise exact values above binary integer precision, identity/basis
substitution, foreign scope, retirement, approval drift, overlapping wildcards,
late outbox rollback and immutable events. Desktop tests also cover identical
retry after encrypted restart, failed encrypted confirmation, optional read
failure, acknowledgement after disposal/disconnect and picker re-verification.
The 123/169 regression logs and final scoped analyzer logs are named
`dimensions-*-20260927.log`. Earlier test-fixture type failures remain diagnostic.

The isolated source copy is `build/w3dm27`, resolved from cached dependencies.
No environment, authentication or acceptance stores were copied. All 25 relevant
source hashes match the workspace and compiled copy in
`dimensions-build-source-hashes-20260927.json`. Candidate/query hashes are recorded
separately. Windows compilation is distinct from native installation or launch.

At 2026-09-26 19:10:36 UTC, development Supabase `xpdoufauvrbdmxgngetv` is
ACTIVE_HEALTHY, PostgreSQL 17.6.1.166, with 36 installed migrations through
`20260926082441_wave4_calendar_versions`. Dimension tables, API, journal columns
and the close-review table are absent outside rollback. The four installed shared
allocation/journal/residual/open-period MD5 values match the starting refresh.
Raw health, ledger, catalog and advisors are preserved alongside this review.
The existing advisor findings remain seven private Wave 4 RLS/no-policy entries,
the leaked-password warning, ten unindexed foreign keys and 295 unused indexes.
These remain review items; this continuation did not alter authentication
or concurrent Wave 4 schema.

Wave 3 remains incomplete. Wider landed allocation/correction, oversized count
partitioning/disposition, operational dashboard/list exports, attachment/source
navigation, cross-module recovery and default-runtime plan/load/contention proof
remain development work. Installation, authenticated native walkthrough,
Credential Manager process restart and owner signoff remain separate gates.
