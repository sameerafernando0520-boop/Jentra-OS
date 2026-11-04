# Reviewed Sales rollout and rollback procedure

Status: **six-candidate rollback rehearsal passed; installation and deployment not authorized**. Target: Jentra Supabase `xpdoufauvrbdmxgngetv`, Sales Hosting `jentra-os-sales`, separate desktop and Employee clients. The owner separately approved the exact [six-candidate SQL](six-candidate-rollback.sql); [its hosted execution record](../hosted-six-rehearsal.json) confirms restoration and candidate removal. The prepared plan records the earlier pre-execution state. The procedure below describes the approved rehearsal and future separately authorized rollout.

Use [rollout-plan.json](rollout-plan.json) for exact candidate hashes and the four compatibility decisions. They are not owner-accepted. `schema-compatibility.json` checks an actual isolated catalog **column projection** and reports no column incompatibility. It does not inspect function semantics, authorization changes, RLS, installed dependencies or complete hosted-schema compatibility. The generated planner/runbook are reference scaffolding; their generic estimates, placeholder SQL and recovery assumptions are not an approved schedule or executable recovery plan. This document supplies the concrete action and rollback for every generated phase.

## 1. Preparation

Record the release operator, organization owner, tenant/entity/branch IDs, scoped representative, independent approver/progression operator, warehouse/finance owners and customer test recipient. Use approved synthetic business documents and an organization-owned mailbox. Do not copy session tokens, passwords, TOTP seeds, email tokens, codes or provider keys into evidence. Each participating organization supplies its own acceptance record from [organization-acceptance-template.json](organization-acceptance-template.json).

Refresh the actual migration ledger and function signatures immediately before execution. The prepared SQL expects PostgreSQL 17, no installed `field_sales` schema and migration-version MD5 `6ace1fe895a4615fa01746eb2632ae65` (130 migrations at the observed trial). A changed ledger or definition requires review/regeneration. Capture a durable pre-install snapshot of every changed definition, owner/ACL, policies, schema grants, permission/entitlement rows and affected role memberships. Verify available backup/restore facilities with the database owner; none are asserted here.

After new approval, run the **complete** six-candidate rollback file in a fresh SQL Editor snippet. Compare the entire buffer with the reviewed SHA-256, never a selection. It sets a 2-second lock timeout and 45-second per-statement timeout, creates an RLS-protected temporary catalog snapshot, composes all six, checks API/worker grants/default-off policy, rolls back to its savepoint, compares originals and executes outer ROLLBACK. It writes no migration ledger, Auth fixture, sender policy or business order.

Capture the visible final result and source hashes. A timeout, console-rewritten buffer, failed assertion or missing final result fails the rehearsal. On error issue ROLLBACK in that session, verify the candidate schema is absent and compare the preflight state; do not run the remaining fragment. Company sessions and email are not proved by this trial.

Rollback for preparation: the candidate transaction is rolled back; retain the reviewed files and failed evidence. No persistent release is made.

## 2. Expand

Prerequisites: successful exact six-candidate hosted rehearsal, written disposition of FS-COMPAT-01 through 04, verified backup/recovery approach and explicit installation authorization. Review other concurrent workspace/hosted changes first. Install the exact six ordered sources in one migration transaction through the repository's approved migration process; use the returned migration version in the applied filename and ledger documentation. Do not edit previously applied migrations or treat candidate filenames as proof of installation.

Leave all transport/mail policies off, all client flags off and the progression capability unassigned. Confirm private tables have no browser grants; anonymous access is exactly the six purpose-specific response facades; worker access is only the two API-schema service facades. Revoke no unrelated application role or provider credential. Verify ordinary company/Employee behavior before enabling a company.

Rollback for expand: an error before COMMIT rolls back the transaction. After a successful COMMIT, retain the security boundary and all evidence; keep activation off and prepare a reviewed forward correction. Do not drop `field_sales` or restore broad representative legacy grants as a quick recovery. A persistent down migration needs its own data/dependency review and explicit authorization.

## 3. Migrate — explicit per-organization onboarding, no backfill

There is no automatic existing-order conversion. Review each representative's membership and grant exposure, enroll the durable restricted principal, create dated customer assignments/prices and explicitly allocate the three narrow representative capabilities. Removing an assignment must never remove the restricted principal and reopen broad legacy access. Company approvers, confirmation administrators and progression operators receive only reviewed scoped capabilities; existing canonical order/stock/finance permissions remain separately necessary.

Configure the canonical workflow, fiscal periods, numbering, warehouses, products/units, tax and fresh credit projection for the organization. Synthetic local sequences/workflows are fixtures, not proof these exist in the company. Validate representative-to-other-company/customer denial through raw tables, legacy RPCs, finance/export/files, as well as the narrow app facades.

For Resend, the owner supplies an actual domain/subdomain and sender address. Prefer a dedicated transactional subdomain. Add the exact DNS records shown by Resend, verify SPF/DKIM and company DMARC alignment, confirm status verified, turn off click/open tracking for bearer-link messages and record a redacted evidence hash. Do not use a shared testing domain for other organizations. See [verified domains](https://resend.com/docs/dashboard/domains/introduction).

Prepare server-only Resend keys (prefer domain-restricted send access), a cryptographically random 32-byte HMAC key per named version and a separate high-entropy scheduler secret. Store values in the server secret manager, not source, SQL bodies, build defines or this record. The database policy holds only aliases, key fingerprint and domain evidence hash. Keep required old frozen versions available until their jobs expire; do not change template `v1` while eligible frozen jobs exist.

Worker environment contract:

| Name | Value type and boundary |
| --- | --- |
| `SUPABASE_URL` | Exact Jentra project origin |
| `SUPABASE_SECRET_KEYS` | Runtime-provided JSON map of named secret keys; never logged |
| `FIELD_SALES_MAIL_DATABASE_KEY_NAME` | Name in that map, default `default`; legacy runtime service JWT is a fallback only if the map is absent |
| `FIELD_SALES_MAIL_ENABLED` | `false` until approved activation |
| `FIELD_SALES_MAIL_TENANT_IDS` | Private JSON UUID allowlist, 1–100 organizations; caller cannot override |
| `FIELD_SALES_MAIL_PROVIDER_KEYS` | JSON alias-to-Resend-key map; server secret |
| `FIELD_SALES_MAIL_SECRET_KEYS` | JSON version-to-64-lowercase-hex key map; server secret |
| `FIELD_SALES_MAIL_SCHEDULER_SECRET` | Independent random secret, at least 32 characters |

After explicit deployment authorization, deploy `field-sales-mail` with platform JWT verification disabled for this function (`--no-verify-jwt`), because the handler verifies its own scheduler secret. Keep it default disabled. No public CORS or arbitrary body is accepted. Invoke with authenticated POST and an empty body or `{}`; one invocation processes at most one job. Set scheduler capacity from the pilot's measured queue latency and provider limits; a single 1/minute invocation is not a multi-company throughput claim. Monitor expired jobs, attempts, failed/uncertain outcomes, latency, provider acceptance and actual mailbox evidence separately. Request headers/bodies and frozen snapshots must not enter access logs.

Rollback for migrate: stop the scheduler, turn off global mail enablement and affected tenant transport/mail policies, revoke active challenges through the scoped company flow and restore reviewed assignment/capability versions as needed. Keep restricted-principal enrollment and historical responses. Retiring one organization's provider alias/allowlist must not remove another organization's credential or jobs. Already accepted external email cannot be recalled; expired/revoked links fail closed.

## 4. Contract — coordinated clients and genuine acceptance

Deploy only the exact reviewed Sales and desktop bundles after authorization, preserving separate Hosting sites, storage and Employee app. Keep last known compatible versions/manifest identities. Enable the three delivery flags only for the approved candidate release; verify the real hosted bundle/version and policy, not just the local build. Restore a compatible default-disabled client if needed, while leaving server authorization controls in place.

Run these company-owned gates with genuine independent sessions and actual devices:

| Gate | Required observed result |
| --- | --- |
| Genuine Auth/MFA | Real rep and independent company sessions; current AAL2 for privileged actions; AAL1/expired/revoked/other-company sessions denied; MFA reset/scope change clears private UI and pending access |
| Email link | Real approved mailbox receives link, then separately requested code; matching verified sender and minimal content; provider reference and mailbox receipt are separate observations |
| Hosted HTTP/privacy | POST-only named APIs, no-store/no-referrer/frame denial, no token/code in request URL/query/history/log/analytics, scrub fragment before SDK, no customer data on signed-in staff session, GET/scanner/forwarded-link and wrong-code/rate/expiry/revocation tests |
| Company order progression | Approved request remains draft before acceptance; exact accepted response and fresh reviewed credit required; explicit company confirm; stock/reservation/credit override retain their own authority and receipt recovery |
| Delivery acknowledgement | Post real pilot partial deliveries through warehouse authority; explicit independent delivery issue; exact received/refused/short sums and exception note; original retry receipt; no stock/invoice/payment change caused by acknowledgement |
| Compatibility | Ordinary company orders, existing installed dependencies and separate Employee own-employee/bootstrap flows pass; real stocked fulfillment and contention/deadlock checks pass |
| Devices/accessibility | Named Android pilot devices and ordinary supported browsers; phone/tablet/desktop large text, keyboard/screen reader, background, reload, offline, wrong account, restart and lost-scope privacy; iPhone acceptance if offered |
| Pilot owner | Named sales approver, warehouse, finance, customer recipient and organization release owner review evidence and explicitly sign/date their own gates |

Do not send to unapproved customer mailboxes to obtain evidence. Do not use synthetic JWT claims or widget dimensions as genuine sessions/MFA or device proof. Resend acceptance is not delivery acknowledgement. One company's signoff does not authorize every organization.

Rollback for contract: pause new submissions using reviewed dated portfolio assignments/membership controls, keep durable restricted principals, stop affected senders, hide/disable the candidate client, resolve uncertain commands only by original receipts and preserve canonical documents. Warehouse/finance corrections use existing authorized compensating workflows; never delete posted documents or rewrite customer evidence.

## 5. Cleanup and ongoing operation

Only after the pilot owner accepts the exact deployed release, approve the next organization separately. Retain minimal actor/scope/document/version/digest/provider-reference evidence under the organization's retention policy; do not retain mailbox codes or bearer links. Review queue recipient-snapshot retention and access with the owner before production scale; no automatic queue purge is supplied. Retention, support, abuse/edge limits and service alert ownership are release decisions.

Rollback for cleanup: stop rollout expansion, restore the approved compatible client/policy version, preserve audit/response records and forward-correct the service. Do not run the generic generator's placeholder DROP/restore commands. Post-activation incidents require an owner-reviewed recovery plan based on actual data; transaction rollback evidence cannot prove recovery of already sent emails or posted commercial documents.
