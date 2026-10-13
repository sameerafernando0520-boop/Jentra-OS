// Exact approved migration continuation. Import/default validation do no network I/O.
import fs from 'node:fs/promises';
import path from 'node:path';
import https from 'node:https';
import { fileURLToPath } from 'node:url';
import { isDeepStrictEqual as equal } from 'node:util';
import { hashBytes, validateRuntimeReview, validateApproval } from './runtime_contract.mjs';

export const PROJECT = 'xpdoufauvrbdmxgngetv';
export const ORGANIZATION = 'kuzlgtbvfmxqcodmicoy';
export const BUNDLE = 'db525758554036fa99ec02d00c85bd8401ef7ebce787e2a983db1c69a08baf7b';
const ROOT = fileURLToPath(new URL('../../', import.meta.url));
const BASE = 'docs/verification/wave5/';
const REVIEW = BASE + 'complete-app-runtime-review-20261010-r5.json';
const REVIEW_SHA = 'b1b0cb94a8aa705b5cc6ff674ed215a8487a960ff0a594f7abffadfbc4e57cc3';
const OWNER = BASE + 'runtime-owner-decision-20261012-r5.json';
const OWNER_SHA = '90daa67a459bd985a1bec824bf0e8e09bf69537c2febdae85238336604c655ab';
const INITIAL = BASE + 'approved-live-resume-20261013-r5-raw.json';
const INITIAL_SHA = 'a9b230d68d85ad222853abcb06e28003b703c9a06b3b715172db681a849b9235';
const PREFLIGHT = BASE + 'complete-live-preflight-20261010-r2.sql';
const PREFLIGHT_SHA = 'cf886dbb2fac359b530626b50d99312c14b5398a7d620b22100852154594e250';
const RENAMES = BASE + 'installed-baseline-rename-fingerprints-20261012-r5.sql';
const RENAMES_SHA = 'f4beb12842047ebf0ab8892155c092b1bf357ec27b044be62796bd4f81579b0a';
const FIRST = Object.freeze({ version: '20261012093803', name: 'product_unit_conversions' });
const must = (test, code) => { if (!test) { const error = new Error(code); error.publicCode = code; throw error; } };

export function decodePublicResult(value) {
  if (typeof value === 'string') {
    let json;
    try { json = JSON.parse(value); } catch {
      const match = value.match(/(?:^|\n)<untrusted-data-([a-zA-Z0-9-]+)>\r?\n([\s\S]*?)\r?\n<\/untrusted-data-\1>(?:\n|$)/);
      must(match, 'PUBLIC_DATA_BOUNDARY_REQUIRED'); return JSON.parse(match[2]);
    }
    return decodePublicResult(json);
  }
  must(value?.isError !== true, 'CONNECTOR_BASELINE_ERROR');
  if (value?.rawConnectorResult) return decodePublicResult(value.rawConnectorResult);
  if (Array.isArray(value?.content)) {
    const text = value.content.filter(item => item.type === 'text');
    must(text.length === 1, 'ONE_PUBLIC_RESULT_REQUIRED'); return decodePublicResult(text[0].text);
  }
  if (typeof value?.result === 'string') return decodePublicResult(value.result);
  return value;
}

export function normalizeLedger(rows) {
  must(Array.isArray(rows), 'LEDGER_ARRAY_REQUIRED');
  const result = rows.map(row => {
    must(typeof row?.version === 'string' && /^[0-9]{14}$/.test(row.version)
      && typeof row.name === 'string' && /^[a-z][a-z0-9_]*$/.test(row.name), 'LEDGER_ENTRY_INVALID');
    return { version: row.version, name: row.name };
  }).sort((a, b) => a.version.localeCompare(b.version));
  must(new Set(result.map(row => row.version)).size === result.length
    && new Set(result.map(row => row.name)).size === result.length, 'LEDGER_DUPLICATE');
  return result;
}

export function checkInitialLedger(current, original43) {
  const old = normalizeLedger(original43), fresh = normalizeLedger(current);
  must(old.length === 43 && equal(fresh, normalizeLedger([...old, FIRST])), 'EXACT_44_LEDGER_REQUIRED');
  return fresh;
}

export function checkOneApplied(before, after, name) {
  const old = normalizeLedger(before), fresh = normalizeLedger(after);
  const versions = new Set(old.map(row => row.version));
  const added = fresh.filter(row => !versions.has(row.version));
  must(fresh.length === old.length + 1 && added.length === 1 && added[0].name === name
    && equal(fresh.filter(row => versions.has(row.version)), old), 'MIGRATION_LEDGER_DELTA_INVALID');
  return added[0];
}

export function checkInitialPreflight(current, prior, nowMs = Date.now()) {
  must(current && prior && Object.keys(current).length === 40
    && equal(Object.keys(current).sort(), Object.keys(prior).sort()), 'FORTY_FIELD_PREFLIGHT_REQUIRED');
  const changed = Object.keys(current).filter(key => key !== 'observed_at' && !equal(current[key], prior[key]));
  must(changed.length === 0, 'PREFLIGHT_METADATA_DRIFT');
  must(current.migration_count === 44 && current.api_functions === 108 && current.functions.length === 121
    && current.proposed_runtime_accounts === 0, 'APPROVED_PARTIAL_STATE_REQUIRED');
  const observed = Date.parse(String(current.observed_at).replace(' ', 'T').replace(/\+00$/, 'Z'));
  must(Number.isFinite(observed) && nowMs - observed >= -10000 && nowMs - observed < 600000, 'FRESH_SERVER_PREFLIGHT_REQUIRED');
  return { observedAt: current.observed_at, metadataFieldsCompared: 40, changedFields: ['observed_at'] };
}

export function checkRenamePreservation(before, after) {
  must(Array.isArray(before?.functions) && before.functions.length === 3
    && Array.isArray(after?.functions) && after.functions.length === 3, 'THREE_RENAME_BASELINES_REQUIRED');
  for (const old of before.functions) {
    const fresh = after.functions.find(row => row.originalSignature === old.originalSignature
      && row.preservedSignature === old.preservedSignature);
    must(old.originalPresent === true && old.preservedPresent === false && /^[a-f0-9]{64}$/.test(old.originalBodyLfSha256 ?? '')
      && fresh?.preservedPresent === true && fresh.preservedBodyLfSha256 === old.originalBodyLfSha256,
    'RENAMED_BASELINE_BODY_CHANGED');
  }
  return true;
}

async function exactFile(relative, sha) {
  const full = path.resolve(ROOT, relative);
  must(full.startsWith(path.resolve(ROOT) + path.sep), 'FILE_OUTSIDE_WORKSPACE');
  const bytes = await fs.readFile(full); must(hashBytes(bytes) === sha, 'APPROVED_FILE_CHANGED'); return bytes;
}

export async function loadApprovedInputs() {
  const review = JSON.parse(await exactFile(REVIEW, REVIEW_SHA)); validateRuntimeReview(review);
  must(review.bundleSha256 === BUNDLE && review.artifacts.length === 5468 && review.migrations.length === 71, 'EXACT_REVIEW_REQUIRED');
  const owner = JSON.parse(await exactFile(OWNER, OWNER_SHA)); validateApproval(owner, review, { runtimeFileSha256: REVIEW_SHA });
  const bindings = [...review.artifacts, ...review.migrations];
  for (let start = 0; start < bindings.length; start += 32) {
    await Promise.all(bindings.slice(start, start + 32).map(binding => exactFile(binding.path, binding.sha256)));
  }
  const initial = JSON.parse(await exactFile(INITIAL, INITIAL_SHA));
  const actual = Object.fromEntries(initial.results.map(item => {
    must(item.status === 'fulfilled', 'ACTUAL_INITIAL_READ_REQUIRED');
    return [item.value.label, decodePublicResult(item.value.result)];
  }));
  const ledgerBinding = review.artifacts.find(item => item.path === BASE + 'complete-live-preflight-20261010-r5-ledger.json');
  must(ledgerBinding, 'APPROVED_LEDGER_BINDING_REQUIRED');
  const originalLedger = decodePublicResult(JSON.parse(await exactFile(ledgerBinding.path, ledgerBinding.sha256))).migrations;
  checkInitialLedger(actual.ledger.migrations, originalLedger);
  const plan = review.migrations.map((migration, index) => {
    must(migration.order === index + 1 && /^supabase\/migrations\/[0-9]{14}_[a-z][a-z0-9_]*\.sql$/.test(migration.path), 'EXACT_MIGRATION_ORDER_REQUIRED');
    return Object.freeze({ ...migration, name: path.basename(migration.path).replace(/^[0-9]{14}_/, '').replace(/\.sql$/, '') });
  });
  must(plan[0].name === FIRST.name && plan[0].sha256 === '1245dd3f3bfca3c00afa4477da67e6a02655ef9f3e25a1c848e5ca3f769f526c', 'EXACT_INSTALLED_FIRST_REQUIRED');
  return Object.freeze({ review, owner, plan: Object.freeze(plan), originalLedger,
    initialPreflight: actual.fullPreflight[0], preflightSql: (await exactFile(PREFLIGHT, PREFLIGHT_SHA)).toString('utf8'),
    renameSql: (await exactFile(RENAMES, RENAMES_SHA)).toString('utf8'), inspectedBindings: bindings.length });
}

export function createManagementTransport(privateToken, { requestFactory = https.request, timeoutMs = 180000 } = {}) {
  must(typeof privateToken === 'string' && privateToken.length >= 9 && privateToken.length <= 2048
    && !/\s/.test(privateToken), 'PRIVATE_OWNER_INPUT_REQUIRED');
  return async (method, suffix, body) => {
    must((method === 'GET' && ['', '/database/migrations'].includes(suffix))
      || (method === 'POST' && ['/database/migrations', '/database/query'].includes(suffix)), 'FIXED_MANAGEMENT_ENDPOINT_REQUIRED');
    if (suffix === '/database/query') must(body?.read_only === true, 'READ_ONLY_QUERY_REQUIRED');
    const target = new URL(`https://api.supabase.com/v1/projects/${PROJECT}${suffix}`);
    const requestBytes = body === undefined ? null : JSON.stringify(body);
    return new Promise((resolve, reject) => {
      let settled = false, request, timer, sent = false, size = 0; const chunks = [];
      const fail = code => { if (settled) return; settled = true; clearTimeout(timer); request?.destroy();
        const error = new Error(code); error.publicCode = code; error.sent = sent; reject(error); };
      try {
        request = requestFactory(target, { method, rejectUnauthorized: true, headers: {
          Authorization: `Bearer ${privateToken}`, ...(requestBytes === null ? {} : {
            'Content-Type': 'application/json', 'Content-Length': Buffer.byteLength(requestBytes) }) } }, response => {
          response.on('error', () => fail('MANAGEMENT_RESPONSE_UNCERTAIN'));
          response.on('data', chunk => { if (settled) return; size += chunk.length;
            if (size > 2 * 1024 * 1024) fail('MANAGEMENT_RESPONSE_LIMIT'); else chunks.push(chunk); });
          response.on('end', () => {
            if (settled) return;
            const raw = Buffer.concat(chunks); const responseSha256 = hashBytes(raw);
            if (![200, 201].includes(response.statusCode)) {
              const code = [401, 403].includes(response.statusCode) ? 'OWNER_CREDENTIAL_OR_PERMISSION_INVALID'
                : response.statusCode === 429 ? 'MANAGEMENT_RATE_LIMITED' : 'MANAGEMENT_HTTP_FAILURE';
              fail(code); return;
            }
            let value; try { value = JSON.parse(raw.toString('utf8')); } catch { fail('MANAGEMENT_RESPONSE_INVALID'); return; }
            settled = true; clearTimeout(timer); resolve({ value, status: response.statusCode, responseSha256, responseBytes: raw.length });
          });
        });
        request.on('error', () => fail('MANAGEMENT_TRANSPORT_UNCERTAIN'));
        timer = setTimeout(() => fail('MANAGEMENT_TIMEOUT_UNCERTAIN'), timeoutMs);
        request.once('socket', socket => {
          const send = () => {
            if (settled) { request.destroy(); return; }
            if (socket.encrypted !== true || socket.authorized !== true) { fail('VERIFIED_MANAGEMENT_TLS_REQUIRED'); return; }
            sent = true; request.end(requestBytes ?? undefined);
          };
          if (settled) { request.destroy(); return; }
          if (socket.encrypted !== true) { fail('VERIFIED_MANAGEMENT_TLS_REQUIRED'); return; }
          if (socket.authorized === true) send(); else socket.once('secureConnect', send);
        });
      } catch { fail('MANAGEMENT_REQUEST_FAILED'); }
    });
  };
}

async function writeNew(folder, name, value) {
  const bytes = JSON.stringify(value, null, 2) + '\n'; const handle = await fs.open(path.join(folder, name), 'wx', 0o600);
  try { await handle.writeFile(bytes); await handle.sync(); } finally { await handle.close(); }
  return { path: path.relative(ROOT, path.join(folder, name)).split(path.sep).join('/'), sha256: hashBytes(bytes) };
}

async function main() {
  const mode = process.argv[2] ?? '--validate';
  must(process.argv.length <= 3 && ['--validate', '--preflight', '--execute'].includes(mode), 'EXACT_INSTALLER_MODE_REQUIRED');
  const inputs = await loadApprovedInputs();
  if (mode === '--validate') {
    process.stdout.write(JSON.stringify({ kind: 'approved-management-installer-validation', passed: true, projectId: PROJECT,
      bundleSha256: BUNDLE, inspectedBindings: inputs.inspectedBindings, pendingMigrations: 70, networkCalls: 0, installedSqlWrites: 0 }) + '\n'); return;
  }
  must(!process.stdin.isTTY, 'PRIVATE_STDIN_REQUIRED'); let privateToken = '';
  for await (const chunk of process.stdin) { privateToken += chunk.toString('utf8'); must(privateToken.length <= 2050, 'PRIVATE_OWNER_INPUT_REQUIRED'); }
  const rawRequest = createManagementTransport(privateToken.trim()); privateToken = '';
  let networkCalls = 0, lastCallAt = 0;
  const request = async (...args) => { const wait = 700 - (Date.now() - lastCallAt);
    if (wait > 0) await new Promise(resolve => setTimeout(resolve, wait)); lastCallAt = Date.now(); networkCalls++; return rawRequest(...args); };
  const directory = path.join(ROOT, BASE, 'approved-management-installation-20261013-r5-' + Date.now());
  await fs.mkdir(directory); await writeNew(directory, '00-start.json', { startedAt: new Date().toISOString(), mode,
    projectId: PROJECT, runtimeBundleSha256: BUNDLE, ownerDecisionSha256: OWNER_SHA, originalSixReplayed: false,
    original43PreservationRequired: true, approvedSqlOnly: true, inspectedBindings: inputs.inspectedBindings });
  let ledger, baselineRename, completed = 0, currentOrder = null;
  try {
    const project = (await request('GET', '')).value;
    must(project.id === PROJECT && (project.organization_id ?? project.organization_slug) === ORGANIZATION
      && project.status === 'ACTIVE_HEALTHY', 'EXACT_OWNER_PROJECT_REQUIRED');
    ledger = checkInitialLedger((await request('GET', '/database/migrations')).value, inputs.originalLedger);
    const preflight = await request('POST', '/database/query', { query: inputs.preflightSql, read_only: true });
    must(Array.isArray(preflight.value) && preflight.value.length === 1, 'ONE_PREFLIGHT_ROW_REQUIRED');
    const checked = checkInitialPreflight(preflight.value[0], inputs.initialPreflight);
    await writeNew(directory, '01-preflight.json', { ...checked, ledger, fullPreflight: preflight,
      project: { id: project.id, organizationId: ORGANIZATION, status: project.status }, original43Preserved: true,
      observedAt: new Date().toISOString() });
    if (mode === '--execute') {
      for (const migration of inputs.plan.slice(1)) {
        currentOrder = migration.order;
        const liveBefore = normalizeLedger((await request('GET', '/database/migrations')).value);
        must(equal(liveBefore, ledger), 'CONCURRENT_LEDGER_CHANGED');
        if (migration.order === 58) {
          const record = await request('POST', '/database/query', { query: inputs.renameSql, read_only: true });
          baselineRename = record.value[0]?.baseline_rename_fingerprints;
          must(baselineRename?.functions?.length === 3 && baselineRename.functions.every(row => row.originalPresent && !row.preservedPresent), 'FRESH_RENAME_BASELINES_REQUIRED');
          await writeNew(directory, '58-before-rename.json', record);
        }
        const queryBytes = await exactFile(migration.path, migration.sha256), query = queryBytes.toString('utf8');
        must(hashBytes(query) === migration.sha256, 'EXACT_UTF8_QUERY_REQUIRED');
        const prefix = String(migration.order).padStart(2, '0');
        await writeNew(directory, prefix + '-intent.json', { recordedAt: new Date().toISOString(), projectId: PROJECT,
          runtimeBundleSha256: BUNDLE, migration, ledgerBefore: ledger, queryBytes: queryBytes.length });
        const applied = await request('POST', '/database/migrations', { query, name: migration.name });
        await writeNew(directory, prefix + '-response.json', { receivedAt: new Date().toISOString(), status: applied.status,
          responseSha256: applied.responseSha256, responseBytes: applied.responseBytes });
        const after = normalizeLedger((await request('GET', '/database/migrations')).value);
        const assignedLedgerEntry = checkOneApplied(ledger, after, migration.name);
        await writeNew(directory, prefix + '-result.json', { finishedAt: new Date().toISOString(), migration,
          assignedLedgerEntry, ledgerAfter: after, originalSixReplayed: false, beforeLedgerPreserved: true });
        ledger = after; completed++;
        process.stdout.write(JSON.stringify({ order: migration.order, installed: true, ledgerCount: ledger.length }) + '\n');
      }
      const afterRename = await request('POST', '/database/query', { query: inputs.renameSql, read_only: true });
      checkRenamePreservation(baselineRename, afterRename.value[0]?.baseline_rename_fingerprints);
      await writeNew(directory, '99-after-rename.json', afterRename);
      must(ledger.length === 114, 'EXPECTED_114_LEDGER_REQUIRED');
    }
    const result = { finishedAt: new Date().toISOString(), mode, projectId: PROJECT, runtimeBundleSha256: BUNDLE,
      migrationsInstalledInThisRun: completed, actualLedgerCount: ledger.length, networkCalls, currentOrder,
      installedSqlFullCatalogVerified: false, authenticatedNative: false, genuineMfa: false, actualDelivery: false,
      independentSessionContention: false, targetScaleLoad: false, ownerAcceptedCriteria: 3, production: false, realBilling: false };
    const ref = await writeNew(directory, '99-finish.json', result); process.stdout.write(JSON.stringify({ ...result, evidence: ref }) + '\n');
  } catch (error) {
    await writeNew(directory, '99-stop.json', { stoppedAt: new Date().toISOString(), mode, currentOrder, networkCalls,
      completedLedgerVerifiedMigrations: completed, lastVerifiedLedger: ledger ?? null,
      failureCode: error.publicCode ?? 'OWNER_SETUP_FAILED', outcomeRequiresFreshReconciliation: mode === '--execute' && currentOrder !== null,
      automaticRetryPerformed: false, rollbackOrCleanupPerformed: false, originalSixReplayed: false });
    throw error;
  }
}

if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  main().catch(error => { process.stderr.write(JSON.stringify({ failureCode: error.publicCode ?? 'OWNER_SETUP_FAILED',
    rawErrorOrCredentialPrinted: false, automaticRetryPerformed: false }) + '\n'); process.exitCode = 1; });
}
