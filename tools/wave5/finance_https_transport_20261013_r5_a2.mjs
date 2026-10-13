import https from 'node:https';
import crypto from 'node:crypto';
import { PROJECT_URL,hashBytes,hashJson,isUuid } from './runtime_contract.mjs';
import { FINANCE_SCOPE } from './finance_cash_fixture_20261013_r5.mjs';

export const FINANCE_RPCS=Object.freeze(['generate_financial_statement','financial_statement_page','wave5_financial_ratios',
 'wave5_classification_publish','wave5_cash_basis','wave5_cash_date_sources','wave5_cash_date_get','wave5_cash_date_command',
 'wave5_cash_save','wave5_cash_get','report_export_preview','record_report_export','wave5_export_reopen','get_pipeline_forecast','post_manual_journal']);
const must=(ok,code)=>{if(!ok){const error=Error(code);error.publicCode=code;throw error;}};
const auth=/^\/auth\/v1\/(token\?grant_type=password|user|factors\/[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\/(challenge|verify))$/i;

// Fixed genuine-user API transport for the new finance slice. Import and
// construction have no I/O. It adds no route to the contention/load provider.
export function createFinanceHttpsTransport({apiKey,requestFactory=https.request,agentFactory=()=>new https.Agent({keepAlive:true,maxSockets:1}),timeoutMs=45000}){
 must(typeof apiKey==='string'&&apiKey.length>8&&Number.isSafeInteger(timeoutMs)&&timeoutMs>0&&timeoutMs<=45000,'EXACT_FINANCE_TRANSPORT_REQUIRED');
 const agents=new Map();let closed=false;
 function connection(){must(!closed,'FINANCE_TRANSPORT_CLOSED');const handle=Object.freeze({connectionId:'w5-finance-'+crypto.randomUUID()});agents.set(handle,agentFactory());return handle;}
 async function send(handle,route,{method='POST',body,bearer,profile,signal}={}){
  must(!closed&&agents.has(handle)&&!signal?.aborted,'FINANCE_TRANSPORT_CLOSED');
  const name=route?.split('/').at(-1),rpc=route===`/rest/v1/rpc/${name}`&&FINANCE_RPCS.includes(name);
  must(auth.test(route)||rpc,'FIXED_FINANCE_ENDPOINT_REQUIRED');
  must(route==='/auth/v1/user'?method==='GET':method==='POST','FIXED_FINANCE_VERB_REQUIRED');
  if(rpc)must(profile==='api'&&typeof bearer==='string'&&bearer.length>8&&body?.p_tenant_id===FINANCE_SCOPE.tenantId
   &&body.p_legal_entity_id===FINANCE_SCOPE.entityId&&body.p_branch_id===FINANCE_SCOPE.branchId,'EXACT_RUNTIME_FINANCE_SCOPE_REQUIRED');
  const bytes=body===undefined?'':JSON.stringify(body);must(Buffer.byteLength(bytes)<=1048576,'FINANCE_REQUEST_LIMIT');
  const startedAt=new Date().toISOString();let sentAt=null;
  const headers={apikey:apiKey,'Content-Type':'application/json','Content-Length':Buffer.byteLength(bytes)};
  if(bearer)headers.Authorization=`Bearer ${bearer}`;
  if(profile){headers['Content-Profile']=profile;headers['Accept-Profile']=profile;}
  return new Promise((resolve,reject)=>{let request,settled=false,size=0,timer;const chunks=[];
   const fail=code=>{if(settled)return;settled=true;clearTimeout(timer);request?.destroy();const error=Error(code);error.publicCode=code;error.sent=sentAt!==null;reject(error);};
   try{request=requestFactory(new URL(route,PROJECT_URL),{method,headers,agent:agents.get(handle),rejectUnauthorized:true,signal},response=>{
    response.on('error',()=>fail('FINANCE_RESPONSE_UNCERTAIN'));
    response.on('data',chunk=>{if(settled)return;size+=chunk.length;if(size>8388608)fail('FINANCE_RESPONSE_LIMIT');else chunks.push(chunk);});
    response.on('end',()=>{if(settled)return;const raw=Buffer.concat(chunks);let value;
     try{value=raw.length?JSON.parse(raw):null;}catch{return fail('FINANCE_RESPONSE_INVALID');}
     const evidence={route,method,startedAt,sentAt,finishedAt:new Date().toISOString(),connectionId:handle.connectionId,status:response.statusCode,
      responseSha256:hashBytes(raw),responseBytes:raw.length};settled=true;clearTimeout(timer);
     resolve({ok:response.statusCode>=200&&response.statusCode<300,status:response.statusCode,value,evidence,responseSha256:evidence.responseSha256,transportEvidenceSha256:hashJson(evidence)});
    });
   });request.on('error',()=>fail(signal?.aborted?'FINANCE_ABORTED':'FINANCE_TRANSPORT_UNCERTAIN'));
   timer=setTimeout(()=>fail('FINANCE_TIMEOUT_UNCERTAIN'),timeoutMs);
   request.once('socket',socket=>{const dispatch=()=>{if(settled){request.destroy();return;}
    if(signal?.aborted)return fail('FINANCE_ABORTED');if(socket.encrypted!==true||socket.authorized!==true)return fail('FINANCE_VERIFIED_TLS_REQUIRED');
    sentAt=new Date().toISOString();request.end(bytes);};
    if(settled){request.destroy();return;}if(socket.encrypted!==true)return fail('FINANCE_VERIFIED_TLS_REQUIRED');
    if(socket.authorized===true)dispatch();else socket.once('secureConnect',dispatch);
   });}catch{fail('FINANCE_REQUEST_FAILED');}
  });
 }
 return Object.freeze({connection,send,closeConnection(handle){agents.get(handle)?.destroy();agents.delete(handle);},
  close(){closed=true;for(const agent of agents.values())agent.destroy();agents.clear();}});
}

// PostgREST v14 forwards transaction rollback (40*) and prerequisite state
// (55*) as HTTP 500. Exact code AND message remain mandatory; arbitrary 500s
// and PT409 without an installed reviewed SQL source are never denials.
export function financeDenial(response){
 const known={CASH_COMPLETE_PROVIDERS_REQUIRED:'55000',CASH_DATE_VERSION_CONFLICT:'40001',CASH_DATE_INDEPENDENT_APPROVER_REQUIRED:'42501',
  CASH_DATE_PROPOSAL_CHANGED:'40001',CASH_DATE_SOURCE_CHANGED:'40001',CASH_DATE_ALREADY_DECIDED:'55000',PERMISSION_DENIED:'42501',IDEMPOTENCY_MISMATCH:'22023',
  CASH_DATES_MFA_REQUIRED:'42501',SOURCE_BASIS_CHANGED:'40001',VALIDATION_ERROR:'22023',CASH_MAPPING_HISTORY_REQUIRED:'55000'};
 if(response?.ok)return null;const {code,message}=response?.value??{};
 const status=code==='42501'?403:code==='40001'||code==='55000'?500:code==='22023'?400:null;
 if(known[message]===code&&status!==null&&response.status===status)return message;
 if(code==='42501'&&response.status===403&&message==='Permission denied or multi-factor authentication required.')return 'PERMISSION_DENIED';
 return null;
}

const integer=text=>{must(typeof text==='string'&&/^-?\d+(?:\.\d{1,6})?$/.test(text),'EXACT_FINANCE_DECIMAL_REQUIRED');
 const sign=text.startsWith('-')?-1n:1n,[whole,fraction='']=text.replace(/^-/,'').split('.');return sign*(BigInt(whole)*1000000n+BigInt(fraction.padEnd(6,'0')));};
export function exactRatio(numerator,denominator){const n=integer(numerator),d=integer(denominator);if(d<=0n)return {exactValue:null,unavailableReason:d===0n?'ZERO_DENOMINATOR':'NEGATIVE_DENOMINATOR'};
 const negative=n<0n,a=(negative?-n:n)*1000000n,units=a/d+(a%d*2n>=d?1n:0n);return {exactValue:(negative&&units!==0n?'-':'')+(units/1000000n)+'.'+(units%1000000n).toString().padStart(6,'0'),unavailableReason:null};}

export function encodeFinanceCsv(document,{exportId,preparedAt,sourceHash}){
 must(document?.version===1&&document.metadata&&Array.isArray(document.rows)&&document.rows.length<=10000&&document.metadata.row_count===document.rows.length
  &&isUuid(exportId)&&typeof preparedAt==='string'&&Number.isFinite(Date.parse(preparedAt))&&/^[a-f0-9]{64}$/.test(sourceHash),'EXACT_EXPORT_DOCUMENT_REQUIRED');
 const meta={...document.metadata,export_id:exportId,export_prepared_at:preparedAt,source_hash:sourceHash,file_format:'csv'};
 const metaKeys=Object.keys(meta).sort(),dataKeys=[...new Set(document.rows.flatMap(row=>Object.keys(row)))].sort();
 const columns=['record_type',...metaKeys.map(k=>'report.'+k),...dataKeys.map(k=>'data.'+k)];
 must(columns.length<=256&&(document.rows.length+1)*columns.length<=500000,'EXPORT_CELL_LIMIT');
 const cell=value=>{let s=value===null||value===undefined?'':typeof value==='object'?JSON.stringify(value):String(value);
  must(s.length<=32767&&!/[\x00-\x08\x0B\x0C\x0E-\x1F\uFFFE\uFFFF]/.test(s)&&Buffer.from(s).toString()===s,'EXPORT_CELL_INVALID');
  if(/^\s*[=+\-@]/.test(s)&&! /^-?\d+(\.\d+)?$/.test(s))s="'"+s;
  return /[",\r\n]/.test(s)?'"'+s.replaceAll('"','""')+'"':s;};
 for(const row of document.rows){must(row&&typeof row==='object'&&!Array.isArray(row),'EXPORT_ROW_INVALID');
  for(const [name,value]of Object.entries(row))must(!(typeof value==='number'&&/(^|_)(amount|value|debit|credit|balance|total|price|cost|tax|rate|quantity|percent)$/.test(name)),'EXACT_EXPORT_DECIMAL_REQUIRED');}
 const grid=[columns,['metadata',...metaKeys.map(k=>meta[k]),...dataKeys.map(()=>null)],
  ...document.rows.map(row=>['data',...metaKeys.map(()=>null),...dataKeys.map(k=>row[k])])];
 const bytes=Buffer.from(grid.map(row=>row.map(cell).join(',')+'\n').join(''));must(bytes.length<=10485760,'EXPORT_BYTE_LIMIT');
 return {bytes,columns,sha256:hashBytes(bytes),rowCount:document.rows.length};
}
