# Governed financial dimensions — FR-365 / FR-379–380 / AC-316 / AC-320

Unapplied additive development candidate. Financial cost centres and project tags
are scoped master identities for posting and budget attribution. A project tag
does not implement Wave 4 project delivery, time, resource or billing processes.

A master has UUID, tenant/entity, kind (`cost_centre` or `project`), immutable
code and optional branch, name, active/retired status, optimistic version and
reasoned immutable events. Creation/update requires current entity and working-
branch `finance.dimensions.manage`; reading requires `finance.view`. A branch
master is usable only in that branch; an entity master is usable in every entity
branch. Masters are never deleted. Retired masters remain in frozen history but
cannot enter a new posting/budget basis. All commands use existing hash/replay,
receipt/audit/outbox primitives and recheck permission before replay.

Manual journal lines can reference active governed identities. Saving freezes
their code, name, kind, scope and version. Existing descriptive labels retain
their historical meaning and acquire no invented identity. Submission/posting
revalidate governed versions; master retirement/renaming requires fresh approval.
A linked reversal preserves the original identity and labels even after retirement.

Nullable journal-line identity columns and a frozen dimension snapshot are filled
by a private insertion trigger from the approved manual source before posting.
No original ledger row is rewritten or backfilled. Existing exact posting,
open-item and journal engines remain unchanged. Automatic sources without governed
attribution remain unassigned; free-text labels do not become actual dimensions.

Budgets can repeat an account for disjoint cost-centre/project combinations.
A null dimension is an aggregate of all values. Overlapping combinations, including
an account-wide wildcard beside a targeted line, are rejected to prevent double
counting. Branch budgets accept entity or matching-branch masters; entity budgets
accept entity masters only. Saving freezes current master identities/versions;
submission and approval revalidate them. Approved versions and historical variance snapshots
remain immutable. Variance filters posted actuals by the selected identity and
retains frozen journal dimensions in its source evidence. Unassigned historical
actuals cannot be guessed into a governed identity.

The permission-aware desktop master workspace uses encrypted sealed recovery.
Journal and budget editors use named bounded pickers, preserve chosen identities,
and show frozen labels in read-only evidence. Scope/offline/MFA changes clear
server evidence and reject stale reads. Unknown raw IDs are never accepted as
picker choices. CSV/XLSX exports reuse the governed saved-report pipeline.

Compatibility review and rollback-tested synthetic fixtures precede any future
coordinated schema/client installation. Stock-opening acceptance and authentication
are untouched. Installation, native recovery, real concurrency/load and owner
signoff remain separate gates.
