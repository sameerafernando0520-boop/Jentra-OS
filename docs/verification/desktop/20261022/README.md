# Jentra OS desktop delivery — 22 October 2026

Follow-up fixes and the `0.2.0+2202` candidate are recorded in the
[HR and desktop correction pass](../../hr-completion-20261022/README.md).
The build hashes and suite totals below belong to the earlier `2201` snapshot.

Version **0.2.0+2201** is built for the owner's selected project,
`xpdoufauvrbdmxgngetv`, using the production app configuration. It is an
**unsigned release candidate**. Build, automated verification, native inspection,
backend rollout and owner acceptance are separate states.

## Install this version

At 12:16 UTC on 22 October, after explicit owner approval, this exact Setup.exe
installed successfully for the Windows user at
`%LOCALAPPDATA%\Programs\Jentra OS`. Windows app registration and the
**Jentra OS** Start-menu shortcut now point to version `0.2.0+2201`.
The installed launcher verified all 44 runtime files and the recorded source
hash. The installer stopped no processes and changed no application user data.
The first subsequent native launch used the installed executable under this exact
versioned directory and displayed sign-in. After private user authentication,
later restarts restored the signed-in QA workspace; the profile editor confirmed
MFA for that session. The sanitized installation receipt is in
`build/desktop-completion-20261022/real-user-install.json`.

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
The comparison at the time of that build found no drift. Later correction-pass
changes have a separate snapshot and verification record.

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

The `2201` source suites passed:

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

Subsequent authenticated inspection confirmed that the account menu opens,
the profile editor displays the saved profile picture after an app restart,
and **Choose picture** opens the native file picker. Cancelling that picker
preserved the saved picture. No profile name, photo, email or preference was
changed during this check. The release sidebar has no Design System entry.

After the owner's separate approval, **Create workspace** was submitted once
for `jentra-qa-221022`, legal entity `QA`/`QA`, and first branch
`Head Office`/`HQ`. The app subsequently selected that workspace and displayed
**Multi-factor verification required**. This is an actual test tenant in the
owner-selected hosted project. It creates owner membership and a starter trial;
it is not a local fixture. No existing-company business transaction was posted.
The native result verified workspace creation and the MFA access gate. The user
subsequently completed setup privately and the installed profile screen confirmed
MFA; the correction-pass record lists the inspected business destinations.
No QR code, setup key or verification code was requested, read or recorded.

After the user reported authenticator setup complete, the former walkthrough
window was no longer open. Computer Use launched the installed executable and
verified the real installed sign-in screen, app title and icon. A private sign-in
was handed back to the user before inspecting authenticated business screens.
The source restores cached Supabase sessions before rendering and uses Windows
application-support identity rather than the executable directory. This source
review does not establish why the earlier session was unavailable; no user
session store or authentication contents were read.

## Open release gates

- The latest public Auth check on 22 October still reports **Google disabled**,
  email enabled and email confirmation required. Follow the dated update in the
  [Google setup guide](../../../development/google-sign-in-setup.md) to enable the
  existing Web client and save the exact callbacks. Real Google consent and email
  delivery/confirmation with a permitted account remain acceptance checks.
- The connected management account previously returned project access **403**.
  No test identity or assurance role was created through an administrative bypass.
  Normal authenticated onboarding created only the explicitly approved test
  workspace and its owner access. Assurance-specific reviewer/auditor grants and
  role acceptance still requires its normal authorized flow. Current-session MFA
  verification and signed-in restart restoration were observed subsequently.
- Native empty-workspace navigation is recorded in the correction pass. People,
  Assets, Projects and Service reached denied module states; populated HR and
  business transaction acceptance remain open. A real screen-reader walkthrough
  and owner sign-off remain open. Unit/widget accessibility checks are not a
  Narrator walkthrough.
- The installer/app are unsigned. A trusted signing certificate and signing
  process remain a release requirement for a signed distribution.
- This work did not install migrations, deploy functions or change hosted Auth
  settings. Existing development evidence and workflows explicitly marked
  synthetic do not become verified production operations by changing the app
  channel. Their release gates remain in the respective module records.

No commit, push or secret-file inclusion was made by this verification run.
The only hosted mutation in this acceptance step was the separately approved
test-workspace creation through the app's normal onboarding flow. No schema,
function, hosted Auth setting or existing-company data was changed.
