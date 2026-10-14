import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs/promises';
import {createEdgeRuntime} from './edge_runtime_20261014_r5_v5.mjs';
import {createEdgeReceiver} from './edge_receiver_20261014_r5_v5.mjs';
const origin='http://xpdoufauvrbdmxgngetv.supabase.co';
const makeRequest=url=>new Request(url,{method:'POST',headers:{'content-type':'application/json'},body:'{}'});

test('managed runtime schedule without its secret is denied before any backend call',async()=>{
 let calls=0;const forbidden=()=>{calls++;throw Error('NETWORK_UNEXPECTED');};
 const handler=createEdgeRuntime({env:{SUPABASE_URL:'https://xpdoufauvrbdmxgngetv.supabase.co',SUPABASE_SERVICE_ROLE_KEY:'DELIBERATELY_FAKE_TEST_FIXTURE_000000000.a.b'},fetchImpl:forbidden,controlFactory:()=>({}),edgeRpcFactory:()=>forbidden});
 const response=await handler(makeRequest(origin+'/wave5-runtime/schedule'));
 assert.equal(response.status,403);assert.deepEqual(await response.json(),{code:'WORKER_ACCESS_DENIED'});assert.equal(calls,0);
});
test('all managed receiver routes still deny unsigned bytes before key reads, backend writes or fault responses',async()=>{
 let reads=0,calls=0;const handler=createEdgeReceiver({env:{get(){reads++;throw Error('PRIVATE_KEY_READ_UNEXPECTED');}},fetchImpl:()=>{calls++;throw Error('NETWORK_UNEXPECTED');}});
 for(const route of ['accept','redirect','timeout','reject']){const response=await handler(makeRequest(origin+'/wave5-receiver/'+route));assert.equal(response.status,403);assert.deepEqual(await response.json(),{code:'INTEGRATION_ACCESS_DENIED'});assert.equal(response.headers.has('location'),false);}
 assert.equal(reads,0);assert.equal(calls,0);
});
test('both handlers reject unreviewed HTTP origins before accessing provider credentials',async()=>{
 let reads=0,calls=0;const env={get(){reads++;throw Error('PRIVATE_KEY_READ_UNEXPECTED');}},fetchImpl=()=>{calls++;throw Error('NETWORK_UNEXPECTED');};
 const runtime=createEdgeRuntime({env,fetchImpl}),receiver=createEdgeReceiver({env,fetchImpl});
 for(const p of ['http://edge-runtime.supabase.com','http://127.0.0.1','http://xpdoufauvrbdmxgngetv.supabase.co.other.invalid']){assert.equal((await runtime(makeRequest(p+'/wave5-runtime/schedule'))).status,404);assert.equal((await receiver(makeRequest(p+'/wave5-receiver/accept'))).status,404);}
 assert.equal(reads,0);assert.equal(calls,0);
});
test('all handler source is preserved apart from the single reviewed route import',async()=>{
 for(const role of ['runtime','receiver']){const before=await fs.readFile(new URL('./edge_'+role+'_20261014_r5_v4.mjs',import.meta.url),'utf8'),after=await fs.readFile(new URL('./edge_'+role+'_20261014_r5_v5.mjs',import.meta.url),'utf8');assert.equal(after,before.replace('./edge_route_20261014_r5_v4.mjs','./edge_route_20261014_r5_v5.mjs'));}
});
