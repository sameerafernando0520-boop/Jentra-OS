# Jentra OS on Firebase Hosting

Firebase project **jentra-os**, Hosting site **jentra-os-desktop**, deploy target
**desktop**. The company OS has its own site so the employee site's
`tools/employee-web` configuration and `jentra-os.web.app` stay separate.

The web client continues to use Supabase project `xpdoufauvrbdmxgngetv` for
authentication, authorization and business data. This hosting setup does not
introduce Firebase Auth, Firestore, Cloud Functions or messaging activation.
The current client is a **Development** build.

## Build and stage

From the repository root, build a new frozen web release:

```powershell
./tools/web-release/build.ps1 -PublicConfigPath .env.acceptance.json -Version 0.3.2 -BuildNumber 2305
node tools/desktop-web/prepare.mjs stage '<web-release-output-directory>' '<matching-native-release-directory>'
node tools/desktop-web/prepare.mjs verify '<printed-hosting-release-directory>'
```

Staging copies only the reviewed static site and checks every source hash.
Private/debug names, private keys and recognized privileged server credentials
are rejected using the existing employee public-artifact scanner. The ignored
Firebase administrator key is not opened or used. Staging adds only public
release identity, robots and 404 files. The manifest and CLI records remain
outside `public/`. A new directory is used for every stage.

Optional Windows downloads require the matching source identity and a successful
actual native-installer staging proof. The existing portable ZIP is published
unchanged, with SHA-256 and release identity. The separate native Setup.exe stays
in the local handoff. The current Spark plan forbids raw EXE/DLL/BAT/APK/IPA
uploads; staging rejects these extensions. Do not rename them to evade that rule
or change the billing plan as part of a web release. See the
[Firebase executable-file policy](https://firebase.google.com/docs/hosting/faq-and-troubleshooting#cannot-store-executable-files).

## Preview, verify, then publish the exact version

Use the existing Firebase CLI login. From the printed Hosting release folder:

```powershell
firebase hosting:channel:deploy desktop-qa-20261029-2305 --only desktop --expires 7d --no-authorized-domains --project jentra-os --config firebase.json --non-interactive --json
```

The result supplies the actual preview URL and version. From the repository
root, verify that exact HTTPS origin:

```powershell
node tools/desktop-web/verify-hosted.mjs '<hosting-release-directory>' '<returned-preview-origin>' preview
node tools/desktop-web/verify-auth.mjs '<returned-preview-origin>' '<new-evidence-directory>' preview
```

Only after `preview-verification.json` passes, promote the preview's version:

```powershell
firebase hosting:clone jentra-os-desktop@<verified-version-id> jentra-os-desktop:live --project jentra-os --config firebase.json --non-interactive --json
```

Run the same verifier against `https://jentra-os-desktop.web.app` with label
`live`. It compares **every served file** with its staged SHA-256, verifies
MIME/no-store/CSP/404/deep-link behavior, and checks the actual signed-out UI,
password eyes and invalid signup rejection in a fresh Chrome context. Backend
write requests are blocked by the verifier; it never signs in, registers an
account or sends a confirmation email. Real-account acceptance remains separate.
`verify-auth.mjs` intercepts every Supabase HTTP/WebSocket request and checks
actual signup, resend, PKCE verifier, password sign-in, existing-session
preservation and rejected callbacks. Synthetic sessions never reach a live
company API. Both verifiers wait for Flutter editing focus before sending keys
and retain exact-text assertions.
Use the finalized version ID returned by the preview deployment, such as
`96336e1a1ad6619c` for the October 29 build, so a channel update cannot change
the content between verification and promotion.

## Hosting controls

The configuration restricts executable resources to the site and network calls
to the exact Supabase HTTPS/WebSocket origin. Renderer, fonts, SQLite WASM and
Drift worker are bundled. WASM has its explicit MIME type. Every response is
no-store with nosniff, frame denial and no-referrer. Missing static/private files
remain 404 rather than returning the app shell. The new origin has no legacy
service-worker migration; the app does not register a caching worker.

No database migrations, functions, senders, Firebase Auth domains or Supabase
settings are deployed by these Hosting commands. Never run an unscoped Firebase
deploy from another project's directory. Keep all manifests and inspection logs
outside `public/` and retain the prior release identity.

## Password and sign-in scope

The updated account-creation form requires at least **12 Unicode code points**,
letters, decimal digits and punctuation/symbols. Password and confirmation have
separate accessible show/hide buttons. Backgrounding or switching modes hides
revealed passwords; mode changes clear the inputs. Existing password sign-in is
still checked by Supabase and is not rejected by the new signup rule.

This is client validation. The authoritative Supabase password-strength policy
must also be reviewed/configured in the approved project before company launch;
Hosting cannot enforce an Auth API policy. Google provider configuration and
exact email/OAuth callback allowlists for the actual Firebase domain also remain
hosted Auth acceptance gates. They were not silently changed. Existing manual
confirmation-link recovery is retained.

Do not transfer or clear pending local recovery when moving from localhost to
Firebase. Browser storage is origin-scoped: finish or reconcile unconfirmed
commands on the original address, then sign in at the new HTTPS site.

## Recovery

Before subsequent promotions, record the current live version. Firebase Console
Hosting release history can roll back **jentra-os-desktop** to a prior verified
release; verify its served hashes afterward. A known-good retained preview can
also be cloned to `jentra-os-desktop:live`. Do not change the employee site.

The first release has no earlier live application version. If it must be
withdrawn, an authorized operator can explicitly disable this site using
`firebase hosting:disable --site jentra-os-desktop --project jentra-os --config firebase.json`.
This command is documented for recovery and is not run by the deployment flow.
Frontend rollback does not roll back database schema or browser draft formats.

References: [Firebase Hosting configuration](https://firebase.google.com/docs/hosting/full-config),
[multisite deploy targets](https://firebase.google.com/docs/hosting/multisites),
[version cloning and rollback](https://firebase.google.com/docs/hosting/manage-hosting-resources),
and [Supabase password security](https://supabase.com/docs/guides/auth/password-security).
