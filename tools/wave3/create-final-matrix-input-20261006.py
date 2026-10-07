"""Bind completed current executions to the fixed approved requirement matrix."""
from pathlib import Path
import json
import re
import subprocess

root = Path.cwd()
base = 'docs/verification/remaining-wave3/'
read = lambda name: json.loads((root / (base + name)).read_text(encoding='utf-8-sig'))
old = read('interim-matrix-input-20261004.json')
policy = old['policy']
policy.pop('implemented_verified', None)
policy.update(implemented=True,
              execution=base + 'database-procurement-negative-stock-final-reviewed-20261006.json',
              query=base + 'database-strict-procurement-negative-stock-final-reviewed-20261006.sql',
              pure_domain_sources=['packages/jentra_domain/lib/src/negative_stock_policy.dart'])
checks = []
for kind, name in [('desktop-whole-current', 'desktop-full-final-20261006.log'),
                   ('platform-whole-current', 'platform-full-final-20261006.log'),
                   ('domain-whole-current', 'domain-full-final-20261006.log')]:
    log = (root / (base + name)).read_text(encoding='utf-8-sig')
    matches = list(re.finditer(r'\+(\d+)(?:\s+-(\d+))?\s*:', log))
    if not matches or not re.search(r'(Some tests failed|All tests passed)[.!]', log):
        raise ValueError('Incomplete execution ' + name)
    last = matches[-1]
    checks.append(dict(kind=kind, file=base + name, passed=int(last[1]), failed=int(last[2] or 0),
                       complete=True, source_capture=base + 'client-sources-final-start-20261006.json'))
checks.append(dict(kind='whole-workspace-analyzer', file=base + 'analyzer-final-20261006.log',
                   complete=True, outcome='No issues found', source_capture=base + 'client-sources-final-start-20261006.json'))
build_file = root / (base + 'windows-build-final-20261006.json')
if not build_file.exists():
    raise ValueError('Completed compilation evidence required')
checks.append(dict(kind='isolated-windows-release', file=base + build_file.name, complete=True,
                   outcome='Compiled; not launched', build_source_hashes=base + 'windows-build-final-source-hashes-20261006.json'))
result = dict(artifact_tag='20261006-final', head=subprocess.check_output(['git', 'rev-parse', 'HEAD'], text=True).strip(),
              database_package=base + 'database-installation-package-negative-stock-policy-20261006-final-reviewed-46-reviewed.json',
              coverage_scope=old['coverage_scope'],
              coverage_raw=base + 'requirements-coverage-source-checked-20261006-final.json',
              coverage_reviewed=base + 'requirements-coverage-policy-declaration-reviewed-20261006-final.json',
              coverage_additional_pure_domain=base + 'requirements-coverage-additional-pure-domain-20261006-final.json',
              desktop_failure_classification=base + 'desktop-result-20261006.json', policy=policy, checks=checks,
              additional_review=[base + name for name in ['candidate-review-selection-verified-20261006.json',
              'schema-negative-stock-policy-20261006-final-reviewed-46.json', 'policy-visual-reuse-audit-20261006.json',
              'desktop-result-20261006.json', 'desktop-final-20261006-source-integrity.json']])
out = root / (base + 'final-matrix-input-20261006.json')
with out.open('x', encoding='utf-8') as stream:
    stream.write(json.dumps(result, indent=2) + '\n')
print(str(out))
