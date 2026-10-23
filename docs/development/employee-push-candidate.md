# Employee Android push candidate — 23 October 2026

This is source prepared for review, not an installed backend, deployed sender,
active schedule or demonstrated device delivery. Supabase remains the identity,
authorization and HR data authority. Firebase Cloud Messaging supplies transport.
Browser Hosting does not require web push, so this slice accepts Android only.

The [candidate SQL](../../supabase/candidates/20261023090000_employee_push.sql)
adds a private schema, own-device RPCs and a recipient-bound delivery outbox.
It changes no plan entitlement, employee/staff role assignment or existing HR
function. Installation requires independent database review and explicit approval.
Current hosted `module.people=false` remains an independent gate.

Client contract:

- `api.employee_push_register(p_tenant_id uuid, p_legal_entity_id uuid,
  p_branch_id uuid, p_installation_id uuid, p_token text, p_platform text,
  p_command_id uuid)` returns `installation_id`, `version`, `status: active`
  and `expires_at`. Platform is `android`. `p_token` is a compatibility name for
  the opaque Firebase Installation ID returned by current Messaging `register`;
  it is not an employee selector. Target length is 20–4096 with no whitespace or
  control characters. No user, employee or session ID is accepted from the app.
- `api.employee_push_remove(p_installation_id uuid, p_command_id uuid)` returns
  `installation_id`, `status: removed` and boolean `removed`. It only affects the current user's
  current-session binding and works after People permission or link revocation.
  `removed: true` proves an own current-session binding was removed; a missing or
  foreign binding returns false without revealing which case applies. The client
  must require true to trust the server removal path; otherwise Firebase unregister
  must succeed before local recovery is deleted. A replay refreshes this proof
  to false if a later registration became active, and never revokes that newer
  registration. It reveals no other user's device state.

The app keeps a random installation UUID, serializes target refreshes, retries
the same command UUID only with identical arguments, and uses a new UUID for a
renewal. A cached acknowledgement proves the original operation, not that an old
binding remains active. A binding lasts 24 hours; renew on authenticated startup,
foreground resume and target change. Remove before sign-out, account or workspace
switch, then unregister Messaging. If removal cannot reach the server, offer
retry rather than claiming server removal; local opt-out cannot recall a send
already in flight. A replacement account cannot overwrite another active binding
without possession of the same opaque target; otherwise removal/expiry is needed.

Registration derives `auth.uid()` and verified JWT `session_id`, checks the
matching `auth.sessions` row with no elapsed `not_after` expiry, reuses existing `people.view`/`people.self.view`
authority, and resolves an accepted account link with active membership and
current scoped employment. Dispatch repeats those checks, including link revision,
active tenant/entity/branch, People entitlement and role MFA requirements using
the captured verified AAL. No staff-wide permission is added to ordinary employees.
Self identity/link inbox do not unconditionally require AAL2; assigned MFA roles
can require it. Own payslip access separately requires AAL2.

All new tables enable and force RLS and deny direct access even to `service_role`.
Only the narrow security-definer worker RPCs expose a current FID to the sender.
Targets never enter notification bodies, generic command receipts or HTTP output.
Removal, invalid-target responses and expired-binding maintenance clear stored
targets and hashes. The scheduler performs bounded expiry cleanup and retains
command/delivery receipts for seven days; no scheduler is activated by this source.
Deleting a Supabase session also deletes its binding through a foreign key.
Session existence and its explicit expiry are rechecked, not treated as proof that every possible sign-out
mode immediately deletes that session. Explicit remove-before-sign-out remains
required, with the 24-hour expiry as a fallback.

An AFTER INSERT trigger mirrors only existing authoritative `workflow.notifications`
with `people.*` type, exact entity/branch and matching recipient into the outbox.
It creates no HR event or employee message. The earlier notifier skips People
commands, so an approved HR event producer remains necessary for real HR pushes.
Old inbox history is not pushed when a new device registers.

The sender uses `employee_push_claim`, `employee_push_target` and
`employee_push_finish`, granted only to `service_role`. Workers claim with
`FOR UPDATE SKIP LOCKED`, random 60-second leases and at most five attempts.
Targets are re-authorized immediately before HTTP delivery; stale lease completion
cannot acknowledge or retire a replacement binding. Transient/network/auth errors
retry with bounded backoff; only FCM's explicit `UNREGISTERED` retires a target.
Delivery plus acknowledgement is not an atomic transaction: timeout/crash can
produce a duplicate generic wake. The app must deduplicate opaque event IDs and
re-authorize the current employee when opening the app. No exact-once or private
data confidentiality claim depends on push arrival.

The fixed notification is **Jentra Employee** / **You have an update. Open the app
to view it.** Data contains only `kind: employee_update` and an opaque `event_id`.
Android channel is `jentra_employee_updates`, TTL five minutes. No employee name,
salary, leave reason, HR case text, tenant ID or private subject route is sent.
The HTTP v1 payload uses `message.fid`, matching the current
[official Message reference](https://firebase.google.com/docs/reference/fcm/rest/v1/projects.messages#Message).

Deployment owner supplies these individual server-only secrets privately:
`EMPLOYEE_PUSH_DISPATCH_SECRET` (random, at least 32 characters),
`EMPLOYEE_PUSH_FIREBASE_PROJECT_ID`, `EMPLOYEE_PUSH_GOOGLE_CLIENT_EMAIL` and
`EMPLOYEE_PUSH_GOOGLE_PRIVATE_KEY`. Supabase supplies server URL/service-role
credentials. The Google service identity needs only the reviewed FCM send access
for the selected Firebase project. No credential belongs in Flutter, Hosting,
source, SQL, chat or logs. The source reads no Firebase admin-key file.
The dispatch function requires its scheduler bearer secret inside the handler;
gateway configuration and a private schedule need separate approved deployment.
No browser/user JWT can start the sender.

Validation command:

```text
node --test supabase/functions/tests/employee_push_dispatch.test.mjs supabase/functions/tests/employee_push_contract.test.mjs supabase/functions/tests/employee_push_runner.test.mjs
```

The sender tests use synthetic keys and mocked HTTP/RPCs; they cover generic FID
payloads, scheduler authorization, recipient/session revocation, stale leases,
bounded requests, OAuth signing/cache, invalid targets and uncertain completion.
SQL tests are static security-contract checks. PostgreSQL compilation, actual
concurrent registration/lease isolation, rollback fixtures, hosted deployment,
FCM permission validation and physical Android delivery are not established by
those tests and remain required before activation.

The [runtime candidate suite](../../supabase/candidates/tests/employee_push_candidate_test.sql)
stays outside default `supabase/tests` discovery. Supabase CLI 2.114.0 mounts only
the selected test paths into its pg_prove container, so a sibling candidate
include would be unavailable (see [versioned CLI source](https://github.com/supabase/cli/blob/v2.114.0/apps/cli-go/internal/db/test/test.go)).
The [local-only runner](../../supabase/candidates/run-employee-push-test.mjs)
inlines the candidate inside the suite's rollback transaction, writes one new
temporary test directory under `supabase/candidates`, mounts and runs only that directory
with `supabase test db --local`, then removes only its own file and empty directory.
It accepts no linked project, database URL, credentials or forwarding options.

```text
node supabase/candidates/run-employee-push-test.mjs --check
node supabase/candidates/run-employee-push-test.mjs --run-local
```

`--check` only assembles the suite in memory; it does not execute PostgreSQL.
`--run-local` requires a running isolated Supabase stack with existing migrations
already installed. Default database discovery cannot reach the temporary file,
including after an interrupted runner leaves its owned directory behind. The runtime suite creates synthetic
users/sessions and employee-only permissions, plans 47 pgTAP assertions, then
rolls everything back. It covers own registration/idempotency, foreign
scope/installation/removal, reactivation at the device cap, recipient outbox
separation, lease exclusion/retry/stale finish, link/module/MFA revocation,
retained expired sessions, session deletion and private-target erasure. Never run
it against a hosted project. Preparing the suite and passing mocked runner tests
are not successful PostgreSQL runs; compilation, true multi-connection concurrency
and physical FCM delivery remain separate checks.
