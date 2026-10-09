import { createHash } from 'node:crypto';
import { readFile, writeFile } from 'node:fs/promises';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { sources } from './cash_ui_evidence.mjs';

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../..');
const base = 'docs/verification/wave5/';
const read = p => readFile(path.join(root, p), 'utf8');
const json = async p => JSON.parse(await read(p));
const write = (p, text) => writeFile(path.join(root, p), `${text.trimEnd()}\n`);
const writeJson = (p, value) => write(p, JSON.stringify(value, null, 2));
const sha = value => createHash('sha256').update(value).digest('hex');
const now = new Date().toISOString();
const reportPath = `${base}cash-dates-verification-20261008.json`;
const reportMd = `${base}cash-dates-verification-20261008.md`;
const reviewPath = `${base}cash-dates-review-20261008.json`;
const reviewMd = `${base}cash-dates-review-20261008.md`;
const migration = 'supabase/migrations/20261008120000_wave5_cash_payment_dates.sql';
const contract = 'docs/blueprint/wave5/W5_CASH_PAYMENT_DATES_CONTRACT.md';
const hashPath = `${base}cash-dates-candidate-20261008.hashes.json`;
const resultPath = `${base}cash-dates-candidate-result-20261008.json`;

// Connector data is inspected as data only. Some envelopes encode their row JSON twice.
function rows(envelope) {
  if (envelope.isError) throw Error('Connector returned an error');
  const text = JSON.parse(envelope.content.find(x => x.type === 'text').text).result;
  let section = text.slice(text.indexOf('[{'), text.lastIndexOf('}]') + 2);
  for (let attempt = 0; attempt < 3; attempt++) {
    try { return JSON.parse(section); } catch {
      section = section.replaceAll('\\"', '"').replaceAll('\\\\', '\\');
    }
  }
  throw Error('Cannot decode connector evidence rows');
}
const report = await json(reportPath);
if (!report.current_source_match || !report.buildSucceeded || report.frames.length !== 60 || !report.visualReview.passed ||
    JSON.stringify(await sources(root)) !== JSON.stringify(report.sourceHashes)) throw Error('Current SDK/source evidence is incomplete');
if (report.authenticatedAcceptance || report.ownerAccepted || report.nativeLaunched || report.localStoresIncluded || report.goldenFilesRegenerated) throw Error('Evidence boundaries changed');
for (const stage of Object.values(report.stages)) {
  if (!stage.passed || stage.exitCode !== 0 || sha(await readFile(path.join(root, stage.log))) !== stage.logSha256) throw Error('SDK log changed or stage failed');
}
for (const frame of report.frames) if (sha(await readFile(path.join(root, frame.path))) !== frame.sha256) throw Error('Frame changed');
if (sha(await readFile(report.executable)) !== report.executableSha256) throw Error('Executable changed');
const hashes = await json(hashPath), result = await json(resultPath);
if (!hashes.actualWave4Schemas || !hashes.strictFinish || !hashes.rollback || hashes.installed || hashes.installedMigrationsReplayed ||
    result.assertions !== 35 || !result.strictFinish || !result.rollback || !result.actualWave4Schemas || result.installed) throw Error('Strict SQL gates do not match');
const tap = rows(result.result)[0].tap;
if (tap.length !== 35 || tap.some((line, i) => !line.startsWith(`ok ${i + 1} - `))) throw Error('Strict SQL assertions failed');
for (const [file, hash] of Object.entries(hashes.migrationSources)) if (sha(await readFile(path.join(root, file))) !== hash) throw Error(`Migration source changed: ${file}`);
for (const [file, hash] of [[hashes.fixture, hashes.fixtureSha256], [hashes.w4Fixture, hashes.w4FixtureSha256], [`${base}cash-dates-candidate-20261008.sql`, hashes.querySha256]]) {
  if (sha(await readFile(path.join(root, file))) !== hash) throw Error(`SQL composition changed: ${file}`);
}
const w4 = await json(`${base}cash-dates-wave4-source-baseline-20261008.json`);
for (const [file, hash] of Object.entries(w4.sources)) if (hashes.migrationSources[file] !== hash || sha(await readFile(path.join(root, file))) !== hash) throw Error('Wave 4 source bytes changed');
const before = rows(await json(`${base}cash-dates-catalog-before-20261008.json`))[0];
const after = rows(await json(`${base}cash-dates-catalog-after-20261008.json`))[0];
for (const key of Object.keys(before).filter(k => k !== 'checked_at')) if (before[key] !== after[key]) throw Error(`Installed catalog changed: ${key}`);
if (after.migration_count !== 43 || after.api_functions !== 107 || after.cash_dates || after.cash_scenarios || after.payroll || after.reimbursements || after.fixture_tenants || after.fixture_accounts) throw Error('Live baseline differs');
const finalRead = rows((await json(`${base}cash-dates-live-final-20261008.json`)).result)[0];
for (const key of Object.keys(finalRead).filter(k => !['checked_at', 'cash_date_decisions'].includes(k))) if (finalRead[key] !== after[key]) throw Error(`Final live state drifted: ${key}`);
if (finalRead.cash_date_decisions) throw Error('Date decisions unexpectedly installed');
const domain = report.stages.domainTests.assertions, platform = report.stages.platformTests.assertions, native = report.stages.nativeTests.assertions;
const description = `Current-source scoped Dart analysis is clean; ${domain} domain, ${platform} platform and ${native} desktop/controller/render tests pass. The Windows release matches all ${report.sourceFileCount.toLocaleString('en-US')} selected source files and ${report.releaseFileCount} release files. Twelve cash variants cover 1024x720, 1440x900 and 1920x1080, both themes/densities and 200% text. Sixty fresh top/provider/lower/date/approval frames were captured; ${report.visualReview.inspectedFrames.length} were visually inspected, including approval in all twelve variants. Initial Tab focus was checked. These are controlled development renders and tests; authenticated native acceptance and complete keyboard navigation remain open.`;
const sql = await read(migration);
const apiFunctions = [...sql.matchAll(/create function (api\.\w+)\(([\s\S]*?)\) returns (\w+)/g)].map(m => ({ name: m[1], arguments: m[2].replace(/\s+/g, ' ').trim(), returns: m[3] }));
const review = {
  capturedAt: now, project: 'xpdoufauvrbdmxgngetv', state: 'uninstalled review only', installationAuthorized: false,
  migration: { path: migration, sha256: hashes.migrationSources[migration], apiFunctions, tables: ['analytics.cash_date_proposals', 'analytics.cash_date_decisions'],
    newPermissions: ['analytics.cash_dates.prepare', 'analytics.cash_dates.approve'], forcedRls: true, directClientTableGrants: false },
  contract, calculationRevision: 'dated_transaction_cash_all_obligations.v3', requiredProviders: ['bank_cash', 'receivables', 'payables', 'payroll', 'project_reimbursements'],
  migrationPrerequisites: Object.entries(hashes.migrationSources).filter(([p]) => !p.includes('_wave4_') && p !== migration).map(([path, sha256]) => ({ path, sha256, installed: false })),
  optionalWave4SourceDependencies: Object.entries(w4.sources).map(([path, sha256]) => ({ path, sha256, installed: false, unchanged: true })),
  verificationComposition: { sourceCount: Object.keys(hashes.migrationSources).length, querySha256: hashes.querySha256, sourceHashes: hashPath, result: resultPath,
    assertions: 35, strictFinish: true, rolledBack: true, actualWave4Schemas: true, wave4ShapeShims: false,
    scope: 'New dates, actual payroll/correction/reimbursement sources, frozen cash and governed projection; AR/AP empty in this composition.' },
  previousEightFileComposition: { review: `${base}continuation-review-20261008.md`, assertions: 116, installed: false,
    scope: 'Separate unchanged composition including nonempty AR/AP and a rolled-back allocation-reversal shape shim.' },
  live: { before, after, finalRead, finalReadEvidence: `${base}cash-dates-live-final-20261008.json`, unchanged: true, installedChecksRerun: false },
  sdk: { evidence: reportPath, domain, platform, native, sourceMatch: true, build: true, frames: 60, inspectedFrames: report.visualReview.inspectedFrames.length },
  authorizationEffects: { rolesAssigned: false, entitlementsActivated: false, tenantsBootstrapped: false, testAccountsCreated: false, secretsProvisioned: false, workersDeployed: false, externalDelivery: false },
  remainingGates: ['Exact new/prerequisite installation review and installed verification', 'Separate synthetic identity/role/entitlement review', 'Real distinct MFA sessions and independent contention', 'Authenticated native restart/revocation/export/keyboard', 'Actual workers/model/delivery, target-scale load and owner acceptance'],
  wholeWaveComplete: false, ownerAccepted: false
};
await writeJson(reviewPath, review);
const links = Object.entries(hashes.migrationSources).map(([file, hash]) => `| [${path.basename(file)}](${path.posix.relative(base, file)}) | ${file.includes('_wave4_') ? 'Optional, separately owned Wave 4 source' : file === migration ? 'New Wave 5 candidate' : 'Uninstalled Wave 3/5 prerequisite'} | \`${hash}\` |`);
await write(reviewMd, [
  '# Cash payment-date contract review - October 8, 2026', '',
  'The implemented candidate gives issued payroll, signed payroll recoveries and approved project reimbursements authoritative payment dates through an immutable, independently MFA-reviewed Wave 5 registry. It reads Wave 4 balances and journals without changing their stores, functions or source files. **No new migration is installed or authorized by this review.**', '',
  `The new file is [${path.basename(migration)}](${path.posix.relative(base, migration)}), SHA-256 \`${hashes.migrationSources[migration]}\`. The [contract](${path.posix.relative(base, contract)}) defines source authority, signed residuals, approval, recovery and full-provider semantics.`, '',
  '## Concrete installation effects', '',
  'The candidate adds two immutable forced-RLS tables with direct client access revoked, two privileged permission definitions and four authenticated date APIs: authorize, bounded source list, proposal read and command. It wraps cash basis/save/get and governed export calculation with revision 3, revoking callable legacy aliases. Role permissions and plan entitlements are not assigned. A source-scoped proposer and a distinct current MFA approver must bind the original source fingerprint, exact proposal digest and expected approved version; serialized approvals reject stale versions.', '',
  'Revision 3 requires bank cash, receivables, payables, payroll and project reimbursements. Missing dates withhold the entire family; absent source contracts remain source_not_installed. Negative payroll corrections become exact recovery inflows. Revision 2 frozen scenarios retain their historical, partial bank/AR/AP scope. Current source access is rechecked for frozen reopen and governed export. Encrypted recovery preserves the original command identity and timestamp in separate actor/scope/source-kind slots.', '',
  '## Dependency and ownership boundary', '',
  'The 14-file table below describes the rollback verification composition, not an installation request. The five Wave 3/5 prerequisites are uninstalled. Wave 4 is optional at installation but required for live payroll, correction and reimbursement coverage; its eight source hashes and original synthetic fixture are unchanged. The original six installed Wave 5 migrations are excluded and must never be replayed. Any later installation plan needs a fresh ledger/dependency review with the relevant Wave 3/4 owners.', '',
  '| Source | Relationship | SHA-256 |', '|---|---|---|', ...links, '',
  `All 35 new strict checks passed with finish(true), followed by rollback. Query SHA-256 is \`${hashes.querySha256}\`. The test uses the actual Wave 4 schemas and no Wave 4 shape shims. It covers signed residuals and effective reversal dates, undated-family rejection, five-provider freeze/export parity, exact retries, independent-actor policy, MFA/revocation and immutable decisions. AR/AP are empty in this fixture; the earlier unchanged 116-check composition retains its separate nonempty allocation/reversal evidence and test-only reversal shape shim. Injected claims and sequential competing proposals do not prove real MFA or overlapping sessions.`, '',
  `The [before](cash-dates-catalog-before-20261008.json) and [after](cash-dates-catalog-after-20261008.json) live reads show 43 migrations and 107 API functions with unchanged ledger/provider hashes, 87 role permissions, one role assignment, 28 entitlements and one membership. The new date/scenario tables and Wave 4 payroll/reimbursement sources remain absent; fixture tenant/account counts are zero. The original 126 installed SQL checks are historical installation evidence and were not rerun here.`, '',
  `The [final read-only refresh](cash-dates-live-final-20261008.json) at ${finalRead.checked_at} confirms the same ledger/API/access counts and absent date/scenario/payroll/reimbursement stores after final SDK verification.`, '',
  '## Current development verification', '', description, '',
  '[Current SDK/build/render evidence](cash-dates-verification-20261008.md) and [strict SQL result](cash-dates-candidate-result-20261008.json). The earlier platform fixture failure and pre-final native logs are preserved. The 13 shared dashboard/setup golden failures remain open; no approved golden was regenerated.', '',
  '## Separate remaining approvals and evidence', '',
  'Before installation, review the exact new file and its dependency closure; this does not enlarge the previous six-file approval or reverse the decision to keep the earlier eight candidates uninstalled. Synthetic identity/role/entitlement setup, secrets, worker deployment and external delivery each need their own concrete review. Real authenticated proposer/approver sessions, native restart/revocation/export/keyboard, actual worker/model delivery, independent contention, target-scale load and owner acceptance remain open. Real billing and production remain excluded. Wave 5 remains incomplete.', '',
  '[Machine-readable review](cash-dates-review-20261008.json).'
].join('\n'));
await write(reportMd, [
  '# Cash dates: current-source verification - October 8, 2026', '', description, '',
  `Flutter ${report.sdk.flutter}, Dart ${report.sdk.dart}; framework \`${report.sdk.frameworkRevision}\`, engine \`${report.sdk.engineRevision}\`. All SDK jobs were serialized against \`${report.snapshot}\`; the selected-source hash inventory matches the final workspace. Acceptance stores were excluded and the executable was not launched.`, '',
  `The release has ${report.releaseFileCount} hashed files. Executable SHA-256: \`${report.executableSha256}\`. [Machine-readable source/build/frame attribution](cash-dates-verification-20261008.json).`, '',
  '## Evidence scope', '',
  '- The separate new SQL composition passes 35 strict rollback-only checks using actual Wave 4 payroll/correction/reimbursement schemas; no additional migration or test identity persists.',
  '- The 72 domain, 48 platform and 96 desktop counts are the focused analytics and three desktop suites shown in the recorded commands. Platform recovery closes/reopens an encrypted synthetic database; controller recreation is not an authenticated Windows process restart.',
  '- Cash render fixtures include five obligation rows and all five families. Exact closing cash is 4.000003; the separate SQL fixture has an empty bank opening and empty AR/AP, so its governed closing cash is -8.999999. Both are exact six-place calculations over different fixture inputs.',
  '- Sixty frames were produced; sixteen inspected frames include all twelve approval variants and four top/provider views. Digest wrapping, scrolled date/approval controls and exact projection are readable at 200% text. No complete keyboard or owner acceptance claim is made.',
  '- The original 126 installed checks and unchanged earlier 116-candidate composition retain their own scope. The prior 31 controlled worker checks were not rerun; no real worker/model delivery, independent contention or target-scale load occurred.',
  '- Three new platform tests initially failed on a loosely typed fixture map. The fixture was corrected and the complete final snapshot rerun; [failed log](cash-dates-platform-tests-attempt1-20261008.log) and [pre-final native log](cash-dates-native-tests-before-final-fixture-20261008.log) are preserved.', '',
  'The 13 shared dashboard/setup golden failures remain unresolved and approved goldens were preserved. The original cash UI proof is historical for the earlier source. [Concrete date-contract review](cash-dates-review-20261008.md). Wave 5 remains incomplete.'
].join('\n'));

const matrixPath = `${base}requirement-matrix-20261008.json`, matrixMd = `${base}requirement-matrix-20261008.md`;
const matrix = await json(matrixPath), text = await read(matrixMd);
const titles = Object.fromEntries([...text.matchAll(/<a id="evidence-([^"]+)"><\/a>\s*## ([^\n]+)/g)].map(m => [m[1], m[2].trim()]));
if (matrix.rows.length !== 109 || new Set(matrix.rows.map(x => x.id)).size !== 109 || matrix.rows.some(x => x.ownerAccepted)) throw Error('Requirement identities changed');
const updates = {
  cash: ['Uninstalled candidates now cover all five cash families, authoritative independently reviewed payroll/correction/reimbursement payment dates, exact residuals, immutable scenarios, encrypted recovery and governed export. New actual-Wave-4 SQL checks and current SDK/build/render verification pass.',
    'Exact new/prerequisite installation and installed provider checks remain open. Real authenticated date proposal/independent MFA approval, scenarios/export bytes/download/reopen, native process restart, revocation and owner acceptance remain unproved.'],
  native: [`Seven analytics workspaces and the cash payment-date section are implemented; ${native} current desktop/controller/render tests pass. Twelve cash variants include date and exact-proposal approval controls; current Windows compilation matches source.`,
    'Real authenticated native launch/restart, delayed revocation, exported bytes/download/reopen, complete keyboard navigation and owner review remain open. Initial Tab focus and controlled renders do not close those gates. The 13 shared golden failures remain unresolved.'],
  provider: ['Historical CRM, realized results, statement classifications, all-five-family cash/date sources, scenario/export, persistent integration and trusted-usage adapters are implemented as uninstalled candidates.',
    'Source/dependency installation and authenticated provider/cache behavior remain open. Unavailable-provider cards and injected policy tests do not establish completed runtime features.'],
  ownership: ['The six approved migrations remain installed: 43 ledger entries and 107 API functions. Ledger/provider hashes and role/entitlement/membership counts match before/after the date tests. Eight Wave 4 source hashes are preserved; the new date candidate and earlier eight-file review remain uninstalled.',
    'Keep candidates uninstalled under the existing owner decision. Review the new date file, optional Wave 4 sources and Wave 3/5 prerequisites before any installation; preserve acceptance stores and never replay the six connector-mapped migrations.'],
  quality: [`The unchanged earlier composition passes 116 rollback checks; the new actual-Wave-4 date composition separately passes 35. Current scoped analysis is clean and ${domain} domain/${platform} platform/${native} desktop tests pass. Windows source attribution and 60 current cash frames are recorded; 16 frames were inspected. The previous 31 controlled worker checks retain their scope.`,
    'The original 126 installed SQL checks were not rerun. Keep 13 shared golden failures visible; no approved golden was regenerated. Real MFA/native/export, worker/model delivery, privacy acceptance, independent contention, target-scale load and owner signoff remain open.']
};
const extra = [contract, migration, hashes.fixture, resultPath, hashPath, reviewPath, reviewMd, reportPath, reportMd, `${base}cash-dates-catalog-after-20261008.json`];
for (const row of matrix.rows) if (updates[row.bundle]) {
  [row.developmentStatus, row.remaining] = updates[row.bundle];
  row.evidence = [...new Set([...row.evidence, ...extra])];
}
Object.assign(matrix, { updatedAt: now, wholeWaveComplete: false, ownerAcceptedCriteria: 0, cashDatesContractImplemented: true, cashDatesInstalled: false, fullCashProviderInstalled: false, cashDatesReview: reviewMd });
Object.assign(matrix.continuationChecks, { candidateSql: 116, cashDatesCandidateSql: 35, cashDatesCandidateSqlScope: 'Separate rollback-only actual-Wave-4 date composition', domainLastVerified: domain, platformLastVerified: platform, nativeLastVerified: native,
  platformAndNativeCurrentSource: true, analyzerCurrentSource: true, windowsBuildCurrentSourceMatch: true, currentCashRenderAvailable: true, cashUiVerification: reportPath,
  historicalCashUiVerification: `${base}cash-ui-verification-20261008.json`, analyzerScope: report.stages.analyzer.command, testScope: 'Wave 5 analytics package suites plus process_metric_workspace/wave5_workspaces/wave5_continuation desktop suites' });
await writeJson(matrixPath, matrix);
const lines = ['# Wave 5 requirement matrix - October 8, 2026', '',
  'All 109 approved identifiers remain mapped, with zero owner-accepted criteria. The fresh before/after catalog and final read remain 43 installed migrations and 107 API functions; new cash/date tables and payroll/reimbursement sources remain absent. The original installation report holds 126 installed SQL checks. The earlier eight-file composition retains 116 strict rollback checks; the new actual-Wave-4 date composition separately passes 35. All candidates remain uninstalled. [Final live read](cash-dates-live-final-20261008.json), [original eight-file review](continuation-review-20261008.md) and [new date review](cash-dates-review-20261008.md).', '',
  `${description} [Current verification](cash-dates-verification-20261008.md). Actual delivery, independent contention, target-scale load and owner signoff remain open; installed full cash coverage remains incomplete.`, '',
  '| ID | Evidence bundle | Current status |', '|---|---|---|'];
for (const row of matrix.rows) lines.push(`| ${row.id} | [${titles[row.bundle]}](#evidence-${row.bundle}) | ${row.developmentStatus} |`);
for (const [bundle, title] of Object.entries(titles)) {
  const rs = matrix.rows.filter(r => r.bundle === bundle);
  if (!rs.length) throw Error(`Empty evidence bundle: ${bundle}`);
  lines.push('', `<a id="evidence-${bundle}"></a>`, `## ${title}`, '', rs[0].developmentStatus, '', `Remaining: ${rs[0].remaining}`, '', 'Evidence:', '');
  for (const file of [...new Set(rs.flatMap(r => r.evidence))]) lines.push(`- [${file}](${path.posix.relative(base, file)})`);
}
await write(matrixMd, lines.join('\n'));

const statusPath = 'docs/development/wave5-status.md';
let status = (await read(statusPath)).replace(/\r\n/g, '\n');
status = status.replace('The [fresh read-only connector refresh](../verification/wave5/live-refresh-confirmed-20261008.json) confirms 43 ledger entries and 107 API functions; the eight review migrations and new dated-cash table are absent.',
  'The [fresh before/after live catalog](../verification/wave5/cash-dates-catalog-after-20261008.json) remains 43 ledger entries and 107 API functions with unchanged provider/ledger hashes and role/entitlement/membership counts. The earlier eight review migrations, new date/scenario tables and Wave 4 payroll/reimbursement sources remain absent.');
status = status.replace('| W5-03 Ratios and cash | Six named statement ratios; dated bank and permission-gated AR/AP residuals with allocations/reversals; immutable scenario assumptions/overrides, encrypted recovery and governed export source/reopen paths | W3 statement/export dependencies and six W5 candidates remain uninstalled. Payroll and project-reimbursement providers lack authoritative payment due dates, so full cash is incomplete. Real authenticated statement/export and native acceptance remain open |',
  '| W5-03 Ratios and cash | Six named ratios; all-five-family dated cash with independent MFA-reviewed payroll/correction/reimbursement dates, immutable source balances/scenarios, encrypted recovery and governed export | New date and earlier W3/5 candidates remain uninstalled; optional Wave 4 payroll/reimbursement dependencies are absent live. Installed/authenticated dates, statements, scenarios/exports and native acceptance remain open |');
status = status.replace('116 strict rollback candidate checks; 109 requirement IDs retained', '116 earlier candidate checks and 35 separate actual-Wave-4 date checks; 109 requirement IDs retained');
status = status.replace('The current candidate composition is the two separately owned Wave 3 prerequisites followed by six additive Wave 5 migrations.', 'The earlier eight-file candidate composition is the two separately owned Wave 3 prerequisites followed by six additive Wave 5 migrations.');
status = status.replace('No candidate was installed and no Wave 3/4 source was replayed.', 'No candidate was installed and no installed Wave 3/4 migration was replayed.');
status = status.replace(/The dated-cash adapter now includes[\s\S]*?no goldens were regenerated\./,
  `The [new payment-date contract](../blueprint/wave5/W5_CASH_PAYMENT_DATES_CONTRACT.md) and [uninstalled review](../verification/wave5/cash-dates-review-20261008.md) implement immutable independent review over actual Wave 4 payroll, signed correction and reimbursement sources. All 35 strict date/source checks passed in rollback using unchanged Wave 4 source bytes; effective settlement/reversal dates, missing-date completeness, version contention policy and governed export parity are covered. The date registry does not change Wave 4 stores or infer due dates from journal/service/milestone dates. Installed full cash coverage remains incomplete.\n\n${description} The prior 31 controlled worker checks retain their scope. [Current cash/date verification](../verification/wave5/cash-dates-verification-20261008.md) replaces the earlier cash UI proof for current source. The 13 shared dashboard/setup golden failures remain open; no goldens were regenerated.`);
await write(statusPath, status);

const protocolPath = `${base}integrated-runtime-protocol-20261006.md`;
let protocol = (await read(protocolPath)).replace(/\r\n/g, '\n');
if (!protocol.includes('[new payment-date composition]')) protocol = protocol.replace('Injected claims/transports remain development evidence.', 'The [new payment-date composition](cash-dates-review-20261008.md) separately passes 35 strict checks against actual Wave 4 schemas, with before/after catalog hashes and counts unchanged. It also remains uninstalled. Injected claims/transports remain development evidence.');
protocol = protocol.replace(/Full cash forecasting still needs[\s\S]*?No projection may claim full coverage while a required family is unavailable\./,
  'The [additive Wave 5 payment-date contract](../../blueprint/wave5/W5_CASH_PAYMENT_DATES_CONTRACT.md) now implements authoritative payroll, signed correction recovery and project-reimbursement dates without changing Wave 4 stores. Five-provider revision 3 requires every source family and reviewed dates, computes exact immutable residuals at effective journal/recorded cutoffs, and rechecks all source permissions on scenario/export reopen. Missing/uninstalled/denied families never certify partial cash as complete. The 35-check actual-Wave-4 fixture has empty AR/AP; the earlier 116-check composition retains its separate nonempty AR/AP/reversal-shim scope.\n\nAll new dates and their dependencies remain uninstalled. Before runtime, review the exact date candidate and Wave 3/5 prerequisites plus optional Wave 4 sources; do not replay the original six migrations. Use distinct real MFA proposer/approver sessions to create and approve the exact source/proposal digest, reject self/aal1 approval, revise with monotonic versions, preserve rejected dates, and verify late/missing dates, signed recovery, settlement/reversal cutoffs, foreign branches and revocation on freeze/export/reopen. Race competing versions through a barrier and record overlapping sessions; sequential rollback commands do not close contention.');
protocol = protocol.replace(/Current-source Dart analysis is clean;[\s\S]*?Earlier worker, coverage and privacy scans retain their original scope\./,
  `${description} [Current verification](cash-dates-verification-20261008.md). The 13 shared dashboard/setup golden failures remain unresolved; approved goldens were preserved. Earlier worker, coverage and privacy scans retain their original scope.`);
await write(protocolPath, protocol);

// Preserve the earlier eight-file source review while making its SDK freshness explicit.
const previousReviewMd = `${base}continuation-review-20261008.md`, previousReviewJson = `${base}continuation-review-20261008.json`;
let oldText = (await read(previousReviewMd)).replace(/\r\n/g, '\n');
if (!oldText.includes('## Later cash-date implementation')) oldText += '\n## Later cash-date implementation\n\nThe eight migration source hashes and 116-check SQL composition above are unchanged. The SDK figures and cash-provider limits in this earlier review describe the source at that verification. The later additive [payment-date review](cash-dates-review-20261008.md) implements payroll/correction/reimbursement dates while preserving Wave 4 sources, and [current SDK verification](cash-dates-verification-20261008.md) supersedes the earlier cash UI proof. All additional candidates remain uninstalled.\n';
oldText = oldText.replace('- Current-source Dart analysis is clean; 71 domain, 42 platform and 94 desktop/controller/render tests pass.', '- At the earlier source snapshot, scoped Dart analysis was clean and 71 domain, 42 platform and 94 desktop/controller/render tests passed.');
oldText = oldText.replace('- The current SDK rerun passed 71 domain/42 platform/94 desktop checks,', '- The earlier SDK rerun passed 71 domain/42 platform/94 desktop checks,');
await write(previousReviewMd, oldText);
const oldReview = await json(previousReviewJson);
oldReview.sdkEvidenceCurrentSource = false;
oldReview.sdkEvidenceStatus = 'Historical earlier source; superseded by current cash-date verification';
oldReview.cashDatesReview = reviewMd;
oldReview.currentCashDatesSdkEvidence = reportPath;
oldReview.evidenceHashesMeaning = 'Historical hash inventory from the earlier eight-file review; current SDK evidence is separately hash-bound in the cash-date report';
if (oldReview.currentSourceSdkEvidence) Object.assign(oldReview.currentSourceSdkEvidence, { currentSource: false, historical: true });
if (oldReview.developmentChecks) Object.assign(oldReview.developmentChecks, { platformAndNativeCurrentSource: false, buildSourceMatches: false });
await writeJson(previousReviewJson, oldReview);

const summaryPath = `${base}continuation-evidence-summary-20261008.json`, summary = await json(summaryPath);
Object.assign(summary, { updatedAt: now, liveStateCheckedAt: finalRead.checked_at, finalLiveEvidence: `${base}cash-dates-live-final-20261008.json`, candidateSqlAssertions: 116, cashDatesCandidateSqlAssertions: 35,
  cashDatesContractImplemented: true, cashDatesInstalled: false, cashDatesReview: reviewMd, fullCashProviders: false, fullCashProviderMeaning: 'Installed authenticated full coverage', payrollProjectPaymentDueDates: false, payrollProjectPaymentDueDatesMeaning: 'Installed authoritative provider dates; candidate implementation is separately true',
  domainLastVerified: domain, platformLastVerified: platform, nativeLastVerified: native, platformEvidenceCurrentSource: true, nativeEvidenceCurrentSource: true,
  analyzerCurrentSource: true, windowsBuildCurrentSourceMatch: true, currentCashRenderAvailable: true, cashUiVerification: reportPath,
  historicalCashUiVerification: `${base}cash-ui-verification-20261008.json`, sdkEvidenceScope: matrix.continuationChecks.testScope,
  authenticatedNative: false, actualDelivery: false, contention: false, load: false, ownerAccepted: 0, wholeWaveComplete: false, newCandidatesInstalled: false });
for (const file of [matrixPath, matrixMd, statusPath, protocolPath, previousReviewMd, previousReviewJson, reviewPath, reviewMd, reportPath, reportMd, hashPath, resultPath, `${base}cash-dates-catalog-before-20261008.json`, `${base}cash-dates-catalog-after-20261008.json`, `${base}cash-dates-live-final-20261008.json`]) {
  summary.evidenceHashes[path.basename(file)] = sha(await readFile(path.join(root, file)));
}
await writeJson(summaryPath, summary);
console.log(JSON.stringify({ sql: 35, domain, platform, native, frames: 60, sourceMatch: true, wave4SourcesUnchanged: 8, ledgerUnchanged: true, requirementRows: matrix.rows.length, installed: false, ownerAccepted: 0 }));
