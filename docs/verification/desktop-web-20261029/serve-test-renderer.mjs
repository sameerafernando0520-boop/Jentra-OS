// Flutter 3.47.5 on Windows uses filesystem separators when checking a URL
// prefix in _localCanvasKitHandler. Fulfil ONLY its four missing SDK renderer
// files in the owned test browser. No application/test response is substituted.
import {readFile} from 'node:fs/promises';
import {createHash} from 'node:crypto';
import path from 'node:path';

const port=Number(process.argv[2]);
if(!Number.isInteger(port)||port<1024||port>65535)throw Error('Explicit owned test debug port required.');
const pages=await(await fetch(`http://127.0.0.1:${port}/json/list`)).json();
const page=pages.find(p=>p.type==='page'&&/^http:\/\/localhost:\d+\/static\/index\.html\?managerUrl=/.test(p.url));
if(!page)throw Error('Owned Flutter test manager page required.');
const origin=new URL(page.url).origin;
const allowed=new Set(['canvaskit.js','canvaskit.wasm','chromium/canvaskit.js','chromium/canvaskit.wasm']);
const sdkRoot='C:/src/flutter/bin/cache/flutter_web_sdk/canvaskit';
const socket=new WebSocket(page.webSocketDebuggerUrl);
await new Promise((resolve,reject)=>{socket.addEventListener('open',resolve,{once:true});socket.addEventListener('error',reject,{once:true});});
let next=0;
const pending=new Map();
const served=[];
function call(method,params={}){
 const id=++next;
 return new Promise((resolve,reject)=>{
  const timeout=setTimeout(()=>{pending.delete(id);reject(Error(`CDP timeout: ${method}`));},15000);
  pending.set(id,{resolve,reject,timeout});
  socket.send(JSON.stringify({id,method,params}));
 });
}
socket.addEventListener('message',async event=>{
 const message=JSON.parse(event.data);
 if(message.id){
  const item=pending.get(message.id);
  if(item){clearTimeout(item.timeout);pending.delete(message.id);message.error?item.reject(Error(message.error.message)):item.resolve(message.result);}
 }
 if(message.method==='Fetch.requestPaused'){
  const {requestId,request}=message.params;
  const url=new URL(request.url);
  const relative=url.pathname.slice('/canvaskit/'.length);
  if(url.origin!==origin||!url.pathname.startsWith('/canvaskit/')||!allowed.has(relative)){
   await call('Fetch.continueRequest',{requestId});return;
  }
  try{
   const bytes=await readFile(path.join(sdkRoot,relative));
   await call('Fetch.fulfillRequest',{requestId,responseCode:200,responseHeaders:[{name:'Content-Type',value:relative.endsWith('.wasm')?'application/wasm':'text/javascript'}],body:bytes.toString('base64')});
   served.push({relative,bytes:bytes.length,sha256:createHash('sha256').update(bytes).digest('hex')});
   console.log(JSON.stringify({sdkRenderer:served.at(-1)}));
  }catch(error){console.error(error);await call('Fetch.failRequest',{requestId,errorReason:'Failed'});process.exitCode=1;}
 }
});
await call('Page.enable');
await call('Fetch.enable',{patterns:[{urlPattern:`${origin}/canvaskit/*`,requestStage:'Request'}]});
const {frameTree}=await call('Page.getFrameTree');
const testFrame=frameTree.childFrames?.find(item=>new URL(item.frame.url).pathname.endsWith('/desktop_browser_storage_test.html'));
if(!testFrame)throw Error('Expected isolated browser test iframe missing.');
await call('Page.navigate',{frameId:testFrame.frame.id,url:testFrame.frame.url});
await new Promise(resolve=>setTimeout(resolve,45000));
socket.close();
if(served.length===0)throw Error('No missing SDK renderer files were fulfilled.');
console.log(JSON.stringify({sdkWorkaroundOnly:true,served:served.length,applicationResponsesSubstituted:false,testAssertionsChanged:false}));
