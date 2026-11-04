# Native Jentra session handoff — 2 November 2026

The owner clarified that the signed-in dashboard is in the **installed Windows
Jentra app**. The built-in web tab is still at its separate sign-in screen.
Use the native app session for the genuine caller test; do not read or copy its
stored authentication data.

Windows Computer Use did not enumerate an open Jentra window. Filesystem checks
of the installed application metadata found:

- Install folder: `C:/Users/sheha/AppData/Local/Programs/Jentra OS`.
- Selected release: `0.2.0-2201-production-8a4eb8fd5d1a` (`0.2.0+2201`).
- Backend project: `xpdoufauvrbdmxgngetv`, matching the configured free provider.
- The `jentra_desktop.exe` hash matched its installed release manifest.
- The installed normal launcher starts that same executable from its release
  directory. No launcher scripts were run by terminal or UI automation.

One attempt to open that verified existing executable through Computer Use
timed out on **app-access approval**. A subsequent native-window inventory still
contained no Jentra window. Launch completion and the signed-in session are
therefore unverified. No stored session, password, private database, MFA secret
or user token was read; no app update or installation was performed.

The owner has been asked to open Jentra through the normal Windows shortcut,
restore its dashboard on this computer, and be ready to allow the Computer Use
permission prompt when the agent connects. Do not work around that access
gate with shell UI automation or token extraction.

Meanwhile, three existing forecasts in the approved synthetic branch were
verified, and the proposed 30-minute scope renewal passed five isolated checks
plus the actual hosted rollback-only allow/deny proof. The exact original scope
was restored, another branch remained denied, and schedule authority remained
inactive. The committed renewal is prepared but **has not been approved or
applied**. Reach the actual app session and confirm its workspace/source access
before requesting that separate bounded renewal.

The Cloudflare provider remains the deployment documented in the earlier
[activation result](ai-integrations-free-activation-result-20261102.md). Genuine
Jentra model usage/settlement and external delivery acceptance remain open.

Current handoff metadata is recorded in
`docs/verification/ai-integrations-free-20261102/native-session-handoff.json`.
