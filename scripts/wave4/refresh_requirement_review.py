"""Refresh all approved Wave 4 IDs without promoting automated checks to acceptance."""
import datetime
import argparse
import hashlib
import json
from pathlib import Path
import re
import subprocess

ROOT = Path(__file__).resolve().parents[2]
SPEC = 'docs/blueprint/40_WAVE4_WORKFORCE_AND_DELIVERY_SPEC.md'
OUT = 'docs/verification/wave4/requirement-review-20261005.json'


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def source(name):
    path = (ROOT / name).resolve()
    if not path.is_relative_to(ROOT) or not path.is_file():
        raise ValueError('Missing or out-of-scope review source: ' + name)
    return {'path': name, 'sha256': digest(path)}


def module(sql, domain, gateway, native, installed, gap):
    return {'sources': [source(name) for name in (
        'supabase/migrations/' + sql,
        'packages/jentra_domain/lib/src/' + domain + '.dart',
        'packages/jentra_platform/lib/src/supabase_' + gateway + '_gateway.dart',
        'apps/jentra_desktop/lib/src/features/' + native + '_controller.dart')],
        'installed': installed, 'remaining': gap}


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--output', default=OUT)
    parser.add_argument('--review-date', default='2026-10-05')
    args = parser.parse_args()
    destination = (ROOT / args.output).resolve()
    if not destination.is_relative_to(ROOT / 'docs/verification/wave4') or destination.exists():
        raise ValueError('Preserve earlier reviews; use a new Wave 4 evidence path')
    text = (ROOT / SPEC).read_text(encoding='utf-8')
    descriptions = dict(re.findall(
        r'^- ((?:FR|NFR|EC)-\d{3}): ([^\n]*(?:\n  [^\n]*)*)', text, re.M))
    descriptions.update({key: value for key, value in re.findall(
        r'^\| (AC-\d{3}) \| [^|]+ \| ([^|]+) \|$', text, re.M)})
    expected = {kind + '-' + str(i) for kind, end in (
        ('FR', 440), ('NFR', 410), ('AC', 420), ('EC', 416))
        for i in range(401, end + 1)}
    if set(descriptions) != expected:
        raise ValueError('The approved specification does not match all 86 expected IDs')
    modules = {
        'employee': module('20260925181927_wave4_employee_foundation.sql',
            'employee', 'employee', 'people/employee', True,
            'Authenticated timeline/consumed history, real overlap, native restart and owner evidence'),
        'calendar': module('20260926082441_wave4_calendar_versions.sql',
            'work_calendar', 'calendar', 'people/calendar', True,
            'Installed resolution/assignment dependencies and authenticated/native/contention evidence'),
        'organization': module('20260926161000_wave4_organization.sql',
            'organization', 'organization', 'people/organization', False,
            'Specific installation approval, installed/native and graph contention evidence'),
        'private_hr': module('20260929224939_wave4_private_hr.sql',
            'private_hr', 'private_hr', 'people/private_hr', True,
            'Trusted worker readiness, real synthetic owner scope and two-user private-byte acceptance'),
        'workforce': module('20260928082234_wave4_attendance_intervals.sql',
            'workforce', 'workforce', 'people/workforce', False,
            'Installed/authenticated work/leave correction and real balance/ownership contention'),
        'payroll': module('20260930070000_wave4_synthetic_payroll.sql',
            'payroll_repository', 'payroll', 'people/payroll', False,
            'Current full integration/build/install, real posting/settlement contention and walkthrough'),
        'corrections': module('20261001110000_wave4_payroll_corrections.sql',
            'payroll_correction', 'payroll_correction', 'people/payroll_correction', False,
            'Full integrated source/install, actual competing billing/source correction and owner evidence'),
        'projects': module('20261001080000_wave4_projects_time.sql',
            'project_values', 'projects', 'projects/projects', False,
            'Full current build/install, authenticated plan/time/cost and source contention'),
        'finance': module('20261001100000_wave4_project_expenses_billing.sql',
            'project_finance', 'project_finance', 'projects/project_finance', False,
            'Final protected client/recovery/build review, installation and real billing contention'),
        'milestones': module('20261004090000_project_milestones.sql',
            'milestones', 'milestone', 'projects/milestones', False,
            'Final current client/recovery review, installation and concurrent approval/billing'),
        'service': module('20261001090000_wave4_service.sql',
            'service', 'service', 'service/service', False,
            'Stock parts provider, final client/build/install and actual dispatch/occurrence races'),
        'assets': module('20260930071000_wave4_fixed_assets.sql',
            'assets_repository', 'assets', 'assets/assets', False,
            'Procurement/stock providers, internal maintenance links, current build/install and depreciation/disposal race'),
    }
    modules['calendar']['sources'].append(source(
        'supabase/migrations/20260926160000_wave4_calendar_resolution.sql'))
    modules['workforce']['sources'].extend(source(name) for name in (
        'supabase/migrations/20260928083449_wave4_leave_ledger.sql',
        'supabase/migrations/20260930070500_wave4_clock_batches.sql'))
    modules['corrections']['sources'].append(source(
        'supabase/migrations/20261002080000_wave4_project_payroll_impacts.sql'))
    modules['asset_equipment'] = module(
        '20261005090000_service_asset_equipment.sql', 'asset_equipment',
        'asset_equipment', 'service/asset_equipment', False,
        'Final operational source/client/recovery reviews, current build/install and real asset/service overlap')
    # Implemented source is traceable even while its final reviews are in progress.
    modules['expense_evidence'] = {
        'sources': [source(name) for name in (
            'supabase/migrations/20261005120000_wave4_project_expense_evidence.sql',
            'packages/jentra_domain/lib/src/expense_evidence.dart',
            'packages/jentra_platform/lib/src/supabase_expense_evidence_gateway.dart',
            'packages/jentra_platform/lib/src/sensitive_expense_evidence_draft_store.dart',
            'apps/jentra_desktop/lib/src/features/projects/expense_evidence_controller.dart',
            'apps/jentra_desktop/lib/src/features/projects/expense_evidence_screen.dart',
            'supabase/functions/expense-private-documents/index.ts',
            'supabase/functions/expense-private-documents/handler.mjs',
            'supabase/functions/expense-private-purge/index.ts',
            'supabase/functions/expense-private-purge/handler.mjs')],
        'installed': False,
        'remaining': 'Complete protected proof/domain/gateway/native/recovery checks and review; specific installation/deployment approval and trusted worker activation'}
    all_modules = list(modules)
    fr_groups = [
        (401, 405, all_modules), (406, 408, ['employee', 'organization', 'corrections']),
        (409, 409, ['private_hr']), (410, 410, ['organization', 'calendar']),
        (411, 411, ['private_hr']), (412, 412, ['calendar', 'organization', 'workforce']),
        (413, 415, ['workforce']), (416, 416, ['workforce', 'payroll', 'corrections']),
        (417, 419, ['payroll']), (420, 421, ['payroll', 'corrections']),
        (422, 422, ['payroll']), (423, 424, ['projects', 'milestones']),
        (425, 425, ['projects', 'workforce', 'service', 'corrections']),
        (426, 426, ['finance', 'expense_evidence']), (427, 427, ['finance', 'milestones', 'service']),
        (428, 428, ['projects', 'finance', 'milestones']),
        (429, 432, ['service']), (433, 434, ['service', 'asset_equipment']),
        (435, 438, ['assets']), (439, 440, all_modules)]
    ac = {
        401: all_modules, 402: ['employee'], 403: ['employee', 'organization'],
        404: ['private_hr', 'payroll', 'expense_evidence'],
        405: ['calendar', 'workforce'], 406: ['workforce', 'corrections'],
        407: ['payroll'], 408: ['payroll', 'corrections'], 409: ['payroll'],
        410: ['projects'], 411: ['projects', 'finance', 'expense_evidence', 'service'],
        412: ['finance', 'milestones'], 413: ['service'], 414: ['service', 'projects'],
        415: ['service', 'assets', 'asset_equipment'], 416: ['assets'], 417: ['assets'], 418: ['assets'],
        419: all_modules, 420: all_modules}
    ec = {
        401: ['employee'], 402: all_modules,
        403: ['employee', 'organization', 'corrections'], 404: ['employee', 'private_hr'],
        405: ['calendar', 'workforce', 'service'], 406: ['calendar', 'workforce'],
        407: ['workforce', 'corrections'], 408: ['payroll'], 409: ['employee', 'payroll'],
        410: ['payroll', 'corrections'], 411: ['finance', 'expense_evidence'],
        412: ['service', 'finance'], 413: ['service'], 414: ['assets'],
        415: all_modules, 416: all_modules}
    entries = []
    for key in sorted(expected):
        kind, number = key.split('-')
        number = int(number)
        selected = (next(group for start, end, group in fr_groups if start <= number <= end)
                    if kind == 'FR' else ac[number] if kind == 'AC' else
                    ec[number] if kind == 'EC' else all_modules)
        entries.append({'id': key, 'requirement': ' '.join(descriptions[key].split()),
            'modules': selected, 'state': 'partial; required acceptance remains open',
            'required_evidence_complete': False,
            'remaining': [modules[name]['remaining'] for name in selected]})
    evidence_names = (
        'resume-checkpoint-20261005.md', 'live-refresh-20261005.json',
        'project-finance-rollback-result-20261005.json',
        'project-billed-payroll-rollback-result-20261005.json',
        'service-rollback-result-20261005.json', 'service-payroll-rollback-result-20261005.json',
        'milestones-rollback-access-result-20261005.json',
        'project-expense-evidence-integration-final-result-20261005.json',
        'project-acknowledgement-evidence-20261005.json',
        'installed-foundation-source-hashes-20261005.json',
        'installed-security-provider-refresh-20261005.json',
        'runtime-evidence-standards-review-20261005.md',
        'install-composition-current-evidence-20261005.json',
        'synthetic-workspace-reconciliation-20261005.json',
        'integrated-contention-runtime-protocol-20261004.md')
    evidence = [source('docs/verification/wave4/' + name) for name in evidence_names]
    gate_name = '.agent-harness/wave4-20261005/reports/root_recovery.json'
    gate = json.loads((ROOT / gate_name).read_text(encoding='utf-8'))
    mismatches = [name for name, value in gate['sources_after'].items()
        if not (ROOT / name).is_file() or digest(ROOT / name) != value]
    report = {'review_date': args.review_date,
        'observed_at': datetime.datetime.now(datetime.timezone.utc).isoformat(),
        'head': subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=ROOT, text=True).strip(),
        'specification': source(SPEC), 'counts': {'FR': 40, 'NFR': 10, 'AC': 20, 'EC': 16},
        'total': len(entries), 'completion_claim': False,
        'evidence_limit': 'All 86 IDs traced; source hashes and dated automated evidence are not installed, contention, authenticated native, load, restart or owner acceptance. No numerical completion percentage is inferred.',
        'modules': modules, 'evidence': evidence,
        'root_gate': {'report': source(gate_name), 'workspace_source_mismatches': mismatches,
            'all_recorded_commands_passed': len(gate['checks']) == 4 and all(c['exit_code'] == 0 for c in gate['checks'])},
        'requirements': entries}
    integrated_name = '.agent-harness/wave4-20261006/reports/wave4_integrated_v1.json'
    if (ROOT / integrated_name).is_file():
        integrated = json.loads((ROOT / integrated_name).read_text(encoding='utf-8'))
        integrated_mismatches = [name for name, value in integrated['sources_after'].items()
            if not (ROOT / name).is_file() or digest(ROOT / name) != value]
        report['integrated_gate'] = {
            'report': source(integrated_name),
            'workspace_source_mismatches': integrated_mismatches,
            'all_recorded_commands_passed': len(integrated['checks']) == 5 and
                all(c['exit_code'] == 0 for c in integrated['checks']),
            'limit': 'Dated source observations; run_current_verification --verify-report must separately verify source/copy/runner/manifest/log bindings.'}
    destination.write_text(json.dumps(report, indent=2) + '\n', encoding='utf-8')
    print(json.dumps({'review': args.output, 'requirements': len(entries),
        'root_gate_current_workspace': not mismatches, 'completion_claim': False}))


if __name__ == '__main__':
    main()
