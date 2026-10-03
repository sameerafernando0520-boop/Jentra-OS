import fs from 'node:fs';
import crypto from 'node:crypto';
const file = 'build/remaining-wave3/desktop-full-20261003.log';
const text = fs.readFileSync(file, 'utf8');
const failures = [];
for (const match of text.matchAll(/^.*?\+(\d+) -(\d+): (C:\/.*?\.dart): (.*?) \[E\]\r?$/gm)) {
  const before = text.slice(0, match.index);
  const marker = before.lastIndexOf('══╡ EXCEPTION CAUGHT BY FLUTTER TEST FRAMEWORK');
  const after = text.slice(match.index + match[0].length).split(/^\d{2}:\d{2} [+-]/m)[0];
  // Plain Dart test failures follow the [E] line and have no Flutter exception
  // banner. Do not borrow an earlier concurrent widget's golden exception.
  const plainFailure = /^\s*(?:Expected:|Null check operator|Bad state:)/.test(after);
  const block = plainFailure ? after.trim() : before.slice(marker);
  if (!plainFailure && !block.includes(match[3].split('/').at(-1))) throw Error('Exception belongs to a different test file: ' + match[3]);
  const goldens = [...block.matchAll(/Golden "([^"]+)": Pixel test\s+failed/g)].map(row => row[1]);
  failures.push({file: match[3], test: match[4], failed_counter: +match[2],
    category: goldens.length ? 'pixel_golden' : 'non_pixel_failure', goldens,
    exception_excerpt: block.split(/\r?\n/).slice(0, 14).join('\n')});
}
if (failures.length !== 90 || failures.at(-1).failed_counter !== 90) throw Error('Full-suite failure count changed');
const out = {generated_at: new Date().toISOString(), executed_log: {file, sha256: crypto.createHash('sha256').update(text).digest('hex')},
  execution_source_capture: 'docs/verification/remaining-wave3/client-sources-full-desktop-20261003.json',
  boundary: 'Classifies the executed Oct3 full log. Pixel failures remain open visual evidence; this does not claim their bytes equal historical goldens. Non-pixel failures require separate diagnosis and current regression. This log preceded the final dialog corrections.',
  passed: 1372, failed: failures.length,
  pixel_golden: failures.filter(row => row.category === 'pixel_golden').length,
  non_pixel_failure: failures.filter(row => row.category === 'non_pixel_failure').length,
  failures};
const independentFile = 'docs/verification/remaining-wave3/full-failure-classification-20261003.json';
if (fs.existsSync(independentFile)) {
  const independent = JSON.parse(fs.readFileSync(independentFile, 'utf8'));
  const expected = new Map(independent.failures.map(row => [row.file + ':' + row.case, row.category === 'golden']));
  for (const row of failures) {
    if (expected.get(row.file.split('/').at(-1) + ':' + row.test) !== (row.category === 'pixel_golden')) throw Error('Independent category disagreement: ' + row.test);
  }
  out.independent_classification_matches = true;
}
fs.writeFileSync('docs/verification/remaining-wave3/requirements-full-failure-review-20261003.json', JSON.stringify(out, null, 2) + '\n');
console.log(JSON.stringify({...out, failures: failures.filter(row => row.category !== 'pixel_golden')}, null, 2));
