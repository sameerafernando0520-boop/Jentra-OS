// Management-only entry point. Public preflight performs no writes, private
// input reads or network calls. The separate owner adapter supplies the PAT.
import fs from 'node:fs/promises';
import path from 'node:path';
import https from 'node:https';
import {fileURLToPath} from 'node:url';
import {createHash,randomUUID} from 'node:crypto';
import {isDeepStrictEqual as same} from 'node:util';
import {setTimeout as delay} from 'node:timers/promises';
import {PROJECT,RUNTIME,BUNDLE,SOURCE,PRIVATE_ADAPTER,PREFLIGHT_SQL,validateReview,buildDispatchSql,buildReadbackSql,runHealthReadiness} from './probe_worker_v7_health_20261014_r5.mjs';
import {EXPORTS_PROFILE,EXPORTS_PROFILE_PATHS,validateExportsProfile} from './finance_exports_20261014_r5_a6.mjs';
import {validateExportsProof} from './resume_worker_schedules_20261014_r5_v7.mjs';

export const LAUNCHER='tools/wave5/run_worker_v7_health_20261015_r5.mjs';
const BASE='docs/verification/wave5/task3-health-readiness-20261014/';
export const PLAN=BASE+'execution-plan-20261015-a1.json',REVIEW=BASE+'final-operation-review-20261015-a1.json';
export const ONCE=BASE+'actual-health-once-20261015-a1.json';
export const OPERATION_DECISION='docs/verification/wave5/runtime-renewed-health-scheduler-owner-decision-20261015-r5-a1.json';
const root=fileURLToPath(new URL('../../',import.meta.url));
const sha=x=>createHash('sha256').update(x).digest('hex');
const digest=x=>typeof x==='string'&&/^[a-f0-9]{64}$/.test(x);
const must=(ok,code)=>{if(!ok){const e=Error(code);e.publicCode=code;throw e;}};
const binding=x=>x&&typeof x.path==='string'&&digest(x.sha256);
const sameBinding=(a,b)=>binding(a)&&binding(b)&&a.path===b.path&&a.sha256===b.sha256;
export function healthPlanBinding(review){
 must(review?.generatedPlan?.path===PLAN&&binding(review.generatedPlan)
  &&(review.planBinding===undefined||sameBinding(review.planBinding,review.generatedPlan)),'EXACT_GENERATED_HEALTH_PLAN_REQUIRED');
 return review.generatedPlan;
}
const publicPath=p=>typeof p==='string'&&/^(docs\/verification\/wave5\/|tools\/wave5\/|scripts\/wave5\/|workers\/wave5\/|supabase\/)/.test(p)
 &&/^[A-Za-z0-9_./-]+$/.test(p)&&!p.split('/').includes('..')&&!p.includes('//');

export async function readPublicFile(item,{workspace=root}={}){
 must(binding(item)&&publicPath(item.path),'PINNED_PUBLIC_HEALTH_FILE_REQUIRED');
 const target=path.resolve(workspace,item.path),stat=await fs.lstat(target);
 must(stat.isFile()&&!stat.isSymbolicLink()&&stat.size<=1048576&&path.resolve(await fs.realpath(target))===target,'BOUNDED_UNREDIRECTED_PUBLIC_HEALTH_FILE_REQUIRED');
 const bytes=await fs.readFile(target);must(bytes.length<=1048576&&sha(bytes)===item.sha256,'PUBLIC_HEALTH_BINDING_CHANGED');return bytes;
}

export async function preflightHealthOperation({finalReviewSha256,readPublic=readPublicFile,now=Date.now,validateProfile=validateExportsProfile}={}){
 must(digest(finalReviewSha256),'PINNED_HEALTH_FINAL_REVIEW_REQUIRED');
 const get=async item=>JSON.parse(await readPublic(item));
 const review=await get({path:REVIEW,sha256:finalReviewSha256});validateReview(review,now());
 const planBinding=healthPlanBinding(review);
 must(review.launcherBinding?.path===LAUNCHER&&review.privateAdapter?.path===PRIVATE_ADAPTER
  &&sameBinding(review.privateAdapterBinding,{path:PRIVATE_ADAPTER,sha256:review.privateAdapter.afterSha256}),'EXACT_HEALTH_PLAN_LAUNCHER_ADAPTER_REQUIRED');
 const plan=await get(planBinding);
 must(plan?.kind==='source-bound-deployed-v7-health-plan'&&plan.projectId===PROJECT&&plan.runtimeId===RUNTIME&&plan.runtimeBundleSha256===BUNDLE
  &&plan.maximumManagementAttempts===5&&plan.maximumHealthInvocations===1&&plan.overallCumulativeMaximum===171
  &&plan.maximumCumulativeAfterHealth===168&&plan.maximumCumulativeBeforeHealth===163&&plan.automaticRetries===0
  &&plan.exclusiveOncePath===ONCE&&plan.finalReviewPath===REVIEW&&plan.liveExecutionAuthorizedByPreparation===false,
  'EXACT_BOUNDED_HEALTH_PLAN_REQUIRED');
 must(plan.controlBindings?.exportsProfile?.path===EXPORTS_PROFILE&&plan.controlBindings.metadata?.path===EXPORTS_PROFILE_PATHS.metadata
  &&plan.controlBindings.operationDecision?.path===OPERATION_DECISION,'FIXED_HEALTH_CONTROL_PATHS_REQUIRED');
 const profile=await get(plan.controlBindings.exportsProfile),documents={};
 for(const [key,p] of Object.entries(EXPORTS_PROFILE_PATHS)){
  must(profile.controlBindings?.[key]?.path===p,'FIXED_EXPORT_PROFILE_CONTROL_REQUIRED');documents[key]=await get(profile.controlBindings[key]);
 }
 validateProfile(profile,documents,now());
 must(sameBinding(plan.controlBindings.metadata,profile.controlBindings.metadata)
  &&sameBinding(review.humanRenewalDecisionBinding,profile.controlBindings.ownerDecision)
  &&sameBinding(review.actualRenewalReadbackBinding,profile.controlBindings.renewalReadback)
  &&sameBinding(review.completedExportsBinding,plan.controlBindings.completedExports)
  &&same(plan.window,{notBefore:profile.window.notBefore,expiresAt:profile.window.expiresAt})
  &&Date.parse(review.serverWindowAnchor)===Date.parse(plan.window.notBefore)
  &&Date.parse(review.renewedExpiry)===Date.parse(documents.renewalReadback.edge.expiresAt)
  &&Date.parse(review.authorizationExpiresAt)===Date.parse(plan.window.expiresAt),'EXACT_ACTUAL_HEALTH_RENEWAL_WINDOW_REQUIRED');
 const decision=await get(plan.controlBindings.operationDecision);
 must(decision?.kind==='direct-human-renewed-health-scheduler-decision'&&decision.approved===true&&decision.approvalSource==='direct-user-reply'
  &&typeof decision.questionItemId==='string'&&decision.questionItemId.length>=16&&decision.projectId===PROJECT&&decision.runtimeId===RUNTIME
  &&decision.runtimeBundleSha256===BUNDLE&&decision.healthInvocationAuthorized===true&&decision.maximumHealthInvocations===1
  &&decision.maximumHealthManagementAttempts===5&&decision.overallCumulativeMaximum===171&&decision.maximumScheduleRequests===4320
  &&decision.healthKeepsSchedulesPaused===true&&decision.productionAuthorized===false&&decision.realBillingAuthorized===false
  &&decision.operationBundleSha256===documents.ownerDecision.operationBundleSha256
  &&Date.parse(decision.decidedAt)<=Date.parse(documents.renewalReadback.appliedAt),'EXPLICIT_RENEWED_HEALTH_OPERATION_AUTHORITY_REQUIRED');
 const exportsResult=validateExportsProof(await get(review.completedExportsBinding));
 must(exportsResult.priorConservativeBound===138&&exportsResult.totalWorkflowRequestBound===162&&exportsResult.maximumCumulativeAttemptLimit===163,
  'ACTUAL_EXPORT_CALL_ACCOUNTING_REQUIRED');
 must(Array.isArray(plan.sourceAndEvidenceBindings)&&new Set(plan.sourceAndEvidenceBindings.map(x=>x.path)).size===plan.sourceAndEvidenceBindings.length,
  'UNIQUE_HEALTH_SOURCE_AND_EVIDENCE_REQUIRED');
 const required=[review.sourceBinding,review.launcherBinding,review.privateAdapterBinding,...Object.values(plan.controlBindings),
  ...Object.values(profile.controlBindings),...documents.sourcePolicy.exportSourceBindings,
  {path:'tools/wave5/resume_worker_schedules_20261014_r5_v7.mjs',sha256:'8bf3fcbb9ec17a2697afa7c4e360e664503e0128922fb8361b64450af73e8372'}];
 for(const artifact of exportsResult.artifacts){must(sameBinding(artifact.artifact,{path:artifact.artifact?.path,sha256:artifact.fileSha256}),
  'ACTUAL_EXPORT_ARTIFACT_BINDING_REQUIRED');required.push(artifact.artifact);}
 for(const item of required)must(plan.sourceAndEvidenceBindings.some(x=>sameBinding(x,item)),'ALL_HEALTH_SOURCE_AND_EVIDENCE_BINDINGS_REQUIRED');
 for(const item of plan.sourceAndEvidenceBindings)await readPublic(item);
 must(same(review.sourceAndEvidenceBindings,plan.sourceAndEvidenceBindings),'EXACT_FINAL_HEALTH_SOURCE_INVENTORY_REQUIRED');
 validateReview(review,now());must(Date.parse(plan.window.expiresAt)-now()>=90000,'HEALTH_PRIVATE_INPUT_RESOLUTION_MARGIN_REQUIRED');
 return {review,plan,publicResult:{passed:true,networkCalls:0,privateInputsRead:false,planSha256:planBinding.sha256,finalReviewSha256}};
}

export function createHealthTransport(ownerToken,{review,requestFactory=https.request,now=Date.now}={}){
 must(typeof ownerToken==='string'&&ownerToken.length>=9&&ownerToken.length<=2048&&!/\s/.test(ownerToken),'PRIVATE_MANAGEMENT_INPUT_REQUIRED');
 validateReview(review,now());const writeSql=buildDispatchSql(review);let attempts=0,dispatches=0,requestId=null;
 return async ({kind,query,readOnly,signal,deadline})=>{
  validateReview(review,now());must(!signal?.aborted&&Number.isFinite(deadline)&&deadline>now()
   &&deadline<=now()+15000&&deadline<=Date.parse(review.authorizationExpiresAt),'BOUNDED_HEALTH_TRANSPORT_WINDOW_REQUIRED');
  must(attempts<5&&((attempts===0&&kind==='preflight'&&readOnly===true&&query===PREFLIGHT_SQL)
   ||(attempts===1&&kind==='dispatch'&&readOnly===false&&query===writeSql&&dispatches===0)
   ||(attempts>=2&&kind==='readback'&&readOnly===true&&requestId!==null&&query===buildReadbackSql(requestId))),
   'EXACT_ORDERED_HEALTH_REQUEST_REQUIRED');
  attempts++;if(!readOnly)dispatches++;
  const body=JSON.stringify({query,read_only:readOnly});
  return new Promise((resolve,reject)=>{let req,timer,settled=false,size=0,sent=false;const chunks=[];
   const cleanup=()=>{clearTimeout(timer);signal?.removeEventListener('abort',abort);};
   const fail=code=>{if(settled)return;settled=true;cleanup();req?.destroy();const error=Error(code);error.publicCode=code;error.sent=sent;reject(error);};
   const abort=()=>fail('HEALTH_TRANSPORT_CANCELLED');
   signal?.addEventListener('abort',abort,{once:true});
   try{req=requestFactory(`https://api.supabase.com/v1/projects/${PROJECT}/database/query`,{method:'POST',rejectUnauthorized:true,
    headers:{Authorization:`Bearer ${ownerToken}`,'Content-Type':'application/json','Content-Length':Buffer.byteLength(body)}},res=>{
     res.on('error',()=>fail('HEALTH_RESPONSE_UNCERTAIN'));res.on('aborted',()=>fail('HEALTH_RESPONSE_ABORTED'));
     res.on('data',chunk=>{if(settled)return;size+=chunk.length;if(size>1048576)fail('HEALTH_RESPONSE_LIMIT');else chunks.push(Buffer.from(chunk));});
     res.on('end',()=>{if(settled)return;const raw=Buffer.concat(chunks);let rows=null;
      if(res.statusCode===200){try{rows=JSON.parse(raw);}catch{/* Hash-only malformed response evidence. */}}
      if(kind==='dispatch'&&Array.isArray(rows)&&rows.length===1&&Number.isSafeInteger(rows[0].requestId)&&rows[0].requestId>0)requestId=rows[0].requestId;
      settled=true;cleanup();resolve({status:res.statusCode,rows,rawSha256:sha(raw),rawBytes:raw.length});});});
    req.on('error',()=>fail('HEALTH_TRANSPORT_UNCERTAIN'));
    timer=setTimeout(()=>fail('HEALTH_TRANSPORT_TIMEOUT'),Math.max(1,deadline-now()));
    req.once('socket',socket=>{const send=()=>{if(settled)return;
     if(signal?.aborted||now()>=deadline)return fail('HEALTH_TRANSPORT_EXPIRED');
     if(socket.encrypted!==true||socket.authorized!==true)return fail('VERIFIED_HEALTH_TLS_REQUIRED');sent=true;req.end(body);};
     if(socket.authorized===true)send();else socket.once('secureConnect',send);});
   }catch{fail('HEALTH_REQUEST_FAILED');}
  });
 };
}

async function save(relative,value){
 must(publicPath(relative),'PUBLIC_HEALTH_OUTPUT_REQUIRED');const target=path.resolve(root,relative),bytes=Buffer.from(JSON.stringify(value,null,2)+'\n');
 const handle=await fs.open(target,'wx');try{await handle.writeFile(bytes);await handle.sync();}finally{await handle.close();}
 return {path:relative,sha256:sha(bytes)};
}
export async function main(argv=process.argv.slice(2),{stdin=process.stdin,stdout=process.stdout,now=Date.now,
 preflight=preflightHealthOperation,run=runHealthReadiness}={}){
 must(argv.length===2&&['--preflight','--execute'].includes(argv[0])&&digest(argv[1]),'EXACT_HEALTH_LAUNCHER_MODE_REQUIRED');
 let checked=await preflight({finalReviewSha256:argv[1],now});
 if(argv[0]==='--preflight'){stdout.write(JSON.stringify(checked.publicResult)+'\n');return checked.publicResult;}
 let text='',cfg,timer;
 try{
  await Promise.race([(async()=>{for await(const chunk of stdin){text+=chunk;must(text.length<=8192,'PRIVATE_HEALTH_INPUT_LIMIT');}})(),
   new Promise((_,reject)=>{timer=setTimeout(()=>{stdin.destroy?.();reject(Error('PRIVATE_HEALTH_INPUT_TIMEOUT'));},15000);})]);
  clearTimeout(timer);cfg=JSON.parse(text);text='';
  must(same(Object.keys(cfg).sort(),['bundleSha256','ownerToken','projectId'])&&cfg.projectId===PROJECT&&cfg.bundleSha256===BUNDLE,
   'EXACT_MANAGEMENT_ONLY_HEALTH_INPUT_REQUIRED');
  checked=await preflight({finalReviewSha256:argv[1],now});
  const transport=createHealthTransport(cfg.ownerToken,{review:checked.review,now});
  const directory=BASE+'actual-'+randomUUID()+'/';await fs.mkdir(path.join(root,directory));
  const result=await run({review:checked.review,transport,now,
   once:async value=>{checked=await preflight({finalReviewSha256:argv[1],now});return save(ONCE,{...value,finalReviewSha256:argv[1],planBinding:healthPlanBinding(checked.review),directory});},
   persist:(file,value)=>save(directory+file,value),wait:(ms,{signal})=>delay(ms,undefined,{signal})});
  stdout.write(JSON.stringify({passed:true,evidencePath:directory+'99-result.json',managementAttempts:result.managementAttempts,actualDelivery:false})+'\n');return result;
 }finally{clearTimeout(timer);if(cfg)cfg.ownerToken=null;text='';}
}
if(process.argv[1]&&path.resolve(process.argv[1])===fileURLToPath(import.meta.url))main().catch(error=>{
 process.stderr.write(JSON.stringify({failureCode:error.publicCode??'HEALTH_LAUNCHER_STOP',secretsPrinted:false})+'\n');process.exitCode=1;
});
