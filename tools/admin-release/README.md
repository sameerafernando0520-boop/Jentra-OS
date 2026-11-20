# J panel for Windows

J panel is the internal Windows app for assigned platform operators. Its native installer and portable ZIP are built from the shared operator panel with a dedicated entry point.

From the repository root, build with the installed Flutter, Visual Studio and Inno Setup tools. Increase the build number when replacing an earlier installation.

```powershell
.\tools\admin-release\build.ps1 -PublicConfigPath <public-config.json> -ApprovedProjectRef <project-ref> -BuildNumber 3
```

Both `-PublicConfigPath` and `-ApprovedProjectRef` are required and must name a separately approved development project. A release without its connection could never show the operator sign-in, so the build refuses it. If an installed panel's connection is wrong, it opens to a "could not start" screen with a support code instead of the sign-in. A debug run without configuration (`flutter run -t lib/main_admin.dart`) still opens to a configuration notice.

Apply the operator identity migration and matching `org-identity` Edge function to the approved backend. Configure the transactional sender and identity code secret from the [organization control rollout guide](../../docs/development/organization-control-rollout.md). Provision each operator's Auth account and assign `organization_manage` through the platform operator process.

After signing in and verifying MFA, open **Account security** in J panel to set or change your password and verify a separate recovery email. An assigned operator who uses an existing approved identity provider can set an initial password from an MFA-verified browser J panel session. **Forgot password** on the Windows sign-in screen uses the operator sign-in email to send a code to the verified recovery address. The operator still completes MFA after resetting the password.

The output folder under `build/admin-release/` contains the unsigned installer, portable ZIP, and delivery manifest. Verify the exact installer in workspace staging before distributing it.

```powershell
.\tools\admin-release\verify-native.ps1 -ReleaseDirectory <release-directory>
```

Open **J panel** from Start after installation, or extract the whole ZIP and run `Launch.cmd`. The installer retains the previous administrator AppId and installation folder so upgrades continue to work.
