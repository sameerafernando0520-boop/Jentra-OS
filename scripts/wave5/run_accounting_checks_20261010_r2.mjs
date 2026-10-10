// Preparation is read-only by default. Root serializes the domain/platform jobs.
// Existing fixture tests only: no account, acceptance, SQL, source, or PNG writes.
import {lstat,open,readFile,realpath,writeFile} from 'node:fs/promises';
import {createHash} from 'node:crypto';
import {spawn} from 'node:child_process';
import path from 'node:path';
import {fileURLToPath} from 'node:url';
import {sources} from './cash_ui_evidence.mjs';
import {parseTestLog} from './record_continuation_windows.mjs';

const root=path.resolve(path.dirname(fileURLToPath(import.meta.url)),'../..');
const mode=process.argv[2]??'check';
if(process.argv.length>3||!['check','freeze','domain','platform'].includes(mode))throw Error('MODE_INVALID');
const base='docs/verification/wave5/';
const files={approvedSource:base+'golden-review-postapproval-source-20261010-r2.json',approvedRun:base+'golden-review-approvedAll-20261010-r2.json',
  source:base+'accounting-checks-source-20261010-r2.json'};
const runnerPath='scripts/wave5/run_accounting_checks_20261010_r2.mjs';
const sdk='C:/src/flutter/bin/cache/dart-sdk/bin/dart.exe',flutter='C:/src/flutter/bin/cache/flutter_tools.snapshot';
const specs={
  domain:{member:'packages/jentra_domain',files:[
    'test/jentra_domain_test.dart','test/procurement_test.dart','test/procurement_comparison_test.dart','test/goods_receipt_test.dart',
    'test/purchase_return_amount_test.dart','test/landed_extension_test.dart','test/receivables_test.dart','test/inventory_transfer_test.dart',
    'test/stock_count_quantity_test.dart','test/stock_opening_test.dart','test/negative_stock_policy_20261003_test.dart',
    'test/wave3_exact_rules_edges_test.dart','test/wave3_protocol_edges_test.dart','test/wave3_lead_to_cash_domain_test.dart',
    'test/analytics/cash_scenarios_test.dart','test/analytics/cash_scenario_revision_test.dart'],
    purpose:'Exact six-place arithmetic, rational quantities and tax/discount rounding; frozen source identity; partial returns and landed-cost conservation; invalid input and currency rejection; stock-deficit correction; immutable dated cash and hypothetical overrides.',
    args:files=>['test','--concurrency=1','--reporter=expanded',...files]},
  platform:{member:'packages/jentra_platform',files:[
    'test/manual_journal_gateway_test.dart','test/posted_journal_gateway_test.dart','test/period_fx_gateway_test.dart',
    'test/control_reconciliation_gateway_test.dart','test/financial_statement_gateway_test.dart','test/tax_summary_gateway_test.dart',
    'test/bank_reconciliation_gateway_test.dart','test/receivables_gateway_test.dart','test/procurement_gateway_test.dart',
    'test/inventory_valuation_gateway_test.dart','test/landed_value_gateway_test.dart','test/landed_extension_gateway_test.dart',
    'test/inventory_transfer_gateway_test.dart','test/stock_count_gateway_test.dart','test/negative_stock_policy_gateway_20261003_test.dart',
    'test/stock_opening_gateway_test.dart','test/security_review_finance_read_denial_test.dart','test/procurement_recovery_test.dart',
    'test/receivable_draft_store_test.dart','test/analytics/dated_cash_gateway_test.dart','test/analytics/cash_payment_dates_gateway_test.dart',
    'test/analytics/cash_scenario_store_test.dart'],
    purpose:'Injected gateway ledger balances, FX/control/statement/tax equations, exact transport and source lineage, AR/AP allocation/reversal evidence, stock valuation and landed costs; scoped denial and malformed-receipt rejection; encrypted input-only command recovery and dated cash provider completeness.',
    args:files=>[flutter,'--suppress-analytics','test','--no-pub','--concurrency=1','--reporter=expanded',...files]}
};
const contracts=[
  'docs/blueprint/21_WAVE3_PROCUREMENT_CONTRACT.md','docs/blueprint/24_WAVE3_SUPPLIER_SETTLEMENT_CONTRACT.md',
  'docs/blueprint/26_WAVE3_INVENTORY_TRANSFER_CONTRACT.md','docs/blueprint/27_WAVE3_STOCK_COUNT_CONTRACT.md',
  'docs/blueprint/30_WAVE3_LANDED_VALUE_CONTRACT.md','docs/blueprint/31_WAVE3_INVENTORY_VALUATION_REPORT_CONTRACT.md',
  'docs/blueprint/32_WAVE3_MANUAL_JOURNAL_CONTRACT.md','docs/blueprint/34_WAVE3_BANK_RECONCILIATION_CONTRACT.md',
  'docs/blueprint/35_WAVE3_PERIOD_FX_GOVERNANCE_CONTRACT.md','docs/blueprint/36_WAVE3_FINANCIAL_STATEMENTS_CONTRACT.md',
  'docs/blueprint/38_WAVE3_TAX_SUMMARY_CONTRACT.md','docs/blueprint/48_WAVE3_POSTED_JOURNAL_EVIDENCE_CONTRACT.md',
  'docs/blueprint/64_WAVE3_NEGATIVE_STOCK_POLICY_CONTRACT.md','docs/blueprint/wave5/W5_CASH_PAYMENT_DATES_CONTRACT.md'
];
const sha=b=>createHash('sha256').update(b).digest('hex');
const eq=(a,b)=>JSON.stringify(a)===JSON.stringify(b);
const must=(condition,message)=>{if(!condition)throw Error(message);};
function inside(base,p){
  must(typeof p==='string'&&!path.isAbsolute(p),'RELATIVE_INPUT_REQUIRED');
  const absolute=path.resolve(base,p),rel=path.relative(base,absolute);
  must(rel&&rel!=='..'&&!rel.startsWith('..'+path.sep)&&!path.isAbsolute(rel),'INPUT_ESCAPES:'+p);
  return absolute;
}
async function bytes(base,p){
  const absolute=inside(base,p),stat=await lstat(absolute),resolved=await realpath(absolute),rel=path.relative(base,resolved);
  must(stat.isFile()&&!stat.isSymbolicLink()&&rel&&rel!=='..'&&!rel.startsWith('..'+path.sep)&&!path.isAbsolute(rel),'INPUT_NOT_REGULAR:'+p);
  return readFile(absolute);
}
export function executedTests(text,workingDirectory,selectedFiles){
  const cwd=workingDirectory.replaceAll('\\','/').replace(/\/$/,'')+'/';
  const entries=[...text.replace(/\r/g,'').replace(/\x1b\[[0-9;]*m/g,'').matchAll(/^\d+:\d+\s+\+\d+(?:\s+[~-]\d+)*:\s+(.+\.dart): (.+)$/gm)];
  const identities=[];
  for(const m of entries){
    const actual=m[1].replaceAll('\\','/'),file=actual.startsWith(cwd)?actual.slice(cwd.length):actual;
    must(selectedFiles.includes(file),'EXECUTED_OUTSIDE_ACCOUNTING_SCOPE:'+actual);
    if(m[2]==='(setUpAll)'||m[2]==='(tearDownAll)')continue;
    identities.push(file+': '+m[2]);
  }
  return identities.sort();
}
export function verifyExecution(raw,workingDirectory,selectedFiles,exitCode){
  const text=raw.toString('utf8'),parsed=parseTestLog(text),identities=executedTests(text,workingDirectory,selectedFiles);
  const actualFiles=[...new Set(identities.map(id=>id.slice(0,id.indexOf(': '))))].sort();
  must(exitCode===0&&parsed?.allTestsPassed&&parsed.passedTests>0&&parsed.failedTests===0&&parsed.skippedTests===0,'ACCOUNTING_STAGE_NOT_GREEN');
  must(identities.length===parsed.passedTests&&new Set(identities).size===identities.length,'UNIQUE_ACCOUNTING_IDENTITIES_COUNT_REQUIRED');
  must(eq(actualFiles,[...selectedFiles].sort()),'EXACT_ACCOUNTING_TEST_FILE_COVERAGE_REQUIRED');
  return{parsed,identities,actualFiles,perFileCounts:actualFiles.map(file=>({file,passedTests:identities.filter(id=>id.startsWith(file+': ')).length}))};
}
async function auditInputs(){
  const bound=new Map(),read=async(p,h)=>{const b=await bytes(root,p),actual=sha(b);must((!h||h===actual)&&(!bound.has(p)||bound.get(p)===actual),'BOUND_INPUT_DRIFT:'+p);bound.set(p,actual);return b;};
  const json=async(p,h)=>JSON.parse((await read(p,h)).toString('utf8').replace(/^\uFEFF/,''));
  const source=await json(files.approvedSource),approved=await json(files.approvedRun);
  const snapshot=path.join(root,'build/w5goldens20261010/r1');
  must(source.kind==='postapproval_desktop1068_source_manifest'&&source.snapshot===snapshot&&source.selectedSources===1068&&Object.keys(source.sourceHashes??{}).length===1068&&source.currentSourceMatchesApprovedInputs===true&&source.warmSourceMatchesApprovedInputs===true,'POSTAPPROVAL1068_SOURCE_REQUIRED');
  must(source.sourceInputsSha256===sha(Buffer.from(JSON.stringify(source.sourceHashes))),'POSTAPPROVAL_SOURCE_DIGEST_INVALID');
  must(approved.stage==='approvedAll'&&approved.status==='complete'&&approved.fullSuitePassed===true&&approved.exitCode===0&&approved.integrityError===null&&approved.spawnError===null&&eq(approved.counts,{passed:2004,failed:0,skipped:0}),'FRESH_APPROVED2004_FULL_SUITE_REQUIRED');
  must(eq(approved.sourceManifest,{path:files.approvedSource,sha256:bound.get(files.approvedSource)})&&eq(approved.expectedTestIdentities,source.expectedTestIdentities)&&eq(approved.actualTestIdentities,source.expectedTestIdentities)&&source.expectedTestIdentities.length===2004&&new Set(source.expectedTestIdentities).size===2004,'APPROVED_SUITE_BINDING_INVALID');
  const fullRaw=await read(approved.log,approved.logSha256),fullParsed=parseTestLog(fullRaw.toString('utf8'));
  const desktopFiles=[...new Set(source.expectedTestIdentities.map(id=>'test/'+id.slice(0,id.indexOf(': '))))].sort();
  const fullActual=verifyExecution(fullRaw,path.join(snapshot,'apps/jentra_desktop'),desktopFiles,approved.exitCode);
  must(fullParsed.passedTests===2004&&eq(fullActual.identities.map(id=>id.slice(5)),source.expectedTestIdentities),'ACTUAL2004_APPROVED_LOG_BINDING_INVALID');
  for(const a of [approved.inputAuditBefore,approved.inputAuditAfter])must(a?.selectedSources===1068&&a.currentSourceMatchesApprovedInputs===true&&a.warmSourceMatchesApprovedInputs===true&&eq(a.sourceHashes,source.sourceHashes)&&a.sourceInputsSha256===source.sourceInputsSha256,'FULL_RUN_SOURCE_AUDIT_REQUIRED');
  must(Array.isArray(source.bindings)&&source.bindings.length>0&&new Set(source.bindings.map(b=>b.path)).size===source.bindings.length,'POSTAPPROVAL_BINDINGS_REQUIRED');
  for(const b of source.bindings)await read(b.path,b.sha256);
  const prior=await json(source.priorSourceManifest.path,source.priorSourceManifest.sha256);
  must(Array.isArray(prior.dependencyScope)&&prior.dependencyScope.length===4&&new Set(prior.dependencyScope).size===4&&eq([...prior.dependencyScope].sort(),['apps/jentra_desktop','packages/jentra_design_system','packages/jentra_domain','packages/jentra_platform']),'DESKTOP_DEPENDENCY_SCOPE_CHANGED');
  const selected=h=>Object.fromEntries(Object.entries(h).filter(([p])=>['pubspec.yaml','pubspec.lock','analysis_options.yaml'].includes(p)||prior.dependencyScope.some(d=>p.startsWith(d+'/'))||/^apps\/[^/]+\/pubspec.yaml$/.test(p)));
  const [current,warm]=await Promise.all([sources(root),sources(snapshot)]);
  must(eq(selected(current),source.sourceHashes)&&eq(selected(warm),source.sourceHashes),'CURRENT_OR_WARM1068_INPUT_DRIFT');
  const toolchain=[];
  must(eq(source.toolchain?.tooling?.map(b=>b.path),['C:/src/flutter/bin/cache/flutter.version.json',sdk,flutter,'C:/src/flutter/bin/cache/artifacts/engine/windows-x64/flutter_tester.exe']),'DEFAULT_SDK_BINDINGS_REQUIRED');
  for(const b of source.toolchain.tooling){const actual=sha(await readFile(b.path));must(actual===b.sha256,'SDK_TOOL_DRIFT:'+b.path);toolchain.push({path:b.path,sha256:actual});}
  const metadata=JSON.parse(await readFile(toolchain[0].path));
  must(eq(metadata,source.toolchain.sdkMetadata)&&metadata.frameworkVersion==='3.47.5'&&metadata.dartSdkVersion==='3.13.4','CACHED_SDK_METADATA_DRIFT');
  const resolution=[];
  for(const p of ['.dart_tool/package_config.json','.dart_tool/package_graph.json','.dart_tool/version'])resolution.push({path:p,sha256:sha(await bytes(snapshot,p))});
  const config=JSON.parse((await bytes(snapshot,'.dart_tool/package_config.json')).toString('utf8'));
  must(config.configVersion===2&&Array.isArray(config.packages)&&new Set(config.packages.map(p=>p.name)).size===config.packages.length,'PACKAGE_RESOLUTION_INVALID');
  for(const [name,member]of [['jentra_domain','packages/jentra_domain'],['jentra_platform','packages/jentra_platform'],['jentra_design_system','packages/jentra_design_system']]){
    const p=config.packages.find(p=>p.name===name);
    must(p&&path.resolve(fileURLToPath(new URL(p.rootUri,new URL('file:///'+snapshot.replaceAll('\\','/')+'/.dart_tool/package_config.json'))))===path.join(snapshot,member),'WORKSPACE_DEPENDENCY_ESCAPES_FROZEN_TREE:'+name);
  }
  const stages=[];
  for(const[stage,s]of Object.entries(specs)){
    must(s.files.length>0&&new Set(s.files).size===s.files.length,'DUPLICATE_SELECTED_TEST_FILE');
    const tests=[];
    for(const f of s.files){const p=s.member+'/'+f,h=source.sourceHashes[p];must(h&&sha(await bytes(root,p))===h&&sha(await bytes(snapshot,p))===h,'SELECTED_TEST_NOT_FROZEN:'+p);tests.push({path:p,sha256:h});}
    stages.push({stage,workingDirectory:path.join(snapshot,s.member),member:s.member,files:s.files,testFiles:tests,purpose:s.purpose,executable:sdk,args:s.args(s.files)});
  }
  for(const p of [...contracts,runnerPath,'scripts/wave5/cash_ui_evidence.mjs','scripts/wave5/record_continuation_windows.mjs'])await read(p);
  for(const[p,h]of bound)must(sha(await bytes(root,p))===h,'INPUT_DRIFT_DURING_ACCOUNTING_AUDIT:'+p);
  return{checkedAt:new Date().toISOString(),snapshot,selectedSources:1068,sourceHashes:source.sourceHashes,sourceInputsSha256:source.sourceInputsSha256,
    sourceManifest:{path:files.approvedSource,sha256:bound.get(files.approvedSource)},approvedDesktopRun:{path:files.approvedRun,sha256:bound.get(files.approvedRun)},
    currentSourceMatchesFrozenInputs:true,warmSourceMatchesFrozenInputs:true,stages,toolchain:{sdkMetadata:metadata,tooling:toolchain},resolution,
    bindings:[...bound].map(([path,sha256])=>({path,sha256})),fixturePolicy:'Existing frozen inline and relative-support fixtures; all application/test/support files are among the1068 inputs. HTTP is injected; stores use test-owned memory or unique temporary databases. No external fixture/template is added.',
    boundary:'Calculation and injected client-contract tests only. Locked resolution files and four SDK tools are bound; hosted dependencies are not independently audited file-by-file. No installed SQL/auth/MFA/native keyboard/delivery/contention/load/owner acceptance/production/billing claim.'};
}
const stableKeys=['snapshot','selectedSources','sourceHashes','sourceInputsSha256','sourceManifest','approvedDesktopRun','currentSourceMatchesFrozenInputs','warmSourceMatchesFrozenInputs','stages','toolchain','resolution','bindings','fixturePolicy','boundary'];
async function main(){
  const initial=await auditInputs();
  if(mode==='check'){
    console.log(JSON.stringify({mode,eligibleForAccountingChecks:true,selectedSources:1068,sourceInputsSha256:initial.sourceInputsSha256,stages:initial.stages.map(s=>({stage:s.stage,testFiles:s.files.length,command:[s.executable,...s.args],workingDirectory:s.workingDirectory})),outputsWritten:false,sdkExecuted:false}));return;
  }
  if(mode==='freeze'){
    await writeFile(inside(root,files.source),JSON.stringify({kind:'accounting_calculation_gateway_source_manifest',frozenAt:new Date().toISOString(),...initial},null,2)+'\n',{flag:'wx'});
    console.log(JSON.stringify({mode,manifest:files.source,sha256:sha(await bytes(root,files.source)),selectedSources:1068,sdkExecuted:false}));return;
  }
  const manifestRaw=await bytes(root,files.source),manifest=JSON.parse(manifestRaw),manifestHash=sha(manifestRaw);
  must(manifest.kind==='accounting_calculation_gateway_source_manifest','ACCOUNTING_MANIFEST_INVALID');
  for(const k of stableKeys)must(eq(manifest[k],initial[k]),'FROZEN_ACCOUNTING_INPUT_DRIFT:'+k);
  const s=initial.stages.find(s=>s.stage===mode),stem=base+'accounting-checks-'+mode+'-20261010-r2',logPath=stem+'.log',resultPath=stem+'.json';
  const startedAt=new Date().toISOString(),result=await open(inside(root,resultPath),'wx');
  let log=null,exitCode=null,spawnError=null,integrityError=null,after=null,raw=Buffer.alloc(0),parsed=null,execution=null;
  await result.writeFile(JSON.stringify({status:'in_progress',stage:mode,startedAt,sourceManifest:{path:files.source,sha256:manifestHash},executable:sdk,args:s.args,workingDirectory:s.workingDirectory,
    boundary:'Reserved before execution; interruption never implies a passing test result.'},null,2)+'\n');
  try{
    log=await open(inside(root,logPath),'wx');
    const env={...process.env};for(const n of ['W5_CASH_FRAME_DIR','W5_MODEL_FRAME_DIR','W5_AUTH_FRAME_DIR'])delete env[n];
    const child=spawn(sdk,s.args,{cwd:s.workingDirectory,env,windowsHide:true,stdio:['ignore','pipe','pipe']});
    let chain=Promise.resolve(),logError=null;
    for(const stream of [child.stdout,child.stderr])stream.on('data',b=>{chain=chain.then(()=>log.write(b)).catch(e=>{logError??=e.message;});});
    exitCode=await new Promise(resolve=>{child.on('error',e=>{spawnError={message:e.message,code:e.code??null};});child.on('close',c=>resolve(c??(spawnError?127:1)));});
    await chain;await log.close();log=null;
    raw=await bytes(root,logPath);parsed=parseTestLog(raw.toString('utf8'));
    // Always capture source/tool postflight before asserting the test outcome.
    after=await auditInputs();
    must(!logError,'ACCOUNTING_LOG_WRITE_FAILED:'+logError);
    must(sha(await bytes(root,files.source))===manifestHash,'ACCOUNTING_MANIFEST_CHANGED_DURING_RUN');
    for(const k of stableKeys)must(eq(initial[k],after[k]),'ACCOUNTING_INPUT_CHANGED_DURING_RUN:'+k);
    execution=verifyExecution(raw,s.workingDirectory,s.files,exitCode);
  }catch(e){integrityError=e.message;}
  if(log)try{await log.close();}catch(e){integrityError??=e.message;}
  if(!raw.length)try{raw=await bytes(root,logPath);parsed=parseTestLog(raw.toString('utf8'));}catch{}
  const stagePassed=exitCode===0&&!integrityError&&!!after&&!!execution;
  const report={stage:mode,status:stagePassed?'complete':'failed',startedAt,finishedAt:new Date().toISOString(),workingDirectory:s.workingDirectory,executable:sdk,args:s.args,
    sourceManifest:{path:files.source,sha256:manifestHash},log:logPath,logSha256:sha(raw),logBytes:raw.length,exitCode,spawnError,integrityError,
    counts:parsed?{passed:parsed.passedTests,failed:parsed.failedTests,skipped:parsed.skippedTests}:null,selectedTestFiles:s.testFiles,
    actualTestIdentities:execution?.identities??[],actualExecutedFiles:execution?.actualFiles??[],perFileCounts:execution?.perFileCounts??[],
    inputAuditBefore:initial,inputAuditAfter:after,stagePassed,serialFileConcurrency:1,sourceEdits:0,newTests:0,approvedImageEdits:0,acceptanceEdits:0,
    fixturePolicy:initial.fixturePolicy,boundary:initial.boundary};
  try{await result.truncate(0);await result.write(JSON.stringify(report,null,2)+'\n',0,'utf8');}finally{await result.close();}
  console.log(JSON.stringify({stage:mode,status:report.status,counts:report.counts,exitCode,integrityError,stagePassed,sourceStable:!!after,executedTestFiles:report.actualExecutedFiles.length,log:logPath}));
  if(!stagePassed)process.exitCode=1;
}
if(process.argv[1]&&path.resolve(process.argv[1])===fileURLToPath(import.meta.url))await main();
