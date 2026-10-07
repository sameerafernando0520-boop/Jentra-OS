import { test } from 'node:test';
import assert from 'node:assert/strict';
import { createHash } from 'node:crypto';
import { permittedAddress, resolveDestination, forecastEvent, signDelivery, attemptOutcome, deliverForecast, validateIntegrationCredential } from './integration_policy.mjs';
const id = i => `10000000-0000-0000-0000-${String(i).padStart(12, '0')}`;
const scope = { tenantId: id(1), legalEntityId: id(2), branchId: null };
const event = { eventId: id(3), type: 'analytics.forecast.frozen.v1', ...scope, forecastId: id(4), definitionVersion: 1, sourceHash: 'a'.repeat(64) };
const subscription = { id: id(5), scope, enabled: true, url: 'https://events.jentra.test/hooks', allowedHosts: ['events.jentra.test'], keyVersion: 2 };
const key = Buffer.alloc(32, 7);
test('unsafe IPv4, IPv6, mapped and noncanonical addresses fail', () => {
  for (const ip of ['0.0.0.0','10.1.2.3','100.64.0.1','127.0.0.1','169.254.169.254','172.31.1.1','192.168.1.1','192.0.2.1','198.19.1.1','203.0.113.1','224.1.1.1','255.255.255.255',
    '::','::1','::ffff:10.0.0.1','64:ff9b::a00:1','100::1','2001:db8::1','2002::1','3fff::1','fc00::1','fe80::1','ff02::1','127.1','2130706433']) assert.equal(permittedAddress(ip), false, ip);
  assert.equal(permittedAddress('8.8.8.8'), true);
  assert.equal(permittedAddress('2606:4700:4700::1111'), true);
});
test('all DNS answers and each attempt must remain safe', async () => {
  await assert.rejects(resolveDestination(subscription.url, new Set(subscription.allowedHosts), async () => ['8.8.8.8','127.0.0.1']), /UNSAFE_DESTINATION/);
  for (const url of ['http://events.jentra.test','https://user@events.jentra.test','https://events.jentra.test:444','https://events.jentra.test/#fragment','https://foreign.test']) {
    await assert.rejects(resolveDestination(url, new Set(subscription.allowedHosts), async () => ['8.8.8.8']), /UNSAFE_DESTINATION/);
  }
});
test('event scope and private payload injection rejected before delivery', () => {
  assert.throws(() => forecastEvent({ ...event, reason: 'private' }, scope), /EVENT_CONTRACT_MISMATCH/);
  assert.throws(() => forecastEvent(event, { ...scope, tenantId: id(9) }), /EVENT_CONTRACT_MISMATCH/);
});
test('signature binds exact bytes, event identity, timestamp and rotating key version', () => {
  const payload = forecastEvent(event, scope), options = { payload, eventId: event.eventId, timestamp: 100, key, keyVersion: 2 };
  const a = signDelivery(options);
  assert.match(a, /^v2=[0-9a-f]{64}$/);
  assert.notEqual(a, signDelivery({ ...options, payload: Buffer.concat([payload, Buffer.from(' ')]) }));
  assert.notEqual(a, signDelivery({ ...options, timestamp: 101 }));
  assert.notEqual(a, signDelivery({ ...options, eventId: id(9) }));
});
test('bounded retries retain stable event identity and reach dead letter', () => {
  assert.equal(attemptOutcome(id(3),id(5),1,200).state,'acknowledged');
  assert.equal(attemptOutcome(id(3),id(5),1,302).state,'retry');
  assert.equal(attemptOutcome(id(3),id(5),8,500).state,'dead_letter');
  assert.throws(() => attemptOutcome(id(3),id(5),9,500));
});
test('injected transport sees pinned public address and revocation prevents send', async () => {
  let sent = 0, authorized = 0;
  const options = { event, subscription, attempt: 1, timestamp: 100, key,
    authorizeCommittedEvent: async () => { authorized++; }, resolve: async () => ['8.8.8.8'],
    post: async (destination, payload, headers) => { assert.equal(destination.address,'8.8.8.8'); assert.equal(payload.includes('reason'),false); assert.match(headers['x-jentra-signature'],/^v2=/); sent++; return 204; } };
  assert.equal((await deliverForecast(options)).state,'acknowledged'); assert.equal(sent,1); assert.equal(authorized,2);
  authorized=0;
  await assert.rejects(deliverForecast({ ...options, authorizeCommittedEvent: async () => { if (++authorized===2) throw Error('revoked'); } }), /revoked/);
  assert.equal(sent,1);
});
test('unknown transport result requires reconciliation without an automatic retry or raw errors', async () => {
  const result=await deliverForecast({ event,subscription,attempt:1,timestamp:100,key,authorizeCommittedEvent:async()=>{},
    resolve:async()=>['8.8.8.8'],post:async()=>{throw Error('secret private diagnostic');} });
  assert.equal(result.state,'unknown');assert.equal(result.retryAfterSeconds,null);assert.equal(JSON.stringify(result).includes('secret'),false);
  assert.equal(attemptOutcome(id(3),id(5),8,null).state,'unknown');
  assert.equal(attemptOutcome(id(3),id(5),8,null).retryAfterSeconds,null);
});
test('integration credentials bind expiry, revocation, scope, hash, command and allowance', () => {
  const token='synthetic-only-token-'.repeat(3),credential={ tokenHash:createHash('sha256').update(token).digest('hex'),scope,
    revokedAt:null,startsAt:1,expiresAt:100,commands:['analytics.freeze_pipeline.v1'] };
  const options={token,credential,scope,commandCode:'analytics.freeze_pipeline.v1',now:2,liveEntitlement:true,quotaReserved:true,throttleReserved:true,schemaVersion:1};
  assert.doesNotThrow(()=>validateIntegrationCredential(options));
  for(const changed of [{now:100},{token:'changed-token-'.repeat(4)},{scope:{...scope,branchId:id(6)}},{quotaReserved:false},{throttleReserved:false},{credential:{...credential,commands:null}},
    {commandCode:'arbitrary.sql'},{credential:{...credential,revokedAt:2}}]) assert.throws(()=>validateIntegrationCredential({...options,...changed}),/INTEGRATION_ACCESS_DENIED/);
});

test('exhausted attempts fail before authority, DNS or transport',async()=>{
 let work=0;
 await assert.rejects(deliverForecast({event,subscription,attempt:9,timestamp:100,key,
  authorizeCommittedEvent:async()=>{work++;},resolve:async()=>{work++;return ['8.8.8.8'];},post:async()=>{work++;return 204;}}),/VALIDATION_ERROR/);
 assert.equal(work,0);
});
