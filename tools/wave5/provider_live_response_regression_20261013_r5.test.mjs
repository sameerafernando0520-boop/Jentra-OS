import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs/promises';
import {outcomeFromRpc} from './supabase_runtime_provider.mjs';
const actual=JSON.parse(await fs.readFile(new URL('../../docs/verification/wave5/genuine-source-workflows-resumed-20261013-r5-1791882899175/runtime-replay-and-denials.json',import.meta.url),'utf8'));
const request={commandId:'ad46d9da-607f-446d-b3c2-1c0e8a1adbc9'};
test('actual replay preserves the original command separately from genuine request and correlation IDs',()=>{
 assert.notEqual(actual.replay.value.request_id,request.commandId);
 const response={...actual.replay,responseSha256:actual.replay.evidence.responseSha256,transportEvidenceSha256:'a'.repeat(64)};
 assert.equal(outcomeFromRpc({operation:'forecast',request,response}).outcome,'applied');
 assert.throws(()=>outcomeFromRpc({operation:'forecast',request,response:{...response,value:{...response.value,command_id:response.value.request_id}}}));
});
test('actual compound permission denial requires its exact message, SQLSTATE and HTTP status',()=>{
 const response={...actual.foreign,status:actual.foreign.evidence.status,responseSha256:actual.foreign.evidence.responseSha256,transportEvidenceSha256:'b'.repeat(64)};
 assert.equal(outcomeFromRpc({operation:'analytics',request,response}).code,'PERMISSION_DENIED');
 assert.equal(outcomeFromRpc({operation:'analytics',request,response:{...response,status:500}}).outcome,'uncertain');
 assert.equal(outcomeFromRpc({operation:'analytics',request,response:{...response,value:{...response.value,code:'54000'}}}).outcome,'uncertain');
 assert.equal(outcomeFromRpc({operation:'analytics',request,response:{...response,value:{...response.value,message:'Permission denied'}}}).outcome,'uncertain');
});
