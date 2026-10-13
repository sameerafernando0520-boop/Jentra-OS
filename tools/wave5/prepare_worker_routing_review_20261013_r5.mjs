import fs from 'node:fs/promises';
import path from 'node:path';
import {fileURLToPath} from 'node:url';
import {PROJECT,BUNDLE,loadApprovedInputs,decodePublicResult} from './approved_management_installer.mjs';
import {hashBytes} from './runtime_contract.mjs';
const root=fileURLToPath(new URL('../../',import.meta.url)),base='docs/verification/wave5/';
const must=(v,c)=>{if(!v)throw Error(c);};
await loadApprovedInputs();
const pins=[['workers/wave5/edge_runtime.mjs','29c50f277e90c3a84bcefa9b5e9b1bea8da8a82ef380ec27ab3a4e47063c4ccd'],['workers/wave5/edge_receiver.mjs','937c0f37f69c45a30a9dc0483d991cc46ecd4f40c54409a734cda40ca778c39e'],
 [base+'worker-routing-node-tests-20261013-r5.log','2b3d3843e98c4828b49b3abc3386a9f031dcf0bb01f2a4feb6fb3d0ada7c1ab2'],
 [base+'worker-routing-runtime-deno-20261013-r5.log','6b06f6adb9529e6afa126aacd10cdaa078ed30017c1bd0bca2f0a78254bc4f03'],
 [base+'worker-routing-receiver-deno-20261013-r5.log','4ae4ac7ca85b051f89ac8428d3684f16291fb840b55956902bb53303b458cbc6'],
 [base+'scheduled-delivery-pause-20261013-r5-1791889754523/99-result.json','f10b6c67bbf7d33a9ed5f64c0ccd6bbb573a162dbab6383c11d36ad79e6dc2b4']];
for(const [file,sha]of pins)must(hashBytes(await fs.readFile(path.join(root,file)))===sha,'EXACT_ROUTING_REVIEW_BINDING_REQUIRED');
const actualFile=base+'scheduled-delivery-paused-live-20261013-r5.json',actualBytes=await fs.readFile(path.join(root,actualFile));
const actual=decodePublicResult(JSON.parse(actualBytes))[0].snapshot;
must(actual.migrationCount===114&&actual.apiFunctionCount===363&&actual.ownJobs.length===3&&actual.ownJobs.every(j=>j.active===false)
 &&actual.netResponseCount===18&&actual.allKnownHandler404===true&&actual.ticks===0&&actual.deliveryOutcomes===0&&actual.receiverReceipts===0&&actual.quotaPeriods===0,'EXACT_FAILED_ROUTE_AND_PAUSE_PROOF_REQUIRED');
async function bind(file){return {path:file,sha256:hashBytes(await fs.readFile(path.join(root,file)))};}
async function save(file,value){const bytes=typeof value==='string'?value:JSON.stringify(value,null,2)+'\n';const h=await fs.open(path.join(root,file),'wx');try{await h.writeFile(bytes);await h.sync();}finally{await h.close();}return {path:file,sha256:hashBytes(bytes)};}
const testFiles=(await fs.readdir(path.join(root,'workers/wave5'))).filter(f=>f.endsWith('.mjs')).sort();
const testLog=await fs.readFile(path.join(root,pins[2][0]),'utf8');must(/# tests 105\s/.test(testLog)&&/# pass 105\s/.test(testLog)&&/# fail 0\s/.test(testLog),'FRESH_WORKER_TESTS_REQUIRED');
const testRecord=await save(base+'worker-routing-local-verification-20261013-r5.json',{kind:'actual-worker-routing-local-verification',actualRecordedAt:new Date().toISOString(),nodeCommand:'node --test --test-isolation=none --test-reporter=tap <13 worker test files>',nodeExecChunkId:'0c7905',tests:105,passed:105,failed:0,skipped:0,nodeTestLog:await bind(pins[2][0]),
 testedSource:await Promise.all(testFiles.map(f=>bind('workers/wave5/'+f))),deno:{version:'2.9.7',command:'deno check --config <reviewed per-entrypoint deno.json> <candidate entrypoint.ts>',execChunkId:'54fbc0',runtimeExitCode:0,receiverExitCode:0,runtimeLog:await bind(pins[3][0]),receiverLog:await bind(pins[4][0]),importedJavaScriptTypeChecked:false,javaScriptVerification:'105 passing Node tests',
 officialRelease:'https://github.com/denoland/deno/releases/tag/v2.9.7',officialArchiveSha256:'a0c3101b4158d1dfb7d6a78a7bf0f3de80c96bb423c152beec8beb22786f2238',executableSha256:'e020f3e232bd16e33768dee528e5983349c962952051ced0a5d58ad42f5d9b33',workspaceOnlyCompiler:true},networkEffectsUnderTest:false,deployed:false,authenticatedNative:false,ownerAccepted:false});
const deployments=[];
for(const name of ['wave5-runtime','wave5-receiver']){
 const entrypoint=`supabase/functions/${name}/index_20261013_r5.ts`,config=`supabase/functions/${name}/deno.json`,closure=new Map();
 async function visit(file){if(closure.has(file))return;const content=await fs.readFile(path.join(root,file),'utf8');closure.set(file,content);
  for(const match of content.matchAll(/(?:from\s+|import\s*)['"](\.{1,2}\/[^'"]+)['"]/g)){
   const child=path.posix.normalize(path.posix.join(path.posix.dirname(file),match[1]));must(!child.startsWith('../')&&!path.posix.isAbsolute(child),'LOCAL_DEPENDENCY_REQUIRED');await visit(child);
  }
 }
 await visit(entrypoint);closure.set(config,await fs.readFile(path.join(root,config),'utf8'));
 const files=[...closure].sort(([a],[b])=>a.localeCompare(b)).map(([name,content])=>({name,content}));
 const payload={link_id:'link_6aa8c9ca60408191b9e7e8344c5a6693',project_id:PROJECT,name,entrypoint_path:entrypoint,verify_jwt:false,files};
 const payloadBinding=await save(base+`supabase-deploy-${name}-routing-20261013-r5.json`,payload);
 deployments.push({name,entrypoint,verifyJwt:false,files:await Promise.all(files.map(f=>bind(f.name))),payload:payloadBinding,customAuthenticationUnchanged:true});
}
must(deployments[0].files.length===15&&deployments[1].files.length===9,'EXACT_NEW_DEPLOYMENT_CLOSURES_REQUIRED');
const body={kind:'focused-edge-routing-runtime-review',projectId:PROJECT,preparedAt:new Date().toISOString(),ownerApproved:false,approvalReady:true,originalApprovedBundleSha256:BUNDLE,
 approvedOperationScopeUnchanged:'Two existing Wave 5 functions and the same three bounded test schedules; no migration, account, grant, secret, destination, model allowance or expiry increase.',
 changes:'Separate candidate files recognize the documented /wave5-runtime and /wave5-receiver function-name paths as well as the original public /functions/v1 paths, retaining the exact configured HTTPS origin and all original authentication and body checks.',
 liveFailure:{evidence:{path:actualFile,sha256:hashBytes(actualBytes)},observedAt:actual.observedAt,scheduledHttpResponses:18,allKnownHandler404:true,workerTicks:0,deliveryOutcomes:0,receiverReceipts:0,quotaPeriods:0,ownJobsPaused:true},
 diagnosis:{basis:'Official in-function routing contract plus confirmed handler NOT_FOUND responses.',officialDocumentation:'https://supabase.com/docs/guides/functions/routing',internalRequestUrlDirectlyObserved:false,inference:true},
 preservedOriginalSources:pins.slice(0,2).map(([file,sha])=>({path:file,sha256:sha})),localVerification:testRecord,deployments,
 actionsAfterSpecificApproval:['Replace only the two named Wave 5 deployments with these exact payloads.','Independently read back all returned modules and unchanged authentication flags.','Resume only the existing exact jobs 4, 5 and 6 within their original expiry and collect real transport/receipt evidence.','Stop and preserve evidence if routing, authentication, readiness or delivery remains uncertain.'],
 retainedLimits:{maximumModelCalls:4,maximumScheduleRequestsOriginal:4320,scheduleRequestsAlreadyObserved:18,authorityExpiresAt:'2026-10-14T09:57:07.481942Z',scopeMayExpireEarlier:true,newUsers:0,newMigrations:0,production:false,realBilling:false},
 livePostPatchVerified:false,fullProviderCoordinatorPassed:false,authenticatedNative:false,nativeKeyboard:false,targetScaleLoad:false,ownerAcceptedCriteria:3,remainingUnacceptedCriteria:106,independentReviewPending:true};
const review={...body,bundleSha256:hashBytes(JSON.stringify(body))};
const reviewBinding=await save(base+'worker-routing-runtime-review-20261013-r5.json',review);
const esc=v=>String(v).replaceAll('&','&amp;').replaceAll('<','&lt;').replaceAll('>','&gt;').replaceAll('"','&quot;');
const routeSource=await fs.readFile(path.join(root,'workers/wave5/edge_route_20261013_r5.mjs'),'utf8');
const html=`<!doctype html><html lang="en"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>Jentra OS routing correction review</title><style>body{font:17px/1.6 system-ui;background:#101a29;color:#e9eef7;max-width:960px;margin:36px auto;padding:0 24px}a{color:#8dd8ff}h1{font-size:30px}pre{background:#19263a;overflow:auto;padding:16px;font-size:13px}code{overflow-wrap:anywhere}table{border-collapse:collapse;width:100%;font-size:14px}td,th{border:1px solid #37516b;padding:10px;text-align:left}.open{color:#ffd899}.pass{color:#92edbd}</style><h1>Jentra OS: reviewed routing correction</h1><p class="open">Development is incomplete. Owner acceptance remains 3/109. This page requests only the focused runtime correction below.</p><p>The three scheduled test jobs ran, but all 18 completed requests returned the worker’s <code>NOT_FOUND</code> response. No worker tick, receiver receipt, delivery outcome or quota period was created. The same three jobs are now paused.</p><p>The <a href="https://supabase.com/docs/guides/functions/routing">official Supabase routing contract</a> uses function-name prefixes inside a function. The preserved original handlers check only the full public <code>/functions/v1/...</code> path. The candidate recognizes both exact namespaces on the same configured HTTPS origin. The diagnosis about the internal path remains an inference until fresh live checks confirm it.</p><p class="pass">105 worker tests passed; both new TypeScript entrypoints passed fresh Deno checks. Tests cover signed delivery, HMAC failures, revoked scope, duplicate ticks, deadline cancellation, quota ordering and rejection of other origins, prefixes, queries and routes. JavaScript was tested with Node; the reviewed Deno configuration does not type-check imported JavaScript.</p><p>Requested action: replace only <code>wave5-runtime</code> and <code>wave5-receiver</code> with these exact candidate payloads, verify returned sources, and resume the existing three bounded schedules. No new SQL, account, permission, secret, destination or spending allowance is requested. Original files remain preserved. Production and real billing remain excluded.</p><table><tr><th>Function</th><th>Bound files</th><th>Authentication</th></tr>${deployments.map(d=>`<tr><td>${esc(d.name)}</td><td>${d.files.length}</td><td>Original custom authentication retained; gateway verify_jwt remains false as already approved.</td></tr>`).join('')}</table><p>Bundle SHA-256: <code>${review.bundleSha256}</code></p><p>Authority expiry remains 14 October, 15:27:07 Sri Lanka time; the scoped test permission may expire earlier. Maximum model calls remain four. The original schedule cap is 4320 requests; 18 have already been observed.</p><details><summary>Exact new path selector</summary><pre>${esc(routeSource)}</pre></details><details><summary>Complete source and payload bindings</summary><pre>${esc(JSON.stringify(deployments,null,2))}</pre></details><p class="open">Independent review is pending. Live delivery, full provider, native keyboard, target-scale load and the other 106 owner decisions remain open. Approving this correction does not accept those requirements.</p></html>`;
const htmlBinding=await save('dist/Jentra OS Worker Routing Review 20261013 r5.html',html);
await loadApprovedInputs();process.stdout.write(JSON.stringify({prepared:true,review:reviewBinding,humanReview:htmlBinding,bundleSha256:review.bundleSha256,independentReviewPending:true,liveOperationsPerformed:false})+'\n');
