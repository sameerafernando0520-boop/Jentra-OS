import { createHash } from 'node:crypto';
import { readFile, writeFile } from 'node:fs/promises';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../..');
const w4 = [
  '20260926160000_wave4_calendar_resolution.sql',
  '20260926161000_wave4_organization.sql',
  '20260928082234_wave4_attendance_intervals.sql',
  '20260928083449_wave4_leave_ledger.sql',
  '20260930070000_wave4_synthetic_payroll.sql',
  '20261001080000_wave4_projects_time.sql',
  '20261001100000_wave4_project_expenses_billing.sql',
  '20261001110000_wave4_payroll_corrections.sql',
];
const w5 = [
  '20260925002000_wave3_financial_statements.sql',
  '20260926009000_wave3_governed_report_exports.sql',
  '20261008090000_wave5_historical_pipeline.sql',
  '20261008103000_wave5_dated_cash.sql',
  '20261008110000_wave5_governed_export_adapter.sql',
  '20261008120000_wave5_cash_payment_dates.sql',
];
const sha = x => createHash('sha256').update(x).digest('hex');
const evidence = path.join(root, 'docs/verification/wave5');
const migrationSources = {}, w4Hashes = {};
const parts = ['begin;'];
// W5 installs first while W4 tables are absent: validates optional providers.
for (const file of [...w5, ...w4]) {
  const relative = `supabase/migrations/${file}`;
  const bytes = await readFile(path.join(root, relative));
  if (/^\s*(?:commit|rollback)\s*;/im.test(bytes.toString())) throw Error(`Transaction boundary: ${file}`);
  migrationSources[relative] = sha(bytes);
  if (w4.includes(file)) w4Hashes[relative] = sha(bytes);
  parts.push(bytes.toString());
  if (file === w5.at(-1)) parts.push(`do $$begin
    if analytics.cash_source_installed('payroll_obligation') or analytics.cash_source_installed('payroll_correction') or analytics.cash_source_installed('project_reimbursement') then
      raise exception 'Unexpected live W4 source; refresh composition ownership';
    end if;
  end $$;`);
}
const fixture = 'supabase/wave_tests/wave5_cash_payment_dates_test.sql';
const w4Fixture = 'supabase/wave_tests/wave4_synthetic_fixture.sql';
const w4FixtureBytes = await readFile(path.join(root, w4Fixture));
parts.push(w4FixtureBytes.toString());
const bytes = await readFile(path.join(root, fixture));
const source = bytes.toString().replace(/select \* from finish\(true\);\s*$/m, '');
parts.push(source);
let query = parts.join('\n').replace('select no_plan();', 'select no_plan();\ncreate temporary table w5_dates_tap(message text);\ngrant insert,select on w5_dates_tap to authenticated;');
query = query.replace(/^select (is|ok|throws_ok|lives_ok)\(/gm, 'insert into w5_dates_tap select $1(');
query += '\nselect * from finish(true);\nselect jsonb_agg(message) tap from w5_dates_tap;\nrollback;\n';
await writeFile(path.join(evidence, 'cash-dates-candidate-20261008.sql'), query);
const baselinePath = path.join(evidence, 'cash-dates-wave4-source-baseline-20261008.json');
try {
  const old = JSON.parse(await readFile(baselinePath));
  if (Object.entries(old.sources).some(([file, hash]) => w4Hashes[file] !== hash) || Object.keys(old.sources).length !== Object.keys(w4Hashes).length) throw Error('Wave 4 owned source bytes changed');
} catch (error) {
  if (error.code !== 'ENOENT') throw error;
  await writeFile(baselinePath, JSON.stringify({ recordedAt: new Date().toISOString(), sources: w4Hashes }, null, 2) + '\n');
}
const report = { migrationSources, w4Fixture, w4FixtureSha256: sha(w4FixtureBytes), fixture, fixtureSha256: sha(bytes), querySha256: sha(query),
  actualWave4Schemas: true, installedMigrationsReplayed: false, strictFinish: true, rollback: true, installed: false };
await writeFile(path.join(evidence, 'cash-dates-candidate-20261008.hashes.json'), JSON.stringify(report, null, 2) + '\n');
process.stdout.write(JSON.stringify({ bytes: Buffer.byteLength(query), migrationCount: w4.length + w5.length, ...report }));
