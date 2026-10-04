import fs from 'node:fs';
import path from 'node:path';
import crypto from 'node:crypto';
import {fileURLToPath} from 'node:url';
import {decodedResult, sourceHash, verifyCandidateOrder, verifyStrictExecution} from './strict-candidate-evidence.mjs';

const repo=path.resolve(path.dirname(fileURLToPath(import.meta.url)),'../..');
const evidenceRoot=path.join(repo,'docs/verification/remaining-wave3');
const historicalManifest='docs/verification/remaining-wave3/migration-order-final-20260930-45.json';
const historicalSchema='docs/verification/remaining-wave3/schema-after-45-20260930.json';
const read=file=>JSON.parse(fs.readFileSync(path.join(repo,file),'utf8').replace(/^\uFEFF/,''));
const hash=file=>sourceHash(path.join(repo,file));
const contained=file=>{
  const resolved=path.resolve(repo,file??'');
  if(typeof file!=='string'||!resolved.startsWith(evidenceRoot+path.sep)||path.extname(resolved)!=='.json'||file.includes('\\'))throw Error('Task-owned explicit candidate selection artifact required.');
  return file;
};
const queryText=file=>{
  const resolved=path.resolve(repo,file??'');
  if(!resolved.startsWith(evidenceRoot+path.sep)||path.extname(resolved)!=='.sql')throw Error('Task-owned executed candidate query required.');
  return fs.readFileSync(resolved,'utf8').replace(/^\uFEFF/,'');
};

export function reviewedCandidateSelection(selection) {
  if(selection===undefined) return {candidate_count:45,manifest_path:historicalManifest,schema_path:historicalSchema,manifest:read(historicalManifest),schema:read(historicalSchema),artifact_paths:[historicalManifest,historicalSchema],boundary:'Historical45 library recipe only; current46 preparation requires an explicit selection.'};
  if(selection?.candidate_count!==46)throw Error('Current candidate selection must explicitly require all46 candidates.');
  const manifestPath=contained(selection.manifest_path),packagePath=contained(selection.package_path),schemaPath=contained(selection.schema_review_path);
  const manifest=read(manifestPath),installation=read(packagePath),schemaReview=read(schemaPath),historical=read(historicalManifest);
  const candidates=manifest.candidates;
  if(!Array.isArray(candidates)||candidates.length!==46||!Array.isArray(installation.candidates)||installation.candidates.length!==46||
      candidates.some((row,index)=>row.ordinal!==index+1||!/^supabase\/migrations\/\d{14}_[a-z0-9_]+\.sql$/.test(row.path)||row.sha256!==hash(row.path)||row.installed===true||row.installed_now===true||
        installation.candidates[index].path!==row.path||installation.candidates[index].ordinal!==row.ordinal||installation.candidates[index].sha256!==row.sha256)||
      historical.candidates.some((row,index)=>candidates[index].path!==row.path||candidates[index].sha256!==row.sha256)||
      candidates.at(-1).path!=='supabase/migrations/20261003090000_wave3_negative_stock_policy.sql')throw Error('Selected46 candidate source/order mismatch or omitted historical body.');
  const orderHash=crypto.createHash('sha256').update(JSON.stringify(candidates.map(({ordinal,path,sha256})=>({ordinal,path,sha256})))).digest('hex');
  if(manifest.exact_order_sha256!==orderHash||installation.exact_order_sha256!==orderHash||installation.manifest_path!==manifestPath||installation.head!==manifest.head||
      installation.compatibility?.new_tail_review?.file!==schemaPath||installation.compatibility.new_tail_review.sha256!==hash(schemaPath))throw Error('Selected package, manifest and reviewed schema bindings differ.');
  const suites=installation.fresh_strict_execution?.suites;
  if(!Array.isArray(suites)||suites.length!==3||new Set(suites.map(row=>row.suite)).size!==3||suites.some(row=>!['procurement','inventory','receivables'].includes(row.suite)))throw Error('Selected46 preparation requires all three completed strict suites.');
  const executionArtifacts=[];
  for(const row of suites) {
    const executedPath=contained(row.execution),execution=read(executedPath),query=queryText(row.query);
    const tap=verifyStrictExecution(execution,query,hash(row.query));
    verifyCandidateOrder(query,candidates,file=>fs.readFileSync(path.join(repo,file),'utf8'));
    if(row.execution_sha256!==hash(executedPath)||row.query_sha256!==hash(row.query)||tap.assertions!==row.assertions||row.failures!==0||row.candidates_source_matched!==46||row.strict_finish!==true||row.final_rollback!==true||
        candidates.some(candidate=>!query.includes(fs.readFileSync(path.join(repo,candidate.path),'utf8'))))throw Error('Selected46 strict suite source/plan mismatch.');
    executionArtifacts.push(executedPath,row.query);
  }
  const procurement=suites.find(row=>row.suite==='procurement');
  const find=(value,key)=>!value||typeof value!=='object'?[]:[...(Object.hasOwn(value,key)?[value[key]]:[]),...Object.values(value).flatMap(child=>find(child,key))];
  const observed=find(decodedResult(read(procurement.execution).result),'negative_stock_schema_review');
  if(schemaReview.execution?.file!==procurement.execution||schemaReview.execution.sha256!==hash(procurement.execution)||schemaReview.execution.query_sha256!==hash(procurement.query)||
      schemaReview.before?.schema_version!=='45-before-negative-stock-tail-20261003'||schemaReview.after?.schema_version!=='46-after-negative-stock-tail-20261003'||
      schemaReview.shared_finance_helpers?.length!==4||schemaReview.shared_finance_helpers.some(row=>row.unchanged!==true)||
      !schemaReview.after?.functions||!schemaReview.after?.tables||observed.length!==1||
      JSON.stringify(observed[0]['45_before_tail'])!==JSON.stringify(schemaReview.before)||JSON.stringify(observed[0]['46_after_tail'])!==JSON.stringify(schemaReview.after))throw Error('Selected successful46 schema review/source/helper binding mismatch.');
  return {candidate_count:46,manifest_path:manifestPath,package_path:packagePath,schema_review_path:schemaPath,manifest,schema:schemaReview.after,
    artifact_paths:[historicalManifest,manifestPath,packagePath,schemaPath,...executionArtifacts],
    boundary:'Explicit current46 source/ordered manifest and completed synthetic schema/suite selection. Installation, compatibility decisions, real actors/load/native and owner approval remain separate.'};
}
