# Employee app final-review fix wave

Date: 2026-10-09. Reviewed findings: `review-findings-20261009.md`, baseline snapshot `review-package.txt`. Scope: the new employee app's `lib/main.dart`, `lib/src/*`, associated tests and this evidence report. Shared packages, backend, root manifests/index and native hosts were not modified by this fix wave. Root retains native packaging and final integrated verification.

## Implemented fixes

1. **Delayed authentication and background lock.** The controller now tracks foreground eligibility independently of phase and a lifecycle generation separately from scope generations. Background locking blocks `start()`, auth-change startup and the post-sign-in continuation. Async auth can complete and update the authenticated actor while the app remains locked; it cannot resolve or restore private employee data. Foreground resume freshly resolves online employee access. A real `EmployeeApp` test delays authentication, backgrounds the app, completes auth, revokes employee access, then resumes: there are zero background self reads and exactly one fresh resumed self check; private names remain absent.

2. **Expired drafts in open editors.** Original stored draft expiry now increments the private route version so the owning private Navigator is replaced. The open editor listens to controller invalidation, clears its text immediately, removes its editable body, rejects save callbacks and disposes its text controllers during route replacement. The shell's captured route version also prevents a stale editor save. The real widget test restores a 23-hour-old draft, opens its actual editor, verifies the private reason in its text controller, advances to original expiry, then verifies that the editor/save widgets are absent, private text is absent and the original text controller is disposed. No restored timestamp is rewritten and no expired body is resaved.

3. **Durable account-session logout.** `EmployeeAuthStorage` serializes reads, writes and removals. Logout synchronously blocks further persistence and invalidates queued old writes. Already-running writes drain before removal. Removal deletes and then verifies absence through the same serialized storage queue. Main supplies the same coordinated storage instance to Supabase initialization and the employee gateway. The gateway explicitly awaits this verification barrier in addition to the framework's event listener; storage failure produces a safe `DURABLE_LOGOUT_INCOMPLETE` error. The controller keeps a logout transition locked until the barrier resolves, and incomplete durable logout remains locked when Continue/resume is requested. Retrying sign-out can complete after storage recovers. Remote revocation failure remains distinct from verified local session removal.

4. **Visible outcomes.** The app displays notices on public and private routes using localized interface strings and an accessible live region. Not-found receipts, unconfirmed remote revocation, confirmed requests, own-receipt confirmations and draft/workspace/link notices are visible. Necessary successful outcomes are retained through their follow-up fresh identity refresh. Stable failure codes map to English/Sinhala/Tamil interface copy at every error-rendering boundary; employer-authored review content remains unchanged.

## Verification evidence

- `review-fixes-red.log`: both new test files compiled; nine tests failed. **Eight are meaningful behavioral RED failures** for delayed background auth, two initialized auth lifecycle cases, three missing outcomes and two missing operational translations. The editor case initially missed an offscreen action and failed at fixture lookup; that initial editor failure is not counted as behavioral evidence.
- After correcting the editor fixture to scroll and settle the actual Edit action, `review-editor-red.log` captured **0 passing / 1 expected behavioral failure** under a controlled mutation that removed editor listener/route invalidation. The private editor remained after expiry. Both source files were restored in PowerShell `finally`.
- `review-fixes-green.log`: **57/57 tests passed** across the two new regression files and the directly affected controller, real gateway/fake HTTP and secure storage tests. This was a focused affected-suite run, not the entire app/golden/native test package.
- `review-fixes-analyze.log`: **No issues found** for the new app's `lib` and `test` sources. Formatting remained within the assigned new-app sources/tests.

The initialized authentication tests use the installed Supabase Flutter 2.17.2 `Supabase.initialize` path, its actual auth-state subscription, password auth and logout lifecycle, with a synthetic token and fake HTTP responses only. They do not call live Auth or create/change an account. The deletion-failure test verifies the framework's unawaited/caught storage failure cannot produce a completed durable logout in the app, then verifies successful retry clears storage. The overlapping-write test holds the actual initialized listener's session write in progress, starts logout, verifies logout has not completed, releases the old write, then verifies the persisted session is absent. Mock secure storage and fake HTTP are used; these are not physical Android/iPhone storage or real provider acceptance evidence.

Commands run from `apps/jentra_employee` with the exclusive SDK lease and approved SDK-cache escalation:

```powershell
# Initial compiling review-fix RED:
& 'C:\src\flutter\bin\cache\dart-sdk\bin\dart.exe' 'C:\src\flutter\bin\cache\flutter_tools.snapshot' test --no-pub test/employee_review_fixes_test.dart test/employee_auth_lifecycle_test.dart --reporter expanded

# Corrected editor controlled-mutation RED and restored verification:
& 'C:\src\flutter\bin\cache\dart-sdk\bin\dart.exe' 'C:\src\flutter\bin\cache\flutter_tools.snapshot' test --no-pub test/employee_review_fixes_test.dart --plain-name 'aged draft expiry removes and disposes open editor body' --reporter expanded

# Final focused GREEN:
& 'C:\src\flutter\bin\cache\dart-sdk\bin\dart.exe' 'C:\src\flutter\bin\cache\flutter_tools.snapshot' test --no-pub test/employee_review_fixes_test.dart test/employee_auth_lifecycle_test.dart test/employee_controller_test.dart test/employee_gateway_test.dart test/secure_storage_test.dart --reporter expanded

# New-app source and associated-test analysis:
& 'C:\src\flutter\bin\cache\dart-sdk\bin\dart.exe' analyze lib test
```

## Files changed

- `lib/main.dart`: coordinated native auth storage supplied to initializer and gateway.
- `lib/src/data/employee_storage.dart`, `employee_gateway.dart`: serialized session persistence/removal and explicit verified logout barrier.
- `lib/src/employee_controller.dart`: foreground and lifecycle guards, durable logout state, expired-draft route invalidation and retained success outcomes.
- `lib/src/employee_app.dart`, `ui/employee_shell.dart`, `ui/leave_draft_screen.dart`: owner-key invalidation, immediate editor masking/save guards and accessible global outcomes.
- `lib/src/l10n/employee_strings.dart`, `ui/onboarding_screens.dart`, `ui/employee_reviews.dart`: stable-code localization at the UI boundary.
- New `test/employee_review_fixes_test.dart`, `test/employee_auth_lifecycle_test.dart`.

The previous `foundation-report.md` timer claim was narrowed to the focused controller checks that actually ran; root's integrated fixtures explicitly cancel externally owned controller timers before widget invariants. The SDK lease was returned to root after final focused GREEN and clean analysis. Full integrated rendering checks, Android packaging, iOS/physical-device acceptance, translation-owner/screen-reader acceptance and the single scoped re-review remain root's next gates. This report makes no production-readiness claim.
