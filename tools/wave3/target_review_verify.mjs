import fs from 'node:fs';
import path from 'node:path';
import assert from 'node:assert/strict';
import { fileURLToPath } from 'node:url';
import { digest } from './prepare-target-verification.mjs';

// Read-only integrity gate for the recorded offline review. This gate does not
// mark outstanding product, installation, session, load or native tasks complete.
const repo = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../..');
const evidencePath = 'docs/verification/remaining-wave3/target-verification-preparation-20261002.json';
const read = name => fs.readFileSync(path.join(repo, name), 'utf8');
const evidence = JSON.parse(read(evidencePath));
assert.equal(evidence.review_date, '2026-10-02');
assert.equal(evidence.execution.database_calls, 0);
assert.equal(evidence.execution.http_calls, 0);
assert.equal(evidence.execution.persistent_migrations, 0);
assert.equal(evidence.execution.fixture_installations, 0);
assert.equal(evidence.execution.native_launches, 0);
assert.equal(evidence.offline_preparation.tests, 16);
assert.equal(evidence.offline_preparation.passed, 16);
assert.equal(evidence.offline_preparation.failed, 0);
assert.equal(evidence.offline_execution_guards.tests, 36);
assert.equal(evidence.offline_execution_guards.passed, 36);
assert.equal(evidence.offline_execution_guards.failed, 0);
assert.equal(evidence.offline_entity_aging.tests, 16);
assert.equal(evidence.offline_entity_aging.passed, 16);
assert.equal(evidence.offline_entity_aging.failed, 0);
assert.equal(evidence.offline_total.tests, 68);
assert.equal(evidence.offline_total.passed, 68);
assert.equal(evidence.offline_total.failed, 0);
assert.equal(evidence.installed_target_verification, 'not_executed');
assert.equal(evidence.native_acceptance, 'not_executed');
assert.equal(evidence.owner_signoff, 'pending');
for (const [name, expected] of Object.entries(evidence.source_sha256)) {
  assert.equal(digest(read(name)), expected, 'Review source drift: ' + name);
}
const order = JSON.parse(read('docs/verification/remaining-wave3/migration-order-final-20260930-45.json'));
assert.equal(order.candidates.length, 45);
for (const candidate of order.candidates) {
  assert.equal(candidate.installed, false, 'Historical candidate manifest must remain candidate-only');
  assert.equal(digest(read(candidate.path)), candidate.sha256, 'Candidate source drift: ' + candidate.path);
}
const compatibility = JSON.parse(read('docs/verification/remaining-wave3/schema-compatibility-final-20260930.json'));
assert.equal(compatibility.breaking_changes_count, 0);
assert.equal(compatibility.potentially_breaking_count, 8);
assert.equal(compatibility.overall_compatibility, 'potentially_incompatible');
const plan = JSON.parse(read('.agent-harness/wave3-final-20261002-plan.json'));
assert.ok(plan.tasks.find(t=>t.id==='T1').verification.some(c=>c.cmd?.includes('target_review_aging.test.mjs')));
assert.equal(plan.goal_complete, false);
assert.ok(plan.tasks.some(t => t.id === 'T2' && t.verification.some(c => c.kind === 'manual-evidence')));
assert.ok(plan.tasks.some(t => t.id === 'T3' && t.verification.every(c => c.kind === 'manual-evidence')));
assert.ok(plan.tasks.some(t => t.id === 'T4' && t.verification.every(c => c.kind === 'manual-evidence')));
assert.equal(plan.authorization.persistent_installation, false);
assert.equal(plan.authorization.authentication_changes, false);
assert.equal(plan.authorization.acceptance_executable, false);
console.log(JSON.stringify({review_integrity: 'passed', candidates_source_matched: 45,
  compatibility: 'zero breaking; eight potential warnings require owner acceptance',
  executed_database_or_http_calls: 0,
  boundary: 'Offline preparation review integrity only; remaining development, installed sessions/load, native acceptance and owner signoff stay open.'}));
