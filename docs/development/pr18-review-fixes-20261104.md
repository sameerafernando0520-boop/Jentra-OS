# PR 18 review and corrections — 4 November 2026

Reviewed `3a92c28c` against the PR base, including the overlapping company
administration in PR 17. Applied the requested Code Review, Review, UIAudit and
Build workflows; only reproducible findings were changed. No hosted migrations,
accounts, passwords, business records or deployments were changed.

## Confirmed findings and fixes

| Priority | Finding | Correction |
| --- | --- | --- |
| P1 | The installed Audit suite calls a private `assurance` function from an `authenticated` CASE expression. PostgreSQL resolves that name even when the branch is not selected, aborting pgTAP. | Use a transaction-local, test-owner `pg_temp` probe retaining the caller's JWT claims. Production schema/function permissions remain private. Regenerate the installed Audit fixture. |
| P2 | The Finance test's session-policy branch directly executes its private helper, which fails when that candidate is installed. | Use the same bounded test-owner probe pattern and update the three generated period fixtures. |
| P2 | Push CI scans all repository history and flags an Auth user UUID in an older document. The same identifier occurs in two historical copies of that commit. | Add only the two verified finding fingerprints to `.gitleaksignore`. All other source/history scanning remains enabled. |
| P2 | A revealed staff password remains visible when the application loses focus or submits the form. | Hide it on lifecycle transitions and submission, preserving the original value only for in-memory retries. |

The SQL fix is applied to the source fragments and generated fixtures. The new
`tools/auth/test_mfa_fixture_permissions_sql.mjs` executes their actual CASE
branches as `authenticated` for both legacy and session policies. It also proves
that direct private calls remain denied and that false verification is rejected.
Its business-command/MFA bodies and TAP formatting are small fixtures: this is
SQL permission/name-resolution evidence, not a full installed pgTAP run.

## Standards and specification review

The confirmed standards failures are the restricted-schema test boundary and
credential concealment. The fixes preserve scoped API access, immutable retries,
existing native controls, and semantic themes. No additional confirmed backend
authorization defect was found in staff reservation/completion, trusted identity
binding, password-free recovery or role-revocation replay checks.

Specification review confirms Admin-created credentials, multiple app-area roles,
and session MFA behavior remain intact. Existing or revoked accounts are not
adopted/restored and replay does not reset passwords. Review did not authorize
installing the candidate schema or deploying the Edge function.

## Native UI audit evidence

- Accessibility/adaptivity: staff role and recovery controls tested at 200% text
  in 1024×600 windows, in light and dark themes.
- Appearance: incumbent Jentra/Material presentation retained; existing dark
  Audit golden inspected. No redesign or new product claims.
- Platform behavior: native controls and scrolling retained; password concealment
  now follows focus/lifecycle changes and submission.
- Performance and assistive technology: device startup, frame performance and
  screen-reader acceptance were not measured, so no whole-product score is given.

## Validation

- Staff form and MFA suites: 22 tests passed, including concealment and large text.
- New restricted-role SQL regression: 14 assertions passed; independently reviewed.
- Session MFA and staff SQL regressions: 61 + 34 assertions passed.
- Company reauthorization regression: 14 assertions passed.
- Original CI evidence: both database jobs fail at the same Audit assertion;
  Flutter quality and Windows desktop jobs pass. Updated CI must verify the full
  installed suite after this commit.

PR 17 additionally corrects Android SDK bootstrap, a Sales formatting violation
and a Sales dark-theme contrast issue; these changes do not belong in PR 18.
