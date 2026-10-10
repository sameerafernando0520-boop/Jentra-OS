// New public-artifact runtime review preparation only. Default check writes nothing.
// Never installs SQL, creates accounts, reads secrets, deploys, launches SDK/OS,
// submits approval, signs acceptance, or changes a prior review/source/image.
import {lstat,open,readFile,readdir,realpath} from 'node:fs/promises';
import {createHash} from 'node:crypto';
import path from 'node:path';
import {fileURLToPath} from 'node:url';
import {isDeepStrictEqual} from 'node:util';
import {sources} from './cash_ui_evidence.mjs';
import {readZipEntries,zipEntryBytes} from './record_continuation_windows.mjs';
import {verifyExecution,verifierProvenance} from './accounting_execution_verifier_20261010_r3.mjs';

const root=path.resolve(path.dirname(fileURLToPath(import.meta.url)),'../..'),base='docs/verification/wave5/';
const mode=process.argv[2]??'check';
if(process.argv.length>3||!['check','compose'].includes(mode))throw Error('CHECK_OR_COMPOSE_ONLY');
const self='scripts/wave5/prepare_current_runtime_review_20261010_r3_a2.mjs',projectId='xpdoufauvrbdmxgngetv';
const p={original:base+'complete-app-runtime-review-20261009.json',r13:base+'complete-app-runtime-review-20261009-r13.json',
  readiness:base+'current-runtime-review-readiness-20261010-r2.json',source:base+'golden-review-postapproval-source-20261010-r2.json',
  full:base+'golden-review-approvedAll-20261010-r2.json',matrix:base+'requirement-matrix-20261008.json',
  accountingSource:base+'accounting-checks-source-20261010-r2.json',accountingMd:base+'accounting-checks-result-20261010-r2.md',
  acceptAfter:base+'owner-criterion-acceptance-after-20261010-r2-serial.json',acceptOwner:base+'owner-criterion-decision-20261010-r2.json',
  promotion:base+'golden-promotion-result-20261010-r2.json',imageOwner:base+'owner-golden-decision-20261010-r2.json',
  live:base+'complete-live-preflight-20261010-r3-summary.json',liveIndex:base+'complete-live-preflight-20261010-r3-index.json',
  late:base+'complete-live-preflight-20261010-r3-late-summary.json',lateIndex:base+'complete-live-preflight-20261010-r3-late-index.json',
  component:base+'continuation-worker-component-20261009-r14.json',workerAdapter:base+'current-runtime-worker-adapter-20261010-r3.json',
  native:base+'windows-test-verification-20261010-r3.json',nativeMd:base+'windows-test-verification-20261010-r3.md',
  nativePreview:base+'native-preview-userflows-20261010-r3.json',nativePreviewMd:base+'native-preview-userflows-20261010-r3.md',
  nativePostStorage:base+'windows-userflow-storage-after-20261010-r3.json',
  statusBefore:base+'current-verification-status-before-20261010-r3-guarded.json',statusAfter:base+'current-verification-status-after-20261010-r3-guarded.json',
  finalHandoff:'docs/development/wave5-next-session-20261010-r2.md',
  preview:base+'windows-test-preview-package-20261010-r3.json',connected:base+'windows-test-connected-package-20261010-r3.json',
  review:base+'complete-app-runtime-review-20261010-r3.json',markdown:base+'complete-app-runtime-review-20261010-r3.md',
  result:base+'complete-app-runtime-composition-result-20261010-r3.json'};
const originals={original:{fileSha256:'3af2dc69e77c37b939cdd02e27860261e36899b95aa68016b0f0703970de565f',bundleSha256:'13ffe2fdfd412fae36d3ff08c1f33bb59d9de85f20b2707e77ba6b9629eae83e'},
  r13:{fileSha256:'97c0d0d29b706b1d1283e2408e4ed9b9622b1ef0a4ab2ddae8dec099fe5cf208',bundleSha256:'92a68a58d70a1f9061776be1b6416b8124112577b0a0859ed6f389becc2533d4'}};
const sha=b=>createHash('sha256').update(b).digest('hex'),eq=(a,b)=>JSON.stringify(a)===JSON.stringify(b);
const must=(c,m)=>{if(!c)throw Error(m);},parse=b=>JSON.parse(b.toString('utf8').replace(/^\uFEFF/,''));
const logText=b=>b.length>=2&&b[0]===0xff&&b[1]===0xfe?b.subarray(2).toString('utf16le'):b.toString('utf8').replace(/^\uFEFF/,'');
function relative(file){
  must(typeof file==='string'&&file.length>0,'PATH_REQUIRED');
  const absolute=path.isAbsolute(file)?path.resolve(file):path.resolve(root,file),rel=path.relative(root,absolute);
  must(rel&&rel!=='..'&&!rel.startsWith('..'+path.sep)&&!path.isAbsolute(rel),'PATH_ESCAPES_WORKSPACE:'+file);
  return rel.split(path.sep).join('/');
}
async function bytes(file){
  const rel=relative(file),absolute=path.join(root,rel),stat=await lstat(absolute),resolved=relative(await realpath(absolute));
  must(stat.isFile()&&!stat.isSymbolicLink()&&resolved===rel,'REGULAR_UNLINKED_INPUT_REQUIRED:'+rel);return readFile(absolute);
}
async function exists(file){try{await lstat(path.join(root,relative(file)));return true;}catch(e){if(e.code==='ENOENT')return false;throw e;}}
async function inventory(directory){
  const rel=relative(directory),absolute=path.join(root,rel),stat=await lstat(absolute);
  must(stat.isDirectory()&&!stat.isSymbolicLink()&&relative(await realpath(absolute))===rel,'REGULAR_UNLINKED_DIRECTORY_REQUIRED:'+rel);
  const result=[];
  async function walk(current){
    for(const entry of await readdir(current,{withFileTypes:true})){
      must(!entry.isSymbolicLink(),'NATIVE_DIRECTORY_LINK_REFUSED');const file=path.join(current,entry.name);
      if(entry.isDirectory())await walk(file);else{must(entry.isFile(),'REGULAR_NATIVE_FILE_REQUIRED');const b=await bytes(relative(file));result.push({path:path.relative(absolute,file).split(path.sep).join('/'),sha256:sha(b),bytes:b.length});}
    }
  }
  await walk(absolute);return result.sort((x,y)=>x.path.localeCompare(y.path));
}
function runtimeScope(review){
  const c=structuredClone(review.workerConfiguration);delete c.nativeIsolation.connectedBuildManifest;delete c.nativeIsolation.windowsSourceRevision;delete c.nativeIsolation.verifiedReleaseEntries;
  const execution=structuredClone(review.execution);
  execution.ownerAcceptance.criteria=execution.ownerAcceptance.criteria.map(({id})=>({id}));delete execution.ownerAcceptance.sharedGoldenFailures;
  delete execution.ownerAcceptance.currentAcceptedBeforeRuntimeApproval;delete execution.ownerAcceptance.wholeSystemSignoff;
  return{projectId:review.projectId,accounts:review.accounts,roles:review.roles,assignments:review.assignments,syntheticPlans:review.syntheticPlans,
    syntheticScopes:review.syntheticScopes,bootstrap:review.bootstrap,workerConfiguration:c,execution,migrations:review.migrations,
    exclusions:review.exclusions,privateProvisioning:review.privateProvisioning};
}
function connectorRows(raw){
  const blocks=raw?.content?.filter(c=>c.type==='text')??[];must(raw?.isError!==true&&blocks.length===1,'SAVED_CONNECTOR_RESULT_INVALID');
  const wrapper=JSON.parse(blocks[0].text),text=wrapper.result;must(typeof text==='string','SAVED_CONNECTOR_WRAPPER_INVALID');
  const matches=[...text.matchAll(/^<untrusted-data-([A-Za-z0-9-]+)>\r?\n([\s\S]*?)\r?\n<\/untrusted-data-\1>\r?$/gm)];
  must(matches.length===1,'EXACT_SAVED_CONNECTOR_DATA_BOUNDARY_REQUIRED');return JSON.parse(matches[0][2]);
}
function plainConnector(raw){const blocks=raw?.content?.filter(c=>c.type==='text')??[];must(raw?.isError!==true&&blocks.length===1,'EXACT_PLAIN_CONNECTOR_RESULT_REQUIRED');return JSON.parse(blocks[0].text);}
function imageDimensions(b){
  if(b.subarray(0,8).equals(Buffer.from([137,80,78,71,13,10,26,10]))){must(b.length>=24,'PNG_HEADER_INCOMPLETE');return{width:b.readUInt32BE(16),height:b.readUInt32BE(20)};}
  must(b.length>4&&b[0]===255&&b[1]===216,'SUPPORTED_NATIVE_IMAGE_REQUIRED');
  let i=2;while(i<b.length){must(b[i]===255,'JPEG_MARKER_INVALID');while(b[i]===255)i++;const marker=b[i++];if(marker===217||marker===218)break;if(marker===1||marker>=208&&marker<=215)continue;
    must(i+2<=b.length,'JPEG_SEGMENT_INCOMPLETE');const length=b.readUInt16BE(i);must(length>=2&&i+length<=b.length,'JPEG_SEGMENT_LENGTH_INVALID');
    if([192,193,194,195,197,198,199,201,202,203,205,206,207].includes(marker)){must(length>=8,'JPEG_FRAME_INCOMPLETE');return{width:b.readUInt16BE(i+5),height:b.readUInt16BE(i+3)};}i+=length;
  }throw Error('JPEG_DIMENSIONS_NOT_FOUND');
}
function concreteScopeMarkdown(a,configuration){
  const code=value=>'```json\n'+JSON.stringify(value,null,2)+'\n```\n',cell=value=>String(value).replaceAll('|','\\|').replaceAll('\n',' ');
  const migrationRows=a.prior.migrations.map(m=>`| ${m.order} | ${cell(m.owner)} | [${path.posix.basename(m.path)}](../../../${m.path}) | \`${m.sha256}\` |`).join('\n');
  const ledgerRows=a.late.originalSixLedger.preservedEntries.map(m=>`| [${path.posix.basename(m.sourcePath)}](../../../${m.sourcePath}) | \`${m.ledgerEntry.version}\` |`).join('\n');
  const accounts=a.prior.accounts.map(ac=>`| ${cell(ac.label)} | \`${ac.email}\` | ${ac.mainRoles.map(cell).join(', ')||'None'} | ${ac.loadRoles.map(cell).join(', ')||'None'} |`).join('\n');
  const plans=a.prior.syntheticPlans.map(plan=>`| \`${plan.code}\` | ${plan.trialDays} | ${plan.seats} | \`${cell(JSON.stringify(plan.entitlements))}\` |`).join('\n');
  return `\n## Exact operations requested after separate owner approval\n\n${a.prior.execution.stages.map((s,i)=>`${i+1}. ${s}`).join('\n')}\n\n## Additional migrations, in execution order\n\nInstall only these 71 exact hashed files once. Record the actual connector-assigned ledger versions. The approved six listed below remain excluded.\n\n| Order | Owner | Source | SHA-256 |\n| --- | --- | --- | --- |\n${migrationRows}\n\n## Installed-six preservation\n\nThe saved late connector batch (read context recorded at ${a.lateContext.recordedAt}) reread all 43 ledger rows and matched each original name/version pair exactly against the installation result. These six files were not reinstalled or replayed. The SQL server observation at ${a.late.observedAt} has its own exact timestamp; the list tool does not expose a separate server timestamp.\n\n| Excluded source | Actual preserved connector version |\n| --- | --- |\n${ledgerRows}\n\n## New Auth Admin accounts and scoped bootstrap\n\nCreate only these six confirmed password-login labels through private owner Auth Admin context. Each real returned Auth ID must bind \`jentra.w5.created_auth_ids\`; collision means abort. No direct \`auth.users\` insertion, adoption/deletion of existing labels or email delivery is included. Passwords and TOTP material remain solely in the reviewed private credential store; no value appears in this review.\n\n| Label | New exact email | Main roles | Load roles |\n| --- | --- | --- | --- |\n${accounts}\n\nThe exact 500 tenant/entity/branch UUID scopes, 1,003 roles and 2,003 assignments are in the machine review. Only the runtime and load-001 scopes allow synthetic activation. The operator has no business membership; its runtime-only authority expires after 45 minutes and genuine-MFA tenant grants after at most 30 minutes. Existing acceptance accounts, role assignments, stores, sessions and the separate desktop-test login remain untouched.\n\nBootstrap bounds and exact source caps:\n\n${code(a.prior.bootstrap)}\nFour new synthetic plans only; no real billing collection:\n\n| Exact code | Trial days | Seats | Entitlements |\n| --- | --- | --- | --- |\n${plans}\n\n## Hosted workers, model, native target and private references\n\nThe following exact public configuration and private reference names are the unchanged operation scope. No secret value is present. Two exact 14/8-file payloads target the already-selected Supabase project. The three named jobs expire with the 24-hour scope; maximum 4,320 scheduled requests. The model permits four persistent invocations, at most 2,000 reserved tokens each and 8,000 total, with numeric projection only and no tools/background/store. The native target is the original new standard local profile; compilation into distinct product directories on the shared owner account does not provision that profile.\n\n${code(configuration)}\n## Contention and target-scale load\n\nThese real independent-session effects are separately verified after approval; controlled tests and package compilation cannot satisfy them. Host/Auth limits must be recorded as incomplete, never bypassed with fabricated claims or global setting changes.\n\n${code({contention:a.prior.execution.contention,load:a.prior.execution.load})}\n## Private access and exclusions\n\n${code({privateProvisioning:a.prior.privateProvisioning,exclusions:a.prior.exclusions})}`;
}
async function audit(){
  const bound=new Map(),missing=[];
  async function bind(file,expected){const rel=relative(file),b=await bytes(rel),h=sha(b);must((!expected||h===expected)&&(!bound.has(rel)||bound.get(rel)===h),'BOUND_INPUT_DRIFT:'+rel);bound.set(rel,h);return b;}
  const json=async(file,h)=>parse(await bind(file,h));
  const refs=async values=>{for(const r of values)await bind(r.path,r.sha256);};
  const original=await json(p.original,originals.original.fileSha256),prior=await json(p.r13,originals.r13.fileSha256),readiness=await json(p.readiness);
  for(const [key,review]of [['original',original],['r13',prior]]){
    const {bundleSha256,...body}=review;must(bundleSha256===originals[key].bundleSha256&&sha(Buffer.from(JSON.stringify(body)))===bundleSha256&&review.ownerApproved===false&&review.projectId===projectId,'PRESERVED_REVIEW_INVALID:'+key);
    must(review.migrations?.length===71&&new Set(review.migrations.map(m=>m.path)).size===71&&review.migrations.every((m,i)=>m.order===i+1&&m.installed===false),'EXACT71_ORDERED_MIGRATIONS_REQUIRED');
  }
  must(eq(runtimeScope(original),runtimeScope(prior)),'PRIOR_RUNTIME_OPERATION_SCOPE_CHANGED');
  const scope=runtimeScope(prior),scopeSha256=sha(Buffer.from(JSON.stringify(scope)));
  must(prior.accounts.length===6&&new Set(prior.accounts.map(a=>a.email)).size===6&&prior.accounts.every(a=>a.authId===null)&&prior.syntheticScopes.length===500&&prior.syntheticPlans.length===4&&prior.workerConfiguration.secrets.newVaultNames.length===3&&prior.workerConfiguration.schedulers.exactJobNames.length===3&&prior.execution.load.concurrentSessions===2000,'EXACT_RUNTIME_BOUNDS_CHANGED');
  must(prior.workerConfiguration.nativeIsolation.windowsAccount==='jentra-w5-runtime'&&prior.workerConfiguration.nativeIsolation.packageDirectory==='C:\\Users\\Public\\Documents\\JentraWave5Runtime\\20261009'&&prior.workerConfiguration.nativeIsolation.provisioned===false&&prior.workerConfiguration.model.approved===false,'ORIGINAL_PRIVATE_TARGET_CHANGED');
  await refs(prior.migrations);await refs(prior.artifacts);
  // Every legacy mismatch is the exact already-reviewed r13 change, not a free allowance.
  const drift=[];
  for(const a of original.artifacts){const current=sha(await bytes(a.path));if(current!==a.sha256)drift.push({path:a.path,originalSha256:a.sha256,currentSha256:current});}
  must(eq(drift,prior.sourceContinuation.originalArtifactDrift),'UNREVIEWED_ORIGINAL_ARTIFACT_DRIFT');
  must(readiness.currentRuntimeApprovalReady===false&&readiness.runtimeApproval===false&&readiness.workers.allInputsAndPayloadsMatch===true&&readiness.workers.sourceInputs===26&&readiness.workers.controlledTests===71,'HISTORICAL_READINESS_BOUNDARY_CHANGED');
  const source=await json(p.source),full=await json(p.full),matrix=await json(p.matrix),accept=await json(p.acceptAfter),acceptOwner=await json(p.acceptOwner),promotion=await json(p.promotion),imageOwner=await json(p.imageOwner);
  must(source.kind==='postapproval_desktop1068_source_manifest'&&source.selectedSources===1068&&Object.keys(source.sourceHashes).length===1068&&source.sourceInputsSha256===sha(Buffer.from(JSON.stringify(source.sourceHashes))),'FINAL1068_SOURCE_REQUIRED');
  must(full.stage==='approvedAll'&&full.status==='complete'&&full.fullSuitePassed===true&&full.exitCode===0&&full.integrityError===null&&full.spawnError===null&&eq(full.counts,{passed:2004,failed:0,skipped:0})&&eq(full.sourceManifest,{path:p.source,sha256:bound.get(p.source)}),'FINAL2004_RUN_REQUIRED');
  const fullRaw=await bind(full.log,full.logSha256),desktopFiles=[...new Set(source.expectedTestIdentities.map(id=>'test/'+id.slice(0,id.indexOf(': '))))].sort();
  const actual=verifyExecution(fullRaw,source.workingDirectory,desktopFiles,0);
  must(actual.identities.length===2004&&eq(actual.identities.map(id=>id.slice(5)),source.expectedTestIdentities)&&eq(full.actualTestIdentities,source.expectedTestIdentities),'ACTUAL_UNIQUE2004_IDENTITIES_REQUIRED');
  for(const a of [full.inputAuditBefore,full.inputAuditAfter])must(a?.selectedSources===1068&&a.currentSourceMatchesApprovedInputs===true&&a.warmSourceMatchesApprovedInputs===true&&eq(a.sourceHashes,source.sourceHashes)&&eq(a.toolchain,source.toolchain),'FINAL2004_INPUT_AUDIT_CHANGED');
  await refs(source.bindings);
  const priorSource=await json(source.priorSourceManifest.path,source.priorSourceManifest.sha256),select=h=>Object.fromEntries(Object.entries(h).filter(([f])=>['pubspec.yaml','pubspec.lock','analysis_options.yaml'].includes(f)||priorSource.dependencyScope.some(s=>f.startsWith(s+'/'))||/^apps\/[^/]+\/pubspec.yaml$/.test(f)));
  const [current,warm]=await Promise.all([sources(root),sources(source.snapshot)]);must(eq(select(current),source.sourceHashes)&&eq(select(warm),source.sourceHashes),'CURRENT_OR_WARM1068_SOURCE_DRIFT');
  await refs(Object.entries(source.sourceHashes).map(([path,sha256])=>({path,sha256})));
  for(const t of source.toolchain.tooling)must(sha(await readFile(t.path))===t.sha256,'CACHED_SDK_TOOL_DRIFT:'+t.path);
  const accountingSource=await json(p.accountingSource),accounting=[];await bind(p.accountingMd);
  must(accountingSource.kind==='accounting_calculation_gateway_source_manifest'&&eq(accountingSource.sourceManifest,{path:p.source,sha256:bound.get(p.source)})&&eq(accountingSource.sourceHashes,source.sourceHashes)&&accountingSource.selectedSources===1068&&eq(accountingSource.toolchain,source.toolchain)&&accountingSource.stages.length===2&&eq(accountingSource.stages.map(s=>[s.stage,s.files.length]),[['domain',16],['platform',22]]),'FROZEN_ACCOUNTING38_SOURCE_SCOPE_REQUIRED');
  await refs(accountingSource.bindings);
  for(const r of accountingSource.resolution)await bind(relative(path.join(accountingSource.snapshot,r.path)),r.sha256);
  for(const scope of accountingSource.stages){
    const file=base+'accounting-checks-'+scope.stage+'-20261010-r2.json',record=await json(file),raw=await bind(record.log,record.logSha256),actual=verifyExecution(raw,scope.workingDirectory,scope.files,0);
    must(record.stage===scope.stage&&record.status==='complete'&&record.exitCode===0&&record.integrityError===null&&record.spawnError===null&&record.stagePassed===true&&record.serialFileConcurrency===1&&eq(record.sourceManifest,{path:p.accountingSource,sha256:bound.get(p.accountingSource)})&&record.workingDirectory===scope.workingDirectory&&record.executable===scope.executable&&eq(record.args,scope.args)&&eq(record.selectedTestFiles,scope.testFiles)&&record.counts.passed===(scope.stage==='domain'?122:406)&&record.counts.failed===0&&record.counts.skipped===0&&actual.identities.length===record.counts.passed&&eq(actual.identities,record.actualTestIdentities),'ACTUAL_ACCOUNTING_SELECTED_EXECUTION_REQUIRED:'+scope.stage);
    for(const observation of [record.inputAuditBefore,record.inputAuditAfter])must(observation.selectedSources===1068&&observation.currentSourceMatchesFrozenInputs===true&&observation.warmSourceMatchesFrozenInputs===true&&eq(observation.sourceHashes,source.sourceHashes)&&eq(observation.toolchain,source.toolchain)&&eq(observation.resolution,accountingSource.resolution)&&eq(observation.bindings,accountingSource.bindings),'ACTUAL_ACCOUNTING_PRE_POST_BINDINGS_REQUIRED');
    for(const k of ['sourceEdits','newTests','approvedImageEdits','acceptanceEdits'])must(record[k]===0,'ACCOUNTING_CHECK_SCOPE_CHANGED');
    accounting.push({stage:scope.stage,record:{path:file,sha256:bound.get(file)},log:{path:record.log,sha256:record.logSha256},passed:record.counts.passed,failed:0,skipped:0,testFiles:scope.files.length,observedAt:record.finishedAt,controlledOnly:true,actualTransactions:false});
  }
  must(matrix.rows?.length===109&&matrix.requirementCount===109&&new Set(matrix.rows.map(r=>r.id)).size===109&&matrix.ownerAcceptedCriteria===3&&eq(matrix.rows.filter(r=>r.ownerAccepted===true).map(r=>r.id),['AC-551','AC-552','AC-553'])&&matrix.rows.filter(r=>r.ownerAccepted===false).length===106,'EXACT3_OF109_ACCEPTANCE_REQUIRED');
  for(const k of ['wholeWaveComplete','ownerSignoff','authenticatedNativeAcceptance','realMfa','actualWorkerDelivery','actualModelUsage','independentSessionContention','targetScaleLoad','nativeKeyboardVerified','newRuntimeInstallationComplete'])must(matrix[k]===false,'SEPARATE_MATRIX_GATE_CHANGED:'+k);
  must(accept.status==='complete'&&accept.fullPublication===true&&accept.publicationError===null&&accept.cleanupErrors.length===0&&accept.postVerificationErrors.length===0&&accept.observedOwnerAcceptedCriteria===3&&eq(accept.observedOwnerAcceptedIds,['AC-551','AC-552','AC-553'])&&accept.other106RowsUnchanged===true&&accept.separateGatesUnchanged===true&&eq(accept.ownerDecision,{path:p.acceptOwner,sha256:bound.get(p.acceptOwner)}),'ACTUAL3_CRITERION_PUBLICATION_REQUIRED');
  must(promotion.status==='complete'&&promotion.fullPromotion===true&&promotion.publishedImageCount===83&&promotion.failure===null&&promotion.cleanupErrors.length===0&&promotion.postVerificationErrors.length===0&&promotion.remainingImages.length===0&&promotion.claimedWithoutPublication.length===0&&eq(promotion.ownerDecision,{path:p.imageOwner,sha256:bound.get(p.imageOwner)}),'ACTUAL83_IMAGE_PROMOTION_REQUIRED');
  for(const o of [acceptOwner,imageOwner])must(o.kind==='direct-human-owner-decision'&&o.authorizationKind==='direct-human-message'&&o.submittedByOwner===true&&o.sourceMessage?.role==='user'&&typeof o.sourceMessage.messageId==='string'&&o.sourceMessage.messageId&&typeof o.sourceMessage.threadId==='string'&&Number.isFinite(Date.parse(o.sourceMessage.receivedAt))&&o.messageSha256===sha(Buffer.from(o.messageVerbatim)),'DIRECT_HUMAN_DECISION_REQUIRED');
  must(imageOwner.images.length===83&&imageOwner.images.every(r=>r.decision==='accept')&&acceptOwner.criteria.length===3&&eq(acceptOwner.criteria.map(c=>c.id),['AC-551','AC-552','AC-553'])&&acceptOwner.criteria.every(c=>c.decision==='accept-complete-criterion'),'OWNER_DECISION_SCOPE_CHANGED');
  const component=await json(p.component),workerSource=await json(component.sourceRecord),tests=await json(component.testRecord),deno=await json(component.denoRecord);
  must(component.originalReview.bundleSha256===original.bundleSha256&&component.migrationHashesUnchanged===true&&component.migrations===71&&workerSource.files.length===26&&new Set(workerSource.files.map(f=>f.path)).size===26&&tests.tests===71&&tests.passed===71&&tests.failed===0&&tests.exitCode===0&&tests.controlled===true&&tests.externalCalls===false&&tests.deployed===false,'UNCHANGED_R14_WORKER_RECORDS_REQUIRED');
  const workerInventory=(await readdir(path.join(root,'workers/wave5'))).filter(f=>f.endsWith('.mjs')).map(f=>'workers/wave5/'+f).sort();
  must(eq(workerInventory,workerSource.files.map(f=>f.path).sort()),'EXACT26_WORKER_SOURCE_INVENTORY_REQUIRED');await refs(workerSource.files);
  const testLog=(await bind(tests.log,tests.logSha256)).toString('utf8');
  for(const [name,count]of [['tests',71],['pass',71],['fail',0],['cancelled',0],['skipped',0],['todo',0]]){
    const summary=[...testLog.matchAll(new RegExp('^(?:#|ℹ) '+name+' (\\d+)\\r?$','gm'))];
    must(summary.length===1&&Number(summary[0][1])===count,'ACTUAL_HISTORICAL71_NODE_LOG_REQUIRED:'+name);
  }
  must(deno.entrypoints.length===2&&deno.checksRerun===true&&deno.importedJavaScriptTypeChecked===false&&deno.deployed===false,'HISTORICAL_TWO_DENO_CHECKS_REQUIRED');
  for(const e of deno.entrypoints){must(e.exitCode===0,'HISTORICAL_DENO_NOT_GREEN');await bind(e.entrypoint,e.entrypointSha256);await bind(e.config,e.configSha256);const log=(await bind(e.log,e.logSha256)).toString('utf8');must(log.includes('Check ')&&!log.includes('error:'),'HISTORICAL_DENO_LOG_CHANGED');}
  must(component.deployments.length===2&&component.deployments.reduce((n,d)=>n+d.files.length,0)===22&&eq(component.deployments,prior.deployments),'EXACT22_DEPLOYMENT_FILE_ENTRIES_REQUIRED');
  for(const d of component.deployments){const payload=await json(d.payloadPath);must(payload.project_id===projectId&&payload.name===d.name&&payload.verify_jwt===false&&payload.files.length===d.files.length&&new Set(payload.files.map(f=>f.name)).size===d.files.length,'EDGE_PAYLOAD_SCOPE_CHANGED');await refs(d.files);for(const f of payload.files)must((await bind(f.name)).toString('utf8')===f.content,'EDGE_PAYLOAD_CURRENT_SOURCE_DRIFT:'+f.name);}
  const live=await json(p.live),index=await json(p.liveIndex);must(eq(index.summary.path,p.live)&&index.summary.sha256===bound.get(p.live)&&index.projectId===projectId&&index.immutableInputs.length===23,'FRESH_R3_PREFLIGHT_INDEX_REQUIRED');
  await refs(index.immutableInputs);await refs([index.report]);
  const raw=await json(live.rawEvidence.path,live.rawEvidence.sha256),rows=connectorRows(raw.rawConnectorResult);must(rows.length===1,'EXACT_ONE_PREFLIGHT_ROW_REQUIRED');const row=rows[0];
  must(raw.readOnly===true&&raw.projectId===projectId&&row.observed_at===live.observedAt&&live.readOnly===true&&live.projectId===projectId&&live.migrationCount===43&&row.migration_count===43&&live.apiFunctions===107&&row.api_functions===107&&live.checkedProviders===120&&live.unchangedProvidersSinceR2===120&&live.unchangedProvidersSinceOriginalOctober9Read===120&&live.changedProviderIdentities.length===0&&live.addedProviderIdentities.length===0&&live.missingProviderIdentities.length===0,'FRESH_R3_PROVIDER_BASELINE_CHANGED');
  must(eq(row.wave5_tables,live.wave5Tables)&&live.wave5Tables.length===15&&live.wave5Tables.every(t=>t.rlsForced&&t.rlsEnabled)&&live.wave5RlsFlagsUnchangedSinceR2===true&&eq(row.access_row_fingerprints,live.accessRowFingerprints)&&eq(row.wave5_policy_and_grant_fingerprints,live.policyAndGrantFingerprints)&&live.accessRowFingerprintsUnchangedSinceFirstR2Baseline===true&&live.policyAndGrantFingerprintsUnchangedSinceFirstR2Baseline===true,'FRESH_R3_ACCESS_RLS_BASELINE_CHANGED');
  must(live.rolePermissions===87&&live.roleAssignments===1&&live.entitlements===28&&live.memberships===1&&row.role_permissions===87&&row.role_assignments===1&&row.entitlements===28&&row.memberships===1&&live.databaseMetadataAndExactCollisionPreflightClean===true&&live.proposedRuntimeAccounts===0&&Object.keys(live.collisions).length===14&&Object.entries(live.collisions).every(([k,v])=>v===0&&row[k]===v)&&Object.values(live.runtimeRelations).every(v=>v===null),'FRESH_R3_COLLISION_BASELINE_CHANGED');
  must(live.exactProposedCollisionScope.accounts===6&&live.exactProposedCollisionScope.tenants===500&&live.exactProposedCollisionScope.branches===501&&live.exactProposedCollisionScope.plans===4&&live.exactProposedCollisionScope.roles===1003&&live.exactProposedCollisionScope.reviewBundleSha256===prior.bundleSha256,'EXACT_SAVED_COLLISION_SCOPE_CHANGED');
  const query=await bind(live.query.path,live.query.sha256);must(query.length===219060&&raw.queryPath===live.query.path&&raw.querySha256===sha(query),'EXACT_SAVED_COLLISION_QUERY_CHANGED');
  const previousRaw=await json(index.originalRawToR3Comparison.r2.path,index.originalRawToR3Comparison.r2.sha256),previousRows=connectorRows(previousRaw.catalogAndCollisionVerification);
  must(previousRaw.projectId===projectId&&previousRaw.readOnly===true&&previousRaw.mutationsExecuted===false&&previousRaw.secretValuesRead===false&&previousRaw.query.sha256===sha(query)&&eq(previousRows,previousRaw.parsedCatalogAndCollisions)&&previousRows.length===1,'EXACT_PRIOR_PREFLIGHT_ROW_REQUIRED');
  const comparable=r=>Object.fromEntries(Object.entries(r).filter(([k])=>k!=='observed_at'));must(eq(comparable(row),comparable(previousRows[0]))&&Date.parse(row.observed_at)>Date.parse(previousRows[0].observed_at),'ONLY_PREFLIGHT_OBSERVATION_TIME_MAY_CHANGE');
  const edge=await json(live.edgeInventory.record.path,live.edgeInventory.record.sha256),functions=JSON.parse(edge.rawConnectorResult.content.find(c=>c.type==='text').text).functions;
  must(edge.readOnly===true&&edge.projectId===projectId&&functions.length===2&&eq(functions.map(f=>f.slug).sort(),['people-private-documents','people-private-purge'])&&live.edgeInventory.deployments.length===2&&live.edgeInventory.unchangedMetadataSinceR2===true&&live.edgeInventory.actualFunctionSourceBodyReread===false,'EXACT_EDGE_METADATA_BOUNDARY_CHANGED');
  const nativeMeta=await json(live.nativeAccountMetadata.record.path,live.nativeAccountMetadata.record.sha256);
  must(nativeMeta.readOnly===true&&nativeMeta.accountName==='jentra-w5-runtime'&&nativeMeta.accountExistenceVerified===true&&nativeMeta.accountExists===false&&nativeMeta.exitCode===2&&nativeMeta.namedError==='NERR_UserNotFound / NET HELPMSG 2221'&&nativeMeta.rawOutput.includes('2221')&&nativeMeta.packageDirectoryExists===false&&nativeMeta.profileDirectoryExists===false&&nativeMeta.provisionedByThisCheck===false&&nativeMeta.accountOrSessionContentsRead===false,'EXACT_NATIVE_TARGET_ABSENCE_REQUIRED');
  must(live.originalSixLedger.entries.length===6&&live.originalSixLedger.entries.every(e=>e.present===true&&!prior.migrations.some(m=>m.path===e.sourcePath))&&live.originalSixLedger.migrationLedgerListRereadInR3===false&&live.originalSixLedger.originalSixReinstalled===false,'INSTALLED_SIX_EXCLUSION_CHANGED');
  for(const k of ['fullRuntimePreflightComplete','currentRuntimeApprovalReady','runtimeOwnerApproved','newRuntimeInstallationComplete','authenticatedNative','nativeKeyboardVerified','realMfa','actualDelivery','actualModelUsage','independentSessionContention','targetScaleLoad','wholeSystemOwnerSignoff','mutationsExecuted','businessFunctionsCalled','AuthAccountsCreatedOrDeleted','privateSecretsRead','SDKJobsExecutedByThisReport','livingDocumentsChanged'])must(live[k]===false,'SAVED_PREFLIGHT_GATE_CHANGED:'+k);
  const late=await json(p.late,'cc4ad95640c7711bb380d90f041870dda98d0c4856c0d2abc8ad1213dbbfd197'),lateIndex=await json(p.lateIndex);
  must(late.kind==='read_only_late_live_preflight_comparison'&&lateIndex.kind==='read_only_late_live_preflight_artifact_index'&&late.projectId===projectId&&lateIndex.projectId===projectId&&lateIndex.observedAt===late.observedAt&&late.priorObservedAt===live.observedAt&&late.comparedFields===40&&eq(late.onlyChangedFields,['observed_at'])&&eq(lateIndex.summary,{path:p.late,sha256:bound.get(p.late),bytes:(await bytes(p.late)).length})&&eq(late.immutableInputs,lateIndex.immutableInputs)&&lateIndex.immutableInputs.length===11&&new Set(lateIndex.immutableInputs.map(r=>r.path)).size===11,'EXACT_LATE_PREFLIGHT_INDEX_REQUIRED');
  await refs(lateIndex.immutableInputs);
  const lateRaw=await json(base+'complete-live-preflight-20261010-r3-late-raw.json'),lateRows=connectorRows(lateRaw),lateContext=await json(base+'complete-live-preflight-20261010-r3-late-read-context.json');
  must(lateRows.length===1,'ONE_LATE_SQL_RESULT_REQUIRED');const lateRow=lateRows[0];
  must(Object.keys(lateRow).length===40&&eq(Object.keys(lateRow).sort(),Object.keys(row).sort())&&isDeepStrictEqual(comparable(lateRow),comparable(row))&&lateRow.observed_at===late.observedAt&&Date.parse(lateRow.observed_at)>Date.parse(row.observed_at),'EXACT40_LATE_FIELDS_ONLY_TIME_CHANGED');
  must(late.readOnly===true&&late.migrationCount===43&&late.apiFunctions===107&&late.checkedProviders===120&&late.unchangedProviders===120&&late.changedProviders.length===0&&late.wave5ForcedAndEnabledRlsTables===15&&late.rolePermissions===87&&late.roleAssignments===1&&late.entitlements===28&&late.memberships===1&&eq(late.collisionCounters,live.collisions)&&late.allPriorCollisionFieldsUnchanged===true&&Object.values(late.collisionCounters).every(v=>v===0),'LATEST_METADATA_PROVIDER_ACCESS_COLLISIONS_CHANGED');
  must(lateContext.kind==='read-only-late-runtime-metadata-observation'&&lateContext.projectId===projectId&&lateContext.readOnly===true&&lateContext.sameProjectVerifiedThroughBothConnections===true&&lateContext.observedAt===late.observedAt&&eq(lateContext.query,{path:live.query.path,sha256:live.query.sha256})&&eq(lateContext.tools,['supabase_execute_sql','supabase_list_migrations','supabase_list_edge_functions'])&&lateContext.sqlInstalled===false&&lateContext.accountsChanged===false&&lateContext.credentialsInspected===false&&lateContext.edgeDeployed===false,'LATEST_CONNECTOR_READ_CONTEXT_CHANGED');
  const lateLedger=plainConnector(await json(base+'complete-live-preflight-20261010-r3-late-ledger.json')).migrations,installation=await json(base+'installation-result-20261008.json');
  must(lateLedger.length===43&&new Set(lateLedger.map(m=>m.version)).size===43&&installation.targetProjectId===projectId&&installation.installationComplete===true&&installation.approvedMigrationsInstalled===6&&installation.migrationsInOrder.length===6&&late.originalSixLedger.migrationLedgerListReread===true&&late.originalSixLedger.ledgerRows===43&&late.originalSixLedger.sixOriginalEntriesMatch===true&&late.originalSixLedger.preservedEntries.length===6&&late.originalSixLedger.sourceMigrationNamesReplayed===false,'ACTUAL_LATE43_LEDGER_AND_INSTALLED6_REQUIRED');
  const exactSix=installation.migrationsInOrder.map(m=>{must(lateLedger.filter(r=>r.name===m.ledgerEntry.name&&r.version===m.ledgerEntry.version).length===1&&!prior.migrations.some(p=>p.path===m.path),'ACTUAL_INSTALLED6_LEDGER_CHANGED:'+m.path);return{sourcePath:m.path,ledgerEntry:m.ledgerEntry,currentMatches:1,reinstalled:false};});
  must(eq(exactSix,late.originalSixLedger.preservedEntries),'EXACT6_LATE_INSTALLATION_MAPPING_CHANGED');
  const lateFunctions=plainConnector(await json(base+'complete-live-preflight-20261010-r3-late-edge-list.json')).functions;
  must(lateFunctions.length===2&&isDeepStrictEqual(lateFunctions,functions)&&late.edgeInventory.actualListReread===true&&late.edgeInventory.actualFunctionSourceBodyReread===false&&late.edgeInventory.unchangedSincePriorR3===true&&eq(late.edgeInventory.deployments,lateFunctions.map(f=>({id:f.id,slug:f.slug,version:f.version,status:f.status,metadataBodyHash:f.ezbr_sha256}))),'ACTUAL_LATE_EDGE_METADATA_CHANGED');
  for(const k of ['fullRuntimePreflightComplete','runtimeOwnerApproved','newRuntimeInstallationComplete','authenticatedNative','fullNativeKeyboardGate','realMfa','actualDelivery','actualModelUsage','independentSessionContention','targetScaleLoad','ownerAcceptanceChanged','wholeSystemOwnerSignoff','sqlInstalled','AuthAccountsCreatedOrDeleted','privateSecretsRead','SDKJobsExecuted'])must(late[k]===false,'LATEST_PREFLIGHT_OPERATION_GATE_CHANGED:'+k);
  must(lateIndex.readOnly===true&&lateIndex.summaryPublished===true&&lateIndex.sqlInstalled===false&&lateIndex.accountsChanged===false&&lateIndex.fullRuntimePreflightComplete===false&&lateIndex.runtimeOwnerApproved===false,'LATEST_INDEX_OPERATION_GATE_CHANGED');
  must(live.ownerAcceptanceSnapshot.ownerAcceptedCriteria===3&&eq(live.ownerAcceptanceSnapshot.criterionIds,['AC-551','AC-552','AC-553'])&&live.goldenSnapshot.promotedImages===83&&live.goldenSnapshot.passed===2004,'PREFLIGHT_OWNER_AND_GOLDEN_SNAPSHOT_CHANGED');
  for(const f of [p.native,p.nativeMd,p.preview,p.connected,p.workerAdapter])if(!await exists(f))missing.push(f);
  let native=null,adapter=null,nativePreview=null,packages=[];
  if(!missing.length){
    native=await json(p.native);await bind(p.nativeMd);
    const preparation=await json(base+'windows-userflow-preparation-20261010-r3.json');
    must(preparation.revision==='r3'&&preparation.date==='20261010'&&preparation.sourceStable===true&&preparation.sharedSourceChanged===false&&preparation.sourceFileCount===1068&&eq(preparation.approvedInput,{path:p.source,sha256:bound.get(p.source)})&&preparation.manifests.length===2,'EXACT_PAIRED_NATIVE_PREPARATION_REQUIRED');await refs(preparation.manifests);
    must(native.kind==='paired-ordinary-native-build-adapter'&&native.revision==='r3'&&native.currentSourceMatch===true&&native.previewBuilt===true&&native.connectedBuilt===true&&native.sourceFilesPerApp===1068&&native.ordinaryEntrypoint==='lib/main.dart'&&native.nativeLaunched===false&&Number.isFinite(Date.parse(native.observedAt)),'CURRENT_PAIRED_NATIVE_REPORT_REQUIRED');
    for(const k of ['authenticatedNativeAcceptance','nativeKeyboardVerified','realMfa','actualWorkerDelivery','actualModelUsage','independentSessionContention','targetScaleLoad','ownerAccepted'])must(native[k]===false,'PAIRED_NATIVE_GATE_CHANGED:'+k);
    await bind(native.recorder,native.recorderSha256);await bind(native.helper,native.helperSha256);
    must(eq(native.ownerImageDecision,{path:p.imageOwner,sha256:bound.get(p.imageOwner),approvedImages:83})&&eq(native.promotion,{path:p.promotion,sha256:bound.get(p.promotion)})&&native.ownerCriterionDecision.path===p.acceptOwner&&native.ownerCriterionDecision.sha256===bound.get(p.acceptOwner),'NATIVE_OWNER_EVIDENCE_BINDINGS_CHANGED');
    const desktop=native.desktopBaseSourceSuite;
    must(desktop.record===p.full&&desktop.recordSha256===bound.get(p.full)&&desktop.sourceManifest===p.source&&desktop.sourceManifestSha256===bound.get(p.source)&&desktop.log===full.log&&desktop.logSha256===full.logSha256&&desktop.passedTests===2004&&desktop.failedTests===0&&desktop.skippedTests===0&&desktop.rerunInIdentityOverlayTree===false&&eq(native.broaderSuites.desktopAll,desktop),'BASE_DESKTOP_RUN_MUST_RETAIN_ORIGINAL_TREE');
    let releaseCount=0;
    for(const [name,file]of [['preview',p.preview],['connected',p.connected]]){
      const packageManifest=await json(file),sourcePath=base+'windows-test-'+name+'-source-20261010-r3.json',ns=await json(sourcePath);
      must(packageManifest.mode===name&&packageManifest.entrypoint==='lib/main.dart'&&packageManifest.controlledEvidence===false&&packageManifest.current_source_match===true&&packageManifest.base_source_match===true&&packageManifest.projectId===(name==='connected'?projectId:null)&&packageManifest.sourceManifest===sourcePath&&packageManifest.sourceManifestSha256===bound.get(sourcePath)&&eq(packageManifest.sourceHashes,source.sourceHashes)&&eq(packageManifest.buildSourceHashes,ns.buildSourceHashes)&&eq(packageManifest.runnerOverlays,ns.overlays)&&eq(ns.baseSourceHashes,source.sourceHashes)&&eq(ns.approvedSourceInput,{path:p.source,sha256:bound.get(p.source)})&&ns.entrypoint==='lib/main.dart'&&ns.controlledEvidence===false,'CURRENT_ORDINARY_NATIVE_PACKAGE_REQUIRED:'+name);
      const overlayPaths=['apps/jentra_desktop/windows/CMakeLists.txt','apps/jentra_desktop/windows/runner/Runner.rc','apps/jentra_desktop/windows/runner/main.cpp'];
      must(ns.overlays.length===3&&new Set(ns.overlays.map(o=>o.path)).size===3&&eq(ns.overlays.map(o=>o.path).sort(),overlayPaths.sort()),'EXACT_THREE_RUNNER_OVERLAYS_REQUIRED');
      const expected={...source.sourceHashes};for(const o of ns.overlays){must(o.baseSha256===expected[o.path]&&o.buildSha256!==o.baseSha256&&o.purpose==='Isolated test runner identity only','DECLARED_RUNNER_OVERLAY_CHANGED');expected[o.path]=o.buildSha256;}
      must(eq(expected,ns.buildSourceHashes)&&Object.keys(expected).length===1068&&path.resolve(ns.snapshot)===path.join(root,'build/w5win10r3',name),'EXACT_NATIVE_EXECUTION_SOURCE_MAP_REQUIRED');
      must(eq(select(await sources(ns.snapshot)),expected),'NATIVE_SNAPSHOT1068_DRIFT:'+name);
      for(const[f,h]of Object.entries(expected))await bind(relative(path.join(ns.snapshot,f)),h);
      for(const[f,h]of Object.entries(ns.scriptBindings))await bind(f,h);await bind(ns.publicBuildBinding.path,ns.publicBuildBinding.sha256);
      if(name==='connected'){must(ns.publicConfig?.publicOnly===true&&ns.publicConfig.projectId===projectId&&ns.publicConfig.environment==='development','PUBLIC_CONNECTED_CONFIGURATION_REQUIRED');await bind(ns.publicConfig.path,ns.publicConfig.sha256);}else must(ns.publicConfig===null,'PREVIEW_MUST_NOT_CONTAIN_PUBLIC_CONNECTED_CONFIG');
      const build=await json(packageManifest.buildEvidence,packageManifest.buildEvidenceSha256),buildLog=logText(await bind(build.log,build.logSha256));
      must(build.stage==='build'&&build.mode===ns.mode&&build.revision==='r3'&&build.date==='20261010'&&build.exitCode===0&&build.failure===null&&build.SDKExecuted===true&&buildLog.includes('Built build')&&build.args.includes('--target=lib/main.dart')&&build.args.includes('--release')&&build.args.includes('--no-pub')&&!build.args.includes('--update-goldens')&&path.resolve(build.workingDirectory)===path.join(ns.snapshot,'apps/jentra_desktop'),'ACTUAL_ORDINARY_NATIVE_BUILD_REQUIRED:'+name);
      must(build.args.includes(name==='connected'?'--dart-define-from-file='+path.join(ns.snapshot,'public-build-config.json'):'--dart-define=JENTRA_ENVIRONMENT=preview')&&packageManifest.buildLog===build.log&&packageManifest.buildLogSha256===build.logSha256,'EXACT_PUBLIC_NATIVE_BUILD_MODE_REQUIRED');
      for(const a of [build.sourceGuardBefore,build.sourceGuardAfter])must(a?.sourceFileCount===1068&&a.currentSourceMatches===true&&a.snapshotSourceMatches===true&&eq(a.manifest,{mode:ns.mode,path:sourcePath,sha256:bound.get(sourcePath)})&&a.runnerOverlayCount===3,'ACTUAL_NATIVE_BUILD_SOURCE_GUARDS_REQUIRED');
      const toolRef=packageManifest.toolchainGuard,tool=await json(toolRef.path,toolRef.sha256);
      must(tool.status==='passed'&&tool.exitCode===0&&tool.failure===null&&tool.SDKStageInvoked===true&&tool.mode===ns.mode&&tool.stage==='build'&&tool.attempt===build.attempt&&tool.sdkRecord===packageManifest.buildEvidence&&tool.sdkRecordSha256===bound.get(packageManifest.buildEvidence)&&tool.resolutionChanged===false&&eq(tool.before,toolRef.before)&&eq(tool.after,toolRef.after),'ACTUAL_NATIVE_TOOL_GUARD_REQUIRED');
      must(eq(tool.before.tooling,source.toolchain.tooling)&&eq(tool.after.tooling,source.toolchain.tooling)&&eq(tool.before.scripts,tool.after.scripts)&&eq(tool.before.resolution,tool.after.resolution),'EXACT_NATIVE_TOOL_PRE_POST_BINDINGS_REQUIRED');
      for(const observation of [tool.before,tool.after]){
        must(observation.approvedInputSha256===bound.get(p.source)&&observation.preparationSha256===bound.get(base+'windows-userflow-preparation-20261010-r3.json'),'NATIVE_TOOL_SOURCE_PREPARATION_BINDING_CHANGED');
        for(const[f,h]of Object.entries(observation.scripts))await bind(f,h);
        const resolutionPaths=['.dart_tool/package_config.json','.dart_tool/package_graph.json'].map(f=>relative(path.join(ns.snapshot,f))).sort();
        must(observation.resolution.length===2&&new Set(observation.resolution.map(r=>r.path)).size===2&&eq(observation.resolution.map(r=>r.path).sort(),resolutionPaths),'EXACT_NATIVE_DEPENDENCY_RESOLUTION_FILES_REQUIRED');
        for(const r of observation.resolution){must(r.exists===true,'NATIVE_RESOLUTION_ABSENT');await bind(r.path,r.sha256);}
      }
      must(build.runner==='scripts/wave5/run_windows_userflow_20261010_r3_a2.ps1'&&tool.before.scripts[build.runner]===build.runnerSha256&&tool.after.scripts[build.runner]===build.runnerSha256,'CORRECTED_NATIVE_RUNNER_PRE_POST_BINDING_REQUIRED');await bind(build.runner,build.runnerSha256);
      const sdkExit=await json(build.sdkExitRecord,build.sdkExitRecordSha256);
      must(build.sdkExitRecord===packageManifest.buildEvidence.replace(/\.json$/,'.sdk-exit.json')&&build.sdkExitCode===0&&sdkExit.sdkExitCode===0&&sdkExit.mode===ns.mode&&sdkExit.stage==='build'&&sdkExit.attempt===build.attempt&&eq(tool.sdkExitRecord,{path:build.sdkExitRecord,sha256:build.sdkExitRecordSha256}),'DURABLE_ACTUAL_NATIVE_SDK_EXIT_REQUIRED');
      must(Array.isArray(packageManifest.releaseFiles)&&packageManifest.releaseFiles.length>0&&new Set(packageManifest.releaseFiles.map(f=>f.path)).size===packageManifest.releaseFiles.length&&packageManifest.releaseFiles.some(f=>f.path==='Jentra_OS.exe'),'EXACT_NATIVE_RELEASE_INVENTORY_REQUIRED');
      for(const f of packageManifest.releaseFiles){must(typeof f.path==='string'&&!path.isAbsolute(f.path)&&!f.path.split(/[\\/]/).includes('..')&&Number.isInteger(f.bytes)&&f.bytes>0,'NATIVE_RELEASE_PATH_OR_SIZE_INVALID');for(const dir of [packageManifest.releaseDirectory,packageManifest.packageDirectory]){const data=await bind(relative(path.join(dir,f.path)),f.sha256);must(data.length===f.bytes,'NATIVE_RELEASE_SIZE_DRIFT');}}
      const title=name==='preview'?'Preview':'Connected',releaseDirectory=path.join(ns.snapshot,'apps/jentra_desktop/build/windows/x64/runner/Release'),packageDirectory=path.join(root,'dist/Jentra OS Windows Test 20261010 r3',title);
      must(packageManifest.releaseDirectory===releaseDirectory&&packageManifest.packageDirectory===packageDirectory,'EXACT_NATIVE_RELEASE_DIRECTORIES_REQUIRED');
      must(eq(await inventory(releaseDirectory),packageManifest.releaseFiles)&&eq((await inventory(packageDirectory)).filter(f=>f.path!=='release-manifest.json'),packageManifest.releaseFiles),'NATIVE_RELEASE_INVENTORY_DRIFT');
      const exeSha=packageManifest.releaseFiles.find(f=>f.path==='Jentra_OS.exe').sha256;
      for(const identity of [packageManifest.executableIdentity.build,packageManifest.executableIdentity.packaged]){
        must(identity.readOnly===true&&identity.nativeLaunched===false&&identity.sha256===exeSha&&identity.CompanyName==='com.jentra.test'&&identity.ProductName==='JentraOS_WindowsTest_20261010-r3_'+title&&identity.OriginalFilename==='Jentra_OS.exe','CAPTURED_COMPILED_NATIVE_IDENTITY_REQUIRED');await bind(identity.inspector,identity.inspectorSha256);
      }
      const releaseManifest=await json(relative(path.join(packageDirectory,'release-manifest.json')));
      must(releaseManifest.mode===name&&eq(releaseManifest.releaseFiles,packageManifest.releaseFiles)&&eq(releaseManifest.storageIdentity,ns.stores)&&eq(releaseManifest.executableIdentity,packageManifest.executableIdentity.packaged)&&eq(packageManifest.storageIdentity,ns.stores)&&ns.stores.company==='com.jentra.test'&&ns.stores.product==='JentraOS_WindowsTest_20261010-r3_'+title&&ns.stores.defaultStoresRead===false&&ns.stores.localStoresCopied===false&&ns.stores.newOsUserCreated===false,'EXACT_NATIVE_STORAGE_IDENTITY_REQUIRED');
      releaseCount+=packageManifest.releaseFiles.length;packages.push({mode:name,manifest:{path:file,sha256:bound.get(file)},source:{path:sourcePath,sha256:bound.get(sourcePath)},packageDirectory:packageManifest.packageDirectory,releaseDirectory:packageManifest.releaseDirectory,releaseFiles:packageManifest.releaseFiles,runnerOverlays:ns.overlays});
    }
    must(native.releaseEntriesVerified===releaseCount&&typeof native.delivery==='string','PAIRED_NATIVE_RELEASE_AND_DELIVERY_REQUIRED');
    const delivery=await json(native.delivery,native.deliveryManifestSha256),zip=await bind(delivery.zip,delivery.zipSha256),zipEntries=readZipEntries(zip),packageInputs=await json(native.packageInputs,native.packageInputsSha256);
    must(delivery.bothAppsIncluded===true&&delivery.revision==='r3'&&delivery.verifiedReleaseEntries===releaseCount&&delivery.acceptanceStoresCopied===false&&delivery.nativeLaunched===false&&delivery.backendChanged===false&&zip.length===delivery.zipBytes&&native.zip===delivery.zip&&native.zipSha256===delivery.zipSha256&&native.zipBytes===delivery.zipBytes&&delivery.packageInputs===native.packageInputs&&delivery.packageInputsSha256===bound.get(native.packageInputs),'PAIRED_ZIP_RECORD_INVALID');
    must(packageInputs.packageName==='Jentra OS Windows Test 20261010 r3'&&packageInputs.packageDirectory===path.join(root,'dist',packageInputs.packageName)&&delivery.packageDirectory===packageInputs.packageDirectory&&packageInputs.compiledRunnerIdentitiesVerified===true&&packageInputs.nativeLaunched===false&&packageInputs.localStoresReadOrCopied===false&&packageInputs.manifests.length===2,'EXACT_TOTAL_PORTABLE_PACKAGE_INPUTS_REQUIRED');
    must(eq(await inventory(packageInputs.packageDirectory),packageInputs.packageFiles)&&native.packageEntriesVerified===packageInputs.packageFiles.length&&delivery.verifiedPackageEntries===packageInputs.packageFiles.length,'TOTAL_PORTABLE_PACKAGE_INVENTORY_DRIFT');
    const zipFiles=[...zipEntries.keys()].filter(f=>!f.endsWith('/')).sort(),expectedZipFiles=packageInputs.packageFiles.map(f=>packageInputs.packageName+'/'+f.path).sort();must(eq(zipFiles,expectedZipFiles),'EXACT_TOTAL_ZIP_INVENTORY_REQUIRED');
    for(const f of packageInputs.packageFiles){const data=await bind(relative(path.join(packageInputs.packageDirectory,f.path)),f.sha256);must(data.length===f.bytes,'TOTAL_PORTABLE_FILE_SIZE_DRIFT');const entry=zipEntries.get(packageInputs.packageName+'/'+f.path);must(entry&&sha(zipEntryBytes(zip,entry,f.bytes))===f.sha256,'ACTUAL_ZIP_FILE_ENTRY_DRIFT');}
    for(const manifest of packageInputs.manifests){const app=packages.find(a=>a.mode===manifest.mode);must(app&&manifest.path===app.manifest.path&&manifest.sha256===app.manifest.sha256&&manifest.releaseFiles===app.releaseFiles.length,'TOTAL_PACKAGE_MANIFEST_BINDING_CHANGED');}
    await bind(packageInputs.packager,packageInputs.packagerSha256);await bind('scripts/wave5/windows_delivery_inputs_20261010_r3.mjs',packageInputs.inputHelperSha256);await bind('scripts/wave5/finalize_windows_userflow_20261010_r3.ps1');
    must(native.stages.length===5&&new Set(native.stages.map(s=>s.mode+':'+s.stage)).size===5&&eq(native.stages.map(s=>s.mode+':'+s.stage).sort(),['Connected:build','Connected:pubget','Preview:analyzer','Preview:build','Preview:pubget']),'EXACT_FIVE_NATIVE_STAGES_REQUIRED');
    for(const s of native.stages){
      must(s.exitCode===0&&typeof s.record==='string'&&typeof s.log==='string','CURRENT_NATIVE_STAGE_RECORD_REQUIRED');const stage=await json(s.record,s.recordSha256),log=await bind(s.log,stage.logSha256);
      must(stage.exitCode===0&&stage.failure===null&&stage.SDKExecuted===true&&stage.mode===s.mode&&stage.stage===s.stage&&stage.log===s.log&&s.logSha256===stage.logSha256&&stage.revision==='r3'&&stage.date==='20261010','CURRENT_NATIVE_STAGE_BINDING_INVALID');
      const sourcePath=base+'windows-test-'+stage.mode.toLowerCase()+'-source-20261010-r3.json';
      for(const g of [stage.sourceGuardBefore,stage.sourceGuardAfter])must(g.currentSourceMatches===true&&g.snapshotSourceMatches===true&&g.manifest.path===sourcePath&&g.manifest.sha256===bound.get(sourcePath),'ALL_NATIVE_STAGE_SOURCE_GUARDS_REQUIRED');
      if(stage.stage==='analyzer')must(logText(log).includes('No issues found!')&&s.SDKGuardClaim==='Source/config guard only; no retroactive SDK/package-resolution before claim','CURRENT_ANALYZER_NOT_CLEAN_OR_NARROWLY_ATTRIBUTED');
    }
    adapter=await json(p.workerAdapter);
    must(adapter.kind==='current-runtime-worker-adapter'&&adapter.revision==='r3'&&adapter.workerSourceUnchanged===true&&adapter.workerTestsRerun===false&&adapter.denoChecksRerun===false&&adapter.workerFiles===26&&adapter.controlledTests===71&&adapter.denoEntrypoints===2&&eq(adapter.sourceManifest,{path:p.source,sha256:bound.get(p.source)})&&eq(adapter.nativeReport,{path:p.native,sha256:bound.get(p.native)})&&eq(adapter.connectedManifest,{path:p.connected,sha256:bound.get(p.connected)})&&eq(adapter.historicalComponent,{path:p.component,sha256:bound.get(p.component)})&&eq(adapter.workerSourceFiles,workerSource.files)&&eq(adapter.deploymentSourceFileCounts,[14,8])&&adapter.deployments.length===2,'LATEST_PAIRED_WORKER_ADAPTER_REQUIRED');
    for(const d of adapter.deployments){const historical=component.deployments.find(h=>h.name===d.name);must(historical&&d.entrypoint===historical.entrypoint&&d.payload.path===historical.payloadPath&&d.payload.sha256===bound.get(historical.payloadPath)&&eq(d.files,historical.files)&&d.sourceFileCount===historical.files.length&&d.verifyJwt===false&&d.deployed===false,'LATEST_ADAPTER_PAYLOAD_SCOPE_CHANGED');}
    must(Date.parse(adapter.observedAt)>=Date.parse(native.observedAt)&&Array.isArray(adapter.bindings)&&adapter.bindings.length>0,'WORKER_ADAPTER_MUST_FOLLOW_NATIVE_REPORT');await refs(adapter.bindings);
    for(const k of ['liveOperationsPerformed','actualModelUsage','actualWorkerDelivery','installedSql','realMfa','independentSessionContention','targetScaleLoad','ownerAccepted'])must(adapter[k]===false,'WORKER_ADAPTER_RUNTIME_GATE_CHANGED:'+k);
  }
  nativePreview=await json(p.nativePreview,'56b786ff721e1f3bbd54d4d277801d85e0c9125ceb705705be3b5dcb156d401c');
  must(nativePreview.kind==='actual-native-preview-userflow-observations'&&nativePreview.status==='complete'&&nativePreview.revision==='r3'&&nativePreview.mode==='Preview'&&nativePreview.nativeLaunched===true&&eq(nativePreview.counts,{pass:10,fail:2,blocked:2,observed:0})&&nativePreview.observations.length===14&&new Set(nativePreview.observations.map(o=>o.id)).size===14&&Date.parse(nativePreview.finishedAt)>=Date.parse(nativePreview.startedAt),'EXACT_COMPLETED_ORDINARY_PREVIEW_REQUIRED');
  for(const k of ['authenticatedNative','fullNativeKeyboardGate','accountingTransactionsPosted','authoritativeReportsGenerated','actualDelivery','realMfa','actualModelUsage','independentSessionContention','targetScaleLoad','ownerAcceptanceChanged'])must(nativePreview[k]===false,'ORDINARY_PREVIEW_BROADER_GATE_CHANGED:'+k);
  await refs([nativePreview.package,nativePreview.sourceManifest,nativePreview.prelaunchPathObservation,nativePreview.recorder]);
  must(nativePreview.package.path===p.preview&&nativePreview.sourceManifest.path===base+'windows-test-preview-source-20261010-r3.json','ORDINARY_PREVIEW_PACKAGE_SCOPE_CHANGED');
  const previewPackage=await json(nativePreview.package.path,nativePreview.package.sha256),previewSource=await json(nativePreview.sourceManifest.path,nativePreview.sourceManifest.sha256),storageBefore=await json(nativePreview.prelaunchPathObservation.path,nativePreview.prelaunchPathObservation.sha256);
  const actualExecutable=await bind(relative(nativePreview.executable),nativePreview.executableSha256);
  must(nativePreview.executable===previewPackage.executable&&nativePreview.executableSha256===previewPackage.executableIdentity.packaged.sha256&&actualExecutable.length>0&&eq(previewSource.baseSourceHashes,source.sourceHashes),'ACTUAL_PREVIEW_EXECUTABLE_SOURCE_CHANGED');
  must(storageBefore.kind==='exact-product-prelaunch-path-existence'&&storageBefore.allExpectedPathsAbsent===true&&storageBefore.paths.length===4&&new Set(storageBefore.paths.map(p=>p.mode+':'+p.kind)).size===4&&eq(storageBefore.paths.map(p=>p.mode+':'+p.kind).sort(),['Connected:applicationCache','Connected:applicationSupport','Preview:applicationCache','Preview:applicationSupport'])&&storageBefore.paths.every(p=>p.exists===false)&&storageBefore.pathContentsRead===false&&storageBefore.defaultAcceptanceStoresRead===false&&storageBefore.localStoresCopied===false&&storageBefore.OSUserCreated===false&&Date.parse(storageBefore.observedAt)<Date.parse(nativePreview.startedAt),'ACTUAL_PRELAUNCH_METADATA_BOUNDARY_CHANGED');
  const normalized=s=>s.replace(/^process:/i,'').replaceAll('\\','/').toLowerCase();
  must(nativePreview.observedWindows.length===3&&new Set(nativePreview.observedWindows.map(w=>w.id)).size===3&&nativePreview.observedWindows.every(w=>Number.isInteger(w.id)&&normalized(w.app)===normalized(nativePreview.executable)&&w.title==='Jentra OS - 20261010 r3 Preview test'),'ACTUAL_RETURNED_NATIVE_WINDOWS_REQUIRED');
  let screenshots=0;const screenshotPaths=new Set(),screenshotHashes=new Set();
  for(const o of nativePreview.observations){
    must(/^[A-Z][A-Z0-9_-]{1,49}$/.test(o.id)&&['pass','fail','blocked','observed'].includes(o.result)&&['action','expected','observed'].every(k=>typeof o[k]==='string'&&o[k].trim())&&nativePreview.observedWindows.some(w=>w.id===o.window.id&&w.app===o.window.app&&w.title===o.window.title&&Date.parse(w.boundAt)<=Date.parse(o.observedAt))&&Date.parse(o.observedAt)>=Date.parse(nativePreview.startedAt)&&Date.parse(o.observedAt)<=Date.parse(nativePreview.finishedAt)&&Array.isArray(o.screenshots)&&o.screenshots.length>0,'EXACT_ACTUAL_NATIVE_OBSERVATION_REQUIRED');
    for(const s of o.screenshots){must(s.path.startsWith(base+'native-preview-20261010-r3/'+o.id+'-')&&!screenshotPaths.has(s.path),'EXACT_NATIVE_SCREENSHOT_SCOPE_REQUIRED');screenshotPaths.add(s.path);screenshotHashes.add(s.sha256);const data=await bind(s.path,s.sha256);must(data.length===s.bytes&&eq(imageDimensions(data),{width:s.width,height:s.height}),'ACTUAL_NATIVE_IMAGE_BYTES_OR_DIMENSIONS_CHANGED');screenshots++;}
  }
  must(screenshots===14&&eq(nativePreview.observations.filter(o=>o.result==='fail').map(o=>o.id),['K01_INITIAL_CTRL_K','K05_CTRL_K_RECHECK'])&&eq(nativePreview.observations.filter(o=>o.result==='blocked').map(o=>o.id),['P02_FINANCE_BLOCKED','P08_PROCUREMENT_BLOCKED']),'EXACT_NATIVE_FAILURE_AND_BLOCKED_SCOPE_REQUIRED');
  for(const k of ['pass','fail','blocked','observed'])must(nativePreview.observations.filter(o=>o.result===k).length===nativePreview.counts[k],'ACTUAL_NATIVE_OBSERVATION_COUNTS_CHANGED');
  must(screenshotHashes.size===13,'ACTUAL_NATIVE_DISTINCT_VISUAL_STATES_CHANGED');
  const postStorage=await json(p.nativePostStorage);
  must(postStorage.kind==='exact-product-postlaunch-path-existence'&&postStorage.revision==='r3'&&postStorage.paths.length===4&&postStorage.pathContentsRead===false&&postStorage.defaultAcceptanceStoresRead===false&&postStorage.localStoresCopied===false&&postStorage.OSUserCreated===false&&postStorage.authenticatedNative===false&&postStorage.formalRuntimeProfileProvisioned===false&&Date.parse(postStorage.observedAt)>=Date.parse(nativePreview.finishedAt),'EXACT_POSTLAUNCH_METADATA_BOUNDARY_REQUIRED');
  for(const before of storageBefore.paths){const after=postStorage.paths.filter(s=>s.mode===before.mode&&s.kind===before.kind&&s.expectedPath===before.expectedPath);must(after.length===1&&after[0].beforeExists===false&&after[0].afterExists===(before.mode==='Preview'&&before.kind==='applicationSupport'),'EXACT_NEW_PRODUCT_POSTLAUNCH_PATH_REQUIRED');}
  if(await exists(p.nativePreviewMd))await bind(p.nativePreviewMd);else missing.push(p.nativePreviewMd);
  await bind(p.finalHandoff,'96d70441f86f858282078ec2db9ff390a41af0522fb60002d31ad183a3bc1e0f');
  let statusBefore=null,statusAfter=null;
  for(const file of [p.statusBefore,p.statusAfter])if(!await exists(file))missing.push(file);
  if(await exists(p.statusBefore)&&await exists(p.statusAfter)){
    statusBefore=await json(p.statusBefore);statusAfter=await json(p.statusAfter);
    must(statusBefore.kind==='current-r3-verification-evidence-before'&&statusAfter.kind==='current-r3-verification-evidence-result'&&statusAfter.status==='complete'&&statusAfter.fullPublication===true&&statusAfter.publicationError===null&&statusAfter.cleanupErrors.length===0&&statusAfter.postVerificationErrors.length===0&&statusAfter.remainingDocuments.length===0&&statusAfter.claimedWithoutPublication.length===0&&statusAfter.observedOwnerAcceptedCriteria===3&&eq(statusAfter.before,{path:p.statusBefore,sha256:bound.get(p.statusBefore)})&&eq(statusBefore.evidence,statusAfter.evidence),'ACTUAL_GUARDED_LIVING_PUBLICATION_REQUIRED');
    for(const k of ['all109RowsUnchanged','criterionAcceptanceUnchanged','separateGatesUnchanged','allExistingMatrixMetadataPreserved','all109MarkdownCellsUnchanged'])must(statusAfter[k]===true,'LIVING_PUBLICATION_PRESERVATION_CHANGED:'+k);
    must(statusAfter.sourceEdits===0&&statusAfter.approvedBaselineEdits===0&&statusAfter.acceptanceStoresTouched===false&&statusAfter.SDKJobsExecuted===false&&statusAfter.liveOperations===false&&statusAfter.nativeActionsPerformed===false,'EVIDENCE_PUBLICATION_OPERATION_SCOPE_CHANGED');
    const living=[p.matrix,base+'requirement-matrix-20261008.md','docs/development/wave5-status.md'];
    must(statusBefore.originalLivingDocuments.length===3&&statusBefore.plannedDocuments.length===3&&statusAfter.observedDocuments.length===3&&statusAfter.retainedRecoveries.length===3&&eq(statusAfter.changedDocuments,living),'EXACT_THREE_LIVING_DOCUMENT_PUBLICATION_REQUIRED');
    for(const file of living){
      const original=statusBefore.originalLivingDocuments.find(d=>d.path===file),planned=statusBefore.plannedDocuments.find(d=>d.path===file),observed=statusAfter.observedDocuments.find(d=>d.path===file),recovery=statusAfter.retainedRecoveries.find(d=>d.originalPath===file);
      must(original&&planned&&observed&&recovery&&sha(Buffer.from(original.utf8Base64,'base64'))===original.sha256&&observed.matchesPlanned===true&&observed.sha256===planned.sha256&&observed.bytes===planned.bytes&&recovery.matchesOriginal===true&&recovery.matchesClaimed===true&&recovery.published===true&&recovery.sha256===original.sha256,'ACTUAL_LIVING_PUBLICATION_OR_RECOVERY_CHANGED:'+file);
      await bind(file,observed.sha256);await bind(recovery.path,original.sha256);
    }
    await refs(statusAfter.validatedInputs.filter(b=>!living.includes(b.path)));
    must(eq(matrix.currentR3Verification,statusAfter.evidence)&&statusAfter.evidence.sourceManifest.sha256===bound.get(p.source)&&statusAfter.evidence.pairedNativeBuild.sha256===bound.get(p.native)&&statusAfter.evidence.actualNativePreview.record.sha256===bound.get(p.nativePreview)&&statusAfter.evidence.actualNativePreview.report.sha256===bound.get(p.nativePreviewMd)&&eq(statusAfter.evidence.actualNativePreview.counts,nativePreview.counts)&&statusAfter.evidence.accounting.passed===528,'CURRENT_LIVING_VERIFICATION_BINDINGS_CHANGED');
    const final=statusAfter.finalSourceAndToolAudit;
    must(final.selectedSources===1068&&final.rootAndWarmMatchApprovedInputs===true&&final.bothR3CopiesMatchDeclaredIdentityOverlays===true&&eq(final.sourceManifest,{path:p.source,sha256:bound.get(p.source)})&&eq(final.toolchain,source.toolchain),'ACTUAL_LIVING_FINAL_SOURCE_TOOL_AUDIT_REQUIRED');
  }
  for(const [f,h]of startupTools)await bind(f,h);
  for(const[f,h]of bound)must(sha(await bytes(f))===h,'INPUT_CHANGED_DURING_CURRENT_RUNTIME_AUDIT:'+f);
  return{bound,missing,original,prior,scopeSha256,source,full,accounting,matrix,accept,acceptOwner,promotion,imageOwner,component,workerSource,tests,deno,live,index,late,lateIndex,lateContext,native,adapter,nativePreview,statusBefore,statusAfter,packages,legacyDrift:drift,
    checkedAt:new Date().toISOString(),current1068SourceMatched:true,legacyR13ArtifactsUnchanged:true};
}
// Capture preparation-tool bytes before the potentially long artifact audit.
// A subsequent edit must invalidate this invocation rather than bind newer bytes.
const startupTools=new Map();
for(const f of [self,'scripts/wave5/accounting_execution_verifier_20261010_r3.mjs','scripts/wave5/prepare_current_runtime_review_20261010_r3.mjs','scripts/wave5/cash_ui_evidence.mjs','scripts/wave5/record_continuation_windows.mjs','scripts/wave5/run_accounting_checks_20261010_r2.mjs','scripts/wave5/prepare_native_runtime_profile.ps1','workers/wave5/validate_runtime_review.mjs','workers/wave5/runtime_launcher.mjs'])startupTools.set(f,sha(await bytes(f)));
must(startupTools.get('scripts/wave5/accounting_execution_verifier_20261010_r3.mjs')==='91f00a9704beaf6c04873be81b75a26cba7fa0357c248e866a33a99cc69b004a','EXACT_PURE_VERIFIER_MODULE_REQUIRED');
for(const ref of verifierProvenance)must(startupTools.get(ref.path)===ref.sha256,'PURE_VERIFIER_ORIGINAL_PROVENANCE_DRIFT:'+ref.path);
const a=await audit();
if(mode==='check'){
  console.log(JSON.stringify({mode,composerPrepared:true,currentRuntimeApprovalReady:false,ownerApproved:false,eligibleForComposition:a.missing.length===0,
    missingArtifacts:a.missing,current1068SourceMatched:true,strictDesktop:{passed:2004,failed:0,skipped:0},ownerApprovedImages:83,ownerAcceptedCriteria:3,wholeSystemAccepted:false,
    controlledAccounting:a.accounting,
    actualOrdinaryPreview:{record:p.nativePreview,nativeLaunched:true,cases:14,counts:a.nativePreview.counts,screenshots:14,uniqueScreenshotHashes:13,formalRuntimeProfileProvisioned:false,authenticatedNative:false,fullNativeKeyboardGate:false},
    guardedLivingPublicationComplete:a.statusAfter?.fullPublication===true,
    migrations:71,scopeSha256:a.scopeSha256,workers:{files:26,tests:71,testsObservedAt:a.tests.observedAt,testsRerun:false,denoEntrypoints:2,denoObservedAt:a.deno.observedAt,payloadFileEntries:22},
    freshLiveObservedAt:a.late.observedAt,latest43LedgerReread:true,installedSixPreserved:true,legacyR13ArtifactsUnchanged:true,checkedBindings:a.bound.size,outputsWritten:false,SDKJobsExecuted:false,liveOperationsPerformed:false},null,2));
}else{
  must(a.missing.length===0,'CURRENT_RUNTIME_REVIEW_PREREQUISITES_PENDING:'+a.missing.join(','));
  const workerConfiguration=structuredClone(a.prior.workerConfiguration),releaseEntries=a.packages.reduce((n,b)=>n+b.releaseFiles.length,0);
  workerConfiguration.nativeIsolation.connectedBuildManifest=p.connected;workerConfiguration.nativeIsolation.windowsSourceRevision='r3';workerConfiguration.nativeIsolation.verifiedReleaseEntries=releaseEntries;
  const execution=structuredClone(a.prior.execution);execution.ownerAcceptance.criteria=a.matrix.rows.map(r=>({id:r.id,ownerAccepted:r.ownerAccepted}));execution.ownerAcceptance.sharedGoldenFailures=0;execution.ownerAcceptance.currentAcceptedBeforeRuntimeApproval=3;execution.ownerAcceptance.wholeSystemSignoff=false;
  const {bundleSha256:oldBundle,...priorBody}=a.prior;
  const evidence={candidateStrictAssertions:105,candidateRolledBack:true,candidateChecksRerun:false,bootstrapMappingStrictAssertions:25,bootstrapMappingRolledBack:true,bootstrapChecksRerun:false,bootstrapPermissionShim:false,
    controlledWorkerTests:71,workerTestsObservedAt:a.tests.observedAt,workerTestsRerun:false,entrypointsDenoChecked:true,entrypointsDenoObservedAt:a.deno.observedAt,entrypointsDenoChecksRerun:false,importedJavaScriptTypeChecked:false,
    workerComponent:p.component,workerAdapter:p.workerAdapter,workerFiles:26,workerPayloadFileEntries:22,freshLiveSummary:p.late,freshLiveIndex:p.lateIndex,earlierR3LiveSummary:p.live,earlierR3LiveIndex:p.liveIndex,checkedProviders:120,unchangedProviders:120,
    finalSourceManifest:p.source,finalSourceInputs:1068,fullStrictDesktop:{record:p.full,passed:2004,failed:0,skipped:0},approvedImages:83,imageOwnerDecision:p.imageOwner,promotion:p.promotion,
    controlledAccounting:{sourceManifest:p.accountingSource,stages:a.accounting,totalPassed:528,failed:0,skipped:0,testFiles:38,actualTransactions:false,installedBehavior:false,authenticatedNative:false},
    ownerAcceptedCriteria:3,ownerAcceptedCriterionIds:['AC-551','AC-552','AC-553'],remainingUnacceptedCriteria:106,criterionOwnerDecision:p.acceptOwner,criterionAcceptance:p.acceptAfter,wholeSystemAccepted:false,
    nativeReport:p.native,windowsSourceRevision:'r3',windowsPreviewBuilt:true,windowsConnectedBuilt:true,ordinaryEntrypoint:'lib/main.dart',sourceFiles:1068,releaseEntries,
    nativeLaunched:true,ordinaryPreviewNativeLaunched:true,ordinaryPreviewObservations:{record:p.nativePreview,sha256:a.bound.get(p.nativePreview),cases:14,counts:a.nativePreview.counts,screenshots:14,failedIds:['K01_INITIAL_CTRL_K','K05_CTRL_K_RECHECK'],blockedIds:['P02_FINANCE_BLOCKED','P08_PROCUREMENT_BLOCKED'],authenticated:false,actualTransactions:false},
    guardedLivingPublication:{before:p.statusBefore,after:p.statusAfter,fullPublication:true,all109RowsUnchanged:true,criterionAcceptanceUnchanged:true,separateGatesUnchanged:true},
    finalHandoff:{path:p.finalHandoff,sha256:a.bound.get(p.finalHandoff)},
    formalRuntimeProfileProvisioned:false,formalRuntimeNativeLaunched:false,nativeKeyboardVerified:false,installedNewMigrations:false,realMfa:false,authenticatedNative:false,actualWorkerDelivery:false,actualModelUsage:false,independentContention:false,targetScaleLoad:false,ownerSignoff:false,
    previousSixInstalledAssertions:126,historicalCandidateEvidence:'105 candidate and25 bootstrap assertions plus126 installed-six checks retain original observation times; no new SQL execution is inferred.',
    liveObservationLimits:'Latest late read observes40SQLfields at its exact server timestamp, with actual43row migration ledger list and the exact six original name/version pairs preserved. Ledger/Edge list tools have no separate server timestamp and bind their recorded read context. Edge source bodies retain earlier dated evidence; no current get-source, complete immediate private-context preflight or runtime authority is inferred.'};
  const artifacts=[...a.bound].sort(([x],[y])=>x.localeCompare(y)).map(([path,sha256])=>({path,sha256}));
  const body={...priorBody,reviewId:'jentra-complete-app-supabase-runtime-20261010-r3',preparedAt:new Date().toISOString(),ownerApproved:false,approvalReady:true,
    approvalReadyScope:'Concrete public-artifact review preparation only. Operation approval is absent; immediate live/collision/source/native/private-context preflight remains mandatory before execution.',
    supersedes:p.r13,preservedReviews:[{path:p.original,...originals.original,ownerApproved:false},{path:p.r13,...originals.r13,ownerApproved:false}],
    liveBaseline:{...a.prior.liveBaseline,observedAt:a.late.observedAt,migrations:43,apiFunctions:107,rolePermissions:87,roleAssignments:1,entitlements:28,memberships:1,refreshedBy:p.late,expectedLedgerAfterOnlyThisInstall:114,installedSixNeverReplayed:true,
      earlierOriginalSixLedgerVersionsObservedAt:a.live.originalSixLedger.lastObservedAt,originalSixLedgerListReadContextRecordedAt:a.lateContext.recordedAt,migrationLedgerListRereadInR3:true,ledgerListSeparateServerTimestampAvailable:false,edgeSourceBodiesRereadInR3:false,completeImmediatePreflightRequiredBeforeOperations:true},
    workerConfiguration,execution,evidence,artifacts,migrations:a.prior.migrations,deployments:a.component.deployments,
    sourceContinuation:{preservedOriginalBundleSha256:a.original.bundleSha256,preservedR13BundleSha256:a.prior.bundleSha256,unchangedRuntimeOperationScopeSha256:a.scopeSha256,
      legacyR13ArtifactsUnchanged:true,exactPreviouslyReviewedOriginalArtifactDrift:a.legacyDrift,currentSourceManifest:{path:p.source,sha256:a.bound.get(p.source)},
      nativeReport:{path:p.native,sha256:a.bound.get(p.native)},connectedBuildManifest:{path:p.connected,sha256:a.bound.get(p.connected)},workerAdapter:{path:p.workerAdapter,sha256:a.bound.get(p.workerAdapter)},
      originalReviewAndPayloadsPreserved:true,earlierApprovalCannotAuthorizeChangedSource:true,nativeBuildManifestMustMatchReviewedArtifact:true,privateOperationContextNotInspected:true},
    remainingDevelopment:['106 criteria remain unaccepted; complete-system owner signoff is absent. Three existing criterion decisions are preserved and authorize no runtime setup.',
      'Exact71 candidate installation and private Auth Admin/bootstrap/model/Vault/native/Edge/schedule operations remain unapproved.',
      'Genuine MFA, authenticated native keyboard/restart/revocation, actual export/model/worker delivery and trusted usage, independent-session contention and target-scale load remain open.',
      'Wave3/4 provider and module acceptance remain subject to their separately owned contracts. Production and real billing remain excluded.']};
  must(eq(runtimeScope(body),runtimeScope(a.prior)),'NEW_RUNTIME_OPERATION_SCOPE_CHANGED');
  must(artifacts.some(b=>b.path===p.connected&&b.sha256===a.bound.get(p.connected))&&artifacts.some(b=>b.path==='scripts/wave5/prepare_native_runtime_profile.ps1')&&artifacts.some(b=>b.path==='workers/wave5/validate_runtime_review.mjs'),'EXACT_NATIVE_PREPROVISION_BINDINGS_REQUIRED');
  const review={...body,bundleSha256:sha(Buffer.from(JSON.stringify(body)))},jsonBytes=Buffer.from(JSON.stringify(review,null,2)+'\n');
  const md=Buffer.from(`# Jentra OS current runtime operation review — October 10 r3

**Owner runtime approval is absent.** This new exact bundle is a review artifact. The 83 approved images and three accepted calculation criteria authorize no installation, provisioning or hosted action. Jentra OS and Wave 5 remain incomplete.

Bundle SHA-256: \`${review.bundleSha256}\`. The [machine manifest](complete-app-runtime-review-20261010-r3.json) binds all 1,068 final source inputs, actual 2,004/0/0 strict desktop tests, direct 83-image approval/promotion, existing three-of-109 criterion decisions, 528 controlled accounting checks in 38 files, paired ordinary Preview/Connected packages, every release/ZIP byte, unchanged 26 worker files, historical 71 controlled worker tests/two Deno entrypoints/22 payload entries, fresh r3 read-only preflight and exact Windows-target metadata. Original 13ffe and r13 92a68 bundles remain preserved and unapproved.

Operation scope remains the original 71 ordered migrations excluding the installed six; six private Auth Admin labels; 500 synthetic scopes/four plans/exact roles/source caps; a bounded separate operator; the original standard Windows profile/package; three Vault values/private model configuration; two same-project Edge deployments/three expiring jobs; and bounded genuine MFA/delivery/export/contention/load. Hosting remains \`xpdoufauvrbdmxgngetv\`; the expected ledger after only these 71 is 114. The complete concrete scope and migration hashes follow below.

The latest saved preflight at ${a.late.observedAt} observes 43 migrations/107 APIs, 120 unchanged provider signatures/hashes, 15 enabled/forced-RLS tables, 87/1/28/1 access counts, 14 zero exact collision counters and the same two People Edge metadata objects. All 40 SQL fields match the earlier r3 read except their server observation timestamp. The late connector batch also reread all 43 migration ledger rows and exactly matched the six original name/version pairs to the installation result; no migration was replayed. Edge source bodies were not reread. Native metadata retains its separate dated observation at ${a.live.nativeAccountMetadata.observedAt}: \`jentra-w5-runtime\` and its original package/profile paths were absent. This review does not claim a complete immediate private-context operation preflight. Recheck live collisions and every bound source/release byte immediately before any approved action.

Paired builds attribute 1,068 base inputs and three isolated runner identity overlays per app, with ${releaseEntries} shipped release entries independently verified against build/copy directories and all portable ZIP entries. The Connected manifest is an exact review artifact. The preserved native provisioner validates the owner-approved bundle, exact manifest SHA and every source/release byte **before creating an OS account or copying files**. Portable storage identity and package compilation do not establish a separate OS security boundary or authenticated native acceptance.

The actual [ordinary Preview session](native-preview-userflows-20261010-r3.json) subsequently launched the exact packaged executable and captured 14 cases/screenshots: 10 passed, two failed (initial/repeated Ctrl+K), and two were blocked (Finance/Procurement accounting paths). Mouse search, a physical letter key, Enter/Escape/Tab, required-field validation, dark theme, density, controlled preference restart and maximizing were observed. This session posted no transaction and authenticated no user. Ctrl+K and programmatic text entry remain under investigation; the broader native keyboard gate remains false. The package report's nativeLaunched=false is its earlier compilation checkpoint, while current ordinary Preview launched=true is bound separately here. The formal runtime profile remains unprovisioned.

The 122 domain and 406 injected platform accounting checks retain actual October 10 logs, unique execution identities and complete source/tool audits before and after execution. They check arithmetic, ledger/date/currency constraints, source lineage, malformed receipts, scoped denial and durable recovery under controlled fixtures. They establish no real posting, server installation or end-user financial report.

Worker checks remain observed at ${a.tests.observedAt}; Deno checks at ${a.deno.observedAt}. Current hashes/payload content were revalidated. The latest adapter binds the completed paired package report. Candidate 105/bootstrap 25/installed-six 126 SQL assertions remain historical. No SQL, Auth, OS, private secret, Edge deployment, schedule, delivery or model operation occurred while composing this review.

Exactly three complete criteria (AC-551/552/553) remain accepted; 106 remain unaccepted. Genuine MFA, authenticated native keyboard/restart/revocation, governed-export download/reopen, persistent hosted delivery/trusted model use, independent contention, 500-tenant/2,000-session load and whole-system owner signoff remain separate open gates. Direct owner approval of **this exact new SHA** is required before the unchanged operations; approval of older bundles or images is insufficient.
${concreteScopeMarkdown(a,workerConfiguration)}\n`);
  // Reserve all new output handles before publication. Preserve any partial outcome.
  const journal=await open(path.join(root,p.result),'wx');let jh=null,mh=null,error=null;
  await journal.writeFile(JSON.stringify({status:'in_progress',preparedAt:new Date().toISOString(),reviewPath:p.review,markdownPath:p.markdown,ownerApproved:false,liveOperationsPerformed:false},null,2)+'\n');
  try{
    jh=await open(path.join(root,p.review),'wx');mh=await open(path.join(root,p.markdown),'wx');
    for(const[f,h]of a.bound)must(sha(await bytes(f))===h,'INPUT_CHANGED_BEFORE_REVIEW_PUBLICATION:'+f);
    await jh.writeFile(jsonBytes);await mh.writeFile(md);await jh.close();jh=null;await mh.close();mh=null;
    for(const[f,h]of a.bound)must(sha(await bytes(f))===h,'INPUT_CHANGED_AFTER_REVIEW_PUBLICATION:'+f);
    must(sha(await bytes(p.review))===sha(jsonBytes)&&sha(await bytes(p.markdown))===sha(md),'ACTUAL_COMPOSED_REVIEW_BYTES_CHANGED');
  }catch(e){error={message:e.message,code:e.code??null};}
  for(const handle of [jh,mh])if(handle)try{await handle.close();}catch(e){error??={message:e.message,code:e.code??null};}
  const observed=[];for(const file of [p.review,p.markdown])try{const b=await bytes(file);observed.push({path:file,sha256:sha(b),bytes:b.length});}catch(e){observed.push({path:file,error:e.message});}
  const complete=!error&&observed.length===2&&observed[0].sha256===sha(jsonBytes)&&observed[1].sha256===sha(md);
  const report={status:complete?'complete':'failed',finishedAt:new Date().toISOString(),fullComposition:complete,error,bundleSha256:review.bundleSha256,observedDocuments:observed,
    boundInputCount:a.bound.size,scopeSha256:a.scopeSha256,ownerApproved:false,approvalExecuted:false,priorReviewsOverwritten:false,sourceEdits:0,approvedImageEdits:0,acceptanceEdits:0,
    SDKJobsExecuted:false,SQLExecuted:false,AuthOperations:false,OSOperations:false,privateSecretsRead:false,liveOperationsPerformed:false,
    boundary:'New public-artifact review files only. On partial failure all observed bytes are retained; no automatic retry, rollback or runtime approval.'};
  try{await journal.truncate(0);await journal.write(JSON.stringify(report,null,2)+'\n',0,'utf8');}finally{await journal.close();}
  console.log(JSON.stringify(report,null,2));if(!complete)process.exitCode=1;
}
