# Install and open Jentra OS

Release: **0.3.2+2305 Development**, prepared 29 October 2026.

Open [Jentra OS](https://jentra-os-desktop.web.app) in current Chrome or Edge.
The [Windows download page](https://jentra-os-desktop.web.app/downloads/)
provides the portable ZIP. The separate native **Setup.exe** is in the local
`dist/Jentra-OS-0.3.2-2305-Development` handoff folder. Transfer that new file to
the other PC; a local workspace link cannot be opened from another computer.

These are working client builds for the existing Development Supabase project.
The installer is unsigned. This delivery does not approve production payroll,
install database candidates, activate push, or certify a company launch.

## Windows desktop

1. Copy the new file ending in **2305-development-55b9f85e70bc-Setup.exe** from
   the handoff folder to the other PC. Use Windows 10/11, 64-bit.
2. Double-click it to open the visible native wizard. It installs for your
   Windows user without administrator rights, .NET or PowerShell. Close an old
   Jentra OS window yourself before opening the updated app.
3. Open **Jentra OS Desktop (Development)** from Start. The native installer
   uses a separate folder and retains earlier release directories.
4. Sign in with your own verified work account. Complete MFA where required.
   Choose the correct company group, legal entity and branch.
5. A new account needs an invitation or the permitted first-business setup.
   Follow the [company operating guide](README.md) and
   [Company & access addendum](company-access-administration.md).

Portable alternative: download the Windows ZIP, extract **the whole ZIP**, and
double-click **Launch.cmd**. Keep `Payload` and all its files together. This
launches the same runtime directly, without .NET or PowerShell. The preserved
`Install.cmd`/PowerShell scripts are a separate legacy option. The ZIP does not
contain the native installer.

The default installation is under
`%LOCALAPPDATA%\Programs\Jentra OS Desktop Development`. Native releases are
retained under `releases/`. To recover an earlier native client, open its retained
executable or use its retained installer. The older PowerShell installation uses
`Jentra OS Development` and its own `Rollback.ps1`; keep those recovery methods
with their matching packages. Neither method rolls back a database schema.
Uninstall removes this client installation and registration, not business records
in Supabase. Back up and reconcile pending work before changing installations.

If Windows blocks this unsigned build, have company IT review it and its
checksum. Do not disable Windows security. The actual installer passed a local
staging check; successful installation on the other PC still needs confirmation.

## Sign in and create an account

1. Existing account: enter the work email and current password, then select
   **Sign in securely**. Use the eye to show or hide the password.
2. New account: select **Create an account**. Use at least **12 characters**,
   including letters, numbers and symbols. Repeat the password; each field has
   its own eye button.
3. After submission, check the email inbox and spam folder. Open the newest
   confirmation link in the **same browser** used to create the account. For
   desktop signup, keep the app open while opening the email link.
4. If the link expired, return to sign-in, choose **Need to confirm your email?**,
   and resend. Wait for the cooldown and use the newest message.
5. If a link will not open, use the recovery panel and copy the **original link
   from the email**. The localhost or dashboard address in the browser is not a
   confirmation link. If already confirmed, use normal sign-in.

As of 30 October, the intended sender is **Jentra OS <jentra.system1@gmail.com>**.
After the owner privately saved the credentials, a fresh authenticated view
verified custom SMTP enabled, this sender address and username saved, host
`smtp.gmail.com`, port `465`, a hidden stored password and Save disabled.
No password was read. Real new-account inbox delivery remains unverified.
Never paste an App Password or an email confirmation link into chat.

The approved Site URL is `https://jentra-os-desktop.web.app/`. The allowlist now
contains that exact URL and the native nonce callback
`http://127.0.0.1:56327/auth/callback/*`. Browser codes are removed from the
address before routing; an incoming link cannot replace an existing session.
Google sign-in is enabled as of 30 October, and its public authorization check
redirects to the expected Google client and Supabase callback. Complete
**Continue with Google** in the browser; a full sign-in and return to Jentra OS
still need acceptance.

## Web application on this computer

1. Extract the **Web.zip** completely. Do not run it from inside the ZIP.
2. Double-click **Start Jentra OS Web.cmd**. Keep its console window open.
3. The browser opens `http://127.0.0.1:8485/`. Use current Chrome or Edge and
   sign in with your own company account. Internet is needed for server actions.
4. Close the console window to stop the local server. Reopen the same launcher
   and address to return. It listens only on this computer and needs no admin.

If port 8485 is occupied, keep the existing service. Run
`Serve-Web.ps1 -Port 8486 -OpenBrowser` from the extracted folder. The chosen
address is a separate browser storage origin: return to that same address while
recovering an unconfirmed command.

Use one editing tab per backend project. Permit persistent browser storage.
Private browsing, denied storage or unsupported persistence can block saving.
Do not clear site data or change origins while any command is unconfirmed.
Browser drafts use persistent encrypted storage and a non-extractable WebCrypto
key; clearing browser data can still destroy local recovery.

## Publish the web app for company access

The Web ZIP contains the actual compiled app in **site/**. Firebase hosts the
browser client at the HTTPS address above. Localhost remains for this computer
only. This project's Spark plan blocks raw `.exe` hosting, so the native installer
is supplied in the local handoff; the hosted Windows download is the portable ZIP.

Have the release owner select the approved backend and HTTPS hostname before a
company rollout. Publish only **site/** to a reviewed static host. Retain the
packaged `_headers` and `_redirects` on a host that supports them, or configure
equivalent CSP, no-store, content-type and SPA routing rules. WASM files must
have `Content-Type: application/wasm`; missing asset requests must remain errors.
Review email/OAuth callback allowlists for the actual hostname. Never upload
`.env` files, signing material, build configuration files or local user stores.

The bundled renderer and SQLite assets are local to the site. The app still
needs its configured Supabase APIs. This is not an offline business server.
Firebase hosts the client; Supabase continues to handle accounts and company
data in the existing Development project. The [Firebase runbook](../../tools/desktop-web/README.md)
records deployment, verification, rollback and remaining hosted Auth checks.

## Before real company launch

Review the [feature completeness record](feature-completeness.md) and
[launch readiness record](../development/launch-readiness-20261028.md).

- Company/access and employee backend candidates need a reviewed rollout and
  authenticated acceptance on the selected target. Missing RPC/schema errors
  are not fixed by repeatedly reinstalling the client.
- The separate Jentra Sales app remains unfinished. Its approved scope includes
  company-approved discount requests and verified email links for distinct
  customer acceptance and delivery acknowledgement.
- Hosted AI, employee push activation, statutory payroll review, restoration,
  monitoring, signing and company pilot acceptance remain open launch gates.
- Named test-company cleanup still requires a verified current database
  inventory. This delivery deletes no stored companies or accounts.

Do not process real salaries or treat these clients as a production-readiness
certificate. Keep the release identity and checksums with your pilot evidence.
