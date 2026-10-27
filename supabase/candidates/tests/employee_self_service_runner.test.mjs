import assert from 'node:assert/strict';
import test from 'node:test';
import { buildSuite, main } from '../run-employee-self-service-test.mjs';

const harness = 'begin;\n\\ir ../20261025090000_employee_self_service.sql\nselect no_plan();\nrollback;\n';
test('self-service suite inlines one exact candidate inside rollback', () => {
  const suite = buildSuite('create schema candidate_only;', harness);
  assert.ok(suite.startsWith('begin;\ncreate schema candidate_only;'));
  assert.ok(suite.endsWith('rollback;\n'));
  assert.ok(!suite.includes('\\ir'));
});
test('self-service suite rejects missing rollback and candidate transaction control', () => {
  assert.throws(() => buildSuite('select 1;', harness.replace('rollback;', 'commit;')));
  assert.throws(() => buildSuite('commit;\nselect 1;', harness));
  assert.throws(() => buildSuite('rollback;\nselect 1;', harness));
});
test('self-service suite rejects external or duplicate includes', () => {
  assert.throws(() => buildSuite('\\ir other.sql', harness));
  assert.throws(() => buildSuite('select 1;', harness.replace('select no_plan();', '\\ir ../20261025090000_employee_self_service.sql')));
});
test('self-service runner rejects all hosted target options before starting CLI', async () => {
  for (const args of [[], ['--linked'], ['--run-local', '--linked'], ['--run-local', '--db-url', 'postgres://example.invalid'], ['--run-local', '--project-ref', 'test']]) {
    await assert.rejects(main(args), /hosted targets are forbidden/);
  }
});
test('self-service real candidate composition is self-contained', async () => {
  assert.equal(await main(['--check']), 0);
});
