# Employee browser preview

Firebase Hosting serves the Flutter employee bundle. Supabase remains the only sign-in and HR data service. This configuration contains only the public Hosting site and Supabase origin; it does not initialize Firebase Auth or web messaging. Android push is a separate native slice.

The existing live site is `https://jentra-os.web.app`. Use the preview wrapper first. It has no live deployment or promotion command. A preview channel is temporary and publicly reachable; real HR data remains protected by Supabase authentication and server authorization.

## Build, inspect and preview

After browser storage, photo selection and sign-in integration are complete, build from `apps/jentra_employee` using a private local file containing only public client configuration:

```powershell
flutter build web --release --no-pub --csp --no-web-resources-cdn --base-href=/ --dart-define-from-file=.env.employee-development.json
```

From the repository root:

```powershell
node --test tools/employee-web/prepare.test.mjs
node tools/employee-web/prepare.mjs stage apps/jentra_employee/build/web
```

The stage command prints a new immutable `releaseDirectory` under the ignored `.staging` folder. It validates the local rendering engine/bootstrap, expected Supabase origin, complete app bundle and absence of recognized server credentials/debug files. It records every public file's size and SHA-256. Inspection is a bounded credential check, not a substitute for source review. No previous build is removed.

Deploy that exact directory only after its contents are reviewed:

```powershell
./tools/employee-web/preview.ps1 -ReleaseDirectory '<printed releaseDirectory>' -Channel employee-qa-20261023
```

The wrapper revalidates public hashes and the exact Hosting configuration before calling `firebase hosting:channel:deploy` for project/site `jentra-os`, with a seven-day expiry. Use an existing private Firebase CLI login; never use or package the untracked Firebase admin key. The Firebase CLI command must be available on PATH, or supplied with `-FirebaseCommand`. No npm dependency installation is required by these scripts.

## Hosting policy

Every response uses `no-store` and `no-referrer`, including a confirmation/auth callback URL rewritten to the app shell. The CSP allows scripts/fonts/rendering resources only from this origin, with WebAssembly compilation and Flutter's runtime styles permitted. Network connections are limited to this origin and the exact Supabase HTTPS/WebSocket host. Framing, camera, microphone, location and payment access are disabled. No caching service worker is registered. Missing static assets are excluded from the SPA rewrite so failures remain real 404s.

The custom bootstrap resolves CanvasKit locally. Build with `--csp --no-web-resources-cdn`; unsupported external font fallback is intentionally blocked. English/Sinhala/Tamil fonts are already bundled by the shared design system. Firebase controls HTTPS and HSTS on its default domains; the configured HSTS value also applies if a custom domain is introduced.

## Browser integration gates

- The initial source explicitly excluded `kIsWeb` from Supabase setup and rejected browser use in `NativeEmployeeKeyValueStore`. Browser storage must be a deliberate adapter with approved retention; browser storage is not Android Keystore/iOS Keychain. Do not fall back silently to plaintext persistent sessions or drafts.
- The employee RPC gateway already imports narrow foundation/private-HR modules rather than native SQLite barrels. Browser support still needs an actual compile and authenticated preview test; source portability alone is insufficient.
- `detectSessionInUri: false` means the current native app does not consume browser confirmation/OAuth redirects automatically. Email/password sign-in needs no OAuth callback. Confirmation/recovery/OAuth support must explicitly consume the correct browser URL, preserve PKCE ownership, clear credentials from the address bar, and use exact preview/live redirect allowlist entries in Supabase. Do not use the Windows loopback callback in the browser or add a broad production wildcard for previews.
- `createBrowserEmployeePhotoPicker()` in `lib/src/data/employee_browser_photo.dart` is browser-only and must be imported conditionally with `dart.library.js_interop`. It uses the browser's one-file selector, secure-context checks and an 8 MiB/MIME bound. Existing controller normalization enforces actual JPG/PNG decoding, a 20-megapixel limit and identity before saving. The mobile entry point must continue to use its native picker.
- Verify refresh, back/forward navigation, a callback reload, lock/background masking, exact account/scope changes, own data isolation, photo selection/cancel, all three languages at 200% text, and browser screen readers before live promotion. CSP/header and auth checks must run against the actual HTTPS preview. A successfully staged bundle does not prove these behaviors or full HR capability completion.
- Inspect the existing live origin for a legacy Flutter caching worker before promotion. A new preview origin and a noncaching bootstrap do not remove a previously controlling live worker. If present, use targeted cleanup for that legacy Flutter worker and its public asset caches; do not unregister unrelated workers. Hosting cache headers alone cannot override a cached service-worker response.

References: [Firebase Hosting headers and rewrites](https://firebase.google.com/docs/hosting/full-config), [preview channels](https://firebase.google.com/docs/hosting/test-preview-deploy), [Flutter web initialization](https://docs.flutter.dev/platform-integration/web/initialization), and [Flutter cache/SPA guidance](https://docs.flutter.dev/platform-integration/web/faq).

## Optional authenticator panel

`EmployeeMfaPanel` in `lib/src/ui/employee_mfa_panel.dart` accepts a stable `EmployeeMfaGateway` instance and `Future<void> Function() onVerified`. Create `SupabaseEmployeeMfaGateway(client)` once for the signed-in application, and supply the panel when employee access reports `MFA_REQUIRED`. The callback can call the employee controller's `start()` to retry authorization. The panel itself never grants HR permission or bypasses a server entitlement.

The flow loads verified authenticators, offers explicit time-based setup when none exist, presents a manual setup key, and challenges the selected factor. Codes and setup keys remain in memory only. Backgrounding hides the key and clears code text; a nonsecret factor ID remains in memory for at most five minutes so a user can add the key in an authenticator app and return to verify. Account change and disposal revoke that intent. Explicit cancellation rechecks that the factor is still unverified before removal; verified factors are never removed by this flow. A setup response arriving after its UI intent was cancelled is eligible for the same unverified-only cleanup under the original account.

`onVerified` runs only after an AAL2 session belongs to the original actor and the panel is still foreground/current. A change to another actor is latched even if a late response later restores the original actor. The flow does not log or persist setup keys, codes or raw SDK error text. Manual setup avoids a QR-rendering dependency. English/Sinhala/Tamil copy is supplied; owner language review and authenticated native/browser acceptance remain integration gates. A panel recreated after background or expiry offers explicit completion of the current user's app-named unverified TOTP setups without recovering or redisplaying the secret. The [Supabase TOTP challenge API](https://supabase.com/docs/reference/dart/auth-mfa-challengeandverify) performs the challenge and verification; server policy remains authoritative.
