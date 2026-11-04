# PR 17 review and corrections — 4 November 2026

Reviewed `5b8141ab` against the PR base and the overlapping staff/session work
in PR 18 using the requested Code Review, Review, UIAudit and Build workflows.
Only confirmed findings were changed. No hosted schema, accounts, business data
or deployments were changed.

## Confirmed findings and fixes

| Priority | Finding | Correction |
| --- | --- | --- |
| P1 | The installed Audit pgTAP fixture resolves a private `assurance` helper from an `authenticated` CASE expression, even when that branch is not selected. | Evaluate it through a transaction-local test-owner `pg_temp` probe, retaining caller JWT claims. Regenerate the installed fixture and preserve private production permissions. |
| P1 | With the Sales candidate enabled, the companion rejects Admin-created usernames in the form and sends them to the email-only Auth endpoint. | Accept usernames or work email and use the shared staff authentication gateway. Username credentials go through `workspace-staff` and its refresh-token exchange; existing email authentication, cancellation and local logout remain supported. |
| P2 | The Finance fixture directly executes a private helper when session MFA is installed. | Add a bounded test-owner probe and update all three generated period fixtures. |
| P2 | Push CI flags an Auth user UUID in two historical copies of a document as an API key. | Ignore only the two verified finding fingerprints. Retain all other source and history scanning. |
| P2 | Android bootstrap requests the retired SDK `tools` package and fails before compilation. | Explicitly request `platform-tools`; retain the required Android platform and development build identity. |
| P2 | The Dart format gate rejects the Sales configuration condition. | Apply the standard formatter. |
| P2 | A revealed staff password stays visible after the app loses focus or the form submits. | Conceal it on lifecycle transitions and submission, preserving only the existing in-memory retry value. |
| P2 | The small Sales sign-in label has insufficient contrast in dark appearance. | Use the existing semantic primary color and verify at least 4.5:1 contrast in both themes. |

## Review boundaries

Independent standards and specification review covered staff reservation and
completion, trusted Auth identity binding, role revocation and retry behavior,
password-free recovery, restricted Sales access and independent recipient proof.
The fixes preserve those authorization boundaries, exact commercial values and
the separation of preview, company approval and customer acceptance.

The native UI audit retained the incumbent Jentra/Material design. Staff role and
recovery controls were exercised at 200% text in a 1024×600 window in both themes.
The Sales suite exercises phone, tablet and desktop layouts, enlarged text,
username/email form submission, password clearing and dark contrast. Device
startup/frame performance and screen-reader acceptance were not measured.

## Validation

- Full Sales suite: 82 tests passed. New username/email gateway and form
  regressions were first observed failing, then passed with the fix.
- Desktop staff form and session MFA: 22 tests passed.
- Repository format check: 947 Dart files checked with no remaining changes.
- Staged patch secret scan passed; the shared history exclusions also passed
  the complete history scan and both PR 18 CI secret-scan jobs.
- Restricted-role SQL fixture regression: 14 assertions passed for legacy and
  session policies, including denied direct private calls and false verification.
- Session MFA, staff accounts and company reauthorization: 61 + 34 + 14 isolated
  PostgreSQL assertions passed; fixture/candidate effects were rolled back.
- Server and candidate-runner tests: 19 passed.
- Locked offline dependency resolution passed. The HTTP test dependency uses the
  already locked version; the dependency lockfile is unchanged.
- The same shared fixes in PR 18 passed all ten GitHub CI checks, including full
  installed database tests and both Windows release builds.

The isolated PostgreSQL fixture test executes the actual source CASE expressions
and owner probes with minimal business-command/MFA bodies and TAP helpers; it is
not a substitute for full installed pgTAP. GitHub CI must verify this branch's
installed suite and Android/web builds. Hosted candidate installation, Edge
function deployment, genuine authenticator/device acceptance and company signoff
remain separate release gates.
