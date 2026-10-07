# Remaining Wave 4 development installation review

Prepared 2026-10-05 for development project `xpdoufauvrbdmxgngetv`.
**Not approved or installed. Final client/build review is still in progress.**

The proposed package installs the 15 unapplied candidates listed, in exact order
and with hashes, in `install-composition-prepared-v2-hashes-20261005.json`.
Employee, calendar and private HR migrations already installed in development
are excluded. No production installation is proposed.

The package adds organization/calendar resolution, attendance/leave/clock
imports, synthetic payroll/corrections, fixed assets, projects/expenses/billing,
service/maintenance, milestones, internal asset equipment and separate private
expense evidence. The complete composition creates 111 protected tables. It
includes two additional reviewed private expense Edge functions, using distinct
user and worker authentication. Existing private HR functions are excluded.

The actual strict composition passes 14 security and preservation assertions.
Every candidate table forces RLS and denies direct authenticated table access;
candidate APIs have protected empty search paths and deny anonymous execution;
owner helpers, renamed base commands and trusted byte/worker APIs deny the wrong
caller roles. Existing role grants, plan entitlements, subscriptions, installed
finance providers and the migration ledger are unchanged. Source, executed query
and result bindings are in `install-composition-current-evidence-20261005.json`.
The first composition attempt lacked temporary pgTAP; that failure is preserved,
and the revised strict query creates pgTAP inside its rolled-back transaction.

Separate actual business suites include current protected finance/evidence 180,
milestones 147, internal asset equipment 171 and billed payroll correction 201.
The service correction/private-cost 186 result and every earlier result remain
bound to their captured source. Assertion counts are not summed into requirement
coverage or acceptance. Installed employee/calendar were rechecked with 49/65
rollback assertions; previously installed private HR 82 remains separate evidence.

Both expense Edge entrypoints pass actual pinned Deno checks. Injected handler
tests cover bounded upload/readback, current ticket scope, safe error handling,
physical-delete verification and bounded worker batches. Final current private
client, service asset client, independent reviews and the complete current-source
Windows build must finish before this artifact is offered for approval.

Installation does not enable any tenant plan, grant any role, accept private
content, activate a retention worker or send external messages. Worker setup and
verified storage probe remain separate provider gates. Generic service stock
parts and asset procurement/stock conversion providers are absent; those actions
remain explicitly unavailable. Governed asset openings and internal asset links
are independent supported candidate paths.

The owner confirmed the desktop project URL matches development. The subsequent
read-only reconciliation still found no matching W4 workspace by name or slug,
zero dedicated-plan subscribers, 37 installed migrations and no worker readiness.
Owner/workspace reconciliation, actual two-user/MFA walkthroughs, independent
overlapping sessions, measured p95 load, Credential Manager restart and owner
signoff remain open. This package cannot establish Wave 4 completion.

Before any approved installation: refresh the live ledger/provider grants and
advisors, verify every reviewed source hash and candidate absence, preserve
acceptance/concurrent data, apply only the approved package, then run installed
security/business checks without reinjecting DDL. Review the two expense function
deployment/configuration separately from worker activation. No Git operation or
application replacement/launch is included in this proposal.
