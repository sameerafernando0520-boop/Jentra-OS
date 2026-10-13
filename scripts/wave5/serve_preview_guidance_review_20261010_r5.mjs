// Loopback-only viewer for the exact new self-contained image review.
// Existing r2 review/server and all source, images and acceptance stores are preserved.
import {createServer} from 'node:http';
import {readFile} from 'node:fs/promises';
import path from 'node:path';
import {fileURLToPath} from 'node:url';
const root=path.resolve(path.dirname(fileURLToPath(import.meta.url)),'../..');
const file=path.join(root,'dist/Jentra OS Preview Guidance Review 20261010 r5.html');
const server=createServer(async(req,res)=>{
  if(req.url!=='/'||!['GET','HEAD'].includes(req.method)){res.writeHead(404);res.end();return;}
  try{
    const data=await readFile(file);
    res.writeHead(200,{'Content-Type':'text/html; charset=utf-8','Content-Length':data.length,'Cache-Control':'no-store','X-Content-Type-Options':'nosniff'});
    res.end(req.method==='HEAD'?undefined:data);
  }catch{res.writeHead(503,{'Content-Type':'text/plain'});res.end('The exact Preview guidance review has not been published yet.');}
});
server.listen(8777,'127.0.0.1',()=>console.log('Preview guidance review: http://127.0.0.1:8777/ (loopback only).'));
