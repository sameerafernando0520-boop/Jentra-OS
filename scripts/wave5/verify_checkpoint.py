"""Validate the review packet's local links, identities and evidence fingerprints."""
import datetime
import hashlib
import json
from pathlib import Path
import re

ROOT = Path(__file__).resolve().parents[2]
E = ROOT / 'docs/verification/wave5'
DOCS = ['docs/development/wave5-status.md',
        'docs/verification/wave5/checkpoint-20261008.md',
        'docs/verification/wave5/installation-review-20261008.md',
        'docs/verification/wave5/requirement-matrix-20261008.md',
        'docs/verification/wave5/integrated-runtime-protocol-20261006.md',
        'docs/blueprint/wave5/W5_01_PROCESS_METRICS_CONTRACT.md',
        'docs/blueprint/wave5/W5_02_03_FORECAST_AND_RATIO_CONTRACT.md',
        'docs/blueprint/wave5/W5_04_07_CONTROL_CONTRACT.md',
        'docs/blueprint/wave5/WAVE5_INTELLIGENCE_AND_CONTROL_SPEC.md']
if (E / 'installation-result-20261008.json').exists():
    DOCS.append('docs/verification/wave5/installation-result-20261008.md')


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def load(name):
    return json.loads((E / name).read_text(encoding='utf-8'))


def main():
    failures = []
    links = 0
    for name in DOCS:
        path = ROOT / name
        text = path.read_text(encoding='utf-8')
        if re.search(r'(?m)^(?:<<<<<<<|=======|>>>>>>>)', text):
            failures.append(name + ': conflict marker')
        for target in re.findall(r'\[[^\]\n]+\]\(([^)\n]+)\)', text):
            if re.match(r'^[a-z]+://', target):
                continue
            links += 1
            location, _, anchor = target.partition('#')
            destination = (path.parent / location).resolve() if location else path
            if not destination.exists():
                failures.append(name + ': missing link ' + target)
            elif anchor and destination.suffix == '.md':
                other = destination.read_text(encoding='utf-8')
                headings = set()
                for heading in re.findall(r'(?m)^#+ (.+)$', other):
                    headings.add(re.sub(r'[^a-z0-9 _-]', '', heading.lower()).replace(' ', '-'))
                headings.update(re.findall(r'<a id="([^"]+)"></a>', other))
                if anchor not in headings:
                    failures.append(name + ': missing anchor ' + target)
    matrix = load('requirement-matrix-20261008.json')
    counts = {kind: sum(row['id'].startswith(kind + '-') for row in matrix['rows'])
              for kind in ('FR', 'NFR', 'AC', 'EC')}
    if counts != {'FR': 46, 'NFR': 14, 'AC': 25, 'EC': 24} or matrix['wholeWaveComplete']:
        failures.append('Requirement count/status mismatch')
    if any(row['ownerAccepted'] for row in matrix['rows']):
        failures.append('Unrecorded owner acceptance')
    review = load('installation-review-20261008.json')
    api_functions = []
    for candidate in review['candidatesInOrder']:
        if digest(ROOT / candidate['path']) != candidate['bytesSha256']:
            failures.append('Migration byte hash drift: ' + candidate['path'])
        api_functions.extend(f['name'] for f in candidate['functions'] if f['name'].startswith('api.'))
    if len(review['candidatesInOrder']) != 6 or len(api_functions) != 22 or len(set(api_functions)) != 22:
        failures.append('Installation list/function mismatch')
    if review['approvalRecorded'] or review['targetProjectId'] != 'xpdoufauvrbdmxgngetv':
        failures.append('Installation target/approval mismatch')
    worker = load('worker-source-attribution-20261008.json')
    for path, expected in worker['sourceSha256'].items():
        if digest(ROOT / path) != expected:
            failures.append('Worker source drift: ' + path)
    coverage = load('coverage-final-20261006.json')
    domain = [f for f in coverage['files'] if f['path'].startswith('packages/jentra_domain/lib/')]
    branches = {'hit': sum(f['branch_hit'] for f in domain), 'count': sum(f['branch_count'] for f in domain)}
    if branches != {'hit': 193, 'count': 199}:
        failures.append('Critical-domain coverage attribution differs from report')
    report = {'verifiedAt': datetime.datetime.now(datetime.timezone.utc).isoformat(),
              'documentsChecked': DOCS, 'localLinksChecked': links, 'identifierCounts': counts,
              'migrationCount': 6, 'apiFunctionCount': 22, 'criticalDomainBranches': branches,
              'wholeWaveComplete': False, 'failureCount': len(failures), 'failures': failures}
    filename = 'installation-document-validation-20261008.json' if (E / 'installation-result-20261008.json').exists() else 'checkpoint-validation-20261008.json'
    (E / filename).write_text(json.dumps(report, indent=2) + '\n', encoding='utf-8')
    print(json.dumps(report))
    return 1 if failures else 0


if __name__ == '__main__':
    raise SystemExit(main())
