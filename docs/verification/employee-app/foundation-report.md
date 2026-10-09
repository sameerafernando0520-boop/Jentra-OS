# Employee app data and session foundation

Date: 2026-10-09. Scope: new employee app only. Native host/UI integration belongs to the root task. No deployment, migration installation, account creation, role changes, staging or commits were performed.

## Owned files

- `apps/jentra_employee/lib/src/data/employee_gateway.dart`: required public const models, bounded calendar-date leave draft, safe failures, employee gateway, real Supabase foundation/private-HR adapter, frozen employee command envelope.
- `apps/jentra_employee/lib/src/data/employee_storage.dart`: native Android AES-GCM/KeyStore and device-bound iOS Keychain settings; separate secure session/PKCE namespaces; scoped draft leases; durable exact command recovery.
- `apps/jentra_employee/lib/src/employee_controller.dart`: authenticated workspace/self selection, link onboarding, own shared review pages, explicit command reconciliation/retry, lease-scoped draft recovery and lifecycle masking.
- Three focused tests: `employee_controller_test.dart`, `employee_gateway_test.dart`, `secure_storage_test.dart`.

## Verification

The initial bootstrap test invocation ran before implementation files existed. It failed at compilation (+0/-3 loading failures), recorded in `foundation-red.log`. This is bootstrap evidence, **not behavioral RED evidence**. That invocation used Flutter's default dependency resolution; subsequent runs use `--no-pub`. No pubspec or lock file was manually modified by this subtask.

The compiling controlled-mutation run produced **19 passing tests and six expected assertion failures**, recorded in `foundation-behavioral-red.log`. Temporarily disabled gates were: online `getUser` actor matching, accepted-self employee matching, draft/submitted review filtering, receipt action matching, 24-hour draft expiry, and lifecycle callback generation checks. Each corresponding regression failed. Source originals were restored in a PowerShell `finally` block. This is behavioral RED evidence. A first mutation attempt also encountered a test-fixture const-expression compilation issue; the fixture was corrected before the final recorded mutation run.

Baseline after actor-wide cleanup: **25/25 passing tests**. Final analysis of the six owned Dart files: **No issues found**, recorded in `foundation-analyze.log`. Final GREEN after source restoration is recorded in `foundation-green.log`; root runs full integrated app checks separately.

Commands, run from `apps/jentra_employee`, with an exclusive SDK lease and approved SDK-cache escalation:

```powershell
# Initial bootstrap only (before implementation files existed):
& 'C:\src\flutter\bin\cache\dart-sdk\bin\dart.exe' 'C:\src\flutter\bin\cache\flutter_tools.snapshot' test test/employee_gateway_test.dart test/employee_controller_test.dart test/secure_storage_test.dart --reporter expanded

# Baseline, controlled-mutation RED, and restored GREEN:
& 'C:\src\flutter\bin\cache\dart-sdk\bin\dart.exe' 'C:\src\flutter\bin\cache\flutter_tools.snapshot' test --no-pub test/employee_gateway_test.dart test/employee_controller_test.dart test/secure_storage_test.dart --reporter expanded

# Formatting and analysis restricted to owned files:
& 'C:\src\flutter\bin\cache\dart-sdk\bin\dart.exe' format lib/src/data lib/src/employee_controller.dart test/employee_controller_test.dart test/employee_gateway_test.dart test/secure_storage_test.dart
& 'C:\src\flutter\bin\cache\dart-sdk\bin\dart.exe' analyze lib/src/data lib/src/employee_controller.dart test/employee_controller_test.dart test/employee_gateway_test.dart test/secure_storage_test.dart
```

An initial fake-HTTP fixture failed because PostgREST requires `http.Response.request` metadata; `foundation-debug.log` contains only synthetic test diagnostics. The mock responses were corrected and production safe error mapping restored. `git diff --numstat -- pubspec.lock` produced no changes during final review.

Coverage includes real Supabase/private-HR + fake HTTP accepted-self/scope checks, safe missing-link/access errors, staff-rights subject substitution prevention, unpublished review filtering, exact receipt matching, transport failures, delayed-response/account changes, online user mismatch and failed remote logout. Controller/storage tests cover uncertain-request blocking and exact retry, secure persistence failure before dispatch, lifecycle masking, forged identity, access loss, fresh resume before draft opening, expiry at displayed-link dispatch, local logout, draft lease/owner validation, native storage options, secure namespace separation, and actor-wide draft cleanup while preserving pending recovery.

## Contract and evidence boundaries

- Online `getUser` validation precedes workspace/self/link reads. Accepted identity comes from `people_hr_self`; no email-to-employee matching or supplied employee ID is accepted for review reads. Each adapter review page freshly rechecks own self before the private HR page.
- The installed legacy reviews RPC can return own draft/submitted rows when an account also has staff review rights. The app adapter filters those rows before exposing typed data to UI. It receives the resolved employee's wire page; a dedicated server employee projection would further minimize transport. No private review history, staff subject directory, documents, payroll or administrative APIs are called.
- Link onboarding uses only the own scoped link inbox. Missing `people.view` or self access remains a visible HR access failure; no access grant is attempted.
- The only write intents are link acceptance/rejection and reviewed-record acknowledgement. Requests are sealed and securely written/read back before dispatch. Unknown results retain the original command and idempotency key. Retry checks the original own receipt first; receipt validation checks action, target, employee, scope and resulting version.
- Drafts are local and never submitted. Owner and schema validation, inclusive calendar dates, 366-day bound, 24-hour expiry and clock rollback checks protect restoration. Online accepted-self validation precedes opening them. Pending requests contain identifiers only and do not expire into a new request identity.
- Background lock removes visible names/workspace, identity, links, reviews and drafts, and invalidates callbacks. Resume freshly lists active choices and resolves accepted identity/permissions before restoration.
- A secure owner index allows logout/account-change cleanup across every previously used workspace. Storage operations are serialized, with the index written before the draft, so an interrupted write remains eligible for cleanup. Sealed pending command metadata remains protected for later receipt reconciliation. Local sign-out completes even when network revocation fails, with an explicit unconfirmed-revocation notice.
- Unit/fake-HTTP tests do not prove real Android/iPhone secure storage behavior, native OS lifecycle preview protection, live authenticated acceptance, server idempotency under contention, worker readiness, performance/load or owner signoff. Root owns those remaining integration/release gates.

## Privacy review follow-up

Two concrete privacy gaps were fixed in the owned controller/data slice after root review:

- Private foreground access now has an online authorization lease of at most 24 hours. A timer masks the visible workspace, identity, links, reviews and draft at expiry even when the wall clock stalls. Private actions and async callbacks also fail closed at expiry or when the clock moves backward from the last valid private access. Fresh online accepted-self resolution replaces the lease. Lock, disposal, account change and scope reload cancel prior timers and invalidate callbacks. Constructor injection permits a shorter positive lease but rejects durations longer than 24 hours.
- Access-loss responses (`PERMISSION_DENIED`, `SELF_LINK_REQUIRED`, `AUTHENTICATION_REQUIRED`, `SESSION_CHANGED`) from command dispatch or receipt recovery now mask/lock immediately. Explicit rejected dispatches may clear their sealed request; uncertain authentication/session outcomes and every failed receipt authorization preserve the original durable request for later reconciliation.

The draft's original storage lease separately bounds visible body retention. An internal typed store/controller lease carries its existing expiry without exposing metadata through the UI controller or rewriting timestamps on read. A draft restored at age 23 hours is masked one hour later even though online authorization was freshly renewed. Saving an explicitly edited draft creates a new local lease; reading/restoring does not. Visible expiry does not auto-submit anything; the existing store rejects/deletes expired records on restoration.

Tests were written before these fixes. `foundation-privacy-red.log` shows a compiling focused run with **10 existing passes and 16 expected behavioral failures** covering foreground expiry, delayed results, action-time clock rollback, and all four access-loss codes for dispatch and receipt recovery. `foundation-aged-draft-red.log` shows the separately added aged-restoration case failing **0/1** before its fix.

After implementation, `foundation-privacy-green.log` records **33/33 focused controller tests passing**, including max lease validation, frozen-clock timer expiry, renewal replacing the old timer, link/action gating, and expiry of a 23-hour restored draft. Every created controller is disposed; these focused controller checks completed without leftover lease timers. The integrated widget suite was not run by this subtask; root later adjusted widget fixtures to lock externally owned controllers before the widget invariant check. `foundation-privacy-analyze.log` reports **No issues found** across all six owned Dart source/test paths. The final analyzer repair was a brace-only lint change. The broad integrated app suite is deliberately left to root's SDK lease.

Exact focused commands from `apps/jentra_employee`, using the installed direct SDK invocation and approved SDK-cache escalation:

```powershell
& 'C:\src\flutter\bin\cache\dart-sdk\bin\dart.exe' 'C:\src\flutter\bin\cache\flutter_tools.snapshot' test --no-pub test/employee_controller_test.dart --reporter expanded
& 'C:\src\flutter\bin\cache\dart-sdk\bin\dart.exe' 'C:\src\flutter\bin\cache\flutter_tools.snapshot' test --no-pub test/employee_controller_test.dart --plain-name 'a draft restored at age 23 hours masks at its original expiry despite fresh authorization' --reporter expanded
& 'C:\src\flutter\bin\cache\dart-sdk\bin\dart.exe' format lib/src/data/employee_storage.dart lib/src/employee_controller.dart test/employee_controller_test.dart
& 'C:\src\flutter\bin\cache\dart-sdk\bin\dart.exe' analyze lib/src/data lib/src/employee_controller.dart test/employee_controller_test.dart test/employee_gateway_test.dart test/secure_storage_test.dart
```

The SDK lease was returned to root after focused GREEN and clean owned-file analysis. This follow-up did not edit UI/native hosts, pubspec/lock, shared packages, repository/index state or production state.

## Memory consulted

`MEMORY.md` lines 47-54 guided use of the separate employee blueprint and existing exact idempotent domain transactions. The current implementation and package interfaces were inspected locally rather than relying on remembered readiness claims.
