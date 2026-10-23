# Hosted HR metadata follow-up — 23 October 2026

Supabase management access to owner-selected project `xpdoufauvrbdmxgngetv` now
works. The project returned `ACTIVE_HEALTHY`. The check began at
**2026-10-23 05:08:56.622 UTC** and completed at **05:09:23.528 UTC**
(10:38:56.622–10:39:23.528 in Asia/Colombo). See the
[sanitized hosted metadata](../../../build/hr-access-20261023/hosted-readiness.json).
This supersedes the previous day's access-unavailable finding; it does not
supersede the version-specific installed-app observations.

The exact `jentra-qa-221022` workspace was observed at
**05:09:17.587817 UTC**. It has a Starter subscription in `trialing` status,
five seats and version 1, with a trial ending **2026-11-21 12:16:30.428686 UTC**.
The source subscription-time test passes, but its plan's `module.people` flag
is explicitly **false**, as is `module.ai`. Starter has no entitlement rows for
`module.assets`, `module.finance`, `module.projects` or `module.service`.
Absent rows are distinct from stored false values. A healthy project, owner
role or unexpired trial therefore does not enable HR access.

The read-only metadata queries found all 20 checked schema columns and all eight
targeted API signatures from the [HR capability matrix](../hr-completion-20261022/hr-capability-matrix.md).
Each inspected RPC returns `jsonb`, uses `SECURITY DEFINER` with an empty
configured search path, grants execution to `authenticated`, and denies execution
to `anon`. This establishes installed identity and grant metadata, not identical
function implementations or employee-safe behavior for every action.

The inbox view is installed with `security_invoker` and depends on
`workflow.notifications`. That base table has enabled and forced RLS and exactly
one recipient SELECT policy requiring `recipient_id = auth.uid()` and tenant
membership. The reported policy count reconciles with the returned policy.
The five inspected private HR/payroll tables have enabled and forced RLS,
zero policies, and no direct authenticated/anonymous SELECT access; authenticated
schema usage is also denied. These private-table restrictions are expected.

The migration ledger returned **all 130 records**, latest version
`20261020093822` (`assurance_people`). Employee foundation, private HR,
attendance, leave, synthetic payroll, clock batches and payroll correction names
are recorded. Several installed HR versions use `202610130709xx` timestamps;
the matrix's source-file dates must not be treated as installed-version proof.
Ledger names and versions do not establish body equality or migration-text hashes.

Auth remains a release gate: Google is disabled and neither its client nor secret
is configured. Email and signup are enabled, with email confirmation required.
The Site URL is `http://127.0.0.1:56327/auth/callback/*`, and the redirect allowlist
is empty. A hosted/mobile redirect plan remains necessary; this configuration
inspection does not prove the cause of a particular failed confirmation link.

The query confirmed `transaction_read_only = on`, and no backend mutation was
made. No credential, personal account/employee row, notification content, payslip
content or function body is reproduced here. Accepted employee links, effective
employee capabilities, MFA sessions, cross-user isolation, payroll validity,
retention-worker schedules and private-file/device delivery were not tested.
Active edge-function metadata does not establish handler authorization or worker
readiness. This follow-up is not production acceptance.

Firebase Hosting and Firebase Cloud Messaging can supply a hosted surface and
push transport. They do not enable the People entitlement, implement missing
employee-safe attendance/leave/document/case APIs, wire the mobile payslip/inbox
screens, or create an HR notification producer. Those workflow and authorization
gaps remain in the capability matrix. This record authorizes no production flag,
schema, function, role, hosting or push deployment change.
