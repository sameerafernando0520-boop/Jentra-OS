# Jentra Employee APK size reduction — 13 October 2026

Version **0.3.1+5** replaces the previous universal debug package with optimized development APKs containing one processor architecture each. The prior file measured **177,762,691 bytes (169.53 MiB)**; see [baseline inspection](baseline-apk.json).

## Changes

- Release compilation removes the debug Dart kernel, hot-reload runtime and graphics validation libraries. [Flutter's size guide](https://docs.flutter.dev/perf/app-size) explains why debug APKs are substantially larger.
- Separate ARM64 and ARMv7 APKs avoid shipping two unused engine architectures to each phone. The build uses [Flutter's per-architecture packaging](https://docs.flutter.dev/deployment/android#build-an-apk), R8 code/resource shrinking and default icon-font tree shaking.
- Compiler debug symbols are retained outside the APK under `apps/jentra_employee/build/symbols/0.3.1-5/`, so diagnostics do not require bundling them into the download.
- Profile photos use only the supported JPEG and PNG decoder classes. The generic registry that referenced additional image codecs is no longer used. Photo cropping, orientation, metadata removal, size limits, protected storage and sign-out cleanup remain covered by the employee tests.
- English, Sinhala, Tamil, the supplied Jentra artwork and the existing Home/Profile/navigation experience remain included.
- [The repeatable build script](../../../../scripts/employee/build_small_apks.ps1) rejects debug runtime content, mixed architectures and APKs larger than 40 MiB. `-IncludeEmulator` additionally builds x86_64.

## Verification

| Check | Result | Evidence |
| --- | --- | --- |
| Employee app unit, controller, auth, photo and layout suites | **125 passed** | [employee-tests.log](employee-tests.log) |
| Employee app static analysis | **No issues found** | [employee-analyze.log](employee-analyze.log) |
| Previous development APK signature | Valid v2 signature | [baseline-signature.log](baseline-signature.log) |
| Optimized Android APK build and archive/signature inspection | In progress | [android-build.log](android-build.log) |

The SDK is Flutter **3.47.5** / Dart **3.13.4**. Tests ran serially with `--no-pub --concurrency=1`. The new format-limit regression rejects valid GIF and BMP input; existing tests cover JPEG/PNG, real EXIF removal, oversized/malformed input, photo replacement/removal, access revocation, account changes, return from the selector and sign-out cleanup. Current-source render tests cover phone layouts, English/Sinhala/Tamil and 200% text.

## Package identity and scope

These APKs use optimized release compilation with the development identity **`com.jentra.employee.dev`** and the existing local Android debug signer. Store distribution still requires a separate release signer. The build script passes the development switch explicitly through Flutter's `--android-project-arg` option and verifies the actual package identity/signature before publishing a deliverable; an ordinary release does not silently select the development signer.

This record covers local tests, compilation and packaged-artifact inspection. It does not claim signed-in acceptance or physical-device photo-selector validation. No live employee rows, business commands, account roles or database migrations were changed, and no phone installation or store upload is part of this work.
