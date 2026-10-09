# Employee foundation implementation brief

Read the three mobile blueprints and existing private HR/domain contracts only as needed. Implement within the new app; do not alter shared packages or desktop work.

## Owned paths

- `apps/jentra_employee/lib/src/data/**`
- `apps/jentra_employee/lib/src/employee_controller.dart`
- `apps/jentra_employee/test/employee_controller_test.dart`
- `apps/jentra_employee/test/employee_gateway_test.dart`
- `apps/jentra_employee/test/secure_storage_test.dart`

The root builds UI/main/native hosts and owns the SDK lease until notified. Do not run Flutter/Dart jobs concurrently or change pubspec/lock files. Do not commit, stage, push, deploy, install SQL, create auth accounts/roles or spawn agents.

## Stable UI interfaces

Export the models and gateway contracts from `data/employee_gateway.dart`.

- `EmployeeWorkspace`: const constructor, required `String tenantId, legalEntityId, branchId, tenantName, entityName, branchName, timeZone`; stable `String get key`.
- `EmployeeIdentity`: const constructor, required `EmployeeWorkspace workspace`, `String actorId, employeeId, displayName`; stable `String get key`.
- `EmployeeLink`: const constructor, required `String id, employeeId, displayName`, `int version`, `DateTime expiresAt`.
- `EmployeeReview`: const constructor, required `String id, status`, `int version`, `DateTime startDate, endDateExclusive`, `List<String> objectives`, optional `String? comments`. `bool get canAcknowledge` true only for reviewed.
- `EmployeeLeaveDraft`: const constructor, required `String leaveType, reason`, `DateTime startDate, endDate`; dates are inclusive calendar dates, local draft only. Expose `String? get validationError` for empty/bounded type/reason and end before start; no invented statutory balance. Valid drafts at most 366 calendar days.
- `EmployeeFailure implements Exception`: `String code, message`; never expose raw provider exception/SQL/credentials.
- `EmployeePhase`: unconfigured, signedOut, loading, chooseWorkspace, linkRequired, ready, locked.

`EmployeeController extends ChangeNotifier`:

Constructor `EmployeeController({required EmployeeGateway? gateway, required EmployeeDraftStore draftStore, DateTime Function()? now})`.

Public fields/getters: `EmployeePhase phase`, `bool busy`, `EmployeeFailure? error`, `String? notice`, `List<EmployeeWorkspace> workspaces`, `EmployeeWorkspace? workspace`, `EmployeeIdentity? identity`, `List<EmployeeLink> links`, `List<EmployeeReview> reviews`, `String? reviewsCursor`, `bool reviewsLoading`, `EmployeeFailure? reviewsError`, `EmployeeLeaveDraft? leaveDraft`, `bool hasPendingCommand`.

Public methods: `Future<void> start()`, `signIn(String email, String password)`, `signOut()`, `selectWorkspace(EmployeeWorkspace value)`, `refresh()`, `loadMoreReviews()`, `respondToLink(EmployeeLink link, {required bool accept})`, `acknowledgeReview(EmployeeReview review)`, `reconcileCommand()`, `retryPendingCommand()`, `saveLeaveDraft(EmployeeLeaveDraft draft)`, `discardLeaveDraft()`, `void lock()`, `Future<void> resume()`, `dispose()`.

`EmployeeGateway` exposes only employee-safe operations. Design its internal methods and pending command models as needed, keeping UI operations in the controller. `SupabaseEmployeeGateway(SupabaseClient client)` is the real implementation.

`data/employee_storage.dart` exports:

- `EmployeeKeyValueStore` with `Future<String?> read(String key)`, `Future<void> write(String key, String value)`, `Future<void> delete(String key)`.
- `NativeEmployeeKeyValueStore()` using flutter_secure_storage device-bound native settings; no plaintext fallback.
- `EmployeeDraftStore(EmployeeKeyValueStore store, {DateTime Function()? now})`, own lease-scoped JSON drafts and pending command persistence. No test-only methods in production. Define needed methods for controller; UI uses controller only.
- `EmployeeAuthStorage` extending Supabase Flutter `LocalStorage`, constructor `EmployeeAuthStorage(EmployeeKeyValueStore store)`, secure session persistence under employee app namespace.
- `EmployeePkceStorage` implements GotrueAsyncStorage, constructor same store; secure PKCE storage.

## Real backend

Use existing foundation identity/auth and `SupabasePrivateHrGateway` for self/link inbox/reviews/own command receipts only. Live catalog on 2026-10-09 has foundation and private HR; attendance, leave and payroll functions absent. Never fall back to administrative employee/payslip/document APIs.

- Resolve actor from current session and validate it after async operations. Get active tenant/entity/branch choices with foundation APIs. No business creation/invitations from this app.
- Accepted own identity comes from `people_hr_self`; no email matching, supplied employee ID or role granting.
- Exact pending link only from own `people_hr_link_inbox`; missing `people.view` becomes a useful HR access error, no grant.
- Reviews through own resolved employee. Only reviewed/acknowledged/closed records appear, even if the account also has staff review rights. No private review history.
- Allowed writes: link_accept/link_reject/review_acknowledge. Reuse original CommandEnvelope/HrCommands and verify confirmation/own receipt against the saved exact request.
- Freeze/persist command before network call. Unknown transport/confirmation outcome retains its identity, prevents another action and reconciles receipt before retry. No auto retry under a fresh key. Definite rejection becomes a safe visible error.
- Draft restoration occurs only after fresh online identity check. Draft expires within 24h, rejects cross-identity payloads, never auto-submits. Background clears sensitive state; resumed identity and permissions are rechecked. Account/scope changes invalidate pending callbacks.
- Server errors map to useful safe messages/codes; network failure is not an empty successful list.

## Tests and report

Write meaningful tests first, run RED then GREEN. Catch missing accepted link, untrusted/cross-scope/stale responses, filtering draft/submitted reviews, uncertain write/receipt mismatch, draft expiry/cross-user storage, storage failure and background masking. Use real Supabase adapter + fake HTTP for external network contract tests where possible, not assertions on a fake gateway's existence.

Wait for the root's SDK lease before running tests. Use installed direct Dart/Flutter snapshot invocation with approved escalation for SDK cache. Full app tests are run by root after integration.

Write `docs/verification/employee-app/foundation-report.md` with files, exact commands/results, RED/GREEN evidence and concerns. Return a short result. Notify root promptly when model interfaces exist so UI implementation can consume them.
