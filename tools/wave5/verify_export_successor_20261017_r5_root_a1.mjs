// Read-only source/evidence verification, followed by one exclusive public report.
import fs from 'node:fs/promises';
import path from 'node:path';
import {fileURLToPath} from 'node:url';
import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import {EXPORTS_PRIOR,EXPORTS_LIMIT,EXPORTS_REVIEWED_BUDGET,EXPORTS_CURRENT_CHARGE,EXPORTS_CURRENT_CHARGE_EVIDENCE,EXPORTS_A6_SOURCE_BINDINGS} from './finance_exports_20261016_r5_a7.mjs';
import {RECORD as CANDIDATE_RECORD} from './prepare_export_private_adapter_20261017_r5_a3.mjs';
const root=fileURLToPath(new URL('../../',import.meta.url));
const frozen=path.join(root,'build/wave5-approved-execution-20261013-r5-a2');
const base='docs/verification/wave5/',own=base+'root-export-adapter-20261016/';
const hash=x=>createHash('sha256').update(x).digest('hex');
async function exact(file,sha256,workspace=root){
 const target=path.resolve(workspace,file),relative=path.relative(workspace,target);
 assert.ok(!relative.startsWith('..')&&!path.isAbsolute(relative));
 assert.equal(await fs.realpath(target),target);const stat=await fs.lstat(target);assert.ok(stat.isFile()&&!stat.isSymbolicLink());
 const bytes=await fs.readFile(target);assert.equal(hash(bytes),sha256,file);return bytes;
}
async function binding(file){const bytes=await fs.readFile(path.join(root,file));return {path:file,sha256:hash(bytes),bytes:bytes.length};}
const proofPath=base+'task3-export-renewal-20261016/export-a7-source-proof-a1.json';
const proof=JSON.parse(await fs.readFile(path.join(root,proofPath),'utf8'));
assert.equal(proof.kind,'source-only-export-a7-controlled-verification');assert.equal(proof.passed,true);
assert.deepEqual(proof.counts,{tests:124,pass:124,fail:0,cancelled:0,skipped:0,todo:0});
assert.equal(proof.preservedOriginalFrozenBindings,68);assert.equal(proof.exactPublicBindingCount,16);
const unique=new Map();
for(const row of proof.allBindings){assert.ok(['workspace','frozen'].includes(row.root));const key=row.root+':'+row.path;
 const bytes=await exact(row.path,row.sha256,row.root==='frozen'?frozen:root);assert.equal(bytes.length,row.bytes);
 if(unique.has(key))assert.equal(unique.get(key).sha256,row.sha256);else unique.set(key,row);
}
assert.equal(unique.size,93);assert.equal(proof.uniqueBindings,93);
for(const row of [...proof.sources,proof.controlledExecution,proof.tap,proof.contract,proof.actual137Ledger])await exact(row.path,row.sha256);
assert.deepEqual(proof.actual137Evidence,EXPORTS_CURRENT_CHARGE_EVIDENCE);
assert.deepEqual(proof.repairedA6SourceBindings,EXPORTS_A6_SOURCE_BINDINGS);
assert.equal(EXPORTS_PRIOR,141);assert.equal(EXPORTS_LIMIT,166);
assert.deepEqual(EXPORTS_REVIEWED_BUDGET,{recordedPrior:137,ownerRefreshCalls:1,renewalControlCalls:3,prior:141,ordinary:24,ordinaryLimit:165,resolution:1,total:166});
const ledger=JSON.parse(await exact(EXPORTS_CURRENT_CHARGE.path,EXPORTS_CURRENT_CHARGE.sha256));
assert.equal(ledger.actualChargedPrior,137);assert.equal(ledger.futureCallsObserved,false);assert.equal(ledger.executionPermitted,false);
const candidate=JSON.parse(await fs.readFile(path.join(root,CANDIDATE_RECORD),'utf8'));
await exact(candidate.candidate.path,candidate.candidate.sha256);await exact(candidate.predecessor.path,candidate.predecessor.sha256);
assert.equal(candidate.exportSource.sha256,proof.sources[0].sha256);assert.equal(candidate.installed,false);
await exact(candidate.readHoldSource.path,candidate.readHoldSource.sha256);
const rootTapPath=own+'root-a7-independent-suite-a1.tap',tap=await fs.readFile(path.join(root,rootTapPath),'utf8');
for(const row of ['# tests 124','# pass 124','# fail 0','# skipped 0'])assert.ok(tap.includes(row));
const controls=JSON.parse(await fs.readFile(path.join(root,own+'root-controlled-execution-a3.json'),'utf8'));
assert.equal(controls.result.exit_code,0);assert.ok(controls.result.output.includes('# pass 8'));
const absent=[];for(const file of proof.actualControlFilesAbsent){
 try{await fs.lstat(path.join(root,file));throw Error('ACTUAL_OPERATION_CONTROL_ALREADY_PRESENT:'+file);}catch(error){if(error.code!=='ENOENT')throw error;absent.push(file);}
}
const record={kind:'root-independent-export-a7-and-adapter-source-verification',passed:true,verifiedAt:new Date().toISOString(),
 sourceProof:await binding(proofPath),sourceBindings:proof.sources,exactPreservedAndNewBindings:unique.size,
 originalFrozenBindings:68,allBindingsVerified:true,exactPublicHoldInventoryCount:16,
 actualCurrentChargedCalls:137,conditionalBudgetOnly:EXPORTS_REVIEWED_BUDGET,conditionalOverallMaximum:174,
 a7IndependentTest:{toolChunkId:'c3f92b',exitCode:0,tests:124,pass:124,fail:0,skipped:0,tap:await binding(rootTapPath)},
 adapterMechanismExecution:await binding(own+'root-controlled-execution-a3.json'),
 candidate:await binding(candidate.candidate.path),candidateTechnicalReviewPending:true,
 historicalA6OriginalSha256:'2b265ea5c5f4921923a1feafb8daf8b8d2538daa20a9cc97deb1bd6b51ccf559',
 reviewedA6ChronologyRepairSha256:EXPORTS_A6_SOURCE_BINDINGS[0].sha256,oldEvidencePreserved:true,
 missingActualOperationControls:absent,privateInputsRead:false,networkCalls:0,actualRenewals:0,actualExports:0,
 acceptanceChanged:false,production:false,realBilling:false,
 limitation:'Controlled source and public-file evidence only. Actual source approval, owner decision, A10 refresh, renewal, authenticated exports and later runtime/acceptance gates remain separate.'};
const output=own+'root-successor-verification-a1.json';
await fs.writeFile(path.join(root,output),JSON.stringify(record,null,2)+'\n',{flag:'wx'});
process.stdout.write(JSON.stringify({passed:true,report:output,bindings:unique.size,a7Tests:124,adapterMechanismTests:8,actualCharge:137,networkCalls:0,privateInputsRead:false})+'\n');
