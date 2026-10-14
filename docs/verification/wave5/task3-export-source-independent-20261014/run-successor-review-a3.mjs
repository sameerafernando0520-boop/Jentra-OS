import fs from 'node:fs/promises';
import path from 'node:path';
import {fileURLToPath} from 'node:url';
import {createHash} from 'node:crypto';
import {spawnSync} from 'node:child_process';
const root=fileURLToPath(new URL('../../../../',import.meta.url)),prefix='docs/verification/wave5/task3-export-source-independent-20261014/';
const hash=bytes=>createHash('sha256').update(bytes).digest('hex'),node='C:/Program Files/nodejs/node.exe';
const authorPath='docs/verification/wave5/task3-export-continuation-20261014/export-source-local-verification-a3.json';
const authorBytes=await fs.readFile(path.join(root,authorPath));
if(hash(authorBytes)!=='4576bbf86ef0143ebb66180491a7a3dc94ef4f1c255bd37093ff2aed117841c9')throw Error('EXACT_AUTHOR_SUCCESSOR_PROOF_REQUIRED');
const author=JSON.parse(authorBytes),sources=author.authoredSources;
const expected=['ab9ec8c1a97a0a009081e5aba58db1359fd6d5df3a3d0ce2680bf4c43f50a544','030c44b84a8c5073c6c2157352fd70783c232ee256befda6ec28e9b6a723cd32','fedd5d9c86d767508bc9e214225316f457ac3b24dce1e1359a581448c998a351'];
async function bind(file){const bytes=await fs.readFile(path.join(root,file));return {path:file,bytes:bytes.length,sha256:hash(bytes)};}
const before=await Promise.all(author.sourceBindingsBefore.map(row=>bind(row.path)));
if(JSON.stringify(before)!==JSON.stringify(author.sourceBindingsBefore)||sources.some((row,i)=>row.sha256!==expected[i]))throw Error('EXACT_FROZEN_SUCCESSOR_POPULATION_REQUIRED');
const original=await fs.readFile(path.join(root,sources[2].path),'utf8');
const from="const base='docs/verification/wave5/task3-export-continuation-20261014';",to="const base='docs/verification/wave5/task3-export-source-independent-20261014';";
if(original.split(from).length!==2)throw Error('EXACT_ONE_OUTPUT_REDIRECTION_REQUIRED');
const peer=await fs.readFile(path.join(root,prefix+'peer-cases-a1.mjs'),'utf8'),runnerText=original.replace(from,to)+'\n'+peer;
const runnerPath=prefix+'independent-successor-combined-a3.test.mjs';await fs.writeFile(path.join(root,runnerPath),runnerText,{flag:'wx'});
const syntax=sources.map(row=>{const result=spawnSync(node,['--check',path.join(root,row.path)],{cwd:root,encoding:'utf8',timeout:10000});return {path:row.path,exitCode:result.status,signal:result.signal,stderr:result.stderr};});
const result=spawnSync(node,['--test','--test-reporter=tap','--test-concurrency=1',path.join(root,runnerPath)],{cwd:root,encoding:'utf8',timeout:45000,maxBuffer:8*1024*1024});
const output=Buffer.from((result.stdout||'')+(result.stderr||'')),tapPath=prefix+'independent-successor-tests-a3.tap';await fs.writeFile(path.join(root,tapPath),output,{flag:'wx'});
const count=name=>{const m=output.toString().match(new RegExp('^# '+name+' (\\d+)\\r?$','m'));if(!m)throw Error('ACTUAL_TAP_COUNTS_REQUIRED');return Number(m[1]);};
const after=await Promise.all(author.sourceBindingsBefore.map(row=>bind(row.path))),unchanged=JSON.stringify(before)===JSON.stringify(after);
const passed=result.status===0&&count('tests')===64&&count('pass')===64&&count('fail')===0&&count('cancelled')===0&&count('skipped')===0&&unchanged&&syntax.every(row=>row.exitCode===0);
const proof={kind:'independent-controlled-export-successor-source-verification',reviewer:'/root/completion_peer',checkedAt:new Date().toISOString(),passed,
 authorProof:{path:authorPath,sha256:hash(authorBytes),bytes:authorBytes.length},authoredSources:sources,
 originalAuthorTestSource:sources[2],copiedRunner:{path:runnerPath,sha256:hash(runnerText),bytes:Buffer.byteLength(runnerText)},
 outputAdaptation:{onlyAuthorSuiteChange:true,from,to,bodyOtherwiseUnchanged:true},appendedPeerCases:{path:prefix+'peer-cases-a1.mjs',sha256:hash(peer),bytes:Buffer.byteLength(peer),cases:10},
 syntax,tests:{exitCode:result.status,signal:result.signal,tests:count('tests'),passed:count('pass'),failed:count('fail'),cancelled:count('cancelled'),skipped:count('skipped'),
 authoredCases:54,peerCases:10,tap:{path:tapPath,sha256:hash(output),bytes:output.length}},sourcesBefore:before,sourcesAfter:after,sourcesUnchanged:unchanged,
 priorRunPreserved:{path:prefix+'independent-local-verification-a2.json',sha256:'a92961a59c5ea424440c300a7d97535489f81ac2760fcd9691e891136da61586',tests:63},
 rerunReason:'Actual helper source added exact optional decision-byte validation and the authored test added a dedicated real-public-a3 path/hash/bytes regression.',
 actualNetworkRequests:0,privateCredentialFilesRead:false,liveOrPrivateWrites:0,SDKJobs:0,realOwnerMetadataCreated:false,
 runtimeExpiry:'2026-10-14T09:57:07.481942Z',runtimeExpiryExtended:false,liveExecutionAuthorizedByThisProof:false};
const bytes=Buffer.from(JSON.stringify(proof,null,2)+'\n'),proofPath=prefix+'independent-local-verification-a3.json';await fs.writeFile(path.join(root,proofPath),bytes,{flag:'wx'});
console.log(JSON.stringify({passed,tests:proof.tests,sourceBindings:before.length,proof:{path:proofPath,sha256:hash(bytes),bytes:bytes.length}}));process.exitCode=passed?0:1;
