import fs from 'node:fs/promises';
import assert from 'node:assert/strict';
import path from 'node:path';
import {createHash} from 'node:crypto';
import {fileURLToPath} from 'node:url';

const root=fileURLToPath(new URL('../../../../',import.meta.url));
const base='docs/verification/wave5/seven-area-completion-20261016/area7-quality/';
const sha=b=>createHash('sha256').update(b).digest('hex');
const read=p=>fs.readFile(path.join(root,p));
const proofPath=base+'domain-current-coverage-a2.json';
const proofBytes=await read(proofPath),proof=JSON.parse(proofBytes);
let checked=0;
for(const binding of [...proof.sourceBindingsBeforeAfterUnchanged,...proof.outputs]) {
 const bytes=await read(binding.path);
 assert.equal(bytes.length,binding.bytes,binding.path+' size');
 assert.equal(sha(bytes),binding.sha256,binding.path+' hash');
 checked++;
}
const records=new Map();
const lcovPath=base+'domain-analytics-current-a5.lcov';
for(const record of (await read(lcovPath)).toString('utf8').split('end_of_record')) {
 const lines=record.trim().split(/\r?\n/),sf=lines.find(l=>l.startsWith('SF:'));
 if(!sf)continue;
 const source=path.relative(root,sf.slice(3)).replaceAll('\\','/');
 assert.ok(!records.has(source),'duplicate LCOV source '+source);
 const lineCounts=lines.filter(l=>l.startsWith('DA:')).map(l=>Number(l.split(',')[1]));
 const branches=lines.filter(l=>l.startsWith('BRDA:')).map(l=>l.split(',')[3]);
 records.set(source,{linesFound:lineCounts.length,linesHit:lineCounts.filter(n=>n>0).length,
  branchesFound:branches.length,branchesHit:branches.filter(n=>n!=='-'&&Number(n)>0).length});
}
assert.equal(proof.files.length,9);
let linesHit=0,linesFound=0,branchesHit=0,branchesFound=0;
for(const file of proof.files) {
 const actual=records.get(file.source.path);assert.ok(actual,file.source.path);
 for(const key of ['linesHit','linesFound','branchesHit','branchesFound']) assert.equal(actual[key],file[key],file.source.path+' '+key);
 assert.ok(actual.branchesFound>0&&actual.branchesHit/actual.branchesFound>=.9,file.source.path+' branch gate');
 linesHit+=actual.linesHit;linesFound+=actual.linesFound;branchesHit+=actual.branchesHit;branchesFound+=actual.branchesFound;
}
assert.deepEqual({linesHit,linesFound,branchesHit,branchesFound},{linesHit:867,linesFound:875,branchesHit:246,branchesFound:252});
const events=(await read(base+'domain-analytics-current-a5.jsonl')).toString('utf8').trim().split(/\r?\n/).map(JSON.parse);
const done=events.filter(e=>e.type==='testDone'&&!e.hidden);
assert.equal(done.length,83);assert.ok(done.every(e=>e.result==='success'&&!e.skipped));
assert.equal(events.at(-1).type,'done');assert.equal(events.at(-1).success,true);
assert.equal((await read(base+'domain-analytics-current-a5.exit.txt')).toString().trim(),'0');
assert.equal((await read(base+'domain-analytics-analysis-a3.exit.txt')).toString().trim(),'0');
assert.match((await read(base+'domain-analytics-analysis-a3.log')).toString(),/No issues found!/);
const result={kind:'root-independent-current-domain-evidence-verification',recordedAt:new Date().toISOString(),
 passed:true,proofBinding:{path:proofPath,sha256:sha(proofBytes)},checkedBindings:checked,
 actualSuccessfulNonhiddenTests:done.length,analysisExitCode:0,analyticsFiles:9,
 linesHit,linesFound,branchesHit,branchesFound,allDeclaredFilesAtLeast90PercentBranches:true,
 testExecutionRepeated:false,networkCalls:0,privateInputsRead:false,requirementsNewlyAccepted:0};
const name=process.argv[2];assert.match(name??'',/^[a-z0-9-]+\.json$/);
await fs.writeFile(path.join(root,'docs/verification/wave5/seven-area-completion-20261016',name),JSON.stringify(result,null,2)+'\n',{flag:'wx'});
process.stdout.write(JSON.stringify(result)+'\n');
