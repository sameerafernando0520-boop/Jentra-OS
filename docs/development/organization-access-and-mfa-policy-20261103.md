# Organization access and sign-in verification

3 November 2026. This assessment describes the checked-out source. The hosted
database and installed applications were not changed by this task.

## How organization access worked before this change

| Requirement | Current implementation |
| --- | --- |
| First person becomes Admin | A signed-in person who **creates a business workspace** becomes its `tenant_owner` with the full permission set. Registering an account alone does not create an organization or grant access to someone else's organization. The visible role is called **Tenant owner**. |
| Admin controls the sections | The owner has the business permission set. Company & access supports companies, branches, custom roles, selected permissions and scoped assignments. Roles can combine tasks from existing application areas. Creating arbitrary new application modules is a development change. Plan limits and independent approval rules still apply. |
| Delegate to several people | Staff invitations and role assignments support several individuals with company/branch scopes. Each person has their own authenticated account. A staff/employee profile alone is not a login account. |
| Admin gives a username and password | Previously sign-in used an email address and password (or Google). Administrators invited a verified email and assigned access. The custom username/password flow described below is now implemented in source. |

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

## Admin-created staff accounts

The confirmed requirement uses existing app areas (Sales, Finance, Inventory and
others) as sections. It is implemented through the existing permission catalogue
and custom roles. A role can combine permissions from several sections; one
person can receive several roles. The workspace creator is its Admin/owner.

The Admin uses **Company & access -> Roles** to define the sections and tasks,
then **Staff -> Create staff account** to enter a full name, username, password
and one or more roles. Staff can then use **Username or work email** on the
sign-in screen and complete their own authenticator setup. Existing invitation,
role editing, suspension and revocation flows remain available.

Usernames are case-insensitive, globally unique, and use 3–40 letters, numbers,
underscores or hyphens. A business prefix helps avoid collisions. Profiles and
the staff register show the username rather than an internal Auth address.

`supabase/candidates/20261103130000_admin_staff_accounts.sql` provides private
reservation, identity-binding and atomic membership/role completion APIs. The
`workspace-staff` Edge function uses Supabase's server-only Auth Admin API for
creation. No service key is shipped in the app. Passwords never enter SQL,
audit receipts, command recovery, saved drafts or error messages.

Both reservation and completion check current administrator permissions and MFA
again after taking the organization lock. Every delegated role must belong to
the organization and remain within the Admin's authority; owner transfer is not
permitted through staff creation. Existing or suspended identities are not
silently adopted or restored. Completed retries reject changed role assignments.

An interrupted request saves only its scoped request identity and access choices
in the existing encrypted draft store. Reopening restores those choices and
requires password re-entry. Retries check an existing account's original password
and never reset it. Pending requests count toward seat limits and have a
per-Admin budget. Reservations older than 24 hours can be reclaimed only when
Auth never created an identity; existing Auth accounts are never deleted.

Username resolution is service-only. Invalid, missing and suspended usernames
use generic sign-in failures, with bounded per-name attempt counters covering
unknown names too. There is no global counter that a few requests can use to
disable every organization's login.

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
- `tools/auth/test_staff_accounts_sql.mjs`: 34 isolated PostgreSQL assertions,
  including multiple roles, MFA, cross-actor and owner-role denials, trusted Auth
  identity binding, immutable retries, revocation, pending budgets, expiry and
  login attempt limits. It runs the actual foundation permission helpers and
  candidate functions with synthetic schema/Auth fixtures.
- `supabase/functions/tests/workspace_staff.test.mjs`: 14 handler tests for
  authentication, reservation binding, credential handling, lost responses,
  retries and generic login failures. The Edge entry point passes Deno checking.
- Staff form tests cover multiple sections, uncertain retries, reopening without
  stored passwords, and wiping passwords after an authority change. Platform
  tests cover username/email sign-in, returned-token exchange with Auth, scoped
  creation and encrypted request recovery.
- The PostgreSQL runner supplies synthetic auth-claim adapters and a permission
  fixture. It tests the real SQL guards, not hosted JWT signing, actual session
  revocation or end-to-end RLS. Flutter tests use synthetic Auth HTTP responses.
- The final focused staff/session run passes all 10 tests, including starting
  another account after a completed request's delegation changes. The broader
  account/onboarding/access/profile run passes 82 tests. Audit access/settings
  passes 20 tests, with four snapshots updated for the revised MFA wording.
- Changed Dart files were analyzed; the remaining staff-dialog style finding was
  corrected and its final analyzer rerun reports no issues. The initial full
  workspace analysis also reported an unrelated existing style hint in
  `payroll_readiness_screen.dart:210`.
- The full platform run passes 1,309 tests and finds a constant-expression error
  in the new recovery test fixture. That fixture is corrected; both encrypted
  recovery tests pass on rerun. Username/Finance gateway coverage also passes
  all 11 focused tests.
- The full desktop run passes 2,388 tests and reports two payroll screenshot
  mismatches plus a warehouse test timeout. These are outside the edited account
  and MFA paths. The warehouse test passes alone in nine seconds; payroll
  snapshots are preserved. The complete desktop suite is therefore **not green**.
- SQL verification totals 95 isolated assertions (34 staff + 61 MFA), all passed.
  Handler and company-candidate runner verification passes all 19 Node tests.
  Deno checks the Edge entry point successfully. `git diff --check` is clean.

To repeat the isolated PostgreSQL test with an existing local PGlite install:

```powershell
$env:JENTRA_PGLITE_MODULE = 'C:\absolute\path\node_modules\@electric-sql\pglite\dist\index.js'
node tools/auth/test_session_mfa_policy.mjs
```

## Installation and remaining scope

The SQL files are reviewable **candidates**, not applied migrations. Existing applied
migrations were preserved. No accounts, credentials, roles, memberships or
entitlements were changed; no application was deployed.

For the coordinated backend installation, obtain the approved target and use the
returned migration versions. Install company administration, then the session
MFA policy, then staff accounts. The updated company candidate also honors the
session policy when installed later. Deploy `workspace-staff` with the server's
standard Supabase environment secrets, then publish the matching desktop build.
No extra user-created secret or credential is needed in the client.

Verify with real, distinct Admin and staff accounts: create the workspace ->
confirm Admin access -> define section roles -> create staff credentials ->
staff login -> authenticator -> assigned sections only -> refresh/reopen without
another code -> logout/login with a new code -> suspend/revoke and confirm denial.
Hosted installation, deployed-function behavior and authenticated native
acceptance are separate from the isolated evidence above and remain pending.
