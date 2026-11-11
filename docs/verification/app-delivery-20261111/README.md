# Jentra app delivery · 11 November 2026

Use [CHECKSUMS.sha256](CHECKSUMS.sha256) to verify the eight files supplied
in the app handoff. All eight matched their recorded SHA-256 hashes after
being copied to the delivery folder.

| App | Version | Package and verification |
| --- | --- | --- |
| Jentra OS Windows x64 | 0.3.3+2306 | Unsigned development installer and portable ZIP. The ZIP verified 47 runtime files. A staged installation verified all 48 files including the release manifest. |
| HR Employee web | 0.5.0+9 | Firebase Hosting ZIP with 56 public files verified after extraction. All 17 web staging tests passed. |
| HR Employee Android | 0.5.0+9 | Owner-signed ARM64 APK from 30 October 2026. The APK v2 signature, 16 KiB alignment, application ID `com.jentra.employee`, and release hash verified. |
| Jentra Sales web | 0.1.4+5 | Preview ZIP with a local launcher. All 49 public files matched their build hashes. The launcher served the app, assets and a navigation route. |
| Jentra Sales Android | 0.1.4+5 | ARM64 preview APK. Its APK v2 signature matched the previous development signer. The application ID is `com.jentra.sales.dev`. |
| J Panel Windows x64 | 0.1.0+4 | Unsigned development installer and portable ZIP. Both hashes match the recorded release and its staging check verified 47 runtime files. |

The fresh Desktop, Employee web and Sales builds used commit `8be27704`.
The app, package, release-tool and dependency inputs match default branch
commit `338a41ee`. The Windows build used a shorter source and staging path
after the initial paths exceeded Windows file path limits. The copied source
files matched the recorded manifest.

Employee Android preserves the existing signed app identity. The fresh
development rebuild exhausted Gradle Metaspace, so the delivered APK is the
previous owner-signed release. It predates the latest project-key validation
change. J Panel was built separately from the reviewed local snapshot based
on `b3178b05`.

Employee web sign-in requires an approved HTTPS Employee Hosting origin. The
[public Employee address](https://jentra-os.web.app/) returned HTTP 404 when
checked. Live Sales is disabled in the delivered web and APK previews. The
[online Sales preview](https://jentra-os-sales.web.app/) was serving 0.1.3+4.
J Panel opens a configuration notice until an approved operator backend
with the matching schema and functions is configured. Device acceptance
and authenticated company workflows remain pending.

## J Panel startup check

The delivered installer completed a staged installation on Windows x64.
The installed and portable executables both started and remained responsive
during the local startup check. If setup fails, extract the entire portable
ZIP to a short local path and open `Launch.cmd` beside the `Payload` folder.
Keep the launcher and its runtime files together.

The development project returned HTTP 404 for the operator assignment RPC
and for the `org-identity` and `platform-organization-lifecycle` functions.
A connected installer needs a project with those services installed and an
assigned operator account with MFA.
