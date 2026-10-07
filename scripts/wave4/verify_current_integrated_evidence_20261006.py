"""Reuse actual whole-workspace executions only after verifying their source hashes."""
from pathlib import Path
import hashlib
import json
import re
from datetime import datetime, timezone
import prepare_integrated_verification as selection

ROOT = Path(__file__).resolve().parents[2]
BASE = ROOT / 'docs/verification/wave4'
PRIOR = ROOT / 'docs/verification/remaining-wave3'
sha = lambda p: hashlib.sha256(p.read_bytes()).hexdigest()
read = lambda p: json.loads(p.read_text(encoding='utf-8-sig'))
capture = read(PRIOR / 'client-sources-final-start-20261006.json')
snapshot = Path(capture['snapshot'])
drift = [str(place / row['file']) for row in capture['files'] for place in [ROOT, snapshot]
         if not (place / row['file']).is_file() or sha(place / row['file']) != row['sha256']]
if drift:
    raise ValueError('Actual execution source drift ' + str(drift))
checks = []
for package, names, filename in [
    ('packages/jentra_domain', selection.DOMAIN, 'domain-full-serialized-20261006.log'),
    ('packages/jentra_platform', selection.PLATFORM, 'platform-full-final-20261006.log'),
    ('apps/jentra_desktop', selection.DESKTOP, 'desktop-full-final-20261006.log')]:
    log = (BASE if package == 'packages/jentra_domain' else PRIOR) / filename
    text = log.read_text(encoding='utf-8-sig').replace('\\', '/')
    terminal = list(re.finditer(r'\+(\d+)(?:\s+-(\d+))?\s*:', text))[-1]
    if not re.search(r'(Some tests failed|All tests passed)[.!]', text):
        raise ValueError('Incomplete full execution')
    required = [package + '/test/' + name + '_test.dart' for name in names]
    missing = [file for file in required if ('test/' + Path(file).name) not in text]
    if missing:
        raise ValueError('Required vertical not executed ' + str(missing))
    failures = []
    for match in re.finditer(r'^.*?\+\d+ -\d+: (.*?\.dart): (.*?) \[E\]\r?$', text, re.M):
        name = Path(match[1]).name
        if any(Path(file).name == name for file in required):
            failures.append({'test_file': name, 'test': match[2]})
    checks.append({'package': package, 'log': str(log.relative_to(ROOT)), 'log_sha256': sha(log),
                   'whole_suite_passed': int(terminal[1]), 'whole_suite_failed': int(terminal[2] or 0),
                   'required_vertical_files': required, 'required_vertical_failures': failures,
                   'required_verticals_pass': not failures})
analysis = PRIOR / 'analyzer-final-20261006.log'
if 'No issues found' not in analysis.read_text(encoding='utf-8-sig'):
    raise ValueError('Whole analyzer did not pass')
build = read(PRIOR / 'windows-build-final-20261006.json')
if not build['current_source_match'] or sha(Path(build['binary'])) != build['sha256']:
    raise ValueError('Compilation binding failed')
composition_path = BASE / 'install-composition-current-evidence-20261005.json'
composition = read(composition_path)
source_mismatches = [name for name, digest in composition['source_hashes'].items() if sha(ROOT / name) != digest]
artifact_mismatches = [name for name, digest in composition['artifacts'].items() if sha(ROOT / name) != digest]
query = BASE / 'install-composition-executed-v2-20261005.sql'
sql = query.read_text(encoding='utf-8-sig')
if source_mismatches or artifact_mismatches or not sql.startswith('begin;') or not sql.rstrip().endswith('rollback;') or 'finish(true)' not in sql:
    raise ValueError('Retained strict composition drift')
if any((ROOT / name).read_text(encoding='utf-8-sig') not in sql for name in composition['source_hashes']):
    raise ValueError('Composition omitted a current candidate body')
report = {'observed_at': datetime.now(timezone.utc).isoformat(), 'execution_capture': str((PRIOR / 'client-sources-final-start-20261006.json').relative_to(ROOT)),
          'execution_capture_sha256': sha(PRIOR / 'client-sources-final-start-20261006.json'),
          'source_files': len(capture['files']), 'current_source_match': True, 'source_mismatches': drift,
          'checks': checks, 'analyzer': {'log': str(analysis.relative_to(ROOT)), 'sha256': sha(analysis), 'passed': True},
          'build': build, 'composition': {'evidence': str(composition_path.relative_to(ROOT)), 'sha256': sha(composition_path),
          'actual_assertions': composition['actual_assertions'], 'candidate_migrations': composition['candidate_migrations'],
          'candidate_tables': composition['candidate_tables'], 'execution_date': '2026-10-05', 'source_match_reverified': True},
          'boundary': 'Source-verified reuse of actual completed Oct6 full client executions and Oct5 strict rollback composition. No new execution date assigned to retained tests/SQL. Compiled, not launched. Not installed, authenticated runtime, overlapping contention, load, restart, visual or owner acceptance.',
          'wave4_complete': False}
output = BASE / 'integrated-current-evidence-20261006.json'
with output.open('x', encoding='utf-8') as out:
    out.write(json.dumps(report, indent=2) + '\n')
print(json.dumps({'output': str(output), 'source_match': True,
                 'vertical_failures': [row['required_vertical_failures'] for row in checks], 'composition_candidates': 15}))
