# Jentra Sales Hosting

Project `jentra-os`, dedicated target `sales`, site `jentra-os-sales`.
The Employee `jentra-os` and desktop `jentra-os-desktop` sites are independent.
Firebase serves the client; Supabase remains the identity/business authority.

From the repository root, `prepare-config.mjs` reads the existing private local
configuration and writes only an allowlisted public URL/client key under ignored
`build/sales-release`. The key must be publishable or an anon JWT for the exact
existing project. No admin key, signing identity or server secret is needed.

```powershell
node tools/sales-release/prepare-config.mjs
cd apps/jentra_sales
$salesWebOutput = Join-Path (Resolve-Path ../..).Path 'build/sales-release/web-new'
flutter build web --release --no-pub --csp --no-web-resources-cdn --no-wasm-dry-run --optimization-level=1 --output=$salesWebOutput --dart-define-from-file=../../build/sales-release/public-client.json
cd ../..
node tools/sales-web/stage.mjs build/sales-release/hosting-new build/sales-release/web-new
```

Staging refuses an existing release directory and inspects only the compiled
web tree. It records SHA-256 for public files and never copies `.env` or admin
configuration. Review the generated public manifest, browser interactions and
headers before promotion. For the exact returned release directory:

```powershell
cd <releaseDirectory>
$env:FIREBASE_HOSTING_UPLOAD_CONCURRENCY = '2'
firebase hosting:channel:deploy sales-20261030 --project jentra-os --only sales --expires 7d --no-authorized-domains --config firebase.json
```

The user authorized publishing this initial app. After preview verification,
promote the **exact finalized preview version** with Hosting clone to
`jentra-os-sales:live`, then repeat the live content/browser checks. Subsequent
updates should retain the live version identity for rollback. Frontend rollback
does not roll back backend or stored drafts. No caching service worker is used.

Same-origin scripts/rendering/fonts, no-store, frame denial, no-referrer and an
exact Supabase network allowlist are configured. No Firebase Auth change is
required. Downloads contain the development APK inside a ZIP, its checksums and
installation notes. An absolute web output path avoids the Windows shader-output
failure observed with a relative path. Low upload concurrency avoids the
connection timeouts observed with the CLI's default concurrency.

The first client is a preview; publishing it does not establish installed
portfolio APIs, real sales posting or verified customer email delivery.

The current deployed version is `ff9d9bdb19326df5`. Its exact public manifest and
bounded verification results are in `docs/verification/jentra-sales-20261030`.
Default Chrome startup/reload is intermittent from this network; live flows
pass with the diagnostic `tcp` mode, while normal live acceptance remains open.
A preview-only `Alt-Svc: clear` experiment was ignored by the Hosting edge and
reverted. Do not treat that experiment as a fix or change users' browser settings.

Browser verification waits for visible app controls after DOM readiness, as
recommended by [Playwright's navigation documentation](https://playwright.dev/docs/api/class-page#page-goto-option-wait-until).
Flutter semantic inputs need focus/frame synchronization and actual keyboard
events; DOM-only fill did not update the quantity controller in this build.
The harness records cancellation of requests already in flight before its own
reload/teardown separately from service/network failures.

References: [Firebase multisite Hosting](https://firebase.google.com/docs/hosting/multisites)
and [Flutter web bootstrapping](https://docs.flutter.dev/platform-integration/web/initialization).
