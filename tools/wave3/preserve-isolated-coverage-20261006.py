"""Preserve executed LCOV and normalize only its isolated source path prefix."""
import argparse
import hashlib
import json
from pathlib import Path

p = argparse.ArgumentParser()
p.add_argument('--snapshot', required=True)
p.add_argument('--package', required=True, choices=['apps/jentra_desktop', 'packages/jentra_platform'])
p.add_argument('--label', required=True)
a = p.parse_args()
root = Path.cwd()
snapshot = Path(a.snapshot).resolve()
source = snapshot / a.package / 'coverage/lcov.info'
dest = root / 'build/remaining-wave3'
raw = dest / (a.label + '-isolated-raw.info')
normalized = dest / (a.label + '.info')
evidence = root / 'docs/verification/remaining-wave3' / (a.label + '-coverage-preservation.json')
if any(x.exists() for x in [raw, normalized, evidence]):
    raise ValueError('Preserve previous artifacts; choose a new label')
data = source.read_bytes()
text = data.decode('utf-8')
prefix = snapshot.as_posix() + '/'
lines = text.splitlines(keepends=True)
count = 0
for i, line in enumerate(lines):
    if line.startswith('SF:'):
        path = line[3:].rstrip('\r\n').replace('\\', '/')
        if path.lower().startswith(prefix.lower()):
            lines[i] = 'SF:' + root.as_posix() + '/' + path[len(prefix):] + '\n'
            count += 1
result = ''.join(lines).encode('utf-8')
if [x for x in text.splitlines() if not x.startswith('SF:')] != [x for x in result.decode().splitlines() if not x.startswith('SF:')]:
    raise ValueError('Measured record change')
dest.mkdir(parents=True, exist_ok=True)
raw.write_bytes(data)
normalized.write_bytes(result)
report = {'source': str(source), 'raw': str(raw), 'normalized': str(normalized),
          'raw_sha256': hashlib.sha256(data).hexdigest(),
          'normalized_sha256': hashlib.sha256(result).hexdigest(),
          'normalized_source_paths': count, 'measurement_records_unchanged': True}
evidence.write_text(json.dumps(report, indent=2) + '\n', encoding='utf-8')
print(json.dumps(report))
