# Jentra Employee

Android/iPhone companion for Jentra OS. This first build implements employee account access, exact account-link onboarding, shared reviews and protected local leave drafts. The complete product blueprint remains in [EMPLOYEE_APP_BLUEPRINT.md](../../docs/blueprint/mobile-apps/EMPLOYEE_APP_BLUEPRINT.md).

The app reuses Jentra's supplied artwork, bundled fonts and semantic colors. Version 0.3.1 adds optimized Android packaging and removes unused photo codecs from the reachable app code. The personal navy identity header, grouped service rows, selected navigation capsules and Profile page introduced in 0.3.0 remain. At enlarged text or in Sinhala/Tamil, the dock becomes Home/Activity/More; Leave, Work and Pay remain reachable through the service screens.

## UI and feature upgrade

Version 0.3.0 adds real native profile photo selection while retaining the outlined HR help question-bubble icon introduced in 0.2.1.

- Sign-in uses “Your work. Your space.” with filled email/password controls and account-access help.
- Tap the identity header or More → My profile to choose, replace or remove your photo. Android uses the system photo selector (document selector on older supported devices); iPhone uses PHPicker on iOS 14+. No camera or library-wide access is requested. JPG/PNG photos are bounded to 8 MB and 20 megapixels; iPhone also converts system-supported still-image formats before returning a thumbnail.
- Photos are center-cropped to 256×256 JPEGs, stripped of source metadata and stored in the existing protected native store under the exact tenant/entity/branch/account/employee identity. They appear on Home and Profile, stay on this device, and are removed on sign-out. No cloud upload endpoint is installed.
- Gallery selection preserves only a bounded owner intent while the private navigator and displayed image are masked. On return the app verifies accepted employee access online before saving, then reopens Profile. Manual lock, sign-out, account/scope change or revoked access cancels the candidate. Photo bytes are evicted from the owned Flutter image provider on replacement or route disposal.
- Activity groups protected local leave drafts, uncertain command receipts and the employee's loaded shared reviews. It is not official HR request history.
- Search shared reviews by objective, comment or displayed period; filter All/To read/Received/Closed. Search is local to loaded published reviews and never sends an acknowledgement.
- Select a leave date range and see its inclusive calendar-day duration. The summary does not calculate policy-charged days, available balance or payroll impact.
- Guided HR help provides next steps for account access, leave, pay, reviews and documents. It does not create a support case or send a message.
- Light/dark appearance, English/Sinhala/Tamil and 200% text remain supported. New language copy requires the same owner language review as the first build.

## Supported first slice

- Sign in with an existing company Jentra account.
- Select an active company/entity/branch, resolve the accepted employee link, or review an exact HR-proposed link before accepting/rejecting it.
- Read employee-visible shared reviews and acknowledge receipt. Receipt does not mean agreement.
- Prepare, validate, edit and delete a local leave draft. Protected device storage, an employee/scope ownership check and a maximum 24-hour lease apply. Saving never submits leave or changes a balance.
- Change interface language (English/Sinhala/Tamil) and light/dark/device appearance.
- Hide private routes in the background; revalidate access on return. Sign out or lock the app.
- Persist a sealed command before sending; check its own receipt after an uncertain outcome and retry only the original request.

The development database's installed services were checked read-only on 2026-10-09. Attendance, leave balances/submission, employee payslips, employee document access, HR cases and recipient notifications still need the reviewed employee-safe backend contracts. Their screens explain availability and the next useful step. The app does not fall back to staff payroll/document permissions or show invented amounts.

Accounts also holding staff review permission are still limited by the app to their resolved employee and published review states. A dedicated server projection remains a subsequent hardening step; this first version uses the existing own-link and HR APIs with app-side state filtering.

## Configure and run

Use the workspace SDK (Flutter 3.47.5/Dart 3.13.4 in this build). From this directory:

```powershell
flutter pub get
flutter run --dart-define-from-file=.env.employee-development.json
```

Only the API URL and **public publishable key** belong in the client configuration. Copy `configuration.example.json` to the ignored `.env.employee-development.json` and fill the public connection fields. No service-role key or server secret is accepted. HTTPS is required.

```powershell
flutter test --no-pub --concurrency=1
flutter analyze --no-pub
# From the repository root, create small installable development APKs:
./scripts/employee/build_small_apks.ps1
```

## Small Android APKs

Use the optimized ARM64 APK for an ARM64 phone, or the ARMv7 APK for a 32-bit ARM phone. Each APK is a standalone installation containing one processor architecture. The build script uses release compilation, R8 code/resource shrinking, icon-font tree shaking and a separate directory for compiler debug symbols. English, Sinhala, Tamil, the supplied artwork and profile-photo support are retained. `-IncludeEmulator` also builds an x86_64 APK.

Outputs are under `build/deliverables/0.3.1-optimized-development/`, with exact sizes and SHA-256 values in `apk-manifest.json`. The script rejects debug runtime content, multiple architectures in one APK and files above a 40 MiB budget. See the [size reduction verification](../../docs/verification/employee-app/apk-size-20261013/result.md).

These optimized development builds use `com.jentra.employee.dev` and the existing local Android debug signer, preserving the development app's identity while disabling the debug runtime. Store releases still require a separate distribution signer. The script passes `--android-project-arg=jentraDevelopmentRelease=true` explicitly to this build and verifies the actual package identity and signature before copying an APK to deliverables. If the previous 0.3.0 APK exists, its signing certificate must also match.

The old universal debug APK is intended for developer debugging and remains a historical artifact. Its three engine architectures, unoptimized Dart kernel and validation libraries made it 169.53 MiB. [Flutter's Android build guidance](https://docs.flutter.dev/deployment/android#build-an-apk) describes per-architecture release APKs; [Flutter's app size guide](https://docs.flutter.dev/perf/app-size) explains debug overhead.

Native secure storage is required for authenticated operation. The development web host is an unconfigured visual review surface; it never substitutes plaintext browser storage for native employee storage. Representative phone renders use fixtures under `test/`, which the production entrypoint never imports.

Android debug application ID: `com.jentra.employee.dev`; the future release uses `com.jentra.employee` and requires separate signing. iOS Debug/Profile use `com.jentra.employee.dev`. Android uses a secure window, disables backup and cleartext traffic. iOS source includes a native app-switcher cover; compiling/signing and validating it require macOS/Xcode. Store distribution signing and physical-device acceptance are separate work.

HR must link an existing active account to the correct employee and provide the needed existing permissions. This app never creates an employee, grants a role or infers a match from an email address. The legacy pending-link API requires `people.view`; missing access is reported to HR rather than silently broadening the role.

## Verification boundaries

Automated tests and rendered previews verify this source. They do not prove an authenticated employee walkthrough or gallery operation on a physical Android/iPhone, installed payroll behavior, background protection on every OS, push delivery or payroll-owner acceptance. See the [profile and design update evidence](../../docs/verification/employee-app/profile-ui-20261009/result.md), [current standalone UI preview](../../docs/verification/employee-app/profile-ui-20261009/employee-app-preview.html), and [design rules](../../docs/verification/employee-app/profile-ui-20261009/design-system.md). The [icon update evidence](../../docs/verification/employee-app/hr-help-icon-20261009/result.md) remains a version 0.2.1 record, the [UI upgrade evidence](../../docs/verification/employee-app/ui-ux-20261009/result.md) remains a version 0.2.0 record, and the [first-build evidence](../../docs/verification/employee-app/progress-20261009.md) remains a version 0.1.0 record.
