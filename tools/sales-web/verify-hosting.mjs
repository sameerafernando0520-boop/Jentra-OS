import { readFile, writeFile } from 'node:fs/promises';
import { createHash } from 'node:crypto';
import assert from 'node:assert/strict';
import path from 'node:path';
const [baseUrl,release,output] = process.argv.slice(2);
if(!/^https:\/\/[a-z0-9-]+\.web\.app$/.test(baseUrl||'')) throw Error('EXACT_FIREBASE_HTTPS_ORIGIN_REQUIRED');
const manifest=JSON.parse(await readFile(path.join(release,'public-manifest.json'),'utf8'));
assert.equal(manifest.site,'jentra-os-sales'); assert.equal(manifest.project,'jentra-os');
assert.equal(new Set(manifest.files.map(f=>f.path)).size,manifest.files.length,'Duplicate public manifest paths');
const checks=[];
for(let start=0;start<manifest.files.length;start+=3) {
  const batch=manifest.files.slice(start,start+3);
  const responses=await Promise.all(batch.map(async file=>{
    const response=await fetch(`${baseUrl}/${file.path}`,{cache:'no-store',signal:AbortSignal.timeout(90000)});
    assert.equal(response.status,200,file.path);
    const bytes=Buffer.from(await response.arrayBuffer());
    assert.equal(bytes.length,file.size,`${file.path} size`);
    assert.equal(createHash('sha256').update(bytes).digest('hex'),file.sha256,`${file.path} hash`);
    if(file.path.endsWith('.wasm')) assert.match(response.headers.get('content-type')||'',/application\/wasm/);
    return {path:file.path,size:bytes.length,sha256:file.sha256,passed:true};
  }));
  checks.push(...responses);
}
const root=await fetch(baseUrl,{signal:AbortSignal.timeout(30000)});
const headers=Object.fromEntries(['cache-control','alt-svc','referrer-policy','x-frame-options','content-security-policy','x-content-type-options','permissions-policy'].map(k=>[k,root.headers.get(k)]));
assert.match(headers['cache-control'],/no-store/);
assert.equal(headers['referrer-policy'],'no-referrer');assert.equal(headers['x-frame-options'],'DENY');
assert.equal(headers['x-content-type-options'],'nosniff');
assert.match(headers['content-security-policy'],/script-src 'self' 'wasm-unsafe-eval'/);
assert.ok(!headers['content-security-policy'].includes('unsafe-eval;'));
const missing=[];
for(const file of ['assets/missing.png','main.dart.missing.js','.env','private-firebase-adminsdk.json','downloads/missing.zip']) {
  const response=await fetch(`${baseUrl}/${file}`,{signal:AbortSignal.timeout(30000)});
  assert.equal(response.status,404,file);missing.push({path:file,status:response.status});
}
const deep=await fetch(`${baseUrl}/sales/orders`,{signal:AbortSignal.timeout(30000)});
assert.equal(deep.status,200);assert.match(await deep.text(),/<title>Jentra Sales<\/title>/);
const version=await (await fetch(`${baseUrl}/version.json`)).json();
assert.equal(version.version,'0.1.0+1');assert.equal(version.liveSalesEnabled,false);
await writeFile(output,JSON.stringify({baseUrl,project:manifest.project,site:manifest.site,passed:true,version,headers,missing,spa:true,files:checks},null,2)+'\n',{flag:'wx'});
console.log(JSON.stringify({baseUrl,files:checks.length,headers:true,missing404:missing.length,spa:true,output}));
