# Jentra Employee first build implementation plan

> **For agentic workers:** Use the Superpowers implementation, test-first and review workflows. Execute the authorized build continuously; do not repeat the blueprint interview.

**Goal:** Build an Android/iPhone employee companion with real Jentra sign-in, exact employee linking, own shared reviews and encrypted local leave drafts.

**Architecture:** A separate Flutter app reuses Jentra's domain, platform contracts and design assets. An employee-only facade limits the available operations, a session controller clears private state when account/scope/lifecycle changes, and native secure storage holds session data and scoped drafts. Services which lack installed employee-safe contracts remain unavailable.

**Tech Stack:** Flutter 3.47.5 / Dart 3.13.4, Jentra packages, Supabase Flutter 2.17.2, flutter_secure_storage 11, uuid and intl from the existing workspace.

**Spec:** `docs/blueprint/mobile-apps/EMPLOYEE_APP_BLUEPRINT.md`, `SHARED_MOBILE_FOUNDATION.md`, `MOBILE_DESIGN_BRIEF.md`.

## Global constraints

- Android/iPhone companions; retain Jentra's original brand assets, colors and fonts.
- Phone navigation: Home · My work · Leave · Pay · More. Keep all destinations reachable at 200% text.
- Derive employee identity from the accepted account link and active membership, never email matching or a user-entered employee ID.
- No employee directory, broad payroll/document grants, administrator editors or private review history in the employee facade.
- No fabricated salary, balance, schedule, payment or submitted request.
- Own salary/documents stay unavailable until employee-safe installed contracts exist; do not fall back to staff APIs.
- Native secure storage for sessions and scoped drafts. Sensitive drafts expire within 24 hours, require online identity revalidation before restoration, and never auto-submit.
- Hide private content in the background; revalidate identity on foreground and discard stale in-flight results after an account/scope change.
- Preserve original command identity after an uncertain response; reconcile own receipt before another attempt.
- No database writes/installations, account/role creation, commits, pushes or changes to concurrent desktop/Wave 5 files in this build.
- Touch controls at least 48 logical pixels, both themes, keyboard-safe forms and English/Sinhala/Tamil navigation.

## Review focus

1. A response completes after sign-out or workspace switch: it must not repopulate the prior employee's private view.
2. A user also has staff review permission: draft/submitted and private history must remain absent from the mobile experience.
3. A write reaches the server but times out: preserve its exact identity and distinguish an unknown result from success.
4. Device storage fails or a restored draft belongs to another employee: do not silently fall back to plaintext or display another subject's draft.
5. Narrow phone, 200% text and visible keyboard: navigation and primary actions must remain reachable without overflow.

## Task 1: Native shell and employee facade

**Files:** Create `apps/jentra_employee/{android,ios,web,pubspec.yaml,lib/main.dart,lib/src/data/*,lib/src/employee_controller.dart}`; add only its workspace entry to root `pubspec.yaml`. Tests: `apps/jentra_employee/test/employee_controller_test.dart`, `employee_gateway_test.dart`, `secure_storage_test.dart`.

**Interfaces:** Employee session, workspace/linked identity, link proposals, shared review models; sign-in/sign-out, list/select workspace, resolve self, read reviews, accept/reject own link, acknowledge receipt and reconcile an uncertain command. Methods never accept arbitrary target employee IDs from the UI.

- [x] Generate Android/iOS and development web hosts without fetching new unrelated packages.
- [x] Write behavior tests for absent accepted links, cross-scope/stale responses, shared-only reviews, unknown-command receipts, secure scoped drafts and session clearing; observe expected failures.
- [x] Implement the facade and session controller using installed foundation/private HR contracts and secure storage.
- [x] Run the focused tests to green; inspect every failure rather than treating compile errors as behavioral red evidence.

## Task 2: Employee mobile experience

**Files:** Create `apps/jentra_employee/lib/src/ui/*`, `lib/src/employee_app.dart`, `lib/src/l10n/*` and `test/employee_app_test.dart`, `test/render_previews_test.dart`.

**Consumes:** Task 1 session/controller and safe employee models. **Produces:** An interactive sign-in, workspace/link onboarding, Home/My work/Leave/Pay/More shell, own profile, shared-review detail/acknowledgement, settings/security and local leave-draft flow.

- [x] Write failing widget tests for navigation, guarded link acceptance, honest unavailable states, review receipt acknowledgement, draft validation and private lifecycle masking.
- [x] Build phone layouts with Jentra's supplied design assets; avoid desktop tables/sidebar and fake operational cards.
- [x] Make language/theme controls work. Keep persisted preferences nonsensitive and localize navigational/system copy.
- [x] Run widget tests at 360/390/430 widths, dark/light and 200% text. Render and inspect representative current-source previews.

## Task 3: Verification and handoff

**Files:** Create `apps/jentra_employee/README.md`, configuration example, employee build evidence under `docs/verification/employee-app/` and ignored build artifacts inside the new app.

- [x] Run the new app's complete test suite and analyzer sequentially on the installed SDK.
- [x] Build a development web preview and Android APK if the installed Android toolchain permits it; record exact build/source evidence.
- [x] Obtain a fresh-context code review under the Superpowers review skill; fix material findings with meaningful regression tests.
- [x] Document configured versus unconfigured launch, supported live operations, draft-only leave, missing backend services, iOS Mac/signing requirement and device acceptance gaps.
- [x] Open the concrete result and provide source/preview/build links. Do not claim installed, authenticated device acceptance or release readiness from tests/builds.

## Execution decisions

- Live read-only catalog check on 2026-10-09 confirmed foundation/private HR functions; attendance/leave/payroll functions are absent. Build safely around installed contracts; no migration installation is part of this task.
- Work is additive in the new employee directory, with a minimal workspace entry; concurrent desktop/Wave 5 edits and the Git index remain untouched.
- The user requested starting implementation after receiving the blueprint. Reuse that design and proceed; ShapeUI's discovery-only workflow does not replace the explicit build instruction.

## Task 4: Requested UI and feature upgrade (0.2.0)

The user's subsequent request replaces the original five-tab navigation with a floating Home/Leave/Activity/More dock, compacted to Home/Activity/More for enlarged text and Sinhala/Tamil. Retain all account, identity, receipt, draft-expiry and unavailable-service boundaries above.

- [x] Observe failing feature tests before implementing account help, Activity, review search/filter and leave-duration controls.
- [x] Replace the welcome slogan and improve sign-in, home, service cards and navigation using the supplied design assets.
- [x] Add a local Activity hub, review search/status filters, a leave range picker/calendar summary and guided HR help.
- [x] Complete full regression tests, analysis and current-source visual inspection.
- [x] Package the updated Android APK and development web host, record source evidence and prepare the preview panel.

## Task 5: Personal UI and employee profile photos (0.3.0)

The user requested a proper, creative design and the ability for employees to add their own profile picture. Continue the supplied Jentra identity with a personal navy header, grouped service rows, refined navigation and a redesigned Profile page.

- [x] Check the installed employee photo contract without changing backend permissions or data; document protected device-only storage because no supported upload endpoint exists.
- [x] Implement native single-image selection, bounded square JPEG preparation, metadata removal, exact employee ownership, persistence, replacement and removal.
- [x] Preserve private-route masking and online access checks through gallery background/return, account and scope changes, revocation, and sign-out during a write.
- [x] Complete 124 regression checks, clean analysis, current-source visual inspection and 17 self-contained preview renders; package and verify the 0.3.0 Android APK and web review host.
- [x] Record unchanged source hashes across final tests/builds and open the updated preview. Physical gallery acceptance, iOS compilation/signing, cloud photo synchronization and HR/payroll release gates remain open.

Evidence: `docs/verification/employee-app/profile-ui-20261009/result.md`.
