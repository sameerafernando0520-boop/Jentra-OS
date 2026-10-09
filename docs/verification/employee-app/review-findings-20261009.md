# Fresh-context employee app review

Reviewer: `employee_review_fallback`, GPT-6.1 Sol/high. The initially requested GPT-6 Astra reviewer failed before reviewing because its model usage limit was reached. The fallback reviewed the complete new-app source snapshot and relevant existing API/auth dependencies read-only. No tests, builds, live database calls or mutations were performed by the reviewer.

Source snapshot: `review-package.txt`. Review evidence at dispatch: 73/73 integrated tests. Root analyzer became clean after brace-only repairs.

## Strengths

The employee facade has three write intents, fresh accepted-self review checks and receipt identity/scope/version validation. Durable request persistence precedes dispatch and uncertain outcomes retain exact command identity. Account/scope generation guards, private Navigator replacement, authorization timers and separate draft expiry substantially reduce private retention. Unavailable services are truthfully described. Native sensitive storage has no plaintext fallback; web authentication stays disabled.

## Important findings

1. **P1 — delayed sign-in can undo the background lock.** Controller auth-change handling and post-sign-in continuation can call `start()` after a lifecycle lock, resolve identity and restore private content while backgrounded. Foreground `resume()` only acts when locked and therefore can skip revalidation. Track foreground eligibility independently of phase, guard auth/start continuations and test delayed sign-in/background/revocation. Sources: `employee_controller.dart:225,307,316,779`; `employee_app.dart:53` in reviewed snapshot.

2. **P1 — expired restored drafts remain readable in an open editor.** Clearing `controller.leaveDraft` does not clear a previously opened editor's text controllers or replace its route; an aged restored draft remains visible/editable after its original expiry. Invalidate the editor/body at the original lease expiry and test the visible widget content. Sources: `employee_controller.dart:159`; `employee_shell.dart:48`; `leave_draft_screen.dart:25`.

3. **P1 — sign-out does not confirm durable auth-session removal.** Supabase Flutter 2.17.2 starts storage updates unawaited and catches/logs deletion failures. A null in-memory actor can produce signed-out UI even if the durable refresh token remains. Serialize persistence/removal and explicitly await/verify logout storage clearing; incomplete durable logout must remain visibly locked. Test deletion failure and overlapping old persistence using the actual initialized auth lifecycle. Sources: `employee_storage.dart:295`; `employee_controller.dart:331,334,341`; installed `supabase_auth.dart:96,188-207`.

4. **P2 — recovery/logout notices are not displayed.** No UI reads `controller.notice`, so users do not see a not-found receipt outcome or unconfirmed remote revocation warning; success notices also disappear during follow-up refresh. Render accessible localized outcomes on public/private surfaces and preserve required notices through refresh. Test actual visible receipt lookup/logout results. Sources: `employee_controller.dart:341,691`; `employee_app.dart:193`; `onboarding_screens.dart:194`.

## Minor finding

**P3 — operational failures remain English in Sinhala/Tamil.** Map stable failure codes to interface translations at the UI boundary. Retain employer-authored content in its original language. Sources: `employee_gateway.dart:165`; `employee_app.dart:163`.

## Existing release gates and declined judgments

The legacy review wire projection can include unpublished records for staff-rights actors before app-side filtering. A dedicated server employee projection remains required before rollout. The reviewer checked existing private-HR gateway/domain/migration contracts and installed Supabase/GoTrue auth sources.

Actual installed/authenticated behavior, Android/iOS compilation or physical storage/lifecycle acceptance, screen-reader/translation-owner acceptance, idempotency under contention, target-scale performance, production payroll and future E1 modules were not judged from this source review. Each remains a separate gate.

The suspected settings-state finding was withdrawn after checking passing Light/System-to-Dark-to-Tamil tests and the mutable route builder. No critical findings were reported. Development handoff requires the four Important fixes; production readiness is not claimed.

## Fix wave

One integrated fix wave was assigned to `employee_foundation`; root will obtain one scoped re-review of that wave after regression evidence. No findings are silently deferred.

## Single scoped re-review

The same fresh-context reviewer read `review-fix-package.txt` and `fix-report.md` after the fix wave and the 82/82 integrated suite. It confirmed all four Important findings and the minor localization finding were addressed. It found two P2 regressions introduced by the wave:

1. Logical “Lock app” set the lifecycle foreground flag to false, so Lock app → Sign out → Sign in silently failed until an OS resume.
2. A durable-removal failure followed by verified local removal with remote revocation failure retained the obsolete durable logout block, preventing a subsequent login.

Root added real-widget regressions before correcting either issue. `rereview-regressions-red.log` compiled and reproduced both failures; an additional delayed-auth/manual-lock guard passed. The targeted correction separates `background()` from logical `lock()`, preserves a locked route during auth callbacks, and clears the durable block after the gateway's verified-local-removal path. The gateway already reports remote failure only after its serialized storage verification barrier.

This is the one scoped re-review required by the review workflow. The two resulting targeted corrections are verified by root; they are not represented as a further independent approval. Final integrated checks and packaging are recorded in `progress-20261009.md`. No other breakage was reported in the scoped re-review. Server projection, physical-device acceptance and release-signing gates remain open.
