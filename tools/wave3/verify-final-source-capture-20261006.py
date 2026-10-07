"""Verify retained execution hashes against both the workspace and isolated copy."""
from pathlib import Path
import hashlib
import json
from datetime import datetime, timezone
import argparse

p = argparse.ArgumentParser()
p.add_argument('--label', required=True)
a = p.parse_args()
root = Path.cwd()
capture_path = root / 'docs/verification/remaining-wave3/client-sources-final-start-20261006.json'
capture = json.loads(capture_path.read_text(encoding='utf-8-sig'))
snapshot = Path(capture['snapshot'])
drift = []
for row in capture['files']:
    for place in [root, snapshot]:
        file = place / row['file']
        digest = hashlib.sha256(file.read_bytes()).hexdigest() if file.exists() else None
        if digest != row['sha256']:
            drift.append({'file': str(file), 'expected': row['sha256'], 'observed': digest})
out = root / 'docs/verification/remaining-wave3' / (a.label + '-source-integrity.json')
if out.exists():
    raise ValueError('Retain previous source review')
result = {'observed_at': datetime.now(timezone.utc).isoformat(), 'execution_capture': str(capture_path),
          'files': len(capture['files']), 'current_source_match': not drift, 'drift': drift}
out.write_text(json.dumps(result, indent=2) + '\n', encoding='utf-8')
print(json.dumps(result))
if drift:
    raise SystemExit(1)
