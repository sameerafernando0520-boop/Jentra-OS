import { createHash } from 'node:crypto';
import { readFile, writeFile } from 'node:fs/promises';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../..');
const migrations = [
  'supabase/migrations/20260925002000_wave3_financial_statements.sql',
  'supabase/migrations/20260926009000_wave3_governed_report_exports.sql',
  'supabase/migrations/20261008090000_wave5_historical_pipeline.sql',
  'supabase/migrations/20261008093000_wave5_persistent_delivery.sql',
  'supabase/migrations/20261008100000_wave5_invocation_storage.sql',
  'supabase/migrations/20261008103000_wave5_dated_cash.sql',
  'supabase/migrations/20261008110000_wave5_governed_export_adapter.sql',
  'supabase/migrations/20261008113000_wave5_statement_classifications.sql',
];
const fixtures = [
  'supabase/wave_tests/wave5_process_metrics_test.sql',
  'supabase/wave_tests/wave5_remaining_adapters_test.sql',
  'supabase/wave_tests/wave5_realized_mapping_test.sql',
];
const sha256 = (value) => createHash('sha256').update(value).digest('hex');
const parts = ['begin;'];
const hashes = {};
for (const file of [...migrations, ...fixtures]) {
  const source = await readFile(path.join(root, file), 'utf8');
  if (/^\s*(?:commit|rollback)\s*;/im.test(source)) {
    throw new Error(`Unexpected transaction boundary in ${file}`);
  }
  hashes[file] = sha256(await readFile(path.join(root, file)));
  parts.push(source.split('select * from finish(true);')[0]);
}
let query = parts.join('\n').replace('select no_plan();',
  'select no_plan();\ncreate temporary table w5_tap(message text);');
query = query.replace(/^select (is|ok|throws_ok)\(/gm, 'insert into w5_tap select $1(');
query += '\nselect * from finish(true);\nselect jsonb_agg(message) tap from w5_tap;\nrollback;\n';
const evidence = path.join(root, 'docs/verification/wave5');
const queryFile = path.join(evidence, 'remaining-candidate-20261008.sql');
const hashFile = path.join(evidence, 'remaining-candidate-20261008.hashes.json');
await writeFile(queryFile, query, 'utf8');
const report = {
  candidateSources: hashes,
  querySha256: sha256(query),
  strictFinish: true,
  rollback: true,
  installedMigrationsReplayed: false,
};
await writeFile(hashFile, `${JSON.stringify(report, null, 2)}\n`, 'utf8');
process.stdout.write(JSON.stringify({
  migrationCount: migrations.length,
  fixtureCount: fixtures.length,
  bytes: Buffer.byteLength(query),
  querySha256: report.querySha256,
}));
