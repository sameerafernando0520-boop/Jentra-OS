# Jentra app installation and first use

Use the 12 November 2026 app handoff for Windows, Android and browser setup. Keep the downloaded files and `CHECKSUMS.sha256` together. On Windows, use `Get-FileHash -Algorithm SHA256 -LiteralPath '<file>'` in PowerShell and compare the result with the corresponding manifest entry. Transfer the files themselves when setting up another computer or phone.

## Windows

### Jentra OS · 0.3.3+2306

1. On Windows x64, close any open Jentra OS window and run `Jentra-OS-0.3.3-2306-Development-Setup.exe`. Follow the wizard, then open **Jentra OS Desktop (Development)** from Start.
2. For a portable install, extract `Jentra-OS-0.3.3-2306-Development-Portable.zip` to a short local path and open `Launch.cmd`. Keep the `Payload` folder beside the launcher.
3. Sign in with your own verified work account and complete the authenticator check when prompted. Choose your company group, legal entity and branch before entering transactions.
4. Follow the Company Setup and Operating Guide for the first workspace, opening balances and daily operations. Use the Company Access Administration Addendum when setting up branches, roles or staff access.

The development installer is unsigned. If Windows blocks it, share the file and its checksum with your IT administrator for review.

### J Panel · 0.1.0+4

1. Run `J-Panel-0.1.0-4-Development-Setup.exe`. You can also extract the whole portable ZIP and open `Launch.cmd` beside `Payload`.
2. This operator build opens its configuration notice. For a connected operator session, ask the Jentra administrator for a build targeting the approved operator project with the matching services installed and an operator account assigned.
3. On a connected build, use your individual operator account and authenticator. Confirm the organization shown before making changes.

## Android

1. Copy the app's `.apk` file to an ARM64 Android phone. Open it from Files and follow Android's install prompt. If your device permits sideloading, allow installation for the app opening the APK and turn that permission off again after installation.
2. To update an existing installation, open the new APK over the installed app. If Android reports a signature or downgrade conflict, check the package version and signer with the administrator before removing anything. Uninstalling can remove local app data and drafts.

### Jentra Employee

Open **Jentra Employee** and sign in with the account linked to your employee record. Complete MFA when prompted. Review your own attendance and leave, open payslips made available by payroll, or update your profile from the employee workspace. If you have no employee assignment, contact HR with your account email and company name. Keep passwords and authenticator codes private.

### Jentra Sales

Open **Jentra Sales** and select **Explore the preview**. Open **Customers** to find a sample account, start an order, add items and review the draft. Save the draft if you want to reopen it on the same device within 24 hours. Visit notes stay in the current session. The preview uses sample data and submits no company orders.

## Browser

| App | Open the downloaded web package |
| --- | --- |
| Jentra OS | Extract the ZIP and open **Start Jentra OS Web.cmd**. Chrome or Edge opens `http://127.0.0.1:8485/`. Keep the console open while using the app. Use the same address and browser profile when resuming local work. |
| Jentra Employee | Give the Hosting ZIP to the release administrator. Its `public/` folder and `firebase.json` are ready to stage on the approved Employee Firebase Hosting site or QA channel. Employee sign-in requires the approved HTTPS origin and matching callback configuration. |
| Jentra Sales | Extract the Preview ZIP and open **Start Sales Preview.cmd** on Windows with Node.js installed. Use `http://127.0.0.1:8396/` and select **Explore the preview**. Keep one editing tab open and use the same address and browser profile to recover a draft. |

Close the launcher console to stop a local server. Jentra OS and Employee need the configured development backend for company actions. For hosted access, have the release administrator use the included hosting configuration and verify sign-in on the approved address.

## Operating guides and access

The handoff includes Word copies of the **Jentra OS Company Setup and Operating Guide** and **Company Access Administration Addendum** in `User Guides/`. Use this handoff guide for package versions and installation. Use the Word manuals for company setup, scoped staff access and day-to-day workflows.

The packages are for development or preview use. Before using them with real company data, verify individual account access, MFA and your organization's supported workflows on the intended backend and devices.
