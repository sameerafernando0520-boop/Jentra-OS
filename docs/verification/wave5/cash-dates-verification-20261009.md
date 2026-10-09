# Current cash UI verification - October 9, 2026

October 9 scoped Dart analysis is clean; 72 domain, 48 platform and 96 desktop/controller/render tests pass. The Windows release matches all 1,051 selected desktop dependency source files and 34 release files, including current workspace dependency manifests. Sixty fresh cash frames were captured at twelve viewport/theme/density variants with 200% text; 16 were visually inspected. Initial Tab focus was checked. These are controlled renders; authenticated native acceptance and full keyboard navigation remain open.

The root pubspec added the concurrent employee app after the previous cash build. A new immutable copy in `build/w5rt9` includes every declared workspace member. Dependency resolution, analysis, focused tests and the Windows build ran serially there. Existing source files, earlier builds, approved goldens and acceptance-owned stores were preserved.

The full-workspace comparison is false; 11 employee-app files changed during the run. The build attribution follows the desktop's transitive workspace dependencies and includes every workspace dependency manifest. Employee application code is outside that dependency graph and has no desktop import. The [initial whole-workspace result](cash-dates-workspace-drift-20261009.json) is retained; all desktop source, manifests, lockfile and release bytes match. No employee file was overwritten or copied back.

| Verification | Result |
|---|---|
| Dependency resolution / scoped Dart analysis | Passed / no issues |
| Domain / platform / desktop tests | 72 / 48 / 96 passed |
| Selected source / release hashes | 1051 / 34 match |
| Fresh renders | 60 frames; 16 inspected; all 12 approval variants |
| Authenticated native, installed new providers, real MFA, worker delivery, contention/load, owner acceptance | Open |

The full [machine evidence](cash-dates-verification-20261009.json) records commands, times, hashed logs, source/release/frame hashes and exact inspection paths. [Run metadata](cash-dates-run-20261009.json) records the twelve viewport/theme/density variants. Flutter 3.47.5 / Dart 3.13.4 were verified from the local SDK cache. An initial restricted dependency attempt was stopped; successful jobs had SDK/package cache access.

At 200% text, the reviewed digest wraps at 1024x720 and approve/reject controls remain visible. The inspected source/date/reason/proposal/recovery controls remain readable. All-five-family availability and closing cash 4.000003 are controlled fixture values; unavailable-provider cards and injected sessions do not establish installed features. Full authenticated keyboard/restart/revocation/export checks remain open.

No native executable was launched, profile provisioned, installer created or approved golden regenerated. The 13 shared dashboard/setup failures remain open. The [runtime review](runtime-review-20261009.md) specifies the distinct real-session and isolated-profile gates.
