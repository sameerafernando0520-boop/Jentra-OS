import fs from 'node:fs/promises';
import path from 'node:path';
import assert from 'node:assert/strict';
import crypto from 'node:crypto';
import { fileURLToPath, pathToFileURL } from 'node:url';

// Independent, offline audit of public saved evidence only. This program never
// constructs a live client, reads encrypted owner inputs, or changes app source.
const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../../..');
const base = 'docs/verification/wave5/';
const attempt = base + 'genuine-finance-finance-20261013-r5-1791894738890/';
const prior = base + 'genuine-finance-finance-20261013-r5-1791894436593/';
const sha = value => crypto.createHash('sha256').update(value).digest('hex');
const cache = new Map();
const checks = [];

async function bytes(relative, expected) {
  const value = await fs.readFile(path.join(root, relative));
  if (expected) assert.equal(sha(value), expected, relative + ' frozen hash');
  cache.set(relative, { path: relative, sha256: sha(value), bytes: value });
  return value;
}
async function json(relative, expected) { return JSON.parse(await bytes(relative, expected)); }
function check(name, run) {
  try { run(); checks.push({ name, passed: true }); }
  catch (error) { checks.push({ name, passed: false, reason: error.message }); }
}
function decode(value) {
  if (typeof value === 'string') {
    let parsed;
    try { parsed = JSON.parse(value); }
    catch {
      const match = value.match(/(?:^|\n)<untrusted-data-([a-zA-Z0-9-]+)>\r?\n([\s\S]*?)\r?\n<\/untrusted-data-\1>(?:\n|$)/);
      assert.ok(match, 'exact public data boundary');
      return JSON.parse(match[2]);
    }
    return decode(parsed);
  }
  assert.notEqual(value?.isError, true);
  if (value?.rawConnectorResult) return decode(value.rawConnectorResult);
  if (Array.isArray(value?.content)) {
    const text = value.content.filter(item => item.type === 'text');
    assert.equal(text.length, 1);
    return decode(text[0].text);
  }
  if (typeof value?.result === 'string') return decode(value.result);
  return value;
}

const programPath = base + 'finance-runtime-independent-evidence-review-20261013-r5-a1.program.mjs';
await bytes(programPath);
const fixturePath = 'tools/wave5/finance_cash_fixture_20261013_r5.mjs';
const transportPath = 'tools/wave5/finance_https_transport_20261013_r5.mjs';
await bytes(fixturePath, '8d5e670368fd89a9e9a98f10aa4befc1f2bc4ed0b28de913aa89ee64766291f9');
await bytes(transportPath, '5eb2b839a9249fd457073d4b63523d311f06ecc2d392710db2f823259395ba0f');
await bytes('tools/wave5/runtime_contract.mjs');
await bytes('tools/wave5/runtime_fixture_spec.mjs');
const fixture = await import(pathToFileURL(path.join(root, fixturePath)));
const { financeDenial } = await import(pathToFileURL(path.join(root, transportPath)));
const { FINANCE_SCOPE: scope, FINANCE_ACTOR: proposer, FINANCE_JOURNALS: journals,
  FINANCE_ACCOUNTS: accounts, FINANCE_CALENDAR: calendar, financeId } = fixture;
const approver = '0635081d-08ea-4ad1-b7f2-ad2f8721f67d';
const hashPattern = /^[a-f0-9]{64}$/;

const plan = await json(base + 'finance-cash-workflow-preparation-20261013-r5-a3.json',
  '2290874b4d90865fea02d0c070c0342962a440f391fb9863df052fcbcc1f4913');
for (const binding of plan.sourceBindings) await bytes(binding.path, binding.sha256);
const attemptFiles = (await fs.readdir(path.join(root, attempt))).filter(p => p.endsWith('.json')).sort();
for (const name of attemptFiles) await bytes(attempt + name);
const oldWorkflow = cache.get('tools/wave5/finance_cash_workflows_20261013_r5.mjs').bytes.toString();
const oldTransport = cache.get(transportPath).bytes.toString();
const [before, stop, date, ratios, guard] = await Promise.all(
  ['00-source-before.json', '99-stop.json', 'date-payroll_obligation.json',
    'ratios-and-classification.json', 'future-horizon-guard.json'].map(p => json(attempt + p)));
const statementKinds = ['profit_loss', 'balance_sheet', 'trial_balance'];
const statements = await Promise.all(statementKinds.map(kind => json(attempt + 'statement-' + kind + '.json')));
const sessions = await Promise.all(['proposer', 'approver', 'foreign-member'].map(label => json(attempt + 'session-' + label + '.json')));
const intents = {}, results = {};
for (const n of [1, 2, 3, 4, 6, 7, 8, 9]) {
  const prefix = String(n).padStart(3, '0') + '-';
  intents[n] = await json(attempt + attemptFiles.find(p => p.startsWith(prefix) && p.endsWith('-intent.json')));
  if (n !== 9) results[n] = await json(attempt + attemptFiles.find(p => p.startsWith(prefix) && p.endsWith('-result.json')));
}
const rollback = decode(await json(base + 'finance-cash-fixture-after-rollback-read-20261013-r5.json'))[0].snapshot;
const commit = decode(await json(base + 'finance-cash-fixture-after-commit-read-20261013-r5.json'))[0].facts;
const commitTool = await json(base + 'finance-cash-fixture-commit-result-20261013-r5.json');
const rollbackTool = await json(base + 'finance-cash-fixture-rollback-result-20261013-r5.json');
const rollbackSql = await bytes(base + 'finance-cash-fixture-20261013-r5-a1-rollback.sql',
  '184a2f500264bd9fe40d29bde49f44592c17d398876060664af0a8a45c45a7bb');
const commitSql = await bytes(base + 'finance-cash-fixture-20261013-r5-a1-commit.sql',
  '233cb3065796d3cc5174506db010b81f5499df5aaa0dba37cb3140fb49e557ab');
const resolution = await json(base + 'finance-stale-command-read-only-resolution-20261013-r5-a1.json');
const late = decode(resolution.lateRead.value)[0].facts;
const observation = await json(base + 'finance-remaining-readonly-observation-20261013-r5-a1.json');
const observationFacts = decode(observation.result)[0].facts;
const reconciliation = await json(base + 'finance-remaining-readonly-reconciliation-20261013-r5-a2.json',
  '57e51d82616158e1eb3b97ab1f574a2091c9bd0f022c0079d287842724d60f67');
const reconstructed = decode(reconciliation.reconstructedBaselineResult)[0].facts;
const eventObservation = decode(reconciliation.processAppendResult)[0].observation;
const metadata = await json(base + 'finance-stale-backend-metadata-20261013-r5-a1.json',
  'fd1f2ac38acbc2297c446ecf892fc4655adbe111cb54641be2aaf48919a3e95c');
const posting = await json(prior + '002-post_manual_journal-result.json');
const priorStop = await json(prior + '99-stop.json');
await json(base + 'finance-cash-finance-resume-once-20261013-r5.json');
await json(base + 'finance-cash-fixture-independent-peer-review-20261013-r5-a1.json',
  '7f58386dc871755534dd304e1353b7572b5552c492e51f2b1360914ea5d71710');
const sqlNames = ['20260925002000_wave3_financial_statements.sql', '20260925003000_wave3_cash_flow.sql',
  '20261008113000_wave5_statement_classifications.sql', '20261008120000_wave5_cash_payment_dates.sql',
  '20261008103000_wave5_dated_cash.sql'];
const sql = {};
for (const name of sqlNames) sql[name] = (await bytes('supabase/migrations/' + name)).toString();

// Independent arithmetic works from balanced fixture lines, not the helper's
// expected totals or exactRatio implementation. No binary floating point.
function units(value) {
  assert.match(value, /^-?\d+\.\d{6}$/);
  const negative = value[0] === '-', parts = value.replace('-', '').split('.');
  return (negative ? -1n : 1n) * (BigInt(parts[0]) * 1000000n + BigInt(parts[1]));
}
function decimal(value) {
  const absolute = value < 0n ? -value : value;
  return (value < 0n ? '-' : '') + absolute / 1000000n + '.' +
    (absolute % 1000000n).toString().padStart(6, '0');
}
const ledger = new Map(accounts.map(account => [account.id, 0n]));
const currentJournals = journals.filter(journal => journal.date <= calendar.fixtureDay);
let turnover = 0n;
for (const journal of currentJournals) {
  const value = units(journal.amount);
  ledger.set(journal.debit, ledger.get(journal.debit) + value);
  ledger.set(journal.credit, ledger.get(journal.credit) - value);
  turnover += value;
}
const byType = type => accounts.filter(a => a.type === type).reduce((v, a) => v + ledger.get(a.id), 0n);
const money = { assets: byType('asset'), liabilities: -byType('liability'), equity: -byType('equity'),
  revenue: -byType('revenue'), expenses: byType('expense') };
money.net_profit = money.revenue - money.expenses;
money.current_earnings = money.net_profit;
const positive = [...ledger.values()].filter(v => v > 0n).reduce((a, b) => a + b, 0n);
const negative = -[...ledger.values()].filter(v => v < 0n).reduce((a, b) => a + b, 0n);
function roundedDivision(numerator, denominator) {
  assert.ok(denominator > 0n);
  const negative = numerator < 0n, absolute = negative ? -numerator : numerator;
  const sevenDigits = absolute * 10000000n / denominator;
  const rounded = (sevenDigits + 5n) / 10n;
  return decimal(negative ? -rounded : rounded);
}

check('frozen plan retains approved project/bundle and150 cumulative cap', () => {
  assert.equal(plan.projectId, 'xpdoufauvrbdmxgngetv');
  assert.equal(plan.bundleSha256, 'db525758554036fa99ec02d00c85bd8401ef7ebce787e2a983db1c69a08baf7b');
  assert.equal(plan.maximumTotalWorkflowRequestAttempts, 150);
  assert.equal(plan.maximumExecutionMs, 900000);
});
check('rollback readback has zero new fixture rows and preserved original CRM/process counts', () => {
  for (const key of ['lines', 'parties', 'accounts', 'journals', 'openItems', 'payrollCorrections',
    'payrollObligations', 'projectReimbursements']) assert.equal(rollback[key], 0);
  assert.equal(rollback.originalCrmOpportunities, 2); assert.equal(rollback.originalProcessEvents, 4);
});
check('successful tool responses are paired with exact rollback/commit SQL hashes', () => {
  assert.deepEqual(decode(commitTool), []); assert.deepEqual(decode(rollbackTool), []);
  assert.equal(commitTool.sqlSha256, sha(commitSql)); assert.equal(rollbackTool.sqlSha256, sha(rollbackSql));
  assert.equal(commitTool.readbackRequired, true);
});
check('commit readback matches bounded administrative fixture counts and zero imbalance', () => {
  assert.equal(commit.lines, 18); assert.equal(commit.journals, 9); assert.equal(commit.accounts, 10);
  assert.equal(commit.openItems, 2);
  for (const key of ['payroll', 'correction', 'reimbursement']) assert.equal(commit[key], 1);
  assert.deepEqual(commit.sourceTypes, ['w5_synthetic_admin_fixture']); assert.equal(commit.unbalancedJournals, 0);
});
check('source-before retains all original nine deterministic journal IDs', () => {
  assert.deepEqual(before.facts.journalIds, journals.map(j => j.id).sort());
  assert.equal(before.facts.journals, 9); assert.equal(before.facts.lines, 18);
  assert.equal(before.facts.sourceHash, 'ff90ee8cb1e1a33982eedfc1d05a8b8118a463d8e2bd9a36ac9f1469eb40be38');
});
check('current statement excludes the future reversal and has eight journals/sixteen lines', () => {
  assert.equal(currentJournals.length, 8); assert.equal(journals.length, 9);
  assert.equal(decimal(turnover), '105219.000012'); assert.equal(decimal(positive), '105209.000008');
  assert.equal(positive, negative); assert.equal(money.assets, money.liabilities + money.equity + money.net_profit);
});
for (let i = 0; i < statements.length; i++) check('saved ' + statementKinds[i] + ' summary matches independent integer ledger', () => {
  const result = statements[i], value = result.summary;
  assert.equal(value.kind, statementKinds[i]); assert.equal(value.id, result.id);
  assert.equal(value.id, intents[i + 1].body.p_payload.id);
  assert.equal(value.tenant_id, scope.tenantId); assert.equal(value.legal_entity_id, scope.entityId);
  assert.equal(value.branch_id, scope.branchId); assert.equal(value.period_id, financeId('period'));
  assert.equal(value.as_of, calendar.fixtureDay); assert.equal(value.period_start, '2026-10-01');
  assert.equal(value.period_end, '2026-10-31'); assert.equal(value.base_currency_code, 'LKR');
  assert.equal(value.status, 'generated'); assert.equal(value.version, 1);
  assert.equal(value.journal_count, 16); assert.equal(value.account_count, 10);
  assert.equal(value.period_debit, decimal(turnover)); assert.equal(value.period_credit, decimal(turnover));
  assert.equal(value.closing_debit, decimal(positive)); assert.equal(value.closing_credit, decimal(negative));
  assert.equal(value.difference, '0.000000'); assert.equal(result.actorId, proposer);
  const relevant = statementKinds[i] === 'profit_loss' ? ['revenue', 'expenses', 'net_profit'] :
    statementKinds[i] === 'balance_sheet' ? ['assets', 'liabilities', 'equity', 'current_earnings'] : [];
  for (const key of relevant) assert.equal(value[key], decimal(money[key]));
});
check('statement journal_count means line-row count in bound SQL', () =>
  assert.match(sql[sqlNames[0]], /'journal_count',jsonb_array_length\(journal_rows\)/));
for (const n of [1, 2, 3, 4, 6, 7, 8]) check('command ' + n + ' binds exact identity/actor/route and client-local interval', () => {
  const intent = intents[n], result = results[n], transport = result.transport;
  assert.equal(intent.commandId, result.commandId); assert.equal(intent.actorId, result.actorId);
  assert.equal(transport.route, '/rest/v1/rpc/' + intent.name); assert.equal(transport.method, 'POST');
  assert.equal(transport.status, 200); assert.equal(result.denialCode, null);
  assert.match(transport.responseSha256, hashPattern); assert.equal(transport.responseSha256, result.responseSha256);
  assert.ok(Date.parse(transport.startedAt) <= Date.parse(transport.sentAt));
  assert.ok(Date.parse(transport.sentAt) <= Date.parse(transport.finishedAt)); assert.ok(transport.responseBytes > 0);
});
for (const proof of sessions) check('saved genuine ' + proof.label + ' Auth/MFA proof uses verified existing factor and online session', () => {
  assert.equal(proof.aal, 'aal2'); assert.equal(proof.factorStatus, 'verified');
  assert.equal(proof.onlineAuthVerified, true); assert.equal(proof.serverSessionRowVerified, true);
  assert.equal(proof.constructedAalClaims, false); assert.equal(proof.existingUser, true);
  assert.equal(proof.existingFactor, true); assert.equal(proof.newUserOrFactorCreated, false);
  assert.deepEqual(proof.actualAuthTransport.map(t => t.route), ['/auth/v1/token?grant_type=password',
    '/auth/v1/factors/' + proof.factorId + '/challenge', '/auth/v1/factors/' + proof.factorId + '/verify', '/auth/v1/user']);
  assert.ok(proof.actualAuthTransport.every(t => t.status === 200));
  assert.equal(new Set(proof.actualAuthTransport.map(t => t.connectionId)).size, 1);
});
check('proposer and approver are distinct actual actors/factors/sessions/connections', () => {
  assert.equal(sessions[0].actorId, proposer); assert.equal(sessions[1].actorId, approver);
  for (const key of ['actorId', 'factorId', 'sessionId']) assert.notEqual(sessions[0][key], sessions[1][key]);
  assert.notEqual(sessions[0].actualAuthTransport[0].connectionId, sessions[1].actualAuthTransport[0].connectionId);
  assert.equal(results[6].transport.connectionId, sessions[0].actualAuthTransport[0].connectionId);
  assert.equal(results[7].transport.connectionId, sessions[1].actualAuthTransport[0].connectionId);
});
check('classification publishes exactly ten frozen labels through the genuine approver', () => {
  assert.equal(intents[4].actorId, approver);
  assert.deepEqual(intents[4].body.p_labels, Object.fromEntries(accounts.map(a => [a.id, a.label])));
  assert.equal(intents[4].body.p_profit_loss_id, statements[0].id); assert.equal(intents[4].body.p_balance_sheet_id, statements[1].id);
  assert.equal(ratios.classificationId, intents[4].commandId); assert.equal(ratios.genuineApprover, approver);
});
const currentAssets = accounts.filter(a => ['current_asset', 'inventory'].includes(a.label)).reduce((v, a) => v + ledger.get(a.id), 0n);
const inventory = accounts.filter(a => a.label === 'inventory').reduce((v, a) => v + ledger.get(a.id), 0n);
const currentLiabilities = -accounts.filter(a => a.label === 'current_liability').reduce((v, a) => v + ledger.get(a.id), 0n);
const costOfSales = accounts.filter(a => a.label === 'cost_of_sales').reduce((v, a) => v + ledger.get(a.id), 0n);
const formulas = {
  assets_to_equity: [money.assets, money.equity + money.net_profit], net_profit_margin: [money.net_profit, money.revenue],
  liabilities_to_assets: [money.liabilities, money.assets], quick_ratio: [currentAssets - inventory, currentLiabilities],
  current_ratio: [currentAssets, currentLiabilities], gross_profit_margin: [money.revenue - costOfSales, money.revenue]
};
for (const [name, [numerator, denominator]] of Object.entries(formulas)) check('ratio ' + name + ' equals independently rounded ledger operands', () => {
  const value = ratios.ratios.ratios[name];
  assert.equal(value.numerator, decimal(numerator)); assert.equal(value.denominator, decimal(denominator));
  assert.equal(value.exactValue, roundedDivision(numerator, denominator)); assert.equal(value.unavailableReason, null);
});
check('base three ratios remain unchanged after classification; six classified identities are exact', () => {
  assert.equal(Object.keys(ratios.ratiosBase.ratios).length, 3); assert.equal(Object.keys(ratios.ratios.ratios).length, 6);
  for (const [key, value] of Object.entries(ratios.ratiosBase.ratios)) assert.deepEqual(value, ratios.ratios.ratios[key]);
  for (const value of [ratios.ratiosBase, ratios.ratios]) {
    assert.equal(value.profitLossId, statements[0].id); assert.equal(value.balanceSheetId, statements[1].id);
    assert.deepEqual(value.scope, { tenantId: scope.tenantId, legalEntityId: scope.entityId, branchId: scope.branchId });
    assert.equal(value.formulaVersion, 1); assert.equal(value.contractRevision, 1);
    assert.match(value.profitLossHash, hashPattern); assert.match(value.balanceSheetHash, hashPattern);
  }
});
check('payroll source uses current partial settlement amount rather than future reversal amount', () => {
  assert.equal(date.source.sourceId, financeId('payroll.obligation')); assert.equal(date.source.originalAmount, '10.000001');
  assert.equal(date.source.remainingAmount, '7.000001'); assert.equal(date.source.issueDate, calendar.issueDate);
  assert.equal(date.source.inflow, false); assert.equal(date.source.approved, null);
});
check('payroll approval binds original proposal/source/prepare and independent decision', () => {
  const value = date.readback;
  assert.equal(value.id, intents[6].body.p_payload.id); assert.equal(value.preparedBy, proposer);
  assert.equal(value.sourceKind, 'payroll_obligation'); assert.equal(value.sourceId, date.source.sourceId);
  assert.equal(value.sourceHash, date.source.sourceHash); assert.equal(value.expectedVersion, '0');
  assert.equal(value.decision, 'approved'); assert.equal(value.approvedVersion, '1');
  assert.equal(value.currentApproval.version, '1'); assert.equal(value.currentApproval.id, value.id);
  assert.equal(value.currentApproval.decisionId, intents[7].commandId);
  assert.equal(value.currentApproval.proposalHash, value.proposalHash);
  assert.equal(value.currentApproval.sourceHash, value.sourceHash); assert.equal(value.dueDate, calendar.dueDate);
  assert.equal(value.currentApproval.dueDate, calendar.dueDate); assert.equal(date.genuineDistinctApprover, approver);
  assert.match(value.proposalHash, hashPattern);
});
check('successful original prepare replay retains exact body/command and response bytes hash', () => {
  assert.deepEqual(intents[6].body, intents[8].body); assert.equal(intents[6].commandId, intents[8].commandId);
  assert.equal(results[6].responseSha256, results[8].responseSha256);
  assert.equal(date.originalReplaySha256, results[6].responseSha256);
});
check('future horizon guard is actualHTTP400 and complete cash basis remains excluded', () => {
  assert.equal(guard.transport.status, 400); assert.equal(guard.denialCode, 'VALIDATION_ERROR');
  assert.equal(guard.completeCashBasisProved, false);
  assert.ok(guard.horizonStart > new Date(guard.observedAt).toISOString().slice(0, 10));
  assert.match(sql[sqlNames[4]], /p_start::timestamptz>p_recorded_through/);
  assert.match(sql[sqlNames[4]], /c.updated_at>p_start::timestamptz/);
});
check('timeout preserves stale identity/version with no captured result or whole-phase completion', () => {
  assert.equal(stop.failureCode, 'FINANCE_TIMEOUT_UNCERTAIN'); assert.equal(stop.phase, 'wave5_cash_date_command');
  assert.equal(stop.lastOriginalCommand.commandId, intents[9].commandId);
  assert.equal(intents[9].body.p_payload.expectedVersion, '0'); assert.equal(date.readback.currentApproval.version, '1');
  assert.equal(intents[9].body.p_payload.sourceId, date.source.sourceId);
  assert.equal(intents[9].body.p_payload.id, '8337ca68-2add-d88a-a198-9019b10235cc');
  assert.equal(attemptFiles.some(p => p.startsWith('009-') && p.endsWith('-result.json')), false);
  assert.equal(attemptFiles.includes('99-result.json'), false); assert.equal(attemptFiles.includes('98-source-after.json'), false);
});
check('configured timeout is bounded at45seconds and frozenSQL guards stale version with40001', () => {
  assert.match(oldTransport, /timeoutMs=45000/); assert.match(oldTransport, /timeoutMs<=45000/);
  assert.match(sql[sqlNames[3]], /errcode='40001',message='CASH_DATE_VERSION_CONFLICT'/);
});
check('timeout resolution has zero saved receipts and no automatic replay', () => {
  assert.deepEqual(stop.resolution.rows, []); assert.equal(stop.resolution.responseSha256, sha('[]'));
  assert.equal(stop.resolution.readOnly, true); assert.equal(stop.resolution.replayPerformed, false);
  assert.equal(stop.automaticRetryPerformed, false); assert.equal(stop.liveGateComplete, false);
  assert.equal(stop.privateErrorPrinted, false);
});
check('35 observed current requests plus40 earlier reserve is75, not an observed total', () => {
  assert.equal(stop.actualRequestAttempts, 35); assert.equal(stop.priorRequestBound, 40);
  assert.ok(stop.actualRequestAttempts + stop.priorRequestBound <= 150);
});
check('earlier posting403/identifier stop are preserved and referenced without replay', () => {
  assert.equal(posting.transport.status, 403); assert.equal(posting.denialCode, 'PERMISSION_DENIED');
  assert.equal(priorStop.lastOriginalCommand, null); assert.equal(priorStop.resolution, null);
  assert.equal(stop.completed[0].commandId, posting.commandId);
  assert.equal(stop.completed[0].priorAttemptEvidence, prior + '99-stop.json');
});
check('14:53 snapshot has three statements/one classification/date, stale0 and exports0', () => {
  assert.equal(late.publications, 3); assert.equal(late.classifications, 1); assert.equal(late.dateProposals, 1);
  assert.equal(late.dateDecisions, 1); assert.equal(late.exports, 0); assert.equal(late.staleReceipts, 0);
  assert.equal(late.staleProposals, 0); assert.equal(late.liveAuthenticatorCashBackends, 0);
  assert.ok(late.jobs.every(job => job.active === false)); assert.equal(resolution.expectedConflictHttpResponseObserved, false);
  assert.equal(resolution.backendTerminated, false); assert.equal(resolution.projectRestarted, false);
});
check('15:05 snapshot preserves stale0 but honestly reports changed whole-source digest/activity1', () => {
  assert.equal(observationFacts.sourceHash, '6419aa1d51407cd016915da47a56ae28f5f3f50458c562b011e2b16da54bccb3');
  assert.equal(observationFacts.activeCashApiInvocations, 1); assert.equal(observationFacts.staleReceipts, 0);
  assert.equal(observationFacts.staleProposals, 0); assert.equal(observation.sourceHashMatchesPrior, false);
  assert.equal(observation.mutationPerformed, false);
});
const commands = [1, 2, 3].map(n => intents[n].commandId);
const financeTemplate = oldWorkflow.match(/export const FINANCE_FACTS_SQL=`([\s\S]*?)`;/)[1]
  .split('${scope.tenantId}').join(scope.tenantId);
const expectedReconstruction = financeTemplate.replace("FROM workflow.process_events x WHERE tenant_id='" + scope.tenantId + "'",
  "FROM workflow.process_events x WHERE tenant_id='" + scope.tenantId + "' AND command_id NOT IN (" +
  commands.map(command => "'" + command + "'").join(',') + ")");
check('reconstruction changes only the exact three documented process command exclusions', () =>
  assert.equal(reconciliation.reconstructedBaselineQuery, expectedReconstruction));
check('saved reconstructed digest equals original baseline across unchanged source families', () => {
  assert.equal(reconstructed.sourceHash, before.facts.sourceHash);
  assert.equal(reconciliation.originalSourceSha256, before.facts.sourceHash);
  assert.equal(reconciliation.currentWholeSourceSha256, observationFacts.sourceHash);
  assert.deepEqual(reconstructed.journalIds, before.facts.journalIds);
  assert.equal(reconstructed.journals, 9); assert.equal(reconstructed.lines, 18);
  assert.equal(reconstructed.exports, 0); assert.equal(reconstructed.scenarios, 0);
});
const appends = eventObservation.events.filter(event => commands.includes(event.commandId));
const originalEvents = eventObservation.events.filter(event => !commands.includes(event.commandId));
check('manifest has original fourCRM rows plus exactly three generated statement events', () => {
  assert.equal(eventObservation.events.length, 7); assert.equal(originalEvents.length, 4); assert.equal(appends.length, 3);
  assert.ok(originalEvents.every(event => event.documentType === 'crm_opportunity' && event.actorId === proposer));
  assert.equal(new Set(originalEvents.map(event => event.documentId)).size, 2);
  for (let i = 0; i < 3; i++) {
    const event = appends.find(item => item.commandId === commands[i]);
    assert.equal(event.documentType, 'financial_statement_report'); assert.equal(event.documentId, statements[i].id);
    assert.equal(event.toStatus, 'generated'); assert.equal(event.actorId, proposer);
  }
  assert.match(sql[sqlNames[1]], /'financial_statement_report',id/);
  assert.match(sql[sqlNames[1]], /jsonb_build_object\('to_status',summary->>'status'\)/);
});
check('original four eventIDs equal exact saved values, without inventing missing fields', () =>
  assert.deepEqual(originalEvents.map(event => event.id).sort(), ['34d25769-e5ac-451f-8800-eb862db79e65',
    'cbe0d78a-4a6a-4c2a-96ac-46523e1ba309', 'de4fd834-20c4-4ab4-9eaa-7d1647b69307',
    'fbc77771-8e5f-4d6d-ade1-409a1370a399'].sort()));
check('specific API activity excludes observerSQL and15:09start is not original12:32 attribution', () => {
  assert.match(reconciliation.processAppendQuery, /position\('pg_stat_activity' in query\)=0/);
  assert.match(reconciliation.processAppendQuery, /pid<>pg_backend_pid\(\)/);
  assert.equal(eventObservation.activeApiCalls.length, 1); assert.equal(eventObservation.activeApiCalls[0].pid, 66780);
  assert.ok(Date.parse(eventObservation.activeApiCalls[0].queryStart) > Date.parse(stop.actualStoppedAt));
  assert.equal(metadata.originalCommandParametersObserved, false); assert.equal(metadata.exactOriginalCommandAttributionConfirmed, false);
});
check('subsequent exactPID metadata is empty; no cancellation/termination/replay occurred', () => {
  assert.deepEqual(decode(metadata.result), []);
  for (const key of ['cancellationPerformed', 'terminationPerformed', 'replayPerformed']) assert.equal(metadata[key], false);
  assert.match(metadata.query, /WHERE pid=66780/);
});
const denialProbe = { code: '40001', message: 'CASH_DATE_VERSION_CONFLICT', status: 500,
  mapped: financeDenial({ ok: false, status: 500, value: { code: '40001', message: 'CASH_DATE_VERSION_CONFLICT' } }) };
check('frozen mapper probe reproduces missed40001/HTTP500 without claiming a live response', () => assert.equal(denialProbe.mapped, null));
check('frozen mapper also misses known55000/HTTP500 and rejects an unrelated500', () => {
  assert.equal(financeDenial({ ok: false, status: 500, value: { code: '55000', message: 'CASH_COMPLETE_PROVIDERS_REQUIRED' } }), null);
  assert.equal(financeDenial({ ok: false, status: 500, value: { code: 'XX000', message: 'CASH_DATE_VERSION_CONFLICT' } }), null);
});
check('old final whole-source assertion would reject genuine allowed process appends', () => {
  assert.match(oldWorkflow, /after.sourceHash===before.sourceHash/);
  assert.notEqual(observationFacts.sourceHash, before.facts.sourceHash);
  assert.equal(reconstructed.sourceHash, before.facts.sourceHash);
});

let stable = true;
for (const [relative, input] of cache) {
  const currentHash = sha(await fs.readFile(path.join(root, relative)));
  check('public input unchanged after review: ' + relative, () => assert.equal(currentHash, input.sha256));
  if (currentHash !== input.sha256) stable = false;
}
const inputs = [...cache.values()].map(({ path, sha256, bytes }) => ({ path, sha256, sizeBytes: bytes.length }));
const failed = checks.filter(item => !item.passed);
const ratioOracles = Object.fromEntries(Object.entries(formulas).map(([name, [n, d]]) =>
  [name, { numerator: decimal(n), denominator: decimal(d), exactValue: roundedDivision(n, d) }]));
const report = {
  kind: 'independent-offline-review-of-saved-genuine-finance-evidence', reviewer: '/root/provider_review_20261013',
  reviewedAt: new Date().toISOString(), projectId: plan.projectId, bundleSha256: plan.bundleSha256,
  verdict: failed.length ? 'LOCAL_REVIEW_CHECK_FAILED' : 'BOUNDED_SAVED_EFFECTS_RECONCILED_FRESH_CONTINUATION_GUARDS_REQUIRED',
  reviewExecution: { independentLiveQueries: 0, sqlMutations: 0, privateFilesRead: 0, networkRequests: 0, sdkCalls: 0,
    operationalSourceEdits: 0, childTestProcesses: 0, newReviewProgramCreated: true, onlyNewReviewArtifactsWritten: true,
    inputHashesStable: stable }, checks: { passed: checks.length - failed.length, failed: failed.length, items: checks }, inputs,
  verifiedSavedEffects: {
    administrativeFixture: { journals: 9, lines: 18, accounts: 10, openItems: 2, payrollSources: 1, recoverySources: 1,
      reimbursementSources: 1, userPostingProved: false, operationalPayrollApprovalProved: false },
    statements: statements.map((value, i) => ({ kind: statementKinds[i], id: value.id,
      originalCommandId: intents[i + 1].commandId, summary: value.summary })),
    journalCountMeaning: '16 source line rows across8 current journals; ninth future journal excluded',
    classification: { id: ratios.classificationId, actorId: approver, exactLabels: 10 }, ratios: ratioOracles,
    genuineSessions: sessions.map(p => ({ label: p.label, actorId: p.actorId, sessionId: p.sessionId, factorId: p.factorId,
      aal: p.aal, onlineAuthVerified: p.onlineAuthVerified, serverSessionRowVerified: p.serverSessionRowVerified })),
    payrollDate: { sourceId: date.source.sourceId, proposalId: date.readback.id, dueDate: date.readback.dueDate,
      prepareCommandId: intents[6].commandId, approveCommandId: intents[7].commandId,
      originalReplayCommandId: intents[8].commandId, originalReplayResponseSha256: date.originalReplaySha256,
      genuineDistinctApprover: approver },
    processPreservation: { originalBaselineHash: before.facts.sourceHash, currentWholeHash: observationFacts.sourceHash,
      exactReconstructedBaselineHash: reconstructed.sourceHash, originalFourEventIds: originalEvents.map(event => event.id),
      permittedStatementAppends: appends, blanketNewRowsExclusion: false }
  },
  timeout: {
    originalCommandId: intents[9].commandId, originalProposalId: intents[9].body.p_payload.id,
    failureCode: stop.failureCode, configuredDeadlineMs: 45000, actualStoppedAt: stop.actualStoppedAt,
    capturedHttpStatus: null, capturedHttpResponse: null, capturedTransportStartOrDispatchProof: false,
    actualServerDenialProved: false, receiptResolutionRows: [], automaticReplayPerformed: false,
    late1453Facts: late, later1505Facts: observationFacts, activeSpecificPidObservation: eventObservation.activeApiCalls,
    followingExactPidMetadata: [], exactOriginalCommandAttributionConfirmed: false,
    configuredVersionConflict: { expectedVersion: '0', alreadyApprovedVersion: '1', sqlState: '40001', actualResponseObserved: false },
    possibleRetryLoopExplanation: { isInference: true, deployedPostgrestVersionVerified: false,
      specificErrorLogOrOriginalPidCorrelated: false }
  },
  findings: [
    { id: 'F01', status: 'NEW_COPY_FIX_PENDING', file: transportPath, line: 60,
      issue: 'Frozen mapper omits documentedHTTP500 for exact known40001/55000; controlled public-input probe returnsnull.',
      probe: denialProbe, actualTimeoutResponseNotCaptured: true,
      required: 'New source-bound transport maps only exact known SQLSTATE/message plus officialstatus, preserves old bytes, rejects unrelated500.' },
    { id: 'F02', status: 'SAVED_BASELINE_RECONCILED_NEW_HELPER_GUARD_PENDING', file: 'tools/wave5/finance_cash_workflows_20261013_r5.mjs', line: 234,
      issue: 'Whole-source digest includesworkflow.process_events, so legitimate statement appends change it; oldsame-hash assertion cannot accept those effects.',
      required: 'Preserve baselineff90 with exact statement/export command manifests and unchanged original rows; no blind baseline replacement.' },
    { id: 'F03', status: 'CURRENT_CASH_BASIS_OPEN', file: 'supabase/migrations/20261008103000_wave5_dated_cash.sql', line: 56,
      issue: 'ActualHTTP400 confirms future opening horizon blocked at genuineOct13cutoff; mappinghistory also forbids invented historical mapping.',
      required: 'Separate futurecash/scenario work; no backdating, future cutoff or unapproved SQLpatch.' }
  ],
  requestBudget: { currentAttemptObservedRequests: 35, earlierAttemptReservedMaximum: 40, cumulativeBoundConsumed: 75,
    cumulativeObservedTotal: null, remainingApprovedMaximum: 75, cap: 150 },
  evidenceLimits: { savedRootResponsesReviewed: true, actualQueriesNotIndependentlyExecuted: true,
    fullStatementCanonicalAccountAndJournalRowsNotSaved: true, fullCanonicalStatementHashRecomputation: false,
    fullSuccessRpcBytesNotSaved: true, clientAndServerClockOffsetVerified: false, crossClockLatencyOrOrderInferred: false,
    subsequentExactPidAbsenceDoesNotProveAllInvocationsIdle: true, lateSnapshotsDoNotResolveOriginalHttpDenial: true },
  remainingBeforeNewWrites: [
    'Fresh baseline reconstruction and exact existing3 statement appendmanifest',
    'Fresh stale originalreceipt/proposal counts0', 'Fresh exact cash API active count0 with observerqueries excluded',
    'Frozen newhelper/preparer/transport/tests and independentreview',
    'Successfulpayrolldate and uncertainstalecommand unchanged; reserve75 priorrequests',
    'After2exports require exact2export command appendmanifest and immutable baseline again'
  ],
  gateSeparation: { boundedSavedFinanceEffectsReviewed: true, completeFinanceAndCash: false, allAuthoritativeCashProviders: false,
    remainingTwoDates: false, governedExports: false, cashScenarios: false, authenticatedNative: false, actualDelivery: false,
    fullPrivateProvider: false, targetScaleLoad: false, ownerAcceptedRequirements: 3, totalOwnerRequirements: 109,
    ownerAcceptanceChanged: false, production: false, realBilling: false },
  primarySources: [
    { url: 'https://supabase.com/docs/guides/troubleshooting/high-cpu-and-infinite-transaction-retries-when-using-custom-error-codes-in-rpc-functions-77326b',
      supports: 'Documented custom40001 retry-loop behavior; project-specific cause is unproved.' },
    { url: 'https://github.com/PostgREST/postgrest/pull/4222', supports: 'Primary upstream correction; no installedprojectversion proof.' },
    { url: 'https://docs.postgrest.org/en/v14/references/errors.html', supports: '40*/55* mapHTTP500; authenticated42501 maps403.' }
  ]
};
const jsonPath = base + 'finance-runtime-independent-evidence-review-20261013-r5-a1.json';
const mdPath = base + 'finance-runtime-independent-evidence-review-20261013-r5-a1.md';
const reportBytes = Buffer.from(JSON.stringify(report, null, 2) + '\n');
await fs.writeFile(path.join(root, jsonPath), reportBytes, { flag: 'wx' });
const md = `# Independent saved finance evidence review, 13 October 2026

${report.verdict}. Actual offline checks: ${report.checks.passed} passed / ${report.checks.failed} failed. Public inputs stayed unchanged: ${stable}. No live, private, SDK or operational source operation was performed.

The saved root responses support nine administrative synthetic journals and eighteen lines, three balanced statements, six exact integer-checked ratios, one classification and one payment-date approval by a distinct existing MFA account. Successful prepare replay retained its original command, body and response hash. These remain bounded API evidence; authenticated native and owner acceptance remain open.

The whole-source digest changed from ff90… to 6419… because the API generated exactly three process events. The saved reconstruction excludes only those three exact statement commands and reproduces ff90…, preserving the original four CRM events. New continuation must also check the exact two export appends.

Stale command 92e523de-6d82-d54a-0bfe-e81a78593a96 stopped with FINANCE_TIMEOUT_UNCERTAIN under a configured 45 second deadline. No HTTP status, body or failed dispatch interval was captured. Saved receipts and proposals are zero. One later active API PID started at 15:09 UTC; an exact PID lookup later returned empty. That does not attribute the invocation to the 12:32 command or prove the whole function idle. Preserve uncertainty and require fresh guards before writes.

The frozen mapper misses exact known 40001/55000 responses at documented HTTP 500; the independent 40001/500 probe returns null. [PostgREST 14 errors](https://docs.postgrest.org/en/v14/references/errors.html) supports the mapping. [Supabase troubleshooting](https://supabase.com/docs/guides/troubleshooting/high-cpu-and-infinite-transaction-retries-when-using-custom-error-codes-in-rpc-functions-77326b) and [the upstream fix](https://github.com/PostgREST/postgrest/pull/4222) support a possible retry explanation, without establishing this project's cause or installed version. A new narrow mapper copy remains to review.

Actual HTTP 400 and frozen SQL still block the future cash opening horizon on October 13. Two further date approvals, exports, cash scenarios, the full provider and load gates, authenticated native checks, delivery and the remaining 106 owner requirements remain open. Accepted requirements remain 3/109.

Exact input hashes, checks, preserved failures and limits: [JSON review](finance-runtime-independent-evidence-review-20261013-r5-a1.json). JSON SHA-256: ${sha(reportBytes)}.
`;
await fs.writeFile(path.join(root, mdPath), md, { flag: 'wx' });
console.log(JSON.stringify({ jsonPath, jsonSha256: sha(reportBytes), mdPath, mdSha256: sha(md),
  programSha256: cache.get(programPath).sha256, checks: report.checks.passed, failures: report.checks.failed,
  inputs: inputs.length, stable, failedChecks: failed }));
if (failed.length) process.exitCode = 1;
