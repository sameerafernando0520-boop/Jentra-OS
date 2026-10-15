// Additive export-only successor. Imports perform no private or network I/O.
import fs from 'node:fs/promises';
import path from 'node:path';
import {fileURLToPath} from 'node:url';
import {PROJECT,BUNDLE,ORGANIZATION,createManagementTransport} from './approved_management_installer.mjs';
import {hashBytes,hashJson,isUuid,immutableJson} from './runtime_contract.mjs';
import {runtimeSealKey,appendRuntimeSecret} from './private_runtime_seal.mjs';
import {createPrivateKeyReader,selectExistingLegacyKeys} from './private_runtime_http.mjs';
import {existingActorSession} from './private_existing_actor_session_20261013_r5.mjs';
import {bindUuidSessionQuery} from './enroll_mfa_management_20261013_r5.mjs';
import {FINANCE_SCOPE,FINANCE_ACTOR,FINANCE_JOURNALS,FINANCE_CALENDAR} from './finance_cash_fixture_20261013_r5.mjs';
import {financeWorkflowId as id,FINANCE_SCOPED_BODY,FINANCE_FACTS_SQL,receiptResolutionSql,sameFinanceJson} from './finance_cash_workflows_20261013_r5.mjs';
import {encodeFinanceCsv,createFinanceHttpsTransport} from './finance_https_transport_20261013_r5_a2.mjs';
import {EXECUTION_ROOT,PUBLIC_EVIDENCE_ROOT,ORIGINAL_SOURCE_HASH,CURRENT_WHOLE_SOURCE_HASH,STALE_COMMAND,
 EXPECTED_PROCESS_APPENDS,REMAINING_BASELINE_SQL,REMAINING_PRIOR_COMPLETE_SQL,REMAINING_ACTIVITY_SQL,REMAINING_FUNCTIONS_SQL,
 validateRemainingQuiescence,validateRemainingFunctions,validateRemainingCommand,createRemainingCommandWriter,
 persistRemainingPreflightResponse,readExactRemainingFile,verifyRemainingPreparation} from './finance_remaining_20261014_r5_a3.mjs';

const root=fileURLToPath(new URL('../../',import.meta.url)),base='docs/verification/wave5/';
const must=(ok,code)=>{if(!ok){const error=Error(code);error.publicCode=code;throw error;}};
const digest=value=>typeof value==='string'&&/^[a-f0-9]{64}$/.test(value);
const exactKeys=(value,keys)=>value&&typeof value==='object'&&!Array.isArray(value)&&sameFinanceJson(Object.keys(value).sort(),keys.slice().sort());
export const EXPORTS_SOURCE_PATHS=Object.freeze(['tools/wave5/finance_exports_20261014_r5_a6.mjs','tools/wave5/prepare_finance_exports_20261014_r5_a6.mjs',
 base+'task3-export-renewal-20261014/finance_exports_20261014_r5_a6.test.mjs']);
export const EXPORTS_PLAN=base+'finance-exports-preparation-20261014-r5-a6.json';
export const EXPORTS_ONCE=base+'finance-exports-once-20261014-r5-a6.json';
// These are FUTURE public integration records. Source preparation creates none.
export const EXPORTS_PROFILE=base+'task3-export-renewal-20261014/execution-profile-a1.json';
export const EXPORTS_FINAL_REVIEW=base+'task3-export-renewal-20261014/final-operation-review-a1.json';
export const EXPORTS_PROFILE_PATHS=Object.freeze({
 sourcePolicy:base+'task3-export-renewal-20261014/source-policy-a1.json',
 independentReview:base+'task3-export-renewal-20261014/independent-policy-review-a1.json',
 ownerDecision:base+'runtime-renewal-export-owner-decision-20261014-r5-a1.json',
 renewalReadback:base+'runtime-renewal-two-row-readback-20261014-r5-a1.json',
 metadata:base+'private-owner-input-ready-20261014-r5-a10.json',
 refresh:base+'private-owner-scope-refresh-20261014-r5-a10.json',
 accounting:base+'finance-cumulative-read-accounting-20261014-r5-a7.json',
 dependency:base+'runtime-expiry-dependency-readonly-20261014-r5-a1.json'
});
export const EXPORTS_DEPENDENCY=Object.freeze({path:EXPORTS_PROFILE_PATHS.dependency,
 sha256:'0dc87893b6635d3ef4fb64c724e6aab2a42dd89d9d07ffc42251105f7c3141dc'});
export const EXPORTS_A5_SOURCE_BINDINGS=immutableJson([
 {path:'tools/wave5/finance_exports_20261014_r5_a5.mjs',sha256:'ab9ec8c1a97a0a009081e5aba58db1359fd6d5df3a3d0ce2680bf4c43f50a544'},
 {path:'tools/wave5/prepare_finance_exports_20261014_r5_a5.mjs',sha256:'030c44b84a8c5073c6c2157352fd70783c232ee256befda6ec28e9b6a723cd32'},
 {path:base+'task3-export-continuation-20261014/finance_exports_20261014_r5_a5.test.mjs',sha256:'fedd5d9c86d767508bc9e214225316f457ac3b24dce1e1359a581448c998a351'}
]);
export const EXPORTS_RUNTIME_ID='778237e3-3d4e-4871-8cc9-e08b07b989c7';
export const EXPORTS_ORIGINAL_WINDOW=immutableJson({
 scopeIssuedAt:'2026-10-13T08:13:04.144135+00:00',scopeExpiresAt:'2026-10-14T08:13:04.144135+00:00',
 scopeNonWindowHash:'3119068e9ab1628e43855122d6e1ad8c2f89811561c15f2ec22d27336db2a387',
 edgeIssuedAt:'2026-10-13T09:57:07.481942+00:00',edgeExpiresAt:'2026-10-14T09:57:07.481942+00:00',
 edgeNonWindowHash:'77cac80be8b4bccfad6c4a56fe14c52b03171e5524a46fe7a55ee4c958d90139'
});
export const EXPORTS_OWNER_REPLY='Approve the exact two-row runtime renewal and export a6 continuation';
export const EXPORTS_MAX_WINDOW_MS=7200000;
export const EXPORTS_REVIEWED_BUDGET=immutableJson({recordedPrior:134,ownerRefreshCalls:1,renewalControlCalls:3,prior:138,ordinary:24,ordinaryLimit:162,resolution:1,total:163});
const a3=base+'genuine-finance-remaining-20261014-r5-a3-1791928284337/';
export const EXPORTS_PRESERVED_BINDINGS=immutableJson({
 a3Plan:{path:base+'finance-remaining-preparation-20261014-r5-a3.json',sha256:'6c39a389ebaec0315774500af2af1e71874486173d85a3e352ef5782153e1198'},
 a3Stop:{path:a3+'99-stop.json',sha256:'e3ebc060f6bfce7e70ed3a09c719cdddc648713d0597771490af706c4887c1fa'},
 a3Once:{path:base+'finance-remaining-once-20261014-r5-a3.json',sha256:'8a1851c6e5ab4d05a453093ccb6d5ed9d059c903c0dc370524e4a2acc9e8e766'},
 a2Once:{path:base+'finance-remaining-once-20261013-r5.json',sha256:'ec27f49a0cd76e792b70a256e79edad5f858373c7d4c71cd9ec027c5a5ef8919'},
 payroll:{path:a3+'date-payroll_correction.json',sha256:'abe1b70ea3ceeeb162a08eb814ac0beef8fc257f26e33925db61301bdf73bc8a'},
 reimbursement:{path:a3+'date-project_reimbursement.json',sha256:'8d6425887b4a6dbea3c4b0d36b30612d6aa6e532030c47d31fef558f8320384e'},
 statement:{path:base+'genuine-finance-finance-20261013-r5-1791894738890/statement-profit_loss.json',sha256:'288af4da9c6d99b04dd9bbb32012dd2523e68e19d72fa19fde7d5ca64fa1f62d'}
});
export const EXPORTS_PRIOR=138;
export const EXPORTS_LIMIT=163;
export const EXPORTS_PIPELINE='e8e582b2-6ce0-4b2d-beca-8ad3203abbfc';
export const EXPORTS_PIPELINE_BASIS='5d5ac676da84df7d7e780f6cadb38464bfc8d671d9a3f88924e5a4563cf94301';
export const EXPORTS_FACTOR='692d8964-27f9-4fd1-9a2b-8e7aefc52ed8';
export const EXPORTS_ROWS=immutableJson([{currency:'LKR',population:1,amount:'2000.125000',weightedAmount:'1000.062500'},
 {currency:'USD',population:1,amount:'1000.000001',weightedAmount:'333.300000'}]);
export const EXPORTS_COMMANDS=EXPECTED_PROCESS_APPENDS.slice(3);
const inner=sql=>sql.trim().replace(/;\s*$/,'');
const exportIds=EXPORTS_COMMANDS.map(row=>`'${row.documentId}'::uuid`).join(',');
const commandIds=EXPORTS_COMMANDS.map(row=>`'${row.commandId}'::uuid`).join(',');
const scope=FINANCE_SCOPE,statementId=id('statement.profit_loss');
export const EXPORTS_FACTS_SQL=`SELECT jsonb_build_object(
 'observedAt',statement_timestamp()::text,
 'installedMigrationCount',(SELECT count(*) FROM supabase_migrations.schema_migrations),
 'installedApiFunctionCount',(SELECT count(*) FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='api'),
 'originalBaseline',(SELECT facts FROM (${inner(REMAINING_BASELINE_SQL)}) original_baseline),
 'wholeSource',(SELECT facts FROM (${inner(FINANCE_FACTS_SQL)}) whole_source),
 'sourceExcludingOnlyApprovedExportEvents',(SELECT facts FROM (${inner(REMAINING_PRIOR_COMPLETE_SQL)}) prior_complete),
 'observation',(SELECT observation FROM (${inner(REMAINING_ACTIVITY_SQL)}) original_activity),
 'functions',coalesce((SELECT jsonb_agg(to_jsonb(f) ORDER BY f.proname) FROM (${inner(REMAINING_FUNCTIONS_SQL)}) f),'[]'::jsonb),
 'pipeline',(SELECT jsonb_build_object('id',f.id,'sourceCount',f.evidence->'sourceCount','currencies',f.evidence->'currencies','sourceHash',f.source_hash,
  'recordSha256',encode(extensions.digest(to_jsonb(f)::text,'sha256'),'hex')) FROM analytics.pipeline_forecasts f WHERE f.tenant_id='${scope.tenantId}' AND f.legal_entity_id='${scope.entityId}' AND f.branch_id='${scope.branchId}' AND f.id='${EXPORTS_PIPELINE}'),
 'statement',(SELECT jsonb_build_object('id',r.id,'kind',r.kind,'recordSha256',encode(extensions.digest(to_jsonb(r)::text,'sha256'),'hex')) FROM finance.financial_reports r WHERE r.tenant_id='${scope.tenantId}' AND r.legal_entity_id='${scope.entityId}' AND r.requested_branch_id='${scope.branchId}' AND r.id='${statementId}'),
 'dateStateSha256',(SELECT encode(extensions.digest(jsonb_build_object(
  'proposals',(SELECT jsonb_agg(to_jsonb(p) ORDER BY id) FROM analytics.cash_date_proposals p WHERE p.tenant_id='${scope.tenantId}'),
  'decisions',(SELECT jsonb_agg(to_jsonb(d) ORDER BY id) FROM analytics.cash_date_decisions d WHERE d.tenant_id='${scope.tenantId}')
 )::text,'sha256'),'hex')),
 'approvedExportJobs',coalesce((SELECT jsonb_agg(jsonb_build_object('id',j.id,'actorId',j.actor_id,'resource',j.resource,'status',j.status,'format',j.file_format,'fileName',j.file_name,'fileSize',j.file_size,'rowCount',j.row_count,'filters',j.filters,'columns',j.columns_json) ORDER BY j.id) FROM core.export_jobs j WHERE j.tenant_id='${scope.tenantId}' AND j.id IN (${exportIds})),'[]'::jsonb),
 'approvedExportReceipts',coalesce((SELECT jsonb_agg(jsonb_build_object('commandId',r.command_id,'actorId',r.actor_id,'aggregateType',r.aggregate_type,'aggregateId',r.aggregate_id,'requestHash',r.request_hash) ORDER BY r.command_id) FROM core.command_receipts r WHERE r.tenant_id='${scope.tenantId}' AND r.command_id IN (${commandIds})),'[]'::jsonb)
) AS export_continuation_facts`;
export const EXPORTS_SQL_SHA256='f0783ac9e8b2041f2566c0fa64e8616d65c9fd2246f0a1809a36f4ce23f3b291';

// UTC-only parsing prevents local timezone interpretation and invalid calendar
// normalization. PostgreSQL microseconds remain bound by the source records.
const utcMillis=value=>{
 must(typeof value==='string'&&/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d{1,6})?(?:Z|\+00:00)$/.test(value),
  'EXPLICIT_UTC_EXPORT_TIMESTAMP_REQUIRED');
 const milliseconds=Date.parse(value);
 must(Number.isFinite(milliseconds)&&new Date(milliseconds).toISOString().slice(0,19)===value.slice(0,19),'VALID_UTC_EXPORT_TIMESTAMP_REQUIRED');
 return milliseconds;
};
export function validateExportsWindow(window){
 must(exactKeys(window,['notBefore','edgeExpiresAt','scopeExpiresAt','privateExpiresAt','expiresAt']),'EXPLICIT_REVIEWED_EXPORT_WINDOW_REQUIRED');
 const start=utcMillis(window.notBefore),edge=utcMillis(window.edgeExpiresAt),scopeEnd=utcMillis(window.scopeExpiresAt),
  privateEnd=utcMillis(window.privateExpiresAt),end=utcMillis(window.expiresAt);
 must(edge===scopeEnd&&edge>start&&edge-start<=EXPORTS_MAX_WINDOW_MS&&privateEnd>start
  &&end===Math.min(edge,scopeEnd,privateEnd)&&end>start,'EXACT_BOTH_RENEWED_EXPIRIES_AND_EARLIEST_DEADLINE_REQUIRED');
 return window;
}
export function validateExportsTime(value,{now=Date.now(),server=false,window}={}){
 validateExportsWindow(window);
 const clock=typeof value==='number'?value:utcMillis(value);
 must(Number.isFinite(clock)&&Number.isFinite(now)&&clock>=utcMillis(window.notBefore)&&clock<utcMillis(window.expiresAt)
  &&clock<=now+10000,'CURRENT_REVIEWED_EXPORT_WINDOW_REQUIRED');
 if(server)must(now-clock>=-10000&&now-clock<=45000,'FRESH_EXPORT_SERVER_CLOCK_REQUIRED');
 return clock;
}
export function validateExportsProfile(profile,documents,now=Date.now()){
 const {sourcePolicy,independentReview,ownerDecision,renewalReadback,metadata,refresh,accounting,dependency}=documents??{};
 must(profile?.kind==='source-reviewed-renewed-export-a6-profile'&&profile.projectId===PROJECT&&profile.runtimeBundleSha256===BUNDLE
  &&profile.priorConservativeBound===138&&profile.ordinaryAttempts===24&&profile.ordinaryLimit===162&&profile.cumulativeLimit===163
  &&profile.resolutionAttempts===1&&profile.originalFixtureUtcDay===FINANCE_CALENDAR.fixtureDay
  &&profile.personalHumanExactSourceSignatureClaimed===false&&exactKeys(profile.controlBindings,Object.keys(EXPORTS_PROFILE_PATHS)),
  'EXACT_RENEWED_A6_EXPORT_PROFILE_REQUIRED');
 for(const [name,file] of Object.entries(EXPORTS_PROFILE_PATHS))must(profile.controlBindings[name]?.path===file&&digest(profile.controlBindings[name].sha256),
  'FIXED_REVIEWED_EXPORT_PROFILE_BINDINGS_REQUIRED');
 must(sameFinanceJson(profile.controlBindings.dependency,EXPORTS_DEPENDENCY),'PINNED_CURRENT134_ACCOUNTING_DEPENDENCY_REQUIRED');
 must(sourcePolicy?.kind==='source-only-export-a6-renewal-policy'&&sourcePolicy.projectId===PROJECT&&sourcePolicy.runtimeBundleSha256===BUNDLE
  &&sourcePolicy.runtimeId===EXPORTS_RUNTIME_ID&&sourcePolicy.sourceImplementationOnly===true&&sourcePolicy.liveExecutionAuthorized===false
  &&sourcePolicy.originalConcreteCumulativeCap===150&&sameFinanceJson(sourcePolicy.budget,EXPORTS_REVIEWED_BUDGET)
  &&sourcePolicy.windowMode==='server-clock-at-application'&&sourcePolicy.maximumWindowMs===EXPORTS_MAX_WINDOW_MS
  &&sameFinanceJson(sourcePolicy.originalWindow,EXPORTS_ORIGINAL_WINDOW)&&sameFinanceJson(sourcePolicy.dependencyBinding,EXPORTS_DEPENDENCY)
  &&sameFinanceJson(sourcePolicy.permittedOriginalExportCommands,EXPORTS_COMMANDS)&&sourcePolicy.originalFixtureUtcDay===FINANCE_CALENDAR.fixtureDay
  &&sameFinanceJson(sourcePolicy.a5SourceBindings,EXPORTS_A5_SOURCE_BINDINGS)&&sourcePolicy.preservedOriginalSourceCount===68
  &&sourcePolicy.consolidatedSqlSha256===EXPORTS_SQL_SHA256&&hashBytes(EXPORTS_FACTS_SQL)===EXPORTS_SQL_SHA256
  &&sourcePolicy.maximumRunMs===900000&&sourcePolicy.maximumRequestMs===45000&&sourcePolicy.ordinaryReserveMs===90000
  &&sourcePolicy.resolutionReserveMs===45000&&sourcePolicy.transportRetries===0&&sourcePolicy.unlistedCallsAllowed===0
  &&sourcePolicy.schedulesMustRemainPaused===true&&sourcePolicy.onlyTwoExpiryFieldsMayChange===true
  &&digest(sourcePolicy.renewalOperationBundleSha256)&&Array.isArray(sourcePolicy.exportSourceBindings)
  &&sourcePolicy.exportSourceBindings.length===EXPORTS_SOURCE_PATHS.length&&sourcePolicy.exportSourceBindings.every((row,i)=>
   row.path===EXPORTS_SOURCE_PATHS[i]&&digest(row.sha256)),'EXACT_SOURCE_ONLY_A6_RENEWAL_POLICY_REQUIRED');
 must(independentReview?.kind==='independent-export-a6-policy-review'&&independentReview.passed===true
  &&independentReview.sourceOnly===true&&independentReview.liveExecutionAuthorized===false
  &&sameFinanceJson(independentReview.policyBinding,profile.controlBindings.sourcePolicy)
  &&sameFinanceJson(independentReview.exportSourceBindings,sourcePolicy.exportSourceBindings)
  &&sameFinanceJson(independentReview.budget,EXPORTS_REVIEWED_BUDGET)
  &&independentReview.renewalOperationBundleSha256===sourcePolicy.renewalOperationBundleSha256
  &&independentReview.exactConsolidatedSqlSha256===EXPORTS_SQL_SHA256,'EXACT_INDEPENDENT_A6_POLICY_REVIEW_REQUIRED');
 // A boolean or delegated technical approval alone is insufficient. The final
 // operation review pins the exact direct-user reply record and its byte hash.
 must(ownerDecision?.kind==='direct-human-runtime-renewal-and-export-a6-decision'&&ownerDecision.approved===true
  &&ownerDecision.approvalSource==='direct-user-reply'&&ownerDecision.exactReply===EXPORTS_OWNER_REPLY
  &&typeof ownerDecision.questionItemId==='string'&&ownerDecision.questionItemId.length>=16&&ownerDecision.questionItemId.length<=300
  &&ownerDecision.projectId===PROJECT&&ownerDecision.runtimeBundleSha256===BUNDLE&&ownerDecision.runtimeId===EXPORTS_RUNTIME_ID
  &&sameFinanceJson(ownerDecision.sourcePolicyBinding,profile.controlBindings.sourcePolicy)
  &&sameFinanceJson(ownerDecision.independentReviewBinding,profile.controlBindings.independentReview)
  &&ownerDecision.operationBundleSha256===sourcePolicy.renewalOperationBundleSha256
  &&sameFinanceJson(ownerDecision.budget,EXPORTS_REVIEWED_BUDGET)&&ownerDecision.maximumWindowMs===EXPORTS_MAX_WINDOW_MS
  &&ownerDecision.onlyTwoExpiryFieldsMayChange===true&&ownerDecision.schedulesMustRemainPaused===true
  &&ownerDecision.productionAuthorized===false&&ownerDecision.realBillingAuthorized===false
  &&utcMillis(ownerDecision.decidedAt)<=now,'EXACT_DIRECT_HUMAN_RENEWAL_AND_A6_DECISION_REQUIRED');
 const start=utcMillis(renewalReadback?.appliedAt),observed=utcMillis(renewalReadback?.observedAt);
 must(renewalReadback?.kind==='actual-two-row-runtime-expiry-renewal-readback'&&renewalReadback.actual===true&&renewalReadback.committed===true
  &&renewalReadback.projectId===PROJECT&&renewalReadback.runtimeId===EXPORTS_RUNTIME_ID
  &&sameFinanceJson(renewalReadback.ownerDecisionBinding,profile.controlBindings.ownerDecision)
  &&sameFinanceJson(renewalReadback.sourcePolicyBinding,profile.controlBindings.sourcePolicy)
  &&renewalReadback.operationBundleSha256===sourcePolicy.renewalOperationBundleSha256
  &&renewalReadback.affectedRows===2&&renewalReadback.onlyTwoExpiryFieldsChanged===true&&renewalReadback.issuedAtUnchanged===true
  &&renewalReadback.nonWindowValuesUnchanged===true&&renewalReadback.jobsPaused===true&&renewalReadback.countersUnchanged===true
  &&renewalReadback.secretValuesRead===false&&renewalReadback.scope?.count===1&&renewalReadback.edge?.count===1
  &&renewalReadback.scope.runtimeId===EXPORTS_RUNTIME_ID&&renewalReadback.edge.runtimeId===EXPORTS_RUNTIME_ID
  &&renewalReadback.scope.tenantId===FINANCE_SCOPE.tenantId&&renewalReadback.scope.legalEntityId===FINANCE_SCOPE.entityId
  &&renewalReadback.scope.branchId===FINANCE_SCOPE.branchId
  &&renewalReadback.scope.issuedAt===EXPORTS_ORIGINAL_WINDOW.scopeIssuedAt&&renewalReadback.edge.issuedAt===EXPORTS_ORIGINAL_WINDOW.edgeIssuedAt
  &&renewalReadback.scope.oldExpiresAt===EXPORTS_ORIGINAL_WINDOW.scopeExpiresAt&&renewalReadback.edge.oldExpiresAt===EXPORTS_ORIGINAL_WINDOW.edgeExpiresAt
  &&renewalReadback.scope.nonWindowHash===EXPORTS_ORIGINAL_WINDOW.scopeNonWindowHash
  &&renewalReadback.edge.nonWindowHash===EXPORTS_ORIGINAL_WINDOW.edgeNonWindowHash
  &&start>=utcMillis(ownerDecision.decidedAt)&&observed>=start&&observed-start<=45000&&observed<=now
  &&now-observed<=EXPORTS_MAX_WINDOW_MS,'ACTUAL_BOTH_EXPIRY_ROWS_AND_PRESERVATION_READBACK_REQUIRED');
 must(metadata?.kind==='wave5-private-owner-input-metadata'&&metadata.projectId===PROJECT&&metadata.runtimeBundleSha256===BUNDLE
  &&metadata.metadataFilename==='metadata-renewed-a10.json'&&metadata.containsPlaintextCredential===false
  &&metadata.reuseAuthorizationQuestionId==='["request_user_input_async","call_637ea7df9a28457388be21396163da04",0]'
  &&sameFinanceJson(metadata.refreshEvidence,profile.controlBindings.refresh)&&utcMillis(metadata.createdAt)<=now
  &&utcMillis(metadata.createdAt)>=utcMillis(ownerDecision.decidedAt)&&utcMillis(metadata.expiresAt)>now
  &&utcMillis(metadata.expiresAt)>utcMillis(metadata.createdAt)
  &&utcMillis(metadata.expiresAt)-utcMillis(metadata.createdAt)<=EXPORTS_MAX_WINDOW_MS,'EXACT_FRESH_A10_EXPORT_METADATA_REQUIRED');
 must(refresh?.kind==='actual-private-owner-scope-refresh'&&refresh.projectId===PROJECT&&refresh.organizationId===ORGANIZATION
  &&refresh.actualStatus==='ACTIVE_HEALTHY'&&refresh.readOnlyOwnerApiCalls===1&&refresh.actualVerifiedAt===metadata.createdAt
  &&digest(refresh.helperSha256)&&refresh.helperSha256===metadata.helperSha256&&refresh.databaseWrites===0&&refresh.authWrites===0&&refresh.settingsChanges===0,
  'ACTUAL_CHARGED_A10_READINESS_REFRESH_REQUIRED');
 must(dependency?.kind==='actual-readonly-runtime-expiry-dependency-investigation'&&dependency.projectId===PROJECT&&dependency.mutation===false
  &&dependency.conservativeContinuationAccounting?.cumulativeChargedCalls===134
  &&dependency.conservativeContinuationAccounting.actualA10RefreshPerformed===false
  &&accounting?.kind==='conservative-renewed-export-a6-read-accounting'&&accounting.projectId===PROJECT
  &&sameFinanceJson(accounting.recordedPriorBinding,EXPORTS_DEPENDENCY)&&accounting.recordedPrior===134
  &&accounting.chargedA10OwnerIdentityReads===1&&accounting.chargedRenewalControlCalls===3&&accounting.otherFinanceCallsSinceDependency===0
  &&accounting.cumulativeChargedPriorCalls===138&&sameFinanceJson(accounting.actualA10Refresh,profile.controlBindings.refresh)
  &&sameFinanceJson(accounting.actualRenewalReadback,profile.controlBindings.renewalReadback)
  &&sameFinanceJson(accounting.renewalCallAccounting,renewalReadback.controlCallAccounting),
  'EXACT_CHARGED_EXPORT_PRIOR138_REQUIRED');
 const renewalCalls=renewalReadback.controlCallAccounting;
 must(renewalCalls?.attempts===3&&renewalCalls.failedAttempts===0&&renewalCalls.automaticRetries===0
  &&Array.isArray(renewalCalls.receipts)&&renewalCalls.receipts.length===3&&renewalCalls.receipts.every((row,i)=>
   row.ordinal===136+i&&row.phase===['preflight','two-row-expiry-write','readback'][i]&&row.successful===true&&digest(row.responseSha256)),
  'THREE_ACTUALLY_CHARGED_RENEWAL_CONTROL_RECEIPTS_REQUIRED');
 const window=immutableJson({notBefore:new Date(start).toISOString(),
  edgeExpiresAt:new Date(utcMillis(renewalReadback.edge.expiresAt)).toISOString(),
  scopeExpiresAt:new Date(utcMillis(renewalReadback.scope.expiresAt)).toISOString(),
  privateExpiresAt:new Date(utcMillis(metadata.expiresAt)).toISOString(),
  expiresAt:new Date(Math.min(utcMillis(renewalReadback.edge.expiresAt),utcMillis(renewalReadback.scope.expiresAt),utcMillis(metadata.expiresAt))).toISOString()});
 must(sameFinanceJson(profile.window,window)&&profile.privateAdapterPredecessor?.path==='scripts/wave5/run_private_management_installer_20261013_r5.ps1'
  &&digest(profile.privateAdapterPredecessor.sha256),'REVIEWED_EXPORT_WINDOW_AND_ADAPTER_REQUIRED');
 validateExportsTime(now,{now,window});return {window,controlBindings:profile.controlBindings,priorConservativeBound:138};
}
export function validateExportsConsumed({a3Stop,a3Once,a3Plan,payroll,reimbursement}){
 must(a3Plan?.maximumTotalWorkflowRequestAttempts===150&&a3Plan.priorRequestBound===78&&a3Stop?.kind==='genuine-finance-remaining-stop'
  &&a3Stop.failureCode==='ACTUAL_NONEMPTY_PIPELINE_EXPORT_REQUIRED'&&a3Stop.phase==='report_export_preview'&&a3Stop.priorRequestBound===78
  &&a3Stop.actualRemainingAttempts===50&&a3Stop.totalRequestBound===128&&a3Stop.lastOriginalCommand===null&&a3Stop.resolution===null
  &&a3Stop.automaticRetryPerformed===false&&a3Stop.staleOriginalCommandId===STALE_COMMAND&&a3Stop.staleOriginalCommandReplayed===false,
  'EXACT_COMPLETED_A3_STOP_REQUIRED');
 const expected=[];for(const kind of ['payroll_correction','project_reimbursement'])for(const action of ['prepare','approve','prepare'])expected.push({
  name:'wave5_cash_date_command',commandId:id('command.date.'+action+'.'+kind),actorId:action==='approve'?'0635081d-08ea-4ad1-b7f2-ad2f8721f67d':FINANCE_ACTOR});
 must(sameFinanceJson(a3Stop.completed,expected)&&a3Once?.planSha256===EXPORTS_PRESERVED_BINDINGS.a3Plan.sha256
  &&a3Once.priorRequestBound===78&&a3Once.retryOrReplayOfStaleForbidden===true,'ALL_ORIGINAL_A3_DATE_COMMANDS_PRESERVED_REQUIRED');
 for(const [kind,value] of [['payroll_correction',payroll],['project_reimbursement',reimbursement]])must(value?.canonicalFullValueIdentical===true
  &&value.rawResponseSha256Identical===true&&value.originalPreparedResponseSha256===value.originalReplayResponseSha256&&digest(value.originalPreparedResponseSha256)
  &&value.readback?.id===id('date.'+kind)&&value.readback.decision==='approved'&&value.readback.currentApproval?.version==='1'
  &&value.actualDistinctApprover==='0635081d-08ea-4ad1-b7f2-ad2f8721f67d','ACTUAL_COMPLETED_DATE_APPROVAL_AND_EXACT_REPLAY_REQUIRED');
 return {successfulDatePairsPreserved:2,exactReplaysPreserved:2,uncertainCommand:null,reexecutionAllowed:false};
}
export function validateExportsState(facts,{before,artifacts=[],now=Date.now(),window}={}){
 must(facts&&facts.installedMigrationCount===115&&facts.installedApiFunctionCount===363,'EXACT_EXPORT_INSTALLED115_BASELINE_REQUIRED');
 validateExportsTime(facts.observedAt,{now,server:true,window});validateRemainingFunctions(facts.functions);
 const after=before!==undefined,count=after?2:0;
 for(const value of [facts.originalBaseline,facts.wholeSource,facts.sourceExcludingOnlyApprovedExportEvents])must(value?.journals===9&&value.lines===18
  &&sameFinanceJson(value.journalIds,FINANCE_JOURNALS.map(row=>row.id).sort())&&value.publications===3&&value.classifications===1
  &&value.dateProposals===3&&value.dateDecisions===3&&value.scenarios===0&&value.exports===count,'EXACT_UNCHANGED_EXPORT_FINANCE_COUNTS_REQUIRED');
 must(facts.originalBaseline.sourceHash===ORIGINAL_SOURCE_HASH&&facts.sourceExcludingOnlyApprovedExportEvents.sourceHash===CURRENT_WHOLE_SOURCE_HASH,
  'ORIGINAL_EXPORT_SOURCE_DIGEST_REQUIRED');
 must(after?digest(facts.wholeSource.sourceHash)&&facts.wholeSource.sourceHash!==CURRENT_WHOLE_SOURCE_HASH:
  facts.wholeSource.sourceHash===CURRENT_WHOLE_SOURCE_HASH,'EXACT_EXPORT_RAW_WHOLE_DIGEST_REQUIRED');
 validateRemainingQuiescence(facts.observation);
 const wanted=EXPECTED_PROCESS_APPENDS.slice(0,after?5:3);
 must(facts.observation.originalProcessRows===4&&Array.isArray(facts.observation.processAppends)&&facts.observation.processAppends.length===wanted.length,
  'ONLY_ORIGINAL_TWO_EXPORT_PROCESS_APPENDS_REQUIRED');
 for(const row of wanted){const matches=facts.observation.processAppends.filter(value=>value.commandId===row.commandId);
  must(matches.length===1&&isUuid(matches[0].id)&&matches[0].fromStatus===null&&Object.entries(row).every(([key,value])=>matches[0][key]===value),
   'EXACT_EXPORT_PROCESS_ACTOR_AND_COMMAND_REQUIRED');}
 must(new Set(facts.observation.processAppends.map(row=>row.id)).size===wanted.length,'UNIQUE_EXPORT_PROCESS_EVENTS_REQUIRED');
 must(facts.pipeline?.id===EXPORTS_PIPELINE&&facts.pipeline.sourceCount===2&&facts.pipeline.sourceHash===EXPORTS_PIPELINE_BASIS
  &&sameFinanceJson(facts.pipeline.currencies,EXPORTS_ROWS)&&digest(facts.pipeline.recordSha256)
  &&facts.statement?.id===statementId&&facts.statement.kind==='profit_loss'&&digest(facts.statement.recordSha256)&&digest(facts.dateStateSha256),
  'EXACT_IMMUTABLE_TWO_CURRENCY_PIPELINE_AND_STATEMENT_REQUIRED');
 must(Array.isArray(facts.approvedExportJobs)&&Array.isArray(facts.approvedExportReceipts)
  &&facts.approvedExportJobs.length===count&&facts.approvedExportReceipts.length===count,'EXACT_ORIGINAL_EXPORT_RECEIPT_AND_JOB_COUNTS_REQUIRED');
 if(after){
  must(before.dateStateSha256===facts.dateStateSha256&&before.pipeline.recordSha256===facts.pipeline.recordSha256
   &&before.statement.recordSha256===facts.statement.recordSha256&&artifacts.length===2,'EXPORT_ONLY_SOURCE_RECORDS_UNCHANGED_REQUIRED');
  for(const artifact of artifacts){const spec=EXPORTS_COMMANDS.find(row=>row.documentId===artifact.exportId),jobs=facts.approvedExportJobs.filter(row=>row.id===artifact.exportId),
   receipts=facts.approvedExportReceipts.filter(row=>row.commandId===spec?.commandId);
   must(spec&&jobs.length===1&&receipts.length===1&&jobs[0].actorId===FINANCE_ACTOR&&jobs[0].resource==='wave3.'+artifact.sourceType
    &&jobs[0].status==='completed'&&jobs[0].format==='csv'&&jobs[0].fileName===artifact.fileName&&jobs[0].fileSize===artifact.size
    &&jobs[0].rowCount===artifact.rowCount&&sameFinanceJson(jobs[0].columns,artifact.columns)
    &&jobs[0].filters?.source_id===artifact.sourceId&&jobs[0].filters.source_type===artifact.sourceType
    &&jobs[0].filters.source_hash===artifact.sourceHash&&jobs[0].filters.file_sha256===artifact.fileSha256
    &&jobs[0].filters.prepared_at===artifact.preparedAt&&receipts[0].actorId===FINANCE_ACTOR
    &&receipts[0].aggregateType==='report_export'&&receipts[0].aggregateId===artifact.exportId&&digest(receipts[0].requestHash),
    'EXACT_REGISTERED_EXPORT_COMMITTED_READBACK_REQUIRED');
  }
 }
 return facts;
}
const descriptor=(kind,method,route,query)=>({kind,method,route,...(query===undefined?{}:{query})});
export function exportsCallDescriptors(){
 const result=[descriptor('management','POST','/database/query',EXPORTS_FACTS_SQL),descriptor('key','GET','/api-keys?reveal=true')];
 for(let session=0;session<2;session++)result.push(descriptor('auth','POST','/auth/v1/token?grant_type=password'),
  descriptor('auth','POST',`/auth/v1/factors/${EXPORTS_FACTOR}/challenge`),descriptor('management','POST','/database/query','SELECT statement_timestamp()::text AS observed_at'),
  descriptor('auth','POST',`/auth/v1/factors/${EXPORTS_FACTOR}/verify`),descriptor('auth','GET','/auth/v1/user'),descriptor('session-row','POST','/database/query'));
 result.push(descriptor('rpc','POST','/rest/v1/rpc/report_export_preview'),descriptor('management','POST','/database/query',REMAINING_ACTIVITY_SQL),
  descriptor('rpc','POST','/rest/v1/rpc/record_report_export'),descriptor('rpc','POST','/rest/v1/rpc/wave5_export_reopen'),
  descriptor('rpc','POST','/rest/v1/rpc/report_export_preview'),descriptor('rpc','POST','/rest/v1/rpc/financial_statement_page'),
  descriptor('management','POST','/database/query',REMAINING_ACTIVITY_SQL),descriptor('rpc','POST','/rest/v1/rpc/record_report_export'),
  descriptor('rpc','POST','/rest/v1/rpc/report_export_preview'),descriptor('management','POST','/database/query',EXPORTS_FACTS_SQL));
 return result;
}
export function createExportsCallGate({now=Date.now,startedAt=now(),signal,window}={}){
 must(typeof now==='function'&&Number.isFinite(startedAt),'EXPORT_ATTEMPT_GATE_REQUIRED');
 window=immutableJson(validateExportsWindow(window));validateExportsTime(startedAt,{now:now(),window});
 const slots=exportsCallDescriptors();let ordinary=0,resolutions=0,busy=false,stopped=false;
 const checkClock=resolution=>{const stamp=now();validateExportsTime(stamp,{now:stamp,window});const reserve=resolution?45000:90000;
  must(stamp>=startedAt&&stamp+reserve<=Math.min(startedAt+900000,utcMillis(window.expiresAt)),
   'EXPORT_INFLIGHT_AND_RESOLUTION_TIME_RESERVED_REQUIRED');
  if(!resolution)must(!signal?.aborted,'EXPORT_EXECUTION_ABORTED');};
 return Object.freeze({stop(){stopped=true;},snapshot(){return {priorConservativeBound:138,actualOrdinaryAttempts:ordinary,actualReadOnlyResolutionAttempts:resolutions,
  totalWorkflowRequestBound:138+ordinary+resolutions,maximumCumulativeAttemptLimit:163,automaticRetries:0};},
  async dispatch(request,send,{resolutionCommand}={}){
   must(!busy&&typeof send==='function','SEQUENTIAL_EXPORT_DISPATCH_REQUIRED');
   if(resolutionCommand!==undefined){must(stopped&&resolutions===0&&EXPORTS_COMMANDS.some(row=>row.commandId===resolutionCommand)
    &&sameFinanceJson(request,descriptor('resolution','POST','/database/query',receiptResolutionSql(resolutionCommand))),
    'ONE_PENDING_ORIGINAL_EXPORT_READONLY_RESOLUTION_REQUIRED');checkClock(true);resolutions++;
   }else{must(!stopped&&ordinary<24,'ORDERED_24_EXPORT_ATTEMPTS_REQUIRED');checkClock(false);const expected=slots[ordinary];let match=sameFinanceJson(expected,request);
    if(expected.kind==='session-row'&&request.kind==='session-row'){
     const session=request.query?.match(/WHERE s\.id='([a-f0-9-]{36})'::uuid AND s\.user_id='([a-f0-9-]{36})'::uuid;/);
     match=isUuid(session?.[1])&&session[2]===FINANCE_ACTOR&&sameFinanceJson(request,descriptor('session-row','POST','/database/query',bindUuidSessionQuery(session[1],FINANCE_ACTOR)));
    }
    must(match,'EXACT_ORDERED_EXPORT_CALL_REQUIRED');ordinary++;
   }
   must(138+ordinary+resolutions<=163,'EXPORT_CUMULATIVE163_BOUND_REQUIRED');busy=true;
   try{return await send();}catch(error){stopped=true;throw error;}finally{busy=false;}
  }
 });
}
export function validateExportsDocument(preview,label){
 must(typeof preview?.canonical_text==='string'&&Buffer.byteLength(preview.canonical_text)<=8388608
  &&hashBytes(preview.canonical_text)===preview.source_hash,'ACTUAL_CANONICAL_EXPORT_HASH_REQUIRED');
 const document=JSON.parse(preview.canonical_text),meta=document.metadata,pipeline=label==='pipeline';
 must(['pipeline','statement'].includes(label)&&document.version===1&&meta?.tenant_id===scope.tenantId&&meta.legal_entity_id===scope.entityId
  &&meta.branch_id===scope.branchId&&meta.working_branch_id===scope.branchId&&meta.actor_id===FINANCE_ACTOR
  &&meta.source_id===(pipeline?EXPORTS_PIPELINE:statementId)&&meta.source_type===(pipeline?'w5_pipeline':'statement')
  &&meta.section===(pipeline?'currencies':'accounts')&&exactKeys(meta.filters,[])&&Array.isArray(document.rows)&&meta.row_count===document.rows.length,
  'EXACT_ORIGINAL_EXPORT_DOCUMENT_SCOPE_REQUIRED');
 if(pipeline)must(meta.source_basis_hash===EXPORTS_PIPELINE_BASIS&&document.rows.length===2&&sameFinanceJson(document.rows,EXPORTS_ROWS),
  'EXACT_UNCOERCED_TWO_CURRENCY_EXPORT_REQUIRED');
 else must(document.rows.length===10&&meta.id===statementId&&meta.kind==='profit_loss','EXACT_ORIGINAL_TEN_ROW_STATEMENT_REQUIRED');
 return document;
}
export function validateExportsCommand(body,{now=Date.now(),window}={}){
 validateRemainingCommand('record_report_export',body);validateExportsTime(now,{now,window});
 const pipeline=body.p_payload.id===id('export.pipeline');
 must(body.p_payload.source_id===(pipeline?EXPORTS_PIPELINE:statementId),'FIXED_IMMUTABLE_EXPORT_SOURCE_REQUIRED');
 validateExportsTime(body.p_client_timestamp,{now,window});validateExportsTime(body.p_payload.prepared_at,{now,window});
}
export function validateExportsSessionPair(actor,fresh){
 for(const who of [actor,fresh])must(who?.proof?.actorId===FINANCE_ACTOR&&who.proof.factorId===EXPORTS_FACTOR&&isUuid(who.proof.sessionId)
  &&who.proof.aal==='aal2'&&who.proof.onlineAuthVerified===true&&who.proof.serverSessionRowVerified===true&&who.proof.constructedAalClaims===false
  &&typeof who.request==='function','GENUINE_INDEPENDENT_EXPORT_MFA_SESSIONS_REQUIRED');
 must(actor.proof.sessionId!==fresh.proof.sessionId,'DISTINCT_GENUINE_EXPORT_SESSION_IDS_REQUIRED');
}
export async function createExclusiveExportFiles(directory){
 must(path.isAbsolute(directory)&&path.resolve(await fs.realpath(directory))===path.resolve(directory),'EXPORT_OUTPUT_REDIRECTION_FORBIDDEN');
 const names=['Jentra-W5-Synthetic-pipeline.csv','Jentra-W5-Synthetic-statement.csv'];
 return Object.freeze({async write(file,bytes){
  must(names.includes(file)&&Buffer.isBuffer(bytes)&&bytes.length>0&&bytes.length<=10485760,'FIXED_BOUNDED_EXPORT_FILE_REQUIRED');
  const handle=await fs.open(path.join(directory,file),'wx');try{await handle.writeFile(bytes);await handle.sync();}finally{await handle.close();}
  return {path:'dist/'+file,sha256:hashBytes(bytes),bytes:bytes.length};
 },async read(file){must(names.includes(file),'FIXED_EXPORT_FILE_READ_REQUIRED');const target=path.join(directory,file),stat=await fs.lstat(target);
  must(stat.isFile()&&!stat.isSymbolicLink()&&stat.size>0&&stat.size<=10485760&&path.resolve(await fs.realpath(target))===path.resolve(target),
   'BOUNDED_ORIGINAL_EXPORT_BYTES_REQUIRED');return fs.readFile(target);
 }});
}
// These injectable ports support controlled tests; the private CLI below wires
// the original genuine session helper and verified-TLS transports unchanged.
export async function runExportsContinuation({ports,planSha256,savedStatement,now=Date.now,startedAt=now(),signal,window,portTimeoutMs=45000}={}){
 must(digest(planSha256)&&ports&&['management','keyReader','session','appendPrivate','persist','writeFile','readFile','close'].every(name=>typeof ports[name]==='function')
  &&savedStatement?.id===statementId&&savedStatement.summary?.id===statementId&&Number.isInteger(portTimeoutMs)&&portTimeoutMs>0&&portTimeoutMs<=45000,
  'BOUND_EXPORT_EXECUTION_PORTS_REQUIRED');
 window=immutableJson(validateExportsWindow(window));
 const gate=createExportsCallGate({now,startedAt,signal,window}),artifacts=[],completed=[];
 let writer,before,stage='preflight',journalSequence=0,writeAttempted=false,closePromise;
 const closePorts=()=>closePromise??=(Promise.resolve().then(()=>ports.close()));
 const waitPort=(operation,{ignoreAbort=false,evidenceOnly=false,maxMs=portTimeoutMs}={})=>new Promise((resolve,reject)=>{
  let settled=false,timer;const finish=(fn,value)=>{if(settled)return;settled=true;clearTimeout(timer);signal?.removeEventListener('abort',abort);fn(value);};
  const fail=code=>{const error=Error(code);error.publicCode=code;finish(reject,error);};
  const abort=()=>fail('EXPORT_EXECUTION_ABORTED');
  if(!evidenceOnly){try{const clock=now();validateExportsTime(clock,{now:clock,window});}catch(error){finish(reject,error);return;}}
  const remaining=evidenceOnly?Math.min(maxMs,5000):Math.min(maxMs,startedAt+900000-now(),utcMillis(window.expiresAt)-now());
  if(remaining<=0){fail('EXPORT_PORT_DEADLINE_REQUIRED');return;}
  if(!ignoreAbort&&signal?.aborted){abort();return;}
  if(!ignoreAbort)signal?.addEventListener('abort',abort,{once:true});
  timer=setTimeout(()=>fail('EXPORT_PORT_DEADLINE_REQUIRED'),remaining);
  Promise.resolve().then(()=>settled?undefined:operation()).then(value=>finish(resolve,value),error=>finish(reject,error));
 });
 // Local audit persistence may finish after expiry. It cannot call a transport,
 // is capped at5s independently, and never extends dispatch authority.
 const persist=async(file,value)=>{if(now()>=Math.min(startedAt+900000,utcMillis(window.expiresAt)))await closePorts();
  const receipt=await waitPort(()=>ports.persist(file,value),{ignoreAbort:true,evidenceOnly:true});
  must(typeof receipt?.path==='string'&&digest(receipt.sha256),'ACKNOWLEDGED_EXPORT_EVIDENCE_REQUIRED');return receipt;};
 const management=async(query,{resolutionCommand,file}={})=>{
  const kind=resolutionCommand?'resolution':query.includes('WHERE s.id=')?'session-row':'management';
  const response=await gate.dispatch(descriptor(kind,'POST','/database/query',query),()=>waitPort(()=>ports.management(query),{ignoreAbort:!!resolutionCommand}),{resolutionCommand});
  await persistRemainingPreflightResponse({persist,file:file??`read-${gate.snapshot().actualOrdinaryAttempts}.json`,query,response});return response;
 };
 const sessionContext={management:async(method,suffix,body)=>{must(method==='POST'&&suffix==='/database/query'&&body?.read_only===true,
  'ONLY_EXPORT_SESSION_READONLY_SQL_REQUIRED');return management(body.query);},send:async(route,options,send)=>{
   must(route.startsWith('/auth/v1/'),'ONLY_GENUINE_EXPORT_SESSION_AUTH_REQUIRED');return gate.dispatch(descriptor('auth',options?.method??'POST',route),()=>waitPort(send));
  }};
 const request=async(who,name,body)=>{
  must(['report_export_preview','record_report_export','wave5_export_reopen','financial_statement_page'].includes(name),'ONLY_FOUR_EXPORT_RPC_ROUTES_REQUIRED');
  return gate.dispatch(descriptor('rpc','POST','/rest/v1/rpc/'+name),()=>{
   if(name==='record_report_export')writeAttempted=true;
   return waitPort(()=>who.request('/rest/v1/rpc/'+name,{...FINANCE_SCOPED_BODY,...body}));
  });
 };
 const readRpc=async(who,name,body)=>{const response=await request(who,name,body);
  await persist(`rpc-${gate.snapshot().actualOrdinaryAttempts}.json`,{name,status:response?.status,responseSha256:response?.responseSha256,
   value:response?.ok===true?response.value:null,validationPending:true});must(response?.ok===true&&digest(response.responseSha256),'ACTUAL_EXPORT_RPC_READ_REQUIRED');return response.value;};
 try{
  before=validateExportsState((await management(EXPORTS_FACTS_SQL,{file:'00-before-response.json'})).value[0]?.export_continuation_facts,{now:now(),window});
  const preparedAt=new Date(before.observedAt).toISOString();
  await gate.dispatch(descriptor('key','GET','/api-keys?reveal=true'),()=>waitPort(()=>ports.keyReader()));
  stage='writer-session';const actor=await waitPort(()=>ports.session('writer',sessionContext),{maxMs:portTimeoutMs*6});
  stage='independent-reopen-session';const fresh=await waitPort(()=>ports.session('independent-reopen',sessionContext),{maxMs:portTimeoutMs*6});validateExportsSessionPair(actor,fresh);
  writer=createRemainingCommandWriter({planSha256,signal,appendPrivate:(kind,value)=>waitPort(()=>ports.appendPrivate(kind,value)),
   appendPublic:record=>persist(`journal-${++journalSequence}-${record.kind}.json`,record),
   send:async(who,name,body)=>{must(name==='record_report_export','ONLY_TWO_ORIGINAL_EXPORT_WRITES_REQUIRED');validateExportsCommand(body,{now:now(),window});
    const observation=(await management(REMAINING_ACTIVITY_SQL,{file:`quiescence-${body.p_payload.id}.json`})).value[0]?.observation;
    validateRemainingQuiescence(observation);validateExportsTime(observation.observedAt,{now:now(),server:true,window});
    const clock=now();validateExportsTime(clock,{now:clock,window});writeAttempted=false;return request(who,name,body);
   }});
  for(const label of ['pipeline','statement']){
   stage=label;const pipeline=label==='pipeline',sourceId=pipeline?EXPORTS_PIPELINE:statementId,sourceType=pipeline?'w5_pipeline':'statement',section=pipeline?'currencies':'accounts';
   const previewBody={p_source_type:sourceType,p_source_id:sourceId,p_section:section,p_filters:{}},preview=await readRpc(actor,'report_export_preview',previewBody);
   const document=validateExportsDocument(preview,label);
   if(!pipeline){const page=await readRpc(fresh,'financial_statement_page',{p_report_id:sourceId,p_section:'accounts',p_offset:0,p_account_id:null});
    must(sameFinanceJson(page.summary,savedStatement.summary)&&page.items?.length===10&&page.next_offset===null&&sameFinanceJson(page.items,document.rows),
     'ACTUAL_ORIGINAL_FRESH_STATEMENT_SOURCE_REQUIRED');}
   const exportId=id('export.'+label),commandId=id('command.export.'+label),artifact=encodeFinanceCsv(document,{exportId,preparedAt,sourceHash:preview.source_hash});
   const fileName='Jentra-W5-Synthetic-'+label+'.csv',file=await waitPort(()=>ports.writeFile(fileName,artifact.bytes));
   must(file?.sha256===artifact.sha256&&file.bytes===artifact.bytes.length,'ACKNOWLEDGED_ORIGINAL_EXPORT_FILE_REQUIRED');
   must(artifact.bytes.equals(await waitPort(()=>ports.readFile(fileName))),'ACTUAL_SAVED_EXPORT_BYTES_REQUIRED');
   const body={p_command_id:commandId,p_idempotency_key:commandId,p_client_timestamp:before.observedAt,p_expected_entity_version:'0',
    p_payload:{id:exportId,source_type:sourceType,source_id:sourceId,section,filters:{},source_hash:preview.source_hash,file_sha256:artifact.sha256,file_format:'csv',
     file_name:fileName,file_size:artifact.bytes.length,columns:artifact.columns,prepared_at:preparedAt}};
   validateExportsCommand(body,{now:now(),window});writeAttempted=false;
   await writer.write(actor,'record_report_export',body,value=>must(value.command_id===commandId&&value.entity?.id===exportId
    &&value.entity.file_sha256===artifact.sha256&&value.entity.source_hash===preview.source_hash&&value.entity.actor_id===FINANCE_ACTOR,
    'ACTUAL_ORIGINAL_EXPORT_REGISTRATION_REQUIRED'));
   completed.push({name:'record_report_export',commandId,exportId,actorId:FINANCE_ACTOR});
   if(pipeline){const opened=await readRpc(fresh,'wave5_export_reopen',{p_export_id:exportId});
    must(opened.id===exportId&&opened.sourceHash===preview.source_hash&&opened.fileHash===artifact.sha256&&opened.format==='csv'&&opened.fileName===fileName
     &&opened.preparedAt===preparedAt&&opened.canonicalText===preview.canonical_text,'ACTUAL_REGISTERED_PIPELINE_REOPEN_REQUIRED');
    const reproduced=encodeFinanceCsv(validateExportsDocument({canonical_text:opened.canonicalText,source_hash:opened.sourceHash},label),
     {exportId,preparedAt:opened.preparedAt,sourceHash:opened.sourceHash});
    must(reproduced.sha256===artifact.sha256&&reproduced.bytes.equals(await waitPort(()=>ports.readFile(fileName))),'ACTUAL_PIPELINE_CSV_BYTE_REPRODUCTION_REQUIRED');
   }else{const reproduced=await readRpc(fresh,'report_export_preview',previewBody);
    must(reproduced.source_hash===preview.source_hash&&reproduced.canonical_text===preview.canonical_text,'ACTUAL_CANONICAL_STATEMENT_REPRODUCTION_REQUIRED');
    const encoded=encodeFinanceCsv(validateExportsDocument(reproduced,label),{exportId,preparedAt,sourceHash:reproduced.source_hash});
    must(encoded.sha256===artifact.sha256&&encoded.bytes.equals(await waitPort(()=>ports.readFile(fileName))),'ACTUAL_STATEMENT_CSV_BYTE_REPRODUCTION_REQUIRED');}
   const evidence={exportId,sourceId,sourceType,fileName,size:artifact.bytes.length,columns:artifact.columns,preparedAt,rowCount:artifact.rowCount,
    sourceHash:preview.source_hash,fileSha256:artifact.sha256,artifact:file,independentSessionId:fresh.proof.sessionId,
    registeredPipelineReopen:pipeline,statementFreshSourceReproduction:!pipeline,registeredStatementReopen:false,authenticatedNative:false};
   artifacts.push(evidence);await persist(`export-${label}.json`,evidence);
  }
  stage='reconciliation';const after=validateExportsState((await management(EXPORTS_FACTS_SQL,{file:'98-after-response.json'})).value[0]?.export_continuation_facts,
   {before,artifacts,now:now(),window});
  must(gate.snapshot().actualOrdinaryAttempts===24&&gate.snapshot().actualReadOnlyResolutionAttempts===0,'ALL_ORDERED_24_EXPORT_CALLS_REQUIRED');
  const result={kind:'genuine-export-only-successor-result',passed:true,projectId:PROJECT,runtimeBundleSha256:BUNDLE,planSha256,completed,artifacts,...gate.snapshot(),
   originalBaselineHash:after.originalBaseline.sourceHash,priorCompleteHash:after.sourceExcludingOnlyApprovedExportEvents.sourceHash,
   successfulDateCommandsReexecuted:false,oldUncertainCommandReplayed:false,registeredStatementReopen:false,rawWholeHashChanged:true,
   authenticatedNative:false,targetScaleLoad:false,fullFinanceAndCashGatesComplete:false,productionReleaseReady:false};
  await persist('99-result.json',result);return result;
 }catch(error){gate.stop();await closePorts();const pending=writer?.pending();let resolution=null;
  if(pending&&writeAttempted){try{const response=await management(receiptResolutionSql(pending.commandId),{resolutionCommand:pending.commandId,file:'99-pending-original-export-resolution.json'});
    resolution={commandId:pending.commandId,readOnly:true,responseSha256:response.responseSha256,replayPerformed:false};
   }catch{resolution={commandId:pending.commandId,readOnlyResolutionUnavailable:true,replayPerformed:false};}}
  const stop={kind:'genuine-export-only-successor-stop',projectId:PROJECT,stage,failureCode:error.publicCode??'EXPORT_ONLY_SUCCESSOR_STOPPED',completed,
   lastOriginalCommand:pending?{commandId:pending.commandId,actorId:pending.actorId,name:pending.name,writeAttempted}:null,resolution,...gate.snapshot(),
   privateErrorPrinted:false,automaticRetryPerformed:false,successfulDateCommandsReexecuted:false,oldUncertainCommandReplayed:false,liveGateComplete:false};
  try{await persist('99-stop.json',stop);}catch{error.publicCode='EXPORT_STOP_EVIDENCE_UNAVAILABLE';}error.exportStop=stop;throw error;
 }finally{gate.stop();await closePorts();}
}
export async function loadExportsProfile(profileBinding,now=Date.now()){
 must(profileBinding?.path===EXPORTS_PROFILE&&digest(profileBinding.sha256),'PINNED_PUBLIC_EXPORT_PROFILE_REQUIRED');
 const bytes=await readExactRemainingFile(PUBLIC_EVIDENCE_ROOT,profileBinding),profile=JSON.parse(bytes),documents={};
 must(exactKeys(profile.controlBindings,Object.keys(EXPORTS_PROFILE_PATHS)),'EXACT_PUBLIC_EXPORT_PROFILE_FIELDS_REQUIRED');
 for(const [name,file] of Object.entries(EXPORTS_PROFILE_PATHS)){
  const binding=profile.controlBindings[name];must(binding?.path===file&&digest(binding.sha256),'FIXED_PUBLIC_EXPORT_CONTROL_FILE_REQUIRED');
  documents[name]=JSON.parse(await readExactRemainingFile(PUBLIC_EVIDENCE_ROOT,binding));
 }
 return {profile,documents,validation:validateExportsProfile(profile,documents,now)};
}
export async function loadExportsPreserved(){
 const documents={};for(const [name,binding] of Object.entries(EXPORTS_PRESERVED_BINDINGS))documents[name]=JSON.parse(await readExactRemainingFile(EXECUTION_ROOT,binding));
 return {documents,validation:validateExportsConsumed(documents)};
}
export function validateExportsPreparation(plan){
 must(plan?.kind==='source-bound-renewed-export-a6-preparation'&&plan.projectId===PROJECT&&plan.runtimeBundleSha256===BUNDLE
  &&plan.priorConservativeBound===138&&plan.ordinaryAttempts===24&&plan.ordinaryLimit===162&&plan.cumulativeLimit===163&&plan.resolutionAttempts===1
  &&plan.originalConcreteCap===150&&plan.explicitAdditionalCeiling===13&&plan.originalFixtureUtcDay===FINANCE_CALENDAR.fixtureDay
  &&plan.profileBinding?.path===EXPORTS_PROFILE&&digest(plan.profileBinding.sha256)
  &&exactKeys(plan.controlBindings,Object.keys(EXPORTS_PROFILE_PATHS))&&sameFinanceJson(plan.controlBindings.dependency,EXPORTS_DEPENDENCY)
  &&sameFinanceJson(plan.preservedBindings,EXPORTS_PRESERVED_BINDINGS)
  &&sameFinanceJson(plan.permittedOriginalExportCommands,EXPORTS_COMMANDS)&&plan.consolidatedSqlSha256===EXPORTS_SQL_SHA256
  &&plan.finalReviewPath===EXPORTS_FINAL_REVIEW&&plan.liveExecutionAuthorizedByPreparation===false&&plan.personalHumanExactSourceSignatureClaimed===false
  &&plan.exclusiveOncePath===EXPORTS_ONCE&&plan.snapshotRoot===EXECUTION_ROOT&&plan.publicEvidenceRoot===PUBLIC_EVIDENCE_ROOT
  &&plan.maximumRunMs===900000&&plan.maximumSingleRequestMs===45000&&plan.ordinaryDispatchMustReserveInflightAndResolutionMs===90000
  &&plan.successfulDateCommandsReexecuted===false&&plan.transportRetries===0&&plan.unlistedCallsAllowed===0,'EXACT_SOURCE_BOUND_EXPORT_ONLY_PLAN_REQUIRED');
 validateExportsWindow(plan.window);
 must(Array.isArray(plan.sourceBindings)&&plan.sourceBindings.length>68&&new Set(plan.sourceBindings.map(row=>row.path)).size===plan.sourceBindings.length
  &&plan.sourceBindings.every(row=>typeof row.path==='string'&&/^[a-zA-Z0-9_./-]+$/.test(row.path)&&!row.path.includes('..')&&digest(row.sha256))
  &&EXPORTS_SOURCE_PATHS.every(file=>plan.sourceBindings.some(row=>row.path===file))
  &&EXPORTS_A5_SOURCE_BINDINGS.every(binding=>plan.sourceBindings.some(row=>sameFinanceJson(row,binding)))
  &&Array.isArray(plan.publicBindings)&&sameFinanceJson(plan.publicBindings,[plan.profileBinding,...Object.values(plan.controlBindings)])
  &&new Set(plan.publicBindings.map(row=>row.path)).size===9&&plan.privateAdapterPredecessor?.path==='scripts/wave5/run_private_management_installer_20261013_r5.ps1'
  &&digest(plan.privateAdapterPredecessor.sha256),'EXACT_EXPORT_SOURCE_POPULATION_AND_PROFILE_REQUIRED');
 for(const [name,file] of Object.entries(EXPORTS_PROFILE_PATHS))must(plan.controlBindings[name]?.path===file&&digest(plan.controlBindings[name].sha256),
  'FIXED_EXPORT_PREPARATION_PUBLIC_FILE_REQUIRED');
}
export async function verifyExportsPreparation(){
 must(path.resolve(await fs.realpath(root))===path.resolve(EXECUTION_ROOT),'EXACT_FROZEN_EXPORT_EXECUTION_ROOT_REQUIRED');
 const planPath=path.join(root,EXPORTS_PLAN),stat=await fs.lstat(planPath);
 must(stat.isFile()&&!stat.isSymbolicLink()&&stat.size<=1048576&&path.resolve(await fs.realpath(planPath))===path.resolve(planPath),
  'BOUNDED_UNREDIRECTED_EXPORT_PLAN_REQUIRED');
 const bytes=await fs.readFile(planPath),plan=JSON.parse(bytes);validateExportsPreparation(plan);
 const context=await loadExportsProfile(plan.profileBinding),old=await verifyRemainingPreparation(),preserved=await loadExportsPreserved();
 must(old.plan.sourceBindings.length===68,'EXACT_68_PRESERVED_ORIGINAL_BINDINGS_REQUIRED');
 must(sameFinanceJson(plan.controlBindings,context.profile.controlBindings)&&sameFinanceJson(plan.privateAdapterPredecessor,context.profile.privateAdapterPredecessor)
  &&sameFinanceJson(plan.window,context.profile.window),'EXACT_GENERATED_EXPORT_PROFILE_REQUIRED');
 const expected=[...new Set([...old.plan.sourceBindings.map(row=>row.path),...Object.values(EXPORTS_PRESERVED_BINDINGS).map(row=>row.path),
  ...EXPORTS_A5_SOURCE_BINDINGS.map(row=>row.path),...EXPORTS_SOURCE_PATHS])].sort();
 must(sameFinanceJson(plan.sourceBindings.map(row=>row.path).sort(),expected),'NO_ADDED_OR_REMOVED_EXPORT_DEPENDENCY_BINDING_REQUIRED');
 for(const binding of [...old.plan.sourceBindings,...Object.values(EXPORTS_PRESERVED_BINDINGS),...EXPORTS_A5_SOURCE_BINDINGS])
  must(plan.sourceBindings.some(row=>sameFinanceJson(row,binding)),'ALL_ORIGINAL_EXPORT_DEPENDENCY_BINDINGS_REQUIRED');
 for(const binding of context.documents.sourcePolicy.exportSourceBindings)
  must(plan.sourceBindings.some(row=>sameFinanceJson(row,binding)),'EXACT_INDEPENDENTLY_REVIEWED_A6_SOURCES_REQUIRED');
 for(const binding of plan.sourceBindings)await readExactRemainingFile(EXECUTION_ROOT,binding);
 for(const binding of plan.publicBindings)await readExactRemainingFile(PUBLIC_EVIDENCE_ROOT,binding);
 return {plan,planSha256:hashBytes(bytes),profile:context.profile,controls:context.documents,preserved:preserved.documents};
}
export function validateExportsFinalReview(review,{plan,planSha256},now=Date.now()){
 validateExportsPreparation(plan);validateExportsTime(now,{now,window:plan.window});
 must(review?.kind==='independent-renewed-export-a6-final-operation-review'&&review.technicalDecision==='approve'&&review.executionPermitted===true
  &&review.projectId===PROJECT&&review.runtimeBundleSha256===BUNDLE&&sameFinanceJson(review.generatedPlan,{path:EXPORTS_PLAN,sha256:planSha256})
  &&sameFinanceJson(review.sourceBindings,plan.sourceBindings)&&sameFinanceJson(review.executionProfileBinding,plan.profileBinding)
  &&sameFinanceJson(review.controlBindings,plan.controlBindings)&&sameFinanceJson(review.window,plan.window)
  &&review.privateAdapter?.beforeSha256===plan.privateAdapterPredecessor.sha256&&digest(review.privateAdapter.afterSha256)
  &&review.priorConservativeBound===138&&review.ordinaryLimit===162&&review.cumulativeLimit===163&&review.ordinaryAttempts===24&&review.resolutionAttempts===1
  &&sameFinanceJson(review.permittedOriginalExportCommands,EXPORTS_COMMANDS)&&review.originalFixtureUtcDay===FINANCE_CALENDAR.fixtureDay
  &&review.directHumanDecisionVerified===true&&review.actualTwoRowReadbackVerified===true&&review.personalHumanExactSourceSignatureClaimed===false,
  'EXACT_INDEPENDENT_EXPORT_FINAL_OPERATION_REVIEW_REQUIRED');
 return review;
}
export async function writeExportsEvidence(directory,file,value,{evidenceRoot=root}={}){
 const target=path.resolve(evidenceRoot,directory,file);
 must(target.startsWith(path.resolve(evidenceRoot)+path.sep),'EXPORT_EVIDENCE_OUTSIDE_ROOT');
 const bytes=Buffer.isBuffer(value)?value:Buffer.from(JSON.stringify(value,null,2)+'\n');
 const handle=await fs.open(target,'wx');try{await handle.writeFile(bytes);await handle.sync();}finally{await handle.close();}
 return {path:path.posix.join(directory,file),sha256:hashBytes(bytes),bytes:bytes.length};
}
// Public-only entry point for the private adapter BEFORE it unseals anything.
// Injectable read-only ports allow bounded controlled tests. This function has
// no stdin, private-key, intent, filesystem-write, or network operation.
export async function preflightExportsOperation({finalReviewSha256,verifyPreparation=verifyExportsPreparation,
 readPublic=readExactRemainingFile,now=Date.now}={}){
 must(digest(finalReviewSha256)&&typeof verifyPreparation==='function'&&typeof readPublic==='function'&&typeof now==='function',
  'PINNED_PUBLIC_EXPORT_FINAL_REVIEW_SHA_REQUIRED');
 const verified=await verifyPreparation(),reviewBytes=await readPublic(PUBLIC_EVIDENCE_ROOT,{path:EXPORTS_FINAL_REVIEW,sha256:finalReviewSha256});
 const finalReview=validateExportsFinalReview(JSON.parse(reviewBytes),verified,now());
 await readPublic(PUBLIC_EVIDENCE_ROOT,{path:verified.plan.privateAdapterPredecessor.path,sha256:finalReview.privateAdapter.afterSha256});
 validateExportsTime(now(),{now:now(),window:verified.plan.window});
 return {verified,finalReview,publicResult:{passed:true,networkCalls:0,privateInputsRead:false,planSha256:verified.planSha256,finalReviewSha256}};
}
async function main(){
 const mode=process.argv[2]??'--validate';must(['--validate','--preflight','--execute'].includes(mode)
  &&process.argv.length===(mode==='--validate'?3:4),'FIXED_EXPORT_SUCCESSOR_MODE_REQUIRED');
 if(mode==='--validate'){
  const verified=await verifyExportsPreparation();
  process.stdout.write(JSON.stringify({passed:true,networkCalls:0,privateInputsRead:false,planSha256:verified.planSha256,
   priorConservativeBound:138,maximumCumulativeAttemptLimit:163,sourceBindings:verified.plan.sourceBindings.length})+'\n');return;
 }
 const {verified,finalReview,publicResult}=await preflightExportsOperation({finalReviewSha256:process.argv[3]});
 if(mode==='--preflight'){process.stdout.write(JSON.stringify(publicResult)+'\n');return;}
 let incoming='',config,key,transport,timer;const abort=new AbortController();
 try{
  for await(const chunk of process.stdin){incoming+=chunk;must(incoming.length<=16000,'BOUNDED_PRIVATE_EXPORT_INPUT_REQUIRED');}
  config=JSON.parse(incoming);incoming='';must(config&&typeof config==='object'&&!Array.isArray(config),'EXACT_REVIEWED_PRIVATE_EXPORT_CONTEXT_REQUIRED');
  must(config.projectId===PROJECT&&config.bundleSha256===BUNDLE&&config.privateDirectory===verified.controls.metadata.privateFolder,'EXACT_REVIEWED_PRIVATE_EXPORT_CONTEXT_REQUIRED');
  const reverified=await verifyExportsPreparation();
  must(reverified.planSha256===verified.planSha256,'EXPORT_PUBLIC_INPUT_CHANGED_BEFORE_UNSEAL');
  await readExactRemainingFile(PUBLIC_EVIDENCE_ROOT,{path:EXPORTS_FINAL_REVIEW,sha256:process.argv[3]});
  await readExactRemainingFile(PUBLIC_EVIDENCE_ROOT,{path:verified.plan.privateAdapterPredecessor.path,sha256:finalReview.privateAdapter.afterSha256});
  const executionStartedAt=Date.now();validateExportsTime(executionStartedAt,{window:verified.plan.window});must(sameFinanceJson(config.exportWindow,verified.plan.window),'EXACT_PRIVATE_ADAPTER_WINDOW_REQUIRED');key=runtimeSealKey(config.encryptionKey);
  timer=setTimeout(()=>abort.abort(),Math.min(executionStartedAt+900000,utcMillis(verified.plan.window.expiresAt))-Date.now());
  const directory=base+'genuine-finance-exports-20261014-r5-a6-'+Date.now()+'/';await fs.mkdir(path.join(root,directory));
  await writeExportsEvidence('',EXPORTS_ONCE,{kind:'exclusive-export-only-successor-intent',projectId:PROJECT,runtimeBundleSha256:BUNDLE,
   generatedPlanSha256:verified.planSha256,directory,startedAt:new Date(executionStartedAt).toISOString(),priorConservativeBound:138,cumulativeLimit:163,
   permittedOriginalExportCommands:EXPORTS_COMMANDS,finalOperationReviewSha256:process.argv[3],successfulDateCommandsReexecuted:false,oldUncertainCommandReplayed:false});
  const rawManagement=createManagementTransport(config.ownerToken,{timeoutMs:45000}),files=await createExclusiveExportFiles(path.join(root,'dist'));
  const ports={management:query=>rawManagement('POST','/database/query',{query,read_only:true}),
   async keyReader(){const response=await createPrivateKeyReader(config.ownerToken,{timeoutMs:45000})();const keys=selectExistingLegacyKeys(response.value);
    transport=createFinanceHttpsTransport({apiKey:keys.anon});keys.serviceRole=null;keys.anon=null;},
   session:async(label,context)=>{
    const sessionTransport={connection:()=>transport.connection(),send:(handle,route,options={})=>route.startsWith('/auth/v1/')?
     context.send(route,options,()=>transport.send(handle,route,{...options,signal:abort.signal})):transport.send(handle,route,{...options,signal:abort.signal})};
    return existingActorSession({root,config,key,label:'proposer',transport:sessionTransport,management:context.management,
     save:async(file,value)=>{const receipt=await writeExportsEvidence(directory,file,value);must(digest(receipt.sha256)&&typeof receipt.path==='string',
      'ACKNOWLEDGED_GENUINE_EXPORT_SESSION_PROOF_REQUIRED');return receipt;},file:'session-'+label+'.json'});
   },appendPrivate:(kind,value)=>appendRuntimeSecret(config.privateDirectory,key,kind,value),persist:(file,value)=>writeExportsEvidence(directory,file,value),
   writeFile:files.write,readFile:files.read,close:async()=>{transport?.close();}};
  const result=await runExportsContinuation({ports,planSha256:verified.planSha256,savedStatement:verified.preserved.statement,signal:abort.signal,startedAt:executionStartedAt,
   window:verified.plan.window});
  process.stdout.write(JSON.stringify({passed:true,ordinaryAttempts:result.actualOrdinaryAttempts,totalWorkflowRequestBound:result.totalWorkflowRequestBound,
   evidencePath:directory+'99-result.json',authenticatedNative:false,fullFinanceAndCashGatesComplete:false})+'\n');
 }finally{incoming='';clearTimeout(timer);abort.abort();transport?.close();key?.fill(0);
  if(config&&typeof config==='object'){config.ownerToken='';config.encryptionKey='';}}
}
if(process.argv[1]&&path.resolve(process.argv[1])===fileURLToPath(import.meta.url))main().catch(error=>{
 process.stderr.write(JSON.stringify({failureCode:error.publicCode??'EXPORT_ONLY_SUCCESSOR_STOPPED',privateErrorOrCredentialPrinted:false,automaticRetryPerformed:false})+'\n');
 process.exitCode=1;
});
