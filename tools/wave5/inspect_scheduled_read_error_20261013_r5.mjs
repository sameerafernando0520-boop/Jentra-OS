import {PROJECT,BUNDLE,loadApprovedInputs} from './approved_management_installer.mjs';
import {runtimeSealKey,readRuntimeSecret} from './private_runtime_seal.mjs';
await loadApprovedInputs();let input='';for await(const c of process.stdin){input+=c;if(input.length>16000)throw Error('PRIVATE_INPUT_LIMIT');}
const config=JSON.parse(input);input='';if(config.projectId!==PROJECT||config.bundleSha256!==BUNDLE)throw Error('EXACT_APPROVED_INPUT_REQUIRED');
const key=runtimeSealKey(config.encryptionKey);
try{const value=await readRuntimeSecret(config.privateDirectory,key,'runtime-schedule-read-error-97d0e5dd-c9e5-4a05-b079-070b89d7bbe5.sealed.json','schedule-read-error');
 const raw=Buffer.from(value.responseBase64,'base64');let response;try{response=JSON.parse(raw);}finally{raw.fill(0);}
 const strings=[];const walk=(v,depth=0)=>{if(typeof v==='string')strings.push(v);else if(v&&typeof v==='object'&&depth<3)Object.values(v).forEach(x=>walk(x,depth+1));};walk(response);
 const privateText=strings.join('\n');const patterns={syntax:/syntax error/i,readOnly:/read.only/i,permission:/permission denied/i,statement:/statement/i,select:/select/i,query:/query/i,transaction:/transaction/i,multiple:/multiple/i,function:/function/i,volatile:/volatile/i,prepared:/prepared/i,parse:/pars(?:e|ing|er)/i,unsupported:/unsupported|not supported/i,timeout:/timeout|timed out/i,notFound:/not found|does not exist/i,method:/method/i,semicolon:/semicolon|trailing/i,forbidden:/forbidden|not allowed/i,invalid:/invalid/i,mustEndSelect:/must.*select|select.*end/i};
 const matches=Object.fromEntries(Object.entries(patterns).map(([k,p])=>[k,p.test(privateText)]));
 process.stdout.write(JSON.stringify({kind:'private-read-error-safe-classification',httpStatus:value.httpStatus,responseShape:Array.isArray(response)?'array':typeof response,matches,rawErrorPrinted:false,networkCalls:0,mutations:0})+'\n');
}finally{key.fill(0);config.ownerToken=null;config.encryptionKey=null;}
