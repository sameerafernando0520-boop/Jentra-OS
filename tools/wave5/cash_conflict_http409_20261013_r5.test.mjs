import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs/promises';
import { hashBytes } from './runtime_contract.mjs';
import { decodePublicResult } from './approved_management_installer.mjs';

const patch = await fs.readFile(new URL('../../supabase/candidates/wave5_cash_conflict_http409_20261013_r5.sql', import.meta.url), 'utf8');
const fixtures = [
  { file: '../../supabase/migrations/20261008120000_wave5_cash_payment_dates.sql', name: 'wave5_cash_date_command',
    signature: 'api.wave5_cash_date_command(uuid,uuid,uuid,uuid,uuid,timestamp with time zone,text,jsonb)',
    before: '509d9f2ef975ca30a355b6874603e1469564107eed911267454de54607e4a149',
    after: '9c87b6aaf874e0a5061b7710b9341240ba982fc26731fe1e99f00646039bf482',
    clauses: [['CASH_DATE_VERSION_CONFLICT', 1], ['CASH_DATE_SOURCE_CHANGED', 2], ['CASH_DATE_PROPOSAL_CHANGED', 1]] },
  { file: '../../supabase/migrations/20261008103000_wave5_dated_cash.sql', name: 'wave5_cash_save',
    installedName: 'wave5_cash_save_v2', signature: 'api.wave5_cash_save_v2(uuid,uuid,uuid,uuid,text,jsonb)',
    before: 'a9e13fb88a940206bb7fc9d804f5dafd591fea5dce138a688f251fb5be684c91',
    after: '98c96ad97956117996c8874d2ff8e1e7e69d827e72f71757c68034d1e5780564',
    clauses: [['SOURCE_BASIS_CHANGED', 1]] },
];
const count = (value, part) => value.split(part).length - 1;
for (const fixture of fixtures) {
  const migration = (await fs.readFile(new URL(fixture.file, import.meta.url), 'utf8')).replaceAll('\r\n', '\n');
  const escaped = fixture.name.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
  const match = migration.match(new RegExp(`create function api[.]${escaped}\\([^]*?\\bas \\$\\$([^]*?)\\$\\$;`, 'i'));
  assert.ok(match, 'Exact original SQL function body must be available');
  const body = match[1];
  test(`${fixture.installedName ?? fixture.name}: installed normalized source fingerprint is exact`, () => {
    assert.equal(hashBytes(body), fixture.before);
    assert.ok(patch.includes(fixture.signature));
    assert.ok(patch.includes(fixture.before));
    assert.ok(patch.includes(fixture.after));
  });
  test(`${fixture.installedName ?? fixture.name}: only reviewed application conflicts change`, () => {
    let revised = body, changes = 0;
    for (const [message, occurrences] of fixture.clauses) {
      const old = `errcode='40001',message='${message}'`, next = `errcode='PT409',message='${message}'`;
      assert.equal(count(body, old), occurrences);
      revised = revised.replaceAll(old, next); changes += occurrences;
    }
    assert.equal(changes, fixture.clauses.reduce((n, x) => n + x[1], 0));
    assert.equal(hashBytes(revised), fixture.after);
    for (const [message] of fixture.clauses) revised = revised.replaceAll(`errcode='PT409',message='${message}'`, `errcode='40001',message='${message}'`);
    assert.equal(revised, body, 'Unchanged guards, receipt identities, permissions, data mutations and replay semantics');
  });
}
test('DDL scope is exactly two installed routines with source and metadata fail-closed guards', () => {
  assert.equal(count(patch, 'execute definition;'), 1);
  assert.equal(count(patch, "'api.wave5_"), 2);
  for (const guard of ['to_regprocedure(target.signature)', 'before_row.prosecdef is distinct from true',
    "before_row.proconfig is distinct from array['search_path=\"\"']::text[]", 'target.before_hash',
    'target.after_hash', "pg_catalog.to_jsonb(before_row)-'prosrc'", "pg_catalog.to_jsonb(after_row)-'prosrc'",
    'CASH_CONFLICT_PATCH_FUNCTION_MISSING', 'CASH_CONFLICT_PATCH_SOURCE_GUARD_FAILED',
    'CASH_CONFLICT_PATCH_CLAUSE_MISSING', 'CASH_CONFLICT_PATCH_POSTCHECK_FAILED']) assert.ok(patch.includes(guard), guard);
  assert.ok(!/\b(?:grant|revoke|delete|insert|update|truncate|drop)\b/i.test(patch.replace(/--[^\n]*/g, '')));
  assert.ok(!/\b(?:auth|vault|cron|net)[.]/i.test(patch));
});
test('DDL retains transaction boundaries and bounded lock/statement waits', () => {
  assert.match(patch, /\bbegin;\s*set local lock_timeout='5s';\s*set local statement_timeout='30s';/);
  assert.match(patch, /end\s*\$cash_conflict_http409\$;\s*commit;\s*$/);
  assert.ok(!/exception when|serialization_failure|pg_terminate_backend|pg_cancel_backend/i.test(patch));
});
test('fresh connected source fingerprints match both approved preconditions without installation', async () => {
  const evidence = JSON.parse(await fs.readFile(new URL('../../docs/verification/wave5/cash-conflict-live-source-fingerprints-20261013-r5-a2.json', import.meta.url), 'utf8'));
  assert.equal(evidence.projectId, 'xpdoufauvrbdmxgngetv'); assert.equal(evidence.writeRequests, 0);
  assert.equal(evidence.results.length, 2);
  for (const result of evidence.results) {
    assert.equal(result.status, 'fulfilled');
    const rows = decodePublicResult(result.value);
    assert.equal(rows.length, 2);
    for (const fixture of fixtures) {
      const row = rows.find(x => x.proname === (fixture.installedName ?? fixture.name));
      assert.equal(row.body_lf_sha256, fixture.before); assert.equal(row.security_definer, true);
      assert.deepEqual(row.proconfig, ['search_path=""']);
    }
  }
});
