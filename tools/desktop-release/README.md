# Windows delivery

These tools produce an unsigned, versioned Windows installer and portable ZIP from an isolated snapshot of the actual desktop source. They do not deploy Supabase, grant roles, sign in or certify production acceptance.

Run from the repository root after the intended source and tests are ready:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File tools/desktop-release/build.ps1 `
  -Channel production -PublicConfigPath .env.production.json `
  -ApprovedProductionProjectRef <owner-selected-project-reference> `
  -Version 0.2.0 -BuildNumber 2201
```

For development, use `-Channel development -PublicConfigPath .env.acceptance.json`. `-PrepareOnly` records the source snapshot without compiling. Build numbers must be 1–65535 because Windows version-resource components are 16-bit. A production build requires an explicit matching project reference; no project is inferred as production from its credentials or previous label.

The public config accepts only `JENTRA_ENVIRONMENT`, `SUPABASE_URL`, `SUPABASE_PUBLISHABLE_KEY` and optional `SUPABASE_PROJECT_REF`. Legacy keys must carry the `anon` role and matching project reference. Secret/service-account files, tests, existing builds and user stores are excluded from the snapshot. Config values are not printed or shipped as a JSON file. A public key is necessarily compiled into the client; service-role keys are rejected.

`prepare.mjs` records every allowlisted input hash, explicit resource overlay, source revision and dirty-source flag. Its source SHA-256 covers the sorted `path:sha256` records for the actual snapshot files, including uncommitted source changes. `build.ps1` passes this identity to Dart, uses locked offline dependencies and the direct Flutter tool snapshot, then builds `lib/main.dart`. `package.ps1` refuses a bundle outside that recorded snapshot or with different version/ProductName; it verifies every runtime byte in the ZIP and emits `delivery.json` with installer/ZIP hashes.

Packaging uses the recorded snapshot's installer sources. It also includes the app-local Microsoft Visual C++ x64 CRT redistributable from the installed Visual Studio instance recorded by CMake. `vc-runtime.ps1` requires that instance to be listed by Microsoft's installed `vswhere`, takes only its release `VC/Redist/MSVC/<version>/x64/Microsoft.VC*.CRT` DLLs, checks the Microsoft publisher metadata and fails if required runtime DLLs are missing. The runtime version, origin, file versions and SHA-256 hashes are recorded separately in `release-manifest.json`; these external SDK DLLs are not part of the application's source hash. No debug DLLs, DLL download sites or files copied from Windows system directories are used. Redistribution follows the installed Visual Studio redistribution rights and [Microsoft's runtime deployment guidance](https://learn.microsoft.com/en-us/cpp/windows/determining-which-dlls-to-redistribute).

Output is under `build/desktop-release/`. Keep `delivery.json`, `source-manifest.json`, build logs, Setup.exe and ZIP together when handing over a release. The source snapshot uses a short sibling `build/b......` directory to limit Windows path lengths.

## Install and update

Double-click Setup.exe, or extract the ZIP and run `Install.cmd`. Setup runs per user, needs no administrator and creates a Start menu shortcut and Windows app registration. Runtime files install side by side under:

- Production: `%LOCALAPPDATA%\Programs\Jentra OS`
- Development: `%LOCALAPPDATA%\Programs\Jentra OS Development`

The installer verifies every declared runtime file, rejects undeclared files/channel switches/downgrades, retains older bundles and atomically switches `current.json`. The launcher resolves that pointer, verifies every manifest runtime hash and starts exactly that bundle with its own working directory. It never terminates an existing app; close the older window yourself and reopen the Start shortcut. An already running older process does not become the new release automatically.

Development snapshots overlay only Windows `ProductName` to `Jentra OS Development`; production keeps `Jentra OS`. This is recorded in the source manifest. The installed `path_provider_windows` implementation derives the application-support path from VERSIONINFO CompanyName/ProductName, and secure storage uses that support path. Existing sessions/settings/drafts are not migrated or erased. A new development identity can require signing in again; runtime acceptance of the resulting store path is a separate check.

`Rollback.ps1 -ConfirmRollback` takes the installer's exclusive lock and verifies every byte of the retained previous desktop bundle before atomically selecting it. A corrupt bundle or active install leaves the current pointer unchanged. It does not revert backend or user data. Uninstall removes shortcut/registration and retains bundles and user data for recovery. Signing remains an external release gate: the generated installer and app are explicitly marked unsigned.

## Safe verification

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File tools/desktop-release/verify_installation.ps1
```

This creates visibly synthetic fixture files under a new workspace `build/` directory and checks install, update, exact launcher target, idempotence, prior-bundle retention, rollback, shared-lock refusal and corruption/path/channel/downgrade refusal. It specifically verifies that a corrupt retained DLL cannot break the working pointer during rollback. It starts no application and changes no user shortcuts or registry keys.

To verify a real Setup.exe without changing the user's installation:

```powershell
Start-Process -FilePath <Setup.exe> `
  -ArgumentList '/quiet','/staging-root="<new-workspace-build-folder>"' `
  -WindowStyle Hidden -Wait -PassThru
```

The staging override always disables shortcut creation and registration. Inspect `installation-receipt.json`; then run the staged `Launch.ps1 -VerifyOnly` to inspect the resolved version without launching. Do not claim a synthetic staging check establishes authenticated native acceptance or an actual user-profile update.
