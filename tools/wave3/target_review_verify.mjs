import fs from 'node:fs';
import path from 'node:path';
import assert from 'node:assert/strict';
import { fileURLToPath } from 'node:url';
import { digest } from './prepare-target-verification.mjs';
import {sourceHash} from './strict-candidate-evidence.mjs';

// Read-only integrity gate for the recorded offline review. This gate does not
// mark outstanding product, installation, session, load or native tasks complete.
const repo = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../..');
const evidencePath = 'docs/verification/remaining-wave3/target-verification-preparation-20261002.json';
const read = name => fs.readFileSync(path.join(repo, name), 'utf8');
const reviewIndex = process.argv.indexOf('--review');
if (reviewIndex >= 0) {
  const currentPath = process.argv[reviewIndex + 1];
  assert.match(currentPath ?? '', /^docs\/verification\/remaining-wave3\/target-selection-preparation-review-2026100[345](?:-[a-z0-9]+)*\.json$/);
  const current = JSON.parse(read(currentPath).replace(/^\uFEFF/, ''));
  for (const key of ['database_calls','http_calls','persistent_migrations','fixture_installations','authentication_changes','native_launches']) assert.equal(current.execution[key], 0);
  for (const [key, expected] of Object.entries({tests:78,passed:78,failed:0,historical_cases:68,new_current_selection_cases:10})) assert.equal(current[key], expected);
  assert.equal(current.installed_target_verification, 'not_executed');
  assert.equal(current.native_acceptance, 'not_executed');
  assert.equal(current.owner_signoff, 'pending');
  for (const row of [current.actual_log, current.execution_start_capture]) {
    assert.ok(row?.file?.startsWith('docs/verification/remaining-wave3/'));
    assert.equal(sourceHash(path.join(repo, row.file)), row.sha256);
  }
  const capture = JSON.parse(read(current.execution_start_capture.file).replace(/^\uFEFF/, ''));
  assert.deepEqual(capture.source_sha256, current.source_sha256);
  assert.equal(Object.keys(current.source_sha256).length, current.source_files);
  for (const [name, expected] of Object.entries(current.source_sha256)) assert.equal(digest(read(name)), expected, 'Current offline review source drift: ' + name);
  for (const name of ['docs/blueprint/57_WAVE3_TARGET_VERIFICATION_CONTRACT.md','supabase/migrations/20261003090000_wave3_negative_stock_policy.sql','tools/wave3/strict-candidate-evidence.mjs','tools/wave3/target_review_verify.mjs','tools/wave3/target_review_selection_20261004.test.mjs']) assert.ok(current.source_sha256[name]);
  const log = read(current.actual_log.file);
  assert.match(log, /tests 78\b/);
  assert.match(log, /pass 78\b/);
  assert.match(log, /fail 0\b/);
  assert.doesNotMatch(log, /fail [1-9]\d*\b|ERR_ASSERTION|AssertionError|not ok \d/);
  assert.match(log, /executed_database_or_http_calls":0/);
  for (const [key, expected] of Object.entries({requires_explicit_candidate_count:46,complete_body_order_hashes:true,complete_artifact_bundle:true,actual_schema_matches_saved_raw_result:true,all_three_complete_tap_plans:true,legacy45_fallback_rejected:true})) assert.equal(current.current_selection_guards[key], expected);
  const order = JSON.parse(read('docs/verification/remaining-wave3/migration-order-final-20260930-45.json'));
  assert.equal(order.candidates.length, 45);
  for (const candidate of order.candidates) {
    assert.equal(candidate.installed, false);
    assert.equal(digest(read(candidate.path)), candidate.sha256);
    assert.equal(current.source_sha256[candidate.path], candidate.sha256);
  }
  const compatibility = JSON.parse(read('docs/verification/remaining-wave3/schema-compatibility-final-20260930.json'));
  assert.equal(compatibility.breaking_changes_count, 0);
  assert.equal(compatibility.potentially_breaking_count, 8);
  assert.equal(compatibility.overall_compatibility, 'potentially_incompatible');
  const plan = JSON.parse(read('.agent-harness/wave3-final-20261002-plan.json'));
  assert.equal(plan.goal_complete, false);
  for (const key of ['persistent_installation','authentication_changes','acceptance_executable']) assert.equal(plan.authorization[key], false);
  console.log(JSON.stringify({review_integrity:'passed',current_review:currentPath,actual_offline_checks:78,historical_candidates_source_matched:45,additional_policy_source_captured:true,
    compatibility:'Historical zero breaking; eight potential warnings retained for owner acceptance. Actual tail metadata remains separately verified.',executed_database_or_http_calls:0,
    boundary:'Current source-matched offline preparation guards only. Artificial46 fixtures are not observed schema or successful real46 suites. No installation, sessions/load, native acceptance or owner signoff.'}));
  process.exit(0);
}
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
