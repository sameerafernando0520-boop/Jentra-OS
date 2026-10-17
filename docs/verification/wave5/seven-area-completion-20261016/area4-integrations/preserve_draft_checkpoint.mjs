import fs from 'node:fs/promises';
import {createHash} from 'node:crypto';
const base='docs/verification/wave5/seven-area-completion-20261016/area4-integrations/';
const hash=bytes=>createHash('sha256').update(bytes).digest('hex');
const files=[['tools/wave5/run_worker_v7_health_20261015_r5.mjs','health-launcher-21-test-checkpoint.mjs','639881dbfc68c70741dd5714e4e5fd85142d0ee4705eec1e96e6c79c63880116'],
 ['tools/wave5/resume_worker_schedules_20261015_r5_a1.mjs','scheduler-21-test-checkpoint.mjs','902878e90cc410ba56d56a7db962fe70bba73aa6021f031a17c4623d1ac6053b']];
const sources=[];
for(const [source,file,expected] of files){
 let text=(await fs.readFile(source,'utf8')).replaceAll('8388608','1048576');
 if(file.startsWith('health'))text=text.replace('Buffer.byteLength(text)<=8192','text.length<=8192');
 if(hash(text)!==expected)throw Error('Exact earlier tool-observed source checkpoint reconstruction failed: '+file);
 await fs.writeFile(base+file,text,{flag:'wx'});sources.push({source,preservedPath:base+file,sha256:expected});
}
await fs.writeFile(base+'checkpoint-lineage.json',JSON.stringify({kind:'exact-source-checkpoint-preservation',sourceOnly:true,
 reconstruction:'Reversed only subsequent UTF-8 byte-limit and public-file-size fixes; both bytes match the exact SHA-256 values observed before those edits.',
 testHistory:{firstRun:{tests:21,pass:15,fail:6,reason:'Controlled fixture fingerprints were not sorted; test fixture corrected without changing production guards.'},
 correctedRun:{tests:21,pass:21,fail:0,proof:'Direct tool TAP output observed in this agent turn; not reconstructed as a saved TAP artifact.'}},sources},null,2)+'\n',{flag:'wx'});
