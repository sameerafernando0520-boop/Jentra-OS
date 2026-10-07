"""Compose all unapplied W4 DDL for a strict rollback-only installation review."""
import argparse
import datetime
import hashlib
import json
from pathlib import Path
import re

ROOT = Path(__file__).resolve().parents[2]
MIGRATIONS = (
    '20260926160000_wave4_calendar_resolution.sql',
    '20260926161000_wave4_organization.sql',
    '20260928082234_wave4_attendance_intervals.sql',
    '20260928083449_wave4_leave_ledger.sql',
    '20260930070000_wave4_synthetic_payroll.sql',
    '20260930070500_wave4_clock_batches.sql',
    '20260930071000_wave4_fixed_assets.sql',
    '20261001080000_wave4_projects_time.sql',
    '20261001090000_wave4_service.sql',
    '20261001100000_wave4_project_expenses_billing.sql',
    '20261001110000_wave4_payroll_corrections.sql',
    '20261002080000_wave4_project_payroll_impacts.sql',
    '20261004090000_project_milestones.sql',
    '20261005090000_service_asset_equipment.sql',
    '20261005120000_wave4_project_expense_evidence.sql',
)


def sha(data):
    return hashlib.sha256(data).hexdigest()


def quoted(values):
    return ','.join("'" + value.replace("'", "''") + "'" for value in values)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--output', required=True)
    parser.add_argument('--manifest', required=True)
    args = parser.parse_args()
    outputs = [(ROOT / name).resolve() for name in (args.output, args.manifest)]
    if not all(p.is_relative_to(ROOT) and not p.exists() for p in outputs):
        raise ValueError('Use new evidence paths inside the workspace')
    bodies, hashes, tables, functions = [], {}, set(), set()
    for name in MIGRATIONS:
        path = ROOT / 'supabase/migrations' / name
        data = path.read_bytes()
        text = data.decode('utf-8-sig')
        if re.search(r'^\s*(?:begin|commit|rollback)\s*;', text, re.M | re.I):
            raise ValueError('DDL contains a transaction boundary: ' + name)
        hashes[path.relative_to(ROOT).as_posix()] = sha(data)
        bodies.append(text)
        tables.update(re.findall(r'create\s+table\s+(\w+\.\w+)\s*\(', text, re.I))
        functions.update(re.findall(r'create\s+(?:or\s+replace\s+)?function\s+(\w+\.\w+)\s*\(', text, re.I))
        for original, renamed in re.findall(
                r'alter\s+function\s+(\w+\.\w+)\([^;]*?\)\s+rename\s+to\s+(\w+)\s*;', text, re.I):
            functions.add(original.split('.')[0] + '.' + renamed)
    for name, value in hashes.items():
        if sha((ROOT / name).read_bytes()) != value:
            raise ValueError('Source changed during preparation: ' + name)
    before = """begin;
set local lock_timeout='3s';
set local statement_timeout='90s';
create extension if not exists pgtap with schema extensions;
set local search_path=extensions,public,pg_catalog;
create temporary table w4_composition_before as select
 (select md5(coalesce(jsonb_agg(to_jsonb(r) order by role_id,permission_code)::text,'')) from core.role_permissions r) roles,
 (select md5(coalesce(jsonb_agg(to_jsonb(r) order by plan_code,entitlement_code)::text,'')) from billing.plan_entitlements r) plans,
 (select md5(coalesce(jsonb_agg(to_jsonb(r) order by tenant_id)::text,'')) from billing.tenant_subscriptions r) subscriptions,
 (select md5(coalesce(jsonb_agg(to_jsonb(r) order by version)::text,'')) from supabase_migrations.schema_migrations r) ledger,
 (select md5(coalesce(jsonb_agg(jsonb_build_object('id',p.oid,'definition',pg_get_functiondef(p.oid)) order by p.oid)::text,''))
  from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname in('core','finance') and p.prokind='f'
  and p.proname ~ '(journal|period|residual|allocate)') finance;
"""
    table_where = 'n.nspname||\'.\'||c.relname in(' + quoted(sorted(tables)) + ')'
    function_where = 'n.nspname||\'.\'||p.proname in(' + quoted(sorted(functions)) + ')'
    checks = f"""
create temporary table w4_composition_assertions(message text);
select no_plan();
insert into w4_composition_assertions select is((select count(*)::integer from pg_class c join pg_namespace n on n.oid=c.relnamespace where {table_where}),{len(tables)},'All candidate tables compose together');
insert into w4_composition_assertions select ok(not exists(select 1 from pg_class c join pg_namespace n on n.oid=c.relnamespace where {table_where} and(not c.relrowsecurity or not c.relforcerowsecurity)),'Every candidate tenant table forces RLS');
insert into w4_composition_assertions select ok(not exists(select 1 from pg_class c join pg_namespace n on n.oid=c.relnamespace where {table_where} and(has_table_privilege('authenticated',c.oid,'SELECT') or has_table_privilege('authenticated',c.oid,'INSERT') or has_table_privilege('authenticated',c.oid,'UPDATE') or has_table_privilege('authenticated',c.oid,'DELETE'))),'Authenticated callers cannot bypass candidate APIs through tables');
insert into w4_composition_assertions select ok(not exists(select 1 from pg_proc p join pg_namespace n on n.oid=p.pronamespace where {function_where} and n.nspname='api' and(not p.prosecdef or not coalesce(p.proconfig @> array['search_path=""'],false))),'All candidate API functions have protected empty search paths');
insert into w4_composition_assertions select ok(not exists(select 1 from pg_proc p join pg_namespace n on n.oid=p.pronamespace where {function_where} and has_function_privilege('anon',p.oid,'EXECUTE')),'Anonymous callers cannot execute candidate APIs or helpers');
insert into w4_composition_assertions select ok(not exists(select 1 from pg_proc p join pg_namespace n on n.oid=p.pronamespace where {function_where} and n.nspname<>'api' and has_function_privilege('authenticated',p.oid,'EXECUTE')),'Authenticated callers cannot bypass named APIs through owner helpers');
insert into w4_composition_assertions select ok(not exists(select 1 from pg_proc p join pg_namespace n on n.oid=p.pronamespace where {function_where} and n.nspname='api' and p.proname like '%_customer_base' and has_function_privilege('authenticated',p.oid,'EXECUTE')),'Renamed base commands cannot bypass the new internal asset guards');
insert into w4_composition_assertions select ok(not exists(select 1 from pg_proc p join pg_namespace n on n.oid=p.pronamespace where {function_where} and n.nspname='api' and p.proname ~ '^projects_expense_evidence_(service|worker)_' and has_function_privilege('authenticated',p.oid,'EXECUTE')),'Human callers cannot invoke trusted private byte or worker APIs');
insert into w4_composition_assertions select is((select md5(coalesce(jsonb_agg(to_jsonb(r) order by role_id,permission_code)::text,'')) from core.role_permissions r),(select roles from w4_composition_before),'Existing role grants are unchanged');
insert into w4_composition_assertions select is((select md5(coalesce(jsonb_agg(to_jsonb(r) order by plan_code,entitlement_code)::text,'')) from billing.plan_entitlements r),(select plans from w4_composition_before),'Existing plan entitlements are unchanged');
insert into w4_composition_assertions select is((select md5(coalesce(jsonb_agg(to_jsonb(r) order by tenant_id)::text,'')) from billing.tenant_subscriptions r),(select subscriptions from w4_composition_before),'Existing subscriptions are unchanged');
insert into w4_composition_assertions select is((select md5(coalesce(jsonb_agg(to_jsonb(r) order by version)::text,'')) from supabase_migrations.schema_migrations r),(select ledger from w4_composition_before),'Composition verification does not install migrations');
insert into w4_composition_assertions select is((select md5(coalesce(jsonb_agg(jsonb_build_object('id',p.oid,'definition',pg_get_functiondef(p.oid)) order by p.oid)::text,'')) from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname in('core','finance') and p.prokind='f' and p.proname ~ '(journal|period|residual|allocate)'),(select finance from w4_composition_before),'Installed finance posting and period providers are unchanged');
insert into w4_composition_assertions select ok((select not public from storage.buckets where id='jentra-project-expense-private') and not exists(select 1 from expense_private.worker_readiness),'Private expense bucket is private and its worker is not activated');
do $$declare failed text;begin
 select string_agg(message,chr(10)) into failed from w4_composition_assertions where message like 'not ok%';
 if failed is not null then raise exception using errcode='P0001',message=failed;end if;
end $$;
set constraints all immediate;
select * from finish(true);
select count(*) assertion_count,{len(MIGRATIONS)} candidate_migrations,{len(tables)} candidate_tables from w4_composition_assertions;
rollback;
"""
    query = before + '\n'.join(bodies) + checks
    outputs[0].parent.mkdir(parents=True, exist_ok=True)
    outputs[0].write_text(query, encoding='utf-8', newline='\n')
    report = {'captured_at': datetime.datetime.now(datetime.timezone.utc).isoformat(),
        'kind': 'prepared rollback-only composition; not yet executed or installed',
        'migration_order': list(MIGRATIONS), 'source_hashes': hashes,
        'sql_sha256': sha(outputs[0].read_bytes()), 'tables': sorted(tables),
        'functions': sorted(functions), 'strict_assertions': 14,
        'installed': False, 'wave4_complete': False}
    outputs[1].parent.mkdir(parents=True, exist_ok=True)
    outputs[1].write_text(json.dumps(report, indent=2) + '\n', encoding='utf-8')
    print(json.dumps({'query': str(outputs[0]), 'bytes': len(query.encode()),
        'migrations': len(MIGRATIONS), 'tables': len(tables), 'strict_assertions': 14}))


if __name__ == '__main__':
    main()
