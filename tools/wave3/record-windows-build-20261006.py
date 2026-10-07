"""Record successful isolated compilation without launching the executable."""
from pathlib import Path
import hashlib
import json
from datetime import datetime, timezone

root = Path.cwd()
base = root / 'docs/verification/remaining-wave3'
capture = json.loads((base / 'client-sources-final-start-20261006.json').read_text(encoding='utf-8-sig'))
snapshot = Path(capture['snapshot'])
log = base / 'windows-build-final-20261006.log'
if 'Built build' not in log.read_text(encoding='utf-8-sig'):
    raise ValueError('Successful Flutter build terminal required')
binary = snapshot / 'apps/jentra_desktop/build/windows/x64/runner/Release/jentra_desktop.exe'
if not binary.exists():
    raise ValueError('Expected isolated executable absent')
rows = []
for row in capture['files']:
    for place in [root, snapshot]:
        path = place / row['file']
        if hashlib.sha256(path.read_bytes()).hexdigest() != row['sha256']:
            raise ValueError('Build source drift ' + str(path))
    rows.append({'path': str(root / row['file']), 'sha256': row['sha256']})
report = {'observed_at': datetime.now(timezone.utc).isoformat(), 'status': 'compiled', 'exit_code': 0,
          'binary': str(binary), 'sha256': hashlib.sha256(binary.read_bytes()).hexdigest(),
          'source_files': len(rows), 'current_source_match': True, 'log': str(log),
          'log_sha256': hashlib.sha256(log.read_bytes()).hexdigest(),
          'boundary': 'Isolated current-source release compilation only. No launch, authenticated session, profile/store change, installed acceptance or owner signoff.'}
for name, value in [('windows-build-final-source-hashes-20261006.json', rows), ('windows-build-final-20261006.json', report)]:
    with (base / name).open('x', encoding='utf-8') as out:
        out.write(json.dumps(value, indent=2) + '\n')
print(json.dumps(report))
