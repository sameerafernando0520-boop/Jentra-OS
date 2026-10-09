"""Read exactly the owner-approved six migrations after live drift checks."""
import datetime
import hashlib
import json
from pathlib import Path
import subprocess

ROOT = Path(__file__).resolve().parents[2]
E = ROOT / 'docs/verification/wave5'
EXPECTED = [
    'supabase/migrations/20261006140000_wave5_process_metrics.sql',
    'supabase/migrations/20261006143000_wave5_pipeline_forecasts.sql',
    'supabase/migrations/20261006150000_wave5_trusted_metering.sql',
    'supabase/migrations/20261006153000_wave5_operator_isolation.sql',
    'supabase/migrations/20261006160000_wave5_human_proposals.sql',
    'supabase/migrations/20261006170000_wave5_synthetic_subscriptions.sql',
]


def read(name):
    return json.loads((E / name).read_text(encoding='utf-8'))


def functions(rows):
    return {(r['schema'], r['name'], r['arguments']): r for r in rows}


def main():
    if (E / 'installation-progress-20261008.json').exists():
        raise ValueError('Installation has already begun; use the recorded ledger mapping instead of replaying approved files')
    review = read('installation-review-20261008.json')
    original = read('live-baseline-20261008.json')
    dependencies = read('command-dependencies-20261008.json')
    live = read('installation-preflight-20261008.json')
    if review['targetProjectId'] != 'xpdoufauvrbdmxgngetv' or [c['path'] for c in review['candidatesInOrder']] != EXPECTED:
        raise ValueError('Owner-approved target/list does not match')
    for key in ['migrationCount', 'latestVersion', 'apiFunctionCount', 'ledger',
                'analyticsSchema', 'intelligenceControlSchema', 'trialStartedAtColumnCount',
                'providerColumns', 'providerRls']:
        if live[key] != original[key]:
            raise ValueError('Live pre-install contract drift: ' + key)
    expected_functions = functions(original['functionFingerprints'])
    expected_functions.update(functions(dependencies['functions']))
    if functions(live['functionFingerprints']) != expected_functions:
        raise ValueError('Live API/command dependency fingerprints changed')
    candidates = []
    for item in review['candidatesInOrder']:
        path = ROOT / item['path']
        raw = path.read_bytes()
        normalized = path.read_text(encoding='utf-8')
        if hashlib.sha256(raw).hexdigest() != item['bytesSha256'] or hashlib.sha256(normalized.encode()).hexdigest() != item['normalizedSqlSha256']:
            raise ValueError('Approved migration bytes changed: ' + item['path'])
        candidates.append({'path': item['path'], 'name': path.stem[15:],
                           'bytesSha256': item['bytesSha256'],
                           'normalizedSqlSha256': item['normalizedSqlSha256'],
                           'query': raw.decode('utf-8')})
    approval = {
        'recordedAt': datetime.datetime.now(datetime.timezone.utc).isoformat(),
        'humanInstruction': 'Approved: install those six migrations in xpdoufauvrbdmxgngetv.',
        'targetProjectId': review['targetProjectId'],
        'approvedReview': 'docs/verification/wave5/installation-review-20261008.json',
        'approvedReviewSha256': hashlib.sha256((E / 'installation-review-20261008.json').read_bytes()).hexdigest(),
        'preflight': 'docs/verification/wave5/installation-preflight-20261008.json',
        'preflightSha256': hashlib.sha256((E / 'installation-preflight-20261008.json').read_bytes()).hexdigest(),
        'sourceHeadAtInstallation': subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=ROOT, text=True).strip(),
        'sourceAndProviderMatch': True,
        'candidatesInOrder': [{k: v for k, v in c.items() if k != 'query'} for c in candidates],
        'excludedScopes': review['excluded'], 'bootstrapAuthorized': False,
    }
    (E / 'installation-authorization-20261008.json').write_text(json.dumps(approval, indent=2) + '\n', encoding='utf-8')
    print(json.dumps({'projectId': review['targetProjectId'], 'sourceAndProviderMatch': True, 'candidates': candidates}))


if __name__ == '__main__':
    main()
