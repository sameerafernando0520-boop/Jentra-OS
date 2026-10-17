// Local read-only preview. Only the review and explicitly bound public files are served.
import http from 'node:http';
import fs from 'node:fs/promises';
import path from 'node:path';
import {fileURLToPath} from 'node:url';
const root=fileURLToPath(new URL('../../',import.meta.url));
const report=JSON.parse(await fs.readFile(path.join(root,'docs/verification/wave5/root-runtime-review-20261017/root-final-publication-a2.json'),'utf8'));
const manifestPath='docs/verification/wave5/root-runtime-review-20261017/operation-bundle.draft-a1.json';
const manifest=JSON.parse(await fs.readFile(path.join(root,manifestPath),'utf8'));
const allowed=new Map([['/',report.html.path],...manifest.sourceAndEvidenceBindings.map(x=>['/'+x.path,x.path]),
 ...[report.html.path,manifestPath,report.policy.path,report.policyReview.path,'docs/verification/wave5/root-runtime-review-20261017/source-policy.draft-a1.json'].map(x=>['/'+x,x])]);
const server=http.createServer(async(req,res)=>{
 try{
  if(!['GET','HEAD'].includes(req.method)){res.writeHead(405);res.end();return;}
  const url=new URL(req.url,'http://127.0.0.1'),file=allowed.get(decodeURIComponent(url.pathname));
  if(!file){res.writeHead(404);res.end('Review file not listed');return;}
  const bytes=await fs.readFile(path.join(root,file));
  res.writeHead(200,{'Content-Type':file.endsWith('.html')?'text/html; charset=utf-8':file.endsWith('.json')?'application/json; charset=utf-8':'text/plain; charset=utf-8',
   'Cache-Control':'no-store','X-Content-Type-Options':'nosniff','Referrer-Policy':'no-referrer'});
  res.end(req.method==='HEAD'?undefined:bytes);
 }catch{res.writeHead(400);res.end('Invalid review request');}
});
server.listen(0,'127.0.0.1',()=>process.stdout.write(JSON.stringify({reviewUrl:'http://127.0.0.1:'+server.address().port+'/',readOnly:true,listedFiles:allowed.size})+'\n'));
