import {createServer} from 'node:http';
import {readFile} from 'node:fs/promises';
import path from 'node:path';
import {fileURLToPath} from 'node:url';
const root=path.resolve(path.dirname(fileURLToPath(import.meta.url)),'../..');
const file=path.join(root,'dist/Jentra OS Owner Review 20261010 r2.html');
const server=createServer(async(req,res)=>{
  if(req.url!=='/'||!['GET','HEAD'].includes(req.method)){res.writeHead(404);res.end();return;}
  try{const data=await readFile(file);res.writeHead(200,{'Content-Type':'text/html; charset=utf-8','Content-Length':data.length,'Cache-Control':'no-store','X-Content-Type-Options':'nosniff'});res.end(req.method==='HEAD'?undefined:data);}
  catch{res.writeHead(503,{'Content-Type':'text/plain'});res.end('Owner packet is being prepared.');}
});
server.listen(8776,'127.0.0.1',()=>console.log('Owner review available at http://127.0.0.1:8776/; loopback only.'));
