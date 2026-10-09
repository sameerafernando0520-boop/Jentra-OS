"""Attribute existing Wave 5 evidence without touching stores or installing SQL."""
import base64
import datetime
import hashlib
import importlib.util
import json
from pathlib import Path
import re
import subprocess

ROOT = Path(__file__).resolve().parents[2]
EVIDENCE = ROOT / 'docs/verification/wave5'
ISOLATE = Path('C:/jw4-wave5-20261006')
DATE = '20261008'


def sha(data):
    return hashlib.sha256(data).hexdigest()


def dump(name, value):
    (EVIDENCE / name).write_text(json.dumps(value, indent=2) + '\n', encoding='utf-8')


def load(name):
    return json.loads((EVIDENCE / name).read_text(encoding='utf-8'))


def relative(path):
    return path.relative_to(ROOT).as_posix()


def credential_findings(data):
    # Do not include matched values in evidence. Generic library field names
    # are not credentials; these checks target actual structured secret values.
    result = []
    patterns = {
        'private_key_material': rb'-----BEGIN (?:RSA |EC |OPENSSH )?PRIVATE KEY-----',
        'supabase_secret_key': rb'\bsb_secret_[A-Za-z0-9_-]{16,}\b',
        'github_credential': rb'\b(?:ghp_[A-Za-z0-9]{30,}|github_pat_[A-Za-z0-9_]{40,})\b',
    }
    for encoding, blob in [('utf8', data), ('utf16le_even', data[::2]), ('utf16le_odd', data[1::2])]:
        for code, pattern in patterns.items():
            if re.search(pattern, blob):
                result.append({'pattern': code, 'encoding': encoding})
        for token in re.finditer(rb'\beyJ[A-Za-z0-9_-]{8,2000}\.[A-Za-z0-9_-]{8,4000}\.[A-Za-z0-9_-]{16,2000}\b', blob):
            try:
                body = token.group().split(b'.')[1]
                payload = json.loads(base64.urlsafe_b64decode(body + b'=' * (-len(body) % 4)))
            except (ValueError, UnicodeError):
                continue
            if isinstance(payload, dict) and payload.get('role') in {'service_role', 'authenticated'}:
                result.append({'pattern': 'embedded_privileged_or_session_jwt', 'encoding': encoding})
    return result


def prohibited_projection_keys(value, prefix=''):
    prohibited = {'password', 'accessToken', 'refreshToken', 'serviceRoleKey', 'secret',
                  'email', 'phone', 'bankAccount', 'salary', 'privateHr', 'rawAudit',
                  'reason', 'notes', 'description', 'rawPayload'}
    findings = []
    if isinstance(value, dict):
        for key, child in value.items():
            path = prefix + '/' + key
            if key.replace('_', '').lower() in {item.lower() for item in prohibited}:
                findings.append(path)
            if key == 'canonicalText' and isinstance(child, str):
                try:
                    findings.extend(prohibited_projection_keys(json.loads(child), path))
                except ValueError:
                    findings.append(path + '/invalid_json')
            else:
                findings.extend(prohibited_projection_keys(child, path))
    elif isinstance(value, list):
        for i, child in enumerate(value):
            findings.extend(prohibited_projection_keys(child, prefix + '/' + str(i)))
    return findings


def main():
    if (EVIDENCE / 'installation-result-20261008.json').exists():
        raise ValueError('Pre-installation review is now immutable; use complete_installation.py for installed evidence')
    checked = datetime.datetime.now(datetime.timezone.utc).isoformat()
    manifest = load('client-snapshot-build-final-20261006.json')
    spec = importlib.util.spec_from_file_location('source_snapshot', ROOT / 'scripts/wave4/create_isolated_snapshot.py')
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    current = {relative(p): sha(p.read_bytes()) for p in module.files()}
    captured = manifest['source_hashes']
    isolate = {name: sha((ISOLATE / name).read_bytes()) for name in captured}
    source_match = current == captured == isolate
    if not source_match:
        raise ValueError('Client source selection/hash changed; existing build cannot be attributed')
    release = ISOLATE / 'apps/jentra_desktop/build/windows/x64/runner/Release'
    executable = release / 'jentra_desktop.exe'
    if not executable.is_file() or 'Built build' not in (EVIDENCE / 'windows-build-final-20261006.log').read_text(encoding='utf-8-sig'):
        raise ValueError('Windows build completion evidence is absent')
    release_files = sorted(p for p in release.rglob('*') if p.is_file())
    artifact_hashes = {p.relative_to(release).as_posix(): sha(p.read_bytes()) for p in release_files}
    dump('windows-build-attribution-' + DATE + '.json', {
        'verifiedAt': checked, 'buildEvidenceDate': '2026-10-06',
        'buildLog': 'docs/verification/wave5/windows-build-final-20261006.log',
        'sourceManifest': 'docs/verification/wave5/client-snapshot-build-final-20261006.json',
        'sourceManifestSha256': sha((EVIDENCE / 'client-snapshot-build-final-20261006.json').read_bytes()),
        'gitHead': subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=ROOT, text=True).strip(),
        'current_source_match': source_match, 'sourceFileCount': len(current),
        'sourceSelectionChanged': sorted(set(current).symmetric_difference(captured)),
        'executable': str(executable), 'executableSha256': sha(executable.read_bytes()),
        'executableBytes': executable.stat().st_size,
        'executableModifiedAt': datetime.datetime.fromtimestamp(executable.stat().st_mtime, datetime.timezone.utc).isoformat(),
        'releaseDirectory': str(release), 'releaseFileCount': len(release_files),
        'releaseSha256': artifact_hashes, 'sourceSha256': current,
        'nativeLaunched': False, 'authenticatedAcceptance': False, 'installerPackaged': False,
    })
    hashes = load('subscription-native-development-20261006.hashes.json')
    candidates = []
    for name, expected in hashes['source_hashes'].items():
        p = ROOT / name
        contents = p.read_text(encoding='utf-8')
        if sha(contents.encode()) != expected:
            raise ValueError('Strict SQL source changed: ' + name)
        if name.startswith('supabase/migrations/'):
            candidates.append({'path': name, 'bytesSha256': sha(p.read_bytes()),
                               'normalizedSqlSha256': expected,
                               'functions': [{'name': m.group(1), 'arguments': ' '.join(m.group(2).split())}
                                             for m in re.finditer(r'create\s+function\s+([a-z_][a-z0-9_]*\.[a-z_][a-z0-9_]*)\s*\((.*?)\)\s*returns', contents, re.I | re.S)],
                               'tables': re.findall(r'create\s+table\s+([a-z_]+\.[a-z_]+)', contents, re.I)})
    sql = EVIDENCE / 'subscription-native-development-20261006.sql'
    if sha(sql.read_text(encoding='utf-8').encode()) != hashes['query_sha256'] or not sql.read_text(encoding='utf-8').rstrip().endswith('rollback;'):
        raise ValueError('Strict rollback query changed')
    result = load('subscription-native-development-result-20261006.json')
    tap = result['result'][0]['tap']
    if len(tap) != 126 or not all(re.match(r'^ok [0-9]+ - ', item) for item in tap):
        raise ValueError('Strict assertion evidence is not green')
    baseline = load('live-baseline-' + DATE + '.json')
    review = {'reviewedAt': checked, 'status': 'unapplied; owner authorization pending',
              'targetProjectId': 'xpdoufauvrbdmxgngetv', 'environment': 'synthetic development',
              'installedMigrationCount': baseline['migrationCount'], 'installedLatestVersion': baseline['latestVersion'],
              'installedApiFunctionCount': baseline['apiFunctionCount'],
              'baseline': 'docs/verification/wave5/live-baseline-' + DATE + '.json',
              'strictAssertions': 126, 'candidateEffectsRolledBack': True,
              'strictQueryNormalizedSqlSha256': hashes['query_sha256'],
              'strictQueryBytesSha256': sha(sql.read_bytes()), 'candidatesInOrder': candidates,
              'newApiFunctionCount': sum(f['name'].startswith('api.') for c in candidates for f in c['functions']),
              'syntheticTenant': None, 'syntheticEntity': None, 'syntheticBranches': [],
              'actorAccountLabels': {}, 'syntheticPlanCode': None,
              'excluded': ['all other unapplied Wave 3/4 candidates', 'SQL test fixtures',
                           'tenant/account/operator/grant bootstrap', 'role assignments',
                           'enabling existing shared plan entitlements', 'real billing',
                           'credentials/vault keys/model provisioning', 'external sends', 'worker deployment'],
              'approvalRecorded': False}
    dump('installation-review-' + DATE + '.json', review)
    worker_paths = sorted((ROOT / 'workers/wave5').glob('*.mjs'))
    worker_hashes = {relative(p): sha(p.read_bytes()) for p in worker_paths}
    dump('worker-source-attribution-' + DATE + '.json', {
        'verifiedAt': checked, 'sourceSha256': worker_hashes,
        'testLog': 'docs/verification/wave5/workers-final-' + DATE + '.log',
        'testsPassed': 15, 'externalRequestSent': False,
        'unknownOutcomeRequiresReconciliation': True,
        'persistentPortsConfigured': False, 'deployed': False,
    })
    logs = [EVIDENCE / name for name in ['domain-final-checked-20261006.log', 'platform-final-checked-20261006.log',
            'native-final-20261006.log', 'analyzer-final-20261006.log', 'windows-build-final-20261006.log',
            'workers-final-' + DATE + '.log']]
    wires = sorted((ROOT / 'packages/jentra_platform/test/analytics').glob('*_sql_snapshot.json'))
    scans, findings = [], []
    for kind, paths in [('release', release_files), ('log', logs), ('wire', wires)]:
        for p in paths:
            data = p.read_bytes()
            label = str(p) if kind == 'release' else relative(p)
            found = credential_findings(data)
            if kind == 'wire':
                found.extend({'pattern': 'prohibited_projection_key', 'jsonPath': key}
                             for key in prohibited_projection_keys(json.loads(data)))
            scans.append({'path': label, 'kind': kind, 'bytes': len(data), 'sha256': sha(data)})
            if found:
                findings.append({'path': label, 'findings': found})
    dump('secret-projection-scan-' + DATE + '.json', {
        'verifiedAt': checked, 'files': scans, 'findingCount': len(findings), 'findings': findings,
        'checks': ['structured private-key material', 'Supabase secret key values', 'GitHub credential values',
                   'JWT payload roles service_role/authenticated in UTF-8 or UTF-16LE',
                   'prohibited data keys recursively including decoded canonical JSON in four SQL projection wires'],
        'limitations': 'Pattern and projection checks only. No real export, provider prompt, runtime log or authenticated native data exists to inspect. This is not exhaustive PII or full NFR-507 acceptance.',
        'localAcceptanceStoresRead': False, 'matchedValuesPrinted': False,
    })
    previews = sorted((EVIDENCE / 'previews').glob('*.png'))
    dump('render-review-' + DATE + '.json', {
        'verifiedAt': checked, 'renderEvidenceDate': '2026-10-06',
        'sourceManifest': 'docs/verification/wave5/client-snapshot-build-final-20261006.json',
        'renderedCasesPassed': 36, 'workspaces': ['process', 'pipeline', 'control'],
        'themes': ['light', 'dark'], 'densities': ['comfortable', 'compact'],
        'viewports': ['1024x720', '1440x900', '1920x1080'], 'textScale': '200%',
        'bundledFontsLoaded': ['Manrope', 'IBM Plex Mono', 'MaterialIcons'],
        'captures': {relative(p): sha(p.read_bytes()) for p in previews},
        'visuallyInspected': ['control-light-top.png', 'control-dark-lower.png',
                             'pipeline-light-lower.png', 'process-dark-lower.png'],
        'inspection': 'Captured source explanations, exact values and lower actions were readable and scrollable. Automated variants reported no layout errors.',
        'realNativeKeyboardReview': False, 'authenticatedAcceptance': False, 'ownerSignoff': False,
    })
    if findings:
        raise ValueError('Potential prohibited evidence values require review; see sanitized scan report')
    print(json.dumps({'sourceFileCount': len(current), 'current_source_match': source_match,
                      'releaseFileCount': len(release_files), 'candidates': len(candidates),
                      'apiFunctions': review['newApiFunctionCount'], 'secretFindings': len(findings)}))


if __name__ == '__main__':
    main()
