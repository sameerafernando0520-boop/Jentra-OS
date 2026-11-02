import {Buffer} from 'node:buffer';
// Observe a trusted deadline around non-cancellable ports such as DNS. A late
// answer is discarded; the caller must still cancel any cancellable I/O itself.
export function waitForSignal(promise,signal){
 if(!signal)return Promise.resolve(promise);
 return new Promise((resolve,reject)=>{
  function cancel(){cleanup();reject(Error('WORKER_REQUEST_TIMEOUT'));}
  function cleanup(){signal.removeEventListener('abort',cancel);}
  signal.addEventListener('abort',cancel,{once:true});
  if(signal.aborted)cancel();
  Promise.resolve(promise).then(value=>{cleanup();if(signal.aborted)reject(Error('WORKER_REQUEST_TIMEOUT'));else resolve(value);},error=>{cleanup();reject(error);});
 });
}
// A byte limit alone cannot bound a peer that opens a stream and never ends it.
// Request signals and trusted server deadlines cancel the pending read as well.
export async function readBoundedBytes(response,maxBytes=8388608,{signal=response.signal}={}) {
 const chunks=[];let bytes=0;
 if(response.body){
  const reader=response.body.getReader();
  let rejectAbort;
  const aborted=new Promise((_,reject)=>{rejectAbort=reject;});
  const cancel=()=>{
   // Cancel synchronously before rejecting; an untrusted cancel callback must
   // not delay release of a worker request slot.
   reader.cancel().catch(()=>{});rejectAbort(Error('WORKER_REQUEST_TIMEOUT'));
  };
  signal?.addEventListener('abort',cancel,{once:true});
  if(signal?.aborted)cancel();
  try{while(true){const {value,done}=await Promise.race([reader.read(),aborted]);if(done)break;bytes+=value.length;
   if(signal?.aborted)throw Error('WORKER_REQUEST_TIMEOUT');
   if(bytes>maxBytes){reader.cancel().catch(()=>{});throw Error('WORKER_OUTPUT_LIMIT');}chunks.push(value);}}
  finally{signal?.removeEventListener('abort',cancel);reader.releaseLock();}
 }else{const value=Buffer.from(await response.text());bytes=value.length;if(bytes>maxBytes)throw Error('WORKER_OUTPUT_LIMIT');chunks.push(value);}
 if(signal?.aborted)throw Error('WORKER_REQUEST_TIMEOUT');
 return Buffer.concat(chunks);
}
export async function readBoundedJson(response,maxBytes=8388608,options) {
 const text=new TextDecoder('utf-8',{fatal:true}).decode(await readBoundedBytes(response,maxBytes,options));
 return text.length?JSON.parse(text):null;
}
