import fs from 'node:fs/promises';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { isDeepStrictEqual as equal } from 'node:util';
import { hashBytes } from './runtime_contract.mjs';
import { PROJECT, ORGANIZATION, BUNDLE, loadApprovedInputs, normalizeLedger, checkOneApplied,
  checkRenamePreservation, createManagementTransport } from './approved_management_installer.mjs';
const root = fileURLToPath(new URL('../../', import.meta.url)), base = 'docs/verification/wave5/';
const installation = base + 'approved-management-installation-20261013-r5-1791875214803/';
const planFile = base + 'installed-verification-plan-20261012-r5-a2.json';
const planSha = '0caf72e72b920efa03246860c4d443e3ad0d2c129218d8cca3d85d79ba3c2077';
const finishSha = '5f4b4612d51274765bc772b99c8c353194c6c500d786989addc7a2ad14bb9fbd';
const additionsBinding = { id: 'approved-access-additions', path: base + 'installed-preservation-additions-20261013-r5.sql',
  sha256: '81f5ae56b625c1c025a274a3e4140cfb21073638874334a796cada4b6acbe80a' };
const must = (condition, code) => { if (!condition) { const error = Error(code); error.publicCode = code; throw error; } };
const read = async file => JSON.parse(await fs.readFile(path.join(root, file), 'utf8'));
const exact = async (file, sha) => { const bytes = await fs.readFile(path.join(root, file)); must(hashBytes(bytes) === sha, 'VERIFICATION_SOURCE_CHANGED'); return bytes; };

export function checkInstalledCatalog(catalog) {
  must(catalog?.migrationCount === 114 && catalog.expectedFunctions === 541 && catalog.matchingFunctions === 541
    && catalog.functionChecks?.length === 541 && catalog.functionChecks.every(row => row.matches === true)
    && catalog.expectedTables === 215 && catalog.presentTables === 215 && catalog.tableChecks?.length === 215
    && catalog.tableChecks.every(row => row.present === true), 'INSTALLED_SOURCE_CATALOG_MISMATCH');
  return { expectedFunctions: 541, matchingFunctions: 541, expectedTables: 215, presentTables: 215,
    apiFunctions: catalog.apiFunctionCount, observedAt: catalog.observedAt };
}

export function checkApprovedAccessAdditions(additions, before, current) {
  must(additions?.migrationCount === 114 && additions.expectedAddedPermissionCount === 4
    && additions.actualAddedPermissionCount === 4 && additions.permissionAdditionsExactlyMatch === true
    && additions.expectedAddedEntitlementCount === 4 && additions.actualAddedEntitlementCount === 4
    && additions.entitlementAdditionsExactlyMatch === true && additions.priorRolePermissionCount === before.role_permissions
    && additions.priorEntitlementCount === before.entitlements
    && additions.priorRolePermissionsSha256 === before.access_row_fingerprints['core.role_permissions']
    && additions.priorEntitlementsSha256 === before.access_row_fingerprints['billing.plan_entitlements']
    && current.accessCounts.rolePermissions === before.role_permissions + 4
    && current.accessCounts.entitlements === before.entitlements + 4, 'APPROVED_ACCESS_ADDITIONS_UNBOUND');
  return { existingPermissionRowsUnchanged: true, existingEntitlementRowsUnchanged: true,
    approvedPermissionRowsAdded: 4, approvedDisabledEntitlementRowsAdded: 4 };
}

export function checkInstalledPreservation(current, before, catalog, additions) {
  const approvedAdditions = additions ? checkApprovedAccessAdditions(additions, before, current) : null;
  const expectedFingerprints = { ...before.access_row_fingerprints };
  if (approvedAdditions) {
    expectedFingerprints['core.role_permissions'] = current.accessRowFingerprints['core.role_permissions'];
    expectedFingerprints['billing.plan_entitlements'] = current.accessRowFingerprints['billing.plan_entitlements'];
  }
  must(current?.migrationCount === 114 && current.plannedRuntimeAccountCount === 0
    && equal(current.accessRowFingerprints, expectedFingerprints)
    && equal(current.accessCounts, { rolePermissions: before.role_permissions, roleAssignments: before.role_assignments,
      entitlements: before.entitlements, memberships: before.memberships,
      ...(approvedAdditions ? { rolePermissions: before.role_permissions + 4, entitlements: before.entitlements + 4 } : {}) })
    && current.existingDesktopAccount?.authId === 'c0ab44a9-7385-4d9c-94f2-4df3efaa453f'
    && current.existingDesktopAccount.confirmed === true, 'PROTECTED_ACCESS_OR_ACCOUNT_CHANGED');
  const identity = row => `${row.schema}.${row.name}(${row.arguments})`;
  const after = new Map(current.protectedProviders.map(row => [identity(row), row]));
  const revisions = [], missing = [], unbound = [];
  for (const old of before.functions) {
    const name = identity(old), fresh = after.get(name);
    if (!fresh) { missing.push(name); continue; }
    if (fresh.definitionSha256 === old.definitionSha256) continue;
    const actual = catalog.functions.find(row => identity(row) === name);
    const source = catalog.functionChecks.find(row => row.signature.startsWith(`${old.schema}.${old.name}(`)
      && row.matches === true && row.installed_body_lf_sha256 === actual?.bodyLfSha256
      && row.installed_language === actual?.language && row.installed_security_definer === actual?.securityDefiner
      && row.installed_volatility === actual?.volatility);
    revisions.push({ identity: name, priorDefinitionSha256: old.definitionSha256, currentDefinitionSha256: fresh.definitionSha256,
      approvedSourceBodyMatched: !!source, matchedSourceSignature: source?.signature ?? null });
    if (!source) unbound.push(name);
  }
  must(missing.length === 0 && unbound.length === 0, 'PROTECTED_PROVIDER_REVISION_UNBOUND');
  return { priorProvidersChecked: before.functions.length, unchangedProviders: before.functions.length - revisions.length,
    approvedSourceBodyRevisions: revisions, existingAccessRowsUnchanged: true, approvedAdditions,
    entireAccessTablesUnchanged: !approvedAdditions, existingDesktopAccountPreserved: true };
}

async function prepare() {
  const inputs = await loadApprovedInputs();
  const plan = JSON.parse(await exact(planFile, planSha));
  must(plan.projectId === PROJECT && plan.review.bundleSha256 === BUNDLE && plan.queries.length === 4, 'EXACT_INSTALLED_PLAN_REQUIRED');
  const queries = [];
  for (const binding of plan.queries) queries.push({ ...binding, query: (await exact(binding.path, binding.sha256)).toString('utf8') });
  const additionSources = [24, 25, 47, 58, 64].map(order => inputs.plan[order - 1]);
  for (const migration of additionSources) await exact(migration.path, migration.sha256);
  queries.push({ ...additionsBinding, query: (await exact(additionsBinding.path, additionsBinding.sha256)).toString('utf8') });
  const finished = JSON.parse(await exact(installation + '99-finish.json', finishSha));
  must(finished.mode === '--execute' && finished.migrationsInstalledInThisRun === 70 && finished.actualLedgerCount === 114,
    'ACTUAL_COMPLETED_INSTALLATION_REQUIRED');
  const before = await read(installation + '01-preflight.json');
  let ledger = normalizeLedger(before.ledger);
  for (const migration of inputs.plan.slice(1)) {
    const result = await read(installation + String(migration.order).padStart(2, '0') + '-result.json');
    must(result.migration.path === migration.path && result.migration.sha256 === migration.sha256
      && result.migration.order === migration.order && result.originalSixReplayed === false && result.beforeLedgerPreserved === true,
    'ACTUAL_MIGRATION_MAPPING_REQUIRED');
    must(equal(checkOneApplied(ledger, result.ledgerAfter, migration.name), result.assignedLedgerEntry), 'ACTUAL_LEDGER_MAPPING_MISMATCH');
    ledger = normalizeLedger(result.ledgerAfter);
  }
  must(ledger.length === 114, 'ACTUAL_114_LEDGER_REQUIRED');
  const baselineRename = (await read(installation + '58-before-rename.json')).value[0].baseline_rename_fingerprints;
  const afterRename = (await read(installation + '99-after-rename.json')).value[0].baseline_rename_fingerprints;
  checkRenamePreservation(baselineRename, afterRename);
  return { inputs, queries, ledger, before: before.fullPreflight.value[0], baselineRename, additionSources };
}

async function main() {
  const mode = process.argv[2] ?? '--validate';
  must(process.argv.length <= 3 && ['--validate', '--verify'].includes(mode), 'EXACT_INSTALLED_VERIFICATION_MODE_REQUIRED');
  const prepared = await prepare();
  if (mode === '--validate') { process.stdout.write(JSON.stringify({ kind: 'installed-management-verification-preparation', passed: true,
    ledgerMappingsChecked: 70, actualAdditionalInstalled: 71, actualLedgerCount: 114, boundReadOnlyQueries: 5,
    approvedAccessAdditionSourceOrders: prepared.additionSources.map(row => row.order), networkCalls: 0 }) + '\n'); return; }
  must(!process.stdin.isTTY, 'PRIVATE_STDIN_REQUIRED'); let token = '';
  for await (const chunk of process.stdin) { token += chunk.toString('utf8'); must(token.length <= 2050, 'PRIVATE_INPUT_TOO_LONG'); }
  const privateRequest = createManagementTransport(token.trim()); token = '';
  let networkCalls = 0;
  const request = (...args) => { networkCalls++; return privateRequest(...args); };
  const folder = path.join(root, base + 'installed-management-verification-20261013-r5-' + Date.now());
  await fs.mkdir(folder);
  const save = async (name, value) => { const text = JSON.stringify(value, null, 2) + '\n';
    const handle = await fs.open(path.join(folder, name), 'wx');
    try { await handle.writeFile(text); await handle.sync(); } finally { await handle.close(); }
    return { path: path.relative(root, path.join(folder, name)).split(path.sep).join('/'), sha256: hashBytes(text) }; };
  const records = {}; let phase = 'owner-project';
  try {
    const project = (await request('GET', '')).value;
    must(project.id === PROJECT && (project.organization_id ?? project.organization_slug) === ORGANIZATION
      && project.status === 'ACTIVE_HEALTHY', 'EXACT_OWNER_PROJECT_REQUIRED');
    phase = 'catalog-metadata';
    for (const binding of prepared.queries.filter(query => query.id !== 'baseline-renames')) {
      phase = binding.id;
      const result = await request('POST', '/database/query', { query: binding.query, read_only: true });
      await save(binding.id + '-raw.json', { queryBinding: { path: binding.path, sha256: binding.sha256 },
        actualFinishedAt: new Date().toISOString(), response: result });
      must(Array.isArray(result.value) && result.value.length === 1, 'ONE_INSTALLED_RESULT_REQUIRED');
      records[binding.id] = result.value[0];
    }
    phase = 'post-verification-ledger';
    const ledger = normalizeLedger((await request('GET', '/database/migrations')).value);
    must(equal(ledger, prepared.ledger), 'INSTALLED_LEDGER_CHANGED');
    const catalog = checkInstalledCatalog(records.catalog.installed_catalog);
    const strict = records.strict.strict_metadata;
    must(strict?.strictMetadataPredicatesPassed === true && strict.ledgerCount === 114
      && strict.forcedRlsPredicates === 72 && strict.functionGrantPredicates === 18, 'INSTALLED_STRICT_METADATA_MISMATCH');
    const preservation = checkInstalledPreservation(records.preservation.installed_preservation, prepared.before,
      records.catalog.installed_catalog, records['approved-access-additions'].installed_preservation_additions);
    const result = { kind: 'actual-wave5-installed-sql-metadata-verification', actualFinishedAt: new Date().toISOString(),
      projectId: PROJECT, runtimeBundleSha256: BUNDLE, passed: true, ledgerCount: 114, installedAdditionalMigrations: 71,
      catalog, strict, preservation, beforeOrder58Captured: true, threeRenamedBodiesPreserved: true,
      originalSixReinstalled: false, networkCalls, databaseWrites: 0, authWrites: 0,
      behaviorFixturesExecuted: false, genuineMfa: false, authenticatedNative: false, actualDelivery: false, actualModelUsage: false,
      independentSessionContention: false, targetScaleLoad: false, ownerAcceptedCriteria: 3, production: false, realBilling: false,
      verificationPlan: { path: planFile, sha256: planSha }, completedInstallation: { path: installation + '99-finish.json', sha256: finishSha },
      approvedAccessAdditionQuery: additionsBinding, approvedAccessAdditionSources: prepared.additionSources,
      limitation: 'Actual installed source-body/language/security/volatility, table, forced-RLS, grants and preservation metadata. Behavior, Auth, MFA, delivery/model, native and load gates remain open.' };
    const ref = await save('99-result.json', result);
    process.stdout.write(JSON.stringify({ passed: true, ledgerCount: 114, apiFunctions: catalog.apiFunctions,
      matchingFunctions: 541, presentTables: 215, forcedRlsPredicates: 72, functionGrantPredicates: 18,
      protectedProvidersChecked: preservation.priorProvidersChecked, evidence: ref }) + '\n');
  } catch (error) {
    await save('99-stop.json', { phase, failureCode: error.publicCode ?? 'INSTALLED_VERIFICATION_FAILED', networkCalls,
      installedSqlVerified: false, actualFailedResultPreserved: true, databaseWrites: 0, authWrites: 0 });
    throw error;
  }
}
if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  main().catch(error => { process.stderr.write(JSON.stringify({ failureCode: error.publicCode ?? 'INSTALLED_VERIFICATION_FAILED',
    rawErrorOrCredentialPrinted: false }) + '\n'); process.exitCode = 1; });
}
