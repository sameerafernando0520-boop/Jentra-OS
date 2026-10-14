import fs from 'node:fs/promises';
import path from 'node:path';
import crypto from 'node:crypto';
import assert from 'node:assert/strict';
import {fileURLToPath} from 'node:url';
const folder=path.dirname(fileURLToPath(import.meta.url)),root=path.resolve(folder,'../../../..');
const sha=b=>crypto.createHash('sha256').update(b).digest('hex');
const evidence=[];
async function read(relative,expected){assert.ok(!path.win32.isAbsolute(relative)&&!relative.split('/').includes('..'));
 const b=await fs.readFile(path.join(root,relative));if(expected)assert.equal(sha(b),expected,relative);
 if(!evidence.some(x=>x.path===relative))evidence.push({path:relative,bytes:b.length,sha256:sha(b)});return b;}
async function json(relative,expected){return JSON.parse(await read(relative,expected));}
const candidatePath='docs/verification/wave5/task3-v7-provider-20261014/candidate-manifest.json';
const candidate=await json(candidatePath,'49a943f5a26de7d17c49ac3fef3f3bd43a2a53122297cebb55c786792523bbc6');
const {candidateBundleSha256,...body}=candidate;assert.equal(sha(JSON.stringify(body)),candidateBundleSha256);
assert.equal(candidate.projectId,'xpdoufauvrbdmxgngetv');assert.equal(candidate.sources.length,7);
assert.equal(candidate.retainedLimits.authorityExpiresAt,'2026-10-14T09:57:07.481942Z');
assert.equal(candidate.retainedLimits.maximumModelCalls,4);assert.equal(candidate.retainedLimits.maximumScheduleRequestsOriginal,4320);
assert.equal(candidate.retainedLimits.scheduledRequestsAlreadyObserved,24);assert.equal(candidate.retainedLimits.extendedExpiry,false);
assert.equal(candidate.compatibility.providerKeyShapeIsAuthenticityProof,false);
const proof=await json('docs/verification/wave5/task3-v7-provider-20261014/source-proof.json',
 'ea94c14e3ee120216796546f6f57e5a6b4820c0ae01b53266816c9efc3688013');
for(const binding of [...candidate.sources,...proof.sourceBindings,...proof.oldBindingPopulationPreserved]){
 const b=await read(binding.path,binding.sha256);assert.equal(b.length,binding.bytes,binding.path);}
const verification=await json(candidate.verification.path,candidate.verification.sha256);
assert.equal(verification.exitCode,0);assert.equal(verification.sourcesUnchangedDuringRun,true);
assert.deepEqual(verification.counts,{tests:21,pass:21,fail:0,cancelled:0,skipped:0,todo:0});
await read(verification.log.path,verification.log.sha256);
const graphs=[],payloads=[];const payloadRows=[];
for(const item of candidate.deployments){const b=await read(item.payload.path,item.payload.sha256);assert.equal(b.length,item.payload.bytes);
 const payload=JSON.parse(b);assert.equal(payload.project_id,candidate.projectId);assert.equal(payload.name,item.name);
 assert.equal(payload.verify_jwt,false);assert.equal(payload.entrypoint_path,item.entrypoint);
 assert.equal(payload.files.length,item.name==='wave5-runtime'?17:10);
 assert.equal(new Set(payload.files.map(x=>x.name)).size,payload.files.length);
 assert.deepEqual(payload.files.map(x=>x.name).sort(),item.files.map(x=>x.path).sort());
 const names=new Set(payload.files.map(x=>x.name));const seen=new Set();
 async function walk(file){if(seen.has(file))return;assert.ok(names.has(file),file);seen.add(file);
  const source=payload.files.find(x=>x.name===file).content;
  const imports=[...source.matchAll(/(?:import|export)[^\n]*?\bfrom\s*['"]([^'"]+)['"]/g)].map(x=>x[1]);
  const dynamic=[...source.matchAll(/\bimport\s*\(\s*['"]([^'"]+)['"]\s*\)/g)].map(x=>x[1]);
  assert.equal((source.match(/\bimport\s*\(/g)??[]).length,dynamic.length,'nonliteral dynamic import');
  for(const specifier of [...imports,...dynamic]){if(specifier.startsWith('node:'))continue;assert.ok(specifier.startsWith('.'));
   await walk(path.posix.normalize(path.posix.join(path.posix.dirname(file),specifier)));}}
 await walk(item.entrypoint);assert.equal(seen.size,item.name==='wave5-runtime'?16:9);
 for(const row of item.files){const actual=await read(row.path,row.sha256);assert.equal(actual.length,row.bytes);
  assert.equal(payload.files.find(x=>x.name===row.path).content,actual.toString('utf8'));payloadRows.push({worker:item.name,...row});}
 graphs.push({worker:item.name,allLiteralImportsPresent:true,reachableModules:seen.size});payloads.push(item.payload);}
assert.equal(payloadRows.length,27);assert.equal(new Set(payloadRows.map(x=>x.path)).size,20);
const report={kind:'primary-independent-frozen-worker-v7-candidate-integrity-review',reviewedAt:new Date().toISOString(),
 projectId:candidate.projectId,candidateBinding:evidence.find(x=>x.path===candidatePath),candidateBundleSha256,
 exactSourceFilesVerified:7,exactPayloadRowsVerified:27,uniqueDeploymentFiles:20,uniqueSourceModules:18,
 oldSourceBindingsVerified:proof.oldBindingPopulationPreserved.length,authorControlledTestsPassed:21,graphs,payloads,
 technicalSourceIntegrityPassed:true,independentAdversarialReviewStillRequired:true,
 deploymentOperationAuthorized:false,liveRequestsByReviewer:0,privateInputsRead:false,
 schedulesMustRemainPaused:true,originalExpiryRetained:candidate.retainedLimits.authorityExpiresAt,
 actualServiceKeyValidityVerified:false,actualDelivery:false,authenticatedNativeAcceptance:false,targetScaleLoad:false,productionReleaseReady:false,evidence};
const b=Buffer.from(JSON.stringify(report,null,2)+'\n'),output=path.join(folder,'worker-v7-independent-candidate-integrity-20261014.json');
await fs.writeFile(output,b,{flag:'wx'});process.stdout.write(JSON.stringify({passed:true,path:path.relative(root,output).replaceAll('\\','/'),sha256:sha(b)})+'\n');
