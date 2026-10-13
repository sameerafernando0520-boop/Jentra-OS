import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs/promises';
import path from 'node:path';
import os from 'node:os';
import crypto from 'node:crypto';
import { EventEmitter } from 'node:events';
import { runtimeSealKey, appendRuntimeSecret, readRuntimeSecret } from './private_runtime_seal.mjs';
import { createApprovedAuthAdmin, createPrivateKeyReader, selectExistingLegacyKeys } from './private_runtime_http.mjs';
import { validateReturnedCreatedUser } from './provision_auth_management_20261013_r5.mjs';
import { PROJECT } from './approved_management_installer.mjs';

test('only the six reviewed emails can be created and the API exposes no delete/update operation', async () => {
  let calls=0,target,body;
  const factory=(url,options,callback)=>{ calls++;target=url;
    const req=new EventEmitter();req.destroy=()=>{};req.end=text=>{body=JSON.parse(text);const res=new EventEmitter();res.statusCode=200;
      callback(res);queueMicrotask(()=>{res.emit('data',Buffer.from('{}'));res.emit('end');});};
    queueMicrotask(()=>req.emit('socket',{encrypted:true,authorized:true}));return req; };
  const admin=createApprovedAuthAdmin('eyJ-synthetic-testing-only',{requestFactory:factory});
  assert.deepEqual(Object.keys(admin).sort(),['create','get']);
  assert.throws(()=>admin.create('desktop-test','a'.repeat(43)),/EXACT_PRIVATE_NEW_ACCOUNT_REQUIRED/);
  assert.throws(()=>admin.create('proposer','short'),/EXACT_PRIVATE_NEW_ACCOUNT_REQUIRED/);
  assert.equal(calls,0);await admin.create('proposer','a'.repeat(43));
  assert.equal(target.href,`https://${PROJECT}.supabase.co/auth/v1/admin/users`);
  assert.equal(body.email,'w5-proposer@jentra.invalid');assert.equal(body.email_confirm,true);
  assert.equal(Object.keys(body).length,3);
});

test('unverified and late sockets cannot transmit privileged Auth credentials', async () => {
  let ends=0,req;
  const factory=()=>{req=new EventEmitter();req.destroy=()=>{};req.end=()=>{ends++;};
    queueMicrotask(()=>req.emit('socket',{encrypted:true,authorized:false,once(_event,fn){fn();}}));return req;};
  const admin=createApprovedAuthAdmin('eyJ-synthetic-testing-only',{requestFactory:factory});
  await assert.rejects(admin.create('proposer','a'.repeat(43)),/VERIFIED_PRIVATE_TLS_REQUIRED/);assert.equal(ends,0);
  const timeoutFactory=()=>{req=new EventEmitter();req.destroy=()=>{};req.end=()=>{ends++;};return req;};
  const read=createPrivateKeyReader('synthetic-owner-token',{requestFactory:timeoutFactory,timeoutMs:5});
  await assert.rejects(read(),/PRIVATE_HTTP_TIMEOUT_UNCERTAIN/);req.emit('socket',{encrypted:true,authorized:true});assert.equal(ends,0);
});

test('keys are selected only from one existing legacy key of each exact kind', () => {
  const rows=[{name:'service_role',api_key:'eyJ-synthetic-admin'},{name:'anon',api_key:'eyJ-synthetic-anon'}];
  assert.equal(selectExistingLegacyKeys(rows).anon,'eyJ-synthetic-anon');
  assert.throws(()=>selectExistingLegacyKeys([rows[0]]),/EXACT_EXISTING_LEGACY_KEY_REQUIRED/);
  assert.throws(()=>selectExistingLegacyKeys([...rows,rows[0]]),/EXACT_EXISTING_LEGACY_KEY_REQUIRED/);
});

test('Admin-created IDs, exact confirmed emails and unique users are required', () => {
  const user={id:'11111111-1111-4111-8111-111111111111',email:'w5-proposer@jentra.invalid',email_confirmed_at:'2026-10-13T07:00:00Z'};
  assert.equal(validateReturnedCreatedUser(user,'proposer',[]).authId,user.id);
  for(const changed of [{...user,id:'made-up'}, {...user,email:'someone-else@jentra.invalid'}, {...user,email_confirmed_at:null},
    {...user,deleted_at:'2026-10-13T07:01:00Z'}]) assert.throws(()=>validateReturnedCreatedUser(changed,'proposer',[]),/GENUINE_EXACT_ADMIN_CREATED_USER_REQUIRED/);
  assert.throws(()=>validateReturnedCreatedUser(user,'proposer',[user.id]),/GENUINE_EXACT_ADMIN_CREATED_USER_REQUIRED/);
});

test('private recovery records are ciphertext, authenticated and scoped to an exact kind', async () => {
  const directory=path.join(os.tmpdir(),'JentraOS-Wave5-owner-'+crypto.randomBytes(16).toString('hex'));
  await fs.mkdir(directory);const key=runtimeSealKey(crypto.randomBytes(32).toString('base64'));
  try {
    const value={password:'SYNTHETIC_PRIVATE_PASSWORD_ONLY',secret:'SYNTHETIC_FACTOR_ONLY'};
    const filename=await appendRuntimeSecret(directory,key,'account-intent',value);
    const text=await fs.readFile(path.join(directory,filename),'utf8');assert.equal(text.includes(value.password),false);
    assert.deepEqual(await readRuntimeSecret(directory,key,filename,'account-intent'),value);
    await assert.rejects(readRuntimeSecret(directory,key,filename,'account-created'),/PRIVATE_RUNTIME_RECORD_BINDING_REQUIRED/);
    await assert.rejects(readRuntimeSecret(directory,crypto.randomBytes(32),filename,'account-intent'));
    await assert.rejects(readRuntimeSecret(directory,key,'../outside.json','account-intent'),/EXACT_PRIVATE_RECORD_REQUIRED/);
    const tampered=JSON.parse(text);tampered.ciphertext='A'+tampered.ciphertext.slice(1);
    await fs.writeFile(path.join(directory,filename),JSON.stringify(tampered));
    await assert.rejects(readRuntimeSecret(directory,key,filename,'account-intent'));
  } finally { key.fill(0);for(const file of await fs.readdir(directory))await fs.unlink(path.join(directory,file));await fs.rmdir(directory); }
});
