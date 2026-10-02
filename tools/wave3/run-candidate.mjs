import fs from 'node:fs';
import crypto from 'node:crypto';
import { performance } from 'node:perf_hooks';

const [input, output] = process.argv.slice(2);
if (!input || !output) throw new Error('Usage: node run-candidate.mjs input.sql output.json');
const query = fs.readFileSync(input, 'utf8').replace(/^\uFEFF/, '');
if (!/^begin;/i.test(query.trimStart()) || !/finish\(true\)/.test(query) ||
    !/rollback;$/i.test(query.trimEnd()) || /^\s*commit\s*;/im.test(query)) {
  throw new Error('Only strict rollback candidate transactions are authorized.');
}
const token = process.env.SUPABASE_ACCESS_TOKEN;
if (!token) throw new Error('Existing Supabase management authorization unavailable.');
const start = performance.now();
const response = await fetch('https://api.supabase.com/v1/projects/xpdoufauvrbdmxgngetv/database/query', {
  method: 'POST', headers: { Authorization: `Bearer ${token}`, 'Content-Type': 'application/json' },
  body: JSON.stringify({ query }), signal: AbortSignal.timeout(180000),
});
const body = await response.text();
let result;
try { result = JSON.parse(body); } catch { result = { response: body }; }
const evidence = { observed_at: new Date().toISOString(), project_id: 'xpdoufauvrbdmxgngetv',
  input, query_sha256: crypto.createHash('sha256').update(query).digest('hex'),
  query_bytes: Buffer.byteLength(query), elapsed_ms: Math.round(performance.now() - start),
  http_status: response.status, boundary: 'synthetic rollback; not installed/native/load proof', result };
fs.writeFileSync(output, JSON.stringify(evidence, null, 2) + '\n');
if (!response.ok || /not ok \d/.test(body)) {
  console.error(JSON.stringify({ http_status: response.status, result })); process.exitCode = 1;
} else {
  const assertions = [...body.matchAll(/(?:ok|not ok) (\d+) -/g)].length;
  console.log(JSON.stringify({ output, assertions, query_sha256: evidence.query_sha256, elapsed_ms: evidence.elapsed_ms }));
}
