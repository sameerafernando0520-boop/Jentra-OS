import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs/promises';
import { EventEmitter } from 'node:events';
import { decodePublicResult, normalizeLedger, checkInitialLedger, checkOneApplied,
  checkInitialPreflight, checkRenamePreservation, createManagementTransport, PROJECT } from './approved_management_installer.mjs';
const initial = JSON.parse(await fs.readFile('docs/verification/wave5/approved-live-resume-20261013-r5-raw.json', 'utf8'));
const live = Object.fromEntries(initial.results.map(item => [item.value.label, decodePublicResult(item.value.result)]));
const old = live.ledger.migrations.slice(0, 43);
test('only the exact original43 plus already-installed conversion migration can start', () => {
  assert.equal(checkInitialLedger(live.ledger.migrations, old).length, 44);
  assert.throws(() => checkInitialLedger(old, old), /EXACT_44_LEDGER_REQUIRED/);
  assert.throws(() => checkInitialLedger([...live.ledger.migrations, { version: '20261013070000', name: 'unreviewed' }], old));
  assert.throws(() => normalizeLedger([...old, old[0]]), /LEDGER_DUPLICATE/);
});
test('successful response cannot conceal missing, duplicate or concurrent migration effects', () => {
  const addition = { version: '20261013070000', name: 'procurement_requisition_drafts' };
  assert.deepEqual(checkOneApplied(live.ledger.migrations, [...live.ledger.migrations, addition], addition.name), addition);
  assert.throws(() => checkOneApplied(live.ledger.migrations, live.ledger.migrations, addition.name));
  assert.throws(() => checkOneApplied(live.ledger.migrations, [...old, addition], addition.name));
  assert.throws(() => checkOneApplied(live.ledger.migrations, [...live.ledger.migrations, { ...addition, name: 'foreign_change' }], addition.name));
});
test('initial installation rechecks all40 fields and rejects access, provider or collision drift', () => {
  const prior = live.fullPreflight[0], now = Date.parse('2026-10-13T07:00:00Z');
  const current = { ...structuredClone(prior), observed_at: '2026-10-13T06:59:59Z' };
  assert.equal(checkInitialPreflight(current, prior, now).metadataFieldsCompared, 40);
  assert.throws(() => checkInitialPreflight({ ...current, memberships: 2 }, prior, now), /METADATA_DRIFT/);
  const changed = structuredClone(current); changed.functions[0].name = 'changed';
  assert.throws(() => checkInitialPreflight(changed, prior, now), /METADATA_DRIFT/);
  assert.throws(() => checkInitialPreflight({ ...current, observed_at: '2026-10-13T06:40:00Z' }, prior, now), /FRESH_SERVER/);
  assert.throws(() => checkInitialPreflight({ ...current, observed_at: '2026-10-13T07:02:00Z' }, prior, now), /FRESH_SERVER/);
});
test('original helper body preservation uses a fresh three-function baseline before order58', () => {
  const before = { functions: [1, 2, 3].map(i => ({ originalSignature: 'original' + i, preservedSignature: 'preserved' + i,
    originalPresent: true, preservedPresent: false, originalBodyLfSha256: String(i).repeat(64) })) };
  const after = { functions: before.functions.map(row => ({ ...row, preservedPresent: true, preservedBodyLfSha256: row.originalBodyLfSha256 })) };
  assert.equal(checkRenamePreservation(before, after), true);
  const changed = structuredClone(after); changed.functions[1].preservedBodyLfSha256 = '9'.repeat(64);
  assert.throws(() => checkRenamePreservation(before, changed), /RENAMED_BASELINE_BODY_CHANGED/);
});
test('private Management transport never writes through an unverified socket or free endpoint', async () => {
  let ends = 0, target;
  const requestFactory = (url, _options, _response) => { target = url;
    const req = new EventEmitter(); req.destroy = () => {}; req.end = () => { ends++; };
    queueMicrotask(() => { const socket = new EventEmitter(); socket.encrypted = true; socket.authorized = false;
      req.emit('socket', socket); socket.emit('secureConnect'); }); return req; };
  const call = createManagementTransport('synthetic-not-a-real-token', { requestFactory, timeoutMs: 100 });
  await assert.rejects(call('GET', '/database/migrations'), /VERIFIED_MANAGEMENT_TLS_REQUIRED/);
  assert.equal(ends, 0); assert.equal(target.href, `https://api.supabase.com/v1/projects/${PROJECT}/database/migrations`);
  await assert.rejects(call('POST', '/database/query', { query: 'SELECT 1' }), /READ_ONLY_QUERY_REQUIRED/);
  await assert.rejects(call('DELETE', ''), /FIXED_MANAGEMENT_ENDPOINT_REQUIRED/);
  await assert.rejects(call('GET', '/api-keys'), /FIXED_MANAGEMENT_ENDPOINT_REQUIRED/);
});
test('private HTTP errors are reduced to fixed codes and late sockets cannot send after timeout', async () => {
  let req, ends = 0;
  const call = createManagementTransport('synthetic-not-a-real-token', { timeoutMs: 5,
    requestFactory: () => { req = new EventEmitter(); req.destroy = () => {}; req.end = () => { ends++; }; return req; } });
  await assert.rejects(call('POST', '/database/migrations', { query: 'reviewed-test', name: 'reviewed_test' }), /MANAGEMENT_TIMEOUT_UNCERTAIN/);
  req.emit('socket', { encrypted: true, authorized: true }); assert.equal(ends, 0);
});
