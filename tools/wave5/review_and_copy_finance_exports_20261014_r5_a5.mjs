import fs from 'node:fs/promises';
import path from 'node:path';
import {fileURLToPath} from 'node:url';
import {hashBytes} from './runtime_contract.mjs';
const root=fileURLToPath(new URL('../../',import.meta.url)),base='docs/verification/wave5/',snapshot=path.join(root,'build/wave5-approved-execution-20261013-r5-a2');
const must=(v,c)=>{if(!v)throw Error(c);},evidence=[];
async function exact(file,pin){const b=await fs.readFile(path.join(root,file));must(hashBytes(b)===pin,'EXACT_EXPORT_SOURCE_REVIEW_REQUIRED');evidence.push({path:file,bytes:b.length,sha256:pin});return JSON.parse(b);}
await exact(base+'approved-isolated-execution-snapshot-20261013-r5-a2.json','9c9e856c2cfdb852a3a9b9e66474f14c86a32dc72cc5b613e806699b2fb78c01');
const proof=await exact(base+'task3-export-continuation-20261014/export-source-proof-a1.json','a2e2dcbac7393fa7eac5c315988497428eabd7956e3d25f95ff54099432e307f');
const peer=await exact(base+'task3-export-source-independent-20261014/independent-source-review-a1.json','1223b1efdd7b85d73742f2f6aa5f4192d90907b6bbd6e45bd20d567649a0dd9d');
const actual=await exact(base+'finance-exports-root-controlled-verification-20261014-r5-a6.json','2c248d90cebc7ab2e8dcbd8fc4715514b5e5d7b18f72621bdcefd905ca5d5f36');
must(proof.sources.length===3&&proof.controlledTests.passed===54&&peer.sourceCandidateApproved===true&&peer.liveExecutionAuthorizedByThisReview===false&&peer.actualTests.total===64&&peer.actualTests.failed===0&&actual.exitCode===0&&actual.sourceStable&&actual.counts.passed===54,'CURRENT_CONTROLLED_AND_INDEPENDENT_EXPORT_SOURCE_REQUIRED');
must(JSON.stringify(proof.sources)===JSON.stringify(peer.authoredSources)&&JSON.stringify(proof.sources)===JSON.stringify(actual.sourceBindingsBefore),'IDENTICAL_TESTED_EXPORT_BYTES_REQUIRED');
const oldPlanBytes=await fs.readFile(path.join(snapshot,base+'finance-remaining-preparation-20261014-r5-a3.json'));must(hashBytes(oldPlanBytes)==='6c39a389ebaec0315774500af2af1e71874486173d85a3e352ef5782153e1198','EXACT_PRESERVED_A3_PLAN_REQUIRED');
const oldPlan=JSON.parse(oldPlanBytes);
for(const binding of oldPlan.sourceBindings)must(hashBytes(await fs.readFile(path.join(snapshot,binding.path)))===binding.sha256,'OLD_SNAPSHOT_SOURCE_OR_EVIDENCE_CHANGED');
must(path.resolve(await fs.realpath(snapshot))===path.resolve(snapshot),'REAL_ORIGINAL_EXECUTION_ROOT_REQUIRED');
const copies=[];
for(const binding of proof.sources){
 must(/^[a-zA-Z0-9_./-]+$/.test(binding.path)&&!binding.path.includes('..')&&!oldPlan.sourceBindings.some(x=>x.path===binding.path),'ONLY_ADDITIVE_EXPORT_SOURCE_REQUIRED');
 const bytes=await fs.readFile(path.join(root,binding.path));must(hashBytes(bytes)===binding.sha256&&bytes.length===binding.bytes,'EXACT_CURRENT_EXPORT_COPY_SOURCE_REQUIRED');
 const destination=path.resolve(snapshot,binding.path);must(destination.startsWith(path.resolve(snapshot)+path.sep),'SNAPSHOT_EXPORT_PATH_REQUIRED');
 const parent=path.dirname(destination);await fs.mkdir(parent,{recursive:true});must(path.resolve(await fs.realpath(parent))===parent,'EXPORT_PARENT_REPARSE_FORBIDDEN');
 await fs.writeFile(destination,bytes,{flag:'wx'});must(hashBytes(await fs.readFile(destination))===binding.sha256,'ACTUAL_EXACT_LOCAL_EXPORT_COPY_REQUIRED');
 copies.push({...binding,snapshotPath:path.relative(root,destination).split(path.sep).join('/')});
}
for(const binding of oldPlan.sourceBindings)must(hashBytes(await fs.readFile(path.join(snapshot,binding.path)))===binding.sha256,'ORIGINAL_A3_SNAPSHOT_CHANGED_AFTER_COPY');
const record={kind:'source-only-reviewed-additive-export-snapshot-copy',recordedAt:new Date().toISOString(),projectId:'xpdoufauvrbdmxgngetv',copies,originalA3SourceAndEvidenceBindingsPreserved:oldPlan.sourceBindings.length,evidence,
 originalAuthorityExpiresAt:'2026-10-14T09:57:07.481942Z',originalAuthorityExpired:Date.now()>=Date.parse('2026-10-14T09:57:07.481942Z'),
 historicalCandidateBudgetOnly:{conditionalPrior:132,cumulativeLimit:157,currentConservativeChargedPrior:133,requiresAdditiveFutureBudgetAndExpiryReview:true},
 actualA10Refresh:false,ownerMetadataCreated:false,executionProfileCreated:false,generatedPlanCreated:false,privateAdapterModesAdded:false,privateInputsRead:false,networkCalls:0,actualExportWrites:0,existingFilesOverwritten:0,production:false,realBilling:false};
const out=base+'finance-exports-root-source-review-and-copy-20261014-r5-a5.json',text=JSON.stringify(record,null,2)+'\n';await fs.writeFile(path.join(root,out),text,{flag:'wx'});process.stdout.write(JSON.stringify({path:out,sha256:hashBytes(text),sourceCopies:3,preservedBindings:oldPlan.sourceBindings.length,actualExports:false,expiredRuntimeExecutionAuthorized:false})+'\n');
