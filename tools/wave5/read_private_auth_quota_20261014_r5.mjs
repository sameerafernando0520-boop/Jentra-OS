import fs from 'node:fs/promises';
import https from 'node:https';
import {fileURLToPath} from 'node:url';
import {hashBytes} from './runtime_contract.mjs';
const mode=process.argv[2],must=(v,c)=>{if(!v)throw Error(c);};
must(process.argv.length===3&&['--validate','--read'].includes(mode),'FIXED_AUTH_QUOTA_READ_MODE_REQUIRED');
if(mode==='--validate'){process.stdout.write(JSON.stringify({passed:true,networkCalls:0,authWrites:0,settingsChanges:0,onlyNumericAuthReadinessFieldsPublished:true})+'\n');}
else{
 let token='';for await(const c of process.stdin){token+=c;must(token.length<=2050,'PRIVATE_OWNER_INPUT_REQUIRED');}token=token.trim();must(token.length>=9&&token.length<=2048&&!/\s/.test(token),'PRIVATE_OWNER_INPUT_REQUIRED');
 try{
  const startedAt=new Date().toISOString();
  const response=await new Promise((resolve,reject)=>{
   let request,timer,done=false,size=0;const chunks=[];
   const fail=code=>{if(done)return;done=true;clearTimeout(timer);request?.destroy();reject(Error(code));};
   request=https.request('https://api.supabase.com/v1/projects/xpdoufauvrbdmxgngetv/config/auth',{method:'GET',rejectUnauthorized:true,agent:false,headers:{Authorization:'Bearer '+token}},res=>{
    res.on('error',()=>fail('AUTH_QUOTA_RESPONSE_UNCERTAIN'));res.on('data',c=>{size+=c.length;if(size>2097152)fail('AUTH_QUOTA_RESPONSE_LIMIT');else chunks.push(c);});
    res.on('end',()=>{if(done)return;if(res.statusCode!==200){fail('AUTH_QUOTA_READ_HTTP_FAILURE');return;}let value;try{value=JSON.parse(Buffer.concat(chunks).toString('utf8'));}catch{fail('AUTH_QUOTA_RESPONSE_INVALID');return;}
     done=true;clearTimeout(timer);const select=k=>typeof value[k]==='number'&&Number.isFinite(value[k])?value[k]:null;
     const fields={jwtLifetimeSeconds:select('jwt_exp'),tokenRefreshGrantQuotaPerFiveMinutes:select('rate_limit_token_refresh'),tokenVerificationQuota:select('rate_limit_token_verify')};
     value=null;for(const c of chunks)c.fill(0);resolve(fields);
    });
   });timer=setTimeout(()=>fail('AUTH_QUOTA_READ_DEADLINE'),15000);request.on('error',()=>fail('AUTH_QUOTA_TRANSPORT_UNCERTAIN'));
   request.once('socket',s=>{const send=()=>{if(s.encrypted!==true||s.authorized!==true){fail('VERIFIED_AUTH_QUOTA_TLS_REQUIRED');return;}request.end();};if(s.authorized===true)send();else s.once('secureConnect',send);});
  });token='';
  const record={kind:'actual-private-owner-auth-quota-readiness-observation',projectId:'xpdoufauvrbdmxgngetv',startedAt,actualVerifiedAt:new Date().toISOString(),...response,numericFieldsOnly:true,unknownFieldsRemainNull:true,source:'One fixed owner Management API GET /config/auth',networkCalls:1,redirectsFollowed:0,automaticRetries:0,credentialValuesPublished:false,completeAuthConfigPublished:false,completeAuthConfigStored:false,authWrites:0,settingsChanges:0,quotaIncreasePerformed:false,syntheticJwtCreated:false,forwardingIpSpoofed:false,production:false,realBilling:false,helperSha256:hashBytes(await fs.readFile(fileURLToPath(import.meta.url)))};
  const file=new URL('../../docs/verification/wave5/auth-token-quota-actual-private-readiness-20261014-r5.json',import.meta.url);await fs.writeFile(file,JSON.stringify(record,null,2)+'\n',{flag:'wx'});process.stdout.write(JSON.stringify(record)+'\n');
 }catch(e){token='';process.stderr.write(JSON.stringify({failureCode:/^[A-Z_]+$/.test(e.message)?e.message:'AUTH_QUOTA_PRIVATE_READ_STOPPED',rawConfigOrCredentialPrinted:false,automaticRetry:false,authWrites:0,settingsChanges:0})+'\n');process.exitCode=1;}
}
