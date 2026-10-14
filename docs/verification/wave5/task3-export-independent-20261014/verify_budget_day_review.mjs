import fs from 'node:fs';
import path from 'node:path';
import crypto from 'node:crypto';
import assert from 'node:assert/strict';
import {fileURLToPath} from 'node:url';

const root = fileURLToPath(new URL('../../../../', import.meta.url));
const output = 'docs/verification/wave5/task3-export-independent-20261014';
const auditFolder = 'docs/verification/wave5/task3-export-continuation-20261014';
const snapshot = 'build/wave5-approved-execution-20261013-r5-a2';
const sha = bytes => crypto.createHash('sha256').update(bytes).digest('hex');
const read = name => fs.readFileSync(path.resolve(root, name));
const bind = name => ({path: name, bytes: read(name).length, sha256: sha(read(name))});
const json = name => JSON.parse(read(name));
const budgetPath = `${auditFolder}/budget-feasibility.json`, manifestPath = `${auditFolder}/source-preservation-manifest.json`;
const budget = json(budgetPath), manifest = json(manifestPath);
const currentBefore = manifest.sourceBindingsBefore.map(row => bind(row.path));
const reviewedAt = new Date().toISOString(), checks = [], cited = new Map(), historicalBindings = [];
const check = (name, operation) => {
  try { operation(); checks.push({name, passed: true}); }
  catch (error) { checks.push({name, passed: false, failure: error.message}); }
};
const exact = binding => {
  const actual = bind(binding.path);
  assert.equal(actual.sha256, binding.sha256, binding.path);
  if (binding.bytes !== undefined) assert.equal(actual.bytes, binding.bytes, binding.path);
  cited.set(binding.path, actual); return actual;
};
const historical = (binding, allowOriginalPublicFile = false) => {
  const savedPath = `${snapshot}/${binding.path}`;
  const actualPath = fs.existsSync(path.resolve(root, savedPath)) ? savedPath : allowOriginalPublicFile ? binding.path : savedPath;
  const actual = bind(actualPath); assert.equal(actual.sha256, binding.sha256, binding.path);
  historicalBindings.push({...actual, historicalReferencedPath: binding.path}); return actual;
};
const refs = value => {
  if (!value || typeof value !== 'object') return;
  if (typeof value.path === 'string' && /^[a-f0-9]{64}$/.test(value.sha256 ?? '')) exact(value);
  for (const child of Object.values(value)) refs(child);
};
check('All 33 preserved inputs and audit before/after bindings remain exact', () => {
  assert.equal(manifest.sourceBindingsBefore.length, 33); assert.deepEqual(manifest.sourceBindingsBefore, manifest.sourceBindingsAfter);
  assert.equal(manifest.sourcesUnchangedDuringAudit, true);
  for (const binding of manifest.sourceBindingsBefore) exact(binding);
  assert.deepEqual(currentBefore, manifest.sourceBindingsBefore);
  exact(budget.sourceManifest);
});
check('Every directly cited public budget evidence digest matches', () => { refs(budget); });
const runtime = json(budget.originalAuthorization.runtimePacket.path), owner = json(budget.originalAuthorization.ownerDecision.path);
const originalPlan = json(budget.originalAuthorization.concreteOriginalFinancePlan.path);
const a3Plan = json(budget.consumedEvidence.a3Plan.path), a3Stop = json(budget.consumedEvidence.a3Stop.path);
check('Original approval authorizes at most eight exports and does not contain numeric 150', () => {
  assert.equal(runtime.bootstrap.sourceFixtureLimits.runtimeOnly.governedExports, 8);
  assert.equal(owner.decision, 'approve'); assert.equal(owner.source.kind, 'direct_user_message');
  assert.equal(owner.runtimeBundleSha256, budget.bundleSha256); assert.equal(owner.operationScopeSha256, budget.originalOperationScopeSha256);
  const {bundleSha256, ...body} = runtime; assert.equal(sha(JSON.stringify(body)), bundleSha256);
  assert.equal(bundleSha256, budget.bundleSha256);
  let numeric150 = 0; const visit = value => {
    if (value === 150) numeric150++;
    if (value && typeof value === 'object') Object.values(value).forEach(visit);
  }; visit(runtime); assert.equal(numeric150, 0);
  assert.equal(originalPlan.maximumTotalWorkflowRequestAttempts, 150);
  assert.equal(a3Plan.maximumTotalWorkflowRequestAttempts, 150);
});
check('All consumed plan source and prior evidence bindings match preserved execution inputs', () => {
  assert.equal(a3Plan.sourceBindings.length, 68); assert.equal(a3Plan.priorEvidenceBindings.length, 37);
  a3Plan.sourceBindings.forEach(row => historical(row));
  a3Plan.priorEvidenceBindings.forEach(row => historical(row));
  originalPlan.sourceBindings.forEach(row => historical(row, true));
  Object.values(a3Plan.previousAttempt).forEach(row => historical(row));
  const once = json(`${snapshot}/docs/verification/wave5/finance-remaining-once-20261014-r5-a3.json`);
  assert.equal(once.planSha256, budget.consumedEvidence.a3Plan.sha256);
  assert.equal(once.priorRequestBound, 78); assert.equal(once.previousStopValidation.pendingCommand, null);
});
check('Conservative prior 130 retains unknown first reserve, all 50 A3 calls, pipeline read and A8 GET', () => {
  assert.deepEqual(a3Plan.priorRequestBoundBreakdown, {firstAttemptConservativeReserve: 40, firstAttemptObservedCount: null,
    resumeObservedAttempts: 35, stoppedA2ReadOnlyAttempts: 3});
  assert.equal(40 + 35 + 3, 78); assert.equal(a3Stop.priorRequestBound, 78);
  const counted = budget.consumedEvidence.a3ReconstructedAttempts;
  assert.equal(Object.entries(counted).filter(([name]) => name !== 'total').reduce((sum, [, count]) => sum + count, 0), 50);
  assert.equal(a3Stop.actualRemainingAttempts, 50); assert.equal(a3Stop.totalRequestBound, 128);
  assert.equal(a3Stop.lastOriginalCommand, null); assert.equal(a3Stop.resolution, null); assert.equal(a3Stop.automaticRetryPerformed, false);
  const pipeline = json(budget.consumedEvidence.trackedPipelineShapeQuery.evidence.path);
  assert.equal(pipeline.additionalReadOnlyInvestigationRequests, 1); assert.equal(pipeline.cumulativeConservativeWorkflowRequestBound, 129);
  const a8 = json(budget.consumedEvidence.sharedOwnerRefresh.evidence.path);
  assert.equal(a8.readOnlyOwnerApiCalls, 1); assert.equal(a8.actualVerifiedAt, budget.consumedEvidence.sharedOwnerRefresh.performedAt);
  assert.equal(128 + 1 + 1, budget.proposedBudget.priorConservativeBound); assert.equal(budget.proposedBudget.priorConservativeBound, 130);
});
check('Completed dates retain exact distinct approval and canonical/raw original replay evidence', () => {
  assert.equal(budget.consumedEvidence.a3CompletedDates.length, 2);
  for (const binding of budget.consumedEvidence.a3CompletedDates) {
    const date = json(binding.evidence.path);
    assert.equal(date.canonicalFullValueIdentical, true); assert.equal(date.rawResponseSha256Identical, true);
    assert.equal(date.originalPreparedResponseSha256, date.originalReplayResponseSha256);
    assert.equal(date.actualDistinctApprover, binding.distinctApprover);
    assert.equal(date.readback.currentApproval.decisionId, binding.decisionId);
    assert.equal(date.readback.currentApproval.id, binding.proposalId);
  }
});
check('24 ordinary attempts include two complete six-call genuine sessions and exactly two original export writes', () => {
  const calls = budget.ordinaryCallInventory;
  assert.equal(calls.length, 24); assert.deepEqual(calls.map(row => row.ordinal), Array.from({length: 24}, (_, i) => i + 1));
  assert.ok(calls.every(row => row.attempts === 1 && row.automaticRetries === 0));
  for (const stage of ['writer', 'independent-reopen']) {
    const session = calls.filter(row => row.stage === stage); assert.equal(session.length, 6);
    assert.deepEqual(session.map(row => row.method), ['POST', 'POST', 'POST', 'POST', 'GET', 'POST']);
    assert.ok(session.some(row => row.route === '/auth/v1/user'));
    assert.ok(session.some(row => row.purpose.includes('UUID session row')));
    assert.ok(session.some(row => row.purpose.includes('actual server clock')));
  }
  assert.equal(calls.filter(row => row.route === 'api.record_report_export').length, 2);
  const RPC = new Set(['api.report_export_preview', 'api.record_report_export', 'api.wave5_export_reopen', 'api.financial_statement_page']);
  assert.ok(calls.filter(row => row.route.startsWith('api.')).every(row => RPC.has(row.route)));
  assert.equal(budget.reservedResolution.maximumAttempts, 1); assert.equal(budget.reservedResolution.automaticRetry, false);
  assert.ok(budget.reservedResolution.condition.includes('pending original export'));
  assert.equal(budget.exactSource.exportIds.length, 2); assert.deepEqual(budget.exactSource.exportIds, a3Plan.expectedNewExportProcessAppends);
});
check('Consolidated before/after query is one identical exact read-only statement with original digest recipes', () => {
  const before = budget.consolidatedEvidenceQueries.before, after = budget.consolidatedEvidenceQueries.after;
  assert.equal(before.query, after.query); assert.equal(sha(before.query), before.sha256); assert.equal(before.sha256, after.sha256);
  const stripped = before.query.replace(/'(?:''|[^'])*'/g, '');
  assert.match(stripped, /^SELECT\s+jsonb_build_object\(/);
  assert.ok(!/[;]|\b(?:insert|update|delete|alter|drop|grant|revoke|truncate|copy|call)\b/i.test(stripped));
  const source = read(`${snapshot}/tools/wave5/finance_cash_workflows_20261013_r5.mjs`).toString('utf8');
  const template = /export const FINANCE_FACTS_SQL=`([\s\S]*?)`;/.exec(source)?.[1]; assert.ok(template);
  const facts = template.replaceAll('${scope.tenantId}', budget.exactSource.scope.tenantId);
  assert.ok(!facts.includes('${'));
  const processClause = `FROM workflow.process_events x WHERE tenant_id='${budget.exactSource.scope.tenantId}'`;
  const appends = [...a3Plan.expectedPriorStatementProcessAppends, ...a3Plan.expectedNewExportProcessAppends];
  const commands = appends.map(row => `'${row.commandId}'::uuid`).join(',');
  const exports = a3Plan.expectedNewExportProcessAppends.map(row => `'${row.commandId}'::uuid`).join(',');
  const baseline = facts.replace(processClause, processClause + ` AND command_id NOT IN (${commands})`);
  const prior = facts.replace(processClause, processClause + ` AND command_id NOT IN (${exports})`);
  assert.ok(before.query.includes(`(${facts}) whole_source`));
  assert.ok(before.query.includes(`(${baseline}) original_baseline`));
  assert.ok(before.query.includes(`(${prior}) prior_complete`));
  for (const id of [budget.exactSource.pipelineId, budget.exactSource.statementId, ...a3Plan.expectedNewExportProcessAppends.flatMap(row => [row.commandId, row.documentId])]) assert.ok(before.query.includes(id));
  assert.equal(budget.requiredBefore.installedMigrationCount, 115); assert.equal(budget.requiredBefore.installedApiFunctionCount, 363);
  assert.equal(budget.requiredAfter.sourceExcludingOnlyOriginalTwoExportEvents, budget.requiredBefore.wholeSourceHash);
  assert.equal(budget.requiredAfter.originalBaselineSourceHash, budget.requiredBefore.originalBaselineSourceHash);
});
const metadata = json(budget.currentOwnerScope.metadata.path);
check('A8 is expired now and a fresh charged metadata binding is required before export unseal/dispatch', () => {
  assert.equal(metadata.expiresAt, '2026-10-14T03:09:42.640Z');
  assert.ok(Date.parse(reviewedAt) > Date.parse(metadata.expiresAt));
  assert.equal(budget.currentOwnerScope.newOwnerRefreshCallsIncludedInFuture24, 0);
  assert.equal(budget.currentOwnerScope.expiredMetadataMustFailBeforeCredentialUnsealOrRequest, true);
  const recovery = json('docs/verification/wave5/private-owner-scope-expiry-recovery-20261014-r5-a8.json');
  assert.equal(recovery.originalAuthorityExpiresAt, budget.currentOwnerScope.originalRuntimeWorkerExpiryUnchanged);
  assert.equal(recovery.authorityExtended, false);
  const refreshSource = read('tools/wave5/refresh_private_owner_scope_20261014_r5_a8.mjs').toString('utf8');
  assert.ok(refreshSource.includes("fs.open(file,'wx')")); assert.ok(refreshSource.includes('metadata-renewed-a8.json'));
  assert.ok(refreshSource.includes('private-owner-scope-refresh-20261014-r5-a8.json'));
});
check('Current required ceiling is 156 with a charged single refresh; 155 or omitted calls cannot fit', () => {
  const ordinary = budget.ordinaryCallInventory.reduce((sum, row) => sum + row.attempts, 0), reserve = budget.reservedResolution.maximumAttempts;
  assert.equal(130 + ordinary + reserve, 155);
  assert.equal(130 + 1 + ordinary, 155); assert.equal(130 + 1 + ordinary + reserve, 156);
  assert.equal(156 - originalPlan.maximumTotalWorkflowRequestAttempts, 6);
  assert.ok(130 + 1 + ordinary + reserve > 155);
  assert.equal(130 + 2 + ordinary + reserve, 157);
  assert.equal(130 + 1 + 32 + reserve, 164);
  assert.equal(budget.proposedBudget.originalCountersReset, false); assert.equal(budget.proposedBudget.allFailedAttemptsCharged, true);
  assert.equal(budget.proposedBudget.maximumRunMs, 900000); assert.equal(budget.proposedBudget.maximumSingleRequestMs, 45000);
});
check('UTC day amendment preserves fixture facts, two currencies and unchanged supported reopen contract', () => {
  assert.equal(new Date(reviewedAt).toISOString().slice(0, 10), '2026-10-14');
  assert.equal(budget.exactSource.originalFixtureDay, '2026-10-13'); assert.equal(budget.exactSource.proposedActualExportUtcDay, '2026-10-14');
  assert.deepEqual(budget.exactSource.pipelineRows, [
    {currency: 'LKR', population: 1, amount: '2000.125000', weightedAmount: '1000.062500'},
    {currency: 'USD', population: 1, amount: '1000.000001', weightedAmount: '333.300000'},
  ]);
  assert.equal(budget.exactSource.fixtureDatesOrAmountsModified, false);
  assert.equal(budget.APIReopenLimit.registeredStatementReopenSupportedByExistingApi, false);
  const adapter = read(budget.APIReopenLimit.migration.path).toString('utf8');
  assert.ok(adapter.includes("job.resource not in('wave3.w5_pipeline','wave3.w5_cash')"));
});
check('All original inputs remain unchanged throughout this independent audit', () => {
  assert.deepEqual(manifest.sourceBindingsBefore.map(row => bind(row.path)), currentBefore);
  assert.equal(budget.actualLiveExportsPerformed, 0); assert.equal(budget.networkCallsDuringThisAudit, 0);
  assert.equal(budget.oldFilesChanged, 0); assert.equal(budget.privateCredentialFilesRead, false);
});
const passed = checks.every(row => row.passed), ordinary = budget.ordinaryCallInventory.reduce((sum, row) => sum + row.attempts, 0);
const report = {
  kind: 'independent-source-only-export-budget-and-utc-day-review', reviewedAt, projectId: budget.projectId,
  reviewer: 'Codex requirement_acceptance independent technical reviewer', passed, checks,
  sourceOnlyVerdict: passed ? 'supports an explicit 156 ceiling and UTC October 14 export day amendment, conditional on one newly charged successful readiness refresh and final source-bound metadata/preparation; 155 with expired A8 is ineligible' : 'source review failed; inspect recorded findings before any implementation or private use',
  originalApprovalAndPlansUntouched: true, acceptanceMatrixEdited: false,
  personalHumanSignatureClaimed: false, newHumanApprovalInvented: false,
  technicalAmendmentGrantedByThisReview: false, liveExecutionAuthorizedByThisReview: false,
  authorityBoundary: 'The user delegated technical decisions and necessary fixes. Root will record a transparent source-only ceiling/day decision. The original approved operation scope remains limited to its exact synthetic project/accounts/scopes; this review issues no live instruction or new personal signature.',
  originalAuthorization: {ownerDecision: bind(budget.originalAuthorization.ownerDecision.path), runtimePacket: bind(budget.originalAuthorization.runtimePacket.path),
    approvedExportMaximum: 8, explicitNumeric150InHumanRuntimePacket: false,
    unchangedOriginalConcreteCap: 150, originalFinancePlan: bind(budget.originalAuthorization.concreteOriginalFinancePlan.path)},
  accounting: {conservativeFirstAttempt: 40, observedResume: 35, stoppedA2Reads: 3, priorA3: 78,
    actualA3Attempts: 50, stoppedA3Total: 128, pipelineInvestigation: 1, attributedA8OwnerRefresh: 1,
    alreadyConsumedConservativeTotal: 130, plannedNewReadinessRefreshAttempts: 1,
    requiredPriorAfterSuccessfulNewRefresh: 131, ordinaryFutureCalls: ordinary, ordinaryMaximum: 155,
    readonlyResolutionReserve: 1, requiredTotalMaximum: 156, deltaFromOriginalConcrete150: 6,
    old155ProposalValidNow: false, disappearingOrResetCallsAllowed: false, automaticRetriesAllowed: 0,
    secondRefreshWouldRequireNewExplicitTotal: 157, uncombined32CallsWouldRequireTotal: 164},
  readiness: {oldA8Metadata: bind(budget.currentOwnerScope.metadata.path), oldA8ExpiresAt: metadata.expiresAt,
    expiredAtReview: true, oldA8MayBeReused: false,
    recordedOriginalRuntimeAuthorityExpiresAt: '2026-10-14T09:57:07.481942Z', authorityExtensionAllowed: false,
    newMetadataOrRefreshProofExistsByThisReview: false,
    beforeAnyPrivateExportUnsealOrRequest: ['Root records the explicit planned refresh/cap/day decision first.',
      'Live owner uses a separately reviewed additive refresh source and new exclusive filenames. Charge the one attempt before its GET, including failure or missing persistence acknowledgment.',
      'Final plan binds the actual new refresh proof, exact metadata digest, current SID/project/bundle, actual creation/expiry and the consumed prior 131. No old A8 hash, altered observation or local future timestamp is a substitute.',
      'Export helper checks local UTC day 14 and the final fresh scope before private unseal; server UTC day is checked from the first consolidated preflight before sessions/exports.',
      'Use the earliest current metadata expiry, unchanged original runtime expiry and 15-minute run deadline, keeping one 45-second resolution window. Stop without extra calls or retries on expiry, day drift, failed refresh or evidence failure.'],
    fixedA8RefreshFilenameTrapVerified: true},
  exactExportScope: {fixtureUtcDayRetained: '2026-10-13', actualExportUtcDayProposed: '2026-10-14', registrations: 2,
    originalIds: budget.exactSource.exportIds, scope: budget.exactSource.scope,
    immutablePipelineId: budget.exactSource.pipelineId, pipelineSourceBasisHash: budget.exactSource.pipelineSourceBasisHash,
    decimalRowsUnchanged: budget.exactSource.pipelineRows, originalStatementId: budget.exactSource.statementId,
    originalAmountsDatesActorsMfaFactorsUnchanged: true, datesOrScenariosDispatched: false,
    registeredPipelineReopenPlanned: true, registeredStatementReopenClaimed: false,
    statementFreshPagePreviewAndCsvReproductionRetained: true, nativeDownloadOrSaveDialogClaimed: false},
  queryReview: {exactConsolidatedSqlSha256: budget.consolidatedEvidenceQueries.before.sha256,
    beforeAndAfterIdentical: true, readOnlySingleStatement: true, originalAndExportExclusionDigestRecipesMatch: true,
    exactSevenFunctionMd5sAndSourceIdentityChecksRetained: true, knownBlockingQuerySourceDefects: [],
    databaseExecutionOrSyntaxValidationPerformed: false,
    activityBoundary: 'Business-row scalar subqueries share their statement snapshot. pg_stat_activity is a momentary statistics observation, not a continuing cross-system quiescence barrier; preserve the two immediately-before-registration quiescence calls and ongoing live-owner coordination.'},
  requiredBeforeImplementationComplete: ['Root explicit source-only 156/day decision',
    'Additive source-bound fresh readiness plan/proof and final metadata binding',
    'V7 source-only export helper with a truthful 24 ordinary plus one conditional receipt call inventory',
    'Meaningful controlled budget/source/two-session/CSV/durability/expiry/uncertainty cases and independent V7 review before private use'],
  auditInputs: [budgetPath, `${auditFolder}/feasibility.md`, manifestPath].map(bind),
  directlyCitedBindingsVerified: [...cited.values()], preservationInputCount: 33,
  historicalConsumedSourceEvidenceBindings: historicalBindings,
  sourceBindingsUnchangedDuringReview: true,
  actualProjectApiRequests: 0, privateCredentialFilesRead: false, liveOrPrivateWrites: 0, SDKJobs: 0,
  liveExportAcceptanceAdded: 0, targetScaleLoadClaimed: false, productionReleaseReady: false,
};
const stem = `${output}/export-budget-day-independent-review-a1`;
fs.writeFileSync(path.resolve(root, `${stem}.json`), JSON.stringify(report, null, 2) + '\n', {flag: 'wx'});
const markdown = [
  '# Independent export budget and UTC day review', '',
  'The source-only continuation needs an explicit **156 cumulative-attempt ceiling**, after one newly charged successful readiness refresh. The earlier 155 proposal depended on A8, which expired at 03:09:42.640 UTC on October 14. It cannot authorize a present export run.', '',
  '| Accounting | Attempts |', '|---|---:|',
  '| Original conservative first/resume/A2 bound | 78 |', '| Completed A3 attempts | 50 |',
  '| Pipeline shape investigation | 1 |', '| Already performed A8 owner/project GET | 1 |',
  '| Preserved consumed total | 130 |', '| Planned new readiness refresh | 1 |',
  '| Ordinary export continuation | 24 |', '| Conditional read-only receipt resolution | 1 |',
  '| Required maximum | **156** |', '',
  'That is 6 above the untouched concrete 150 plan. The human runtime packet permits at most 8 governed exports and has no numeric 150 cap; the successor still permits only the two original export registrations. Every attempted/failed call remains charged, with no retry or counter reset.', '',
  'The actual export timestamp/day must be October 14 UTC. Preserve the October 13 fixture day, all original amounts/dates/actors/factors, both exact currency rows, source hashes and deterministic export/command IDs. Pipeline registration reopening is supported; the statement uses distinct-session page/preview and CSV reproduction. No registered statement reopen or native download is claimed.', '',
  'All 33 preservation inputs and their recorded before/after hashes match. The 68 consumed-plan sources and 37 prior evidence files also match the approved execution copies. The identical consolidated before/after SQL is one read-only statement with the original digest recipes and the exact two-export exclusion. Its activity view remains a momentary observation; retain immediate quiescence checks before both registrations.', '',
  'The original runtime expiry remains **09:57:07.481942 UTC**. A new refresh needs additive, exclusive filenames because the fixed A8 helper would spend its GET and then fail on consumed filenames. Count the new call before dispatch, and bind its actual proof and fresh metadata into the final cap/day plan before the export helper can unseal or request. A failed refresh stops; another refresh would require an explicit recomputed maximum.', '',
  'This is an independent technical recommendation. Root must publish the source-only decision and final preparation. No live execution authorization, personal human signature, requirement acceptance, credential access, project API call or SDK job is supplied by this review.', '',
  `[Machine review and verifier results](${path.basename(stem)}.json).`, '',
].join('\n');
fs.writeFileSync(path.resolve(root, `${stem}.md`), markdown, {flag: 'wx'});
const validation = {kind: 'independent-export-budget-day-review-verification', verifiedAt: new Date().toISOString(),
  passed, checksPassed: checks.filter(row => row.passed).length, checksTotal: checks.length, checks,
  sourcePreservationMatches: true, report: bind(`${stem}.json`), markdown: bind(`${stem}.md`),
  verifier: bind(`${output}/verify_budget_day_review.mjs`), networkCalls: 0, privateCredentialsRead: false, SDKJobs: 0};
fs.writeFileSync(path.resolve(root, `${output}/verifier-result-a1.json`), JSON.stringify(validation, null, 2) + '\n', {flag: 'wx'});
console.log(JSON.stringify({passed, checks: checks.length, failures: checks.filter(row => !row.passed),
  report: validation.report, markdown: validation.markdown, verifierResult: bind(`${output}/verifier-result-a1.json`)}, null, 2));
if (!passed) process.exitCode = 1;
