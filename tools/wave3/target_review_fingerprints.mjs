import fs from 'node:fs';
import path from 'node:path';
import crypto from 'node:crypto';
import { fileURLToPath } from 'node:url';

const repo = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../..');
const names = [
  'docs/blueprint/08_WAVE3_INTEGRATED_COMMERCE_FINANCE_SPEC.md',
  'docs/blueprint/47_WAVE3_CONTROL_READ_PLAN_CONTRACT.md',
  'docs/blueprint/57_WAVE3_TARGET_VERIFICATION_CONTRACT.md',
  'docs/verification/remaining-wave3/target-verification-preparation-20261002.md',
  'docs/verification/remaining-wave3/target-review-final2-20261002.log',
  'docs/verification/remaining-wave3/representative-plans-residual-20261002.sql',
  'docs/verification/remaining-wave3/representative-plans-residual-20261002.json',
  'docs/verification/remaining-wave3/migration-order-final-20260930-45.json',
  'docs/verification/remaining-wave3/schema-compatibility-final-20260930.json',
  'docs/verification/remaining-wave3/schema-after-45-20260930.json',
  'docs/verification/remaining-wave3/migration-review-and-runbook-20260930.md',
  '.agent-harness/wave3-final-20261002-plan.json',
  'tools/wave3/prepare-target-verification.mjs',
  'tools/wave3/target-verification-preparation.test.mjs',
  'tools/wave3/target_review_guards.mjs',
  'tools/wave3/target_review_guards.test.mjs',
  'tools/wave3/target_review_aging.mjs',
  'tools/wave3/target_review_aging.test.mjs',
  'tools/wave3/target_review_verify.mjs',
  'tools/wave3/target_review_candidate.mjs',
  'tools/wave3/target_review_fingerprints.mjs',
  'tools/wave3/run-target-fixture-generator.mjs',
  'tools/wave3/prepare-target-race-invariants.mjs',
  'tools/wave3/prepare-target-query-plans.mjs',
  'tools/wave3/run-reviewed-target-verification.mjs',
  'tools/wave3/run-independent-sessions.mjs',
  'tools/wave3/run-target-load.mjs',
  'tools/wave3/run-candidate.mjs',
  'supabase/tests/build_representative_read_plan_candidate.ps1',
  'supabase/tests/build_remaining_wave3_candidate.ps1',
  'supabase/tests/build_posted_journal_candidate.ps1',
  'supabase/tests/build_control_read_plan_candidate.ps1',
  'supabase/tests/build_control_candidate.ps1',
  'supabase/tests/build_journal_candidate.ps1',
];
const manifest = JSON.parse(fs.readFileSync(path.join(repo,
  'docs/verification/remaining-wave3/migration-order-final-20260930-45.json'), 'utf8'));
names.push(...manifest.candidates.map(candidate => candidate.path));
names.push(...fs.readdirSync(path.join(repo, 'supabase/tests'))
  .filter(name => /^wave3_.*\.sql$/.test(name))
  .map(name => 'supabase/tests/' + name));
const source_sha256 = Object.fromEntries([...new Set(names)].sort().map(name =>
  [name, crypto.createHash('sha256').update(fs.readFileSync(path.join(repo, name), 'utf8')).digest('hex')]));
console.log(JSON.stringify({ source_sha256 }));
