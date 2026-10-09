# Employee app 0.3.0 — personal design and profile photos

The requested UI refinement and employee profile-photo feature are implemented. Home now has a personal navy header with an original arc motif, employee avatar and workplace, grouped service rows and a refined selected navigation capsule. Profile uses the same identity language and exposes choose/change/remove photo controls alongside read-only employer details.

Tap the Home identity header or More → My profile → Choose a photo. The app uses the native system selector, center-crops the selected still image, strips source metadata, reduces it to a 256×256 JPEG and stores it in the existing protected native store. The thumbnail appears on Home and Profile, is scoped to the exact tenant/entity/branch/account/employee, and is removed at sign-out. Initials appear when there is no photo.

Photos stay on this device. The read-only development catalog check found no supported employee photo upload endpoint or avatar field in the checked schemas. No storage bucket, role, permission, migration or HR employee record was changed. Server synchronization remains future backend work.

## Verification

| Check | Result | Evidence |
|---|---|---|
| Complete employee regression suite | 124 passed, including 21 photo checks and 17 screen renders | [tests-final.log](tests-final.log) |
| Static analysis | No issues | [analyze-final.log](analyze-final.log) |
| Android debug compile | Passed; native Kotlin photo selector compiled | [android-build.log](android-build.log) |
| Web review host compile | Passed; authenticated web operation remains disabled | [web-build.log](web-build.log) |
| APK identity | com.jentra.employee.dev, version 0.3.0, code 4; API 24 minimum, target 36 | [apk-badging.log](apk-badging.log) |
| APK signature | v2 verification passed; development signing | [apk-signature.log](apk-signature.log) |
| Standalone HTML | 17/17 embedded PNGs decoded and matched current renders; zero external assets | [preview-validation.json](preview-validation.json) |
| Source consistency | All 332 tracked source/asset entries match before final tests and after both builds | [source-comparison.json](source-comparison.json) |
| Browser presentation | Updated 0.3.0 preview opened at the existing loopback URL; light/dark Home and Profile visually inspected | [employee-app-preview.html](employee-app-preview.html) |

The web build emits a nonfatal Cupertino icon-font family warning. Employee controls use the bundled Material icon font; the native and rendered screens were inspected. This compile result is not a browser login or native acceptance claim.

The photo checks exercise actual replacement/removal, verified storage writes, source EXIF removal, malformed/oversized images, cancellation, exact account isolation, hostile cleanup indexes, sign-out during a write, background masking, revoked access, changed employees, and a resumed route waiting for canceled writes to finish cleanup. Photo controls remain reachable at 200% text in English, Sinhala and Tamil. Renders explicitly wait for avatar decoding so a loading circle cannot masquerade as a displayed image. The colored geometric image is a test fixture, not an employee portrait.

The system selector may background the app. The old private navigator and displayed avatar are destroyed, and accepted employee access is verified online before a selection is applied on return. Profile reopens after that check. A write already initiated under verified access can finish while masked; explicit lock, scope change, sign-out or session change revokes it, and reloading waits for that cleanup to settle. Only the owned photo provider is evicted from Flutter's image cache on removal, replacement or route disposal.

## Artifacts

- [Self-contained UI preview](employee-app-preview.html) — 2,564,760 bytes; SHA-256 `642ba16243fb8f3ed636f4e732b7c798dd7871fd7c9596b2d1e68a8fd67bbb60`.
- [Development Android APK](../../../../apps/jentra_employee/build/deliverables/Jentra-Employee-0.3.0-development.apk) — 177,762,691 bytes; SHA-256 `cfe73e4adc45e4b0a2aed333c3e6282b2dd3d8c5af4cf4341e8ec5d00de3888f`.
- [Design rules](design-system.md), [APK metadata](apk-artifact.json), and [source manifests](source-after-build.json).

The original 0.2.1 APK and preview are preserved. The Git index and concurrent Wave 5/desktop changes were left untouched.

## Remaining acceptance

Physical Android selection, canceled gallery return, persisted-photo restoration after process restart, screen masking, access revocation and sign-out cleanup must be exercised with an authorized employee account on a phone. API 33+ photo-picker and API 24–32 document-picker paths need device coverage. No installation or authenticated device walkthrough was performed in this change.

iOS PHPicker/ImageIO source is implemented and reviewed against the current Flutter registrar API, but macOS/Xcode compilation, signing and a real iPhone walkthrough are still required. It supports photo selection on iOS 14+; older iOS receives an unavailable-selector result. New translated photo copy still requires owner language review.

Attendance, authoritative leave submission/balances, employee payslips/documents/cases, employee-only review projection and payroll release acceptance retain their existing backend/release gates. This UI/photo delivery does not claim the complete HR/payroll app is production-ready.
