"""Compose the unchanged six fixtures against installed functions, then rollback."""
import hashlib
import importlib.util
import json
from pathlib import Path
import re
import sys

sys.dont_write_bytecode = True

ROOT = Path(__file__).resolve().parents[2]
E = ROOT / 'docs/verification/wave5'


def main():
    spec = importlib.util.spec_from_file_location('candidate_inputs', ROOT / 'scripts/wave5/prepare_candidates.py')
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    reference = json.loads((E / 'subscription-native-development-20261006.hashes.json').read_text(encoding='utf-8'))
    parts = ['begin;']
    sources = {}
    for name in module.FIXTURES:
        content = (ROOT / name).read_text(encoding='utf-8')
        value = hashlib.sha256(content.encode()).hexdigest()
        if value != reference['source_hashes'][name]:
            raise ValueError('Fixture changed since candidate review: ' + name)
        if re.search(r'(?im)^\s*(?:begin|commit|rollback)\s*;', content):
            raise ValueError('Fixture contains an unexpected transaction boundary')
        sources[name] = value
        parts.append(content.split('select * from finish(true);')[0])
    query = '\n'.join(parts)
    query = query.replace('select no_plan();', 'select no_plan();\ncreate temporary table w5_tap(message text);')
    query = re.sub(r'^select (is|ok|throws_ok)\(', r'insert into w5_tap select \1(', query, flags=re.M)
    query += '\nselect * from finish(true);\nselect jsonb_agg(message) tap from w5_tap;\nrollback;\n'
    if any(name.split('/')[-1] in query for name in module.MIGRATIONS):
        raise ValueError('Installed check must not reinstall migrations')
    output = E / 'installed-strict-checks-20261008.sql'
    output.write_text(query, encoding='utf-8')
    report = {'installedFunctionsUsed': True, 'migrationsIncluded': False,
              'strictFinish': True, 'rollback': True,
              'normalizedQuerySha256': hashlib.sha256(query.encode()).hexdigest(),
              'queryBytesSha256': hashlib.sha256(output.read_bytes()).hexdigest(),
              'fixtureNormalizedSha256': sources}
    (E / 'installed-strict-checks-20261008.hashes.json').write_text(json.dumps(report, indent=2) + '\n', encoding='utf-8')
    print(json.dumps(report))


if __name__ == '__main__':
    main()
