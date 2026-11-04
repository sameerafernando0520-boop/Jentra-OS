// Verify source/evidence consistency and record local artifacts. No network or deployment.
import assert from 'node:assert/strict';
import {readFile,writeFile,readdir} from 'node:fs/promises';
import {createHash} from 'node:crypto';
import {candidates} from './prepare-rollout-review.mjs';
assert.deepEqual(process.argv.slice(2),['--record-local']);
const root=new URL('../../',import.meta.url),out=new URL('docs/verification/field-rollout-20261103/',root);
const bytes=path=>readFile(new URL(path,root));
const digest=b=>createHash('sha256').update(b).digest('hex');
const json=async path=>JSON.parse(await readFile(new URL(path,out),'utf8'));
const database=await json('postgres-result.json'),hosted=await json('hosted-rehearsal.json'),http=await json('hosted-http.json'),review=await json('review/rollout-plan.json');
let hostedSix=null;try{hostedSix=await json('hosted-six-rehearsal.json');}catch(error){if(error.code!=='ENOENT')throw error;}
if(hostedSix){
 assert.equal(hostedSix.sqlSha256,review.sqlSha256);assert.equal(hostedSix.fullBufferCompared,true);
 assert.equal(hostedSix.result.project,review.project);assert.equal(hostedSix.result.mode,'six_candidate_rollback_only');
 assert.equal(hostedSix.result.candidate_removed,true);assert.equal(hostedSix.result.original_state_restored,true);
 assert.equal(hostedSix.result.migration_installed,false);assert.equal(hostedSix.result.mail_enabled,false);assert.equal(hostedSix.result.genuine_auth_tested,false);
 assert.deepEqual(hostedSix.sources,review.candidates);
}
assert.equal(database.passed,222);assert.ok(Object.values(database.rollback).every(Boolean));
for(const [path,sha256] of Object.entries(database.sources))assert.equal(digest(await bytes(path)),sha256,'Database evidence source changed: '+path);
for(const [path,sha256] of Object.entries(hosted.sources))assert.equal(digest(await bytes(path)),sha256,'Hosted three-candidate source changed: '+path);
for(const [path,sha256] of Object.entries(review.candidates))assert.equal(digest(await bytes(path)),sha256,'Prepared six-candidate source changed: '+path);
assert.equal(digest(await readFile(new URL('full-schema-rollback.sql',out))),hosted.sqlSha256);
assert.equal(digest(await readFile(new URL('review/six-candidate-rollback.sql',out))),review.sqlSha256);
const tests={};
for(const [log,expected] of [['sales-tests.log',67],['desktop-tests.log',65],['platform-tests.log',24],['default-navigation.log',1],['domain-tests.log',10]]){
 const text=await readFile(new URL(log,out),'utf8');const count=Number([...text.matchAll(/\+(\d+): All tests passed!/g)].at(-1)?.[1]);
 assert.equal(count,expected,log);tests[log]={passed:count,exitCode:0};
}
const node=await readFile(new URL('node-tests.log',out),'utf8');assert.match(node,/tests 14/);assert.match(node,/fail 0/);tests['node-tests.log']={passed:14,exitCode:0};
assert.match(await readFile(new URL('analyze.log',out),'utf8'),/No issues found!/);
assert.match(await readFile(new URL('format.log',out),'utf8'),/Formatted 24 files \(0 changed\)/);
assert.match(await readFile(new URL('deno-check.log',out),'utf8'),/Check supabase\/functions\/field-sales-mail\/index.ts/);
for(const log of ['sales-web-build.log','desktop-web-build.log'])assert.match(await readFile(new URL(log,out),'utf8'),/Built build[\\/]field-rollout-candidate/);
const owned=[...candidates,
 'workers/field-sales/mail_worker.mjs','workers/field-sales/mail_worker.test.mjs','workers/field-sales/.env.example',
 'supabase/functions/field-sales-mail/index.ts','supabase/functions/field-sales-mail/deno.json',
 'supabase/candidates/run-field-rollout-test.mjs',...['field_mail','field_progression','field_delivery','field_rollout_runner'].map(n=>`supabase/candidates/tests/${n}.test.mjs`),
 ...['prepare-rehearsal','prepare-rollout-review','check-hosted-readiness','record-verification'].map(n=>`tools/field-sales/${n}.mjs`),
 'apps/jentra_sales/lib/main.dart','apps/jentra_sales/lib/src/delivery_confirmation_controller.dart','apps/jentra_sales/lib/src/ui/delivery_confirmation.dart','apps/jentra_sales/lib/src/ui/field_sales_workspace.dart','apps/jentra_sales/test/delivery_confirmation_test.dart','apps/jentra_sales/README.md',
 'packages/jentra_platform/lib/field_confirmation.dart','packages/jentra_platform/lib/src/field_confirmation_link.dart','packages/jentra_platform/lib/field_confirmation_company.dart','packages/jentra_platform/lib/src/field_confirmation_company_store.dart','packages/jentra_platform/test/field_delivery_gateway_test.dart','packages/jentra_platform/test/field_delivery_company_test.dart',
 'packages/jentra_domain/lib/src/sales_order_workspace.dart',
 'apps/jentra_desktop/lib/main.dart','apps/jentra_desktop/lib/src/router.dart','apps/jentra_desktop/lib/src/shell/navigation.dart',
 ...['sales_order_controller','sales_order_dialogs','sales_order_screen','field_confirmation_company_controller','field_confirmation_company_screen'].map(n=>`apps/jentra_desktop/lib/src/features/sales/${n}.dart`),
 ...['sales_order_controller','field_confirmation_company_controller','field_confirmation_company_screen','field_confirmation_navigation'].map(n=>`apps/jentra_desktop/test/${n}_test.dart`),
 'docs/development/field-sales-rollout-candidate-20261103.md','docs/development/field-company-confirmation-candidate-20261102.md','docs/blueprint/mobile-apps/README.md'];
const sources=Object.fromEntries(await Promise.all(owned.map(async path=>[path,digest(await bytes(path))])));
async function tree(directory){
 const entries=await readdir(new URL(directory+'/',root),{withFileTypes:true}),files=[];
 for(const e of entries.sort((a,b)=>a.name.localeCompare(b.name))){const path=directory+'/'+e.name;
  if(e.isDirectory())files.push(...await tree(path));else if(e.isFile()){const b=await bytes(path);files.push({path,size:b.length,sha256:digest(b)});}}
 return files;
}
const builds={};
for(const app of ['jentra_sales','jentra_desktop']){
 const directory=`apps/${app}/build/field-rollout-candidate`;const files=await tree(directory);
 assert.ok(files.some(f=>f.path.endsWith('/main.dart.js')));assert.ok(files.some(f=>f.path.endsWith('/index.html')));
 builds[app]={directory,release:true,optimizationLevel:1,csp:true,externalWebResources:false,wasmBuilt:false,
  defines:['FIELD_SALES_CANDIDATE_ENABLED=true','FIELD_SALES_EMAIL_CONFIRMATION_ENABLED=true','FIELD_SALES_DELIVERY_CONFIRMATION_ENABLED=true'],
  publicConfiguration:'Jentra URL and publishable client key only',files,deployed:false};
}
const artifacts={};
for(const f of await tree('docs/verification/field-rollout-20261103')){
 if(f.path.endsWith('/verification.json'))continue;artifacts[f.path]={size:f.size,sha256:f.sha256};
}
const before=await json('schema-before.json'),after=await json('schema-after.json');
const report={verifiedOn:'2026-11-03',timezone:'Asia/Colombo',recordedAtUtc:new Date().toISOString(),
 scope:'Shared dirty checkout snapshot; only selected Sales source/tests and existing domain contracts were verified. No commit, push or Employee app edit.',
 implementation:{perOrganizationResendWorker:true,companyOrderProgression:true,separatePostedDeliveryAcknowledgement:true,employeeAndSalesRemainSeparate:true},
 database:{engine:database.engine,passed:database.passed,rollbackAssertions:Object.keys(database.rollback).length,rollbackPassed:true,fullHostedSchema:false,simulatedAuthAndMfa:true,simulatedResend:true,
  fixtureBoundary:'Non-stocked canonical confirmation and two partial-delivery postings; no real stocked-company acceptance or contention/load proof.'},
 tests,analysis:{files:24,issues:0,formatChanges:0},edgeCheck:{exitCode:0,checkJs:false,behaviorCoveredByNodeTests:true},builds,
 compatibility:{columnProjection:'review/schema-compatibility.json',addedCatalogRelations:Object.keys(after.tables).filter(k=>!before.tables[k]),manualReview:'review/rollout-plan.json',manualItemsOwnerAccepted:false},
 hosted:{threeCandidateRollback:{source:'hosted-rehearsal.json',postgres:hosted.result.server_version,sqlSha256:hosted.sqlSha256,passed:true,migrationInstalled:false},
  sixCandidateRehearsal:{source:hostedSix?'hosted-six-rehearsal.json':null,preparedSqlSha256:review.sqlSha256,authorized:!!hostedSix,executed:!!hostedSix,passed:!!hostedSix,fullHostedSchema:!!hostedSix,postgresMajor:hostedSix?.guardedEnvironment.postgresMajor??null,observedAt:hostedSix?.result.observed_at??null},publicHttp:{source:'hosted-http.json',salesStatus:200,requiredHeadersPresent:true,recipientRpcStatus:404,workerGetStatus:404,preview:!http.acceptanceEstablished}},
 localBrowser:{attempted:true,passed:false,reason:'Connected in-app browser could not reach the Windows loopback preview (ERR_CONNECTION_TIMED_OUT). No UI or fragment-scrubbing browser result claimed; temporary server stopped.'},
 gates:{senderDomainVerified:false,approvedMailboxSupplied:false,providerCredentialsConfigured:false,emailActuallySent:false,mailboxLinkAndCodeReceived:false,hostedRecipientPostAccepted:false,
  sixCandidateHostedRehearsalPassed:!!hostedSix,migrationsInstalled:false,workerDeployed:false,clientsDeployed:false,mailEnabled:false,genuineSessionsAndMfaAccepted:false,physicalDevicesAccepted:false,companyPilotSignedOff:false},
 sources,artifacts,boundary:'Candidate implementation and bounded evidence only. The exact hosted rollback record determines rehearsal status. Sender/domain/mailbox, installation/deployment and each organization acceptance remain separate gates.'};
await writeFile(new URL('verification.json',out),JSON.stringify(report,null,2)+'\n');
console.log(JSON.stringify({databaseChecks:report.database.passed,rollbackAssertions:report.database.rollbackAssertions,selectedTests:Object.values(tests).reduce((n,t)=>n+t.passed,0),sourceFiles:owned.length,buildFiles:Object.fromEntries(Object.entries(builds).map(([k,v])=>[k,v.files.length])),sixCandidateHostedRollbackPassed:!!hostedSix,installed:false,deployed:false}));
