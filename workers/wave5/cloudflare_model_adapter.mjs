import {Buffer} from 'node:buffer';
import {readBoundedJson} from './bounded_json.mjs';
import {validateModelSuggestion} from './model_runtime.mjs';

export const cloudflareFreeModel='@cf/meta/llama-3.3-70b-instruct-fp8-fast';
const uuid=/^[0-9a-f]{8}-(?:[0-9a-f]{4}-){3}[0-9a-f]{12}$/;
const hash=/^[0-9a-f]{64}$/;
function unavailable(){throw Error('MODEL_PROVIDER_UNAVAILABLE');}

// Use only with an account whose Workers Free plan has been verified during
// activation. No gateway, credit purchase, model substitution or retry exists.
export class CloudflareFreeProvider {
 #key; #fetch;
 constructor({accountId,apiToken,review,fetchImpl=fetch}){
  if(review?.approved!==true||review.revision!==1||review.freeOnly!==true||review.paidFallback!==false||
   review.provider!=='cloudflare.workers-ai.free.v1'||review.model!==cloudflareFreeModel||
   typeof review.maxTokensPerInvocation!=='string'||!/^[1-9][0-9]{0,3}$/.test(review.maxTokensPerInvocation)||
   Number(review.maxTokensPerInvocation)>2000||typeof accountId!=='string'||!/^[a-f0-9]{32}$/.test(accountId)||
   typeof apiToken!=='string'||!/^[A-Za-z0-9_-]{40,256}$/.test(apiToken)||
   typeof fetchImpl!=='function')unavailable();
  this.accountId=accountId;this.#key=apiToken;this.#fetch=fetchImpl;
  this.review=Object.freeze({...review});this.policyRevision=1;this.trustedUsage=true;
  this.invocationIdentity=Object.freeze({provider:this.review.provider,model:this.review.model,accountId});
  Object.freeze(this);
 }
 #prepare({evidence,maxTokens}){
  if(typeof maxTokens!=='string'||!/^[1-9][0-9]{0,3}$/.test(maxTokens)||
   BigInt(maxTokens)>BigInt(this.review.maxTokensPerInvocation))throw Error('MODEL_INPUT_LIMIT');
  if(!uuid.test(evidence?.sourceId??'')||!hash.test(evidence?.sourceHash??''))throw Error('MODEL_CONTRACT_MISMATCH');
  for(const value of [evidence.horizonStart,evidence.horizonEnd]){
   if(typeof value!=='string'||!/^\d{4}-\d{2}-\d{2}$/.test(value)||!Number.isFinite(Date.parse(value))||
    !new Date(value).toISOString().startsWith(value))throw Error('MODEL_CONTRACT_MISMATCH');
  }
  const days=(Date.parse(evidence.horizonEnd)-Date.parse(evidence.horizonStart))/86400000;
  if(days<=0||days>366)throw Error('MODEL_CONTRACT_MISMATCH');
  const expected={commandCode:'analytics.freeze_pipeline.v1',sourceId:evidence.sourceId,sourceHash:evidence.sourceHash,
   horizonStart:evidence.horizonStart,horizonEnd:evidence.horizonEnd};
  const fields=Object.keys(expected);
  // This task only proposes these exact references. Currency amounts, company
  // scope, tenant identifiers and population data are not sent to the provider.
  const prompt='<|begin_of_text|><|start_header_id|>system<|end_header_id|>\n\n'+
   'Return only the exact expected JSON object. No tools or execution.<|eot_id|>'+
   '<|start_header_id|>user<|end_header_id|>\n\n'+JSON.stringify({expected})+
   '<|eot_id|><|start_header_id|>assistant<|end_header_id|>\n\n';
  const body={prompt,raw:true,stream:false,temperature:0,response_format:{type:'json_schema',json_schema:{type:'object',
   properties:Object.fromEntries(fields.map(field=>[field,{type:'string',enum:[expected[field]]}])),required:fields,additionalProperties:false}}};
  // raw=true avoids an implicit chat template. A conservative UTF-8 byte bound
  // covers the explicit prompt/schema plus framing; only returned provider
  // token counts can settle usage. The bound is never reported as usage.
  const inputBound=Buffer.byteLength(JSON.stringify({...body,max_tokens:512}),'utf8')+64;
  const outputLimit=Math.min(512,Number(maxTokens)-inputBound);
  if(outputLimit<256)throw Error('MODEL_INPUT_LIMIT');
  return {body:JSON.stringify({...body,max_tokens:outputLimit}),inputBound,outputLimit};
 }
 preflight(input){this.#prepare(input);}
 async generate({evidence,maxTokens}){
  const {body,inputBound,outputLimit}=this.#prepare({evidence,maxTokens});
  const response=await this.#fetch(`https://api.cloudflare.com/client/v4/accounts/${this.accountId}/ai/run/${this.review.model}`,{
   method:'POST',headers:{authorization:`Bearer ${this.#key}`,'content-type':'application/json'},
   body,redirect:'error',signal:AbortSignal.timeout(30000)});
  if(!response.ok){await response.body?.cancel().catch(()=>{});throw Error(response.status===429?'MODEL_FREE_QUOTA_EXCEEDED':'MODEL_PROVIDER_UNAVAILABLE');}
  const envelope=await readBoundedJson(response,65536),result=envelope?.result,usage=result?.usage;
  if(envelope?.success!==true||!Array.isArray(envelope.errors)||envelope.errors.length!==0||!result||
   (result.tool_calls!==undefined&&(!Array.isArray(result.tool_calls)||result.tool_calls.length!==0)))throw Error('MODEL_OUTPUT_INVALID');
  if(!usage||![usage.prompt_tokens,usage.completion_tokens,usage.total_tokens].every(value=>Number.isSafeInteger(value)&&value>0)||
   usage.prompt_tokens>inputBound||usage.completion_tokens>outputLimit||usage.prompt_tokens+usage.completion_tokens!==usage.total_tokens||
   usage.total_tokens>Number(maxTokens))throw Error('TRUSTED_USAGE_MISMATCH');
  const text=typeof result.response==='string'?result.response:JSON.stringify(result.response);
  if(typeof text!=='string'||Buffer.byteLength(text,'utf8')>8192)throw Error('MODEL_OUTPUT_INVALID');
  return {tokens:String(usage.total_tokens),suggestion:validateModelSuggestion(JSON.parse(text),evidence)};
 }
}
