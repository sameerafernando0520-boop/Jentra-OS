# Windows and browser delivery verification

29 October 2026. Actual client artifacts for **0.3.1+2302 Development** are in
`dist/Jentra-OS-0.3.1-2302-Development`. Open its `index.html` or `START HERE.md`.
No production completeness certificate is claimed.

## Release identity

The original workspace remains on `codex/employee-web-android-push`, revision
`678584047d7f4a5fd0e50192b2d3ea576f33b1c7`, with its existing uncommitted work.
Builds use immutable allowlisted snapshots, public-only configuration, pinned
dependencies and artifact hashes. Applied migrations and the employee push
candidate were preserved. Source was not committed or pushed by this delivery.

Windows source SHA-256:
`2d43a02861fd4e82d826e920a4515ff8d8f2bfce0808e587c93d87d79e1aa6b3`.
The web snapshot has the same compiled application sources, with later fixes
only to web packaging/launcher scripts. `delivery.json` records both complete
source identities and the exact script differences. Do not reinterpret earlier
frozen manifests as hashes of today's entire dirty workspace.

| Artifact | Bytes | SHA-256 |
| --- | ---: | --- |
| Windows Setup.exe | 25206272 | `4648ccb89e5cecf5a83888f1443dca22be5a6d5568538e2d6f8ce6bf5ac6c073` |
| Windows ZIP | 25115303 | `652773d6f2aea62b15622fa13f5f28de0ebe703c1273a3cb43e7a2e5e9715a45` |
| Web ZIP | 21289938 | `ca94bef8913ef3cfb6c44716d16d1496c9581cef28216ea9195aeb3e2972d928` |

## Observed checks

- Windows release compilation succeeded. All **47** packaged runtime files
  were verified. The actual Setup.exe installed into a new synthetic workspace
  staging root; `Launch.ps1 -VerifyOnly` resolved the correct version and hash.
  No user-profile installation, shortcut or registry changes were made.
- **14** installer/rollback assertions and **3** ZIP assertions passed. The ZIP
  regression covers canonical entry paths, byte identity and overwrite refusal.
- **1,262** native platform tests and **73** focused desktop tests passed after
  the browser adapter changes. These cover native persistence, recovery,
  company/access, authentication capabilities and protected file/export paths.
- Workspace static analysis passed with no issues. The final shared browser
  scenarios also compiled successfully as release JavaScript.
- Actual compiled web app served from the packaged loopback launcher. Chrome
  rendered the real sign-in screen at 1440 by 960 with accessibility semantics.
  Required JS/SQLite/renderer assets returned 200 with correct MIME types,
  no-store and nosniff. The secret-config request returned 404. No console,
  runtime or failed-request errors occurred. See `web-smoke.json` and the PNG.
- **Four** actual browser storage scenarios passed with no console errors:
  non-extractable persisted key/encrypted record/reopen; project namespace and
  competing lease protection; missing key preserves ciphertext; real SQLite
  close/reopen restores the exact encrypted immutable administration command.
  See `browser-storage-probe.json` for scenario and source hashes.

The installed Flutter 3.47.5 browser unit harness returned 404 for its local
CanvasKit files on Windows. A scoped diagnostic served the exact cached SDK
renderer to the owned test browser, without substituting application responses,
but the harness still did not complete. The same four scenarios were extracted
into one shared library and executed by the compiled synthetic probe with the
normal packaged renderer. They are reported as compiled browser scenario
results, not as a passing Flutter browser unit-harness run. Earlier failed and
stalled diagnostics remain in `build/`.

Packaging defects fixed: .NET ZIP backslash entry names, PowerShell treating a
Flutter deprecation warning as fatal, and Windows PowerShell evaluating
`$PSScriptRoot` too early in a parameter default. Existing business gateway
authority, native SQLite behavior and private-file reauthorization were retained.

## Boundaries

Both clients use the existing Development target `xpdoufauvrbdmxgngetv`. The
Windows artifact is unsigned. No real account was used by these smoke tests,
and native authenticated business acceptance was not performed. The local web
preview is not Internet hosting. No database candidate was installed, sender
deployed/activated, company/account deleted or real business record mutated.

Production target selection, the separate Sales mobile app, reviewed backend
rollout, hosted AI and employee push, statutory payroll, restoration/monitoring,
signing and company pilot acceptance remain open. See
`docs/user-guide/feature-completeness.md` for the detailed inventory.

## Reproducibility

Build Windows with `tools/desktop-release/build.ps1` and web with
`tools/web-release/build.ps1`, using the approved public-only Development config.
The source manifests identify the exact frozen inputs. Browser probe source is
`browser_storage_probe.dart`, importing the shared scenarios from
`packages/jentra_platform/test/support/browser_storage_scenarios.dart`. Compile
it with Flutter's web builder into a separate app-local build directory, serve
it with `Serve-Web.ps1` on the isolated loopback port, then run `storage-probe.mjs`.
The probe authenticates no user and creates only synthetic local browser data.
The helper closes its fresh browser context and its temporary probe server.
