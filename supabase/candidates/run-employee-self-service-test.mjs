// Stages only a self-contained rollback suite into an isolated local CLI target.
import { readFile } from 'node:fs/promises';
import { join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { stageAndRun } from './run-employee-push-test.mjs';

const root = fileURLToPath(new URL('../../', import.meta.url));
const include = /^\\ir \.\.\/20261025090000_employee_self_service\.sql[\t ]*\r?$/m;
export function buildSuite(candidate, harness) {
  if (!/^begin;/m.test(harness) || !/rollback;\s*$/i.test(harness)
      || harness.split(include).length !== 2
      || /^\s*(?:commit|rollback)\s*;/im.test(candidate)) {
    throw new Error('Expected one candidate include inside a rollback-only suite.');
  }
  const suite = harness.replace(include, () => candidate);
  if (/^\\(?:i|ir|include|include_relative)\s/m.test(suite)) {
    throw new Error('The isolated suite must have no external includes.');
  }
  return suite;
}
export async function main(args) {
  if (args.length !== 1 || !['--help', '--check', '--run-local'].includes(args[0])) {
    throw new Error('Use exactly --help, --check or --run-local; hosted targets are forbidden.');
  }
  if (args[0] === '--help') {
    console.log('Employee self-service candidate: --check validates composition; --run-local runs a rollback suite using supabase test db --local. No hosted options are accepted.');
    return 0;
  }
  const [candidate, harness] = await Promise.all([
    readFile(new URL('20261025090000_employee_self_service.sql', import.meta.url), 'utf8'),
    readFile(new URL('tests/employee_self_service_candidate_test.sql', import.meta.url), 'utf8'),
  ]);
  const suite = buildSuite(candidate, harness);
  if (args[0] === '--check') {
    console.log('Self-service suite is self-contained. PostgreSQL has not been executed.');
    return 0;
  }
  return stageAndRun({ suite, testsDir: join(root, 'supabase', 'candidates'), cwd: root });
}
if (process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  main(process.argv.slice(2)).then(code => { process.exitCode = code; }).catch(() => {
    console.error('Self-service candidate suite could not complete; use an isolated local Supabase stack and valid runner inputs.');
    process.exitCode = 1;
  });
}
