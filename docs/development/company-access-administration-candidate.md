# Company and staff administration candidate

28 October 2026. Implements the owner-requested general administration slice in
[contract 69](../blueprint/69_COMPANY_AND_ACCESS_ADMINISTRATION_CONTRACT.md).
The new desktop screen uses existing core identity, scope, permission,
subscription, command receipt, audit and outbox authority. It does not create a
parallel identity or billing model. User instructions are in the
[administration addendum](../user-guide/company-access-administration.md).

## Candidate boundary

`supabase/candidates/20261028130000_company_access_administration.sql` adds the
private `workspace_admin` helper schema and four named APIs: administration
list/command, own verified-email invitations and invitation acceptance. Creating
these definitions changes no existing function, grant, permission, assignment,
entitlement or migration-ledger row. It is not an applied migration.

Two additive triggers on `core.invitations` and `core.memberships` also close
legacy token issuance/acceptance bypasses. They protect verified email, current
inviter/delegation, scope, seat limits and inactive staff's retained roles while
preserving original function definitions and execution grants. Valid bootstrap
and permitted legacy acceptance are regression-tested. These are stricter
security checks for old clients; review their error/retry handling before rollout.

Administration requires current group-wide capability and recent MFA; delegated
roles remain a subset of current authority. Tenant/subscription locks protect
changes and plan limits. Owner/self access and system roles are protected. Invite
acceptance checks canonical verified email, active scope, current inviter
authority, expiry, membership status and seats. It cannot reactivate suspended
staff's retained roles. Original commands, audit records and outbox are reused;
the original invitation creator also retains its original audit/outbox behavior.

The desktop clears stale private data, validates exact confirmation receipts and
persists immutable actor/context-bound encrypted recovery before dispatch. A
missing backend fails closed. Unknown outcomes retain the original envelope;
only a definite precommit rejection or matching confirmation can release it.

## Rollback-safe checks

From the repository root:

```powershell
node --test supabase/candidates/tests/company_access_runner.test.mjs
node supabase/candidates/run-company-access-test.mjs --check
```

These check composition and refusal of hosted/linked targets; they do not run
PostgreSQL. With an already-running isolated local Supabase test stack only:

```powershell
node supabase/candidates/run-company-access-test.mjs --run-local
```

The pgTAP harness snapshots original definitions with a fixed deparse path and
their ACLs, protected setup rows and the migration ledger. All candidate
definitions, synthetic users, companies, roles, invitations, receipts and other
effects are inside `BEGIN` / `ROLLBACK`. The runner has no hosted/linked option.
CI has an additive step for this suite. Its new step has not yet run on GitHub.

The separate executable probe in
[the verification directory](../verification/company-access-20261028/)
runs actual candidate SQL, actual foundation migrations and command helpers in
in-memory PGlite PostgreSQL 18 with real pgcrypto/btree_gist. It uses a minimal
simulated Auth surface and the exact Wave 2 business-schema prefix before
Storage provider setup. It is not the Supabase stack or hosted RLS acceptance.
Its JSON report records source hashes and 73 successful checks, including legacy
API attacks and candidate/fixture rollback. The exact pgTAP harness also passed
31 assertions in this engine using the pinned official pgTAP 1.3.4 SQL. Auth and
an empty migration-ledger table are simulated; the Supabase stack and its new CI
step remain unexecuted. No migration was installed by these probes.

Run Flutter tests from each owning package/app directory so its native assets are
available. The new domain, platform, desktop controller and invitation tests
cover receipt binding, persistent encryption/restart, concurrent recovery seals,
actor/session/offline invalidation, definitive rejection and uncertain retry.
The widget fixtures use synthetic company details and global 200% text. Approved
goldens are retained. Current results and limits are in the verification record.

## Installation and recovery procedure to review

No installation is authorized or performed by this work. For a future approved
rollout, verify the target and migration history, take and restore-test the
database/private-file backup, run the isolated full candidate suite, and review
the exact candidate hash. Install through the normal migration process only
after that review; do not mark the candidate as already installed. Verify the
named authenticated API grants, group isolation and native application journey
with actual pilot accounts before wider invitation.

On an application-only rollback, retain the additive APIs, private security
helpers, both guard triggers and all core records. The previous application
retains its signatures and valid invitation flows with the stricter checks. For
an approved API-only rollback, stop new administration activity and remove only
the four new APIs; retain the guards and the helpers they require.

Removing the guards would reopen the legacy invitation vulnerabilities. A
complete database rollback therefore needs an approved replacement control or
closure of legacy issuance/acceptance and membership activation first. Only then
may the explicitly named `workspace_admin_invitation_guard` on
`core.invitations` and `workspace_admin_membership_activation_guard` on
`core.memberships` be removed, followed by private helpers in dependency order.
Never use `CASCADE`. Do not delete companies, memberships, assignments,
invitations, receipts, audit or outbox to undo a UI release. Already-confirmed
business/access changes need reviewed compensating commands, never ledger edits
or auth-account deletion. Independent lock contention and old-client retry
behavior still require the full staging rehearsal.

Company deletion/archive, owner transfer, accounting/time conversion, production
load, independent database contention and company/native acceptance remain
separate work. This runbook does not authorize sender deployment or activation.
