# Wave 5 concrete runtime review — October 9, 2026

**Prepared for owner review; no new installation, persistent bootstrap, secret provisioning, deployment or delivery has been approved or performed.** Account labels were confirmed by the owner. The owner will supply host/receiver details. Approval is pending these exact bindings: owner-controlled worker HTTPS URL/reverse-proxy host; exact owner-authorized HTTPS receiver URL and durable event-id deduplication.

Target: `xpdoufauvrbdmxgngetv`. Review bundle SHA-256: `673408b3fffaae8c8099f5cc048e9bf73f0fe10d59cad61798ac27eed66b90c5`. The [machine manifest](runtime-review-20261009.json) includes every proposed UUID, role assignment, plan, source cap, worker parameter and artifact hash. The proposal namespace retains 20261008 because preparation started then; this review is dated October 9. No Auth ID is invented: actual returned Auth Admin IDs will bind the six exact labels.

## Current baseline and scope

[Fresh live catalog](runtime-review-live-20261009.json), observed 2026-10-09 03:53:02.374045+00: 43 migrations / 107 API functions; 87 role-permission rows / 1 assignment / 28 plan entitlements / 1 membership. Plugin Management confirms Supabase enabled. Only the two existing people-private Edge functions are deployed, with unchanged hashes; neither is a Wave 5 worker. The six already-installed migrations remain excluded from this plan; their connector-assigned versions are in [the installation report](installation-result-20261008.md). Expected ledger count after only this proposed installation is **71**; API/catalog/grant counts must be measured after installation.

This is a **28-file dependency closure**, not approval to install every repository migration. Wave 3 AP/statement/export sources and eight Wave 4 payroll/project files are separately owned, retained byte-for-byte and explicitly included for owner review. Wave 3 AP files replace shared residual helpers and extend AP read policies; installation is a database-wide schema/API change even though subsequent data setup is synthetic only. No existing installed migration is replayed. Any hash, prerequisite or live-provider mismatch stops installation for a revised concrete review.

| Order | Exact migration filename | Source owner | SHA-256 |
|---|---|---|---|
| 1 | 20260912153000_procurement_requisition_drafts.sql | Wave 3 | `9b751a04245677ca999b6e11a4b7935a2e577d5080961553df3af30161b49a2c` |
| 2 | 20260913001000_procurement_requisition_workflow.sql | Wave 3 | `05533f3c9b038cc1e023c35869a62b987810d776fbba805621678eaa787579d5` |
| 3 | 20260913002000_procurement_reference_options.sql | Wave 3 | `c56605aa3ab7fafe38dbab4777ca23f731e7a53fd9076ef30a1953fa49adc74c` |
| 4 | 20260913003000_procurement_sourcing.sql | Wave 3 | `d4f92c0fb5c6d24c48d4c21c7184ef042a635abb654c7a53c92129fbc3503d44` |
| 5 | 20260913004000_procurement_purchase_orders.sql | Wave 3 | `8a71252b8bf62a0a8a7325a4683ae770039cecd5c72dc30be131c428636e6795` |
| 6 | 20260913005000_procurement_order_workflow.sql | Wave 3 | `dedb4da3b59ca593a349ecaf4c77fc1adf5dd9e3e56d903726291f6e5e98c077` |
| 7 | 20260913006000_procurement_goods_receipts.sql | Wave 3 | `f38bc858ea03067f56f44208196312842484bd1263b4b9466dc58cb8a7220b76` |
| 8 | 20260913007000_procurement_supplier_bills.sql | Wave 3 | `9212e1dea7c9abcb0e3224ff37bc5a3e1495ea73128bb450f99ef79c4c93c722` |
| 9 | 20260914001000_procurement_supplier_settlement.sql | Wave 3 | `5b776e2dc0eb53a72fa51375f248ab24848768d3141c757233c7b97a4a654bf1` |
| 10 | 20260915001000_payable_allocation_corrections.sql | Wave 3 | `d175cf49fe16783e2d413d46167e99777904b804873e96dbc185992fc2625666` |
| 11 | 20260925002000_wave3_financial_statements.sql | Wave 3 | `7596ec3e5b1ac2b348e4b23371ff6c54818a5336d276fa3a03f14f1ecd5f17b6` |
| 12 | 20260926009000_wave3_governed_report_exports.sql | Wave 3 | `85238e684c967e8377221e55f911fcb9dfa64e7696110ee28eacffe8b6586386` |
| 13 | 20260926160000_wave4_calendar_resolution.sql | Wave 4 | `6abd4dceddbb3124b4bfa01efd97ecafabd59f03ee1f85f48b5bc2a2f5685053` |
| 14 | 20260926161000_wave4_organization.sql | Wave 4 | `6f682652564a030e8a3a6960999aa9c51aa96486ab0f7219d4347f5445e31c45` |
| 15 | 20260928082234_wave4_attendance_intervals.sql | Wave 4 | `21cb1745977492f343f2992ccc915400f9320a82957f342d943e36a50db60ad6` |
| 16 | 20260928083449_wave4_leave_ledger.sql | Wave 4 | `1fbdd603a68f1962291c85a90739f599ee629fef27e5714ee6c00e8a0e37d4b3` |
| 17 | 20260930070000_wave4_synthetic_payroll.sql | Wave 4 | `5517cc4559c3f91901525b38ec8fbf03633da49c587a0d034a885405a43465b2` |
| 18 | 20261001080000_wave4_projects_time.sql | Wave 4 | `52ca0ba293d0a621304e01135db1424e69ebff579f14712b6b6c29d8c031e740` |
| 19 | 20261001100000_wave4_project_expenses_billing.sql | Wave 4 | `0430f55698a28ee7c26a609bc982a96cbc20319d204c3d5546f9a6ae4272efef` |
| 20 | 20261001110000_wave4_payroll_corrections.sql | Wave 4 | `709170a703a5fd6808ba15de27a4b6cfcb33470da977203b960e2d04e67437cf` |
| 21 | 20261008090000_wave5_historical_pipeline.sql | Wave 5 | `183a8688dd2c78a9e13032a165d2e1787b3d8f9dd4a15aee9b201eddf4767768` |
| 22 | 20261008093000_wave5_persistent_delivery.sql | Wave 5 | `1a636229a0749cf9d6334ae49efe8ff38627b6a2d1bb642789a28e86efd1c663` |
| 23 | 20261008100000_wave5_invocation_storage.sql | Wave 5 | `a9bdd3bf5b1593bd3253930c5a0cd6286f576b7f81161a5832919efbc585d6e8` |
| 24 | 20261008103000_wave5_dated_cash.sql | Wave 5 | `24b5ab44250ec5239ab2b942277cb104867d8e67288666c6297d4fa694e4b391` |
| 25 | 20261008110000_wave5_governed_export_adapter.sql | Wave 5 | `fbe68cc451f5044c03be7b68803ff2afbb858004109a5ee2319960d495e193ed` |
| 26 | 20261008113000_wave5_statement_classifications.sql | Wave 5 | `aad2c6cb360490ad653470858a389354c7016f2346b41e26bff8ac8294dc97c3` |
| 27 | 20261008120000_wave5_cash_payment_dates.sql | Wave 5 | `1463953b0fa76269740a732a59485ff3d160681fb2a6655eedbd8c0aeda42c8a` |
| 28 | 20261008123000_wave5_runtime_scope.sql | Wave 5 | `655df9b9bfa373dbbe8872ca802815f9c730c4f3543b72c7950640563e2da8dc` |

The new runtime migration scopes lease expiry, committed-outbox discovery, claims and acknowledged settlement **before** queue mutation. It also scopes external/model actions, quota, scheduled activation and health collection. Only the runtime RT1 branch is registered; sibling/foreign/load branches are excluded from the scheduled worker. A fixed persistent model limit allows at most four distinct invocation records, each <=2000 reserved tokens; rejected or unknown records do not silently reopen a budget after restart.

## Six distinct accounts and exact access

The [final post-rollback read](runtime-review-live-after-20261009.json), observed 2026-10-09 04:35:39.557895+00, preserves all six catalog/access counts above. All six proposed account labels and all proposed tenant/plan names are absent. The [native profile preparation](runtime-native-profile-plan-20261009.json) ran only in read-only Plan mode; it provisioned no account or package.

| Confirmed label | Membership and roles | Runtime purpose |
|---|---|---|
| w5-proposer@jentra.invalid | reader, financeAnchor, proposer | MFA for governed actions; no independent approval authority |
| w5-approver@jentra.invalid | reader, financeAnchor, approver | Distinct MFA approval; no propose/execute |
| w5-executor@jentra.invalid | reader, financeAnchor, executor | MFA for governed actions; no independent approval authority |
| w5-billing-admin@jentra.invalid | billing | Synthetic billing/invitations in runtime and load-001; other load tenants billing.read |
| w5-operator@jentra.invalid | Separate operator; zero membership/roles | MFA health + owner-bounded grant |
| w5-foreign-member@jentra.invalid | Foreign tenant only | Foreign own-scope read |

Create six new password-login users through Auth Admin with email confirmation and **no email send**. Abort if any exact label already exists; do not adopt it. New random passwords and genuine TOTP enrollments belong to private OS/host secret storage under the exact `Jentra/W5/20261008/<label>/password` and `.../totp` references. Auth Admin creation, actual enroll/challenge/verify and returned server session IDs are separate evidence. A stored factor is not AAL2. Do not construct JWT claims for runtime evidence or extract any existing session/credential. The earlier `test@test.com` account and Jentra Acceptance Lab stay untouched.

Main runtime scope: tenant `babe6c86-a764-4d3a-80a3-952a7c096c2c`, entity `caa2bb06-219a-47e9-8132-66d1271b0ffd`, RT1 `3813692c-f0de-4c69-8e34-d56cf54695b1`; RT2 `ed14db1b-8088-4e4d-89e0-34da88d2d769` is a denial target. Foreign tenant `c1ae4d89-6379-45ef-8ee8-1779593eb8d9`, entity `2a082915-10ed-47a1-8985-8c0368b53116`, branch `5de9d678-48af-4db1-8310-f367bb53088d` belongs only to the foreign member. The manifest enumerates 498 additional load tenants. Only new runtime/load-001 tenants enter synthetic activation/seat guarding. Four business actors have explicit load-reader or billing-reader scope; approval/execution authority is not copied across the load tenants.

- **reader**: entity + RT1 branch; requires_mfa=false; `analytics.view`, `workflow.process.view`, `crm.opportunities.view`, `finance.view`, `finance.receivables.view`, `sales.returns.view`, `procurement.bills.view`, `people.view`, `people.payroll.view`, `projects.view`, `projects.cost.view`, `ai.proposals.view`, `analytics.reports.view`.
- **financeAnchor**: entity; required by W3 statement/export parent checks; requires_mfa=false; `finance.view`, `finance.reports.export`.
- **proposer**: entity + RT1 branch; requires_mfa=false; `ai.proposals.manage`, `analytics.reports.manage`, `analytics.cash_dates.prepare`, `integrations.manage`, `finance.reports.export`.
- **approver**: entity + RT1 branch; requires_mfa=true; `ai.proposals.approve`, `analytics.cash_dates.approve`, `finance.classifications.approve`.
- **executor**: entity + RT1 branch; requires_mfa=true; `ai.proposals.execute`.
- **billing**: runtime + load-001 tenant only; requires_mfa=true; `billing.read`, `billing.synthetic.manage`, `core.members.invite`.
- **foreignReader**: foreign entity + branch only; requires_mfa=false; `analytics.view`, `workflow.process.view`, `crm.opportunities.view`.
- **loadReader**: load entity + branch only; requires_mfa=false; `analytics.view`, `workflow.process.view`, `crm.opportunities.view`.
- **loadBilling**: load tenant only; requires_mfa=false; `billing.read`.

Proposer source/integration delegation remains AAL1 under the reviewed existing worker contract; registration, key rotation, date decisions and export actions perform their own explicit MFA checks. Privileged approver/executor/billing roles require MFA. W3 statement/export parent checks require the financeAnchor entity assignment; it is limited to finance.view/export, while analytics/source branches remain RT1. There is no tenant owner/all-permissions role.

## Synthetic plans and bootstrap operations

| New plan only | Seats | Explicit enabled entitlements/limits |
|---|---|---|
| w5_runtime_20261008 | 5 | analytics; module.ai; module.projects; module.finance; quota.ai.tokens = 8000; quota.webhook.deliveries = 100; quota.integration.commands = 200 |
| w5_load_20261008 | 4 | analytics; quota.ai.tokens = 0; quota.webhook.deliveries = 0; quota.integration.commands = 0 |
| w5_quota10_20261008 | 4 | analytics; quota.ai.tokens = 10; quota.webhook.deliveries = 10; quota.integration.commands = 10 |
| w5_foreign_20261008 | 1 | analytics; quota.ai.tokens = 0; quota.webhook.deliveries = 0; quota.integration.commands = 0 |

Trials start at database setup time and end seven days later, half open. Run synthetic schedule/activation before first quota reservation, then record its actual authoritative period for later requests. Existing starter and other plan entitlement values are not activated or modified by bootstrap. All quantities are exact integer/decimal strings; no payment provider or real collection is configured.

[Exact bootstrap SQL](runtime-bootstrap-20261008.sql) creates 500 tenants, 500 entities, 501 branches, 1997 memberships, 1003 explicit roles and 2003 assignments. The reviewed membership/role mappings passed [10 strict rollback assertions](runtime-bootstrap-probe-result-20261009.json). That probe uses test-only Auth shapes and missing permission-name registrations to validate relational mappings; it is not real Auth provisioning or a full installed-provider test. The separate full 28-file composition passed [63 strict assertions](runtime-candidate-final-result-20261009.json), including real Wave 3 reversal tables and actual Wave 4 schemas. Its cash fixture has empty AR/AP; it does not close nonempty all-family runtime acceptance. Both probes rolled back. Earlier failed/time-out attempts are retained.

The proposed persistent source caps are 200 opportunities/800 process events/100 posted journals/200 journal lines/120 AR+AP open items per synthetic tenant, plus runtime-only 10 payroll obligations, 4 signed corrections, 10 reimbursements, 3 financial publications, 1 independent classification review, 4 scenarios and 8 governed exports. Seed only these new scopes with clearly synthetic bodies, balanced immutable journals and authentic source relationships. Initial synthetic source rows are setup fixtures; acceptance of authenticated producer commands remains a separate claim. No accepted store, employee, invoice or journal is copied from an existing tenant. Persist the actual distribution/row counts before load; these caps authorize a maximum, not an assertion that rows already exist.

## Separate operator and bounded grant

Register only `w5-operator@jentra.invalid` in the separate operator table; active/health_read/grant_manage=true, zero tenant memberships/roles. The additive guard restricts that actor both as issuer and recipient to the exact main runtime tenant, exact reviewed reason and a fixed 45-minute authority deadline. It rejects a foreign tenant, another operator, changed reason or later expiry. Other existing operator records are unaffected.

Run [the exact authority SQL](runtime-operator-authority-20261008.sql) immediately before this phase. Then the real AAL2 operator uses the **installed** `issue_operator_tenant_grant` API to issue a 30-minute grant within that deadline. Record its server-generated ID, immutable receipt/audit and actual expiry. No grant is inserted by the setup SQL. Prove tenant-member/owner denial, AAL1 denial, foreign grant denial, audited selected-tenant reads and real expiry. The operator cannot grant or extend authority beyond the approved guard.

## Worker, provider and secret configuration

Worker runtime ID: `778237e3-3d4e-4871-8cc9-e08b07b989c7`; Node 24 host supplied by owner; loopback listener `127.0.0.1:8785` behind that host's HTTPS reverse proxy. Expose only `POST /v1/external/forecast` and `POST /v1/model/suggestion`, bounded 64KiB body and 8 active handlers. Delivery/synthetic scheduling is every 15s, batches 20/50; health is every 60s for the runtime tenant only. Stop expires/revokes the scope and preserves immutable unknown outcomes. Startup refuses unbound URLs, missing explicit owner approval, altered source hashes or missing private configuration **before network/provisioning**. [Prepared launcher](../../../workers/wave5/runtime_launcher.mjs); its artifact and all dependency hashes are in the manifest. The 38 worker tests are controlled transports/policy tests, not actual delivery.

Worker public URL: **pending owner host details**. Receiver: **pending exact owner HTTPS receiver**. The final receiver allowlist must contain its single exact hostname. TLS port 443, public-only DNS on every attempt, pinned resolved address with original TLS hostname, no redirects/proxies; 10s timeout, <=8KiB payload and <=64KiB response. Receiver must durably deduplicate event IDs and record exact signed bytes/digest plus acknowledgement. Test-only redirect/timeout/replay modes need explicitly bound paths on that same receiver in the final review; no alternate public service is implied.

HMAC keys are two distinct 32-byte random values, refs `w5/runtime/20261008/delivery/v1` and `.../v2`, injected as `W5_DELIVERY_KEY_V1`/`V2`. Signature is HMAC-SHA256 of `timestamp.eventId.` followed by exact UTF-8 payload bytes, header `x-jentra-signature: v<keyVersion>=<digest>`; event/timestamp headers are `x-jentra-event-id`/`x-jentra-timestamp`. Maximum eight durable attempts, exponential delay 15s to 1h; unknown stays reserved until reviewed reconciliation, and acknowledged settlement never requires a resend. MFA registration/key rotation/revocation/reviewed replay uses the candidate APIs and exact runtime scope.

External credential ID `ae3f4a8b-3272-4abc-81c3-b074bf5d575d`; subscription ID `58699e8a-28fd-4356-8cad-87ce46e17ddd`. New 32-byte random credential, hash stored server-side, 24h expiry, exact RT1 scope, schema 1, command `analytics.freeze_pipeline.v1`, throttle 60 new requests/minute and quota 200 for the authoritative period. Raw credential exists only in the reviewed private caller/host secret store; use `W5_EXTERNAL_CREDENTIAL`. Register/revoke through real MFA and verify scope/schema/expiry/throttle denial precedes effects.

Server injection refs: `W5_SUPABASE_SERVICE_ROLE_JWT`, `W5_SUPABASE_PUBLISHABLE_KEY`, `W5_OPENAI_API_KEY` and the keys above. The Node transport requires a legacy service_role JWT; modern secret API keys cannot be used as Authorization bearer tokens. This is a project-wide backend secret and belongs only in the owner-controlled host's secret manager; the application code restricts calls with the scoped server adapter. Do not put it in Flutter, Git, the review, shell history or logs, and never retrieve it from another chat. Connected tools expose publishable keys but do not currently expose a secure server-key provisioning operation; actual host injection must be completed privately before launch. [Supabase API-key contract](https://supabase.com/docs/guides/api/api-keys).

Proposed reviewed model: OpenAI Responses `gpt-4.1-mini-2025-04-14`, policy 1, numeric-only `pipeline.current_weighted.v1`; no actor names, business text, HR, credentials or tools. At most 4 durable distinct invocations, <=2000 tokens each, total quota 8000; full-input token count first, actual provider usage settlement, store=false/background=false/tools=[]/truncation=disabled, 30s timeout, bounded structured output <=8KiB. Only the five immutable forecast suggestion fields are accepted; human submission and distinct approval remain separate. Explicit owner approval must cover this model/provider and external calls. [Pinned model/Responses support](https://developers.openai.com/api/docs/models/gpt-4.1-mini), [input-token endpoint](https://developers.openai.com/api/reference/typescript/resources/responses/subresources/input_tokens). Provider credentials/readiness and actual model delivery remain open.

## Execution after final approval

[Fresh cash source/build/render verification](cash-dates-verification-20261009.md) passes scoped analysis, 72 domain, 48 platform and 96 desktop tests. The release matches 1051 selected source files and 34 release files, including the current employee workspace registration. Sixty fresh frames were captured and sixteen inspected. This controlled evidence does not satisfy real authenticated native launch, MFA, restart, exports or owner acceptance; the runtime stage below still requires a fresh ordinary configured build on the selected isolated Windows profile.

1. Freeze final endpoint/native bindings and review hash; record explicit owner message against that hash. Refresh ledger, signatures, all reviewed hashes and collisions. Install only the listed files through the migration connector, mapping actual assigned versions; rerun strict installed checks with rollback data.
2. Privately create the six real Auth users, enroll/challenge/verify TOTP, bind returned IDs, then execute this exact new-scope bootstrap and verify existing-scope fingerprints/counts unchanged. Start real independent sessions. Schedule/activate synthetic billing before usage, including half-open boundaries, version/quota/seat conflict.
3. Create nonempty synthetic authoritative source rows within caps. Authenticate proposed dates, signed recovery, classifications, scenarios and human/model proposals; reject self/aal1/stale/expired approvals and recheck current rights on execution/reopen.
4. Provision only reviewed secret refs/host/receiver, register integration/credential through real MFA, and start the scoped worker. Capture actual receiver bytes/signature/receipt, key rotation, revocation during lookup, redirection/timeout rejection, dead letters/reviewed replay, crash recovery between send/outcome/settlement and actual provider usage. Never auto-resend unknown state.
5. Issue and exercise the bounded operator MFA grant. Build a fresh ordinary runtime Windows executable with the actual publishable project configuration in the **isolated Windows target** (new standard local Windows profile jentra-w5-runtime); record source/release hashes before rendered evidence. Do not use the controlled-render entrypoint or shared local database/session stores. Verify actual native light/dark/density/200% text/keyboard, source revocation, login switch, encrypted recovery/restart and governed CSV/XLSX creation/download/reopen with current authorization and exact byte hash.
6. Use a real barrier and at least two independent authenticated/trusted sessions for 100 duplicates per command family, quota-10 overcommit, overlapping version decisions/activation and seat admission. In load-001, revoke two existing reviewed business memberships, reduce seats to 3 with two active, issue no-email scoped invitations to those same approver/executor labels, and race actual invitation acceptance for the last seat; do not admit the separate operator/foreign member. Record actual session IDs (no tokens), overlap times and committed effect counts. Sequential replay loops do not pass this gate.
7. Mint 2000 separately server-authenticated sessions, verify distinct session IDs, and run 500-tenant load: four business actors across 499 owned scopes =1996 plus four foreign-member sessions; operator excluded. No global Auth rate-limit/single-session setting changes. Publish reference hardware/project tier and actual row distributions; warmup 60s, measure 300s, stop at 900s/100000 timed requests. Workload 70% indexed reads / 20% ordinary forecast commands / 10% bounded analytics; required p95 <500ms/<1.5s/<3s. Test 10001-row/101-group/367-day/8MiB+1-byte failures. No model/webhook sends are part of load. Auth/host capacity failures are failures, not substitute session evidence.
8. Present the evidence to the owner for each of 109 criteria. Owner approval to run is not owner acceptance. Thirteen shared dashboard/setup golden failures remain unresolved; no approved goldens are regenerated. Real billing and production remain excluded.

## Approval boundary

The owner delegated native target selection. WindowsSandbox.exe is unavailable here, so the exact native target is a **new standard local Windows account** `jentra-w5-runtime`, with fresh AppData/secure keys/Supabase sessions. This OS test profile is separate from the six Supabase accounts. After approval, administrator-only [profile preparation](../../../scripts/wave5/prepare_native_runtime_profile.ps1) creates that one standard Users-group account and copies only a freshly source/hash-verified ordinary release into `C:\Users\Public\Documents\JentraWave5Runtime\20261009` with private/read-only ACLs for the test user. It refuses existing account/package collisions; no reset, account adoption or cleanup is implied. Password ref: `Jentra/W5/20261009/native-profile/password`, supplied as private SecureString. OS-account/profile creation and this exact directory/ACL/copy operation are included in the proposed approval. No profile has been created and Windows Sandbox is not enabled/installed.

This document does **not** request approval of unresolved host/receiver bindings. Supply those exact values without secrets; regenerate one final bound manifest and review hash, then request one approval covering the exact 28 files, six Auth labels, 500 synthetic scopes/roles/plans/source caps, bounded operator authority, listed secret references, native OS test profile/package, host deployment, receiver/OpenAI calls and runtime/contention/load execution. Nothing is installed or provisioned until that approval. Any new source, destination, identity, entitlement, secret reference or scope requires a revised review before dependent work.

Installed SQL, candidate rollback, bootstrap mapping, controlled workers, authenticated native, actual delivery/model usage, independent contention, target-scale latency and owner signoff remain separate evidence gates. **Wave 5 remains incomplete.**
