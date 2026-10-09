"""Verify installed catalog/fixture evidence and write the current installation result."""
import datetime
import hashlib
import importlib.util
import json
from pathlib import Path
import re

ROOT = Path(__file__).resolve().parents[2]
E = ROOT / 'docs/verification/wave5'


def read(name):
    return json.loads((E / name).read_text(encoding='utf-8'))


def write(name, data):
    (E / name).write_text(json.dumps(data, indent=2) + '\n', encoding='utf-8')


def signature(value):
    return re.sub(r'\s+', ' ', value.replace('timestamp with time zone', 'timestamptz').replace(',', ', ')).strip()


def main():
    review = read('installation-review-20261008.json')
    authorization = read('installation-authorization-20261008.json')
    progress = read('installation-progress-20261008.json')
    before = read('installed-catalog-before-checks-20261008.json')
    after = read('installed-catalog-final-20261008.json')
    preflight = read('installation-preflight-20261008.json')
    existing = read('installed-existing-provider-fingerprints-20261008.json')
    strict = read('installed-strict-checks-result-20261008.json')
    residue = read('installation-fixture-residue-check-20261008.json')
    if residue['synthetic_fixture_accounts'] or residue['synthetic_fixture_tenants'] or residue['migration_count'] != 43 or residue['api_function_count'] != 107:
        raise ValueError('Synthetic account/tenant fixture residue or live scope drift')
    if authorization['approvedReviewSha256'] != hashlib.sha256((E / 'installation-review-20261008.json').read_bytes()).hexdigest():
        raise ValueError('The approved review was changed')
    if not progress['complete'] or len(progress['installed']) != 6 or after['migrationCount'] != 43 or after['apiFunctionCount'] != 107:
        raise ValueError('Installation count differs from approval')
    for item in review['candidatesInOrder']:
        if hashlib.sha256((ROOT / item['path']).read_bytes()).hexdigest() != item['bytesSha256']:
            raise ValueError('Approved migration source changed: ' + item['path'])
    live_functions = {(r['schema'] + '.' + r['name'], signature(r['arguments'])): r for r in after['functions']}
    expected = {(f['name'], signature(f['arguments'])) for c in review['candidatesInOrder'] for f in c['functions']}
    if set(live_functions) != expected:
        raise ValueError('Installed function signatures differ from the approved list')
    worker_only = {'api.wave5_reserve_usage', 'api.wave5_settle_usage', 'api.wave5_correct_usage',
                   'api.record_wave5_health_probe', 'api.apply_synthetic_subscription'}
    for (name, _), function in live_functions.items():
        if function['publicExecute'] or function['anonExecute'] or function['configuration'] != ['search_path=""']:
            raise ValueError('Unsafe installed function grants/search path: ' + name)
        if name.startswith('api.'):
            if not function['securityDefiner'] or function['authenticatedExecute'] != (name not in worker_only) or function['serviceRoleExecute'] != (name in worker_only):
                raise ValueError('API grant/authority differs from approved source: ' + name)
        elif function['authenticatedExecute']:
            raise ValueError('Private helper directly executable by desktop: ' + name)
    expected_tables = set(t for c in review['candidatesInOrder'] for t in c['tables'])
    actual_tables = set(t['schema'] + '.' + t['name'] for t in after['tables'])
    if actual_tables != expected_tables or len(actual_tables) != 15:
        raise ValueError('Installed table list differs')
    mutable = {'operators', 'quota_periods', 'synthetic_tenants'}
    for table in after['tables']:
        if not table['rls'] or not table['forced'] or any(table[k] for k in ['anonRead', 'anonWrite', 'authenticatedRead', 'authenticatedWrite']):
            raise ValueError('Table RLS/client privilege mismatch: ' + table['name'])
        if table['name'] not in mutable and not table['immutableTrigger']:
            raise ValueError('Immutable evidence trigger missing: ' + table['name'])
    if len(after['schemas']) != 2 or any(s['anonUsage'] or s['authenticatedUsage'] for s in after['schemas']):
        raise ValueError('Private schema usage exposed')
    if after['trialStartedAt'] != {'type': 'timestamptz', 'nullable': 'YES', 'default': None}:
        raise ValueError('Trial column shape mismatch')
    if not after['processCohortIndex'] or after['seatGuard']['enabled'] != 'O':
        raise ValueError('Required process index/seat trigger missing')
    if after['stateCounts'] != before['stateCounts'] or any(after['stateCounts'].values()):
        raise ValueError('Installed fixtures left persistent state')
    if after['newRolePermissionAssignments'] != 0 or any(e['enabled'] for e in after['disabledEntitlements']):
        raise ValueError('Unapproved role/entitlement activation')
    if before['functions'] != after['functions'] or before['tables'] != after['tables'] or before['disabledEntitlements'] != after['disabledEntitlements']:
        raise ValueError('Fixture verification changed installed definitions or controls')
    final_existing = {(f['schema'], f['name'], f['arguments']): f for f in existing['functions']}
    for function in preflight['functionFingerprints']:
        if final_existing.get((function['schema'], function['name'], function['arguments'])) != function:
            raise ValueError('Existing provider function changed: ' + function['name'])
    if strict['passed'] != 126 or not strict['strictFinish'] or not strict['rollback'] or strict['migrationsIncluded']:
        raise ValueError('Installed SQL checks are not strict green rollback evidence')
    base_keys = {(r['version'], r['name']) for r in preflight['ledger']}
    after_keys = {(r['version'], r['name']) for r in after['ledger']}
    installed_keys = {(r['ledgerEntry']['version'], r['ledgerEntry']['name']) for r in progress['installed']}
    if after_keys != base_keys | installed_keys:
        raise ValueError('Unexpected persistent migration ledger change')
    manifest = read('client-snapshot-build-final-20261006.json')
    module_spec = importlib.util.spec_from_file_location('source_snapshot', ROOT / 'scripts/wave4/create_isolated_snapshot.py')
    module = importlib.util.module_from_spec(module_spec)
    module_spec.loader.exec_module(module)
    current = {p.relative_to(ROOT).as_posix(): hashlib.sha256(p.read_bytes()).hexdigest() for p in module.files()}
    source_match = current == manifest['source_hashes']
    write('installation-client-source-state-20261008.json', {
        'checkedAt': datetime.datetime.now(datetime.timezone.utc).isoformat(),
        'sourceFileCount': len(current), 'current_source_match': source_match,
        'reference': 'docs/verification/wave5/client-snapshot-build-final-20261006.json',
        'changedOrAdded': sorted(p for p, h in current.items() if manifest['source_hashes'].get(p) != h),
        'removed': sorted(set(manifest['source_hashes']) - set(current)),
        'sourceSha256': current})
    result = {
        'verifiedAt': datetime.datetime.now(datetime.timezone.utc).isoformat(),
        'targetProjectId': authorization['targetProjectId'], 'installationComplete': True,
        'ownerApproval': authorization['humanInstruction'], 'migrationCountBefore': 37,
        'migrationCountAfter': 43, 'apiFunctionsBefore': 85, 'apiFunctionsAfter': 107,
        'approvedMigrationsInstalled': 6, 'newApiFunctions': 22, 'newPrivateHelpers': 10,
        'newTablesForcedRls': 15, 'authenticatedApiFunctions': 17, 'workerOnlyApiFunctions': 5,
        'publicOrAnonymousNewFunctionAccess': False, 'directClientTableAccess': False,
        'existingProviderFingerprintsUnchanged': len(preflight['functionFingerprints']),
        'installedStrictSqlAssertions': 126, 'installedStrictSqlPassed': 126,
        'syntheticFixturesRolledBack': True, 'persistentStateCountsAfterChecks': after['stateCounts'],
        'fixtureAccountsAfterChecks': residue['synthetic_fixture_accounts'],
        'fixtureTenantsAfterChecks': residue['synthetic_fixture_tenants'],
        'fixtureResidueEvidence': 'docs/verification/wave5/installation-fixture-residue-check-20261008.json',
        'newEntitlementsEnabled': False, 'newRolePermissionsAssigned': False,
        'schemaReloadRequested': after['schemaReloadRequested'],
        'schemaCacheAuthenticatedRequestVerified': False, 'currentClientSourceMatch': source_match,
        'migrationsInOrder': progress['installed'], 'remaining': [
            'named synthetic tenant/entity/two branches and test-account labels',
            'separately reviewed private synthetic plan/role/operator/grant setup',
            'historical CRM and realized-result providers',
            'authoritative financial/cash adapters, immutable scenarios and governed export integration',
            'persistent integration/model providers and separately approved external provisioning/delivery',
            'authenticated native/MFA/restart/keyboard, actual contention/load and owner acceptance'],
        'wholeWaveComplete': False,
    }
    write('installation-result-20261008.json', result)
    lines = ['# Wave 5 installation result - October 8, 2026', '',
             '**The six owner-approved migrations are installed in `xpdoufauvrbdmxgngetv`. Wave 5 remains incomplete.**', '',
             'The ledger changed from 37 to 43 migrations and API functions from 85 to 107. '
             'The exact approved byte hashes still match. All 98 existing API/command provider fingerprints remain unchanged. '
             'See the [authorization](installation-authorization-20261008.json), [preflight](installation-preflight-20261008.json), '
             '[final catalog](installed-catalog-final-20261008.json) and [machine-readable result](installation-result-20261008.json).', '',
             '## Applied ledger mapping', '',
             'The connector assigns installation-time ledger versions. The original approved source filenames and hashes are retained below. '
             'These six files are applied despite their earlier filename timestamps. Use this mapping before any future CLI migration reconciliation; '
             'do not replay them or bulk-push the remaining W3/W4 candidates.', '',
             '| Order | Approved source | Installed ledger version |', '|---|---|---|']
    for item in progress['installed']:
        lines.append(f"| {item['order']} | [{Path(item['path']).name}](../../../{item['path']}) | `{item['ledgerEntry']['version']}_{item['ledgerEntry']['name']}` |")
    lines.extend(['', '## Installed verification', '',
                  '- All 32 introduced function signatures match the review: 22 API functions and 10 private helpers. Public/anonymous execute is denied. Seventeen API functions require authenticated access; five worker RPCs require service role. Private helper access is unavailable to the desktop.',
                  '- All 15 new tables enable and force RLS; direct anonymous/authenticated table reads and writes are denied. Immutable evidence tables retain their triggers. Only quota counters, operator authority and the synthetic allowlist are intentionally mutable through reviewed server authority.',
                  '- The nullable trial-start column, process cohort index and synthetic membership seat trigger are present.',
                  '- [All 126 strict installed SQL checks passed](installed-strict-checks-result-20261008.json), with `finish(true)` and `rollback;`. The composition contained fixture SQL only, not migration reinstallation.',
                  '- Before/after catalogs, disabled entitlements and empty state counters match. The [additional residue check](installation-fixture-residue-check-20261008.json) found zero fixture auth accounts and tenants. No synthetic operator/grant/proposal/usage/trial data persisted, no role permission was assigned, and no new entitlement was enabled.',
                  '- PostgREST schema reload was requested. A real authenticated API/native request remains an acceptance gate; notification alone does not prove cached endpoint behavior.', '',
                  '## Remaining Wave 5 work', '',
                  'Runtime needs named synthetic tenant/entity/two branches and proposer, distinct MFA approver, executor, billing administrator, separate operator and foreign-tenant account labels. '
                  'Synthetic plan/role/operator/grant bootstrap and entitlement activation were excluded from this approval. '
                  'Historical CRM/realized providers, financial/cash/scenario/export adapters, persistent integration/model providers, '
                  'real authenticated native/MFA/restart/keyboard, contention/load and owner signoff remain open. '
                  'Installed rollback SQL is not a real signed-in or independent-session acceptance run.', '',
                  'No production, real billing, keys, model provisioning, external sends or worker deployment occurred. '
                  'The [current development status](../../development/wave5-status.md) and [requirement matrix](requirement-matrix-20261008.md) distinguish these gates.'])
    (E / 'installation-result-20261008.md').write_text('\n'.join(lines) + '\n', encoding='utf-8')
    print(json.dumps({k: result[k] for k in ['installationComplete', 'migrationCountAfter', 'apiFunctionsAfter',
                                          'installedStrictSqlPassed', 'newTablesForcedRls', 'currentClientSourceMatch', 'wholeWaveComplete']}))


if __name__ == '__main__':
    main()
