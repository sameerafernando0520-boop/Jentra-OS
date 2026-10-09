# HR help icon update — Jentra Employee 0.2.1

The user's browser marker selected the headset on the Home HR help card. The employee app now uses an outlined question-bubble icon (`Icons.contact_support_outlined`) on Home and the Work, Pay and More HR help links. The original Jentra semantic colors, icon sizes and guidance routes remain in use.

## Verification

- Existing UI/navigation and current-source render tests: **18/18 passed**, including thirteen phone renders, both themes, enlarged Sinhala/Tamil navigation and account/lifecycle guards. See `ui-tests.log`. No new test was added for this cosmetic change; the earlier 99-test feature baseline is recorded separately under `ui-ux-20261009/`.
- Flutter analysis: **No issues found**, `analyze.log`.
- Standalone HTML: thirteen embedded PNGs decoded and matched to the new renders; zero external assets, `preview-validation.json`.
- The localhost browser displays version 0.2.1 and the question-bubble icon on the HR help card. This is a fixture preview, not a live employee sign-in.
- Android development APK: build succeeded in **68.2 seconds**, `android-build.log`. Native inspection confirms version 0.2.1/code 3; the debug APK v2 signature verifies.

## Artifact

`apps/jentra_employee/build/deliverables/Jentra-Employee-0.2.1-development.apk`

- Bytes: **175,402,059**.
- SHA-256: `744265f25157812ad86c66a94967c306f1dfb52f6f605b3e49f55a27cba61297`.
- Application ID: `com.jentra.employee.dev`. This is a development build; no device installation was performed.
- [Self-contained preview](employee-app-preview.html). The previously reviewed localhost URL also serves this updated HTML.
- The original version 0.2.0 HTML is preserved as `../ui-ux-20261009/employee-app-preview-0.2.0.html`; its original PNGs and APK remain intact.

## Scope and packaging

This update changes the HR help glyph, app patch version, preview output path and associated documentation. It does not introduce chat, message sending, HR-case submission, authentication or backend changes. Remaining employee-service and device-acceptance gates are unchanged from [the UI upgrade](../ui-ux-20261009/result.md).

The development web host also built successfully in **99.8 seconds**, `web-build.log`; it retains the existing nonfatal Cupertino icon-font warning and intentionally disabled browser authentication. `source-before-build.json`, `source-after-build.json` and `source-comparison.json` confirm **327/327 files unchanged** across the 18 UI checks, clean analysis and both builds. The Git index and concurrent Wave 5 work are preserved.
