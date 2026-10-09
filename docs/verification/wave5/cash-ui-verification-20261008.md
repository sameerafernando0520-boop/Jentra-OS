# Current cash UI verification — October 8, 2026

The post-edit cash source passes scoped Dart analysis, focused Wave 5 tests, Windows release compilation and fresh rendered inspection. The final comparison at `2026-10-08T10:21:26.968Z` records **`current_source_match: true` for all 1,047 selected source files**. This replaces the stale cash SDK evidence; Wave 5 remains incomplete.

| Gate | Fresh result | Evidence |
|---|---|---|
| Dart analysis | No issues in analytics source/tests, desktop continuation tests and main wiring | [Log](cash-ui-analyzer-final-20261008.log), [execution metadata](cash-ui-analyzer-final-20261008.json) |
| Domain analytics | 71 tests passed | [Log](cash-ui-domain-tests-20261008.log) |
| Platform analytics | 42 tests passed | [Log](cash-ui-platform-tests-20261008.log) |
| Desktop/controller/render | 94 tests passed | [Log](cash-ui-native-tests-20261008.log) |
| Windows release | Built successfully; 34 release files hashed | [Log](cash-ui-windows-build-20261008.log), [execution metadata](cash-ui-windows-build-20261008.json) |
| Cash renders | 12 variants passed; all 36 top/provider/lower PNGs inspected | [Full source/log/frame/build manifest](cash-ui-verification-20261008.json) |

Flutter `3.47.5` / Dart `3.13.4` ran sequentially against [a source-only snapshot](cash-ui-snapshot-final-20261008.json) at `build/w5c2`. Dependencies resolved from the existing offline cache, and Flutter test/build used `--no-pub`. Every test runner used `--concurrency=1`. The snapshot excludes local databases, secret files, existing build output and generated Windows plugin files. The final manifest compares the original snapshot, built snapshot and current checkout byte hashes.

The 207 tests include cash/immutable-assumption arithmetic, AP permission loss, actor and foreign-scope rejection, encrypted uncertain-command recovery, delayed revocation, governed export hash verification, and the surrounding Wave 5 workspaces. The cash-specific render assertions check the visible payable/missing-payroll status and the last exact balance. The initial analysis found a redundant null assertion in the new capture helper; it was corrected before the final snapshot. [The initial warning log](cash-ui-analyzer-20261008.log) is retained.

The cash variants use bundled Manrope, IBM Plex Mono and Material Icons fonts at **1024×720, 1440×900 and 1920×1080**, light/dark themes, compact/comfortable densities and **200% text**. Initial Tab focus reaches a text field in all twelve variants. Visual inspection confirms readable labels/status, wrapped controls at 1024px, scroll access to lower controls and exact `LKR 13.000002` closing balances on both fixture days after the `2.000000` payable outflow. The visible disclaimer and status retain the missing payroll/project-reimbursement due dates. Provider status currently shows contract codes; this rendering check does not establish product design acceptance.

Representative fresh evidence:

- [1024 light compact, lower controls and balances](cash-ui-frames-20261008/cash-1024-720-light-compact-lower.png)
- [1440 dark comfortable, provider status and balances](cash-ui-frames-20261008/cash-1440-900-dark-comfortable-providers.png)
- [1920 light comfortable, complete cash view](cash-ui-frames-20261008/cash-1920-1080-light-comfortable-top.png)

The retained executable is `build/w5c2/apps/jentra_desktop/build/windows/x64/runner/Release/jentra_desktop.exe`. Its SHA-256 is `369b12648d905f768cf36c1dd95a3c8fd69ba11988a28c71cad2d3fc38fa883f`; all accompanying release files are listed in the manifest.

These are source-scoped development tests and widget fixture renders. The executable was not launched against acceptance stores. Installed SQL, real authenticated native/MFA access, complete native keyboard navigation, process restart/revocation, actual export delivery/reopen, worker delivery, independent-session contention, target-scale load and owner acceptance remain separate gates. Full cash coverage still lacks authoritative payroll/project-reimbursement payment dates, the eight review migrations remain uninstalled, and the 13 shared dashboard/setup golden failures remain unresolved. Approved goldens were not regenerated.
