# Employee Firebase verification baseline — 25 October 2026

This record preserves the confirmed **23 October** baseline for PR #16,
commit `448220ed88253fa3f86636632df42c4276140fce`. Firebase project `jentra-os`
provides browser Hosting and Android push transport; Supabase project
`xpdoufauvrbdmxgngetv` remains the sign-in, employee identity and HR authority.
The push backend is still an uninstalled candidate. Browser preview deployment,
compiled development APKs and passing CI do not constitute production acceptance.

The 25 October company-connection banner and preview-wrapper corrections for
patch version **0.4.1+8** are being verified separately. Their final head, rebuilt artifacts and preview
results must be recorded before they supersede this baseline. No new build,
deployment, hosted Auth change or database mutation was performed for this record.

## Confirmed CI and tests

[PR #16 CI run 39946877445](https://github.com/sameerafernando0520-boop/Jentra-OS/actions/runs/39946877445)
completed successfully on 23 October for the exact commit above. All five jobs
passed; the Windows release job completed at **11:50:52 UTC**.

| Job | Confirmed result |
| --- | --- |
| [Format, analyze, and test](https://github.com/sameerafernando0520-boop/Jentra-OS/actions/runs/39946877445/job/120391858298) | 815 Dart files, zero formatting changes; analyzer clean; employee VM 180, Chrome storage 10, push sender/contract/runner 17 and Hosting preparation 17 tests passed |
| [Secret scan](https://github.com/sameerafernando0520-boop/Jentra-OS/actions/runs/39946877445/job/120391858641) | Passed with the reviewed public Firebase client configuration and exact synthetic-fixture exceptions; no blanket server-credential exception |
| [Desktop tests and goldens](https://github.com/sameerafernando0520-boop/Jentra-OS/actions/runs/39946877445/job/120391858667) | Windows suite passed |
| [Migrations, lint, and pgTAP](https://github.com/sameerafernando0520-boop/Jentra-OS/actions/runs/39946877445/job/120391858703) | Existing suite: 42 files / 7,369 assertions; isolated push candidate: one file / 47 assertions; both `Result: PASS` |
| [Windows release build](https://github.com/sameerafernando0520-boop/Jentra-OS/actions/runs/39946877445/job/120396314722) | Unsigned desktop build and configured bundle upload passed; this is distinct from Android store distribution |

The candidate result was emitted at **2026-10-23 11:39:56.641 UTC** using
Supabase CLI 2.114.0 and Node 24. Its synthetic users, sessions, employee-only
permissions, candidate schema and fixtures were enclosed in one rollback
transaction against the isolated local CI stack. The [candidate guide](../../development/employee-push-candidate.md)
describes the coverage and runner. This is actual PostgreSQL execution, while
true multi-connection registration/worker contention remains untested here.

The local [MFA/identity-hook log](../../../build/employee-web-20261023/mfa-final-tests.log)
also records 23 focused passes: 21 MFA checks and two identity-hook checks,
including expired setup recovery, code clearing and Sinhala/Tamil enlarged-text
verification. These automated results do not establish privately authenticated
MFA, HR or assistive-technology acceptance.

## Confirmed artifacts and preview

The local manifests below record artifact identities and build times separately
from CI's Git head; they contain no Git-head attestation. Retain the 0.4.0 files
when recording the later 0.4.1 patch artifacts.

The [Android manifest](../../../apps/jentra_employee/build/deliverables/0.4.0-optimized-development/apk-manifest.json)
records version **0.4.0+7**, package **`com.jentra.employee.dev`**, built at
**2026-10-23 11:36:41.849 UTC**. The APKs use the local Android debug signer
despite release-mode compilation. The manifest records verified package identity
and signatures; neither file is signed for store distribution.

| Android artifact | Bytes | SHA-256 |
| --- | ---: | --- |
| [arm64-v8a development APK](../../../apps/jentra_employee/build/deliverables/0.4.0-optimized-development/Jentra-Employee-0.4.0-arm64-v8a-optimized-development.apk) | 24,416,867 | `408a4666b9246a885378f4ecd6ce7bcbd0d907a150be41600997a2aa8c4a5b9a` |
| [armeabi-v7a development APK](../../../apps/jentra_employee/build/deliverables/0.4.0-optimized-development/Jentra-Employee-0.4.0-armeabi-v7a-optimized-development.apk) | 21,875,117 | `d0e3825f9f13587f4d7c58da4c81503bbb0f4a2def423b266c499779b5e7d7c5` |

The immutable [web release manifest](../../../tools/employee-web/.staging/2026-10-23T11-31-22-055Z-2328354571fa/release-manifest.json)
records **54 public files**, created at **2026-10-23 11:31:27.354 UTC**, with
package SHA-256 **`2328354571fa94a75dca17c01ac4ea48961ce748ec20fedaf1ea7688c994b9a0`**.
This package digest covers the recorded file manifest; individual response hashes
are recorded separately.

The [deployment log](../../../build/employee-web-20261023/firebase-preview-deploy.log)
records preview channel `employee-qa-20261023`, version `8bf977a71b48ac5a`, at
[the temporary preview origin](https://jentra-os--employee-qa-20261023-j8c2pxwt.web.app).
The channel was scheduled to expire on 30 October; this record is not a fresh
availability check and records no live-site promotion. The CLI emitted Firebase
Auth domain-sync warnings; Supabase remains the application Auth provider, and
that warning is not proof of a successful Auth configuration change.

The [public HTTPS verification](../../../build/employee-web-20261023/preview-http-verification.json)
at **2026-10-23 11:34:08.149 UTC** passed: `/`, `/auth/callback`, the compiled app
and local CanvasKit script returned 200 with the recorded hashes; a deliberately
missing asset returned 404. Responses used `no-store, max-age=0` and
`no-referrer`. Serving the callback app shell does not prove confirmation,
recovery, OAuth, employee authorization or push receipt.

## Remaining release gates

- **Production approval and installation:** independently review and approve the
  candidate SQL, sender, service identity, server-only secrets and private
  schedule before any hosted installation or activation. No backend deployment
  or production Hosting promotion is established by this record.
- **Hosted Auth:** the last [read-only metadata check](../hr-completion-20261023/README.md)
  on 23 October found a Windows loopback Site URL and an empty redirect allowlist.
  A fresh [public provider-settings check](../../../build/employee-web-20261025/public-auth-settings.json)
  at **2026-10-24 20:55:12.722 UTC** (**25 October 02:25:12.722 Asia/Colombo**)
  returned HTTP 200 for the selected project: Google disabled, email enabled,
  signup enabled and email autoconfirm disabled. This exposes no user/HR rows
  or credentials and does not refresh the private redirect configuration.
  Recheck and approve exact
  hosted/mobile callbacks, then privately verify confirmation, recovery,
  password sign-in and any Google flow in the selected project. Preserve the
  authorized desktop callback; avoid broad production preview wildcards.
- **People authority:** the same snapshot found `module.people=false` for the QA
  Starter plan. Use an approved, scoped HR-enabled workspace with an accepted
  employee link, active employment, required self permissions and valid MFA.
  Firebase configuration grants none of these and does not justify enabling HR
  globally for Starter tenants.
- **HR workflows and event production:** implement/review the missing employee-safe
  capabilities in the [HR matrix](../hr-completion-20261022/hr-capability-matrix.md)
  and an authoritative recipient-scoped HR notification producer. The push
  candidate mirrors existing `people.*` notifications and creates no absent
  attendance, leave, payroll, document or case events.
- **Device and concurrency acceptance:** verify actual Android FCM permissions and
  delivery on a device with Play services, denial/opt-out, generic lock-screen
  content, refresh/retry, background/foreground, sign-out/account/workspace
  changes, expiry and link revocation. Exercise multiple concurrent sessions,
  registrations and workers; one-connection pgTAP lease checks are insufficient.
- **Browser and owner acceptance:** verify authenticated own-data isolation,
  reload/navigation, competing tabs, lock masking, MFA, photo selection/cancel,
  all three languages at enlarged text, keyboard and screen-reader use. Review
  the actual final HTTPS preview and any legacy live-origin service worker before
  promotion. Screen and language sign-off remain separate from automated tests.
- **Production signing and distribution:** obtain the owner's chosen store
  identity and private release-signing configuration. The development APK signer
  and registered production Firebase identity do not establish a signed
  production Android release or store acceptance. The CI Windows bundle is
  unsigned; signed desktop distribution is a separate release check.

The [activation guide](../../development/employee-firebase-activation.md) lists
the owner-supplied setup and approval boundaries. Keep credentials, MFA material,
private HR rows and the ignored Firebase administrator key out of source,
artifacts, chat and this evidence record.
