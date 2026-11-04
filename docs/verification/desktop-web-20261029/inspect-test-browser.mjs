const port=Number(process.argv[2]);
if(!Number.isInteger(port)||port<1024||port>65535)throw Error('Explicit test debug port required.');
const pages=await(await fetch(`http://127.0.0.1:${port}/json/list`)).json();
const page=pages.find(p=>p.type==='page'&&p.url.startsWith('http://localhost:'));
if(!page)throw Error('Owned local test page not found.');
const socket=new WebSocket(page.webSocketDebuggerUrl);
await new Promise((resolve,reject)=>{socket.addEventListener('open',resolve,{once:true});socket.addEventListener('error',reject,{once:true});});
socket.addEventListener('message',event=>{
 const value=JSON.parse(event.data);
 if(value.method==='Log.entryAdded')console.log(JSON.stringify({browserLog:value.params.entry}));
 if(value.method==='Runtime.exceptionThrown')console.log(JSON.stringify({browserException:value.params.exceptionDetails}));
});
socket.send(JSON.stringify({id:2,method:'Log.enable'}));
socket.send(JSON.stringify({id:3,method:'Runtime.enable'}));
const response=new Promise((resolve,reject)=>{
 const timeout=setTimeout(()=>reject(Error('Test browser diagnostic timeout.')),10000);
 socket.addEventListener('message',event=>{const value=JSON.parse(event.data);if(value.id===1){clearTimeout(timeout);resolve(value.result);}});
});
socket.send(JSON.stringify({id:1,method:'Runtime.evaluate',params:{
 expression:`JSON.stringify({ready:document.readyState,text:document.body.innerText.slice(0,400),frames:Array.from(document.querySelectorAll('iframe')).map(f=>({source:f.src,ready:f.contentWindow.document.readyState,text:f.contentWindow.document.body.innerText.slice(0,600),resources:f.contentWindow.performance.getEntriesByType('resource').map(r=>({url:r.name,size:r.transferSize,duration:r.duration})).slice(-10)})),resources:performance.getEntriesByType('resource').map(r=>({url:r.name,size:r.transferSize,duration:r.duration})).slice(-6)})`,returnByValue:true,
}}));
try{console.log(JSON.stringify(await response));await new Promise(resolve=>setTimeout(resolve,500));}finally{socket.close();}
