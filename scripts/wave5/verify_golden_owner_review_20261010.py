import base64
import hashlib
import io
import json
import pathlib
import re
import subprocess
import sys
from PIL import Image

root = pathlib.Path(__file__).resolve().parents[2]
report_path = root / sys.argv[1]
report_bytes = report_path.read_bytes()
report = json.loads(report_bytes)
html_bytes = (root / report['html']['path']).read_bytes()
digest = lambda data: hashlib.sha256(data).hexdigest()
assert digest(html_bytes) == report['html']['sha256'], 'HTML hash drift'
html = html_bytes.decode('utf-8')
match = re.search(r'<script id="review-data" type="application/json">(.*?)</script>', html, re.S)
assert match, 'Embedded review data missing'
data = json.loads(match.group(1))
embedded_core = {key: value for key, value in data.items() if key not in ['reviewSha256', 'cases']}
assert embedded_core == report['reviewCore'], 'Embedded core metadata drift'
node_hash = subprocess.run(['node', '-e', "const fs=require('node:fs'),crypto=require('node:crypto');const v=JSON.parse(fs.readFileSync(0,'utf8'));process.stdout.write(crypto.createHash('sha256').update(JSON.stringify(v)).digest('hex'));"], input=json.dumps(embedded_core, ensure_ascii=False), encoding='utf-8', capture_output=True, check=True).stdout
assert node_hash == report['reviewSha256'], 'Review core hash drift'
assert data['reviewSha256'] == report['reviewSha256'], 'Review hash mismatch'
assert data['candidateBundleSha256'] == report['candidateBundleSha256'], 'Candidate hash mismatch'
assert len(data['cases']) == 83 and len(data['requirements']) == 109
assert len({case['stem'] for case in data['cases']}) == 83
assert len({row['id'] for row in data['requirements']}) == 109
assert not any(row['ownerAccepted'] for row in data['requirements'])
assert report['actualOwnerDecisionsRecorded'] == 0
assert report['allDecisionsInitiallyPending'] is True
assert report['embeddedImages'] == 249
metadata = {case['stem']: case for case in report['images']}
assert len(metadata) == 83 and len(report['images']) == 83
case_metadata = [{key: value for key, value in case.items() if key not in ['approved', 'candidate', 'diff']} for case in data['cases']]
assert case_metadata == report['images'] == report['reviewCore']['images'], 'Displayed image metadata drift'
decoded = 0
for case in data['cases']:
    bound = metadata[case['stem']]
    for key, hash_key in [('approved', 'approvedSha256'), ('candidate', 'candidateSha256'), ('diff', 'diffSha256')]:
        uri = case[key]
        assert uri.startswith('data:image/png;base64,'), 'Nonlocal image asset'
        raw = base64.b64decode(uri.split(',', 1)[1], validate=True)
        assert digest(raw) == bound[hash_key] == case[hash_key], 'Embedded PNG hash drift'
        with Image.open(io.BytesIO(raw)) as image:
            image.load()
            assert image.format == 'PNG'
            assert list(image.size) == bound['dimensions'] == case['dimensions']
        decoded += 1
assert len(re.findall(r'<script\b', html)) == 2
assert not re.search(r'<(?:script|img|link)\b[^>]*\b(?:src|href)\s*=\s*[\"\'](?:https?:|//)', html, re.I)
assert "connect-src 'none'" in html
assert 'localStorage' not in html and 'sessionStorage' not in html
assert 'submittedByOwner:false' in html
out = {'verifiedAtSource': str(report_path.relative_to(root)).replace('\\', '/'), 'reportSha256': digest(report_bytes), 'htmlSha256': digest(html_bytes), 'decodedPngs': decoded, 'images': 83, 'requirements': 109, 'ownerAccepted': 0, 'selfContained': True, 'scope': 'Artifact validation only; browser interaction and native keyboard are separate.'}
print(json.dumps(out, indent=2))
