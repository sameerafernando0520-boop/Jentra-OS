// Controlled in-memory fixtures only. No owner decision, metadata, intent,
// runtime proof, private credential, HTTP request, or application row is created.
import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs/promises';
import {createHash} from 'node:crypto';
import {EventEmitter} from 'node:events';
import * as R from '../../../../tools/wave5/renew_runtime_authority_20261015_r5_a1.mjs';
const root=new URL('../../../../',import.meta.url);
const sha=x=>createHash('sha256').update(x).digest('hex');
const bytes=x=>Buffer.isBuffer(x)?x:Buffer.from(JSON.stringify(x,null,2)+'\n');
const clone=x=>structuredClone(x);
const T=Date.parse('2026-10-16T20:00:00.000Z');
const iso=x=>new Date(x).toISOString();
const H='a'.repeat(64),J='b'.repeat(64);
const pinned=new Map();
for(const item of [...Object.entries(R.STATIC_HASHES).map(([name,sha256])=>({path:R.CONTROL_PATHS[name],sha256})),...Object.values(R.SQL_BINDINGS),...R.CURRENT_EVIDENCE,R.OWNER_REFRESH_HELPER]){
 const data=await fs.readFile(new URL(item.path,root));assert.equal(sha(data),item.sha256);pinned.set(item.path,data);
}
const readSource=await fs.readFile(new URL(R.SOURCE,root)),testSource=await fs.readFile(new URL(R.TEST,root));
const readSql=pinned.get(R.SQL_BINDINGS.read.path).toString(),writeTemplate=pinned.get(R.SQL_BINDINGS.write.path).toString();
const parse=file=>JSON.parse(pinned.get(file));
function fixture(time=T){
 const files=new Map(pinned),sourceBindings=[{path:R.SOURCE,sha256:sha(readSource)},{path:R.TEST,sha256:sha(testSource)}];
 files.set(R.SOURCE,readSource);files.set(R.TEST,testSource);
 const controls=Object.fromEntries(Object.keys(R.STATIC_HASHES).map(key=>[key,parse(R.CONTROL_PATHS[key])]));
 const binding=(name,value)=>{const data=bytes(value);files.set(R.CONTROL_PATHS[name],data);return {path:R.CONTROL_PATHS[name],sha256:sha(data)};};
 const controlBindings=Object.fromEntries(Object.entries(R.STATIC_HASHES).map(([key,sha256])=>[key,{path:R.CONTROL_PATHS[key],sha256}]));
 controls.sourcePolicy={kind:'source-only-export-a7-renewal-policy',projectId:R.PROJECT,runtimeId:R.RUNTIME,runtimeBundleSha256:R.BUNDLE,
  sourceImplementationOnly:true,liveExecutionAuthorized:false,budget:clone(R.BUDGET),maximumWindowMs:7200000,windowMode:'server-clock-at-application',
  onlyTwoExpiryFieldsMayChange:true,schedulesMustRemainPaused:true,originalWindow:clone(R.OLD),renewalOperationBundleSha256:H,
  renewalControllerSourceBindings:clone(sourceBindings),renewalSqlBindings:clone(R.SQL_BINDINGS),currentChargeBinding:clone(controlBindings.currentCharge),
  renewalProposalBinding:clone(controlBindings.proposal),renewalSourceRepairBinding:clone(controlBindings.sourceRepair)};
 controlBindings.sourcePolicy=binding('sourcePolicy',controls.sourcePolicy);
 controls.policyReview={kind:'independent-export-a7-policy-review',passed:true,sourceOnly:true,liveExecutionAuthorized:false,
  policyBinding:clone(controlBindings.sourcePolicy),budget:clone(R.BUDGET),renewalOperationBundleSha256:H,currentChargeBinding:clone(controlBindings.currentCharge),
  renewalControllerSourceBindings:clone(sourceBindings),renewalSqlBindings:clone(R.SQL_BINDINGS)};
 controlBindings.policyReview=binding('policyReview',controls.policyReview);
 controls.ownerDecision={kind:'direct-human-runtime-renewal-and-export-a7-decision',approved:true,approvalSource:'direct-user-reply',
  exactReply:R.OWNER_REPLY,questionItemId:'CONTROLLED-IN-MEMORY-QUESTION-ONLY',projectId:R.PROJECT,runtimeId:R.RUNTIME,runtimeBundleSha256:R.BUNDLE,
  budget:clone(R.BUDGET),maximumWindowMs:7200000,onlyTwoExpiryFieldsMayChange:true,schedulesMustRemainPaused:true,productionAuthorized:false,
  realBillingAuthorized:false,operationBundleSha256:H,sourcePolicyBinding:clone(controlBindings.sourcePolicy),
  independentReviewBinding:clone(controlBindings.policyReview),decidedAt:iso(time-120000)};
 controlBindings.ownerDecision=binding('ownerDecision',controls.ownerDecision);
 controls.refresh={kind:'actual-private-owner-scope-refresh',projectId:R.PROJECT,organizationId:R.ORGANIZATION,actualStatus:'ACTIVE_HEALTHY',readOnlyOwnerApiCalls:1,
  actualVerifiedAt:iso(time-60000),helperSha256:R.OWNER_REFRESH_HELPER.sha256,databaseWrites:0,authWrites:0,settingsChanges:0};
 controlBindings.refresh=binding('refresh',controls.refresh);
 controls.metadata={kind:'wave5-private-owner-input-metadata',projectId:R.PROJECT,runtimeBundleSha256:R.BUNDLE,
  metadataFilename:'metadata-renewed-a10.json',containsPlaintextCredential:false,
  reuseAuthorizationQuestionId:'["request_user_input_async","call_637ea7df9a28457388be21396163da04",0]',
  refreshEvidence:clone(controlBindings.refresh),createdAt:iso(time-60000),expiresAt:iso(time+7140000),helperSha256:R.OWNER_REFRESH_HELPER.sha256};
 controlBindings.metadata=binding('metadata',controls.metadata);
 controls.staticReview={kind:'independent-runtime-renewal-controller-source-review',passed:true,sourceOnly:true,executionPermitted:false,
  sourceBindings:clone(sourceBindings),sqlBindings:clone(R.SQL_BINDINGS),proposalBinding:clone(controlBindings.proposal),sourceRepairBinding:clone(controlBindings.sourceRepair)};
 controlBindings.staticReview=binding('staticReview',controls.staticReview);
 const plan={kind:'source-bound-two-row-runtime-renewal-plan',projectId:R.PROJECT,runtimeId:R.RUNTIME,runtimeBundleSha256:R.BUNDLE,
  maximumManagementAttempts:3,recordedPrior:137,actualPriorAfterOwnerRefresh:138,cumulativeAfterRenewal:141,maximumRequestMs:45000,
  maximumRunMs:900000,ordinaryReserveMs:90000,maximumWindowMinutes:120,automaticRetries:0,exclusiveOncePath:R.ONCE,finalReviewPath:R.REVIEW,
  readbackPath:R.READBACK,liveExecutionAuthorizedByPreparation:false,sqlBindings:clone(R.SQL_BINDINGS),controlBindings,sourceBindings,
  otherCallsSinceDependency:3,otherCallsSinceCurrentCharge:0,window:{notBefore:controls.metadata.createdAt,expiresAt:controls.metadata.expiresAt}};
 plan.publicBindings=[...Object.values(controlBindings),...Object.values(R.SQL_BINDINGS),...R.CURRENT_EVIDENCE,R.OWNER_REFRESH_HELPER].sort((a,b)=>a.path.localeCompare(b.path));
 const planData=bytes(plan),planSha256=sha(planData);files.set(R.PLAN,planData);
 const adapterBytes=Buffer.from('# Controlled adapter bytes, never executed.');files.set(R.PRIVATE_ADAPTER,adapterBytes);
 const review={kind:'independent-runtime-renewal-final-operation-review',technicalDecision:'approve',executionPermitted:true,
  projectId:R.PROJECT,runtimeId:R.RUNTIME,runtimeBundleSha256:R.BUNDLE,generatedPlan:{path:R.PLAN,sha256:planSha256},
  controlBindings:clone(controlBindings),sourceBindings:clone(sourceBindings),publicBindings:clone(plan.publicBindings),sqlBindings:clone(R.SQL_BINDINGS),window:clone(plan.window),
  privateAdapter:{path:R.PRIVATE_ADAPTER,afterSha256:sha(adapterBytes)},directHumanDecisionVerified:true,maximumManagementAttempts:3,cumulativeAfterRenewal:141};
 const reviewData=bytes(review),finalReviewSha256=sha(reviewData);files.set(R.REVIEW,reviewData);
 const checked={plan,review,controls,planSha256,finalReviewSha256,readSql,writeTemplate,currentEvidence:R.CURRENT_EVIDENCE.map(x=>parse(x.path))};
 checked.publicResult={passed:true,networkCalls:0,privateInputsRead:false,planSha256,finalReviewSha256};
 const reads=[];
 const readPublic=async item=>{reads.push(item.path);const data=files.get(item.path);assert.ok(data,'Controlled public file present: '+item.path);assert.equal(sha(data),item.sha256);return data;};
 return {checked,files,readPublic,reads};
}
function snapshot(checked,time=T,renewed=false){
 const {proposal,sourceRepair,dependency}=checked.controls;
 const expires=checked.controls.metadata.expiresAt;
 return {timeZone:'UTC',observedAt:iso(time),migrationCount:115,apiFunctionCount:363,containsUnexpected24HourFunctionCeiling:false,
  scopeCount:1,scopeAllowed:renewed,authority:{runtimeId:R.RUNTIME,enabled:true,issuedAt:R.OLD.edgeIssuedAt,expiresAt:renewed?expires:R.OLD.edgeExpiresAt,
   nonWindowHash:R.OLD.edgeNonWindowHash,jobIds:[4,5,6]},scope:{...R.SCOPE,enabled:true,issuedAt:R.OLD.scopeIssuedAt,expiresAt:renewed?expires:R.OLD.scopeExpiresAt},
  scopeNonWindowHash:R.OLD.scopeNonWindowHash,financeCounters:clone(sourceRepair.financeBaseline),effectCounters:clone(sourceRepair.effectBaseline),
  ownJobs:clone(proposal.recordedState.pausedJobs),outsideJobHash:'4f53cda18c2baa0c0354bb5f9a3ecbe5ed12ab4d8e11ba873c2f11161202b945',
  guardFunctionBindings:clone(proposal.exactGuardFunctionBindings),keyReferences:clone(dependency.snapshot.keyReferences),ticks:0,modelInvocations:0,recordedCronRuns:24,
  billingWindow:[{status:'trialing',trialEndsAt:'2026-10-20T08:13:04.144135+00:00',currentPeriodEndsAt:null}],
  tableContracts:[['intelligence_control.edge_authorities','edgeAuthority'],['intelligence_control.runtime_worker_scopes','workerScope']].map(([name,key])=>
   ({name,rls:true,forceRls:true,userTriggers:0,columns:clone(proposal.schemaContracts[key]),constraints:['CONTROLLED_CONSTRAINT_ONE','CONTROLLED_CONSTRAINT_TWO']}))};
}
function harness(options={}){
 const f=fixture(options.time??T),events=[],evidence=new Map();let time=options.time??T,closed=0,published=null;
 const ack=(path,value)=>({path,sha256:sha(bytes(value))});
 const persist=async(file,value)=>{events.push('persist:'+file);if(options.persist)await options.persist(file,value);evidence.set(file,Buffer.isBuffer(value)?Buffer.from(value):clone(value));return ack('docs/verification/wave5/root-runtime-renewal-20261015/controlled-memory/'+file,value);};
 const once=async value=>{events.push('once');if(options.once)await options.once(value);return ack(R.ONCE,value);};
 const publishReadback=async value=>{events.push('publish');if(options.publish)await options.publish(value);published=clone(value);return ack(R.READBACK,value);};
 const transport=async request=>{
  events.push('dispatch:'+request.phase);time+=1000;
  const defaultRow=request.phase==='two-row-expiry-write'?{renewal_application:{runtimeId:R.RUNTIME,appliedAt:iso(time),expiresAt:f.checked.controls.metadata.expiresAt,
   affectedRows:2,applicationTimestampProvenance:'server-post-commit-observation'}}:{renewal_snapshot:snapshot(f.checked,time,request.phase==='readback')};
  const response={status:200,raw:Buffer.from(JSON.stringify([defaultRow]))};
  return options.transport?options.transport({request,response,defaultRow,time,setTime:v=>time=v,checked:f.checked}):response;
 };
 const run=()=>R.runRenewal({checked:f.checked,transport,persist,once,publishReadback,close:async()=>{events.push('close');closed++;},now:()=>time,
  portTimeoutMs:options.portTimeoutMs??45000,signal:options.signal});
 return {...f,run,events,evidence,get closed(){return closed;},get published(){return published;},setTime:v=>time=v};
}
test('controlled full contract accepts exact137/141/166 accounting',()=>{const f=fixture();assert.equal(R.validateContract(f.checked,T),f.checked.plan);});
test('historical134 dependency and old proposal caps remain unchanged',()=>{const f=fixture();assert.equal(f.checked.controls.dependency.conservativeContinuationAccounting.cumulativeChargedCalls,134);assert.equal(f.checked.controls.proposal.budget.priorAtExports,138);assert.equal(f.checked.controls.proposal.budget.overallMaximum,171);assert.equal(R.BUDGET.prior,141);});
for(const [name,mutate,code] of [
 ['old recorded budget',c=>c.plan.recordedPrior=134,'EXACT_THREE_CALL'],['old after-owner budget',c=>c.plan.actualPriorAfterOwnerRefresh=135,'EXACT_THREE_CALL'],
 ['old renewal cap',c=>c.plan.cumulativeAfterRenewal=138,'EXACT_THREE_CALL'],['extra call since baseline',c=>c.plan.otherCallsSinceCurrentCharge=1,'PRESERVED_RECORDED134'],
 ['omitted new calls',c=>c.plan.otherCallsSinceDependency=0,'PRESERVED_RECORDED134'],['false human approval',c=>c.controls.ownerDecision.approved=false,'DIRECT_EXACT'],
 ['old human reply',c=>c.controls.ownerDecision.exactReply='Approve the exact two-row runtime renewal and export a6 continuation','DIRECT_EXACT'],
 ['indirect human source',c=>c.controls.ownerDecision.approvalSource='agent-generated','DIRECT_EXACT'],['future human decision',c=>c.controls.ownerDecision.decidedAt=iso(T+1),'DIRECT_EXACT'],
 ['policy scope changed',c=>c.controls.sourcePolicy.onlyTwoExpiryFieldsMayChange=false,'EXACT_REVIEWED'],['cap drift',c=>c.controls.sourcePolicy.budget.total=174,'EXACT_REVIEWED'],
 ['false policy review',c=>c.controls.policyReview.passed=false,'INDEPENDENT_RENEWAL_POLICY'],['false final review',c=>c.review.executionPermitted=false,'EXACT_FINAL'],
 ['wrong plan hash',c=>c.review.generatedPlan.sha256=H,'EXACT_FINAL'],['wrong adapter path',c=>c.review.privateAdapter.path='scripts/wave5/other.ps1','EXACT_FINAL'],
 ['missing public closure',c=>c.plan.publicBindings.pop(),'EXACT_RENEWAL_PUBLIC_BINDING_CLOSURE'],
 ['extra public closure',c=>c.plan.publicBindings.push({path:'docs/verification/wave5/extra.json',sha256:H}),'EXACT_RENEWAL_PUBLIC_BINDING_CLOSURE'],
 ['changed public closure',c=>c.plan.publicBindings[0]={...c.plan.publicBindings[0],sha256:H},'EXACT_RENEWAL_PUBLIC_BINDING_CLOSURE'],
 ['missing current raw evidence',c=>c.currentEvidence.pop(),'SIX_PINNED'],['failed advisor result',c=>c.currentEvidence[3].result.status='rejected','ACTUAL_SUCCESSFUL'],
 ['invented prior ledger',c=>c.controls.currentCharge.actualChargedPrior=134,'EXACT_CURRENT137'],['future calls mislabeled actual',c=>c.controls.currentCharge.futureCallsObserved=true,'EXACT_CURRENT137'],
 ['old readback path',c=>c.plan.readbackPath='docs/verification/wave5/runtime-renewal-two-row-readback-20261014-r5-a1.json','EXACT_THREE_CALL'],
 ['metadata not actual A10 filename',c=>c.controls.metadata.metadataFilename='metadata.json','ACTUAL_FRESH_A10'],
 ['refresh attempts reset',c=>c.controls.refresh.readOnlyOwnerApiCalls=0,'ACTUAL_ONE_GET'],['missing static review',c=>c.controls.staticReview.passed=false,'INDEPENDENT_RENEWAL_CONTROLLER']
])test('contract rejects '+name,()=>{const {checked}=fixture();mutate(checked);assert.throws(()=>R.validateContract(checked,T),new RegExp(code));});
for(const [name,value] of [['stale',iso(T-1)],['unbounded',iso(T+7200000)],['invalid day','2026-02-30T20:00:00Z'],['offset','2026-10-16T22:00:00+02:00']])
 test('window rejects '+name,()=>{assert.throws(()=>R.validateWindow({notBefore:iso(T-60000),expiresAt:value},T));});
test('window rejects not-before in future',()=>assert.throws(()=>R.validateWindow({notBefore:iso(T+1),expiresAt:iso(T+7000000)},T)));
test('window rejects insufficient90second reserve',()=>assert.throws(()=>R.validateWindow({notBefore:iso(T-60000),expiresAt:iso(T+90000)},T,90000)));
test('public preflight verifies exact closure and returns only five safe fields',async()=>{const f=fixture();const checked=await R.preflightRenewalOperation({finalReviewSha256:f.checked.finalReviewSha256,readPublic:f.readPublic,now:()=>T});assert.deepEqual(checked.publicResult,f.checked.publicResult);assert.deepEqual(Object.keys(checked.publicResult).sort(),['passed','networkCalls','privateInputsRead','planSha256','finalReviewSha256'].sort());for(const item of f.checked.plan.publicBindings)assert.ok(f.reads.includes(item.path));assert.ok(f.reads.includes(R.PRIVATE_ADAPTER));});
test('public preflight rejects changed public bytes',async()=>{const f=fixture();f.files.set(R.CURRENT_EVIDENCE[1].path,Buffer.from('{}'));await assert.rejects(R.preflightRenewalOperation({finalReviewSha256:f.checked.finalReviewSha256,readPublic:f.readPublic,now:()=>T}));});
test('public preflight rejects changed adapter bytes',async()=>{const f=fixture();f.files.set(R.PRIVATE_ADAPTER,Buffer.from('changed'));await assert.rejects(R.preflightRenewalOperation({finalReviewSha256:f.checked.finalReviewSha256,readPublic:f.readPublic,now:()=>T}));});
test('public CLI preflight reads no stdin, network, or once intent',async()=>{const f=fixture();let touched=0,output='';const stdin={[Symbol.asyncIterator](){touched++;throw Error('PRIVATE_INPUT_FORBIDDEN');}};await R.main(['--preflight',f.checked.finalReviewSha256],{stdin,stdout:{write:s=>output+=s},now:()=>T,preflight:args=>R.preflightRenewalOperation({...args,readPublic:f.readPublic}),run:()=>{throw Error('INTENT_FORBIDDEN');},transportFactory:()=>{throw Error('NETWORK_FORBIDDEN');}});assert.equal(touched,0);assert.deepEqual(JSON.parse(output),f.checked.publicResult);});
test('invalid final review fails before stdin or transport',async()=>{let touched=0;await assert.rejects(R.main(['--execute',H],{stdin:{[Symbol.asyncIterator](){touched++;}},preflight:async()=>{throw Error('CONTROLLED_FINAL_REVIEW_FAILURE');},transportFactory:()=>{touched++;}}));assert.equal(touched,0);});
test('execute rechecks public files after stdin and before transport or intent',async()=>{const f=fixture();let passes=0,transport=0;const stdin=(async function*(){yield JSON.stringify({projectId:R.PROJECT,bundleSha256:R.BUNDLE,ownerToken:'CONTROLLED_NOT_A_CREDENTIAL'});})();await assert.rejects(R.main(['--execute',H],{stdin,preflight:async()=>{if(++passes===2)throw Error('CONTROLLED_SECOND_PREFLIGHT_FAILURE');return f.checked;},transportFactory:()=>{transport++;}}),/SECOND_PREFLIGHT/);assert.equal(passes,2);assert.equal(transport,0);});
test('execute rejects second preflight plan replacement before transport',async()=>{const f=fixture();let passes=0,transport=0;await assert.rejects(R.main(['--execute',H],{stdin:(async function*(){yield JSON.stringify({projectId:R.PROJECT,bundleSha256:R.BUNDLE,ownerToken:'CONTROLLED_NOT_A_CREDENTIAL'});})(),preflight:async()=>({...f.checked,planSha256:++passes===1?H:J}),transportFactory:()=>{transport++;}}),/PUBLIC_INPUT_CHANGED/);assert.equal(transport,0);});
test('exact SQL rendering changes only five null slots',()=>{const f=fixture();const rendered=R.renderRenewalSql(f.checked,snapshot(f.checked),T);assert.equal(R.assertRenderedQuery(rendered.query,writeTemplate),true);assert.equal(rendered.substitutions.length,5);assert.equal(rendered.expiresAt,f.checked.controls.metadata.expiresAt);assert.equal(sha(writeTemplate),R.SQL_BINDINGS.write.sha256);});
test('transport rejects original null template',()=>assert.throws(()=>R.assertRenderedQuery(writeTemplate,writeTemplate),/FIVE_SUBSTITUTED/));
test('transport rejects valid substitution plus extra SQL',()=>{const f=fixture();const r=R.renderRenewalSql(f.checked,snapshot(f.checked),T);assert.throws(()=>R.assertRenderedQuery(r.query+'select 1;',writeTemplate),/FIVE_SLOT/);});
test('transport rejects date literal outside strict UTC',()=>{const f=fixture();const r=R.renderRenewalSql(f.checked,snapshot(f.checked),T);assert.throws(()=>R.assertRenderedQuery(r.query.replace(f.checked.controls.metadata.expiresAt,'2026-99-99T00:00:00Z'),writeTemplate),/VALID_UTC/);});
for(const [name,mutate] of [
 ['scope count',x=>x.scopeCount=2],['one row only expiry',x=>x.scope.expiresAt=iso(T+60000)],['future server timestamp',x=>x.observedAt=iso(T+1)],
 ['stale server timestamp',x=>x.observedAt=iso(T-45001)],['issued timestamp',x=>x.scope.issuedAt=iso(T)],['nonwindow hash',x=>x.authority.nonWindowHash=H],
 ['schedule resumed',x=>x.ownJobs[0].active=true],['outside job change',x=>x.outsideJobHash=H],['function body',x=>x.guardFunctionBindings[0].sourceHash=H],
 ['key binding',x=>x.keyReferences[0].secretId='changed'],['effects',x=>x.effectCounters.outcomes=1],['finance',x=>x.financeCounters.exports=1],
 ['schema column',x=>x.tableContracts[0].columns.pop()],['user trigger',x=>x.tableContracts[0].userTriggers=1],['RLS',x=>x.tableContracts[0].forceRls=false],
 ['billing',x=>x.billingWindow[0].status='active'],['historical run reset',x=>x.recordedCronRuns=0],['24h ceiling',x=>x.containsUnexpected24HourFunctionCeiling=true]
])test('snapshot rejects '+name,()=>{const f=fixture(),s=snapshot(f.checked);mutate(s);assert.throws(()=>R.validateSnapshot(s,f.checked,{now:T}));});
test('three controlled calls charge139/140/141 before dispatch and publish server provenance',async()=>{const h=harness();const result=await h.run();assert.equal(result.actualCumulativeChargedCalls,141);assert.equal(result.preflightObservedAt,iso(T+1000));assert.equal(result.appliedAt,iso(T+2000));assert.equal(result.observedAt,iso(T+3000));assert.equal(result.applicationTimestampProvenance,'server-post-commit-observation');assert.deepEqual(result.controlCallAccounting.receipts.map(x=>x.ordinal),[139,140,141]);assert.equal(h.closed,1);assert.equal(h.published.kind,'actual-two-row-runtime-expiry-renewal-readback');for(const [i,phase] of ['preflight','two-row-expiry-write','readback'].entries())assert.ok(h.events.indexOf('persist:'+`${139+i}-${phase}-attempt.json`)<h.events.indexOf('dispatch:'+phase));assert.equal(result.actualExports,0);assert.equal(result.requirementsAccepted,0);});
test('controlled renewal crosses UTC midnight without replaying original date',async()=>{const h=harness({time:Date.parse('2026-10-16T23:59:58Z')});const result=await h.run();assert.equal(result.preflightObservedAt.slice(0,10),'2026-10-16');assert.equal(result.appliedAt.slice(0,10),'2026-10-17');assert.equal(result.scope.issuedAt,R.OLD.scopeIssuedAt);});
test('raw HTTP error evidence is acknowledged before status validation',async()=>{const h=harness({transport:({response})=>({...response,status:503,raw:Buffer.from('CONTROLLED_ERROR_BODY')})});await assert.rejects(h.run());assert.ok(h.evidence.has('139-preflight-response.bin'));assert.ok(h.events.indexOf('persist:139-preflight-response.json')<h.events.indexOf('persist:139-preflight-failure.json'));assert.equal(h.evidence.get('99-stop.json').cumulativeChargedCalls,139);assert.equal(h.published,null);});
test('invalid JSON raw bytes are durable before parse failure',async()=>{const h=harness({transport:({response})=>({...response,raw:Buffer.from('{invalid controlled json')})});await assert.rejects(h.run());assert.ok(h.evidence.has('139-preflight-response.bin'));assert.equal(h.evidence.get('99-stop.json').actualOrConservativelyChargedAttempts,1);});
test('preflight transport failure is charged and never retried',async()=>{const h=harness({transport:()=>{throw Error('CONTROLLED_TRANSPORT_ERROR');}});await assert.rejects(h.run());assert.deepEqual(h.events.filter(x=>x.startsWith('dispatch:')),['dispatch:preflight']);assert.equal(h.evidence.get('99-stop.json').cumulativeChargedCalls,139);});
test('uncertain write gets exactly one readback and cannot fabricate appliedAt',async()=>{const h=harness({transport:({request,response})=>{if(request.phase==='two-row-expiry-write')throw Error('CONTROLLED_WRITE_UNCERTAIN');return response;}});await assert.rejects(h.run());const stop=h.evidence.get('99-stop.json');assert.equal(stop.cumulativeChargedCalls,141);assert.equal(stop.failedAttempts,1);assert.equal(stop.resolution.renewedRowsObserved,true);assert.equal(stop.resolution.applicationTimestampRecovered,false);assert.equal(stop.a7ContinuationAllowed,false);assert.equal(stop.applicationTimestampFabricated,false);assert.equal(h.published,null);assert.equal(h.events.filter(x=>x==='dispatch:two-row-expiry-write').length,1);});
test('write raw evidence failure resolves once and never publishes',async()=>{const h=harness({persist:file=>{if(file==='140-two-row-expiry-write-response.bin')throw Error('CONTROLLED_DURABLE_FAILURE');}});await assert.rejects(h.run());assert.equal(h.events.filter(x=>x.startsWith('dispatch:')).length,3);assert.equal(h.published,null);});
test('attempt evidence failure prevents dispatch while retaining conservative charge',async()=>{const h=harness({persist:file=>{if(file==='139-preflight-attempt.json')throw Error('CONTROLLED_DURABLE_FAILURE');}});await assert.rejects(h.run());assert.equal(h.events.filter(x=>x.startsWith('dispatch:')).length,0);assert.equal(h.evidence.get('99-stop.json').cumulativeChargedCalls,139);});
for(const [name,mutate] of [
 ['missing application',row=>delete row.renewal_application],['client provenance',row=>row.renewal_application.applicationTimestampProvenance='client-clock'],
 ['preflight timestamp used as appliedAt',row=>row.renewal_application.appliedAt=iso(T)],['future application',row=>row.renewal_application.appliedAt=iso(T+5000)],
 ['only one row',row=>row.renewal_application.affectedRows=1],['wrong renewed expiry',row=>row.renewal_application.expiresAt=iso(T+7000000)]
])test('application rejects '+name+' without successful readback proof',async()=>{const h=harness({transport:({request,response,defaultRow})=>{if(request.phase==='two-row-expiry-write'){mutate(defaultRow);return {status:200,raw:Buffer.from(JSON.stringify([defaultRow]))};}return response;}});await assert.rejects(h.run());assert.equal(h.published,null);assert.equal(h.events.filter(x=>x==='dispatch:readback').length,1);});
test('late postcommit application over45seconds blocks continuation',async()=>{const h=harness({transport:({request,response,defaultRow,time,setTime})=>{if(request.phase==='two-row-expiry-write'){setTime(T+50000);defaultRow.renewal_application.appliedAt=iso(T+50000);return {status:200,raw:Buffer.from(JSON.stringify([defaultRow]))};}return response;}});await assert.rejects(h.run(),/POST_COMMIT/);assert.equal(h.published,null);});
test('readback must follow actual application within45seconds',async()=>{const h=harness({transport:({request,response,defaultRow,setTime})=>{if(request.phase==='readback'){setTime(T+50000);defaultRow.renewal_snapshot.observedAt=iso(T+50000);return {status:200,raw:Buffer.from(JSON.stringify([defaultRow]))};}return response;}});await assert.rejects(h.run(),/POST_APPLICATION/);assert.equal(h.events.filter(x=>x==='dispatch:readback').length,1);});
test('readback schema constraints must equal preflight constraints',async()=>{const h=harness({transport:({request,response,defaultRow})=>{if(request.phase==='readback'){defaultRow.renewal_snapshot.tableContracts[0].constraints[0]='CONTROLLED_CHANGED';return {status:200,raw:Buffer.from(JSON.stringify([defaultRow]))};}return response;}});await assert.rejects(h.run(),/TABLE_CONTRACT_CHANGED/);assert.equal(h.published,null);});
test('readback network failure consumes final call with no retry',async()=>{const h=harness({transport:({request,response})=>{if(request.phase==='readback')throw Error('CONTROLLED_READBACK_UNCERTAIN');return response;}});await assert.rejects(h.run());assert.equal(h.evidence.get('99-stop.json').cumulativeChargedCalls,141);assert.equal(h.events.filter(x=>x==='dispatch:readback').length,1);assert.equal(h.published,null);});
test('exclusive intent collision prevents all network',async()=>{const h=harness({once:()=>{const e=Error('CONTROLLED_EXISTING_ONCE');e.code='EEXIST';throw e;}});await assert.rejects(h.run());assert.equal(h.events.filter(x=>x.startsWith('dispatch:')).length,0);assert.equal(h.evidence.get('99-stop.json').cumulativeChargedCalls,138);});
test('run expiry after once prevents dispatch',async()=>{let h;h=harness({once:()=>h.setTime(T+7130000)});await assert.rejects(h.run());assert.equal(h.events.filter(x=>x.startsWith('dispatch:')).length,0);});
test('per-request timeout resolves uncertain write once and preserves failures',async()=>{const h=harness({portTimeoutMs:10,transport:({request,response})=>request.phase==='two-row-expiry-write'?new Promise(()=>{}):response});await assert.rejects(h.run(),/PORT_DEADLINE/);assert.equal(h.evidence.get('99-stop.json').cumulativeChargedCalls,141);assert.equal(h.published,null);});
test('aborted before dispatch stops without a network call',async()=>{const controller=new AbortController();controller.abort();const h=harness({signal:controller.signal});await assert.rejects(h.run(),/ABORTED/);assert.equal(h.events.filter(x=>x.startsWith('dispatch:')).length,0);});
test('publish receipt failure cannot turn into another write',async()=>{const h=harness({publish:()=>{throw Error('CONTROLLED_PUBLISH_FAILURE');}});await assert.rejects(h.run());assert.equal(h.events.filter(x=>x==='dispatch:two-row-expiry-write').length,1);assert.equal(h.evidence.get('99-stop.json').a7ContinuationAllowed,false);});
test('checked context is immutable after run starts',async()=>{let h;h=harness({once:()=>{h.checked.plan.window.expiresAt=iso(T+1);h.checked.controls.ownerDecision.approved=false;}});const result=await h.run();assert.equal(result.actualCumulativeChargedCalls,141);});
function fakeHttps({authorized=true,encrypted=true,status=200,raw=Buffer.from('[]'),deferSocket=false,failRequest=false}={}){
 const calls=[];return {calls,requestFactory:(url,options,callback)=>{const req=new EventEmitter();req.destroy=()=>{req.destroyed=true;};req.end=body=>{calls.push({url,options,body,req});queueMicrotask(()=>{if(failRequest)return req.emit('error',Error('CONTROLLED_SOCKET_FAILURE'));const response=new EventEmitter();response.statusCode=status;callback(response);response.emit('data',raw);response.emit('end');});};
  if(!deferSocket)queueMicrotask(()=>{const socket=new EventEmitter();socket.encrypted=encrypted;socket.authorized=authorized;req.emit('socket',socket);if(!authorized)socket.emit('secureConnect');});return req;}};
}
function httpFixture(opts={}){const f=fixture(),fake=fakeHttps(opts);let time=T;const t=R.createRenewalTransport('CONTROLLED_NOT_A_CREDENTIAL',{readSql,writeTemplate,window:f.checked.plan.window,requestFactory:fake.requestFactory,now:()=>time});return {...f,...fake,...t,setTime:v=>time=v,request:(phase,query=readSql)=>t.send({phase,query,readOnly:phase!=='two-row-expiry-write',deadline:time+25})};}
test('transport uses exact verified HTTPS project endpoint and no redirects',async()=>{const t=httpFixture({status:302});const response=await t.request('preflight');assert.equal(response.status,302);assert.equal(t.calls.length,1);assert.equal(t.calls[0].url,'https://api.supabase.com/v1/projects/'+R.PROJECT+'/database/query');assert.equal(t.calls[0].options.rejectUnauthorized,true);assert.deepEqual(JSON.parse(t.calls[0].body),{query:readSql,read_only:true});t.close();});
for(const [name,options] of [['unauthorized TLS',{authorized:false}],['unencrypted socket',{encrypted:false}]])test('transport rejects '+name+' before body dispatch',async()=>{const t=httpFixture(options);await assert.rejects(t.request('preflight'),/VERIFIED_RENEWAL_TLS/);assert.equal(t.calls.length,0);t.close();});
test('transport deadline bounds stalled TLS handshake',async()=>{const t=httpFixture({deferSocket:true});await assert.rejects(t.request('preflight'),/TRANSPORT_TIMEOUT/);assert.equal(t.calls.length,0);t.close();});
test('transport rejects wrong route SQL before request creation',async()=>{const t=httpFixture();await assert.rejects(t.request('preflight','select 1;'),/EXACT_RENEWAL_READ_SQL/);assert.equal(t.calls.length,0);t.close();});
test('transport preserves raw nonJSON response for durable caller evidence',async()=>{const t=httpFixture({raw:Buffer.from('not-json'),status:500});const r=await t.request('preflight');assert.equal(r.status,500);assert.equal(r.raw.toString(),'not-json');t.close();});
test('transport enforces response cap',async()=>{const t=httpFixture({raw:Buffer.alloc(2097153)});await assert.rejects(t.request('preflight'),/RESPONSE_LIMIT/);t.close();});
test('transport failures do not silently retry',async()=>{const t=httpFixture({failRequest:true});await assert.rejects(t.request('preflight'),/TRANSPORT_UNCERTAIN/);assert.equal(t.calls.length,1);t.close();});
test('transport accepts exact three calls and rejects fourth',async()=>{const t=httpFixture();const rendered=R.renderRenewalSql(t.checked,snapshot(t.checked),T);await t.request('preflight');await t.request('two-row-expiry-write',rendered.query);await t.request('readback');await assert.rejects(t.request('readback'),/TRANSPORT_ORDER/);assert.equal(t.calls.length,3);t.close();});
test('transport rejects a NULL write after preflight',async()=>{const t=httpFixture();await t.request('preflight');await assert.rejects(t.request('two-row-expiry-write',writeTemplate),/FIVE_SUBSTITUTED/);assert.equal(t.calls.length,1);t.close();});
test('transport carries immutable approved window through delayed dispatch',async()=>{const t=httpFixture();t.checked.plan.window.expiresAt=iso(T+9999999);t.setTime(T+7140001);await assert.rejects(t.request('preflight'),/FRESH_BOUNDED/);assert.equal(t.calls.length,0);t.close();});
test('closed transport cannot be reused',async()=>{const t=httpFixture();t.close();await assert.rejects(t.request('preflight'),/TRANSPORT_ORDER/);assert.equal(t.calls.length,0);});
test('source-only tests did not create any actual operation file',async()=>{for(const file of [R.PLAN,R.REVIEW,R.ONCE,R.READBACK,R.CONTROL_PATHS.ownerDecision,R.CONTROL_PATHS.metadata,R.CONTROL_PATHS.refresh])await assert.rejects(fs.access(new URL(file,root)),e=>e.code==='ENOENT');});
test('all server anchor aliases and raw response bindings retain exact provenance',async()=>{const h=harness();const result=await h.run();assert.equal(result.serverWindowAnchor,result.preflightObservedAt);assert.equal(result.serverExpiryAnchor,result.preflightObservedAt);for(const [i,name] of ['renewalPreflightResponseBinding','renewalWriteResponseBinding','renewalReadbackResponseBinding'].entries()){assert.equal(result[name].sha256,result.controlCallAccounting.receipts[i].responseSha256);assert.ok(result[name].path.endsWith(`${139+i}-${['preflight','two-row-expiry-write','readback'][i]}-response.bin`));}});
test('window expires during public checks before private input is allowed',async()=>{const f=fixture();let calls=0;await assert.rejects(R.preflightRenewalOperation({finalReviewSha256:f.checked.finalReviewSha256,readPublic:f.readPublic,now:()=>++calls===1?T:T+7140001}),/FRESH_BOUNDED/);});
test('source bytes drift blocks public preflight',async()=>{const f=fixture();f.files.set(R.SOURCE,Buffer.from('CONTROLLED_CHANGED_SOURCE'));await assert.rejects(R.preflightRenewalOperation({finalReviewSha256:f.checked.finalReviewSha256,readPublic:f.readPublic,now:()=>T}));});
test('policy current ledger mismatch fails closed',()=>{const f=fixture();f.checked.controls.sourcePolicy.currentChargeBinding.sha256=H;assert.throws(()=>R.validateContract(f.checked,T),/EXACT_REVIEWED_RENEWAL/);});
test('review current ledger mismatch fails closed',()=>{const f=fixture();f.checked.controls.policyReview.currentChargeBinding.sha256=H;assert.throws(()=>R.validateContract(f.checked,T),/INDEPENDENT_RENEWAL_POLICY/);});
test('extra management private configuration rejected before transport',async()=>{const f=fixture();let transports=0;await assert.rejects(R.main(['--execute',H],{stdin:(async function*(){yield JSON.stringify({projectId:R.PROJECT,bundleSha256:R.BUNDLE,ownerToken:'CONTROLLED_ONLY',serviceKey:'CONTROLLED_EXTRA'});})(),preflight:async()=>f.checked,transportFactory:()=>transports++}),/MANAGEMENT_ONLY/);assert.equal(transports,0);});
test('oversized management configuration rejected before transport',async()=>{const f=fixture();let transports=0;await assert.rejects(R.main(['--execute',H],{stdin:(async function*(){yield 'x'.repeat(8193);})(),preflight:async()=>f.checked,transportFactory:()=>transports++}),/BOUNDED_PRIVATE/);assert.equal(transports,0);});
test('invalid final review digest rejected before any public read',async()=>{let reads=0;await assert.rejects(R.preflightRenewalOperation({finalReviewSha256:'no',readPublic:()=>{reads++;},now:()=>T}),/FINAL_REVIEW_SHA/);assert.equal(reads,0);});
test('failed readback raw response remains retained and cannot be replayed',async()=>{const h=harness({transport:({request,response})=>request.phase==='readback'?{status:200,raw:Buffer.from('null')}:response});await assert.rejects(h.run());assert.ok(h.evidence.has('141-readback-response.bin'));assert.equal(h.events.filter(x=>x==='dispatch:readback').length,1);assert.equal(h.evidence.get('99-stop.json').failedAttempts,1);});
test('evidence receipt digest mismatch fails before any dispatch',async()=>{const f=fixture();let calls=0;await assert.rejects(R.runRenewal({checked:f.checked,now:()=>T,transport:()=>calls++,persist:async(file,value)=>({path:'docs/verification/wave5/'+file,sha256:sha(bytes(value))}),once:async()=>({path:R.ONCE,sha256:H}),publishReadback:async()=>{throw Error('NO_PUBLISH');}}),/EXCLUSIVE_RENEWAL_INTENT/);assert.equal(calls,0);});
test('future metadata not-before blocks contract despite otherwise valid timestamps',()=>{const f=fixture();f.checked.plan.window.notBefore=iso(T+1);f.checked.controls.metadata.createdAt=iso(T+1);assert.throws(()=>R.validateContract(f.checked,T),/FRESH_BOUNDED/);});
test('observed readback before application fails even with valid row state',()=>{const f=fixture(),s=snapshot(f.checked,T+1000,true);assert.throws(()=>R.validateSnapshot(s,f.checked,{now:T+3000,renewedExpiry:f.checked.controls.metadata.expiresAt,appliedAt:iso(T+2000)}),/POST_APPLICATION/);});
test('owner refresh must bind original project organization',()=>{const f=fixture();f.checked.controls.refresh.organizationId='CONTROLLED_OTHER_ORGANIZATION';assert.throws(()=>R.validateContract(f.checked,T),/ACTUAL_ONE_GET/);});
test('matching fabricated metadata and refresh helper hashes are rejected',()=>{const f=fixture();f.checked.controls.refresh.helperSha256=H;f.checked.controls.metadata.helperSha256=H;assert.throws(()=>R.validateContract(f.checked,T),/ACTUAL_ONE_GET/);});
test('public preflight checks exact owner refresh helper before private input',async()=>{const f=fixture();f.files.set(R.OWNER_REFRESH_HELPER.path,Buffer.from('CONTROLLED_CHANGED_REFRESH_SOURCE'));await assert.rejects(R.preflightRenewalOperation({finalReviewSha256:f.checked.finalReviewSha256,readPublic:f.readPublic,now:()=>T}));assert.ok(f.reads.includes(R.OWNER_REFRESH_HELPER.path));});
