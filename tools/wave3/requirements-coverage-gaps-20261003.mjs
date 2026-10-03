import fs from 'node:fs';
import path from 'node:path';
import crypto from 'node:crypto';
const root = 'docs/verification/remaining-wave3/';
const read = file => JSON.parse(fs.readFileSync(file, 'utf8'));
const current = read(root + 'requirements-coverage-source-checked-20261003.json');
const hash = file => crypto.createHash('sha256').update(fs.readFileSync(file)).digest('hex');
const lines = new Map();
for (const entry of current.checked_inputs) {
  const capture = new Map(read(entry.source_fingerprint).files.map(row => [row.file, row.sha256]));
  for (const record of fs.readFileSync(entry.file, 'utf8').split('end_of_record')) {
    const raw = record.match(/^SF:([^\r\n]+)/m)?.[1];
    if (!raw) continue;
    const file = path.relative(process.cwd(), path.isAbsolute(raw) ? raw : path.resolve(entry.base, raw)).replaceAll('\\', '/');
    if (!fs.existsSync(file) || capture.get(file) !== hash(file)) continue;
    const measured = lines.get(file) ?? new Map();
    for (const match of record.matchAll(/^DA:(\d+),(\d+)/gm)) measured.set(+match[1], (measured.get(+match[1]) ?? false) || +match[2] > 0);
    lines.set(file, measured);
  }
}
const ranked = current.files.filter(row => row.changed && row.measured).sort((a, b) => (b.lines - b.lines_hit) - (a.lines - a.lines_hit)).slice(0, 30).map(row => {
  const source = fs.readFileSync(row.file, 'utf8').split(/\r?\n/);
  const missing = [...(lines.get(row.file) ?? [])].filter(([, hit]) => !hit).map(([line]) => line).sort((a, b) => a - b);
  return {file: row.file, sha256: hash(row.file), executable_lines: row.lines, lines_hit: row.lines_hit, missing_lines: row.lines - row.lines_hit,
    missed_current_source_lines: missing.map(line => ({line, source: source[line - 1]?.trim()}))};
});
const out = {observed_at: new Date().toISOString(), raw_report: {file: root + 'requirements-coverage-source-checked-20261003.json', sha256: hash(root + 'requirements-coverage-source-checked-20261003.json')},
  boundary: 'Development diagnosis from current hash-matching executed coverage only. Recently edited whole-workspace sources need their final full run before choosing additional tests. No coverage denominator, selected scope, tests or gates are changed.',
  top_missing_executable: ranked, currently_unmeasured: current.changed_dart.unmeasured_executable};
fs.writeFileSync(root + 'requirements-coverage-gaps-20261003.json', JSON.stringify(out, null, 2) + '\n');
console.log(JSON.stringify({top_missing: ranked.slice(0, 12).map(row => ({file: row.file, missing: row.missing_lines})), unmeasured: out.currently_unmeasured}));
