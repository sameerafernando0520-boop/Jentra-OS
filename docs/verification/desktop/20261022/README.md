# Jentra OS desktop delivery — 22 October 2026

Version **0.2.0+2201** is built for the owner's selected project,
`xpdoufauvrbdmxgngetv`, using the production app configuration. It is an
**unsigned release candidate**. Build, automated verification, native inspection,
backend rollout and owner acceptance are separate states.

## Install this version

The installer is
`build/desktop-release/0.2.0-2201-production-20261022-055822-3f88/Jentra-OS-0.2.0-2201-production-8a4eb8fd5d1a-Setup.exe`.
The same folder contains the portable ZIP, source manifest, build identity,
runtime manifest and delivery hashes. Run Setup, close any older Jentra window,
and reopen **Jentra OS** from Start. Check **About Jentra OS** for
`0.2.0+2201`, channel `production`, and the selected project's hostname.
The installer retains older bundles and does not terminate a running app.

Installer SHA-256:
`ea9bcf9fb43865f6f9c5b07347e489ff4b2be51f71d98334ad4fbdd9b6fab194`.

Portable ZIP SHA-256:
`5422bcc3826567bdfdb2e2f1593b3218c3ca3eb973142fedb1fa25d5bfae33fa`.

Source snapshot SHA-256:
`8a4eb8fd5d1a416a7d5f918d43353bc7fc3f88348fe4ecf43f12d19b9d116b4a`.
This covers 480 recorded build inputs, including the intended uncommitted work.
The final comparison found no drift between those inputs and current source.

## Desktop changes

- Installed release builds exclude the Design System tab, command-palette entry
  and deep route. Offline debug sessions retain the developer reference.
- Connected navigation groups permitted workflows by module. Workspace switching
  uses actual business, legal-entity and branch access. Refresh preserves still
  permitted selections; delayed results cannot restore another account's scope.
- The account icon opens a profile editor with name, picture, appearance, layout,
  security status, About and sign-out. Profile pictures are normalized and saved
  encrypted on this computer, partitioned by account/project. This does not add
  cloud photo synchronization.
- The connected command centre uses actual scoped queues and exact metrics.
  Finance has a functional overview linking permitted workflows. CRM reports the
  configured environment rather than a hardcoded development label.
- Business creation retains input and exact uncertain requests, verifies the
  committed membership and handles account changes without publishing stale data.
- Audit setup, team access and template authoring are connected to existing
  contracts. Evidence cancellation, owner remediation, independent retention
  release, carry-forward and immutable monitoring actions are exposed with their
  capability/state guards. Restored carry-forward drafts reload verified context;
  selected workpaper hashes are visible. Selecting a workpaper for these digest
  fields records its SHA-256 and does not upload its contents.
- Startup validates the configured project and public key and fails with a
  recoverable message instead of silently opening a sample-data workspace.
- Google PKCE and email confirmation include the Windows browser-return flow.
  An unreachable confirmation redirect can be recovered through **Need to confirm
  your email? → Link won't open?**, using the original email link privately in the
  app. No email token belongs in chat or diagnostic output.
- The executable and installer include all nine Jentra icon sizes. The package
  includes ten Microsoft x64 CRT redistributable DLLs from the installed Visual
  Studio toolchain, with recorded hashes and provenance.

## Verification

All current suites passed:

| Suite | Passing tests |
|---|---:|
| Desktop | 2,246 |
| Platform | 1,251 |
| Domain | 500 |
| Employee | 125 |
| Design system | 10 |

Final `flutter analyze --no-pub apps packages`: **No issues found**.
The machine-readable [verification record](verification.json) contains log hashes,
artifact identity, public Auth flags, icon verification and staging results.

Eighteen screen baselines changed after visual review. Changes cover permission
filtered navigation, the configured CRM environment label and the carry-forward
action. Light/dark and 200% frames were reviewed. The previous baselines are
backed up under `build/desktop-completion-20261022/reviewed-goldens`, with
before/after hashes in `reviewed-goldens.json`. All 460 pre-existing failure images
remain byte-identical. Exact golden comparison remains enabled; each run writes
new differences to a separate build folder.

The actual Setup.exe completed a workspace staging installation with exit 0 and
verified all 44 runtime files. Its launcher resolved this exact version and source
hash. No user shortcut, registration, existing installation or user data changed.
Fourteen synthetic installer checks additionally cover update, idempotence,
corruption refusal, downgrade/channel refusal, retained versions, rollback and the
shared installation lock. A corrupt rollback target leaves the current pointer
unchanged.

After the user allowed app access, Computer Use launched the staged executable.
The native title/icon, production startup, About metadata, account-creation
navigation, keyboard dismissal of About and scrollable confirmation-link help
were inspected. These observations establish pre-sign-in behavior only. A
permitted private sign-in was requested for authenticated navigation/profile
acceptance; no password, MFA code or email token was requested in chat.

## Open release gates

- The latest public Auth check on 22 October still reports **Google disabled**,
  email enabled and email confirmation required. Follow the dated update in the
  [Google setup guide](../../../development/google-sign-in-setup.md) to enable the
  existing Web client and save the exact callbacks. Real Google consent and email
  delivery/confirmation with a permitted account remain acceptance checks.
- The connected management account previously returned project access **403**.
  No test identity or assurance role was created through an administrative bypass.
  Current role assignment and genuine MFA need authorized account access.
- Authenticated native workflows, a real screen-reader walkthrough and owner
  sign-off remain open until performed. Unit/widget accessibility checks are not
  a Narrator walkthrough.
- The installer/app are unsigned. A trusted signing certificate and signing
  process remain a release requirement for a signed distribution.
- This work did not install migrations, deploy functions or change hosted Auth
  settings. Existing development evidence and workflows explicitly marked
  synthetic do not become verified production operations by changing the app
  channel. Their release gates remain in the respective module records.

No commit, push, secret-file inclusion or production backend mutation was made.
