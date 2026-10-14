import fs from 'node:fs/promises';
import path from 'node:path';
import {fileURLToPath} from 'node:url';
import {spawnSync} from 'node:child_process';
import {createHash} from 'node:crypto';

const root=fileURLToPath(new URL('../../../../',import.meta.url));
const dir=path.join(root,'docs/verification/wave5/task3-export-source-independent-20261014');
const node='C:/Program Files/nodejs/node.exe';
const sha=bytes=>createHash('sha256').update(bytes).digest('hex');
const sourceFiles=['tools/wave5/finance_exports_20261014_r5_a5.mjs',
 'tools/wave5/prepare_finance_exports_20261014_r5_a5.mjs',
 'docs/verification/wave5/task3-export-continuation-20261014/finance_exports_20261014_r5_a5.test.mjs'];
const expected=['6e16122506ab9e64d88dc03b0a5fbe013c2b758013269006ed6799610fbb0e97',
 '030c44b84a8c5073c6c2157352fd70783c232ee256befda6ec28e9b6a723cd32',
 '40acbc250ef4792cad09f33a71ea5a05b282f9f822427354d977aa5449ef0699'];
async function bind(file){const bytes=await fs.readFile(path.join(root,file));return {path:file,sha256:sha(bytes),bytes:bytes.length};}
const before=await Promise.all(sourceFiles.map(bind));
if(before.some((row,i)=>row.sha256!==expected[i]))throw Error('WAIT_FOR_EXACT_STABLE_AUTHOR_SOURCE');
const original=await fs.readFile(path.join(root,sourceFiles[2]),'utf8');
const oldBase="const base='docs/verification/wave5/task3-export-continuation-20261014';";
const newBase="const base='docs/verification/wave5/task3-export-source-independent-20261014';";
if(original.split(oldBase).length!==2)throw Error('EXACT_ONE_CONTROLLED_OUTPUT_REDIRECTION_REQUIRED');
const peerFile=path.join(dir,'peer-cases-a1.mjs'),peer=await fs.readFile(peerFile,'utf8');
const copied=original.replace(oldBase,newBase)+'\n'+peer;
const runner=path.join(dir,'independent-combined.test.mjs');
await fs.writeFile(runner,copied,{flag:'wx'});
const checkedAt=new Date().toISOString();
const syntax=sourceFiles.map(file=>{const result=spawnSync(node,['--check',path.join(root,file)],{cwd:root,encoding:'utf8',timeout:15000});
 return {path:file,exitCode:result.status,signal:result.signal,stderr:result.stderr||''};});
const output=spawnSync(node,['--test','--test-concurrency=1',runner],{cwd:root,encoding:'utf8',timeout:45000,maxBuffer:8*1024*1024});
const tap=Buffer.from((output.stdout||'')+(output.stderr||''));
const tapFile=path.join(dir,'independent-controlled-tests-a1.tap');await fs.writeFile(tapFile,tap,{flag:'wx'});
const summary=name=>Number(tap.toString().match(new RegExp('^# '+name+' (\\d+)$','m'))?.[1]??0);
const after=await Promise.all(sourceFiles.map(bind));
const passed=output.status===0&&summary('fail')===0&&syntax.every(row=>row.exitCode===0)&&JSON.stringify(before)===JSON.stringify(after);
const proof={kind:'independent-controlled-export-source-verification',reviewer:'/root/completion_peer',checkedAt,
 actualNetworkRequests:0,privateCredentialFilesRead:false,SDKJobs:0,liveOrPrivateWrites:0,
 originalAuthoredTestSource:before[2],copiedRunner:{path:path.relative(root,runner).replaceAll('\\','/'),sha256:sha(copied),bytes:Buffer.byteLength(copied)},
 outputRedirection:{onlyAuthorSuiteAdaptation:true,exactReplacedLine:oldBase,exactReplacementLine:newBase,authorTestBodiesUnchanged:true},
 appendedPeerFragment:{path:path.relative(root,peerFile).replaceAll('\\','/'),sha256:sha(peer),bytes:Buffer.byteLength(peer)},
 sourcesBefore:before,sourcesAfter:after,sourcesUnchanged:JSON.stringify(before)===JSON.stringify(after),syntax,
 command:{binary:node,args:['--test','--test-concurrency=1',path.relative(root,runner).replaceAll('\\','/')],timeoutMs:45000},
 tests:{exitCode:output.status,signal:output.signal,tests:summary('tests'),passed:summary('pass'),failed:summary('fail'),cancelled:summary('cancelled'),skipped:summary('skipped'),
  tap:{path:path.relative(root,tapFile).replaceAll('\\','/'),sha256:sha(tap),bytes:tap.length}},passed,
 limits:['Controlled Auth, SQL and response fixtures are test inputs, not genuine acceptance evidence.',
 'No A10 metadata/profile was created; the suite uses in-memory hypothetical values only.',
 'Original runtime expiry is unchanged; passing source tests do not authorize execution.']};
const proofFile=path.join(dir,'independent-local-verification-a1.json'),bytes=Buffer.from(JSON.stringify(proof,null,2)+'\n');
await fs.writeFile(proofFile,bytes,{flag:'wx'});
console.log(JSON.stringify({passed,tests:proof.tests,proof:{path:path.relative(root,proofFile).replaceAll('\\','/'),sha256:sha(bytes),bytes:bytes.length}}));
process.exitCode=passed?0:1;
