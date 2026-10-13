import fs from 'node:fs/promises';
import path from 'node:path';
import assert from 'node:assert/strict';
import { fileURLToPath } from 'node:url';
import { hashBytes, hashJson } from './runtime_contract.mjs';
import { FIXTURE_CAPS } from './runtime_fixture_spec.mjs';
import { FINANCE_SCOPE, FINANCE_ACCOUNTS, FINANCE_JOURNALS, FINANCE_CALENDAR,
  FINANCE_COUNTS, FINANCE_EXPECTED, financeFixtureSql, validateFinanceFixture } from './finance_cash_fixture_20261013_r5.mjs';

// Independent public-source inspection and exact arithmetic only. This program
// cannot execute SQL, acquire sessions, read credentials or change acceptance.
const root = fileURLToPath(new URL('../../', import.meta.url));
const base = 'docs/verification/wave5/';
const attempt = process.argv[2];
if (!/^a[1-9][0-9]*$/.test(attempt ?? '') || process.argv.length !== 3) throw Error('EXACT_NEW_PEER_REVIEW_ATTEMPT_REQUIRED');
const prefix = base + `finance-cash-fixture-independent-peer-review-20261013-r5-${attempt}`;
const files = ['tools/wave5/review_finance_fixture_peer_20261013_r5.mjs',
  'tools/wave5/finance_cash_fixture_20261013_r5.mjs', 'tools/wave5/prepare_finance_fixture_20261013_r5.mjs',
  'tools/wave5/runtime_contract.mjs', 'tools/wave5/runtime_fixture_spec.mjs',
  base + 'complete-app-runtime-review-20261010-r5.json', base + 'runtime-owner-decision-20261012-r5.json',
  base + 'finance-cash-fixture-preparation-20261013-r5-a1.json',
  base + 'finance-cash-fixture-20261013-r5-a1-rollback.sql', base + 'finance-cash-fixture-20261013-r5-a1-commit.sql',
  'supabase/migrations/20260901090317_create_wave2_shared_foundation_schema.sql',
  'supabase/migrations/20260910135010_complete_delivery_receivables.sql',
  'supabase/migrations/20260930070000_wave4_synthetic_payroll.sql',
  'supabase/migrations/20261001110000_wave4_payroll_corrections.sql',
  'supabase/migrations/20261001100000_wave4_project_expenses_billing.sql',
  'supabase/migrations/20261008103000_wave5_dated_cash.sql',
  'supabase/migrations/20261008120000_wave5_cash_payment_dates.sql'];
const binding = async file => { const bytes = await fs.readFile(path.join(root, file));
  return { path: file, sha256: hashBytes(bytes), bytes: bytes.length }; };
const before = await Promise.all(files.map(binding));
const text = async file => fs.readFile(path.join(root, file), 'utf8');
const json = async file => JSON.parse(await text(file));
const review = await json(base + 'complete-app-runtime-review-20261010-r5.json');
const approval = await json(base + 'runtime-owner-decision-20261012-r5.json');
const plan = await json(base + 'finance-cash-fixture-preparation-20261013-r5-a1.json');
const rollback = await text(plan.rollback.path), commit = await text(plan.commit.path);
const checks = [];
const check = (name, fn) => { fn(); checks.push({ name, passed: true }); };
check('Frozen owner decision, exact runtime company and original scope', () => {
  assert.equal(approval.decision, 'approve'); assert.equal(approval.runtimeBundleSha256, review.bundleSha256);
  assert.equal(plan.projectId, review.projectId); assert.equal(plan.bundleSha256, review.bundleSha256);
  assert.equal(plan.operationScopeSha256, review.sourceContinuation.unchangedRuntimeOperationScopeSha256);
  assert.deepEqual(validateFinanceFixture(review), plan.fixture); assert.deepEqual(plan.fixture.scope, FINANCE_SCOPE);
});
for (const item of plan.sourceBindings) check('Exact generator binding: ' + item.path, () =>
  assert.equal(before.find(value => value.path === item.path)?.sha256, item.sha256));
check('Exact reviewed rollback bytes and source generation', () => {
  assert.equal(hashBytes(rollback), plan.rollback.sha256); assert.equal(rollback, financeFixtureSql());
});
check('Exact reviewed commit bytes and source generation', () => {
  assert.equal(hashBytes(commit), plan.commit.sha256); assert.equal(commit, financeFixtureSql({ commit: true }));
});
check('Rollback and commit differ only in final transaction decision', () => {
  assert.match(rollback, /\nROLLBACK;\n$/); assert.match(commit, /\nCOMMIT;\n$/);
  assert.equal(rollback.replace(/\nROLLBACK;\n$/, '\nCOMMIT;\n'), commit);
});
check('Immutable bounded counts remain inside existing approved caps', () => {
  assert.equal(Object.isFrozen(FINANCE_COUNTS), true); assert.equal(FINANCE_JOURNALS.length, 9);
  assert.equal(FINANCE_ACCOUNTS.length, 10); assert.equal(FINANCE_COUNTS.journalLines, 18);
  assert.ok(FINANCE_COUNTS.journals <= FIXTURE_CAPS.perTenant.postedJournals);
  assert.ok(FINANCE_COUNTS.journalLines <= FIXTURE_CAPS.perTenant.journalLines);
  assert.ok(FINANCE_COUNTS.openItems <= FIXTURE_CAPS.perTenant.openItems);
  for (const [key, maximum] of Object.entries(FIXTURE_CAPS.runtimeOnly)) assert.ok(FINANCE_COUNTS[key] <= maximum);
});
const units = value => { assert.match(value, /^-?\d+\.\d{6}$/); const negative = value.startsWith('-');
  const [whole, fraction] = value.replace(/^-/, '').split('.');
  return (BigInt(whole) * 1000000n + BigInt(fraction)) * (negative ? -1n : 1n); };
const decimal = value => (value < 0n ? '-' : '') + ((value < 0n ? -value : value) / 1000000n)
  + '.' + ((value < 0n ? -value : value) % 1000000n).toString().padStart(6, '0');
const balances = new Map(FINANCE_ACCOUNTS.map(account => [account.id, 0n]));
check('Nine distinct journals have exact two-sided positive six-place amounts', () => {
  assert.equal(new Set(FINANCE_JOURNALS.map(journal => journal.id)).size, 9);
  for (const journal of FINANCE_JOURNALS) {
    assert.ok(balances.has(journal.debit) && balances.has(journal.credit)); assert.notEqual(journal.debit, journal.credit);
    assert.ok(units(journal.amount) > 0n);
    if (journal.date <= FINANCE_CALENDAR.fixtureDay) {
      balances.set(journal.debit, balances.get(journal.debit) + units(journal.amount));
      balances.set(journal.credit, balances.get(journal.credit) - units(journal.amount));
    }
  }
  assert.equal([...balances.values()].reduce((sum, value) => sum + value, 0n), 0n);
});
const normal = key => { const account = FINANCE_ACCOUNTS.find(value => value.key === key);
  return balances.get(account.id) * (account.normal === 'debit' ? 1n : -1n); };
const revenue = normal('revenue'), expenses = normal('cost') + normal('expense'), netProfit = revenue - expenses;
const assets = normal('bank') + normal('inventory') + normal('receivable');
const liabilities = normal('payable') + normal('payroll') + normal('reimbursement'), equity = normal('equity');
const calculated = { revenue, expenses, netProfit, assets, liabilities, equity, currentEarnings: netProfit };
for (const [key, value] of Object.entries(calculated)) check('Independent statement arithmetic: ' + key, () =>
  assert.equal(decimal(value), FINANCE_EXPECTED[key]));
check('Independent accounting equation balances before the future reversal', () => assert.equal(assets, liabilities + equity + netProfit));
const issue = FINANCE_JOURNALS.find(value => value.key === 'payroll');
const settlement = FINANCE_JOURNALS.find(value => value.key === 'settlement');
const reversal = FINANCE_JOURNALS.find(value => value.key === 'future-reversal');
const openingPayroll = units(issue.amount) - units(settlement.amount);
const recovery = units(FINANCE_JOURNALS.find(value => value.key === 'recovery').amount);
const reimbursement = units(FINANCE_JOURNALS.find(value => value.key === 'reimbursement').amount);
const openingCash = normal('bank');
check('Opening and next-day payroll source amounts remain distinct', () => {
  assert.equal(decimal(openingPayroll), FINANCE_EXPECTED.payrollOpening);
  assert.equal(decimal(openingPayroll + units(reversal.amount)), FINANCE_EXPECTED.payrollAfterReversal);
  assert.equal(reversal.date, FINANCE_CALENDAR.horizonStart);
  assert.equal(decimal(-recovery), FINANCE_EXPECTED.recovery);
  assert.equal(decimal(reimbursement), FINANCE_EXPECTED.reimbursement);
});
const finalBalance = openingCash + normal('receivable') - normal('payable') - openingPayroll + recovery - reimbursement;
check('Independent dated cash and hypothetical balances use opening obligations', () => {
  assert.equal(decimal(openingCash), FINANCE_EXPECTED.openingCash);
  assert.equal(decimal(finalBalance), FINANCE_EXPECTED.cashFinalBalance);
  assert.equal(decimal(finalBalance + openingPayroll - units('6.000000')), FINANCE_EXPECTED.hypotheticalFinalBalance);
});
check('Collision stop and newly inserted-row-only updates precede mutations', () => {
  assert.ok(commit.indexOf('FINANCE_FIXTURE_COLLISION_INSPECT_ORIGINAL_IDS') < commit.indexOf('INSERT INTO crm.parties'));
  assert.match(commit, /pg_advisory_xact_lock/); assert.match(commit, /EXACT_FINANCE_FIXTURE_DAY_REQUIRED/);
  assert.match(commit, /SET CONSTRAINTS ALL IMMEDIATE/);
  assert.match(commit, /UPDATE finance\.journal_entries SET status='posted' WHERE tenant_id=t AND id=r\.id AND status='draft'/);
  assert.match(commit, /UPDATE people_payroll\.runs SET current_revision_id=/);
});
check('No account/role/approval/receipt fabrication or history bypass', () => {
  assert.doesNotMatch(commit, /\b(?:DELETE|TRUNCATE|ALTER|DISABLE)\b/i);
  assert.doesNotMatch(commit, /\b(?:INSERT INTO|UPDATE)\s+(?:auth\.|core\.(?:memberships|roles|role_permissions|role_assignments|permissions|command_receipts)|analytics\.cash_date_(?:proposals|decisions))/i);
  assert.doesNotMatch(commit, /approved_by|approved_digest|approved_revision_id/i);
  assert.match(commit, /synthetic_admin_finance_fixture/); assert.match(commit, /'userPosting',false,'operationalApproval',false/);
  assert.match(commit, /PROTECTED_OUTSIDE_FINANCE_SCOPE_CHANGED/); assert.match(commit, /FINANCE_FIXTURE_AUTHORITY_OR_CRM_CHANGED/);
  assert.equal(plan.actualRollbackExecuted, false); assert.equal(plan.actualCommitExecuted, false);
});
const datedSource = await text('supabase/migrations/20261008103000_wave5_dated_cash.sql');
const dateExtension = await text('supabase/migrations/20261008120000_wave5_cash_payment_dates.sql');
check('Source contract proves the same-day future-horizon blocker without a live call', () => {
  assert.ok(FINANCE_CALENDAR.horizonStart > FINANCE_CALENDAR.fixtureDay);
  assert.match(datedSource, /p_start::timestamptz>p_recorded_through/);
  assert.match(datedSource, /c\.updated_at>p_start::timestamptz/);
  assert.match(dateExtension, /api\.wave5_cash_basis_v2\(p_tenant_id,p_legal_entity_id,p_branch_id,p_start,p_end,p_recorded_through\)/);
  assert.match(dateExtension, /\(statement_timestamp\(\) at time zone 'UTC'\)::date\+1,statement_timestamp\(\)/);
});
const after = await Promise.all(files.map(binding)); assert.equal(hashJson(before), hashJson(after));
const report = { kind: 'independent-source-only-runtime-finance-fixture-review', observedAt: new Date().toISOString(),
  projectId: review.projectId, bundleSha256: review.bundleSha256, operationScopeSha256: plan.operationScopeSha256,
  fixtureVerdict: 'source-reviewed-for-exact-bounded-administration-fixture', wholeWorkflowVerdict: 'changes-required-before-current-day-cash-execution',
  checkCount: checks.length, checks, sourceBindings: after, sourceBindingsUnchanged: true,
  plan: after.find(value => value.path === base + 'finance-cash-fixture-preparation-20261013-r5-a1.json'),
  rollback: plan.rollback, commit: plan.commit, scope: FINANCE_SCOPE, counts: FINANCE_COUNTS,
  arithmetic: Object.fromEntries(Object.entries(calculated).map(([key, value]) => [key, decimal(value)])),
  openingCash: decimal(openingCash), openingPayroll: decimal(openingPayroll), nextDayCurrentPayroll: decimal(openingPayroll + units(reversal.amount)),
  cashFinalBalance: decimal(finalBalance), hypotheticalFinalBalance: decimal(finalBalance + openingPayroll - units('6.000000')),
  findings: [{ id: 'F-01', priority: 'blocking-current-day-cash-workflow', title: 'Future opening date is rejected by the actual source contract',
    source: 'supabase/migrations/20261008103000_wave5_dated_cash.sql', lines: [56, 59, 61],
    evidence: 'Oct14 opening is after any actual Oct13 recordedThrough and is rejected. Moving to Oct13 midnight instead predates the newly created mapping. The v3 extension delegates unchanged to v2.',
    remediation: 'Run independently valid financial statements, ratios and date approvals separately. Complete cash requires a real later observed clock and distinct current-source/opening-source payroll oracles, or an explicitly reviewed additive contract correction. Never backdate the mapping or fabricate future observedAt.' }],
  sourceFixtureIsAdministrative: true, operationalPayrollCalculationOrApprovalProved: false, genuineUserJournalPostingProved: false,
  actualRollbackObservedByPeer: false, actualCommitObservedByPeer: false, liveSqlCalls: 0, authWrites: 0, privateCredentialsRead: false,
  executedLive: false, providerNetworkCalls: 0, sdkJobs: 0, nativeActions: 0, ownerAcceptance: false,
  ownerAcceptedCriteria: 3, ownerCriteria: 109, production: false, realBilling: false,
  limitations: ['This peer checked public source and exact arithmetic, not actual PostgreSQL constraints or a live fixture result.',
    'The root must verify rollback/commit outcomes and protected-state hashes independently before claiming installed behavior.',
    'Admin-issued payroll/project source rows are explicitly synthetic and do not establish Wave4 user preparation, approval or posting.'] };
const bytes = JSON.stringify(report, null, 2) + '\n';
const markdown = `# Independent finance fixture source review — 2026-10-13\n\n${checks.length} source/arithmetic checks passed with unchanged hashes. The exact nine-journal, eighteen-line administration fixture is bounded by the existing approval. Actual rollback/commit verification remains root-owned.\n\nThe current-day complete cash workflow needs correction: the frozen Oct14 horizon is later than the real Oct13 recorded-through clock, which v2 rejects. Oct13 midnight would predate the new cash mapping. V3 delegates to v2 unchanged. Keep real timestamps; execute independent statements, ratios and genuine payment-date approvals separately.\n\nThe statement arithmetic balances: revenue ${decimal(revenue)}, expenses ${decimal(expenses)}, profit ${decimal(netProfit)}, assets ${decimal(assets)}, liabilities ${decimal(liabilities)}, equity ${decimal(equity)}. Opening cash is ${decimal(openingCash)}. Payroll opening ${decimal(openingPayroll)} is distinct from the next-day current-source ${decimal(openingPayroll + units(reversal.amount))}; the future reversal becomes effective on Oct14.\n\nExact fixture plan SHA-256: ${report.plan.sha256}. Commit SQL: ${plan.commit.sha256}. Rollback SQL: ${plan.rollback.sha256}. No Auth rows, role grants, approved-by/digest fields or cash-date decision rows are inserted; constraints stay enabled. Existing rows collision-stop before mutation and outside-scope/authority hashes must stay unchanged.\n\nThis is source-only administration-fixture review. It does not prove user journal posting, operational payroll calculation/approval, actual SQL execution, native acceptance, delivery, load or owner signoff. Acceptance remains 3/109.\n`;
await fs.writeFile(path.join(root, prefix + '.json'), bytes, { flag: 'wx' });
await fs.writeFile(path.join(root, prefix + '.md'), markdown, { flag: 'wx' });
process.stdout.write(JSON.stringify({ path: prefix + '.json', sha256: hashBytes(bytes), markdown: prefix + '.md',
  markdownSha256: hashBytes(markdown), checks: checks.length, fixtureVerdict: report.fixtureVerdict,
  wholeWorkflowVerdict: report.wholeWorkflowVerdict, liveSqlCalls: 0 }) + '\n');
