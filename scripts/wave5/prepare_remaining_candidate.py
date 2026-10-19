"""Compose only new candidates with installed fixture providers; no installation."""
import hashlib
import json
from pathlib import Path
import re

ROOT=Path(__file__).resolve().parents[2]
NEW=['supabase/migrations/20260925002000_wave3_financial_statements.sql',
     'supabase/migrations/20260926009000_wave3_governed_report_exports.sql',
     'supabase/migrations/20261008090000_wave5_historical_pipeline.sql',
     'supabase/migrations/20261008093000_wave5_persistent_delivery.sql',
     'supabase/migrations/20261008100000_wave5_invocation_storage.sql',
     'supabase/migrations/20261008103000_wave5_dated_cash.sql',
     'supabase/migrations/20261008110000_wave5_governed_export_adapter.sql',
     'supabase/migrations/20261008113000_wave5_statement_classifications.sql']
FIXTURES=['supabase/wave_tests/wave5_process_metrics_test.sql','supabase/wave_tests/wave5_remaining_adapters_test.sql',
          'supabase/wave_tests/wave5_realized_mapping_test.sql']
parts=['begin;']
hashes={}
for name in NEW+FIXTURES:
    data=(ROOT/name).read_text(encoding='utf-8')
    if re.search(r'(?im)^\s*(?:commit|rollback)\s*;',data):
        raise ValueError('Unexpected transaction boundary: '+name)
    hashes[name]=hashlib.sha256((ROOT/name).read_bytes()).hexdigest()
    parts.append(data.split('select * from finish(true);')[0])
query='\n'.join(parts).replace('select no_plan();','select no_plan();\ncreate temporary table w5_tap(message text);')
query=re.sub(r'^select (is|ok|throws_ok)\(',r'insert into w5_tap select \1(',query,flags=re.M)
query+='\nselect * from finish(true);\nselect jsonb_agg(message) tap from w5_tap;\nrollback;\n'
query=query.rstrip()+'\n'
e=ROOT/'docs/verification/wave5'
(e/'remaining-candidate-20261008.sql').write_bytes(query.encode('utf-8'))
(e/'remaining-candidate-20261008.hashes.json').write_text(json.dumps({'candidateSources':hashes,
 'querySha256':hashlib.sha256(query.encode()).hexdigest(),'strictFinish':True,'rollback':True,
 'installedMigrationsReplayed':False},indent=2)+'\n',encoding='utf-8')
print('Prepared rollback candidate with '+str(len(query.encode()))+' bytes')
