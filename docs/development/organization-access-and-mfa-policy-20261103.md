# Organization access and sign-in verification

3 November 2026. This assessment describes the checked-out source. The hosted
database and installed applications were not changed by this task.

## How organization access currently works

| Requirement | Current implementation |
| --- | --- |
| First person becomes Admin | A signed-in person who **creates a business workspace** becomes its `tenant_owner` with the full permission set. Registering an account alone does not create an organization or grant access to someone else's organization. The visible role is called **Tenant owner**. |
| Admin controls the sections | The owner has the business permission set. Company & access supports companies, branches, custom roles, selected permissions and scoped assignments. Roles can combine tasks from existing application areas. Creating arbitrary new application modules is a development change. Plan limits and independent approval rules still apply. |
| Delegate to several people | Staff invitations and role assignments support several individuals with company/branch scopes. Each person has their own authenticated account. A staff/employee profile alone is not a login account. |
| Admin gives a username and password | **Different today:** sign-in uses an email address and password (or Google). The administrator invites a verified email and assigns access; the invitee uses their own account and accepts the invitation. There is no administrator-created custom username/password flow in the checked source. |

Company & access administration is supplied by the existing uninstalled candidate
`supabase/candidates/20261028130000_company_access_administration.sql`. Its UI and
tests in this checkout do not prove that it is installed in a particular backend.
The foundation already contains workspace ownership and invitation APIs.

Source references:

- `supabase/migrations/20260831193714_create_greenfield_foundation.sql`:
  `core.bootstrap_tenant_impl`, `core.create_invitation_impl`,
  `core.accept_invitation_impl`.
- `apps/jentra_desktop/lib/src/features/tenant/tenant_onboarding_screen.dart`.
- `apps/jentra_desktop/lib/src/features/tenant/workspace_admin_screen.dart`.
- `packages/jentra_platform/lib/src/supabase_foundation_gateway.dart`.

## Requested authenticator behavior

1. A new password/Google sign-in has to complete authenticator verification
   before entering the business workspace.
2. Navigation, ordinary operations and token refresh reuse that verification.
3. Reopening Jentra with the same saved, valid session reuses its verification.
4. Signing out removes the session. The next sign-in needs a new code.
5. A revoked, expired or missing session must be authenticated again. Account or
   MFA changes that invalidate a session do not create a bypass.

Supabase already persists sessions and refreshes tokens. Jentra's shell already
checks the current session's AAL2 assurance. No separate saved boolean, TOTP
secret, generated code or locally elevated JWT is used to remember MFA.
See the upstream [session documentation](https://supabase.com/docs/guides/auth/sessions)
and [MFA documentation](https://supabase.com/docs/guides/auth/auth-mfa).

The inconsistency was in backend authorization: Finance period reopening,
Audit & Assurance actions and the company administration candidate required
second-factor evidence from the last **15 minutes**. That could refuse an
otherwise valid verified session and require another code during ordinary use.

## Implementation

`supabase/candidates/20261103120000_session_mfa_policy.sql` adds
`core.session_has_mfa()` and updates the existing Finance and Audit guards.
It also updates the company administration guard if that schema is installed.
The uninstalled company administration candidate recognizes the shared helper,
so installing company administration later also retains the session policy.
The helper requires a current actor, signed AAL2, a recognized second factor and
a valid non-future timestamp; it imposes no elapsed-time limit on verification.
The previous function signatures and error codes remain compatible. The
historical `recent_mfa` names do not impose a recency window after this candidate.

Existing permission checks, organization status, scoping, independent approvers
and mutation validation remain in place. The helper is executable by
`authenticated`; it grants no access to anonymous callers.

The authenticator screen explains the session policy in ordinary language,
prevents overlapping verification submissions, clears a successful code and
handles disposal during verification. Audit and Finance instructions no longer
ask for a code verified within 15 minutes.

## Verification

- `apps/jentra_desktop/test/auth_session_policy_test.dart`: password login,
  repeated refresh, saved-session recovery, sign-out and subsequent login,
  prompt behavior and code clearing.
- `tools/auth/test_session_mfa_policy.mjs`: 61 assertions executed in an isolated
  in-memory PostgreSQL runtime (PGlite 0.3.14). Historic guards reject an
  eight-hour-old verification; the new policy accepts verified sessions after
  eight hours or 30 days. Unverified sessions, malformed or missing evidence,
  future timestamps, missing permission and suspended organizations are refused.
  Candidate DDL is rolled back. Company administration installed before or after
  the policy is covered, as is the company schema being absent.
- The PostgreSQL runner supplies synthetic auth-claim adapters and a permission
  fixture. It tests the real SQL guards, not hosted JWT signing, actual session
  revocation or end-to-end RLS. Flutter tests use synthetic Auth HTTP responses.
- Broader analyzer and regression-suite results are recorded below when complete.

To repeat the isolated PostgreSQL test with an existing local PGlite install:

```powershell
$env:JENTRA_PGLITE_MODULE = 'C:\absolute\path\node_modules\@electric-sql\pglite\dist\index.js'
node tools/auth/test_session_mfa_policy.mjs
```

## Installation and remaining scope

The SQL is a reviewable **candidate**, not an applied migration. Existing applied
migrations were preserved. No accounts, credentials, roles, memberships or
entitlements were changed; no application was deployed.

For the coordinated backend installation, use a unique returned migration version
and apply this policy **after** the installed Finance/Audit schemas and any
company administration candidate when available. The updated company candidate
also supports being installed later. Publish the matching desktop build
after that backend installation, then verify with an actual signed-in account:
login -> code -> navigate -> refresh -> reopen -> sign out -> login -> code.

Administrator-created custom usernames/passwords would be a separate change to
account provisioning, sign-in and recovery. This task preserves email invitation
delegation while clarifying the difference.
