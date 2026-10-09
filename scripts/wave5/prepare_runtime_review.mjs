import {readFile,writeFile} from 'node:fs/promises';
import {createHash} from 'node:crypto';
import path from 'node:path';
import {fileURLToPath} from 'node:url';
import {accounts,assignments,id,migrationFiles,plans,projectId,roles,scopes,workerConfig} from './runtime_plan.mjs';
const root=path.resolve(path.dirname(fileURLToPath(import.meta.url)),'../..');
const base='docs/verification/wave5/';
const hash=bytes=>createHash('sha256').update(bytes).digest('hex');
const readJson=async file=>JSON.parse(await readFile(path.join(root,file),'utf8'));
const sourceHash=async file=>hash(await readFile(path.join(root,file)));
const config=structuredClone(workerConfig);
let bindings={};if(process.argv[2])bindings=await readJson(process.argv[2]);
if(bindings.workerBaseUrl)config.hostBinding.publicBaseUrl=bindings.workerBaseUrl;
if(bindings.receiverUrl){const u=new URL(bindings.receiverUrl);if(u.protocol!=='https:'||u.username||u.password||u.hash||u.search||u.port&&u.port!=='443')throw Error('RECEIVER_BINDING_INVALID');config.receiver.url=u.href;config.receiver.allowedHosts=[u.hostname];}
config.nativeIsolation={target:'new standard local Windows profile jentra-w5-runtime',windowsAccount:'jentra-w5-runtime',
 packageDirectory:'C:\\Users\\Public\\Documents\\JentraWave5Runtime\\20261009',passwordReference:'Jentra/W5/20261009/native-profile/password',
 provisioned:false,requiresOwnerApproval:true,administratorSetupOnly:true,reason:'WindowsSandbox.exe is unavailable; owner delegated target selection',
 required:'fresh AppData, Windows secure keys and Supabase sessions; never open the shared acceptance database/session stores'};
const pending=[];if(!config.hostBinding.publicBaseUrl)pending.push('owner-controlled worker HTTPS URL/reverse-proxy host');
if(!config.receiver.url)pending.push('exact owner-authorized HTTPS receiver URL and durable event-id deduplication');
const migrations=await Promise.all(migrationFiles.map(async(file,index)=>({order:index+1,path:`supabase/migrations/${file}`,sha256:await sourceHash(`supabase/migrations/${file}`),
 owner:file.includes('wave4')?'Wave 4':file.includes('wave5')?'Wave 5':'Wave 3',installed:false})));
const w4=await readJson(base+'cash-dates-wave4-source-baseline-20261008.json');
for(const [file,expected] of Object.entries(w4.sources))if(await sourceHash(file)!==expected)throw Error('WAVE4_OWNED_SOURCE_CHANGED');
const earlier=await readJson(base+'remaining-candidate-20261008.hashes.json');
for(const m of migrations)if(earlier.candidateSources[m.path]&&earlier.candidateSources[m.path]!==m.sha256)throw Error('EARLIER_REVIEW_SOURCE_CHANGED');
const fixtureHash=await readJson(base+'runtime-candidate-20261008.hashes.json');
for(const [file,expected]of Object.entries(fixtureHash.sources))if(await sourceHash(file)!==expected)throw Error('VERIFIED_SOURCE_CHANGED');
const workerFiles=(await import('node:fs/promises')).readdir;
const workerNames=await workerFiles(path.join(root,'workers/wave5'));
const artifactPaths=[...workerNames.filter(f=>f.endsWith('.mjs')).sort().map(f=>`workers/wave5/${f}`),
 'scripts/wave5/runtime_plan.mjs','scripts/wave5/prepare_runtime_scope.mjs','scripts/wave5/prepare_runtime_bootstrap.mjs',
 'scripts/wave5/prepare_runtime_bootstrap_probe.mjs','scripts/wave5/prepare_runtime_candidate.mjs','scripts/wave5/prepare_runtime_review.mjs',
 'scripts/wave5/prepare_native_runtime_profile.ps1',
 'scripts/wave5/cash_ui_evidence.mjs','scripts/wave5/run_cash_dates_verification.ps1','scripts/wave5/record_runtime_review_status.mjs',
 base+'runtime-bootstrap-20261008.sql',base+'runtime-operator-authority-20261008.sql',base+'runtime-bootstrap-probe-20261008.sql',
 base+'runtime-candidate-20261008.sql',base+'runtime-candidate-20261008.hashes.json',
 base+'runtime-review-live-20261009.json',base+'runtime-review-live-after-20261009.json',
 base+'runtime-review-plugin-20261009.json',base+'runtime-review-edge-20261009.json',base+'runtime-native-profile-plan-20261009.json',
 base+'runtime-candidate-final-result-20261009.json',
 base+'runtime-bootstrap-probe-result-20261009.json',base+'runtime-worker-tests-20261009.json',
 base+'cash-dates-verification-20261009.json',base+'cash-dates-verification-20261009.md',
 base+'cash-dates-workspace-drift-20261009.json',base+'cash-dates-run-20261009.json',base+'cash-dates-snapshot-20261009.json'];
const artifacts=await Promise.all(artifactPaths.map(async file=>({path:file,sha256:await sourceHash(file)})));
const matrix=await readJson(base+'requirement-matrix-20261008.json');
if(matrix.rows.length!==109||matrix.rows.some(r=>r.ownerAccepted))throw Error('ACCEPTANCE_STATE_CHANGED');
function resultRows(raw){const text=raw.content.find(c=>c.type==='text').text;const wrapped=JSON.parse(text).result;const start=wrapped.indexOf('\n['),end=wrapped.indexOf('\n</untrusted-data-');return JSON.parse(wrapped.slice(start+1,end));}
const live=resultRows(await readJson(base+'runtime-review-live-20261009.json'))[0];
const liveAfter=resultRows(await readJson(base+'runtime-review-live-after-20261009.json'))[0];
if(liveAfter.migration_count!==live.migration_count||liveAfter.api_functions!==live.api_functions||
 liveAfter.role_permissions!==live.role_permission_count||liveAfter.role_assignments!==live.role_assignment_count||
 liveAfter.plan_entitlements!==live.entitlement_count||liveAfter.memberships!==live.membership_count||
 liveAfter.proposed_account_collisions!==null||liveAfter.proposed_tenant_collisions!==0||liveAfter.proposed_plan_collisions!==0)throw Error('POST_ROLLBACK_BASELINE_CHANGED');
const tap=resultRows(await readJson(base+'runtime-candidate-final-result-20261009.json'))[0].tap;
const bootstrapTap=resultRows(await readJson(base+'runtime-bootstrap-probe-result-20261009.json'))[0].tap;
if(tap.length!==63||bootstrapTap.length!==10||[...tap,...bootstrapTap].some(t=>!/^ok \d+ -/.test(t)))throw Error('STRICT_EVIDENCE_MISSING');
const workerEvidence=await readJson(base+'runtime-worker-tests-20261009.json');
if(workerEvidence.exit_code!==0||!workerEvidence.output.includes('tests 38')||!workerEvidence.output.includes('fail 0'))throw Error('WORKER_EVIDENCE_MISSING');
const cash=await readJson(base+'cash-dates-verification-20261009.json');
if(!cash.current_source_match||!cash.buildSucceeded||cash.frames.length!==60||cash.visualReview.inspectedFrames.length!==16||
 Object.values(cash.stages).some(s=>!s.passed)||cash.authenticatedAcceptance||cash.ownerAccepted)throw Error('FRESH_CASH_EVIDENCE_MISSING');
const installation=await readJson(base+'installation-result-20261008.json');
const accountPlan=accounts.map(a=>({...a,secretReferences:{password:`Jentra/W5/20261008/${a.label}/password`,totp:`Jentra/W5/20261008/${a.label}/totp`},
  mainRoles:assignments[a.label],loadRoles:a.label==='operator'||a.label==='foreign-member'?[]:a.label==='billing-admin'?['loadBilling; billing in load-001']:['loadReader']}));
const body={reviewId:'jentra-wave5-runtime-20261009',preparedAt:new Date().toISOString(),projectId,
 approvalReady:pending.length===0,ownerApproved:false,pendingBindings:pending,
 liveBaseline:{observedAt:live.checked_at,migrations:live.migration_count,apiFunctions:live.api_functions,rolePermissions:live.role_permission_count,
 roleAssignments:live.role_assignment_count,entitlements:live.entitlement_count,memberships:live.membership_count,
 installedSixNeverReplayed:true,expectedLedgerAfterOnlyThisInstall:live.migration_count+migrations.length,existingProviderFingerprintsRecheckRequired:true,
 postRollbackObservedAt:liveAfter.observed_at,postRollbackCountsUnchanged:true,proposedAccountsTenantsPlansAbsent:true},
 accounts:accountPlan,roles,assignments,syntheticPlans:plans,syntheticScopes:scopes,
 bootstrap:{authAdminOnly:true,emailConfirm:true,emailDelivery:false,accountCollisionAction:'abort, never adopt an existing label',
  tenants:500,entities:500,branches:501,memberships:1997,roles:1003,roleAssignments:2003,
  syntheticActivationAllowlist:['runtime','load-001'],businessDataOnlyInReviewedNewTenants:true,existingAcceptanceLabUntouched:true,
  sourceFixtureLimits:{perTenant:{opportunities:200,processEvents:800,postedJournals:100,journalLines:200,openItems:120},
   runtimeOnly:{payrollObligations:10,payrollCorrections:4,projectReimbursements:10,financialPublications:3,classificationReviews:1,cashScenarios:4,governedExports:8},
   invitationTargets:['w5-approver@jentra.invalid','w5-executor@jentra.invalid'],invitationTenant:'load-001',externalEmail:false}},
 workerConfiguration:config,
 execution:{requiresFinalBoundReviewApproval:true,stages:['refresh live/source fingerprints and hash preflight','install only exact new migrations, retaining assigned ledger-version mapping',
 'create six Auth Admin accounts and bind returned IDs; real private TOTP verification','execute exact reviewed synthetic bootstrap; verify counts and zero existing-scope changes',
 'synthetic billing schedule/activation before first quota reservation; real independent sessions','create nonempty authorized source data within fixture caps; distinct MFA dates/classifications/proposal approval and revocation',
 'bind/provision reviewed private secrets, register exact receiver and credential through real MFA, start scoped worker',
 'verify signed delivery, key rotation/revocation, retries/dead letters/reviewed replay and actual model usage','issue operator authority and real MFA grant, prove exact scope/audit/expiry',
 'native fresh build/source attribution, actual login, exports/reopen/restart/keyboard/revocation on isolated Windows target',
 'barrier-based independent-session contention and exact before/after counts','500 tenants / 2000 real concurrent sessions target-scale load','owner review of evidence against all 109 identifiers'],
 contention:{duplicates:100,quotaLimit:'10',competingReservations:'20 independent reservations of 1 unit',independentSessions:true,
  overlapEvidence:['real Auth session IDs (IDs only; no JWTs)','server backend/connection identities where supported','barrier/start/end timestamps','same original command/idempotency identities','committed before/after counts'],
  seatRace:'load-001 only: deactivate reviewed approver/executor memberships, set synthetic seats to 3 with 2 active members, invite those same two accounts without email; race actual accept_invitation sessions for the final seat',
  authorityRevocations:'only newly reviewed assignments/scopes; exact restoration, never an existing acceptance role'},
 load:{tenants:500,concurrentSessions:2000,realSessionDistribution:'4 sessions sets for four business actors across runtime + 498 load tenants = 1996; four independent foreign-member sessions = 2000; operator excluded',
  uniqueAuthSessionIdsRequired:true,noConstructedJwtClaims:true,noGlobalAuthRateLimitOrSingleSessionChanges:true,
  warmupSeconds:60,measuredSeconds:300,maxRunSeconds:900,connectionLimit:2000,workloadPercent:{indexedReads:70,ordinaryForecastCommands:20,boundedAnalytics:10},
  p95LimitsMs:{indexedReads:500,ordinaryCommands:1500,boundedAnalytics:3000},maximumTimedRequests:100000,
  actualHardwareDatabaseTierAndRowDistributionsRequired:true,invalidBoundaries:['10001 rows','101 groups','367-day window beyond 366-day maximum','8MiB + 1 byte'],
  apiModelAndWebhookDeliveryExcludedFromLoad:true,hostOrAuthLimitFailureMustBeRecordedAsIncomplete:true},
 ownerAcceptance:{criteria:matrix.rows.map(r=>({id:r.id,ownerAccepted:false})),agentMayNotSelfSign:true,sharedGoldenFailures:13,blindGoldenRegeneration:false}},
 evidence:{candidateStrictAssertions:63,candidateRolledBack:true,bootstrapMappingStrictAssertions:10,bootstrapMappingRolledBack:true,
  bootstrapUsesTestOnlyAuthShapesAndPermissionRegistration:true,controlledWorkerTests:38,installedNewMigrations:false,realMfa:false,
  authenticatedNative:false,actualWorkerDelivery:false,actualModelUsage:false,independentContention:false,targetScaleLoad:false,ownerSignoff:false,
  previousSixInstalledAssertions:installation.installedStrictSqlPassed,
  cashSourceRender:{observedAt:cash.capturedAt,sourceFiles:cash.sourceFileCount,releaseFiles:cash.releaseFileCount,frames:60,inspectedFrames:16,
   analysis:true,domainTests:cash.stages.domainTests.assertions,platformTests:cash.stages.platformTests.assertions,nativeTests:cash.stages.nativeTests.assertions,
   sourceMatch:true,sourceAttributionScope:cash.sourceAttributionScope,wholeWorkspaceSourceMatch:cash.workspace_source_match,
   concurrentOutsideScopeChanges:cash.workspaceSourceChangesSinceSnapshot,
   scope:'October 9 controlled desktop dependency source/render evidence; does not prove authenticated runtime'}},
 migrations,artifacts,
 exclusions:['real billing collection','production','existing acceptance accounts, sessions and stores','other chats credentials','broad staging, reset, clean, commit or push','external destinations except final bound receiver and reviewed OpenAI endpoints']};
const review={...body,bundleSha256:hash(JSON.stringify(body))};
await writeFile(path.join(root,base+'runtime-review-20261009.json'),JSON.stringify(review,null,2)+'\n');
const rows=migrations.map(m=>`| ${m.order} | ${m.path.split('/').at(-1)} | ${m.owner} | \`${m.sha256}\` |`).join('\n');
const roleRows=accountPlan.map(a=>`| ${a.email} | ${a.label==='operator'?'Separate operator; zero membership/roles':a.label==='foreign-member'?'Foreign tenant only':a.mainRoles.join(', ')} | ${a.label==='operator'?'MFA health + owner-bounded grant':a.label==='foreign-member'?'Foreign own-scope read':a.label==='billing-admin'?'Synthetic billing/invitations in runtime and load-001; other load tenants billing.read':a.label==='approver'?'Distinct MFA approval; no propose/execute':'MFA for governed actions; no independent approval authority'} |`).join('\n');
const entitlementRows=plans.map(p=>`| ${p.code} | ${p.seats} | ${Object.entries(p.entitlements).map(([k,v])=>typeof v==='boolean'?k:`${k} = ${v}`).join('; ')} |`).join('\n');
const rolePermissions=Object.entries(roles).map(([name,r])=>`- **${name}**: ${r.scope}; requires_mfa=${r.requiresMfa}; ${r.permissions.map(p=>'\`'+p+'\`').join(', ')}.`).join('\n');
const text=`# Wave 5 concrete runtime review — October 9, 2026

**Prepared for owner review; no new installation, persistent bootstrap, secret provisioning, deployment or delivery has been approved or performed.** Account labels were confirmed by the owner. The owner will supply host/receiver details. Approval is pending these exact bindings: ${pending.join('; ')||'none'}.

Target: \`${projectId}\`. Review bundle SHA-256: \`${review.bundleSha256}\`. The [machine manifest](runtime-review-20261009.json) includes every proposed UUID, role assignment, plan, source cap, worker parameter and artifact hash. The proposal namespace retains 20261008 because preparation started then; this review is dated October 9. No Auth ID is invented: actual returned Auth Admin IDs will bind the six exact labels.

## Current baseline and scope

[Fresh live catalog](runtime-review-live-20261009.json), observed ${live.checked_at}: ${live.migration_count} migrations / ${live.api_functions} API functions; ${live.role_permission_count} role-permission rows / ${live.role_assignment_count} assignment / ${live.entitlement_count} plan entitlements / ${live.membership_count} membership. Plugin Management confirms Supabase enabled. Only the two existing people-private Edge functions are deployed, with unchanged hashes; neither is a Wave 5 worker. The six already-installed migrations remain excluded from this plan; their connector-assigned versions are in [the installation report](installation-result-20261008.md). Expected ledger count after only this proposed installation is **71**; API/catalog/grant counts must be measured after installation.

This is a **28-file dependency closure**, not approval to install every repository migration. Wave 3 AP/statement/export sources and eight Wave 4 payroll/project files are separately owned, retained byte-for-byte and explicitly included for owner review. Wave 3 AP files replace shared residual helpers and extend AP read policies; installation is a database-wide schema/API change even though subsequent data setup is synthetic only. No existing installed migration is replayed. Any hash, prerequisite or live-provider mismatch stops installation for a revised concrete review.

| Order | Exact migration filename | Source owner | SHA-256 |
|---|---|---|---|
${rows}

The new runtime migration scopes lease expiry, committed-outbox discovery, claims and acknowledged settlement **before** queue mutation. It also scopes external/model actions, quota, scheduled activation and health collection. Only the runtime RT1 branch is registered; sibling/foreign/load branches are excluded from the scheduled worker. A fixed persistent model limit allows at most four distinct invocation records, each <=2000 reserved tokens; rejected or unknown records do not silently reopen a budget after restart.

## Six distinct accounts and exact access

The [final post-rollback read](runtime-review-live-after-20261009.json), observed ${liveAfter.observed_at}, preserves all six catalog/access counts above. All six proposed account labels and all proposed tenant/plan names are absent. The [native profile preparation](runtime-native-profile-plan-20261009.json) ran only in read-only Plan mode; it provisioned no account or package.

| Confirmed label | Membership and roles | Runtime purpose |
|---|---|---|
${roleRows}

Create six new password-login users through Auth Admin with email confirmation and **no email send**. Abort if any exact label already exists; do not adopt it. New random passwords and genuine TOTP enrollments belong to private OS/host secret storage under the exact \`Jentra/W5/20261008/<label>/password\` and \`.../totp\` references. Auth Admin creation, actual enroll/challenge/verify and returned server session IDs are separate evidence. A stored factor is not AAL2. Do not construct JWT claims for runtime evidence or extract any existing session/credential. The earlier \`test@test.com\` account and Jentra Acceptance Lab stay untouched.

Main runtime scope: tenant \`${scopes[0].tenantId}\`, entity \`${scopes[0].entityId}\`, RT1 \`${scopes[0].branchId}\`; RT2 \`${scopes[0].secondBranchId}\` is a denial target. Foreign tenant \`${scopes[1].tenantId}\`, entity \`${scopes[1].entityId}\`, branch \`${scopes[1].branchId}\` belongs only to the foreign member. The manifest enumerates 498 additional load tenants. Only new runtime/load-001 tenants enter synthetic activation/seat guarding. Four business actors have explicit load-reader or billing-reader scope; approval/execution authority is not copied across the load tenants.

${rolePermissions}

Proposer source/integration delegation remains AAL1 under the reviewed existing worker contract; registration, key rotation, date decisions and export actions perform their own explicit MFA checks. Privileged approver/executor/billing roles require MFA. W3 statement/export parent checks require the financeAnchor entity assignment; it is limited to finance.view/export, while analytics/source branches remain RT1. There is no tenant owner/all-permissions role.

## Synthetic plans and bootstrap operations

| New plan only | Seats | Explicit enabled entitlements/limits |
|---|---|---|
${entitlementRows}

Trials start at database setup time and end seven days later, half open. Run synthetic schedule/activation before first quota reservation, then record its actual authoritative period for later requests. Existing starter and other plan entitlement values are not activated or modified by bootstrap. All quantities are exact integer/decimal strings; no payment provider or real collection is configured.

[Exact bootstrap SQL](runtime-bootstrap-20261008.sql) creates 500 tenants, 500 entities, 501 branches, 1997 memberships, 1003 explicit roles and 2003 assignments. The reviewed membership/role mappings passed [10 strict rollback assertions](runtime-bootstrap-probe-result-20261009.json). That probe uses test-only Auth shapes and missing permission-name registrations to validate relational mappings; it is not real Auth provisioning or a full installed-provider test. The separate full 28-file composition passed [63 strict assertions](runtime-candidate-final-result-20261009.json), including real Wave 3 reversal tables and actual Wave 4 schemas. Its cash fixture has empty AR/AP; it does not close nonempty all-family runtime acceptance. Both probes rolled back. Earlier failed/time-out attempts are retained.

The proposed persistent source caps are 200 opportunities/800 process events/100 posted journals/200 journal lines/120 AR+AP open items per synthetic tenant, plus runtime-only 10 payroll obligations, 4 signed corrections, 10 reimbursements, 3 financial publications, 1 independent classification review, 4 scenarios and 8 governed exports. Seed only these new scopes with clearly synthetic bodies, balanced immutable journals and authentic source relationships. Initial synthetic source rows are setup fixtures; acceptance of authenticated producer commands remains a separate claim. No accepted store, employee, invoice or journal is copied from an existing tenant. Persist the actual distribution/row counts before load; these caps authorize a maximum, not an assertion that rows already exist.

## Separate operator and bounded grant

Register only \`w5-operator@jentra.invalid\` in the separate operator table; active/health_read/grant_manage=true, zero tenant memberships/roles. The additive guard restricts that actor both as issuer and recipient to the exact main runtime tenant, exact reviewed reason and a fixed 45-minute authority deadline. It rejects a foreign tenant, another operator, changed reason or later expiry. Other existing operator records are unaffected.

Run [the exact authority SQL](runtime-operator-authority-20261008.sql) immediately before this phase. Then the real AAL2 operator uses the **installed** \`issue_operator_tenant_grant\` API to issue a 30-minute grant within that deadline. Record its server-generated ID, immutable receipt/audit and actual expiry. No grant is inserted by the setup SQL. Prove tenant-member/owner denial, AAL1 denial, foreign grant denial, audited selected-tenant reads and real expiry. The operator cannot grant or extend authority beyond the approved guard.

## Worker, provider and secret configuration

Worker runtime ID: \`${config.runtimeId}\`; Node 24 host supplied by owner; loopback listener \`127.0.0.1:8785\` behind that host's HTTPS reverse proxy. Expose only \`POST /v1/external/forecast\` and \`POST /v1/model/suggestion\`, bounded 64KiB body and 8 active handlers. Delivery/synthetic scheduling is every 15s, batches 20/50; health is every 60s for the runtime tenant only. Stop expires/revokes the scope and preserves immutable unknown outcomes. Startup refuses unbound URLs, missing explicit owner approval, altered source hashes or missing private configuration **before network/provisioning**. [Prepared launcher](../../../workers/wave5/runtime_launcher.mjs); its artifact and all dependency hashes are in the manifest. The 38 worker tests are controlled transports/policy tests, not actual delivery.

Worker public URL: **${config.hostBinding.publicBaseUrl??'pending owner host details'}**. Receiver: **${config.receiver.url??'pending exact owner HTTPS receiver'}**. The final receiver allowlist must contain its single exact hostname. TLS port 443, public-only DNS on every attempt, pinned resolved address with original TLS hostname, no redirects/proxies; 10s timeout, <=8KiB payload and <=64KiB response. Receiver must durably deduplicate event IDs and record exact signed bytes/digest plus acknowledgement. Test-only redirect/timeout/replay modes need explicitly bound paths on that same receiver in the final review; no alternate public service is implied.

HMAC keys are two distinct 32-byte random values, refs \`w5/runtime/20261008/delivery/v1\` and \`.../v2\`, injected as \`W5_DELIVERY_KEY_V1\`/\`V2\`. Signature is HMAC-SHA256 of \`timestamp.eventId.\` followed by exact UTF-8 payload bytes, header \`x-jentra-signature: v<keyVersion>=<digest>\`; event/timestamp headers are \`x-jentra-event-id\`/\`x-jentra-timestamp\`. Maximum eight durable attempts, exponential delay 15s to 1h; unknown stays reserved until reviewed reconciliation, and acknowledged settlement never requires a resend. MFA registration/key rotation/revocation/reviewed replay uses the candidate APIs and exact runtime scope.

External credential ID \`${config.external.credentialId}\`; subscription ID \`${config.external.subscriptionId}\`. New 32-byte random credential, hash stored server-side, 24h expiry, exact RT1 scope, schema 1, command \`analytics.freeze_pipeline.v1\`, throttle 60 new requests/minute and quota 200 for the authoritative period. Raw credential exists only in the reviewed private caller/host secret store; use \`W5_EXTERNAL_CREDENTIAL\`. Register/revoke through real MFA and verify scope/schema/expiry/throttle denial precedes effects.

Server injection refs: \`W5_SUPABASE_SERVICE_ROLE_JWT\`, \`W5_SUPABASE_PUBLISHABLE_KEY\`, \`W5_OPENAI_API_KEY\` and the keys above. The Node transport requires a legacy service_role JWT; modern secret API keys cannot be used as Authorization bearer tokens. This is a project-wide backend secret and belongs only in the owner-controlled host's secret manager; the application code restricts calls with the scoped server adapter. Do not put it in Flutter, Git, the review, shell history or logs, and never retrieve it from another chat. Connected tools expose publishable keys but do not currently expose a secure server-key provisioning operation; actual host injection must be completed privately before launch. [Supabase API-key contract](https://supabase.com/docs/guides/api/api-keys).

Proposed reviewed model: OpenAI Responses \`gpt-4.1-mini-2025-04-14\`, policy 1, numeric-only \`pipeline.current_weighted.v1\`; no actor names, business text, HR, credentials or tools. At most 4 durable distinct invocations, <=2000 tokens each, total quota 8000; full-input token count first, actual provider usage settlement, store=false/background=false/tools=[]/truncation=disabled, 30s timeout, bounded structured output <=8KiB. Only the five immutable forecast suggestion fields are accepted; human submission and distinct approval remain separate. Explicit owner approval must cover this model/provider and external calls. [Pinned model/Responses support](https://developers.openai.com/api/docs/models/gpt-4.1-mini), [input-token endpoint](https://developers.openai.com/api/reference/typescript/resources/responses/subresources/input_tokens). Provider credentials/readiness and actual model delivery remain open.

## Execution after final approval

[Fresh cash source/build/render verification](cash-dates-verification-20261009.md) passes scoped analysis, ${cash.stages.domainTests.assertions} domain, ${cash.stages.platformTests.assertions} platform and ${cash.stages.nativeTests.assertions} desktop tests. The release matches ${cash.sourceFileCount} selected source files and ${cash.releaseFileCount} release files, including the current employee workspace registration. Sixty fresh frames were captured and sixteen inspected. This controlled evidence does not satisfy real authenticated native launch, MFA, restart, exports or owner acceptance; the runtime stage below still requires a fresh ordinary configured build on the selected isolated Windows profile.

1. Freeze final endpoint/native bindings and review hash; record explicit owner message against that hash. Refresh ledger, signatures, all reviewed hashes and collisions. Install only the listed files through the migration connector, mapping actual assigned versions; rerun strict installed checks with rollback data.
2. Privately create the six real Auth users, enroll/challenge/verify TOTP, bind returned IDs, then execute this exact new-scope bootstrap and verify existing-scope fingerprints/counts unchanged. Start real independent sessions. Schedule/activate synthetic billing before usage, including half-open boundaries, version/quota/seat conflict.
3. Create nonempty synthetic authoritative source rows within caps. Authenticate proposed dates, signed recovery, classifications, scenarios and human/model proposals; reject self/aal1/stale/expired approvals and recheck current rights on execution/reopen.
4. Provision only reviewed secret refs/host/receiver, register integration/credential through real MFA, and start the scoped worker. Capture actual receiver bytes/signature/receipt, key rotation, revocation during lookup, redirection/timeout rejection, dead letters/reviewed replay, crash recovery between send/outcome/settlement and actual provider usage. Never auto-resend unknown state.
5. Issue and exercise the bounded operator MFA grant. Build a fresh ordinary runtime Windows executable with the actual publishable project configuration in the **isolated Windows target** (${config.nativeIsolation.target??'pending'}); record source/release hashes before rendered evidence. Do not use the controlled-render entrypoint or shared local database/session stores. Verify actual native light/dark/density/200% text/keyboard, source revocation, login switch, encrypted recovery/restart and governed CSV/XLSX creation/download/reopen with current authorization and exact byte hash.
6. Use a real barrier and at least two independent authenticated/trusted sessions for 100 duplicates per command family, quota-10 overcommit, overlapping version decisions/activation and seat admission. In load-001, revoke two existing reviewed business memberships, reduce seats to 3 with two active, issue no-email scoped invitations to those same approver/executor labels, and race actual invitation acceptance for the last seat; do not admit the separate operator/foreign member. Record actual session IDs (no tokens), overlap times and committed effect counts. Sequential replay loops do not pass this gate.
7. Mint 2000 separately server-authenticated sessions, verify distinct session IDs, and run 500-tenant load: four business actors across 499 owned scopes =1996 plus four foreign-member sessions; operator excluded. No global Auth rate-limit/single-session setting changes. Publish reference hardware/project tier and actual row distributions; warmup 60s, measure 300s, stop at 900s/100000 timed requests. Workload 70% indexed reads / 20% ordinary forecast commands / 10% bounded analytics; required p95 <500ms/<1.5s/<3s. Test 10001-row/101-group/367-day/8MiB+1-byte failures. No model/webhook sends are part of load. Auth/host capacity failures are failures, not substitute session evidence.
8. Present the evidence to the owner for each of 109 criteria. Owner approval to run is not owner acceptance. Thirteen shared dashboard/setup golden failures remain unresolved; no approved goldens are regenerated. Real billing and production remain excluded.

## Approval boundary

The owner delegated native target selection. WindowsSandbox.exe is unavailable here, so the exact native target is a **new standard local Windows account** \`jentra-w5-runtime\`, with fresh AppData/secure keys/Supabase sessions. This OS test profile is separate from the six Supabase accounts. After approval, administrator-only [profile preparation](../../../scripts/wave5/prepare_native_runtime_profile.ps1) creates that one standard Users-group account and copies only a freshly source/hash-verified ordinary release into \`C:\\Users\\Public\\Documents\\JentraWave5Runtime\\20261009\` with private/read-only ACLs for the test user. It refuses existing account/package collisions; no reset, account adoption or cleanup is implied. Password ref: \`Jentra/W5/20261009/native-profile/password\`, supplied as private SecureString. OS-account/profile creation and this exact directory/ACL/copy operation are included in the proposed approval. No profile has been created and Windows Sandbox is not enabled/installed.

This document does **not** request approval of unresolved host/receiver bindings. Supply those exact values without secrets; regenerate one final bound manifest and review hash, then request one approval covering the exact 28 files, six Auth labels, 500 synthetic scopes/roles/plans/source caps, bounded operator authority, listed secret references, native OS test profile/package, host deployment, receiver/OpenAI calls and runtime/contention/load execution. Nothing is installed or provisioned until that approval. Any new source, destination, identity, entitlement, secret reference or scope requires a revised review before dependent work.

Installed SQL, candidate rollback, bootstrap mapping, controlled workers, authenticated native, actual delivery/model usage, independent contention, target-scale latency and owner signoff remain separate evidence gates. **Wave 5 remains incomplete.**
`;
await writeFile(path.join(root,base+'runtime-review-20261009.md'),text);
process.stdout.write(JSON.stringify({review:base+'runtime-review-20261009.md',bundleSha256:review.bundleSha256,approvalReady:review.approvalReady,pendingBindings:pending,migrations:migrations.length}));
