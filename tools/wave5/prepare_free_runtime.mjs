import {execFile} from 'node:child_process';
import {promisify} from 'node:util';
import {createHash} from 'node:crypto';
import {readFile,writeFile,mkdir,copyFile,realpath} from 'node:fs/promises';
import {fileURLToPath} from 'node:url';
import path from 'node:path';

// Preparation only: no credentials, provider requests, deployment or DB writes.
const run=promisify(execFile),root=await realpath(fileURLToPath(new URL('../../',import.meta.url)));
const deno=path.join(root,'build/wave5-local-tools-20261013-r5/deno-2.9.7/bin/deno.exe');
const entry='supabase/functions/wave5-runtime/index.ts',config='supabase/functions/wave5-runtime/deno.json';
const {stdout}=await run(deno,['info','--json','--config',config,entry],
 {cwd:root,encoding:'utf8',windowsHide:true,maxBuffer:4*1024*1024});
const graph=JSON.parse(stdout),inputs=new Set([config]);
if(!Array.isArray(graph.modules)||!Array.isArray(graph.roots)||graph.roots.some(value=>!value.startsWith('file:')))
 throw Error('FREE_RUNTIME_GRAPH_INVALID');
const expectedEntry=await realpath(path.join(root,entry));
const roots=await Promise.all(graph.roots.map(value=>realpath(fileURLToPath(value))));
if(!roots.some(value=>path.relative(expectedEntry,value)===''))throw Error('FREE_RUNTIME_ENTRY_MISMATCH');
for(const module of graph.modules){
 if(module.specifier.startsWith('node:'))continue;
 if(!module.specifier.startsWith('file:')||module.error)throw Error('UNREVIEWED_RUNTIME_DEPENDENCY');
 const absolute=await realpath(fileURLToPath(module.specifier)),relative=path.relative(root,absolute).replaceAll('\\','/');
 if(!(relative.startsWith('workers/wave5/')&&relative.endsWith('.mjs')&&!relative.endsWith('.test.mjs'))&&relative!==entry)
  throw Error('RUNTIME_DEPENDENCY_OUTSIDE_APPROVED_SCOPE');
 inputs.add(relative);
}
const stamp=new Date().toISOString();
const candidateRoot=path.join(root,'build/wave5-cloudflare-free-20261102',stamp.replaceAll(':','-'));
await mkdir(candidateRoot,{recursive:true});
const sources=[];
for(const relative of [...inputs].sort()){
 const source=path.join(root,relative),bytes=await readFile(source),destination=path.join(candidateRoot,relative);
 await mkdir(path.dirname(destination),{recursive:true});await copyFile(source,destination);
 sources.push({path:relative,bytes:bytes.length,sha256:createHash('sha256').update(bytes).digest('hex')});
}
const localConfig='project_id = "jentra-free-ai-candidate"\n\n[functions.wave5-runtime]\nverify_jwt = false\n';
await writeFile(path.join(candidateRoot,'supabase/config.toml'),localConfig,{flag:'wx'});
await run(deno,['check','--config',config,entry],
 {cwd:candidateRoot,encoding:'utf8',windowsHide:true,maxBuffer:1024*1024});
const manifest={kind:'jentra-free-ai-runtime-candidate',preparedAt:stamp,projectId:'xpdoufauvrbdmxgngetv',
 functionSlug:'wave5-runtime',entry,provider:'cloudflare.workers-ai.free.v1',model:'@cf/meta/llama-3.3-70b-instruct-fp8-fast',
 freePlanMustBeVerified:true,paidFallback:false,containsSecretValues:false,deployed:false,databaseChanged:false,
 stagedDenoCheckPassed:true,candidateRoot,sources};
const manifestBytes=JSON.stringify(manifest,null,2)+'\n';
await writeFile(path.join(candidateRoot,'candidate.json'),manifestBytes,{flag:'wx'});
console.log(JSON.stringify({candidateRoot,sourceFiles:sources.length,stagedDenoCheckPassed:true,
 manifestSha256:createHash('sha256').update(manifestBytes).digest('hex'),deployed:false,containsSecretValues:false},null,2));
