# Employee Android release signing

The owner authorized a new release signing key. The existing key is stored outside
the repository at `%USERPROFILE%\.jentra\signing\employee`. Never regenerate it to
fix a build. The local signing password uses Windows DPAPI for this Windows user;
copying `password.dpapi` to another computer does not create a portable recovery.

The release identity is `com.jentra.employee`, alias `jentra-employee`. Its public
certificate SHA-256 is:

```text
60b7d92d591435d8001db62b41453efdae5caab3abff76cb8cfedc106d8e2b65
```

Run `scripts/employee/build_production_release.ps1` from the repository root to
build the AAB and ARM64 APK. The helper unlocks the existing key privately, avoids
a persistent Gradle daemon, and checks signatures, certificate identity, package,
version and APK alignment before writing a delivery manifest. A production package
identity does not activate a hosted feature, deploy the database or publish to Play.

Before store distribution, the owner should create a portable encrypted backup
on a private backup drive and keep its password in their password manager:

```powershell
./scripts/employee/backup_release_signing.ps1 -Destination 'E:\Private backup\jentra-employee-release.p12'
```

The helper asks for the new backup password privately, exports the same key with
that password, checks its certificate, and proves that its private key unlocks.
It refuses a destination inside the repository or an existing destination file.
It never saves or prints the backup password. The original local key is retained.
The example drive is a placeholder; select an actual private destination.

Portable recovery and retention on a separate device remain owner actions until
this interactive check is completed. Play App Signing enrollment and real-device
acceptance are separate release steps. No Android test device is currently
available for delivery, account switching or system document-picker acceptance.
