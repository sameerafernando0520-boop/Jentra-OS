# Jentra Employee 0.2.0 UI and feature upgrade

The requested upgrade replaces the welcome slogan with **“Your work. Your space.”**, introduces a floating navigation dock and adds useful employee features around the current supported services.

## Delivered changes

- Modern company sign-in: compact original Jentra branding, filled email/password controls, a clear primary action and account-access help. Existing account validation and private authentication remain in place.
- Floating Home/Leave/Activity/More navigation with selected-state styling, accessible touch targets and reduced-motion support. At enlarged text or in Sinhala/Tamil, Home/Activity/More keeps secondary services accessible through Home and More. Changing a destination starts its page independently of the previous page's scroll position.
- Focused home: employee/workplace identity, actual loaded review actions and consistent service shortcuts. Both themes use Jentra's supplied fonts, image assets and semantic colors.
- Activity: protected local leave drafts, uncertain command receipt checks and the employee's loaded shared reviews. Local drafts remain labeled **Not submitted to HR**; acknowledged reviews show receipt status. This is not official HR request history.
- Review search: objectives, comments and displayed periods of loaded published reviews; All/To read/Received/Closed filters, clearing search and newest-period sorting. Pagination remains available. Search does not send a receipt or query another employee.
- Leave range selection and an inclusive calendar-day summary using date-only UTC arithmetic. The count does not calculate working days, policy-charged days, available balance or payroll impact. The existing protected draft lease, validation, edit/delete and explicit save behavior remain intact.
- Guided HR help: account access, leave, pay, reviews and documents. It gives next steps and can open the local leave editor; it does not create a support case or contact HR automatically.
- New interface copy in English, Sinhala and Tamil. Employer-authored review content and draft text remain in their source language.

## Executed verification

| Check | Result | Evidence |
| --- | --- | --- |
| Complete app suite on build source | 99/99 passed | `tests-build-source.log` |
| Flutter analysis on build source | No issues found | `analyze-final.log` |
| New feature and locale workflows | 10/10 passed | `features-accessibility-verified.log` |
| Current-source phone renders | 13 passed, 360/390/430 widths, both themes, 200% text and keyboard inset | `previews/`, full suite log |
| Standalone HTML packaging | 13/13 PNGs decoded and matched to current renders; zero external assets | `preview-validation.json` |
| Preview interaction | Core filter shows 10 screens; All restores 13 | Local in-app browser observation |
| Android development APK | Build exit 0, Gradle 54.6 seconds | `android-build.log` |
| Android manifest and signature | Version 0.2.0/code 2; debug certificate and APK v2 signature verified | `apk-badging.log`, `apk-manifest.log`, `apk-signature.log` |
| Development web host | Build exit 0, 72.4 seconds; Wasm dry run succeeded | `web-build.log` |
| Source consistency | 327/327 source, asset and workspace files unchanged across final tests, analysis and builds | `source-before-build.json`, `source-after-build.json`, `source-comparison.json` |

The initial five feature tests compiled and failed for the missing requested behavior (`features-red.log`). Follow-up checks exposed a real 49-pixel Sinhala section-header overflow at 200% text. The header now stacks its action below the title at enlarged text. Both Sinhala and Tamil workflows reach Activity, review search, HR help and the leave range control without layout errors. Intermediate implementation/analyzer/test-helper failures are preserved in their earlier logs; only the final passing logs above represent delivery checks.

## Android artifact

`apps/jentra_employee/build/deliverables/Jentra-Employee-0.2.0-development.apk`

- Size: **175,402,071 bytes**.
- SHA-256: `5c4b0c3cdd081039db8f5af81129efd8c2106af257c327599b5a55fb9615a1f0`.
- Application ID: `com.jentra.employee.dev`; minimum API 24, target API 36, compile API 37.
- Backup/full backup and cleartext traffic remain disabled. Network permissions are present; camera, microphone and location permissions are absent.
- Development connection configuration contains the API URL and public publishable key. No live employee sign-in, employee write, migration, account/role creation, commit, push or device installation was performed by this upgrade.
- The 0.1.0 artifact and verification directory remain separate historical records.

## Product boundaries

Attendance, authoritative leave balances/submission, employee payslips, documents, HR cases and recipient notifications still require the employee-safe backend contracts described in [backend readiness](../backend-readiness-20261009.md). The dedicated server review projection remains a rollout gate; app-side filtering does not establish server-side projection readiness.

Tests, compilation and fixture previews verify this development source. Authenticated physical-device acceptance, iOS compilation/signing, screen-reader and translation-owner acceptance, production payroll behavior and release signing remain separate delivery gates.

## Source and web packaging

`source-before-build.json` and `source-after-build.json` confirm **327/327 files unchanged** and `current_source_match=true` across the final 99-test suite, analysis, Android build and web build. Source enumeration includes the app, reused shared-library source/assets and workspace manifests, while excluding client connection files and generated build/cache artifacts. Flutter 3.47.5/Dart 3.13.4 were used; SDK compilation jobs ran sequentially.

The development web host compiled successfully in 72.4 seconds. Its Wasm dry run succeeded; the delivered web host is the normal JavaScript build. A nonfatal Cupertino icon-font warning remains in the compiler log; the current employee UI uses Material icons. Browser authentication remains disabled and native protected storage is required for employee access. This build is not a browser employee sign-in acceptance result.

The upgrade is limited to the employee app and its documentation. The Git index and concurrent Wave 5 worker edits were preserved. A focused source walkthrough checked private route ownership, help callbacks, local-only draft behavior and review search over the controller's published own-review projection; this does not claim a new independent review or server projection approval.

## Review files

- [Version 0.2.0 UI preview](employee-app-preview-0.2.0.html) — original screenshots embedded; works without sibling assets. The canonical preview URL now presents the subsequent 0.2.1 icon update.
- [App setup and scope](../../../../apps/jentra_employee/README.md).
- [Original employee blueprint](../../../blueprint/mobile-apps/EMPLOYEE_APP_BLUEPRINT.md).
