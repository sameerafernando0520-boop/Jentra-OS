"""Compare a fresh read-only installed catalog with preserved installed fingerprints."""
import hashlib
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
E = ROOT / 'docs/verification/wave5'

def identity(row):
    return row['schema'], row['name'], row['arguments']

def main():
    fresh = json.loads((E / 'continuation-post-rollback-catalog-20261008.json').read_text(encoding='utf-8'))
    baseline = json.loads((E / 'installed-existing-provider-fingerprints-20261008.json').read_text(encoding='utf-8'))
    actual = {identity(row): row['definitionSha256'] for row in fresh['functions']}
    changed = [identity(row) for row in baseline['functions'] if actual.get(identity(row)) != row['definitionSha256']]
    fresh['fingerprintComparison'] = {'checked': len(baseline['functions']),
        'unchanged': len(baseline['functions']) - len(changed), 'changedOrMissing': changed}
    fresh['fingerprintBaselineSha256'] = hashlib.sha256((E / 'installed-existing-provider-fingerprints-20261008.json').read_bytes()).hexdigest()
    if fresh['migrationCount'] != 43 or fresh['apiFunctionCount'] != 107 or fresh['forcedRlsCount'] != 15 or changed:
        raise ValueError('Installed baseline drift requires investigation before publication')
    if any(fresh[key] != 0 for key in ['fixtureAccounts','fixtureTenants','candidateRoleDefinitions','syntheticAllowlist','healthProbes','operators','operatorGrants']):
        raise ValueError('Unexpected fixture residue or unreviewed activation')
    if any(value is not None for value in fresh['candidateTables'].values()):
        raise ValueError('A new candidate table is already installed; reconcile the ledger')
    (E / 'continuation-live-final-20261008.json').write_text(json.dumps(fresh, indent=2) + '\n', encoding='utf-8')
    print(json.dumps({key: fresh[key] for key in ['checkedAt','migrationCount','apiFunctionCount','forcedRlsCount','fingerprintComparison','sourceDependencies']}))

if __name__ == '__main__':
    main()
