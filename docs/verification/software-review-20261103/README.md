# Jentra OS local software review — 3–4 November 2026

Reviewed the clean checkout at `91c2237c` and repaired seven confirmed issues in
desktop authentication, company administration, Employee configuration, and the Sales interface.
The original repairs are now recorded in commits `0d36fd95`, `6d9c0b9d`,
`68ae7f0d`, and `c98d1626` in the shared checkout. This review did not deploy an app, install a
database candidate, or change hosted accounts or business data.

Completion continued on 4 November in the supplied
`C:\Users\sheha\.codex\worktrees\d01f\Jentra OS` worktree. That worktree already
contained an additional Employee configuration regression. It reproduced a
project/key mismatch and was addressed without removing the supplied test.

## Repairs

| Priority | Reproduction and impact | Result |
| --- | --- | --- |
| P1 | Start desktop authenticator setup, interrupt it, and reopen. The app hid the unfinished factor and reused its friendly name, blocking another setup attempt. | Existing unfinished desktop factors can be verified or explicitly removed. New setups use unique names. Removal rechecks the actor and rejects verified factors and unfinished factors not labeled as desktop setups. |
| P1 | A company-administration command authorizes before waiting for its tenant lock. Authority can be revoked while it waits. | The SQL candidate repeats the same permission, membership, MFA, and tenant checks after the lock and before replay or mutation. |
| P2 | An authenticator lookup fails. The desktop treated the failure as an empty factor list and offered new enrollment. | A sanitized error and explicit retry replace enrollment until loading succeeds. Immediate retry failures are handled before the next widget frame. |
| P1 | Open live Sales at 768×360 or 1024×360 with 200% text. Its four-destination rail overflows vertically by 24 pixels. | The existing navigation rail scrolls; every destination remains reachable. |
| P2 | Open Sales sign-in at 1050×800 with 140% or 149% text. The welcome panel overflows vertically by 606–874 pixels and horizontally by 26–47 pixels. | Split-view eligibility accounts for text scaling. Constrained windows use the existing scrollable single-column form. The split view remains available at 1600×1200 with 140% text. |
| P2 | Open single-column Sales sign-in in dark mode. The default dark wordmark is almost invisible against the dark canvas. | The sign-in page selects the existing inverse brand asset in dark mode. |
| P2 | Configure Employee with a hosted Supabase URL and a legacy anonymous key naming a different project. Validation incorrectly accepts the pair. | The validator reuses the desktop startup policy to compare a supplied legacy project reference with the hosted URL. Valid publishable keys and legacy anonymous keys without a reference remain supported. |

The MFA changes are in the [desktop screen](../../../apps/jentra_desktop/lib/src/features/auth/mfa_required_screen.dart)
and [platform gateway](../../../packages/jentra_platform/lib/src/supabase_foundation_gateway.dart).
The authorization repair is in the [company-administration candidate](../../../supabase/candidates/20261028130000_company_access_administration.sql).
Sales changes are limited to its [sign-in layout](../../../apps/jentra_sales/lib/src/ui/login.dart)
and [navigation rail](../../../apps/jentra_sales/lib/src/ui/field_sales_workspace.dart).
The additional configuration repair is in the
[Employee validator](../../../apps/jentra_employee/lib/src/employee_configuration.dart).
Its shared validation API is exposed by
[runtime_configuration.dart](../../../packages/jentra_platform/lib/runtime_configuration.dart).

Supabase enrollment creates an unverified factor; the interrupted setup must be
handled separately from verified authenticators. See the official
[enrollment](https://supabase.com/docs/reference/dart/auth-mfa-enroll) and
[unenrollment](https://supabase.com/docs/reference/dart/auth-mfa-unenroll) references.
The implementation was also checked against the installed GoTrue client.

## Verification

| Check | Observed result | Evidence |
| --- | --- | --- |
| Domain package | 578 passed | [Log](logs/domain-tests.log) |
| Platform package | 1,311 passed | [Log](logs/platform-tests.log) |
| Design system | 10 passed, including light/dark contrast and action semantics | [Log](logs/design-system-tests.log) |
| Employee app, VM | 224 passed | [Log](logs/employee-tests.log) |
| Sales app | 72 passed after layout changes; final logo verification is recorded separately | [Log](logs/sales-tests.log) |
| Final Sales logo/layout verification | 17 permanent widget/layout tests and one screenshot capture passed | [Log](logs/sales-logo-final.log) |
| Full desktop suite | 2,396 passed; two existing Payroll screenshot references were stale | [Initial run](logs/desktop-full-initial.log) |
| Final Payroll and MFA suites | 42 passed, without screenshot-update mode | [Final run](logs/desktop-final.log) |
| Desktop MFA alone | 13 passed, including recovery at 200% text in both themes | [Log](logs/mfa-final.log) |
| Edge handlers and field-sales mail worker | 92 passed | [Log](logs/edge-tests.log) |
| Company reauthorization regression | 14 isolated PostgreSQL assertions passed | [Red](logs/company-reauthorization-red.log), [green](logs/company-reauthorization-green.log) |
| Windows release build | Passed with Flutter 3.47.5 / Dart 3.13.4 | [Log](logs/windows-build.log) |
| Full source analysis, original checkout | No issues | [Log](logs/source-analysis.log) |
| Full source formatting, original checkout | 969 files, zero changes | [Log](logs/format.log) |

The four initial [MFA regressions](../../../apps/jentra_desktop/test/auth_session_policy_test.dart)
failed before the behavioral fixes. The four original
[Sales layout regressions](../../../apps/jentra_sales/test/sales_layout_regressions_test.dart)
also failed before repair; the final suite adds an explicit split-layout check.
The [SQL regression runner](../../../tools/auth/test_company_access_reauthorization_sql.mjs)
failed against the original command because an edit succeeded after authority
was removed.

The full desktop run's only failures were
`payroll_light_200.png` and `payroll_dark_200.png`: each differed by 7,939 pixels
(0.50%), confined to the existing “Statutory & bank review” toolbar button and
the adjacent buttons it shifts. The current Payroll screen already implements
this button. Both reference images were reviewed and refreshed; the complete
Payroll test file then passed without update mode. Other golden references were
left unchanged. An unrelated missing-braces analyzer diagnostic in the Payroll
readiness form was also corrected.

The 3 November Windows executable was produced under the original checkout at
`C:\Users\sheha\Desktop\Jentra OS\apps\jentra_desktop\build\windows\x64\runner\Release\jentra_desktop.exe`.
Its recorded SHA-256 at verification time was
`DCB1B54EAAB62B4D8F37CBD2EEADAE0315A27FA31335BCAA07A524A05F3C8758`.
This is a local default-configuration build, not a signed distribution or a
production acceptance result.

## UI evidence and limits

Rendered widget fixtures use bundled fonts and synthetic data. They cover
scaled sign-in in both themes and short-window navigation. The regression tests
exercise navigation and button reachability; screenshots alone do not establish
interactive correctness.

- [Sales sign-in, light](images/sales-login-scaled-light.png)
- [Sales sign-in, dark](images/sales-login-scaled-dark.png)
- [Short Sales window, light](images/sales-rail-landscape-light.png)
- [Short Sales window, dark](images/sales-rail-landscape-dark.png)

The technical UI review found existing semantic color tokens, native Material
controls, scrollable content, accessible action labels, and substantial large-text
coverage worth preserving. The fixes retain the incumbent brand and workflows.
No whole-product UI score is assigned: runtime performance, assistive-technology
use on devices, and all platform/window combinations were not measured.

The SQL runner uses local PGlite 0.5.12 with the actual foundation, command
helpers, and candidate. It changes real table-backed authority immediately after
successful preflight, then calls the unchanged command body. Its 14 assertions
cover revoked membership, removed delegation, suspended tenants, company edits,
staff revocation, receipt replay, normal success, and rollback. PGlite has one
session, so genuinely queued concurrent transactions remain untested. No hosted
Supabase installation or advisor run was performed.

To reproduce that isolated regression from the repository root:

```powershell
$env:JENTRA_PGLITE_MODULE = 'C:\Users\sheha\Desktop\Jentra OS\build\launch-validation-runtime\node_modules\@electric-sql\pglite\dist\index.js'
node tools/auth/test_company_access_reauthorization_sql.mjs
```

Actual account/device MFA acceptance, browser-only Employee storage tests, hosted
database behavior, release signing, and deployment acceptance are separate from
the local checks recorded here. The full desktop suite was not repeated after
refreshing the two references; its affected Payroll and MFA files were rerun.
The Windows build record predates the additional Employee-only configuration
repair and does not establish an Android or browser release for that change.

## Completion in the supplied worktree — 4 November

The locked dependencies were restored from the local cache using offline mode.
The original review logs and rendered fixtures were retained in this directory;
duplicate scratch logs and the temporary screenshot generator were removed.
The separate `sales-release-20261104` evidence directory was preserved.

The supplied Employee configuration test failed before the additional repair:
the mismatched key incorrectly returned `true`. It now uses the same hosted
project-reference rule as desktop startup. This is configuration validation;
Supabase still performs authoritative key verification.

The shared checkout received the original review commits and a concurrent Sales
release continuation during these checks. Those release changes were preserved.
Employee's final shared-validator refactor retained the public-key format guard;
its remaining missing-braces diagnostic was corrected. The focused configuration
tests and analysis were repeated for that final form.

| Completion check | Result | Evidence |
| --- | --- | --- |
| Supplied configuration regression, before fix | Failed as expected | [Log](logs/configuration-red-20261104.log) |
| Employee, full VM suite after configuration repair | 225 passed | [Log](logs/employee-completion-20261104.log) |
| Final shared Employee validator | 4 configuration tests passed | [Log](logs/employee-config-final-20261104.log) |
| Payroll and MFA, current worktree | 42 passed | [Log](logs/desktop-completion-20261104.log) |
| Sales widget and layout regressions, current worktree | 17 passed | [Log](logs/sales-completion-20261104.log) |
| Company reauthorization, current worktree | 14 assertions passed | [Log](logs/company-reauthorization-completion-20261104.log) |
| Final Employee configuration analysis | No issues after correcting the remaining diagnostic | [Log](logs/employee-config-analysis-final-20261104.log) |
| Final changed-file formatting | 9 files, zero changes | [Log](logs/format-completion-final-20261104.log) |
