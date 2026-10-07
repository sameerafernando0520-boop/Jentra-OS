"""Create a current 86-ID review while retaining every open acceptance boundary."""
from pathlib import Path
import hashlib
import json
import re
from datetime import datetime, timezone

root = Path(__file__).resolve().parents[2]
base = root / 'docs/verification/wave4'
sha = lambda p: hashlib.sha256(p.read_bytes()).hexdigest()
read = lambda name: json.loads((base / name).read_text(encoding='utf-8-sig'))
matrix = read('requirement-review-20261006.json')
integration = read('integrated-current-evidence-20261006.json')
prepared = read('install-composition-prepared-hashes-20261006.json')
executed = read('install-composition-result-20261006.json')
query = root / executed['query']
sql = query.read_text(encoding='utf-8-sig')
if sha(query) != prepared['sql_sha256'] or executed['result'].get('isError'):
    raise ValueError('Actual composition query/result mismatch')
raw = json.loads(executed['result']['content'][0]['text'])['result']
rows = json.loads(re.search(r'^<untrusted-data-[^>]+>\s*([\s\S]*?)\s*</untrusted-data-', raw, re.M)[1])
if rows != [{'assertion_count': 14, 'candidate_migrations': 15, 'candidate_tables': 111}]:
    raise ValueError('Incomplete strict composition result')
for name, digest in prepared['source_hashes'].items():
    source = root / name
    if sha(source) != digest or source.read_text(encoding='utf-8-sig') not in sql:
        raise ValueError('Executed candidate body/source mismatch')
if not sql.startswith('begin;') or not sql.rstrip().endswith('rollback;') or 'finish(true)' not in sql:
    raise ValueError('Strict rollback boundary absent')
remaining = {
    'employee': 'Authenticated timeline/consumed history, real overlap, native restart and owner evidence',
    'calendar': 'Install resolution/assignment candidates; authenticated/native/contention evidence',
    'organization': 'Specific installation approval, installed/native and graph contention evidence',
    'private_hr': 'Trusted worker readiness, actual synthetic workspace and two-user private-byte acceptance',
    'workforce': 'Installed/authenticated work/leave correction and real balance/ownership contention',
    'payroll': 'Two changed payroll visual baselines require owner review; installation, real posting/settlement contention and authenticated walkthrough',
    'corrections': 'Installation, actual competing billing/source correction and owner acceptance',
    'projects': 'Installation, authenticated plan/time/cost and source contention',
    'finance': 'Installation and real billing contention; owner acceptance',
    'milestones': 'Installation, concurrent approval/billing and owner acceptance',
    'service': 'Generic stock reservation/issue/return provider absent; installation, actual dispatch/occurrence races and owner acceptance',
    'assets': 'Procurement/stock conversion providers absent; installation, depreciation/disposal races and owner acceptance',
    'asset_equipment': 'Installation, real asset/service overlap and authenticated owner acceptance',
    'expense_evidence': 'Specific installation and two Edge deployments; trusted worker setup/probe, authenticated private-byte acceptance and owner approval',
}
for name, module in matrix['modules'].items():
    module['remaining'] = remaining[name]
for row in matrix['requirements']:
    row['remaining'] = [remaining[name] for name in row['modules']]
    row['state'] = 'candidate implementation and current integration verified; required acceptance open'
    if 'service' in row['modules'] or 'assets' in row['modules']:
        row['state'] = 'current supported candidates verified; dependent stock/procurement providers and acceptance open'
matrix['observed_at'] = datetime.now(timezone.utc).isoformat()
matrix['current_integrated_evidence'] = {'path': str((base / 'integrated-current-evidence-20261006.json').relative_to(root)),
                                        'sha256': sha(base / 'integrated-current-evidence-20261006.json'),
                                        'source_match': integration['current_source_match'],
                                        'required_vertical_failures': [r['required_vertical_failures'] for r in integration['checks']]}
matrix['current_strict_composition'] = {'query': str(query.relative_to(root)), 'query_sha256': sha(query),
    'result': 'docs/verification/wave4/install-composition-result-20261006.json',
    'result_sha256': sha(base / 'install-composition-result-20261006.json'),
    'assertions': 14, 'candidate_migrations': 15, 'candidate_tables': 111, 'strict_finish': True, 'rollback': True,
    'source_hashes': prepared['source_hashes'], 'installed': False}
matrix['fresh_auxiliary_checks'] = [{'path': 'docs/verification/wave4/' + name, 'sha256': sha(base / name)}
    for name in ['expense-edge-current-20261006.log', 'runtime-validator-current-20261006.log']]
out = base / 'requirement-review-final-20261006.json'
with out.open('x', encoding='utf-8') as stream:
    stream.write(json.dumps(matrix, indent=2) + '\n')
print(json.dumps({'output': str(out), 'approved_ids': len(matrix['requirements']), 'candidate_migrations': 15,
                  'current_source_match': integration['current_source_match'], 'wave4_complete': False}))
