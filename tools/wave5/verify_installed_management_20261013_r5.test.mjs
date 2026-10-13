import test from 'node:test';
import assert from 'node:assert/strict';
import { checkInstalledCatalog, checkInstalledPreservation, checkApprovedAccessAdditions } from './verify_installed_management_20261013_r5.mjs';

const goodCatalog = () => ({ migrationCount: 114, expectedFunctions: 541, matchingFunctions: 541,
  functionChecks: Array.from({ length: 541 }, () => ({ matches: true })), expectedTables: 215, presentTables: 215,
  tableChecks: Array.from({ length: 215 }, () => ({ present: true })), apiFunctionCount: 399 });
const fixtures = () => {
  const provider = { schema: 'api', name: 'reviewed_provider', arguments: 'p_id uuid', definitionSha256: 'old' };
  const before = { access_row_fingerprints: { memberships: 'original-memberships' }, role_permissions: 28,
    role_assignments: 1, entitlements: 1, memberships: 87, functions: [provider] };
  const current = { migrationCount: 114, plannedRuntimeAccountCount: 0,
    accessRowFingerprints: structuredClone(before.access_row_fingerprints),
    accessCounts: { rolePermissions: 28, roleAssignments: 1, entitlements: 1, memberships: 87 },
    existingDesktopAccount: { authId: 'c0ab44a9-7385-4d9c-94f2-4df3efaa453f', confirmed: true },
    protectedProviders: [structuredClone(provider)] };
  return { before, current, catalog: { functions: [], functionChecks: [] } };
};

test('installed catalog refuses partial, mismatching and truncated results', () => {
  assert.equal(checkInstalledCatalog(goodCatalog()).matchingFunctions, 541);
  for (const change of [{ migrationCount: 113 }, { matchingFunctions: 540 }, { presentTables: 214 },
    { functionChecks: [] }, { tableChecks: [] }]) {
    assert.throws(() => checkInstalledCatalog({ ...goodCatalog(), ...change }), /INSTALLED_SOURCE_CATALOG_MISMATCH/);
  }
  const changed = goodCatalog(); changed.functionChecks[200].matches = false;
  assert.throws(() => checkInstalledCatalog(changed), /INSTALLED_SOURCE_CATALOG_MISMATCH/);
});

test('protected account, existing assignments and access fingerprints cannot drift', () => {
  const { before, current, catalog } = fixtures();
  assert.equal(checkInstalledPreservation(current, before, catalog).unchangedProviders, 1);
  for (const mutate of [c => { c.existingDesktopAccount.authId = 'another-account'; },
    c => { c.existingDesktopAccount.confirmed = false; }, c => { c.plannedRuntimeAccountCount = 1; },
    c => { c.accessCounts.memberships = 88; }, c => { c.accessRowFingerprints.memberships = 'changed'; }]) {
    const candidate = structuredClone(current); mutate(candidate);
    assert.throws(() => checkInstalledPreservation(candidate, before, catalog), /PROTECTED_ACCESS_OR_ACCOUNT_CHANGED/);
  }
});

test('an old provider cannot disappear or be justified by a same-name overload', () => {
  const { before, current, catalog } = fixtures();
  current.protectedProviders[0].arguments = 'p_id text';
  assert.throws(() => checkInstalledPreservation(current, before, catalog), /PROTECTED_PROVIDER_REVISION_UNBOUND/);
});

test('a provider revision needs an exact approved body and language/security/volatility match', () => {
  const { before, current, catalog } = fixtures();
  current.protectedProviders[0].definitionSha256 = 'new';
  catalog.functions.push({ ...current.protectedProviders[0], bodyLfSha256: 'reviewed-body', language: 'plpgsql',
    securityDefiner: true, volatility: 'v' });
  const source = { signature: 'api.reviewed_provider(uuid)', matches: true, installed_body_lf_sha256: 'reviewed-body',
    installed_language: 'plpgsql', installed_security_definer: true, installed_volatility: 'v' };
  catalog.functionChecks.push(source);
  assert.equal(checkInstalledPreservation(current, before, catalog).approvedSourceBodyRevisions.length, 1);
  for (const change of [{ installed_body_lf_sha256: 'unreviewed' }, { installed_language: 'sql' },
    { installed_security_definer: false }, { installed_volatility: 's' }, { signature: 'api.other(uuid)' }, { matches: false }]) {
    const changed = structuredClone(catalog); changed.functionChecks[0] = { ...source, ...change };
    assert.throws(() => checkInstalledPreservation(current, before, changed), /PROTECTED_PROVIDER_REVISION_UNBOUND/);
  }
});

test('approved additions must preserve every preexisting row and match exact tuples and disabled entitlements', () => {
  const { before, current, catalog } = fixtures();
  before.access_row_fingerprints['core.role_permissions'] = 'old-permissions';
  before.access_row_fingerprints['billing.plan_entitlements'] = 'old-entitlements';
  current.accessRowFingerprints = { ...before.access_row_fingerprints,
    'core.role_permissions': 'with-four-new-permissions', 'billing.plan_entitlements': 'with-four-disabled-entitlements' };
  current.accessCounts.rolePermissions += 4; current.accessCounts.entitlements += 4;
  const additions = { migrationCount: 114, expectedAddedPermissionCount: 4, actualAddedPermissionCount: 4,
    permissionAdditionsExactlyMatch: true, expectedAddedEntitlementCount: 4, actualAddedEntitlementCount: 4,
    entitlementAdditionsExactlyMatch: true, priorRolePermissionCount: 28, priorEntitlementCount: 1,
    priorRolePermissionsSha256: 'old-permissions', priorEntitlementsSha256: 'old-entitlements' };
  assert.equal(checkInstalledPreservation(current, before, catalog, additions).approvedAdditions.approvedPermissionRowsAdded, 4);
  for (const change of [{ actualAddedPermissionCount: 5 }, { permissionAdditionsExactlyMatch: false },
    { entitlementAdditionsExactlyMatch: false }, { priorRolePermissionsSha256: 'changed-existing-row' },
    { priorEntitlementsSha256: 'changed-existing-entitlement' }, { priorRolePermissionCount: 27 }]) {
    assert.throws(() => checkApprovedAccessAdditions({ ...additions, ...change }, before, current), /APPROVED_ACCESS_ADDITIONS_UNBOUND/);
  }
  const membershipDrift = structuredClone(current); membershipDrift.accessRowFingerprints.memberships = 'changed';
  assert.throws(() => checkInstalledPreservation(membershipDrift, before, catalog, additions), /PROTECTED_ACCESS_OR_ACCOUNT_CHANGED/);
});
