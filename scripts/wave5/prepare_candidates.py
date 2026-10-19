"""Prepare owned strict rollback composition and attributable SHA-256 hashes."""
import argparse
import hashlib
import json
from pathlib import Path
import re

ROOT = Path(__file__).resolve().parents[2]
MIGRATIONS = [
    'supabase/migrations/20261006140000_wave5_process_metrics.sql',
    'supabase/migrations/20261006143000_wave5_pipeline_forecasts.sql',
    'supabase/migrations/20261006150000_wave5_trusted_metering.sql',
    'supabase/migrations/20261006153000_wave5_operator_isolation.sql',
    'supabase/migrations/20261006160000_wave5_human_proposals.sql',
    'supabase/migrations/20261006170000_wave5_synthetic_subscriptions.sql',
]
FIXTURES = [
    'supabase/wave_tests/wave5_process_metrics_test.sql',
    'supabase/wave_tests/wave5_pipeline_forecasts_test.sql',
    'supabase/wave_tests/wave5_trusted_metering_test.sql',
    'supabase/wave_tests/wave5_operator_isolation_test.sql',
    'supabase/wave_tests/wave5_human_proposals_test.sql',
    'supabase/wave_tests/wave5_synthetic_subscriptions_test.sql',
]


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--output', required=True)
    args = parser.parse_args()
    output = (ROOT / args.output).resolve()
    if not output.is_relative_to(ROOT / 'docs/verification/wave5'):
        raise ValueError('Evidence must remain in the Wave 5 directory')
    selected = MIGRATIONS + FIXTURES
    contents = {name: (ROOT / name).read_text(encoding='utf-8') for name in selected}
    sections = ['begin;'] + [contents[name] for name in MIGRATIONS]
    for name in FIXTURES:
        fixture = contents[name]
        if 'select * from finish(true);' in fixture:
            fixture = fixture.split('select * from finish(true);')[0]
        sections.append(fixture)
    query = '\n'.join(sections)
    query = query.replace('select no_plan();', 'select no_plan();\ncreate temporary table w5_tap(message text);')
    query = re.sub(r'^select (is|ok|throws_ok)\(', r'insert into w5_tap select \1(', query, flags=re.M)
    query += '''
select * from finish(true);
select jsonb_agg(message) tap,(select result from w5_frozen) pipeline_snapshot,
 (select result from w5_results) process_snapshot,(select result from w5_proposal_wire) proposal_snapshot,
 (select result from w5_subscription_wire) subscription_snapshot from w5_tap;
rollback;
'''
    output.write_text(query, encoding='utf-8')
    after = {name: (ROOT / name).read_text(encoding='utf-8') for name in selected}
    report = {'source_stable': contents == after, 'strict_finish': True, 'rollback': True,
              'query_sha256': hashlib.sha256(query.encode()).hexdigest(),
              'source_hashes': {name: hashlib.sha256(text.encode()).hexdigest()
                                for name, text in contents.items()}}
    output.with_suffix('.hashes.json').write_text(json.dumps(report, indent=2)+'\n', encoding='utf-8')
    print(json.dumps(report))
    return 0 if contents == after else 1


if __name__ == '__main__':
    raise SystemExit(main())
