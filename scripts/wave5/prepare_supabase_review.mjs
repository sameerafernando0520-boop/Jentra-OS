// Review preparation only. No tool/network calls or provisioning.
import {readFile,readdir,writeFile} from 'node:fs/promises';
import {createHash} from 'node:crypto';
import path from 'node:path';
import {edgeConfiguration as edge} from '../../workers/wave5/edge_configuration.mjs';
import {accounts,assignments,plans,roles,scopes} from './complete_app_runtime_plan.mjs';
const base='docs/verification/wave5/',revision=process.argv[2]??'r5',sha=v=>createHash('sha256').update(v).digest('hex');
if(!/^r\d+$/.test(revision))throw Error('CURRENT_REVIEW_REVISION_REQUIRED');
const json=async p=>JSON.parse(await readFile(p,'utf8'));
const save=async(p,v)=>writeFile(p,JSON.stringify(v,null,2)+'\n');
function rows(raw){const t=raw.content.find(c=>c.type==='text').text,w=JSON.parse(t).result;return JSON.parse(w.slice(w.indexOf('\n[')+1,w.indexOf('\n</untrusted-data-')));}
const earlier=await json(base+'runtime-review-20261009.json'),inventory=await json(base+'complete-app-migration-inventory-20261009.json');
const {bundleSha256:earlierBundleSha256,...earlierBody}=earlier;
const candidate=await json(base+'complete-app-candidate-20261009.hashes.json');
const result=await json(base+'complete-app-candidate-result-20261009.json'),tap=rows(result.result)[0].tap;
if(result.strictAssertions!==105||!result.rolledBack||tap.length!==105||tap.some(s=>!/^ok \d+ -/.test(s)))throw Error('STRICT_CANDIDATE_EVIDENCE_REQUIRED');
const live=rows(await json(base+'complete-app-live-after-final-20261009.json'))[0];
if(live.migrations!==43||live.api_functions!==107||live.role_permissions!==87||live.role_assignments!==1||live.entitlements!==28||live.memberships!==1||live.proposed_accounts!==0||live.proposed_tenants!==0||live.proposed_plans!==0||live.fixture_or_proposed_keys!==0||live.cron_jobs||live.edge_authorities||live.net_queue)throw Error('LIVE_BASELINE_CHANGED');
const bootstrapResult=await json(base+'complete-app-bootstrap-probe-result-20261009.json');
const bootstrapTap=rows(bootstrapResult.result)[0].tap;
if(bootstrapResult.strictAssertions!==25||!bootstrapResult.rolledBack||bootstrapResult.permissionShim!==false||!bootstrapResult.authIdsBoundToReturnedIdParameter||bootstrapTap.length!==25||bootstrapTap.some(s=>!/^ok \d+ -/.test(s)))throw Error('STRICT_AUTH_BOUND_BOOTSTRAP_EVIDENCE_REQUIRED');
const bootstrapManifest=await json(bootstrapResult.sourceManifest);
for(const [p,h] of Object.entries(bootstrapManifest.sources))if(sha(await readFile(p))!==h)throw Error('BOOTSTRAP_PROBE_SOURCE_DRIFT:'+p);
const previewPackage=await json(base+`windows-test-preview-package-20261009-${revision}.json`);
const sourceCount=Object.keys(previewPackage.sourceHashes).length;
const native=await json(base+`windows-test-verification-20261009-${revision}.json`);
if(!native.currentSourceMatch||!native.previewBuilt||!native.connectedBuilt||!native.nativeLaunched||native.revision!==revision||native.sourceFilesPerApp!==sourceCount||sourceCount<1||native.releaseEntriesVerified!==68||native.cashFramesInspected!==8||native.modelFramesInspected!==4)throw Error('CURRENT_NATIVE_PACKAGE_EVIDENCE_REQUIRED');
const authEvidence=revision!=='r5',authGuide=base+'windows-account-google-setup-20261009.md';
const authGatewayTests=native.authGatewayTests??0,authTests=native.authTests??0,authFrames=native.authFrames?.length??0;
const authRenderTests=native.stages?.find(s=>s.stage==='authFrames')?.passedTests??0;
if(authEvidence&&(!Number.isSafeInteger(authGatewayTests)||authGatewayTests<11||!Number.isSafeInteger(authTests)||authTests<1||authRenderTests!==2||authFrames!==2||native.authFramesInspected!==2||!native.newAccountUiImplemented||!native.googleWindowsReturnImplemented||native.realGoogleSignIn!==false||native.emailConfirmationDeliveryVerified!==false))throw Error('CURRENT_AUTH_CANDIDATE_EVIDENCE_REQUIRED');
if(authEvidence){
 for(const [stage,count]of [['authGatewayTests',authGatewayTests],['authTests',authTests]])if(native.stages.find(s=>s.stage===stage)?.passedTests!==count)throw Error('AUTH_STAGE_COUNT_MISMATCH:'+stage);
 for(const frame of native.authFrames)if(!frame.visuallyInspected||sha(await readFile(frame.path))!==frame.sha256)throw Error('AUTH_RENDER_DRIFT:'+frame.path);
}
const deno=await json(base+'supabase-entrypoint-checks-20261009.json');
if(!deno.entrypoints.every(c=>c.exitCode===0))throw Error('ENTRYPOINT_CHECKS_REQUIRED');
const workerTests=await json(base+'complete-app-worker-tests-20261009.json');
if(workerTests.exit_code!==0||!workerTests.output.includes('tests 63')||!workerTests.output.includes('fail 0'))throw Error('CURRENT_WORKER_TESTS_REQUIRED');
const migrations=Object.entries(candidate.sources).filter(([p])=>p.startsWith('supabase/migrations/')).map(([p,h],i)=>({order:i+1,path:p,sha256:h,owner:p.includes('wave4')?'Wave 4':p.includes('wave5')?'Wave 5':'Wave 3',installed:false}));
if(migrations.length!==71)throw Error('EXACT_MIGRATION_CLOSURE_REQUIRED');
for(const m of migrations){if(sha(await readFile(m.path))!==m.sha256)throw Error('SOURCE_DRIFT:'+m.path);const older=inventory.pending.find(p=>p.path===m.path);if(older&&older.sha256!==m.sha256)throw Error('OWNED_SOURCE_DRIFT:'+m.path);}
for(const mode of ['preview','connected']){
 const b=await json(base+`windows-test-${mode}-package-20261009-${revision}.json`);
 if(!b.current_source_match||!b.base_source_match||b.entrypoint!=='lib/main.dart'||b.controlledEvidence||Object.keys(b.sourceHashes).length!==sourceCount)throw Error('ORDINARY_SOURCE_MATCHED_BUILD_REQUIRED');
 for(const [p,h]of Object.entries(b.sourceHashes))if(sha(await readFile(p))!==h)throw Error('DESKTOP_SOURCE_DRIFT:'+p);
 for(const f of b.releaseFiles)if(sha(await readFile(path.join(b.packageDirectory,f.path)))!==f.sha256)throw Error('RELEASE_DRIFT:'+f.path);
}
const deployment=[];
for(const name of ['wave5-runtime','wave5-receiver']){
 const entry=`supabase/functions/${name}/index.ts`,config=`supabase/functions/${name}/deno.json`,closure=new Map();
 async function visit(p){if(closure.has(p))return;const content=await readFile(p,'utf8');closure.set(p,content);
  for(const match of content.matchAll(/(?:from\s*|import\s*\(\s*)['"](\.[^'"]+)['"]/g)){const next=path.posix.normalize(path.posix.join(path.posix.dirname(p),match[1]));if(!/^(supabase\/functions|workers\/wave5)\//.test(next))throw Error('DEPLOYMENT_PATH_ESCAPE');await visit(next);}}
 await visit(entry);await visit(config);
 const files=[...closure].map(([name,content])=>({name,content})).sort((a,b)=>a.name.localeCompare(b.name));
 const payload={link_id:'link_6aa8c9ca60408191b9e7e8344c5a6693',project_id:edge.projectId,name,entrypoint_path:entry,verify_jwt:false,files};
 const payloadPath=base+`supabase-deploy-${name}-20261009.json`;await save(payloadPath,payload);
 deployment.push({name,payloadPath,entrypoint:entry,verifyJwt:false,customAuthentication:name==='wave5-runtime'?'Private schedule key hashed against a live scoped database authority; external credentials; authenticated forecast reader with caller JWT':'HMAC v1/v2 over exact bytes, signed timestamp and event ID; committed outbox, scope, subscription, lease/attempt and revocation rechecks',files:files.map(f=>({path:f.name,sha256:sha(f.content)}))});
}
const configuration={...structuredClone(earlier.workerConfiguration),
 hostBinding:{kind:'supabase-edge',status:'owner-selected existing project; prepared, not deployed',publicBaseUrl:edge.workerUrl},
 receiver:{status:'exact same-project receiver prepared, not deployed',url:edge.receiverUrl,allowedHosts:[new URL(edge.receiverUrl).hostname],durableIdempotencyRequired:true,subscriptions:edge.receiverSubscriptions,
  paths:Object.fromEntries(['accept','redirect','timeout','reject'].map(m=>[m,edge.receiverUrl.replace(/accept$/,m)]))},
 schedulers:{deliveryIntervalMs:60000,deliveryBatchLimit:3,subscriptionIntervalMs:60000,subscriptionBatchLimit:50,healthIntervalMs:60000,
  exactJobNames:['jentra-w5-20261009-delivery','jentra-w5-20261009-subscription','jentra-w5-20261009-health'],maximumScheduledRequests24Hours:4320,
  requestBudgetMs:65000,deliveryBudgetMs:55000,tickLeaseMs:90000},
 http:{maxRequestBytes:65536,maxConcurrentRequestsPerIsolate:8,paths:['/schedule','/external/forecast','/model/suggestion']},
 model:{...structuredClone(earlier.workerConfiguration.model),approved:false,configurationApprovalRequired:true},
 secrets:{platformInjected:['SUPABASE_URL','SUPABASE_SERVICE_ROLE_KEY','SUPABASE_ANON_KEY'],modelKey:'W5_OPENAI_API_KEY',
  newVaultNames:['jentra-w5-runtime-20261009-schedule','jentra-w5-runtime-20261009-delivery-v1','jentra-w5-runtime-20261009-delivery-v2'],
  deliveryKeys:edge.receiverSubscriptions?{'w5/runtime/20261008/delivery/v1':'jentra-w5-runtime-20261009-delivery-v1','w5/runtime/20261008/delivery/v2':'jentra-w5-runtime-20261009-delivery-v2'}:{},
  valuesReturnedInReview:false,existingProjectSecretsRead:false,accountPasswords:earlier.workerConfiguration.secrets.accountPasswords,
  externalCredential:'New random 32-byte credential in private OS store; only SHA-256 registered through real MFA; 24-hour expiry'}
};
const workerFiles=(await readdir('workers/wave5')).filter(f=>f.endsWith('.mjs')).map(f=>'workers/wave5/'+f);
const goldenDiagnostic=native.sharedGoldensRerun?base+`full-desktop-golden-investigation-20261009-${revision}.md`:null;
const broaderSummary=(native.broaderSuites??[]).map(s=>`${s.stage}: ${s.passedTests} passed / ${s.failedTests} failed (exit ${s.exitCode})`).join('; ');
const artifactPaths=[...workerFiles,...deployment.flatMap(d=>d.files.map(f=>f.path)),...deployment.map(d=>d.payloadPath),
 'scripts/wave5/runtime_plan.mjs','scripts/wave5/complete_app_runtime_plan.mjs','scripts/wave5/prepare_runtime_bootstrap.mjs','scripts/wave5/prepare_complete_app_bootstrap_probe.mjs',
 'scripts/wave5/prepare_supabase_setup.mjs','scripts/wave5/prepare_supabase_setup_probe.mjs','scripts/wave5/prepare_supabase_review.mjs',
 'scripts/wave5/prepare_complete_app_candidate.mjs','scripts/wave5/prepare_native_runtime_profile.ps1',
 base+'runtime-bootstrap-complete-app-20261009.sql',base+'runtime-operator-authority-complete-app-20261009.sql',base+'complete-app-bootstrap-probe-result-20261009.json',
 base+'complete-app-bootstrap-probe-20261009.sql',base+'complete-app-bootstrap-probe-20261009.hashes.json',
 base+'supabase-runtime-setup-20261009.sql',base+'supabase-runtime-stop-20261009.sql',base+'complete-app-candidate-result-20261009.json',
 base+'complete-app-candidate-20261009.sql',base+'complete-app-candidate-20261009.hashes.json',base+'complete-app-migration-inventory-20261009.json',
 base+'complete-app-live-after-final-20261009.json',base+'complete-app-worker-tests-20261009.json',
 base+'supabase-entrypoint-checks-20261009.json',base+`windows-test-verification-20261009-${revision}.json`,base+`windows-test-delivery-20261009-${revision}.json`,
 ...(authEvidence?[authGuide,base+'public-auth-settings-20261009.json']:[]),
 ...(native.broaderSuites??[]).flatMap(s=>[s.record,s.log]),
 ...(goldenDiagnostic?[goldenDiagnostic,goldenDiagnostic.replace(/\.md$/,'.json')]:[]),
 ...(native.pkceDeadlineRegression?[native.pkceDeadlineRegression.record,native.pkceDeadlineRegression.log]:[]),
 'docs/blueprint/wave5/W5_REVIEWED_MODEL_NATIVE_CONTRACT.md','scripts/wave5/run_windows_test_build.ps1','scripts/wave5/launch_windows_test.ps1',
 'scripts/wave5/package_windows_test_build.mjs','scripts/wave5/finalize_windows_test_package.ps1','scripts/wave5/prepare_final_windows_evidence.mjs',
 'supabase/tests/wave5_supabase_runtime_test.sql','supabase/tests/wave5_supabase_setup_test.sql',
 ...['preview','connected'].flatMap(m=>[base+`windows-test-${m}-source-20261009-${revision}.json`,base+`windows-test-${m}-package-20261009-${revision}.json`])];
const artifacts=await Promise.all([...new Set(artifactPaths)].sort().map(async p=>({path:p,sha256:sha(await readFile(p))})));
const body={...earlierBody,reviewId:'jentra-complete-app-supabase-runtime-20261009',preparedAt:new Date().toISOString(),
 supersedes:{reviewId:earlier.reviewId,bundleSha256:earlierBundleSha256,reason:'Owner selected existing Supabase hosting; full app request exposed 41 additional W3/W4 dependencies plus two hosted-runtime contracts'},
 approvalReady:true,ownerApproved:false,pendingBindings:[],accountLabelsOwnerConfirmed:true,hostingChoiceOwnerConfirmed:true,
 privateProvisioning:{authAdminContextAvailable:false,modelSecretConfigured:false,googlePrivateConfigurationPending:true,connectedToolsProvideAuthAdminOrSecrets:false,
  requiresOwnerAuthorizedPrivateContext:true,secretValuesMayBeSentInChat:false,directAuthUserSqlForbidden:true},
 liveBaseline:{...earlier.liveBaseline,observedAt:live.observed_at,postRollbackObservedAt:live.observed_at,expectedLedgerAfterOnlyThisInstall:114,
  migrations:43,apiFunctions:107,rolePermissions:live.role_permissions,roleAssignments:live.role_assignments,entitlements:live.entitlements,memberships:live.memberships,
  postRollbackCountsUnchanged:true,proposedAccountsTenantsPlansAbsent:true,installedSixNeverReplayed:true},
 accounts:earlier.accounts,roles,assignments,syntheticPlans:plans,syntheticScopes:scopes,
 bootstrap:{...earlier.bootstrap,authIdsBindingParameter:'jentra.w5.created_auth_ids',authIdsMustMatchExactReturnedAdminCreateIds:true,bootstrapSql:base+'runtime-bootstrap-complete-app-20261009.sql',operatorAuthoritySql:base+'runtime-operator-authority-complete-app-20261009.sql'},workerConfiguration:configuration,deployments:deployment,migrations,artifacts,
 evidence:{candidateStrictAssertions:105,candidateRolledBack:true,bootstrapMappingStrictAssertions:25,bootstrapMappingRolledBack:true,bootstrapPermissionShim:false,controlledWorkerTests:63,
  entrypointsDenoChecked:true,installedNewMigrations:false,realMfa:false,authenticatedNative:false,actualWorkerDelivery:false,actualModelUsage:false,
  independentContention:false,targetScaleLoad:false,ownerSignoff:false,previousSixInstalledAssertions:126,
  desktopAnalysisClean:true,focusedDesktopTests:96,modelGatewayTests:15,modelNativeTests:20,keyboardWidgetTests:6,cashRenderTests:12,freshCashFrames:60,modelRenderTests:12,freshModelFrames:24,inspectedCashFrames:8,inspectedModelFrames:4,startupTests:2,
  windowsPreviewBuilt:true,windowsConnectedBuilt:true,ordinaryEntrypoint:'lib/main.dart',sourceFiles:sourceCount,releaseFilesPerApp:34,packageRevision:revision,
  newAccountUiImplemented:authEvidence,googleWindowsReturnImplemented:authEvidence,authGatewayTests,authUiAndCapabilityTests:authTests,authRenderTests,freshAuthFrames:authFrames,inspectedAuthFrames:native.authFramesInspected??0,realGoogleSignIn:false,emailConfirmationDeliveryVerified:false,googlePrivateConfigurationPending:true,
  nativeKeyboard:{verified:native.nativeKeyboardVerified,reason:native.nativeKeyboardReason},sharedGoldenFailures:13,sharedGoldensRerun:native.sharedGoldensRerun,broaderSuites:native.broaderSuites??[],goldenDiagnostic,pkceDeadlineRegression:native.pkceDeadlineRegression},
 remainingDevelopment:['Thirteen shared dashboard/setup golden failures remain unresolved; native keyboard/restart/revocation and owner visual review remain unverified',
  'Wave 3/4 generic provider and acceptance items remain subject to their separately owned contracts; installing the closure does not prove every module workflow'],
 execution:{...earlier.execution,stages:[
  'Obtain explicit approval for this exact bundle SHA; re-read live ledger/collisions and all source/release hashes. Stop on drift.',
  'Install the 71 listed missing migrations once, in listed order. Record connector-assigned versions; do not replay the installed six.',
  'Run strict installed-schema checks with fixture rollback; re-read grants/RLS/providers and preservation evidence.',
  'Create only the six new confirmed password-login users through Auth Admin, email_confirm=true and no email delivery; store new credentials privately. Abort collisions.',
  'Bind all six actual returned Auth IDs through jentra.w5.created_auth_ids on every SQL connection; execute exact scoped bootstrap and operator authority: 500 synthetic tenants, four new plans and reviewed memberships/roles. Create bounded source fixtures only within listed caps.',
  'Enroll/challenge/verify genuine TOTP and independent sessions. Record only returned IDs and AAL results, never passwords, seeds, JWTs or refresh tokens.',
  'Deploy the two exact Edge payloads, privately configure W5_OPENAI_API_KEY, run exact Vault/cron setup, and verify deployed source/JWT/custom-auth settings.',
  'Use real MFA registration for the four exact same-project receiver subscriptions and external credential; test signatures, rotation, revocation, redirects, timeout, dead letters and reviewed replay.',
  'Exercise nonempty source dates/statements/scenarios and native export create/download/reopen, real model usage and proposal review/approval/execution; preserve distinct evidence gates.',
  'Create the reviewed standard native profile/package and collect authenticated keyboard/restart/revocation and visual evidence; current preview/sign-in screens are not that gate.',
  'Run overlapping independent-session duplicate/quota/seat/activation/lease races and bounded 500-tenant/2000-session load; report unmet host/Auth limits as failures.',
  'Disable only this worker authority and its three recorded jobs after the run or on expiry. Present every requirement to owner for acceptance; never self-sign.'
 ]}};
const review={...body,bundleSha256:sha(JSON.stringify(body))};await save(base+'complete-app-runtime-review-20261009.json',review);
const roleText=Object.entries(roles).map(([k,r])=>`- **${k}**: ${r.scope}; MFA=${r.requiresMfa}; ${r.permissions.map(p=>'`'+p+'`').join(', ')}.`).join('\n');
const text=`# Jentra OS — full backend and Supabase runtime review, October 9

Prepared for one owner decision. **Nothing new is installed, provisioned, activated or deployed.** The owner selected the existing Supabase project and confirmed the six account labels. Those selections do not approve the operations below. This concrete package supersedes the older unbound 28-file Node review.

Bundle SHA-256: **\`${review.bundleSha256}\`**. [Machine manifest](complete-app-runtime-review-20261009.json) contains all 500 scope UUIDs, permissions, plans, exact source hashes, deployment files and operation bounds. Any source, ledger, identity, URL or scope drift requires a refreshed review before the dependent operation.

## Decision requested

Approve the **71 exact missing migrations**, the six new Auth accounts, scoped 500-tenant synthetic bootstrap/source caps, four new synthetic plans, one bounded operator authority/grant, one standard Windows test profile/package, three new Vault secrets, one privately supplied model secret, two new Edge functions, three expiring scheduled jobs, the four same-project receiver paths and the bounded real MFA/delivery/export/contention/load run described here. Production, real billing, other destinations, existing acceptance stores/accounts and Git publication remain excluded. Runtime approval is separate from owner acceptance of the app.

## Verified baseline and effect

[Fresh post-rollback read](complete-app-live-after-final-20261009.json), ${live.observed_at}: **43 migrations / 107 API functions**, 87 role-permission rows, one assignment, 28 plan entitlements and one membership. No proposed account, tenant, Vault key, Edge authority, cron/net table or candidate fixture remains. The [six installed migrations](installation-result-20261008.md) are excluded; their connector-assigned versions are not their original source timestamps.

The full app request uncovered **69 uninstalled repository dependencies**: 48 Wave 3, 13 Wave 4 and eight Wave 5. Two new hosted-runtime migrations bring this review to **71**. Expected ledger after only this installation: **114**. Installation changes shared database schemas/APIs/default registrations across waves. W3/W4 source bytes are preserved; their broader native/provider acceptance is not inherited from this review.

The full composition and exact setup/stop bodies pass **105 strict rollback assertions**. A separate **25-assertion full-schema bootstrap probe** verifies all 500 scopes, exact role mappings, payroll/correction/reimbursement date permissions, role isolation, AAL1 denial and the returned Auth-ID binding. It adds no permission-registration shim. Both probes use test-only Auth/policy shapes, end in rollback and make no HTTP call. **63 controlled worker tests** pass and both Edge entrypoints pass Deno checking; their imported JavaScript modules are exercised by the controlled tests, not TypeScript-checked. These gates are separate from installed SQL, real Auth and actual hosted delivery.

## Exact installation order

| Order | Filename | Owner | SHA-256 |
|---|---|---|---|
${migrations.map(m=>`| ${m.order} | ${path.basename(m.path)} | ${m.owner} | \`${m.sha256}\` |`).join('\n')}

## Six confirmed accounts and access

| New label only | Roles | Purpose |
|---|---|---|
${earlier.accounts.map(a=>`| ${a.email} | ${assignments[a.label].join(', ')||'No tenant membership or role'} | ${a.label} |`).join('\n')}

Auth Admin must create each account with a new random private password, email confirmation and **no email send**. The non-secret \`jentra.w5.created_auth_ids\` parameter must bind exactly the six labels to their actual returned Auth Admin IDs on each SQL connection; bootstrap/operator SQL refuses an absent, mismatched or reused identity. No fake Auth ID or JWT claim may serve as runtime evidence. Genuine TOTP enroll/challenge/verify and independent server session IDs are required. Password/TOTP refs stay \`Jentra/W5/20261008/<label>/password\` and \`.../totp\` in the isolated private credential store. Existing \`test@test.com\`, Jentra Acceptance Lab and other chats' credentials are untouched. A collision aborts; no existing label is adopted.

${roleText}

Runtime: tenant \`${scopes[0].tenantId}\`, entity \`${scopes[0].entityId}\`, branch RT1 \`${scopes[0].branchId}\`. RT2 \`${scopes[0].secondBranchId}\` is a denial target. Foreign member belongs only to \`${scopes[1].tenantId}\`. All 498 load tenants and their read/billing mappings are enumerated in the manifest. Scheduled worker authority covers **RT1 only for 24 hours**. No owner/all-permissions role is assigned. Explicit RPC MFA checks remain in force; the existing worker subscription delegation uses AAL1 and is not human MFA evidence.

## Scoped synthetic setup

[Bootstrap SQL](runtime-bootstrap-complete-app-20261009.sql) creates 500 tenants, 500 entities, 501 branches, 1997 memberships, 1003 roles and 2003 assignments. Its separate 25-check probe applies the full candidate schema, adds no permission shim and uses test-only Auth shapes. The runtime plan includes People plus the source-specific payroll/reimbursement settlement and independent approval permissions required by the cash-date contract; existing Wave 4 stores and RPC MFA checks are preserved. Synthetic activation allowlist is runtime and load-001 only; the scheduled worker applies runtime only. Trial windows last seven days from authoritative setup time.

| New plan | Seats | Enabled entitlements and limits |
|---|---|---|
${plans.map(p=>`| ${p.code} | ${p.seats} | ${Object.entries(p.entitlements).map(([k,v])=>k+'='+v).join('; ')} |`).join('\n')}

Per-tenant source maxima: 200 opportunities, 800 process events, 100 posted journals, 200 journal lines and 120 open items. Runtime-only maxima: 10 payroll obligations, four corrections, 10 reimbursements, three financial publications, one classification review, four cash scenarios and eight governed exports. Only new synthetic scopes receive business fixtures; caps do not themselves establish valid posted sources. No source body or private HR/receipt evidence enters generic analytics/command receipts. Invitation/seat races reuse the reviewed approver/executor labels in load-001 without email.

## Exact hosted worker, receiver and secrets

Worker: \`${edge.workerUrl}\`. Receiver: \`${edge.receiverUrl}\`. Hosting is the owner-selected existing project, using [Supabase Cron, pg_net and Vault](https://supabase.com/docs/guides/functions/schedule-functions). No additional host or reverse proxy is required.

| Receiver mode | Exact subscription ID | URL ending | Behavior |
|---|---|---|---|
${Object.entries(edge.receiverSubscriptions).map(([m,id])=>`| ${m} | ${id} | /wave5-receiver/${m} | ${m==='accept'?'Save immutable exact-byte receipt before ACK':m==='timeout'?'Save receipt, then delay 12s; unknown worker outcome requires review':m==='redirect'?'Authenticate committed source, return 307 without ACK':'Authenticate committed source, return 503 without ACK'} |`).join('\n')}

The two exact [runtime](supabase-deploy-wave5-runtime-20261009.json) and [receiver](supabase-deploy-wave5-receiver-20261009.json) upload payloads include entrypoints, Deno configuration and every relative dependency. Both set \`verify_jwt=false\` because their bodies implement the listed schedule/credential/caller-JWT or HMAC authentication. This is explicitly reviewed custom authentication; an anonymous request cannot issue a tick, command or receipt.

[Prepared setup](supabase-runtime-setup-20261009.sql) generates only three fresh 32-byte Vault values: \`jentra-w5-runtime-20261009-schedule\`, \`...-delivery-v1\`, \`...-delivery-v2\`. Existing secret values are never queried. HMAC refs are \`w5/runtime/20261008/delivery/v1\` and \`.../v2\`; rotation occurs through the real MFA API. The exact public build key is checked by SHA, not privately provisioned. Platform-injected service/anon variables remain on the Edge server. \`W5_OPENAI_API_KEY\` must be supplied privately to this project after approval; no secret value belongs in a chat, artifact, desktop binary or log. Auth Admin/private runtime execution likewise needs an owner-authorized private context; connected SQL alone does not create real Auth users.

The three jobs \`jentra-w5-20261009-delivery\`, \`...-subscription\`, \`...-health\` run once per minute, at most 4320 scheduled requests over 24 hours. Delivery batch <=3, subscription page <=50; Edge request budget 65s and tick lease 90s. Database leases prevent overlapping jobs of the same kind across isolates. HTTP concurrency <=8 is per isolate; global quota/lease checks are persistent. Source authority is rechecked before sending and receiving. Quota is 100 delivery units with bounded attempts; this is not a claim of only 100 network attempts. No redirect is followed and uncertain sends cannot auto-retry. [Stop SQL](supabase-runtime-stop-20261009.sql) disables only this authority/scope and unschedules its three recorded IDs; unrelated jobs survive. Expiry performs the same scoped shutdown.

External credential: new private random value; only its SHA is registered through real MFA for \`analytics.freeze_pipeline.v1\`, exact RT1 and 24-hour expiry. Atomic throttle is 60/minute with 200-command quota. It has no generic dispatch or foreign/sibling authority.

Model: \`openai.responses.v1\`, \`gpt-4.1-mini-2025-04-14\`, policy revision 1, <=4 distinct persistent invocations, <=2000 reserved tokens each and 8000-token plan ceiling. Only the numeric \`pipeline.current_weighted.v1\` projection goes to the two named OpenAI Responses/token-count endpoints. No names/free text/receipt/HR bodies, tools, storage or background responses are enabled. Unknown outputs retain reservations. Actual provider token counts settle trusted usage. Native Control now implements the [reviewed request/recovery contract](../../blueprint/wave5/W5_REVIEWED_MODEL_NATIVE_CONTRACT.md): actor/scope-bound encrypted original invocation/usage IDs, exact parameter recovery, current source/access checks and explicit selection into the human proposal form. Selecting a suggestion issues no command; proposal, distinct MFA approval and executor remain separate. Fifteen gateway/control tests and 20 native model tests pass; authenticated provider usage remains unproved.

## Operator, native target and acceptance run

The separate operator has zero tenant membership. [Authority SQL](runtime-operator-authority-complete-app-20261009.sql) binds its returned Auth ID and limits it to the exact runtime tenant/reason for 45 minutes; a genuine MFA call issues a <=30-minute grant within that deadline. Foreign tenant, changed reason, longer deadline, different recipient and AAL1 are denied. No grant is inserted as a substitute for authenticated issuance.

The owner delegated native-target selection. The reviewed new standard Windows profile is \`jentra-w5-runtime\`, package path \`C:\\Users\\Public\\Documents\\JentraWave5Runtime\\20261009\`, password ref \`Jentra/W5/20261009/native-profile/password\`. [Preparation script](../../../scripts/wave5/prepare_native_runtime_profile.ps1) requires exact review approval and verifies all source/release hashes before creating that one OS account and copying the ordinary release with private ACLs. Existing account/package collisions abort. The fresh [portable ${revision} preview/connected apps](windows-test-verification-20261009-${revision}.md) use separate runner identities and are available now. Both releases match ${sourceCount} selected desktop dependency inputs and 34 release files per app. Scoped analysis, 96 workspace/cash tests, six keyboard tests and two startup tests pass. Twelve cash and twelve model render variants at 200% text produce 60 and 24 images; eight cash and four model images plus the two native startup windows were inspected. Controlled images/dashboard/sign-in are separate from authenticated acceptance. Native keyboard focus was not acquired in the earlier own-window probe; no keys were sent and that gate remains open.

${authEvidence?`The Connected app implements **Create account** and the Windows Google PKCE browser return. Fresh evidence records **${authGatewayTests} gateway/settings/loopback tests**, **${authTests} authentication UI/capability tests** and **${authRenderTests} auth render tests**, with both auth images inspected. The [account/Google setup guide](windows-account-google-setup-20261009.md) records the current disabled Google provider and exact private provider/redirect configuration. Real Google sign-in and email confirmation delivery remain unverified. Google configuration is a separate prepared owner decision; this runtime bundle does not enable that project-wide provider, provision its client secret or change global Auth URLs.`:''}

After approval: install and validate SQL; create/bind six real Auth accounts; provision only reviewed synthetic data/entitlements; obtain real independent MFA sessions; deploy exact Edge payloads and private configuration; register through MFA; run native dates/statements/scenarios/export download/reopen/revocation/restart; test actual model/delivery/rotation/replay; issue scoped operator grant; run concurrent races and bounded load. Do not change global Auth settings to make the harness pass.

Contention: two or more independently authenticated/trusted connections, barrier and actual overlap; 100 duplicate requests, quota-10 competing reservations, lease races, seat/activation races, exact original identities and committed before/after counts. Load: 500 tenants, 2000 distinct real sessions, 60s warmup +300s measurement, <=900s total and <=100000 timed requests; p95 reads <500ms, commands <1500ms, analytics <3000ms. Record actual tier/hardware/populations/errors; unsupported Auth/connection limits remain an unmet gate. Model/webhook calls are excluded from load. The operator is excluded from load sessions. Owner signoff is required for each of 109 Wave 5 IDs; the agent cannot sign for the owner.

## Remaining app work and decision boundary

The [remaining-work record](complete-app-remaining-work-20261009.md) distinguishes provider installation, private Auth/provider setup, authenticated native/export/worker behavior, independent contention/load, the 13 shared golden failures, broader W3/W4 provider acceptance and final owner release approval. Native model request/recovery is implemented as a tested candidate; its real provider path is not yet verified. The current Windows package is a test build. **Jentra OS and Wave 5 remain incomplete.**

${broaderSummary?`The fresh full-suite results are **${broaderSummary}**. The [golden investigation](${path.basename(goldenDiagnostic)}) records every current failure, exact render hashes and any established earlier SDK/fixture evidence. Additional preserved golden failures remain open; approval of runtime operations does not accept or replace these images.`:''}

The prior approval covers only the six already installed migrations. This new 71-file installation plus bootstrap/activation/secrets/OS profile/deployment/delivery/load requires one explicit approval of the bundle SHA above. No production rollout, real billing, unrelated data cleanup, blanket role grant, golden replacement, staging, commit or push is included.
`;
await writeFile(base+'complete-app-runtime-review-20261009.md',text);
console.log(JSON.stringify({approvalReady:true,ownerApproved:false,migrations:migrations.length,artifacts:artifacts.length,deployments:deployment.map(d=>({name:d.name,files:d.files.length})),bundleSha256:review.bundleSha256}));
