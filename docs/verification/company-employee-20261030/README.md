# Company administration and employee rollout — 30 October 2026

This continuation covers the requested company/staff backend installation and
Jentra Employee rollout. Work is in the shared `codex/check-feature-completion`
checkout. Existing application work and installed migration source are retained.

## Results and current limits

| Area | Result | Evidence / remaining step |
| --- | --- | --- |
| Current backend runner and sender checks | 35 passed, zero failed | `build/company-employee-completion-20261030/backend-runner-tests-current.log`; controlled Node tests, not hosted PostgreSQL or FCM delivery |
| Company administration behavioral rerun | 73 passed | `build/company-employee-completion-20261030/company-postgres-result.json`; isolated PGlite PostgreSQL with simulated Auth |
| Company administration pgTAP rerun | 31 passed, rollback verified | `build/company-employee-completion-20261030/company-pgtap-result.json`; isolated engine, not the full Supabase stack |
| Employee application tests | 224 passed | `employee-tests-final.log`; the earlier compiler out-of-memory log is retained separately |
| Employee analyzer | No issues found | `employee-analyzer-final.log`; current employee source, not a full workspace release certification |
| Signed Android release | APK and AAB built and verified for 0.5.0+9 | Release manifest, signatures, package/version and 16 KiB APK alignment passed; both copied artifact hashes were independently rechecked |
| Hosted database | Read-only check completed in authenticated Chrome | Company administration, employee self-service and push schemas are all absent; latest migration is `20261020093822` |
| Hosted rollback rehearsal | Owner approved; not executed yet | Exact script/hash confirmed; native Chrome input is currently refused because other input is detected, and Chrome tab-control integration is unavailable |
| Sender activation | Pending | No backend or sender was installed or activated by this continuation |
| Physical Android acceptance | Pending | No phone was returned by the device inventory |
| Real-company acceptance | Pending | Requires the selected real company, individual administrator/employee accounts and completed hosted checks |
| Store publication and portable signing backup | Pending | A signed package does not establish Play publication or recovery of the signing key on another device |

The previous in-memory company reports were preserved at their original sealed
hashes; the rerun reports are separate files under `build/`. No old verification
manifest is rewritten to imply new installation or acceptance.

## Signed Android delivery

The production package is `com.jentra.employee`, version `0.5.0`, build `9`.
The release used the existing approved certificate, with SHA-256
`60b7d92d591435d8001db62b41453efdae5caab3abff76cb8cfedc106d8e2b65`.

| Artifact | Bytes | SHA-256 |
| --- | ---: | --- |
| [Signed APK](../../../apps/jentra_employee/build/deliverables/0.5.0-9-signed-production-identity-20261030T065609063Z-4d84c890105e4a3095d9663edda131d7/Jentra-Employee-0.5.0-arm64-signed.apk) | 27,094,526 | `3ec51ed5de074f5ae5357619b1c6c504bfa687400f1389900ed042775f305802` |
| [Signed Android App Bundle](../../../apps/jentra_employee/build/deliverables/0.5.0-9-signed-production-identity-20261030T065609063Z-4d84c890105e4a3095d9663edda131d7/Jentra-Employee-0.5.0-signed.aab) | 47,076,371 | `5479871ed37f268faebe36304d5010a30b94ac3f7b7584e2625822140b8f78a3` |

The [release manifest](../../../apps/jentra_employee/build/deliverables/0.5.0-9-signed-production-identity-20261030T065609063Z-4d84c890105e4a3095d9663edda131d7/release-manifest.json)
records the pre/post-build source, configuration and tool hashes. Its source
snapshot is `3a39ff3cd3588d7e69982a43e9061b1e5d810c4ef54f9d6bea1b59238acd29e7`.
All 367 recorded source files still match byte for byte after the build, with
no added or removed release inputs. PowerShell 7 and Windows PowerShell sort
punctuation differently, so a cross-runtime aggregate hash can differ despite
identical files; the independent check compares the complete file set and
reconstructs the recorded order. It also checks the public configuration and
each tool hash. This does not relax the build's before/after source guard.

The APK is ready for the selected ARM64 test device. The AAB is the signed input
for a reviewed Play upload. Neither has been installed on a physical phone or
published to Play by this continuation. Hosted employee services and push remain
inactive; those journeys cannot pass until the backend is installed and the
required scoped accounts are available. The signing key's portable backup is
still unverified.

[The final verification record](verification.json) binds the artifacts and
results to their evidence-file hashes. A fresh independent APK signature check,
AAB signature/certificate check, 16 KiB APK alignment check and source-file-set
comparison all passed. The Android inventory returned no connected devices.

## Release repair

The first APK attempt failed with native JVM allocation errors in
`hs_err_pid4668.log` and `hs_err_pid9924.log`. The release helper now defaults to
a 1 GiB Gradle heap, one worker, two active processors and in-process Kotlin
compilation. No signing key was replaced. JVM crash/replay files are preserved
as diagnostics and excluded from release-source provenance. Kotlin's generated
session directory is also excluded, alongside the existing Gradle/build caches.
Real source/configuration/tool changes still block publication. Each new build
now saves `release-inputs.json` before compiling, allowing a rejected snapshot to
be compared precisely instead of being lost with the failed build process.

The existing independent-process directory race test exposed a separate defect:
PowerShell directory creation could succeed for both callers. The helper now
reserves each release name through an exclusive `CreateNew` file handle and
checks for an existing destination while holding it. All **18** provenance
checks pass, including source/configuration/tool changes, artifact overwrite,
manifest overwrite and the independent-process race. Evidence:
`build/company-employee-completion-20261030/provenance-tests-final.log`.

## Current hosted evidence

The authenticated dashboard identifies project `xpdoufauvrbdmxgngetv`, branch
`main`, and reports **No backups**. The read-only SQL result is recorded in
`build/company-employee-completion-20261030/hosted-preflight-observed.txt`.
It returns `false` for `company_admin_installed`, `employee_self_installed`
and `push_installed`, with latest migration `20261020093822`.

The five exact source files have been composed into
`build/company-employee-completion-20261030/hosted-ddl-rehearsal.sql`, with one
transaction, a 3-second lock timeout, 30-second statement timeout and a rollback
before the final absence check. It contains no synthetic company fixtures or
business commands. The dashboard flagged destructive statements in the source
and could not detect the candidates' dynamic RLS setup. Automatic approval review
rejected proceeding through **Run without RLS** because exact authorization for
this production DDL rehearsal was missing. The action did not execute. The owner
subsequently approved the exact rollback-only rehearsal. Chrome's native input
is currently refused with `user input was detected in this window`; the separate
Chrome tab-control integration is unavailable. Browser access is being
coordinated before any SQL submission. The existing CLI 2.75.0 connection was
also rechecked and still returns an invalid access token, so it cannot provide
an authenticated fallback. No permanent installation was approved or performed.
[The current rehearsal status](rehearsal-status.json) records this
separately from the earlier artifact-verification snapshot.

The previously passing CI run `40681398794` was rechecked. Its employee push,
self-service and HR producer sources match this checkout; the cases candidate
has additional current-owner eligibility hardening, and the administration
candidate is separate workspace work. That run therefore does not certify the
complete current rollout bundle.

## Hosted verification and rollout order

Open the exact Supabase project `xpdoufauvrbdmxgngetv`. Run
[preflight.sql](preflight.sql) in its SQL editor to inspect migration history,
function grants, private-table RLS, extensions and administration guards. The
query is read-only and returns no user, employee, payroll, invitation or device
target records. Verify the dashboard project identity separately; a database
name is insufficient to establish the project.

The source dependency order for a reviewed installation is:

1. `20261023090000_employee_push.sql`.
2. `20261025090000_employee_self_service.sql`.
3. `20261025100000_employee_cases_documents_notifications.sql`.
4. `20261027100000_employee_hr_event_producers.sql`.
5. `20261028130000_company_access_administration.sql` (independent of the employee candidates).

These files remain in `supabase/candidates`. Do not bulk-push the repository's
historical migrations or run synthetic rollback acceptance suites on the hosted
company. Refresh installed state, isolated regression results and recovery
evidence before installation. Record each applied migration and its exact source
hash only after it actually succeeds.

Push additionally requires the dedicated FCM sender identity, server-only secrets,
deployed `employee-push-dispatch` handler, private scheduler and verified device
opt-in/delivery/revocation. The [activation guide](../../development/employee-firebase-activation.md)
and [signing guide](../../development/employee-release-signing.md) describe those
operational steps. Credentials must remain outside source and verification logs.
