# Jentra Employee

Android/iPhone companion for Jentra OS. This first build implements employee account access, exact account-link onboarding, shared reviews and protected local leave drafts. The complete product blueprint remains in [EMPLOYEE_APP_BLUEPRINT.md](../../docs/blueprint/mobile-apps/EMPLOYEE_APP_BLUEPRINT.md).

The app reuses Jentra's supplied artwork, bundled fonts and semantic colors. Phone navigation is Home, My work, Leave, Pay and More. At enlarged text or in Sinhala/Tamil, secondary destinations remain available through More.

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
flutter build apk --debug --no-pub --dart-define-from-file=.env.employee-development.json
```

Native secure storage is required for authenticated operation. The development web host is an unconfigured visual review surface; it never substitutes plaintext browser storage for native employee storage. Representative phone renders use fixtures under `test/`, which the production entrypoint never imports.

Android debug application ID: `com.jentra.employee.dev`; the future release uses `com.jentra.employee` and requires separate signing. iOS Debug/Profile use `com.jentra.employee.dev`. Android uses a secure window, disables backup and cleartext traffic. iOS source includes a native app-switcher cover; compiling/signing and validating it require macOS/Xcode. Store distribution signing and physical-device acceptance are separate work.

HR must link an existing active account to the correct employee and provide the needed existing permissions. This app never creates an employee, grants a role or infers a match from an email address. The legacy pending-link API requires `people.view`; missing access is reported to HR rather than silently broadening the role.

## Verification boundaries

Automated tests and rendered previews verify this source. They do not prove an authenticated employee walkthrough on Android/iPhone, installed payroll behavior, background protection on every OS, push delivery or payroll-owner acceptance. See [employee build evidence](../../docs/verification/employee-app/progress-20261009.md) for executed commands, current results and remaining gates.
