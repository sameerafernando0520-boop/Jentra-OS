# Wave 3 posted journal evidence contract

Candidate development for FR-366, FR-375, FR-382 and FR-393; supports AC-316,
AC-317 and AC-320. Installation and authenticated native acceptance are separate.

## Public read contract

`api.posted_journal_evidence(tenant, entity, working_branch, journal_id,
after_line=0)` is an authenticated, STABLE, read-only RPC. Every page checks current
`finance.view` in the active working scope and the journal's actual branch before
returning a posted journal. Missing, draft, other-tenant and other-entity identities
return the same non-disclosing unavailable error. A retired source branch remains
readable only with current permission there; it cannot become the working branch.
No raw ledger table or private helper gains a client grant. Existing installed
ledger SELECT grants and RLS remain unchanged; this reader does not claim to
replace or strengthen that older direct-read contract.

Journals linked to immutable stock movements by command require stock-view and
cost-view permission in the working branch, journal branch and each movement
branch, including retired branches. More than 500 linked branches fails closed.
This read exposes ledger identities and amounts, not stock or attachment contents.

The envelope binds the requested tenant/entity/working branch and exact journal
identity. The header includes posting date, currencies, exact ten-place exchange
rate, source/document/command/request/correlation identities, period, immutable
creation identity, whole-journal exact debit/credit totals and line count. Account
and branch labels are explicitly current catalogue labels. Line identities,
source-line and party IDs, exact six-place transaction/base amounts and frozen
governed dimension snapshots come from the immutable posted ledger. Legacy rows
receive no invented dimension identity. The viewer does not infer document or
attachment access from a journal identity.

Pages contain at most 50 lines in unique line-number order, with a validated
integer cursor. The whole journal is limited to 10,000 lines and each response to
1 MiB; unsupported size, missing cursor or inconsistent ledger balance fails
without a partial response. Every nested query uses the same statement snapshot.

## Desktop behavior

`/finance/journal-evidence?tenant=…&entity=…&branch=…&journal=…` binds the originating
working context. A mismatched current context displays an unavailable destination
without a read; it never silently selects a tenant or mutates authentication.
The journal's actual branch may differ from the working branch, subject to server
permission checks. Source rows in control reconciliation, close review and posted
financial statements offer this link only with current finance capability and
verified online evidence. Unsupported source-document navigation remains separate.

The viewer keeps one bounded page in memory, offers previous/next/refresh, and
shows exact whole-journal balance plus immutable source identities. Disconnect,
permission/MFA loss, provider scope change, failed refresh and disposal clear
financial evidence. Late success or failure from an obsolete read cannot restore
or relabel it. This read-only viewer creates no command or local draft; existing
encrypted command recovery is preserved in the originating workspaces.

## Verification and compatibility boundary

The additive candidate changes no installed helper, journal posting engine,
immutable history, allocation, authentication or stock-opening acceptance source.
Final-stack synthetic tests must use strict `finish(true)` and end in `rollback;`.
Verify exact numbers, bounded paging, retired-branch access, command-linked stock
cost access, revoked access, unavailable identities and private-table grants.
Client tests cover protocol validation, scoped links, paging and stale read races;
inspect 200% light/dark renders and compile an isolated Windows copy without launch.
Candidate proof is distinct from installation, native authentication, real
contention/load, Credential Manager restart and owner signoff.
