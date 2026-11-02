# Sign-in, verification mail and installer repair

Owner request: focus sign-in/account creation, use `jentra.system@gmail.com`
for verification mail, and repair a Setup.exe that does not open on other PCs.

## Scope and trace

Auth boundary: the 11 existing `packages/jentra_platform/lib/src/auth` helpers,
foundation gateway, Supabase initialization and desktop login. Dependencies are
Supabase PKCE/Auth, bounded token transport, session guards, public configuration,
router refresh and capability invalidation. Employee authentication has its own
implementation and is preserved.

Installer boundary: frozen source, Windows runtime/CRT provenance, manifest,
archive validation, bootstrap and shortcuts. Firebase Hosting provides the web
client and portable Windows ZIP; its current Spark plan rejected a raw EXE.
The native installer is supplied in the local release handoff for transfer to
another PC, which cannot use local workspace file links.
Initialization/login changes are necessary to handle browser returns before
routing and display safe errors. Packaging/Hosting changes deliver the native
installer. Business APIs, roles, applied migrations and push remain out of scope.

## Diagnosis before changes

- Baseline: **51** platform Auth tests and **39** desktop login/capability tests
  passed. These controlled tests do not establish hosted mail delivery.
- HIGH: browser signup/resend omit `emailRedirectTo`, coupling browser links to
  the backend default Site URL. Native Windows has an explicit nonce-bound
  loopback return that must be preserved.
- HIGH: the SDK clears browser callback URL parameters after success, but an
  exchange error can leave parameters in the address. Login has no bootstrap
  callback-failure notice. Browser input needs early URL cleanup, PKCE-only
  handling, account preservation and fixed safe failure messages.
- External blocker: the selected project's Auth management request returns
  **401**. No SMTP credentials are in this task environment. Current SMTP values
  are unconfirmed. Sender activation requires renewed access and a Gmail App
  Password entered privately; an email address alone cannot activate sending.
- MED: Setup is a .NET wrapper that starts hidden PowerShell and shows UI only
  after completion/error. These dependencies are confirmed; the exact other-PC
  launch blocker remains unknown without its Windows version/error. Installed
  Inno Setup 6 permits a visible native installer without those dependencies.
- MED: a stable HTTPS binary download is missing from the previous handoff.

## Verification plan

Test callback allow/deny parsing, PKCE, preserved sessions, safe notices and
browser redirects, plus existing native Auth and desktop consumers. Build from
an immutable snapshot. Run the actual native installer's staging-only mode with
shortcuts/registration disabled and compare every installed byte. Verify the
Firebase version and download hash; preserve earlier evidence and releases.

Do not claim Gmail delivery or successful installation on the other PC until
observed. Do not disable Windows security or package any mail/server secret.

## Implemented repair and evidence

- Browser signup/resend explicitly request the current secure origin root.
  Callback material is captured and removed before SDK initialization/routing.
  Only bounded PKCE codes are accepted. Existing sessions cannot be replaced by
  an incoming link; expired/invalid links display fixed safe recovery messages.
  Native nonce-bound loopback confirmation remains intact.
- The old .NET/hidden-PowerShell Setup wrapper is preserved in source. The new
  primary Setup is a visible Inno native wizard, with per-user versioned releases,
  app-local Microsoft CRT and SHA-256 verification. It needs neither .NET nor
  PowerShell. The existing portable ZIP gains a direct `Launch.cmd`.
- Builds **0.3.2+2305 Development** share exact allowlisted source SHA-256
  `55b9f85e70bc23465ab2f1022b69d529d00d8a130a71ef233d63f5d9c69189d5`.
  Frozen snapshots and earlier releases remain in `build/`.
- Full platform **1,280** and desktop **2,348** tests passed. Five missing-brace
  analyzer findings were then corrected without behavior changes; focused Auth
  suites passed **69 + 40** tests and full workspace analysis reported no issues.
- The actual final installer passed workspace staging with **48 files** verified;
  no registry, shortcuts, app launch or user-profile installation changed. The
  preserved legacy rollback suite passed **14** checks and archive verification
  passed **3** checks. This does not establish acceptance on another PC.
- Local and Firebase preview controlled browser checks cover signup, resend,
  exact PKCE verifier, password sign-in, preserved identity and rejected links.
  They intercept all Supabase HTTP/WebSocket traffic and create no real account
  or email. Early automation diagnostics exposed frame timing during focus and
  duplicate aria-live text; the harness now waits for editing focus and selects
  the exact rendered errors, keeping all text/security assertions. A separate
  transient internet disconnection is retained in the original logs.
- The owner approved the exact hosted redirect repair. Site URL and the two
  allowlisted web/native callbacks were saved and verified after reload in the
  authenticated Supabase dashboard. Email signup and required confirmation were
  also verified through the public Auth settings endpoint. Google remains off.
- Public SMTP fields for `jentra.system@gmail.com` were filled again at the
  owner's request, with **Save left untouched**. Credential entry/submission and
  actual Gmail inbox delivery remain private owner acceptance steps.

Final served hashes, preview/live checks, native staging proof and artifact
checksums are collected in
`docs/verification/auth-installer-20261029-2305/verification.json`. Firebase's
verified preview version is `3759c87a7a2ec554`; the previous live version
`96336e1a1ad6619c` is recorded for rollback. The employee site, database
candidates, applied migrations and push sender are preserved.
