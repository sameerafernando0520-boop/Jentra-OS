"""Generate the Wave 3-5 installed pgTAP files that `supabase test db` runs.

`supabase test db` hands every file in supabase/tests to pg_prove on its own,
in autocommit. The Wave 3-5 suites were never written for that: they are
fragments (pg_temp helpers, set_config/set local role state, no plan) that a
candidate builder concatenates into one begin...rollback query, collects into a
temporary results table, and returns as JSON. Those fragments now live in
supabase/wave_tests/, and this script turns each builder's composition into one
self-contained file here:

  * the builder runs unchanged, then every supabase/migrations file it embedded
    verbatim is removed, because `supabase start` has already installed them;
  * `insert into <results table> select <pgTAP call>` becomes `select <pgTAP
    call>`, so pg_prove sees the TAP stream (the same rewrite
    build_operational_smoke_candidate.ps1 already uses);
  * the file stays one transaction that ends in rollback, with its single
    no_plan() and finish() from the composition.

No assertion is added, removed or changed. Candidates that are not migrations
(none today) would stay embedded and be named in the header.

Wave 5 compositions live in scripts/wave5/*; the same fixture order is rebuilt
here without the migrations.

Usage (Windows PowerShell or pwsh must be on PATH for the builders):
  py -3 supabase/tests/build_wave_installed_pgtap.py           # write files
  py -3 supabase/tests/build_wave_installed_pgtap.py --check   # fail if stale
"""
import argparse
import hashlib
import re
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
TESTS = ROOT / 'supabase' / 'tests'
FRAGMENTS = ROOT / 'supabase' / 'wave_tests'
MIGRATIONS = ROOT / 'supabase' / 'migrations'

NEGATIVE_STOCK = 'supabase/migrations/20261003090000_wave3_negative_stock_policy.sql'

# (output stem, builder, arguments). Every Wave 3-5 fragment is reached by at
# least one of these; later builders in a chain include the earlier fragments.
BUILDS = [
    ('wave3_representative_read_plans', 'build_representative_read_plan_candidate', []),
    ('wave3_remaining_inventory', 'build_remaining_wave3_candidate', ['-Suite', 'inventory']),
    ('wave3_remaining_receivables', 'build_remaining_wave3_candidate', ['-Suite', 'receivables']),
    ('wave3_finance_receivables', 'build_financial_dimensions_candidate', ['-Suite', 'receivables']),
    ('wave3_inventory_transfers', 'build_inventory_candidate', []),
    ('wave3_reservation_release', 'build_reservation_candidate', []),
    ('wave3_negative_stock_policy', 'build_negative_stock_policy_candidate_20261003',
     ['-Suite', 'procurement', '-CandidatePath', NEGATIVE_STOCK,
      '-AssertionsPath', '@wave3_negative_stock_policy_20261003_test.sql']),
    # Not built: wave3_negative_stock_policy_replay_diagnostic_20261004_test.sql and
    # wave3_negative_stock_tracking_red_20261005_test.sql are dated snapshots of
    # the policy suite taken while it was being fixed (red/diagnostic runs). Every
    # assertion in them is in wave3_negative_stock_policy_20261003_test.sql except
    # the replay diagnostic's own probe of a superseded hash hypothesis; they fail
    # only where the policy suite was later corrected. They stay in wave_tests.
    ('wave3_negative_stock_multi_actor', 'build_negative_stock_policy_candidate_20261003',
     ['-Suite', 'procurement', '-CandidatePath', NEGATIVE_STOCK,
      '-AssertionsPath', '@wave3_negative_stock_multi_actor_red_20261004_test.sql']),
    ('wave4_employee', 'build_employee_candidate', ['-Installed']),
    ('wave4_calendar', 'build_calendar_candidate', ['-Installed']),
    ('wave4_calendar_resolution', 'build_calendar_resolution_candidate', ['-Installed']),
    ('wave4_organization', 'build_organization_candidate', ['-Installed']),
    ('wave4_attendance', 'build_attendance_candidate', ['-Installed', '-InstalledPrerequisites', '-IncludeClockBatches']),
    ('wave4_leave', 'build_leave_candidate', ['-Installed', '-InstalledPrerequisites']),
    ('wave4_payroll', 'build_payroll_candidate', ['-Installed', '-InstalledPrerequisites']),
    ('wave4_payroll_corrections', 'build_payroll_corrections_candidate', []),
    ('wave4_private_hr', 'build_private_hr_candidate', ['-Installed']),
    ('wave4_projects', 'build_projects_candidate', ['-Installed', '-InstalledPrerequisites']),
    ('wave4_project_finance', 'build_project_finance_candidate', ['-Installed', '-InstalledPrerequisites']),
    ('wave4_expense_evidence', 'build_expense_evidence_candidate', []),
    ('wave4_milestones', 'build_milestones_candidate', []),
    ('wave4_project_expense_evidence_integration', 'build_project_expense_evidence_integration_candidate', []),
    ('wave4_project_payroll_impacts', 'build_project_payroll_impacts_candidate', []),
    ('wave4_project_billed_payroll_impacts', 'build_project_billed_payroll_impacts_candidate', []),
    ('wave4_service', 'build_service_candidate', ['-Installed']),
    ('wave4_service_payroll_impacts', 'build_service_payroll_impacts_candidate', []),
    ('wave4_assets', 'build_assets_candidate', ['-Installed']),
    ('wave4_asset_equipment', 'build_asset_equipment_candidate', []),
]

FINISH = 'select * from finish(true);'


def read(path):
    return path.read_text(encoding='utf-8-sig').replace('\r\n', '\n')


def wave5_candidates():
    """scripts/wave5/prepare_candidates.py without its six migrations."""
    names = ['wave5_process_metrics_test.sql', 'wave5_pipeline_forecasts_test.sql',
             'wave5_trusted_metering_test.sql', 'wave5_operator_isolation_test.sql',
             'wave5_human_proposals_test.sql', 'wave5_synthetic_subscriptions_test.sql']
    parts = ['begin;'] + [read(FRAGMENTS / n).split(FINISH)[0] for n in names]
    return '\n'.join(parts) + '\n' + FINISH + '\nrollback;\n', names


def wave5_remaining():
    """scripts/wave5/prepare_remaining_candidate.py without its eight migrations."""
    names = ['wave5_process_metrics_test.sql', 'wave5_remaining_adapters_test.sql',
             'wave5_realized_mapping_test.sql']
    parts = ['begin;'] + [read(FRAGMENTS / n).split(FINISH)[0] for n in names]
    # The adapters suite's cash section asserts the v2 AR/AP-only basis
    # (dated_transaction_cash_ar_and_ap.v2), which 20261008120000_wave5_cash_
    # payment_dates replaced with the five-provider v3 basis; installed, its save
    # stops on CASH_COMPLETE_PROVIDERS_REQUIRED. prepare_runtime_candidate.mjs
    # likewise leaves this legacy v2 cash fixture out, and the v3 basis, save and
    # export are asserted in wave5_cash_payment_dates_test.sql (wave5_runtime).
    # Its fixture rows stay: realized_mapping reads them.
    parts[2] = parts[2].split('create temporary table w5_cash as')[0]
    names[1] += ' (fixture rows only; v2 cash assertions superseded by v3)'
    return '\n'.join(parts) + '\n' + FINISH + '\nrollback;\n', names


def wave5_runtime():
    """prepare_runtime_candidate.mjs, then prepare_complete_app_candidate.mjs's two
    suites on top, without the migrations either of them replays."""
    def fixture(name):
        sql = read(FRAGMENTS / name).replace(FINISH, '').replace('select no_plan();', '')
        if name == 'wave5_remaining_adapters_test.sql':
            start = sql.index('-- Rollback-only shape shim')
            sql = sql[:start] + sql[sql.index('insert into finance.accounts', start):]
        return sql
    seed = read(FRAGMENTS / 'wave5_process_metrics_test.sql')
    parts = ['begin;', seed.split('select is(api.analytics_process_authorize')[0].replace('select no_plan();', ''),
             "insert into intelligence_control.integration_hosts values('runtime-fixture.invalid');",
             "insert into core.outbox_events(tenant_id,topic,aggregate_type,aggregate_id,payload) values(pg_temp.fid('t'),'runtime.scope.fixture','fixture',pg_temp.fid('queue.fixture'),'{}');",
             "insert into intelligence_control.operators(actor_id,active,health_read,grant_manage) values(pg_temp.fid('owner'),true,true,true);"]
    names = ['wave4_synthetic_fixture.sql', 'wave5_cash_payment_dates_test.sql', 'wave5_runtime_scope_test.sql']
    parts += [fixture(n) for n in names]
    tail = ['wave5_supabase_runtime_test.sql', 'wave5_supabase_setup_test.sql']
    # Their timestamps must stay equal to the installed defaults written in the
    # same statement (issued_at default statement_timestamp()), so no pin here.
    parts += [read(FRAGMENTS / n).replace('statement_timestamp()', KEEP_STATEMENT_TIME) for n in tail]
    query = '\n'.join(parts).replace('set local search_path=extensions,public,pg_catalog;',
                                     'set local search_path=extensions,public,pg_catalog;\nselect no_plan();', 1)
    return query + '\n' + FINISH + '\nrollback;\n', ['wave5_process_metrics_test.sql (seed)'] + names + tail


WAVE5 = [
    ('wave5_candidates', wave5_candidates, 'scripts/wave5/prepare_candidates.py'),
    ('wave5_remaining', wave5_remaining, 'scripts/wave5/prepare_remaining_candidate.py'),
    ('wave5_runtime', wave5_runtime, 'scripts/wave5/prepare_runtime_candidate.mjs + prepare_complete_app_candidate.mjs'),
]


def powershell():
    for exe in ('pwsh', 'powershell'):
        if shutil.which(exe):
            return exe
    raise SystemExit('PowerShell (pwsh or powershell) is required to run the candidate builders.')


def run_builder(builder, args, workdir):
    resolved = []
    for a in args:
        if a.startswith('@'):
            # The builder refuses any source that mentions finish(, including in
            # a comment (tracking_red's header does); reword comments only.
            body = read(FRAGMENTS / a[1:])
            body = re.sub(r'(?m)^(\s*--.*?)finish\s*\(', r'\1finish-', body)
            copy = Path(workdir) / a[1:]
            copy.write_text(body, encoding='utf-8')
            resolved.append(str(copy))
        elif a.startswith('supabase/'):
            resolved.append(str(ROOT / a))
        else:
            resolved.append(a)
    out = Path(workdir) / (builder + '.sql')
    quoted = ' '.join("'" + a.replace("'", "''") + "'" if not a.startswith('-') else a for a in resolved)
    command = ("$ErrorActionPreference='Stop';$PSDefaultParameterValues['Get-Content:Encoding']='UTF8';"
               f"$q=& '{TESTS / (builder + '.ps1')}' {quoted};"
               f"[IO.File]::WriteAllText('{out}',($q -join \"`n\"),[Text.UTF8Encoding]::new($false))")
    r = subprocess.run([powershell(), '-NoProfile', '-ExecutionPolicy', 'Bypass', '-Command', command],
                       cwd=ROOT, capture_output=True, text=True)
    if r.returncode or not out.exists():
        raise SystemExit(f'{builder} {" ".join(args)} failed:\n{r.stdout}\n{r.stderr}')
    return out.read_text(encoding='utf-8').replace('\r\n', '\n')


def quoted_mask(s):
    """True for every character inside a string literal, dollar quote or comment."""
    mask = bytearray(len(s))
    dq = re.compile(r'\$([A-Za-z_][A-Za-z0-9_]*)?\$')
    i, n = 0, len(s)
    while i < n:
        c = s[i]
        j = None
        if c == "'":
            j = i + 1
            while j < n:
                if s[j] == "'":
                    if j + 1 < n and s[j + 1] == "'":
                        j += 2
                        continue
                    break
                j += 1
            j += 1
        elif s.startswith('--', i):
            j = s.find('\n', i)
            j = n if j < 0 else j
        elif s.startswith('/*', i):
            j = s.find('*/', i + 2)
            j = n if j < 0 else j + 2
        elif c == '$' and not (i and (s[i - 1].isalnum() or s[i - 1] == '_')):
            m = dq.match(s, i)
            if m:
                j = s.find(m.group(0), m.end())
                j = n if j < 0 else j + len(m.group(0))
        if j is None:
            i += 1
            continue
        mask[i:min(j, n)] = b'\x01' * (min(j, n) - i)
        i = j
    return mask


def strip_migrations(query):
    removed = []
    bodies = sorted(((p.name, read(p)) for p in MIGRATIONS.glob('*.sql')), key=lambda x: -len(x[1]))
    for name, body in bodies:
        if body.strip() and body in query:
            removed.append(name)
            query = query.replace(body, f'-- installed by supabase/migrations/{name}\n')
    # Any migration that is still recognisable was embedded in an edited form;
    # replaying it would test a different schema from the installed one.
    for name, body in bodies:
        lines = [l for l in body.split('\n') if len(l) > 60 and not l.lstrip().startswith('--')]
        probe = [l for l in lines[:40] if re.match(r'\s*(create|alter|grant|revoke|comment)\b', l, re.I)]
        if probe and sum(l in query for l in probe) * 2 > len(probe):
            raise SystemExit(f'migration {name} is embedded in an edited form; cannot run it as installed')
    return query, sorted(removed)


def tap_stream(query):
    sinks = sorted(set(re.findall(r'create (?:temp|temporary) table (?:if not exists )?(\w+) *\(message text', query, re.I)))
    if not sinks:
        return query, sinks
    mask = quoted_mask(query)
    pattern = re.compile(r'insert into (' + '|'.join(sinks) + r')\s+select\b', re.I)
    out, last = [], 0
    for m in pattern.finditer(query):
        if mask[m.start()]:
            continue
        out.append(query[last:m.start()])
        out.append('select')
        last = m.end()
    out.append(query[last:])
    return ''.join(out), sinks


# 20260924185321_wave3_period_governance makes a fiscal-period state change
# legal only after a period event by the same actor in the same transaction.
# Candidate builders installed that migration after the older fixtures had
# already set their periods up, so those fixtures update the state directly;
# installed, the same statement raises PERIOD_TRANSITION_COMMAND_REQUIRED.
# The fixture's own UPDATE stays verbatim and runs with only the lifecycle
# trigger switched off, which is the state it ran in under the candidate
# order. It writes no period events of its own (assertions count them), and
# the whole file still rolls back.
PERIOD_TRIGGER = 'alter table finance.fiscal_periods {} trigger fiscal_periods_enforce_lifecycle;'
PERIOD_UPDATE = re.compile(
    r"(?im)^update finance\.fiscal_periods\s+set\s+state\s*=\s*'(\w+)'(?:\s*,\s*updated_by\s*=[^;]*?)?\s+where\s+([^;]+);")


def govern_period_updates(query):
    mask = quoted_mask(query)
    out, last, count = [], 0, 0
    for m in PERIOD_UPDATE.finditer(query):
        if mask[m.start()]:
            continue
        before = query[:m.start()].rstrip()
        previous = before[before.rstrip(';').rfind(';') + 1:].strip().lower()
        if previous.startswith('insert into finance.period_events'):
            continue  # already the governed path
        out.append(query[last:m.start()])
        out.append('\n'.join([PERIOD_TRIGGER.format('disable'), m.group(0), PERIOD_TRIGGER.format('enable')]))
        last = m.end()
        count += 1
    out.append(query[last:])
    return ''.join(out), count


KEEP_STATEMENT_TIME = 'statement_timestamp/*per statement*/()'


def pin_statement_time(query):
    """The compositions were run as one execute_sql message, where every
    statement shares one statement_timestamp() and it equals now(). psql sends
    each statement on its own, so a basis hashed in one statement no longer
    matches the same basis recomputed in the next (SOURCE_BASIS_CHANGED), and a
    retried command no longer matches its first attempt (IDEMPOTENCY_MISMATCH).
    Every statement here is fixture code (installed migrations are already
    removed), so its statement_timestamp() reads now() again; the installed
    schema's own functions are untouched."""
    query, count = re.subn(r'\bstatement_timestamp\(\)', 'now()', query)
    return query.replace(KEEP_STATEMENT_TIME, 'statement_timestamp()'), count


def finalise(stem, query, source, notes):
    query = query.strip() + '\n'
    if not re.match(r'(?is)\s*begin;', query) or not query.rstrip().endswith('rollback;'):
        raise SystemExit(f'{stem}: composition must be one begin...rollback transaction')
    if re.search(r'(?im)^\s*commit\s*;', query):
        raise SystemExit(f'{stem}: composition must never commit')
    if len(re.findall(r'(?i)select (?:\* from )?(?:no_)?plan\(', query)) != 1:
        raise SystemExit(f'{stem}: expected exactly one plan')
    header = [f'-- Generated by supabase/tests/build_wave_installed_pgtap.py from {source}; do not edit.',
              '-- Runs against the schema `supabase start` installs from supabase/migrations.'] + \
             [f'-- {n}' for n in notes]
    return '\n'.join(header) + '\n' + query


def build_all(workdir):
    files = {}
    for stem, builder, args in BUILDS:
        query = run_builder(builder, args, workdir)
        query, removed = strip_migrations(query)
        query, sinks = tap_stream(query)
        query, periods = govern_period_updates(query)
        query, pinned = pin_statement_time(query)
        source = f'supabase/tests/{builder}.ps1 {" ".join(a.lstrip("@") for a in args)}'.strip()
        notes = [f'Installed migrations removed from the composition: {len(removed)}.']
        if sinks:
            notes.append('TAP rows go to output instead of: ' + ', '.join(sinks) + '.')
        if periods:
            notes.append(f'Fixture period updates run with only the lifecycle trigger off, as in candidate order: {periods}.')
        if pinned:
            notes.append(f'Fixture statement_timestamp() read as now(), as in one execute_sql message: {pinned}.')
        files[stem] = finalise(stem, query, source, notes)
    for stem, compose, source in WAVE5:
        query, names = compose()
        query, removed = strip_migrations(query)
        query, periods = govern_period_updates(query)
        query, pinned = pin_statement_time(query)
        notes = ['Fixtures, in order: ' + ', '.join(names) + '.']
        if periods:
            notes.append(f'Fixture period updates run with only the lifecycle trigger off, as in candidate order: {periods}.')
        if pinned:
            notes.append(f'Fixture statement_timestamp() read as now(), as in one execute_sql message: {pinned}.')
        files[stem] = finalise(stem, query, source, notes)
    return files


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--check', action='store_true', help='fail when a generated file is stale')
    args = parser.parse_args()
    with tempfile.TemporaryDirectory() as workdir:
        files = build_all(workdir)
    stale = []
    for stem, text in files.items():
        path = TESTS / f'{stem}_installed_test.sql'
        old = path.read_text(encoding='utf-8').replace('\r\n', '\n') if path.exists() else None
        if old != text:
            stale.append(path.name)
            if not args.check:
                path.write_bytes(text.encode('utf-8'))
        print(f'{path.name}: {len(text.encode()):>9} bytes  sha256 {hashlib.sha256(text.encode()).hexdigest()[:16]}')
    if args.check and stale:
        print('stale: ' + ', '.join(stale), file=sys.stderr)
        return 1
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
