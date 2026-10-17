import fs from 'node:fs';
import crypto from 'node:crypto';
import { modelAuthCapacity } from './auth_capacity_model.mjs';
const folder = 'docs/verification/wave5/seven-area-completion-20261016/area6-load';
const sha = bytes => crypto.createHash('sha256').update(bytes).digest('hex');
const bind = path => { const bytes = fs.readFileSync(path); return { path, bytes: bytes.length, sha256: sha(bytes) }; };
const ids = ['FR-502','FR-508','NFR-503','NFR-504','NFR-505','NFR-506','AC-503','EC-514','NFR-552','AC-555','EC-557'];
const matrixPath = 'docs/verification/wave5/requirement-readiness-matrix-20261014-r5-a4.json';
const matrix = JSON.parse(fs.readFileSync(matrixPath, 'utf8'));
const historyPath = 'docs/verification/wave5/task3-completion-20261013/load-package-independent-final-review-20261014.json';
const historical = JSON.parse(fs.readFileSync(historyPath, 'utf8'));
const harnessPath = 'docs/verification/wave5/task3-acceptance-20261013/runtime-harness-review-20261014-acceptance-a1.json';
const harness = JSON.parse(fs.readFileSync(harnessPath, 'utf8'));
const publicTests = ['runtime_coordinator','supabase_provider','supabase_provider_plan','supabase_management_read','preparation_journal',
  'preparation_file_sink','supabase_provider_peer_20261013','provider_live_response_regression_20261013_r5',
  'membership_preparation_peer_20261013','preparation_journal_peer_20261013','preparation_file_sink_peer_20261013'].map(n => `tools/wave5/${n}.test.mjs`);
const driverTests = ['fixture_writer','provider_operation_wrapper','transport_helpers','readonly_credential_lifecycle']
  .map(n => `docs/verification/wave5/task3-load-release-20261013/${n}.test.mjs`);
const newTests = ['load_trace','cli_trace_binding'].map(n => `${folder}/${n}.test.mjs`);
const command = ['C:/Program Files/nodejs/node.exe','--test','--test-isolation=none','--test-reporter=tap','--test-timeout=5000',
  ...publicTests,...newTests,...driverTests];
function tap(name, expected) {
  const path = `${folder}/${name}`, text = fs.readFileSync(path, 'utf8');
  const counts = Object.fromEntries(['tests','pass','fail','cancelled','skipped','todo'].map(k => [k, Number(text.match(new RegExp(`^# ${k} (\\d+)$`, 'm'))?.[1])]));
  if (expected !== undefined && (counts.tests !== expected || counts.pass !== expected || counts.fail || counts.cancelled || counts.skipped || counts.todo)) throw Error('ACTUAL_CONTROLLED_RESULT_REQUIRED');
  return { log: bind(path), counts };
}
const notes = {
 'FR-502': 'Run the seven committed races, then extend exact retry/version/receipt/audit/outbox checks to every remaining authoritative command family; one forecast duplicate race alone does not close this universal criterion.',
 'FR-508': 'Exercise actual installed time/rows/groups/output/pages boundaries across every analytics surface; retain named rejection and zero partial totals, including genuine pagination permission loss.',
 'NFR-503': 'Verify actual default50/cap200 pages and exact 10000rows/100groups/366UTCdays/8MiB boundaries. Three over-limit fixture populations exceed or are absent from the existing reviewed preparation; do not fabricate evidence.',
 'NFR-504': 'Run the published 500-scope/2000 genuine-session 60s+300s protocol and independently audit actual dispatch trace, zero errors and strict P95 read<500ms/command<1500ms on a recorded reference environment.',
 'NFR-505': 'Identify/implement the allowed large analytics job path with durable scoped progress, <=1000rows/committed chunk, failure/cancellation/resume and source authorization; the reviewed load provider contains no implementation or live demonstration of that job lifecycle. Measure bounded analytics P95<3000ms.',
 'NFR-506': 'Run all seven genuine independent overlapping committed races (100duplicates,2seats,2admissions,2activation,2execution,2leases,20quota); preserve winner/loser effects and no overshoot. Controlled barriers are preparation only.',
 'AC-503': 'Combine installed exact-boundary rejection/zero-effect evidence, allowed resumable job evidence and the actual reference-workload latency report; these are three distinct unclosed dependencies.',
 'EC-514': 'Inject bounded job crash, cancellation and unavailable worker failures in an isolated reviewed fixture; verify named state, no partial totals, durable progress and safe resume without replaying uncertain effects.',
 'NFR-552': 'Exercise exact and over-limit process snapshot time/rows/groups/output/page boundaries through the installed adapter, with zero partial totals and no hidden truncation.',
 'AC-555': 'Prove actual paginated source completeness, duplicate identity rejection and allowed/excess source/group/time/output boundaries; fresh controlled arithmetic is narrower than installed pagination evidence.',
 'EC-557': 'Run real pagination permission loss/retrieval-cap cases plus malformed UTC/inverted windows/oversized serialized output, and verify all-or-nothing failure with protected aggregates cleared.'
};
const report = {
 kind: 'wave5-area6-load-controlled-completion-report', publishedAt: new Date().toISOString(), projectId: 'xpdoufauvrbdmxgngetv',
 scope: { assignedIds: ids, rows: 11, newAcceptedRows: 0, acceptedRows: 0, openRows: 11 },
 baseline: { installedMigrations: 115, apiFunctions: 363, cumulativeManagementAttempts: 137, authorityWindowsExpired: 2,
   jobsPaused: 3, provenance: 'Root-coordinated Oct16 observation; this child made no new live or private request.' },
 skillsApplied: ['engineering-advanced-skills:performance-profiler','engineering-advanced-skills:chaos-engineering','supabase'],
 actual: { liveSqlCalls: 0, networkCalls: 0, privateDatabaseInputsRead: false, genuineSessionsCreated: 0, sdkJobs: 0,
   fullTargetLoad: 'NOT_RUN', sevenRaceProtocolExecuted: false, productionReleased: false, ownerAcceptance: false },
 changes: [
   { defect: 'checkLoadResult trusted reported measured session/scope coverage and P95 summaries instead of deriving them from actual samples.',
     repair: 'Mandatory integrated trace validation recomputes coverage, actual strict P95, sample hash, exact scheduled slots/classes, operation/actor restrictions, stable independent session/connection identity, monotonic transport/elapsed times, actual dispatch lag and minimum actual transport peak.' },
   { defect: 'A new imported validator would otherwise be optional in the CLI source-bound harness review.',
     repair: 'The existing CLI now requires the exact new trace module as a mandatory reviewed source binding before any private module can load.' }
 ],
 verification: { before: tap('before-trace-regressions.tap'), firstConsumers: tap('after-trace-and-consumers.tap',105),
   sandboxAttempt: { ...tap('complete-consumer-verification.tap'), failure: 'One existing temporary Windows junction creation failed with sandbox EPERM. No assertion failure in the new trace controls.',
     resolution: 'Automatic approval allowed the exact controlled suite outside the sandbox; no source/test weakening or skip.' },
   finalNewRegressions: tap('final-new-regressions.tap',16), finalCompleteConsumers: { ...tap('final-complete-consumer-verification.tap',199), exitCode: 0, command },
   authCapacityArithmetic: { ...tap('auth-capacity-controlled.tap',5), exitCode: 0 },
   distinctPassingTests: 204, countsAreControlledOnly: true,
   independentSourceReview: 'Area7 reviewed initial trace fix and requested connection/peak/lag hardening; final source binding review requested separately.' },
 authCapacity: { savedSettingsAreHistorical: true, oneGenuineSource: modelAuthCapacity(),
   twoGenuineSourcesWithVerificationTail: modelAuthCapacity({ sourceGroups: 2, verificationTailSeconds: 300 }),
   arrangement: 'A candidate is two genuinely separate owner-controlled source hosts, each provisioning 1000 legitimate Auth sessions at the existing policy. Do not spoof forwarding IPs, copy token IDs, manufacture JWTs or change global policy.',
   remainingProof: 'Verify the deployed limiter actually permits independent source budgets and no shared lower cap; legitimate source infrastructure/permission, real MFA, actual session persistence, 2000 online Auth+committed session row checks within300s, >=900s remaining lifetime, exact distribution and generator/reference capacity. GET/user verification quota is unresolved. The model is necessary arithmetic, not a working arrangement.' },
 rows: ids.map(id => { const row = matrix.currentRows.find(r => r.id === id); if (!row?.fullStatement || !row.statementSha256) throw Error('FULL_CRITERION_REQUIRED');
   return { id, fullStatement: row.fullStatement, statementSha256: row.statementSha256, decision: 'open_missing_evidence', accepted: false, nextEvidence: notes[id] }; }),
 historicReview: { binding: bind(historyPath), originalUnchanged: true, currentApproval: false,
   limitation: 'The old 18-source harness and load package reviews remain historical. Coordinator/CLI changed and imported trace module is new; execution requires a separate successor source review and concrete private/live prerequisites.' },
 evidenceCapturedAfterRun: true,
 sourceBindings: [...new Set([...harness.files,...harness.contractSources].map(r => r.path).concat([
   'tools/wave5/runtime_load_trace_20261017_r5.mjs',...publicTests,...driverTests,...newTests,
   `${folder}/auth_capacity_model.mjs`,`${folder}/auth_capacity_model.test.mjs`,`${folder}/finalize_report.mjs`]))].map(bind),
 preservedBeforeSource: bind(`${folder}/runtime_coordinator-before-trace-validation.mjs`),
 historicalSourceInputs: [bind(matrixPath),bind(harnessPath),bind('docs/verification/wave5/task3-load-release-20261013/protocol-result-a2.json')],
 acceptanceRecommendation: 'Keep all eleven rows open. Authoritative execution, full installed limits, genuine target-scale load and allowed resumable jobs need their own evidence. No controlled test count closes those gates.'
};
const target = `${folder}/completion-report.json`;
fs.writeFileSync(target, JSON.stringify(report,null,2)+'\n', { flag: 'wx' });
const md = `# Area 6: load, limits and recovery\n\nThe local implementation work repaired a false-pass load gate. It previously accepted nine manipulated traces while retaining plausible summary fields. The integrated validator now derives coverage, P95 and dispatch invariants from the actual trace. CLI review must bind the new module.\n\n**204 distinct controlled tests passed**: 199 combined coordinator/provider/preparation/reader-writer/integration checks, including16 new trace/CLI controls, and5 separate capacity arithmetic tests. The original one-pass/nine-failure regression record and a later sandbox junction failure are preserved; the final full suite passed without skips outside the sandbox. No network, live PostgreSQL, genuine session provisioning, private input or SDK operation was performed.\n\n**All11 assigned requirements remain open. Full target load: NOT_RUN.** The existing 500-scope/2000-session protocol and seven committed race definitions are retained. The former source-bound reviews are historical after this change and need a successor independent source review before execution.\n\nThe saved Auth settings imply3940s optimistic one-source issuance versus2700s freshness allowance. Two genuine source hosts give an optimistic1940s bound; reserving300s final verification leaves2400s issuance. This arithmetic does not prove deployed per-source independence, verification throughput, MFA, infrastructure or a working cohort. Do not fabricate IPs/tokens or change global Auth policy.\n\n| Row | Work still required |\n|---|---|\n${report.rows.map(r => `| ${r.id} | ${r.nextEvidence} |`).join('\n')}\n\nThe root's frozen actual call count is137;115 migrations/363 API functions, both old authority windows expired and3 jobs paused are coordination inputs. This child did not refresh or change them.\n\nSee [completion-report.json](completion-report.json) for full statements, source/test hashes, preserved failures, exact commands and evidence boundaries.\n`;
fs.writeFileSync(`${folder}/README.md`,md,{flag:'wx'});
console.log(JSON.stringify({ report: bind(target), summary: bind(`${folder}/README.md`), sourceBindings: report.sourceBindings.length, tests: report.verification.distinctPassingTests, openRows:11 }));
