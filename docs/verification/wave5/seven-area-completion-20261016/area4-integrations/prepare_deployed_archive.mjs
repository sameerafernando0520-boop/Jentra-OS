import fs from 'node:fs/promises';
import path from 'node:path';
import {createHash} from 'node:crypto';
import {PRESERVED} from '../../../../../tools/wave5/resume_worker_schedules_20261014_r5_v7.mjs';
const sha=x=>createHash('sha256').update(x).digest('hex');
const archive='build/wave5-deployed-v7-archive-20261017/';
const output='docs/verification/wave5/seven-area-completion-20261016/area4-integrations/deployed-archive-manifest.json';
const readback=JSON.parse(await fs.readFile(PRESERVED[8].path,'utf8'));
const rows=new Map();for(const row of [...PRESERVED,...readback.evidence,...readback.sources]){
 if(!/^[A-Za-z0-9_./-]+$/.test(row.path)||row.path.split('/').includes('..'))throw Error('Invalid archive input');
 if(rows.has(row.path)&&rows.get(row.path).sha256!==row.sha256)throw Error('Conflicting archive bytes');rows.set(row.path,row);
}
const manifest={kind:'exact-deployed-v7-source-archive',sourceOnly:true,archiveRoot:archive,codeExecutedFromArchive:false,
 originalFilesOverwritten:false,sourceOnlyArchiveDoesNotAuthorizeExecution:true,entries:[]};
await fs.mkdir(archive);
for(const row of rows.values()){
 let copiedFrom=row.path,bytes=await fs.readFile(copiedFrom);
 if(sha(bytes)!==row.sha256){
  if(row.path!=='workers/wave5/model_runtime.mjs')throw Error('Unexpected changed archive input: '+row.path);
  copiedFrom='docs/verification/wave5/seven-area-completion-20261016/area3-permissions-ai/model_runtime.before.mjs';bytes=await fs.readFile(copiedFrom);
 }
 if(sha(bytes)!==row.sha256)throw Error('Saved deployed bytes do not match exact immutable hash');
 const target=archive+row.path;await fs.mkdir(path.dirname(target),{recursive:true});await fs.writeFile(target,bytes,{flag:'wx'});
 manifest.entries.push({path:target,originalPath:row.path,copiedFrom,sha256:row.sha256,bytes:bytes.length});
}
const candidate=await fs.readFile('workers/wave5/model_runtime.mjs');
manifest.currentProductCandidate={path:'workers/wave5/model_runtime.mjs',sha256:sha(candidate),
 deployedSha256:rows.get('workers/wave5/model_runtime.mjs').sha256,installedByThisArchive:false};
manifest.candidateDiffersFromDeployed=manifest.currentProductCandidate.sha256!==manifest.currentProductCandidate.deployedSha256;
await fs.writeFile(output,JSON.stringify(manifest,null,2)+'\n',{flag:'wx'});
process.stdout.write(JSON.stringify({path:output,sha256:sha(await fs.readFile(output)),entries:manifest.entries.length,currentProductCandidate:manifest.currentProductCandidate})+'\n');
