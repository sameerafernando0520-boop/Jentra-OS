import fs from 'node:fs';
import crypto from 'node:crypto';
import assert from 'node:assert/strict';

export function declarationsOnly(source) {
  const stripped = source.replace(/\/\*[\s\S]*?\*\//g, '').replace(/\/\/[^\n]*/g, '')
    .replace(/^\s*(?:library|import|export)\b[^;]*;/gm, '').trim();
  const match = stripped.match(/^abstract interface class \w+\s*\{([\s\S]*)\}$/);
  if (!match) return false;
  const members = match[1].trim().split(';');
  if (members.pop().trim() !== '') return false;
  return members.length > 0 && members.every(member => {
    // Exact tested interface syntax: generic return type and method signature;
    // named parameter braces are allowed only inside the argument list.
    const signature = member.trim().match(/^[\w<>?, ]+\s+\w+\s*\(([^()]*)\)$/);
    if (!signature) return false;
    const params = signature[1].trim();
    if (/\b(?:return|throw|async|await|yield|new|factory|static|const|final|var)\b|=>/.test(params)) return false;
    if (/[{}]/.test(params) && !/^\{[^{}]*\}$/.test(params)) return false;
    return params.replace(/[{}]/g, '').split(',').filter(part => part.trim())
      .every(part => /^\s*(?:required\s+)?[\w<>?]+\s+\w+(?:\s*=\s*\d+)?\s*$/.test(part));
  });
}

if (process.argv.includes('--self-test')) {
  for (const sample of [
    'abstract interface class A { Future<List<B>> page({required C context, int limit = 50,}); }',
    "import 'a.dart';\nabstract interface class A { Future<B?> get(C context); }",
  ]) assert.equal(declarationsOnly(sample), true);
  for (const sample of [
    'abstract interface class A { Future<B> get(C context) { return fetch(); } }',
    'abstract interface class A { Future<B> get(C context) => fetch(); }',
    'abstract interface class A { final a = 50; }',
    'abstract interface class A { static int get() => 5; }',
    'class A { Future<B> get(C context); }',
    'abstract interface class A { factory A() = B; }',
    'abstract interface class A { Future<B> get({int limit = fetch()}); }',
  ]) assert.equal(declarationsOnly(sample), false);
  console.log('Declaration diagnostic self-test passed:2 declaration signatures,7 executable or unsupported declarations rejected');
} else {
  const files = ['packages/jentra_domain/lib/src/crm_repository.dart', 'packages/jentra_domain/lib/src/lead_to_cash_repository.dart'];
  const hash = file => crypto.createHash('sha256').update(fs.readFileSync(file)).digest('hex');
  const rows = files.map(file => ({file, sha256: hash(file), declarations_only: declarationsOnly(fs.readFileSync(file, 'utf8'))}));
  if (rows.some(row => !row.declarations_only)) throw Error('Reviewed interface gained executable or unsupported source');
  const out = {observed_at: new Date().toISOString(),
    boundary: 'Diagnostic only. No selected path, coverage threshold, locked summarizer or gate is changed. Exact source consists of abstract method declarations, including named parameter braces and an integer default. Compilation evidence belongs to its separately source-matched Flutter suite; this parser is not a compiler.',
    locked_classifier_problem: 'Its [^{}=]* expression rejects named parameter braces/default values as if they were implementation bodies.',
    executable_lines_in_these_two_files: 0, rows};
  fs.writeFileSync('docs/verification/remaining-wave3/requirements-declaration-diagnostic-20261003.json', JSON.stringify(out, null, 2) + '\n');
  console.log(JSON.stringify(out));
}
