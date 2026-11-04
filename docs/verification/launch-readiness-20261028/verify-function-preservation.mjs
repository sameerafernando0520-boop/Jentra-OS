// Isolated in-memory PostgreSQL probe. No connection string or hosted access.
// Runtime: npm install --prefix build/launch-validation-runtime --ignore-scripts
//   --no-audit --no-fund --save-exact @electric-sql/pglite@0.5.12
import assert from 'node:assert/strict';
import { readFile, writeFile } from 'node:fs/promises';
import { PGlite } from '../../../build/launch-validation-runtime/node_modules/@electric-sql/pglite/dist/index.js';

const source = await readFile(new URL('../../../supabase/candidates/tests/employee_hr_event_producers_test.sql', import.meta.url), 'utf8');
const helper = source.match(/create function pg_temp\.hr_function_definition[\s\S]*?\$\$;/)?.[0];
assert.ok(helper, 'probe must execute the real harness helper');
const db = new PGlite();
const checks = [];
const read = async () => (await db.query(`select
 pg_get_functiondef('employee_self.probe(employee_self.cases)'::regprocedure) raw,
 pg_temp.hr_function_definition('employee_self.probe(employee_self.cases)'::regprocedure) canonical,
 (select proacl::text from pg_proc where oid='employee_self.probe(employee_self.cases)'::regprocedure) acl`)).rows[0];
try {
  const version = (await db.query('select version() version')).rows[0].version;
  await db.exec(`begin; create schema employee_self;
    create table employee_self.cases(id uuid);
    ${helper}
    create function employee_self.probe(c employee_self.cases) returns integer language sql as $$select 1$$;`);
  const before = await read();
  await db.exec('set local search_path=employee_self,public,pg_catalog;');
  const changedPath = await read();
  assert.notEqual(changedPath.raw, before.raw);
  checks.push('Reproduced false difference from caller search_path');
  assert.equal(changedPath.canonical, before.canonical);
  checks.push('Actual harness helper preserves equality across search_path changes');
  await db.exec('create or replace function employee_self.probe(c employee_self.cases) returns integer language sql as $$select 2$$;');
  assert.notEqual((await read()).canonical, before.canonical);
  checks.push('Actual body changes remain detectable');
  await db.exec('revoke all on function employee_self.probe(employee_self.cases) from public;');
  assert.notEqual((await read()).acl, before.acl);
  checks.push('Actual execution-grant changes remain detectable');
  await db.exec('rollback;');
  assert.equal((await db.query("select to_regnamespace('employee_self')::text scope")).rows[0].scope, null);
  checks.push('Probe schema and fixtures roll back');
  const report = { atUtc: new Date().toISOString(), kind: 'in-memory-postgresql-preservation-regression',
    version, runtime: '@electric-sql/pglite@0.5.12', checks, passed: checks.length,
    fullSupabaseSuiteExecuted: false, hostedConnection: false, migrationsInstalled: false };
  await writeFile(new URL('function-preservation-result.json', import.meta.url), JSON.stringify(report, null, 2) + '\n');
  console.log(JSON.stringify(report, null, 2));
} finally {
  await db.close();
}
