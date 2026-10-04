import fs from 'node:fs';
import crypto from 'node:crypto';
import {execFileSync} from 'node:child_process';
import {artifactTag, verifyCandidateOrder, verifyStrictExecution, writeNewJson} from './strict-candidate-evidence.mjs';

// A derivative of completed strict responses only; this sends no SQL.
const base='docs/verification/remaining-wave3/';
const read=file=>JSON.parse(fs.readFileSync(file,'utf8').replace(/^\uFEFF/,''));
const hash=file=>crypto.createHash('sha256').update(fs.readFileSync(file)).digest('hex');
const [packagePath,inputPath,schemaPath,selectedTag='20261003']=process.argv.slice(2);
const tag=artifactTag(selectedTag);
if(![packagePath,inputPath,schemaPath].every(file=>file&&fs.existsSync(file)))throw Error('Pass prepared46 package, explicit completed3suite inputs and observed45→46 schema report.');
const prepared=read(packagePath),input=read(inputPath),schema=read(schemaPath);
const head=execFileSync('git',['rev-parse','HEAD'],{encoding:'utf8'}).trim();
if(prepared.head!==head||prepared.candidates?.length!==46||prepared.candidates.some(row=>row.sha256!==hash(row.path)))throw Error('Current46candidate preparation/source drift.');
if(!Array.isArray(input.suites)||input.suites.length!==3||new Set(input.suites.map(row=>row.suite)).size!==3||input.suites.some(row=>!['procurement','inventory','receivables'].includes(row.suite)))throw Error('Explicit completed procurement/inventory/receivables executions required.');
const suites=input.suites.map(row=>{
  const evidence=read(row.execution),query=fs.readFileSync(row.query,'utf8').replace(/^\uFEFF/,'');
  const tap=verifyStrictExecution(evidence,query,hash(row.query));
  verifyCandidateOrder(query,prepared.candidates);
  return {...row,execution_sha256:hash(row.execution),query_sha256:hash(row.query),observed_at:evidence.observed_at,assertions:tap.assertions,failures:0,candidates_source_matched:46,strict_finish:true,final_rollback:true,
    boundary:'Actual sequential TAP plan/result from a completed source-matched46candidate strict rollback execution; no persistent installation or independent-session/native/load/owner acceptance.'};
});
const procurement=suites.find(row=>row.suite==='procurement');
if(schema.execution?.query_sha256!==procurement.query_sha256||schema.execution?.sha256!==procurement.execution_sha256||schema.shared_finance_helpers?.some(row=>!row.unchanged))throw Error('Observed schema comparison differs from actual procurement execution.');
const report={generated_at:new Date().toISOString(),head,project_id:'xpdoufauvrbdmxgngetv',prepared_package:{file:packagePath,sha256:hash(packagePath)},
  candidates:prepared.candidates,suites,total_suite_assertions:suites.reduce((sum,row)=>sum+row.assertions,0),
  assertion_count_boundary:'Suite assertion counts overlap; sum is a recorded execution count, not a distinct behavior count or exhaustive proof. Historical1328 counts are not added or relabelled.',
  schema_review:{file:schemaPath,sha256:hash(schemaPath),summary:schema.summary},
  installed_baseline:{refresh:prepared.refresh_path,sha256:prepared.refresh_sha256,observed_at:prepared.observed_at,installed:prepared.installed_count,api_functions:prepared.api_functions},
  boundary:'Fresh46candidate synthetic strict rollback responses and actual45→46 metadata review. Existing development ledger remains separately observed; persistent migration installation, genuine authenticated sessions, target-scale/p95, native profile/recovery and owner signoff remain unverified.',
};
const reportPath=base+`database-verification-negative-stock-policy-${tag}.json`;
const output=base+`database-installation-package-negative-stock-policy-${tag}-46-reviewed.json`;
if([reportPath,output].some(file=>fs.existsSync(file)))throw Error('Retain completed derivative evidence; choose an unused artifact tag.');
writeNewJson(reportPath,report);
const reviewed={...prepared,generated_at:new Date().toISOString(),fresh_strict_execution:{file:reportPath,sha256:hash(reportPath),suites},
  compatibility:{...prepared.compatibility,new_tail_review:{file:schemaPath,sha256:hash(schemaPath),summary:schema.summary},status:'historical45_review_retained_actual46_tail_metadata_review_complete_concrete_data_older_client_acceptance_pending'},
  boundary:'Reviewed46candidate source order and fresh synthetic strict rollback verification with actual tail metadata review. No candidate installed; concrete compatibility/data/resources/restore/actor/native acceptance bindings and owner release remain open.',
};
writeNewJson(output,reviewed);
console.log(JSON.stringify({output,evidence:reportPath,suites:suites.map(({suite,assertions})=>({suite,assertions})),total:report.total_suite_assertions,schema:schema.summary,installed:false}));
