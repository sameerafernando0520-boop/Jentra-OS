// Public GET requests only. This cannot send email, install SQL or submit a response.
import assert from 'node:assert/strict';
import {readFile,writeFile} from 'node:fs/promises';
import {createHash} from 'node:crypto';
const origin='https://jentra-os-sales.web.app',project='https://xpdoufauvrbdmxgngetv.supabase.co';
assert.deepEqual(process.argv.slice(2),['--read-only']);
const root=new URL('../../',import.meta.url),out=new URL('docs/verification/field-rollout-20261103/hosted-http.json',root);
const config=JSON.parse(await readFile(new URL('build/sales-release/public-client.json',root),'utf8'));
assert.equal(config.SUPABASE_URL,project);
const key=config.SUPABASE_PUBLISHABLE_KEY;
assert.equal(typeof key,'string');
if(!key.startsWith('sb_publishable_')){
 const claims=JSON.parse(Buffer.from(key.split('.')[1]??'','base64url').toString('utf8'));
 assert.equal(claims.role,'anon');assert.equal(claims.ref,'xpdoufauvrbdmxgngetv');
}
const get=async(url,headers={})=>{
 const r=await fetch(url,{method:'GET',redirect:'error',cache:'no-store',headers,signal:AbortSignal.timeout(15000)});
 const body=await r.text();assert.ok(Buffer.byteLength(body)<2_000_000);
 return {status:r.status,headers:r.headers,body};
};
const requests=[{id:'sales_root',url:origin},{id:'sales_version',url:origin+'/version.json'},
 {id:'mail_worker_get',url:project+'/functions/v1/field-sales-mail',headers:{apikey:key}},
 ...['confirmation','delivery'].flatMap(purpose=>['request_code','verify','respond'].map(action=>({
  id:`${purpose}_${action}_get`,url:project+`/rest/v1/rpc/field_sales_${purpose}_${action}`,headers:{apikey:key,'Accept-Profile':'api'},
 })))];
const responses=await Promise.allSettled(requests.map(r=>get(r.url,r.headers)));
const observations=responses.map((r,i)=>{
 if(r.status==='rejected')return {id:requests[i].id,method:'GET',state:'network_unavailable'};
 const {status,headers,body}=r.value;
 const item={id:requests[i].id,method:'GET',status,bodySha256:createHash('sha256').update(body).digest('hex')};
 if(i===0){
  item.headers=Object.fromEntries(['cache-control','content-security-policy','referrer-policy','x-frame-options','x-content-type-options','permissions-policy'].map(h=>[h,headers.get(h)]));
  item.requiredHeadersPresent=/no-store/i.test(item.headers['cache-control']??'')
   &&item.headers['referrer-policy']==='no-referrer'&&item.headers['x-frame-options']==='DENY'
   &&item.headers['x-content-type-options']==='nosniff'
   &&(item.headers['content-security-policy']??'').includes("frame-ancestors 'none'")
   &&(item.headers['content-security-policy']??'').includes(project);
 }
 if(i===1&&status===200){try{const v=JSON.parse(body);item.version={version:v.version,channel:v.channel,mode:v.mode,liveSalesEnabled:v.liveSalesEnabled};}catch{item.state='invalid_version';}}
 if(i>2){try{const v=JSON.parse(body);item.code=typeof v.code==='string'?v.code:null;item.state=typeof v.state==='string'?v.state:null;}catch{item.state='non_json';}}
 return item;
});
const report={atUtc:new Date().toISOString(),project,origin,mode:'read-only-public-get',observations,
 claim:'Current hosted HTTP reachability and header observations only. GET refusal cannot establish the deployed worker version, installed RPCs, POST behavior, email delivery, fragment scrubbing, genuine sessions/MFA, device behavior or company acceptance.',
 emailSent:false,sqlExecuted:false,installed:false,deployed:false,acceptanceEstablished:false};
await writeFile(out,JSON.stringify(report,null,2)+'\n');
console.log(JSON.stringify({observations:observations.map(({id,status,state,requiredHeadersPresent})=>({id,status,state,requiredHeadersPresent})),acceptanceEstablished:false}));
