// Serve only the already reviewed human artifact on loopback; no workspace listing.
import {readFile} from 'node:fs/promises';
import {createHash} from 'node:crypto';
import http from 'node:http';
import path from 'node:path';
import {fileURLToPath} from 'node:url';
const root=path.resolve(path.dirname(fileURLToPath(import.meta.url)),'../..');
const record=JSON.parse(await readFile(path.join(root,'docs/verification/wave5/runtime-approval-page-20261012-r5-a2.json')));
const bytes=await readFile(path.join(root,record.page.path));
if(createHash('sha256').update(bytes).digest('hex')!==record.page.sha256||record.ownerApproved!==false||record.runtimeBundleSha256!=='db525758554036fa99ec02d00c85bd8401ef7ebce787e2a983db1c69a08baf7b')throw Error('FROZEN_APPROVAL_PAGE_REQUIRED');
const server=http.createServer((request,response)=>{
 if(request.method!=='GET'||!['/','/index.html'].includes(request.url)){response.writeHead(404,{'Content-Type':'text/plain'});response.end('Not found');return;}
 response.writeHead(200,{'Content-Type':'text/html; charset=utf-8','Cache-Control':'no-store','X-Content-Type-Options':'nosniff','Content-Security-Policy':"default-src 'none'; style-src 'unsafe-inline'; img-src data:; base-uri 'none'; frame-ancestors 'none'"});response.end(bytes);
});
server.on('error',e=>{console.error(JSON.stringify({serverStarted:false,code:e.code}));process.exitCode=1;});
server.listen(8783,'127.0.0.1',()=>console.log(JSON.stringify({serverStarted:true,url:'http://127.0.0.1:8783/',servedFile:record.page.path,sha256:record.page.sha256,servedFiles:1,externalNetwork:false})));
