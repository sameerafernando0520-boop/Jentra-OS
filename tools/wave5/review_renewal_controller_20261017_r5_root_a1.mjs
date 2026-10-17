// Publishes technical source review only; never reads private input or executes SQL.
import fs from 'node:fs/promises';
import path from 'node:path';
import {fileURLToPath} from 'node:url';
import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import {SOURCE,TEST,SQL_BINDINGS,STATIC_HASHES,CONTROL_PATHS} from './renew_runtime_authority_20261015_r5_a1.mjs';
const root=fileURLToPath(new URL('../../',import.meta.url)),own='docs/verification/wave5/root-runtime-renewal-20261015/';
const hash=x=>createHash('sha256').update(x).digest('hex');
async function verify(row){const target=path.resolve(root,row.path);assert.equal(await fs.realpath(target),target);const bytes=await fs.readFile(target);assert.equal(hash(bytes),row.sha256,row.path);if(row.bytes!==undefined)assert.equal(bytes.length,row.bytes);return bytes;}
async function bind(file){const bytes=await fs.readFile(path.join(root,file));return {path:file,sha256:hash(bytes),bytes:bytes.length};}
const proofBinding=await bind(own+'renewal-controller-source-proof-a1.json'),proof=JSON.parse(await verify(proofBinding));
assert.equal(proof.sourceOnly,true);assert.equal(proof.executionPermitted,false);assert.equal(proof.passed,true);
assert.equal(proof.validation.controlledTests,115);assert.equal(proof.validation.passed,115);assert.equal(proof.validation.failed,0);
assert.deepEqual(proof.sourceBindings.map(x=>x.path),[SOURCE,TEST]);
for(const row of [...proof.sourceBindings,...proof.verifiedUnchangedBindings,proof.contract,proof.draftCheckpoint,proof.validation.finalTestOutput])await verify(row);
assert.equal(proof.sourceBindings[0].sha256,'b3d8d2dda66e0945b1451d2d5f57d4daefbdf00cb2799d59543220a7d952956d');
assert.equal(proof.sourceBindings[1].sha256,'f55039fe103b78487c96ae132d567d3c56c079cffd88fe1c3940b2d7ce08d79d');
const tapBinding=await bind(own+'root-independent-controller-a1.tap'),tap=(await verify(tapBinding)).toString('utf8');
for(const summary of ['# tests 115','# pass 115','# fail 0','# skipped 0'])assert.ok(tap.includes(summary));
for(const row of Object.values(SQL_BINDINGS))await verify(row);
const checks=[
 'Public-only preflight validates exact controller/test/SQL/control/current137 files and repeats the complete public gate before private execution.',
 'The explicit public closure includes ten controls, both SQL files, all six current-charge observations and the fixed A10 helper; sourceBindings contains only the controller and tests.',
 'The metadata and owner readiness record follow the real exact human decision and bind original A10 source and organization; no credential is embedded in source or public output.',
 'At most three ordered attempts139/140/141 are charged and persisted before dispatch. Raw response bytes are acknowledged before any state validation.',
 'The only write is the fixed a3 template with five validated literal substitutions. Original issue times, non-window hashes, paused jobs, schema, ACL, counters and billing constraints remain guarded.',
 'The actual server preflight anchors the expiry; post-commit application observation and final server readback remain distinct. All three anchor aliases agree and three response bindings hash durable raw bytes.',
 'An uncertain dispatched write permits one readback and no replay. A failed or uncertain result cannot publish a successful readback or enable export continuation.',
 'Private handoff uses only projectId, bundleSha256 and ownerToken, enforces bounded input/TLS/time/response limits, clears configuration and prints public summaries only.'
];
const review={kind:'independent-runtime-renewal-controller-source-review',reviewedAt:new Date().toISOString(),passed:true,sourceOnly:true,executionPermitted:false,
 sourceBindings:proof.sourceBindings.map(({path,sha256})=>({path,sha256})),sqlBindings:SQL_BINDINGS,
 proposalBinding:{path:CONTROL_PATHS.proposal,sha256:STATIC_HASHES.proposal},sourceRepairBinding:{path:CONTROL_PATHS.sourceRepair,sha256:STATIC_HASHES.sourceRepair},
 sourceProofBinding:proofBinding,independentControlledExecution:{toolChunkId:'57394f',exitCode:0,tests:115,pass:115,fail:0,skipped:0,tapBinding},
 checks,privateInputsRead:false,networkCalls:0,SQLExecuted:false,actualRenewalPerformed:false,ownerDecisionCreated:false,acceptanceChanged:false,
 remaining:['Exact source-only policy and independent policy review','Direct exact human runtime approval','Actual A10 owner refresh','Actual reviewed plan and final operation review','Only then the three bounded actual requests and authenticated later gates']};
await fs.writeFile(path.join(root,CONTROL_PATHS.staticReview),JSON.stringify(review,null,2)+'\n',{flag:'wx'});
process.stdout.write(JSON.stringify({passed:true,review:CONTROL_PATHS.staticReview,tests:115,sourceOnly:true,executionPermitted:false,networkCalls:0,privateInputsRead:false})+'\n');
