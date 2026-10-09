# Wave 5 provider, cash and recovery continuation — October 9

Jentra OS and Wave 5 remain incomplete. This continuation implements source fixes in the cash workspaces; it does not install SQL, create an account, activate an entitlement, publish financial data or certify runtime acceptance. The root continuation owns fresh live-state reads and serialized SDK/build/render verification.

## Source defects and resulting behavior

`CashScenarioController` and `CashPaymentDatesController` awaited authorization and then continued the requested read after their controller had been disposed or gone offline. Cash scenario freeze also continued into the server save after an asynchronous encrypted pending-save completed, without checking the operation's current epoch. A late freeze receipt could trigger further authorization and delete the original pending recovery marker after invalidation.

The controllers now check their operation epoch after authorization and asynchronous provider/storage steps, before advancing to another protected read or command. An invalidated operation leaves visible evidence cleared. A freeze invalidated before dispatch sends no server save; its encrypted original scenario identity remains available for reviewed recovery. A receipt arriving after invalidation retains the encrypted original request for reconciliation instead of silently removing it. These guards cannot cancel a command already sent to the server; server idempotency and current authorization remain authoritative.

The independent review identified a further gap while the final store removal authorization was in flight: the controller could be invalidated during that await and the store would still delete its recovery row. `CashScenarioStore.removePending` and `Wave5CommandStore.remove` now accept the controller's current-operation predicate and check it after their own authorization, immediately before deletion. Both cash controllers pass that predicate. Four additional regressions cover disposal and offline invalidation at this final removal boundary, retaining the original encrypted command/scenario after a late authorization completes.

The scenario screen also retained typed scenario amounts/dates, horizon fields and reopen IDs when its controller changed to another actor/scope or when the existing controller went offline/failed authorization. It now clears those fields and selections when the controller changes or reports unavailable access. Controller authorization failures and disposal clear the previous frozen scenario/export identity as well as its source evidence.

Owned source changes:

- `apps/jentra_desktop/lib/src/features/analytics/cash_scenario_screen.dart`: epoch checks, frozen identity clearing and controller-bound input clearing.
- `apps/jentra_desktop/lib/src/features/analytics/cash_payment_dates_section.dart`: epoch checks around authorization, source/proposal reads and command-send/reconciliation steps.
- `apps/jentra_desktop/test/wave5_cash_epoch_test.dart`: twelve focused regression cases covering delayed authorization with disposal/offline invalidation, pending-save dispatch prevention, late-receipt recovery preservation, final-removal authorization invalidation, cleared frozen identity and actor/offline input clearing. The independent review added four final-removal cases.
- `packages/jentra_platform/lib/src/analytics/cash_scenario_store.dart` and `wave5_command_store.dart`: independently reviewed optional current-operation checks after final removal authorization and before recovery-row deletion.

The native/golden agent separately owns spacing changes within the two screens' widget child layouts and the geometry assertions in `wave5_continuation_test.dart`. These changes were coordinated in disjoint sections. No approved PNG was replaced.

## Verification boundary

Heavy SDK jobs are serialized by the root continuation. Its frozen r13 results now record twelve passing epoch/privacy regressions, 96 passing surrounding cash/workspace tests and twelve passing 200% cash capture variants. The separate control run used the preserved r10 source for the four changed controller/store files: all twelve new regression cases failed there, then the final r13 source was restored. This demonstrates the regression trigger under controlled test conditions; genuine authenticated native/runtime acceptance remains open.

Evidence:

- [Twelve final regression tests](windows-test-preview-cashEpochTests-20261009-r13.json) and [log](windows-test-preview-cashEpochTests-20261009-r13.log).
- [Preserved r10 control failures and source bindings](cash-epoch-red-20261009-r13.json) and [failed control log](windows-test-preview-cashEpochRed-20261009-r13.log).
- [96 surrounding cash/workspace tests](windows-test-preview-cashTests-20261009-r13.json) and [log](windows-test-preview-cashTests-20261009-r13.log).
- [Twelve cash capture variants](windows-test-preview-cashFrames-20261009-r13.json) and [log](windows-test-preview-cashFrames-20261009-r13.log). Captures overlap the workspace suite and are not additional independent feature coverage.

Final scoped analysis is clean. Both ordinary Windows builds completed successfully: Preview in 204.4 seconds and Connected in 201.6 seconds. The root packaging verification binds 1,068 selected current source inputs per app and verifies 68 release entries through the build directories, portable app directories and ZIP. The explicit fresh frame inspection contains 24 frames: 18 cash, four model and two authentication frames. The 200% cash input geometry assertions pass. The aggregate native report must retain these source/release/inspection bindings before living status publication. r10 passing results remain historical for the older source.

The broader frozen-source suites record 1,127 platform tests passing and 1,921 desktop tests passing with the same 83 strict approved-golden failures and zero skips. All 83 failures have their retained classification; the current source does not have a passing strict desktop golden gate. Widget keyboard tests are separate from actual native keyboard verification. Neither r13 app was natively launched for this continuation, and authenticated native/MFA/keyboard/export delivery/contention/load/owner acceptance remain unverified.

Additional final evidence:

- [Clean scoped analysis](windows-test-preview-analyzer-20261009-r13.json).
- [Ordinary Preview build](windows-test-preview-build-20261009-r13.json) and [ordinary Connected build](windows-test-connected-build-20261009-r13.json).
- [Source/release/ZIP delivery record](windows-test-delivery-20261009-r13.json) and [24 explicit frame inspections](windows-test-frame-inspections-20261009-r13.json).

Remaining evidence checks:

- Retain the already executed r13 regression/workspace/capture results and their exact source bindings.
- Complete the aggregate native report from the fresh successful analysis/build/package and explicit render-inspection records; require current source/release hashes before living status publication.
- Preserve the 83 approved images and separate controlled widget evidence from authenticated native keyboard/restart/revocation/export and owner acceptance.

The source fixes bind to FR-503, FR-514, FR-515, FR-531 and NFR-507. They do not close the authenticated native/restart/revocation, actual export delivery, installed provider or owner acceptance gates.

## Provider investigation and remaining gates

The source includes immutable historical CRM/realized mapping, authoritative statement/classification ratios, dated cash from five families, source-specific payment-date approval, immutable scenario assumptions and governed export adapters. The current implementation reads Wave 4 issued payroll/correction/reimbursement authority and preserves its stores and journals. This continuation changed no migration or provider contract and did not reinstall the six previously approved migrations.

The 71-file runtime bundle remains unapproved. Installing its missing provider dependencies and publishing valid nonempty sources are separate required operations. Completion still needs real authorized/denied CRM and statement/ratio sessions, distinct genuine MFA date preparation/approval, source settlements/reversals at recorded/effective cutoffs, actual immutable scenario creation/recovery, actual CSV/XLSX creation/download/hash/reopen, authenticated native actor switch/restart/revocation, independent contention/target-scale load and owner acceptance. A malformed/incomplete or denied provider must remain unavailable; a controller test is not evidence of installed financial authority or downloaded bytes. Production and real billing remain excluded.

## Documents reviewed for this slice

- `docs/development/wave5-next-session-20261009.md` and `docs/development/wave5-status.md`.
- `docs/verification/wave5/installation-result-20261008.md` and the cash/finance/recovery rows and evidence sections of `requirement-matrix-20261008.md` / `.json`.
- `docs/verification/wave5/complete-app-remaining-work-20261009.md`, `complete-app-runtime-review-20261009.md` and the artifact-path bindings in its `.json`.
- `docs/verification/wave5/integrated-runtime-protocol-20261006.md` and `windows-test-verification-20261009-r10.md`.
- `docs/blueprint/wave5/WAVE5_INTELLIGENCE_AND_CONTROL_SPEC.md`, `W5_02_03_FORECAST_AND_RATIO_CONTRACT.md` and `W5_CASH_PAYMENT_DATES_CONTRACT.md`.
- `docs/verification/wave5/cash-dates-review-20261008.md`, `cash-dates-verification-20261008.md` and `cash-ui-verification-20261008.md`.

The shared checkout was refreshed before changes and initially clean. Concurrent workers/build-runner/Employee/W3/W4 changes are preserved. No reset, clean, stash, stage, commit, push, acceptance-store copy or session extraction occurred.
