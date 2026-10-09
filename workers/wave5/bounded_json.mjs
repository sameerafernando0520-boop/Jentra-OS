import {Buffer} from 'node:buffer';
export async function readBoundedJson(response,maxBytes=8388608) {
 const chunks=[];let bytes=0;
 if(response.body){
  const reader=response.body.getReader();
  try{while(true){const {value,done}=await reader.read();if(done)break;bytes+=value.length;
   if(bytes>maxBytes){await reader.cancel();throw Error('WORKER_OUTPUT_LIMIT');}chunks.push(value);}}
  finally{reader.releaseLock();}
 }else{const value=Buffer.from(await response.text());bytes=value.length;if(bytes>maxBytes)throw Error('WORKER_OUTPUT_LIMIT');chunks.push(value);}
 const text=new TextDecoder('utf-8',{fatal:true}).decode(Buffer.concat(chunks));
 return text.length?JSON.parse(text):null;
}
