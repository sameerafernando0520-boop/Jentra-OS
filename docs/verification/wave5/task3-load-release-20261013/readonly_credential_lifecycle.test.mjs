import test from 'node:test';
import assert from 'node:assert/strict';
import {createBoundedPgDriver,PrivatePgError} from './postgres_transport.mjs';
import {PROJECT_ID} from '../../../../tools/wave5/runtime_contract.mjs';
const config=()=>({host:`db.${PROJECT_ID}.supabase.co`,port:5432,database:'postgres',user:'postgres',
  password:'CONTROLLED_CALLBACK_VALUE_ONLY',ssl:{rejectUnauthorized:true}});
const deferred=()=>{let resolve;const promise=new Promise(value=>resolve=value);return{promise,resolve};};
test('never-settling private callback is bounded and cleanup does not wait for that promise',async()=>{
  let callbackCount=0,poolCount=0;const start=Date.now();
  const driver=createBoundedPgDriver({credentialProvider:()=>{callbackCount++;return new Promise(()=>{});},
    PoolClass:class {constructor(){poolCount++;}},acquireTimeoutMs:25});
  await assert.rejects(new driver.PgClient(config()).connect(),{code:'PRIVATE_DATABASE_CONFIG_TIMEOUT'});
  await driver.close();assert.equal(callbackCount,1);assert.equal(poolCount,0);assert.ok(Date.now()-start<1500);
});
test('close cancels private initialization immediately and late callback cannot construct a pool',async()=>{
  const started=deferred(),pendingCredentials=deferred();let poolCount=0;
  const driver=createBoundedPgDriver({credentialProvider:()=>{started.resolve();return pendingCredentials.promise;},
    PoolClass:class {constructor(){poolCount++;}}});
  const stopped=assert.rejects(new driver.PgClient(config()).connect(),{code:'POSTGRES_DRIVER_CLOSED_OR_FAILED'});
  await started.promise;const first=driver.close(),second=driver.close();assert.equal(first,second);
  await first;await stopped;pendingCredentials.resolve(config());await new Promise(resolve=>setImmediate(resolve));
  assert.equal(poolCount,0);assert.equal(driver.metrics().actualConnections,0);
});
test('private callback cannot inject an arbitrary error code or credential value into public failure',async()=>{
  const driver=createBoundedPgDriver({credentialProvider:()=>{throw new PrivatePgError('CONTROLLED_CALLBACK_VALUE_ONLY');},PoolClass:class {}});
  await assert.rejects(new driver.PgClient(config()).connect(),error=>error.code==='PRIVATE_DATABASE_CONFIG_UNAVAILABLE'
    &&!JSON.stringify(error).includes(config().password));await driver.close();
});
