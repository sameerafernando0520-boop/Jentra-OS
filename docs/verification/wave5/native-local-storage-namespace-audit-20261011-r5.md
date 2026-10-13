# r5 Preview local storage namespace audit

Observed: 2026-10-11T11:03:43.206Z. Read-only public source, generated plugin registration and compiled PE inspection. No app, credential manager, account store, SDK or live service was accessed by this audit.

The bound r5 Preview uses the pinned Windows Dart FFI plugin and the default WindowsOptions(useBackwardCompatibility: false). Its DPAPI key file, SQLite draft database and preferences resolve beneath the verified com.jentra.test/JentraOS_WindowsTest_20261010-r5_Preview application-support identity. The legacy C++ shared-credential code exists but is bypassed by this default path. No namespace fix is justified for the current default configuration.

This inference depends on successful generated Dart plugin registration and the exact bound executable. Native plugin registration, path creation and save success require the separate genuine UI record. The product directory is on the same Windows account and is not a separate OS security boundary.

A valid Save preview example first persists an encrypted local draft, publishes the example in memory, then deletes the draft. Secure key and database files can remain. Refresh removes the published example; nothing is confirmed with a server. Empty online validation and Cancel stop before a draft write. Save draft persists an encrypted draft, while user-visible setup draft recovery after restart is not established by this screen.

Theme/density restart evidence is preference persistence only. Preview rows, save toasts, controlled memory tests and this audit cannot establish authenticated accounting, MFA, delivery, contention, load or owner acceptance.

## Current build binding

- Preview package record: docs/verification/wave5/windows-test-preview-package-20261010-r5.json SHA-256 09e1a0eccd61e791edef5579db991d92a7f319aa181051a0088c2c16d0e2ca74.
- Windows build record: docs/verification/wave5/windows-test-preview-build-20261010-r5-a1.json SHA-256 99ce8012e2e63a243b776e6d248996cb3419b1971b43e019e8855722b2866a9a; SDK exit 0, finished 2026-10-11T10:45:39.8898041Z.
- Both built and packaged executable SHA-256: 9c3a188cce375c5863d28c30e65b148f7f1c8114dab0499712b1dffcdbebfa51; 93,184 bytes. Fresh PE metadata inspection tool output 5b3bf8 at 2026-10-11T11:00:48Z.
- Generated Windows Dart registrant: build/w5win10r5/preview/apps/jentra_desktop/.dart_tool/flutter_build/dart_plugin_registrant.dart SHA-256 6aa978c2ad5af67c6c23abc40769802dbf07c3b32cde4aa4a78e379043954abf; line 205 registers FlutterSecureStorageWindows.
- Structured audit: docs/verification/wave5/native-local-storage-namespace-audit-20261011-r5.json SHA-256 c806fc271dc7ae33b873090df64ac2e75842e7b5ca7315d9f5f89fff384790bf.

## Public pinned source bindings

| Source | SHA-256 | Lines inspected |
| --- | --- | --- |
| apps/jentra_desktop/lib/main.dart | 648b3456944e3ccdafd2ef0c3ace8379889f0757b11aa7528e4c2b5ac3601fb5 | 79-110 |
| apps/jentra_desktop/lib/src/app_providers.dart | aa75e24065096a4a6bc0cad30ca8bc6b16c6f7ccd37cafdefa8a424e7d6ad5a6 | 91-122, 143-154, 179-210 |
| packages/jentra_platform/lib/src/draft_cipher.dart | 7487958ec72c210cc5a983bb37c8dd9112c93114443e681649c5bb268f6dee63 | 11-22, 29-61 |
| packages/jentra_platform/lib/src/local_database.dart | f81270ba958a5ef29b681dd52276094ad21c79291b909eddd4158ad1cd9565c3 | 43-52 |
| packages/jentra_platform/lib/src/draft_repository.dart | e666cb1e70cb998b05096d4eefaa724217827f2cbe428efe98658d7a4c359872 | 61-88, 148-156 |
| packages/jentra_platform/lib/src/runtime_config.dart | 53511face7ea2040344d75a9f83f476fe58f6067eeceb01f9230625232fe37eb | 9-24 |
| packages/jentra_platform/lib/src/supabase_platform.dart | 29d8ab8dc0fec6737d00598c09b0b63e33bd46a9d8ebea38a60f0a0a3e4861de | 11-28 |
| apps/jentra_desktop/lib/src/features/setup/business_setup_controller.dart | 789afbaf130f852eb07aa719d715689852e9a982350ca78a42d22190090e1e9b | 216-244, 258-327, 773-788 |
| apps/jentra_desktop/lib/src/features/setup/business_setup_screen.dart | 97501a3814b0f19351e422156cdb8b10bcddfe9609e85c55434b6bdbe6aeedfa | 1587-1607, 1707-1730, 1818-1863, 1886-1915 |
| apps/jentra_desktop/test/warehouse_setup_test.dart | c3879ff13c293d921a3dea2fe9d3a143211f393ff90e693aae5511811b463222 | 27-58, 76-127 |
| C:/Users/sheha/AppData/Local/Pub/Cache/hosted/pub.dev/flutter_secure_storage-11.2.0/lib/flutter_secure_storage.dart | b54695b49e2bfdd3573f2f9609a4e0f510f2a7b3bd0412f4981fc76afa612824 | 41-46, 82-83, 191-209, 351-374 |
| C:/Users/sheha/AppData/Local/Pub/Cache/hosted/pub.dev/flutter_secure_storage-11.2.0/lib/options/windows_options.dart | 9dbd46eb44b8e19040c7d1a537661921fa9d0c9176ce42242e49075ad3ca0d05 | 26-41 |
| C:/Users/sheha/AppData/Local/Pub/Cache/hosted/pub.dev/flutter_secure_storage_windows-4.2.2/lib/flutter_secure_storage_windows.dart | 7d758c20c2f92245bb308b18848cce07756e41f0eb7c05596412173437ffaf35 | 1-4 |
| C:/Users/sheha/AppData/Local/Pub/Cache/hosted/pub.dev/flutter_secure_storage_windows-4.2.2/lib/src/flutter_secure_storage_windows_ffi.dart | b3b07acd8398ef9ee73de40eb9e908404682ebec970b24d4caf884d77f87dc66 | 49-82, 86-145, 187-205, 257-290, 324-346, 412-464 |
| C:/Users/sheha/AppData/Local/Pub/Cache/hosted/pub.dev/flutter_secure_storage_windows-4.2.2/pubspec.yaml | 1952cbb0d75442f28fee1706fbac2b272157b2670284043eec7fc5a6b12f0ece | 27-32 |
| C:/Users/sheha/AppData/Local/Pub/Cache/hosted/pub.dev/flutter_secure_storage_windows-4.2.2/windows/flutter_secure_storage_windows_plugin.cpp | a832d629ac72979e0ae4c0012517e5af10f8eda0af045efac38746945034fa67 | 34-35, 259-303, 306-359, 534-594 |
| C:/Users/sheha/AppData/Local/Pub/Cache/hosted/pub.dev/flutter_secure_storage_windows-4.2.2/windows/CMakeLists.txt | 4a2f8955d46d092b3e8a93dd721053e20cb13c8a75b0b3a1ba3fc951d07df41b | 57-61 |
| C:/Users/sheha/AppData/Local/Pub/Cache/hosted/pub.dev/path_provider_windows-2.3.0/lib/src/path_provider_windows_real.dart | 965dbe53f21866b132c0445b89f5cc4ea23e11fbb1e61b8f58426d6cefab1034 | 119-120, 168-227, 250-263 |
| C:/Users/sheha/AppData/Local/Pub/Cache/hosted/pub.dev/shared_preferences_windows-2.4.1/lib/shared_preferences_windows.dart | c915eb47d8e9fa20ed23cc846cf7f1c3fe769d7162ed80acfdf07ae918a9c12f | 17, 333-345, 402-410 |

## Bounded genuine Preview walkthrough

1. Use only the bound r5 Preview executable and visible window; verify Development preview guidance, selected scope and empty account validation, then Cancel.
2. Select Catalogue and Warehouses; verify branch selector, empty warehouse validation, Cancel and optional dirty-cancel confirmation.
3. After the exact package identity is bound, an isolated local valid warehouse example can be saved. Observe its row and refresh disappearance; label this Preview retention and local-save evidence only.
4. Toggle theme/density, close the owned Preview window, relaunch that exact package and observe preferences through the UI.
5. Verify Finance overview warning and Procurement connected-workspace guidance. Treat actual posting, reports, bills and payments as separate blocked scenarios.
6. Use focused palette physical a/b/c, Ctrl+A then physical f as a modifier diagnostic; Escape, visible shell focus and one Ctrl+K retest. Do not infer keyboard root cause or native acceptance from widget tests.

Actual native evidence: pending and separate at audit time. This record changes no acceptance, installed SQL or runtime gate.
