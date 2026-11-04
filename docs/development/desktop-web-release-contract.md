# Windows and browser delivery contract

29 October 2026. Owner-requested installable Windows client and web app. The
existing business modules, scoped Supabase authority and candidate boundaries
remain unchanged. These artifacts are Development builds for the existing
configured target; they do not certify a company launch.

## Functional requirements

- WR-01: Build the actual desktop entrypoint and preserve existing dirty work,
  migrations, user profiles and prior artifacts. Windows delivery includes an
  installer, portable package, source identity and runtime hashes.
- WR-02: The browser runs the same scoped business UI and authoritative gateways.
  Native SQLite and filesystem dependencies must be conditional adapters.
- WR-03: Browser drafts and reference bodies remain encrypted and persist across
  restart. A missing secure context, persistence or key store must block writes;
  an in-memory fallback must never acknowledge durable command recovery.
- WR-04: Browser storage must be separate by backend project. A second browser
  tab must not overwrite the active tab's pending command recovery.
- WR-05: File downloads retain existing authorization/revalidation and byte
  limits. A browser download replaces only the unavailable native save chooser.
- WR-06: Web packaging includes the pinned compatible SQLite WASM/worker,
  static assets, safe hosting headers and usable launch/deployment instructions.
- WR-07: Installation and browser smoke verification must use synthetic staging
  or a fresh browser context. Do not sign in, alter existing accounts, deploy
  database candidates or activate any sender.

## Non-functional requirements

Keep locked dependency versions. Record SHA-256 provenance for source and output.
Browser delivery requires HTTPS, with loopback HTTP permitted for local testing.
Serve WASM with its correct MIME type; do not cache authentication/private API
responses. Do not ship secret config, signing keys or user stores.

## Acceptance criteria

Given the frozen source, Windows builds and its staged installer verifies every
runtime file and resolves the intended version without updating the user profile.
Given a fresh browser, the compiled app starts and provides its actual sign-in
surface without native-library errors. Browser persistence tests save encrypted
data, close/reopen the database and recover the same immutable command. Missing
persistence and a competing tab fail closed. Existing native storage and file
authorization regression tests continue passing.

## Edge cases

Unavailable browser APIs or quota errors retain unconfirmed work. Changed auth,
scope or connectivity must keep existing invalidation behavior. Existing install
roots, artifacts, occupied ports and open user browser sessions are preserved.

## API contracts

No backend/API contract changes. `JentraLocalDatabase.open()` chooses a persistent
native or browser executor. The existing save destination abstraction chooses a
native path or a browser filename before existing authorized byte delivery.

## Data models

The existing encrypted drafts/reference tables and receipt envelopes remain
unchanged. Browser database names bind the configured project; no parallel sales,
finance, HR or account model is introduced. Delivery manifests record source,
channel, configured project, artifact hashes and verification limits.

## Out of scope

Production target selection, migration installation, sender activation, signing
identity, statutory payroll and real company acceptance remain separate gates.
The unfinished Sales app is not represented as complete by either artifact.
