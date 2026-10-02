import fs from 'node:fs';
import path from 'node:path';
import crypto from 'node:crypto';
import assert from 'node:assert/strict';
import { fileURLToPath } from 'node:url';

// Read-only transport of a generated, source-reviewed synthetic rollback query.
// This helper neither contacts a database nor executes SQL.
const repo = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../..');
const source = 'docs/verification/remaining-wave3/representative-plans-residual-20261002.sql';
const query = fs.readFileSync(path.join(repo, source), 'utf8').replace(/^\uFEFF/, '');
assert.match(query, /^\s*begin\s*;/i);
assert.match(query, /finish\(true\)/);
assert.match(query, /rollback\s*;\s*$/i);
assert.doesNotMatch(query, /(?:^|\n)\s*commit\s*;/i);
if (process.argv[2] === '--read') {
  const offset = Number(process.argv[3]);
  const size = Number(process.argv[4] ?? 45000);
  assert.ok(Number.isSafeInteger(offset) && offset >= 0);
  assert.ok(Number.isSafeInteger(size) && size > 0 && size <= 45000);
  process.stdout.write(JSON.stringify({ offset, text: query.slice(offset, offset + size) }));
} else {
  console.log(JSON.stringify({ source, length: query.length,
    sha256: crypto.createHash('sha256').update(query).digest('hex'),
    strict_finish: true, final_rollback: true,
    boundary: 'Read-only query transport; no database or HTTP execution.' }));
}
