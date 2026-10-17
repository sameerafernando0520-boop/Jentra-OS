// Source-only, exclusive review-artifact assembly. No credentials, approvals,
// actual profiles, execution plans, runtime intents, database calls, or installs.
import fs from 'node:fs/promises';
import path from 'node:path';
import {fileURLToPath} from 'node:url';
import {createHash} from 'node:crypto';
import {isDeepStrictEqual} from 'node:util';
import vm from 'node:vm';
import * as R from '../../../../tools/wave5/renew_runtime_authority_20261015_r5_a1.mjs';
import * as E from '../../../../tools/wave5/finance_exports_20261016_r5_a7.mjs';
import * as H from '../../../../tools/wave5/run_worker_v7_health_20261015_r5.mjs';
import * as S from '../../../../tools/wave5/resume_worker_schedules_20261015_r5_a1.mjs';
import {FINANCE_CALENDAR} from '../../../../tools/wave5/finance_cash_fixture_20261013_r5.mjs';
const ROOT=fileURLToPath(new URL('../../../../',import.meta.url));
const OWN='docs/verification/wave5/root-runtime-review-20261017/';
const HTML='dist/Jentra OS Runtime Continuation Review 20261017 r5.html';
const SNAPSHOT='build/wave5-approved-execution-20261013-r5-a2/';
const hash=x=>createHash('sha256').update(x).digest('hex');
const json=x=>Buffer.from(JSON.stringify(x,null,2)+'\n');
const must=(ok,message)=>{if(!ok)throw Error(message);};
const digest=x=>typeof x==='string'&&/^[a-f0-9]{64}$/.test(x);
const read=p=>fs.readFile(path.join(ROOT,p));
const parse=async p=>JSON.parse(await read(p));
const seen=new Map();
async function bind(file,expected){const data=await read(file),sha256=hash(data);must(!expected||sha256===expected,'HASH_DRIFT:'+file);const row={path:file,sha256,bytes:data.length};seen.set(file,row);return row;}
const slim=({path,sha256})=>({path,sha256});
const escape=s=>String(s).replace(/[&<>"']/g,x=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[x]));
const link=p=>`../${p.split('/').map(encodeURIComponent).join('/')}`;
const table=(heads,rows)=>`<div class="table-wrap"><table><thead><tr>${heads.map(x=>`<th scope="col">${escape(x)}</th>`).join('')}</tr></thead><tbody>${rows.map(row=>'<tr>'+row.map(x=>`<td>${x}</td>`).join('')+'</tr>').join('')}</tbody></table></div>`;
async function load(){
 const reviews=[
  ['Renewal controller','docs/verification/wave5/root-runtime-renewal-20261015/independent-source-review-a1.json','bd28c026a0b91866e72dd798205c72de85a34a8908eb339dd09fe38fb559fe8d'],
  ['Export adapter a3','docs/verification/wave5/root-export-adapter-20261017/independent-review-a3.json','b1f18ceb697a1180a643a5f08dfa8bd2babe35edbac447c977007db42a414185'],
  ['Management adapter a2','docs/verification/wave5/root-management-adapter-20261016/independent-review-a2.json','30288741537aa600492b896866949d0e8a427c57e505eaad1d2037a0a125610c']
 ];
 const reviewBindings=[];for(const [name,p,sha] of reviews){const b=await bind(p,sha);must((await parse(p)).passed===true,'SOURCE_REVIEW_NOT_PASSED');reviewBindings.push({name,...b});}
 const exportAdapter=await parse('docs/verification/wave5/root-export-adapter-20261017/source-candidate-a3.json');
 const managementAdapter=await parse('docs/verification/wave5/root-management-adapter-20261016/source-candidate-a2.json');
 must(exportAdapter.candidate.sha256==='aba5237681017897064118d2529c9401d92e6054257a19d4c01a6196f076dcf3','EXACT_EXPORT_ADAPTER');
 must(managementAdapter.candidate.sha256==='7d3559d196932587ea76eafbd527bd6943362ad5c321b5c58873aa822343cce7','EXACT_MANAGEMENT_ADAPTER');
 const exportProof=await parse('docs/verification/wave5/task3-export-renewal-20261016/export-a7-source-proof-a1.json');
 const controllerProof=await parse('docs/verification/wave5/root-runtime-renewal-20261015/renewal-controller-source-proof-a1.json');
 const area=await parse('docs/verification/wave5/seven-area-completion-20261016/area4-integrations/completion-report.json');
 for(const b of [...exportProof.sources,...controllerProof.sourceBindings,...area.sourceBeforeAfterUnchanged])await bind(b.path,b.sha256);
 for(const b of [...Object.values(R.SQL_BINDINGS),R.OWNER_REFRESH_HELPER,E.EXPORTS_DEPENDENCY,E.EXPORTS_CURRENT_CHARGE,...E.EXPORTS_CURRENT_CHARGE_EVIDENCE,
  ...E.EXPORTS_A5_SOURCE_BINDINGS,...E.EXPORTS_A6_SOURCE_BINDINGS,...S.PRESERVED])await bind(b.path,b.sha256);
 for(const b of managementAdapter.sourceBindings)await bind(b.path,b.sha256);
 for(const file of H.HEALTH_IMPORT_DEPENDENCIES)await bind(file);
 for(const b of [exportAdapter.candidate,managementAdapter.candidate,exportAdapter.predecessor,exportAdapter.readHoldSource,managementAdapter.template])await bind(b.path,b.sha256);
 const supportFiles=['tools/wave5/prepare_export_private_adapter_20261017_r5_a3.mjs','tools/wave5/prepare_management_private_adapter_20261016_r5_a2.mjs',
  'docs/verification/wave5/root-export-adapter-20261017/source-candidate-a3.json','docs/verification/wave5/root-management-adapter-20261016/source-candidate-a2.json',
  'docs/verification/wave5/task3-export-renewal-20261016/export-a7-source-proof-a1.json','docs/verification/wave5/root-runtime-renewal-20261015/renewal-controller-source-proof-a1.json',
  'docs/verification/wave5/seven-area-completion-20261016/area4-integrations/completion-report.json','docs/verification/wave5/seven-area-completion-20261016/area4-integrations/entrypoints.test.mjs',
  'docs/verification/wave5/task3-runtime-renewal-20261014/source-repair-a3.json','docs/verification/wave5/runtime-renewal-20261014/export-a6-independent-review-a2.json',
  'docs/verification/wave5/runtime-renewal-20261014/a6-helper-before-chronology-a1.mjs.txt',
  'workers/wave5/model_runtime.mjs'];
 for(const p of supportFiles)await bind(p);
 const oldPlan=await parse(SNAPSHOT+E.EXPORTS_PRESERVED_BINDINGS.a3Plan.path);must(oldPlan.sourceBindings.length===68,'PRESERVED68_REQUIRED');
 const original68=[];for(const b of oldPlan.sourceBindings)original68.push(await bind(SNAPSHOT+b.path,b.sha256));
 const preservedWorkflow=[];for(const b of Object.values(E.EXPORTS_PRESERVED_BINDINGS))preservedWorkflow.push(await bind(SNAPSHOT+b.path,b.sha256));
 for(const b of E.EXPORTS_A5_SOURCE_BINDINGS)await bind(SNAPSHOT+b.path,b.sha256);
 const archive=await parse(S.ARCHIVE_MANIFEST.path);must(archive.entries.length===39,'DEPLOYED39_REQUIRED');
 const archive39=[];for(const b of archive.entries)archive39.push(await bind(b.path,b.sha256));
 const inventory=await parse(S.CALL_INVENTORY.path);S.validateCallInventory(inventory);
 const current=await parse(R.CURRENT_EVIDENCE[5].path);must(current.cumulativeConservativeCharge===137,'ACTUAL137_REQUIRED');
 return {reviewBindings,exportAdapter,managementAdapter,exportProof,controllerProof,area,original68,preservedWorkflow,archive39,inventory,current};
}
function policyFor(bundleSha,material){
 return {kind:'source-only-export-a7-renewal-policy',sourceOnlyDraft:true,intendedPublishedPath:E.EXPORTS_PROFILE_PATHS.sourcePolicy,
  projectId:R.PROJECT,runtimeId:R.RUNTIME,runtimeBundleSha256:R.BUNDLE,sourceImplementationOnly:true,liveExecutionAuthorized:false,
  originalConcreteCumulativeCap:150,budget:E.EXPORTS_REVIEWED_BUDGET,windowMode:'server-clock-at-application',maximumWindowMs:7200000,
  originalWindow:E.EXPORTS_ORIGINAL_WINDOW,dependencyBinding:E.EXPORTS_DEPENDENCY,currentChargeBinding:E.EXPORTS_CURRENT_CHARGE,
  permittedOriginalExportCommands:E.EXPORTS_COMMANDS,originalFixtureUtcDay:FINANCE_CALENDAR.fixtureDay,
  a5SourceBindings:E.EXPORTS_A5_SOURCE_BINDINGS,a6SourceBindings:E.EXPORTS_A6_SOURCE_BINDINGS,preservedOriginalSourceCount:68,
  consolidatedSqlSha256:E.EXPORTS_SQL_SHA256,maximumRunMs:900000,maximumRequestMs:45000,ordinaryReserveMs:90000,resolutionReserveMs:45000,
  transportRetries:0,unlistedCallsAllowed:0,schedulesMustRemainPaused:true,onlyTwoExpiryFieldsMayChange:true,
  renewalOperationBundleSha256:bundleSha,operationBundleBinding:{path:OWN+'operation-bundle.draft-a1.json',sha256:bundleSha},
  exportSourceBindings:material.exportProof.sources.map(slim),renewalControllerSourceBindings:material.controllerProof.sourceBindings.map(slim),
  renewalSqlBindings:R.SQL_BINDINGS,renewalProposalBinding:{path:R.CONTROL_PATHS.proposal,sha256:R.STATIC_HASHES.proposal},
  renewalSourceRepairBinding:{path:R.CONTROL_PATHS.sourceRepair,sha256:R.STATIC_HASHES.sourceRepair},
  overallProposal:{recordedPrior:137,maximumFutureAttempts:37,cumulativeMaximum:174,healthNeedsSeparateDirectDecision:true,
   schedulerNeedsLaterExactActualWindowDecision:true,schedulerPermissionGranted:false},
  ownerApprovalRecorded:false,executionPermitted:false,additionalRequirementAcceptance:0,productionAuthorized:false,realBillingAuthorized:false};
}
async function validatePolicy(policy,material){
 // Evaluate the two exact frozen source policy predicates, without constructing
 // or persisting any alleged actual decision, metadata, profile or operation plan.
 const exportSource=(await read(E.EXPORTS_SOURCE_PATHS[0])).toString(),controllerSource=(await read(R.SOURCE)).toString();
 const extract=(source,start,end)=>{const a=source.indexOf(start),b=source.indexOf(end,a);must(a>=0&&b>a,'FROZEN_POLICY_PREDICATE_LOCATED');return source.slice(a,b+end.length);};
 const exportPredicate=extract(exportSource,"must(sourcePolicy?.kind==='source-only-export-a7-renewal-policy'","'EXACT_SOURCE_ONLY_A7_RENEWAL_POLICY_REQUIRED');");
 vm.runInNewContext(exportPredicate,{must,digest,sourcePolicy:policy,PROJECT:R.PROJECT,BUNDLE:R.BUNDLE,FINANCE_CALENDAR,sameFinanceJson:isDeepStrictEqual,
  hashBytes:hash,...E},{timeout:1000});
 const controllerPredicate=extract(controllerSource,"must(policy?.kind==='source-only-export-a7-renewal-policy'","'EXACT_REVIEWED_RENEWAL_SOURCE_POLICY_REQUIRED');");
 vm.runInNewContext(controllerPredicate,{must,digest,policy,PROJECT:R.PROJECT,RUNTIME:R.RUNTIME,BUNDLE:R.BUNDLE,BUDGET:R.BUDGET,OLD:R.OLD,
  SQL_BINDINGS:R.SQL_BINDINGS,same:isDeepStrictEqual,plan:{sourceBindings:material.controllerProof.sourceBindings.map(slim),controlBindings:{
   currentCharge:E.EXPORTS_CURRENT_CHARGE,proposal:policy.renewalProposalBinding,sourceRepair:policy.renewalSourceRepairBinding}}},{timeout:1000});
 return {exactFrozenExportPolicyPredicatePassed:true,exactFrozenControllerPolicyPredicatePassed:true,actualAuthorityObjectsConstructed:false};
}
function makeHtml(manifest,bundleSha,policySha,material){
 const sourceRows=manifest.selectedEntryPoints.map(x=>[escape(x.name),`<a href="${link(x.path)}"><code>${escape(x.path)}</code></a>`,`<code class="hash">${x.sha256}</code>`]);
 const decision1=R.OWNER_REPLY,decision2='Approve the exact single deployed V7 health readiness check with schedules paused';
 const section=(id,title,body)=>`<section id="${id}"><h2>${title}</h2>${body}</section>`;
 const sections=[
  section('summary','What this packet proposes',`<p>Finish a bounded test continuation in the existing Supabase project <code>${R.PROJECT}</code>: renew two existing test authority expiry fields, complete the two original governed exports, and then check the deployed V7 health worker. A later, separate decision is required to resume three schedules.</p><p>The system is <strong>not fully complete</strong>. This packet grants no requirement acceptance and contains no actual approval, fresh credential metadata, runtime renewal or successful export.</p><div class="notice"><strong>Unapproved source proposal.</strong> Source reviews passed. Direct human decisions, actual upstream evidence and final operation reviews remain required. Reading this page does not authorize execution.</div>`),
  section('recorded','Recorded facts — October 16',`<p>The saved database observation is <strong>${escape(material.current.actualDatabaseObservedAt)}</strong>. It is not a fresh October 17 read. Recorded state:115 migrations,363 API functions; both original authorities expired; three schedules paused; zero actual exports and worker ticks in that snapshot. Historical404 worker responses remain failure evidence.</p><div class="stats"><div><b>137</b><span>actual or conservatively charged prior calls</span></div><div><b>37</b><span>maximum proposed future attempts</span></div><div><b>174</b><span>conditional cumulative ceiling</span></div></div><p>New failed or uncertain attempts remain charged. Any extra unlisted call invalidates this exact accounting; there are no automatic retries or resets.</p>`),
  section('budget','Bounded calls and sequencing',table(['Phase','Maximum new attempts','Cumulative maximum','Condition'],[
   ['Owner readiness','1','138','Actual owner project identity GET after direct renewal approval.'],['Two-row renewal','3','141','Fresh read; one atomic expiry update; one readback.'],
   ['Two original exports','24 +1 reserved read','166','24 ordinary calls end at165; one uncertainty resolution may consume166.'],['One deployed health invocation','5','171','Separately approved; completed exports first; jobs stay paused.'],
   ['Three-job schedule resume','3','174','Later exact approval after actual renewal window and health/provider evidence exist.']].map(row=>row.map(escape)))+`<p>The worker invocation allowance is separate:24 historical requests plus one readiness invocation count toward the unchanged4,320 total ceiling. This packet does not increase existing destinations, model or spending caps.</p>`),
  section('window','Expiry and exact data scope',`<p>The proposed window is at most120minutes and ends at the earlier of the actual server preflight anchor plus120minutes or the actual fresh owner metadata expiry. Original issue times stay unchanged. The existing seven-day constraints still apply; the earliest hard limit is <strong>2026-10-20 08:13:04.144135 UTC</strong>. No fixed future timestamp is invented in this packet.</p>`+table(['Identity','Exact value'],[['Runtime',R.RUNTIME],['Tenant',R.SCOPE.tenantId],['Legal entity',R.SCOPE.legalEntityId],['Branch',R.SCOPE.branchId]].map(([a,b])=>[escape(a),`<code>${escape(b)}</code>`]))+`<p>The only renewal changes are <code>expires_at</code> on the existing one <code>runtime_worker_scopes</code> row and one <code>edge_authorities</code> row. Original issue times, all other values and hashes, schema, ACLs, key references, billing window, counters and paused jobs remain guarded. Each run is bounded to900seconds, each request45seconds, with90seconds reserved before ordinary dispatch.</p>`),
  section('exports','Two original exports and genuine worker evidence',`<p>The export continuation permits only the two original command IDs and export IDs below. It retains the original UTC13 fixture basis, independently authenticated existing actor sessions, fixed CSV filenames with exclusive creation, four existing RPC routes, registered pipeline reopening, and fresh statement-page reproduction. Earlier successful date commands are not replayed.</p>`+table(['Command ID','Export ID'],S.EXPORT_COMMANDS.map(x=>[`<code>${escape(x.commandId)}</code>`,`<code>${escape(x.exportId)}</code>`]))+`<p>Health must prove actual backend service authorization through the deployed V7 worker. An unsigned403 response, a key format, or a controlled fixture is insufficient. The scheduler additionally requires an independently reviewed actual provider result. Current product changes to <code>workers/wave5/model_runtime.mjs</code> differ from deployed V7 and are not deployed by this proposal.</p>`),
  section('local','Exact proposed local preparation',`<ol><li>Add exactly the six a6/a7 files listed in the manifest to the existing reviewed execution snapshot using exclusive creation. Verify all68 original snapshot bindings remain unchanged. Do not overwrite existing snapshot files.</li><li>Preserve the existing export adapter at its exact predecessor hash, then install only the reviewed export candidate bytes at the original fixed adapter path. Install the new management adapter exclusively at its fixed absent target path.</li><li>Use only <code>ValidateExportsA7</code>/<code>ExecuteExportsA7</code> and management targets <code>Renewal</code>, <code>Health</code>, or later <code>Scheduler</code>. Existing legacy modes remain preserved source; this packet grants no authority to replay them.</li></ol><p>No six-migration or71-migration reinstall, account deletion, profile/session reset, production activation, real billing, commit, push, reset or clean is included. All existing accounts, acceptance stores, concurrent changes and sessions remain preserved.</p>`),
  section('decisions','Separate decisions and their timing',`<article class="decision"><span class="label">Decision1 — pending</span><h3>Renewal and export continuation</h3><p>After reviewing this exact bundle, the direct reply expected by the source is:</p><blockquote>${escape(decision1)}</blockquote><p>This permits the selected local preparation, fresh owner readiness, two-row renewal, and two exports only after exact public and final-operation review gates. Jobs remain paused.</p></article><article class="decision"><span class="label">Decision2 — separately pending</span><h3>One health readiness invocation</h3><p>Proposed separate direct reply:</p><blockquote>${escape(decision2)}</blockquote><p>This decision must be recorded before the actual renewal application timestamp. It authorizes one deployed health check, at most five management attempts, after successful exports. It keeps all schedules paused and does not authorize schedule resumption.</p></article><article class="decision later"><span class="label">Decision3 — later; unavailable now</span><h3>Resume the exact three schedules</h3><p>The later direct reply required by the frozen source is:</p><blockquote>${escape(S.SCHEDULE_REPLY)}</blockquote><p><strong>A reply now cannot satisfy this gate.</strong> The decision must be made after the actual renewal window exists and bind that exact window, source hashes and budget. Actual completed exports and independently reviewed health/provider evidence must also exist. Its timestamp must be at or after the genuine renewal application time. A new final operation review then permits at most three scheduler requests for jobs4,5,6. Never fabricate a later decision time.</p></article><p>These are runtime permission decisions, not acceptance of any remaining accounting requirement. The HTML has no approval submission or credential form.</p>`),
  section('checks','Source checks and remaining gates',table(['Evidence','Recorded result'],[
   ['Renewal controller','115/115 controlled tests; independent source review passed.'],['Export a7','124/124 controlled tests; exact original source preservation checked.'],
   ['Export adapter a3','10/10 source/race tests and AST review passed.'],['Management adapter a2','14/14 source tests and exact AST review passed.'],
   ['Health/scheduler entrypoints','27/27 controlled tests; actual provider and delivery gates remain open.']].map(r=>r.map(escape)))+`<p>Every run checks public source hashes before private input. The adapters hold read-only file handles that deny replacement from before public preflight through child exit. Raw responses are persisted before validation; uncertain writes receive at most the reserved read and are never blindly replayed.</p><p>Still required: root policy review and publication, direct decisions, genuine fresh A10 metadata, actual generated plans and final reviews, actual renewal and exports, deployed worker/provider evidence, later schedule decision, delivery and receiver receipts, authenticated native/keyboard checks, independent-session contention, target-scale load and requirement-by-requirement acceptance.</p>`),
  section('sources','Exact selected sources',table(['Role','Path','SHA-256'],sourceRows)+`<p>The complete manifest also pins imported modules, exact a3 SQL, all68 original snapshot bindings,39 deployed archive files, prior evidence and both adapter reviews. These inventories are preserved separately from current product candidates.</p>`),
  section('packet','Packet identity and evidence',`<p>Operation bundle SHA-256:</p><pre id="bundle">${bundleSha}</pre><p>Draft source-policy SHA-256:</p><pre>${policySha}</pre><p>The operation hash covers the fixed manifest bytes. The policy and HTML are derived from it and excluded from that hash to avoid a self-reference cycle.</p><ul><li><a href="${link(OWN+'operation-bundle.draft-a1.json')}">Exact operation manifest</a></li><li><a href="${link(OWN+'source-policy.draft-a1.json')}">Source-policy draft — not the published fixed policy</a></li>${material.reviewBindings.map(x=>`<li><a href="${link(x.path)}">${escape(x.name)} independent source review</a></li>`).join('')}<li><a href="${link(E.EXPORTS_CURRENT_CHARGE.path)}">Recorded137 accounting and raw evidence bindings</a></li></ul><p class="muted">Prepared as a source-only proposal on ${escape(manifest.preparedAt)}. No private input or live action was used to create this page. Full-project completion is not claimed.</p>`)
 ];
 const titles=[['summary','Summary'],['recorded','Recorded facts'],['budget','Call limits'],['window','Window & scope'],['exports','Export & worker gates'],['local','Local preparation'],['decisions','Three decisions'],['checks','Checks & remaining gates'],['sources','Exact sources'],['packet','Packet identity']];
 return `<!doctype html><html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><meta http-equiv="Content-Security-Policy" content="default-src 'none'; style-src 'unsafe-inline'; script-src 'unsafe-inline'; base-uri 'none'; form-action 'none'"><title>Jentra OS · Runtime Continuation Review ·17 October2026</title><style>
 :root{color-scheme:light;--ink:#17283b;--muted:#526273;--line:#d9e2e8;--nav:#132c36;--accent:#086a63;--paper:#fff;--wash:#f2f6f7;--warning:#754b06}*{box-sizing:border-box}body{margin:0;background:var(--wash);color:var(--ink);font:16px/1.65 'Segoe UI',Arial,sans-serif}a{color:#075e68;text-underline-offset:3px}a:hover{text-decoration-thickness:2px}a:focus-visible,summary:focus-visible{outline:3px solid #b65d00;outline-offset:4px}.skip{position:absolute;left:20px;top:-80px;background:white;padding:12px;z-index:10}.skip:focus{top:12px}.shell{display:grid;grid-template-columns:250px minmax(0,1fr);max-width:1560px;margin:auto}aside{position:sticky;top:0;height:100vh;background:var(--nav);padding:32px 24px;color:#fff}aside strong{font-size:23px;letter-spacing:.05em}aside p{color:#cee1e3;font-size:13px}nav a{display:block;color:#e4eeee;padding:7px 0;text-decoration:none;font-size:14px}nav a:hover,nav a.active{color:#fff;text-decoration:underline}main{padding:48px 6%;min-width:0}header{border-bottom:1px solid var(--line);padding-bottom:28px;margin-bottom:32px}.eyebrow{font-size:12px;letter-spacing:.13em;color:var(--accent);font-weight:800;text-transform:uppercase}h1{font-size:clamp(32px,4vw,50px);line-height:1.12;letter-spacing:-.035em;margin:12px 0 20px}header p{max-width:780px}.status{display:inline-flex;gap:8px;align-items:center;background:#fff0d7;color:var(--warning);border:1px solid #e5c58e;border-radius:30px;padding:7px 13px;font-size:13px;font-weight:700}section{background:var(--paper);border:1px solid var(--line);border-radius:10px;padding:28px 32px;margin:24px 0;scroll-margin-top:20px}h2{font-size:24px;line-height:1.3;margin:0 0 18px}h3{font-size:19px;line-height:1.35;margin:9px 0}p{margin:12px 0}code{font:12px/1.55 Consolas,monospace;overflow-wrap:anywhere;background:#edf4f5;padding:2px 4px;border-radius:3px}pre{font:12px/1.6 Consolas,monospace;overflow-wrap:anywhere;white-space:pre-wrap;background:#edf4f5;padding:16px;border-radius:6px}.hash{font-size:11px}.table-wrap{overflow:auto}table{border-collapse:collapse;width:100%;font-size:14px}td,th{text-align:left;padding:12px 10px;border-bottom:1px solid var(--line);vertical-align:top}th{color:#334c5b;background:#eef4f5;font-size:12px;text-transform:uppercase;letter-spacing:.03em}.stats{display:grid;grid-template-columns:repeat(3,1fr);gap:12px;margin:24px 0}.stats div{padding:18px;border:1px solid var(--line);border-radius:7px;background:#f7fafb}.stats b{display:block;font-size:35px;line-height:1.2;color:var(--accent)}.stats span{display:block;font-size:13px;margin-top:7px}.notice{border-left:4px solid #b77811;background:#fff7e7;padding:16px 18px;margin:20px 0}.decision{padding:20px;border:1px solid var(--line);border-left:4px solid var(--accent);border-radius:6px;margin:18px 0}.decision.later{border-left-color:#ac7116;background:#fffaf1}.label{font-size:12px;font-weight:800;letter-spacing:.06em;text-transform:uppercase;color:#526273}blockquote{margin:16px 0;padding:14px 16px;background:#edf4f5;border-left:3px solid #6d9b9a;font-weight:600}li{margin:9px 0}.muted{font-size:13px;color:var(--muted)}footer{font-size:13px;color:var(--muted);padding:20px 0}@media(max-width:980px){.shell{grid-template-columns:1fr}aside{position:static;height:auto;padding:22px}nav{display:flex;flex-wrap:wrap;gap:8px 20px}nav a{font-size:12px}main{padding:28px 4%}section{padding:22px}.stats{grid-template-columns:1fr}}@media print{aside,.skip{display:none}.shell{display:block}main{padding:0}section{break-inside:avoid;border-color:#ccc}a{color:inherit}body{background:white}.status{border:1px solid #999}}
 </style></head><body><a class="skip" href="#content">Skip to review</a><div class="shell"><aside><strong>JENTRA OS</strong><p>Runtime continuation<br>17 October2026 · r5</p><nav aria-label="Review sections">${titles.map(([id,title])=>`<a href="#${id}">${title}</a>`).join('')}</nav></aside><main id="content"><header><span class="eyebrow">Source review · bounded test continuation</span><h1>A precise next step.<br>Separate evidence gates.</h1><p>Renew the expired test window, finish the two governed exports, and verify the existing worker before any later schedule decision.</p><span class="status" role="status">○ Unapproved · no execution authority recorded</span></header>${sections.join('')}<footer>Jentra OS · Source-only review packet · No credentials, approval submission, external assets or tracking.</footer></main></div><script>const links=[...document.querySelectorAll('nav a')];const observer=new IntersectionObserver(items=>{for(const item of items)if(item.isIntersecting){links.forEach(a=>a.classList.toggle('active',a.hash==='#'+item.target.id));}},{rootMargin:'-10% 0px -70% 0px'});document.querySelectorAll('section[id]').forEach(s=>observer.observe(s));</script></body></html>`;
}
async function main(){
 must(process.argv[2]==='--build'&&process.argv.length===3,'SOURCE_PACKET_BUILD_MODE_REQUIRED');
 const outputs=[OWN+'operation-bundle.draft-a1.json',OWN+'source-policy.draft-a1.json',OWN+'packet-validation-a1.json',HTML];
 for(const p of outputs){try{await fs.access(path.join(ROOT,p));throw Error('EXCLUSIVE_OUTPUT_EXISTS:'+p);}catch(e){if(e.code!=='ENOENT')throw e;}}
 const material=await load(),preparedAt=new Date().toISOString();
 const newSnapshotFiles=[...E.EXPORTS_A6_SOURCE_BINDINGS,...material.exportProof.sources.map(slim)].map(row=>({...row,target:SNAPSHOT+row.path,creationMode:'wx'}));
 for(const row of newSnapshotFiles)try{await fs.access(path.join(ROOT,row.target));throw Error('SNAPSHOT_ADDITION_ALREADY_EXISTS:'+row.target);}catch(e){if(e.code!=='ENOENT')throw e;}
 try{await fs.access(path.join(ROOT,R.PRIVATE_ADAPTER));throw Error('MANAGEMENT_TARGET_ALREADY_EXISTS');}catch(e){if(e.code!=='ENOENT')throw e;}
 const selectedEntryPoints=[['Renewal controller',R.SOURCE],['Export a7',E.EXPORTS_SOURCE_PATHS[0]],['Export public preparer',E.EXPORTS_SOURCE_PATHS[1]],
  ['Health launcher',H.LAUNCHER],['Health core','tools/wave5/probe_worker_v7_health_20261014_r5.mjs'],['Scheduler',S.SOURCE],
  ['Owner refresh A10',R.OWNER_REFRESH_HELPER.path],['Export adapter candidate',material.exportAdapter.candidate.path],['Management adapter candidate',material.managementAdapter.candidate.path]]
  .map(([name,p])=>({name,...seen.get(p)}));
 const manifest={kind:'unapproved-source-only-runtime-continuation-operation-bundle',version:1,preparedAt,projectId:R.PROJECT,runtimeId:R.RUNTIME,runtimeBundleSha256:R.BUNDLE,
  sourceOnly:true,approvalRecorded:false,executionPermitted:false,actualStateObservedAt:material.current.actualDatabaseObservedAt,actualPriorCharge:137,
  recordedCurrentChargeBinding:E.EXPORTS_CURRENT_CHARGE,proposedBudget:material.inventory.arithmetic,unchangedWorkerBounds:material.inventory.unchangedWorkerBounds,
  maximumWindowMs:7200000,expiryFormula:'min(actual server preflight anchor +120 minutes, actual owner metadata expiry)',originalWindow:R.OLD,
  issuedAtMaximumWindowMs:604800000,earliestExistingHardExpiry:'2026-10-20T08:13:04.144135+00:00',maximumRunMs:900000,maximumRequestMs:45000,
  ordinaryReserveMs:90000,resolutionRequestReserveMs:45000,scope:R.SCOPE,onlyRenewalDatabaseChanges:['intelligence_control.runtime_worker_scopes.expires_at: exact existing row','intelligence_control.edge_authorities.expires_at: exact existing row'],
  exportCommands:E.EXPORTS_COMMANDS,exportIdentifiers:S.EXPORT_COMMANDS,originalFixtureUtcDay:FINANCE_CALENDAR.fixtureDay,consolidatedExportSqlSha256:E.EXPORTS_SQL_SHA256,
  renewalSqlBindings:R.SQL_BINDINGS,selectedEntryPoints,
  localPreparationOnlyAfterExactApproval:{newSnapshotFiles,originalSnapshotBindingsPreserved:68,exportAdapter:{candidate:material.exportAdapter.candidate,target:material.exportAdapter.predecessor.path,
   predecessor:material.exportAdapter.predecessor,archiveOriginalBeforeReplacement:true,allowedModes:['ValidateExportsA7','ExecuteExportsA7']},
   managementAdapter:{candidate:material.managementAdapter.candidate,target:R.PRIVATE_ADAPTER,targetMustBeAbsent:true,creationMode:'wx',allowedTargets:['Renewal','Health','Scheduler']},
   legacyModeReplayAuthorized:false,newSourceCopiesPerformed:false,adapterInstallPerformed:false},
  decisions:{renewalAndExports:{required:true,recorded:false,exactReply:R.OWNER_REPLY,recordMustFollowExactIndependentPolicyReview:true},
   health:{requiredSeparately:true,recorded:false,maximumManagementAttempts:5,maximumInvocations:1,keepsSchedulesPaused:true,mustBeDecidedBeforeActualRenewalApplication:true,
    proposedReply:'Approve the exact single deployed V7 health readiness check with schedules paused'},
   scheduler:{requiredLater:true,recorded:false,exactReply:S.SCHEDULE_REPLY,mayNotBePreauthorizedNow:true,mustBindActualWindow:true,
    decisionAtOrAfterActualRenewalApplication:true,completedExportsAndActualHealthProviderReviewRequired:true,maximumManagementAttempts:3,exactJobIds:[4,5,6]}},
  sourceReviews:material.reviewBindings,preservedOriginalSnapshotBindings:material.original68,preservedWorkflowEvidence:material.preservedWorkflow,
  deployedV7ArchiveBindings:material.archive39,currentProductCandidateObservedSeparately:seen.get('workers/wave5/model_runtime.mjs'),productDeploymentAuthorized:false,
  sourceAndEvidenceBindings:[...seen.values()].sort((a,b)=>a.path.localeCompare(b.path)),
  exclusions:['No migration reinstall or replay, including original six and71 migrations','No account deletion or session/profile reset','No production or real billing','No commit, push, reset, clean, broad staging or unrelated source overwrite','No additional requirement acceptance','No new model/destination/spending caps','No complete-system claim'],
  hashDefinition:'SHA-256 of exact UTF-8 bytes of this JSON file, including final newline; derived policy and HTML excluded to avoid a hash cycle'};
 const manifestBytes=json(manifest),bundleSha=hash(manifestBytes),policy=policyFor(bundleSha,material),policyBytes=json(policy),policySha=hash(policyBytes);
 const validation=await validatePolicy(policy,material),html=makeHtml(manifest,bundleSha,policySha,material);
 must(!/https?:\/\/|<form\b|fetch\(|XMLHttpRequest|localStorage|password|sbp_[a-z0-9]/i.test(html),'SELF_CONTAINED_NONCREDENTIAL_HTML_REQUIRED');
 must(html.includes('A reply now cannot satisfy this gate.')&&html.includes(bundleSha)&&html.includes(policySha),'EXPLICIT_LATER_SCHEDULER_GATE_REQUIRED');
 for(const b of seen.values())must(hash(await read(b.path))===b.sha256,'INPUT_CHANGED_DURING_PACKET_ASSEMBLY:'+b.path);
 const protectedAbsent=[R.PLAN,R.REVIEW,R.ONCE,R.READBACK,R.CONTROL_PATHS.ownerDecision,R.CONTROL_PATHS.metadata,R.CONTROL_PATHS.refresh,E.EXPORTS_PROFILE,E.EXPORTS_FINAL_REVIEW,E.EXPORTS_PROFILE_PATHS.sourcePolicy,E.EXPORTS_PROFILE_PATHS.independentReview,H.OPERATION_DECISION,S.PLAN,S.REVIEW,S.ONCE];
 for(const p of protectedAbsent)try{await fs.access(path.join(ROOT,p));throw Error('UNEXPECTED_ACTUAL_OR_FIXED_RECORD:'+p);}catch(e){if(e.code!=='ENOENT')throw e;}
 await fs.writeFile(path.join(ROOT,outputs[0]),manifestBytes,{flag:'wx'});await fs.writeFile(path.join(ROOT,outputs[1]),policyBytes,{flag:'wx'});await fs.writeFile(path.join(ROOT,HTML),html,{flag:'wx'});
 const proof={kind:'source-only-runtime-review-packet-validation',preparedAt,passed:true,...validation,operationBundle:{path:outputs[0],sha256:bundleSha,bytes:manifestBytes.length},
  policyDraft:{path:outputs[1],sha256:policySha,bytes:policyBytes.length},html:{path:HTML,sha256:hash(html),bytes:Buffer.byteLength(html)},
  boundInputsVerifiedUnchanged:seen.size,originalSnapshotBindings:68,deployedArchiveBindings:39,newSnapshotAdditionsProposed:6,sourceReviewsPassed:3,
  actualStateObservationDate:material.current.actualDatabaseObservedAt,actualPrior137:true,maxFuture37:true,proposedMaximum174:true,
  protectedRecordsCheckedAbsent:protectedAbsent,externalHtmlAssets:0,approvalForm:false,actualLiveCalls:0,privateInputsRead:false,
  ownerApprovalCreated:false,actualMetadataCreated:false,profileCreated:false,executionPlanCreated:false,finalOperationReviewCreated:false,intentCreated:false,
  snapshotFilesCopied:false,adaptersInstalled:false,acceptanceChanged:false,production:false,realBilling:false,rootPolicyReviewAndPublicationPending:true};
 await fs.writeFile(path.join(ROOT,outputs[2]),json(proof),{flag:'wx'});
 process.stdout.write(JSON.stringify({passed:true,operationBundle:proof.operationBundle,policyDraft:proof.policyDraft,html:proof.html,validation:{path:outputs[2],sha256:hash(json(proof))},boundInputs:seen.size})+'\n');
}
if(process.argv[1]&&path.resolve(process.argv[1])===fileURLToPath(import.meta.url))main().catch(error=>{process.stderr.write(error.message+'\n');process.exitCode=1;});
