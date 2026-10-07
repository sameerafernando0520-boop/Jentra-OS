"""Prepare real Wave 4 checks bound to one complete isolated source snapshot."""
import argparse
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
DART = 'C:/src/flutter/bin/cache/dart-sdk/bin/dart.exe'
FLUTTER = 'C:/src/flutter/bin/cache/flutter_tools.snapshot'
DOMAIN = (
    'employee', 'work_calendar', 'calendar_contract', 'calendar_resolution',
    'organization', 'private_hr', 'workforce', 'clock_import',
    'payroll_calculation', 'payroll_repository', 'payroll_correction',
    'payroll_correction_repository', 'project_values', 'project_finance',
    'milestones', 'service_values', 'fixed_asset_schedule', 'assets_repository',
    'expense_evidence', 'asset_equipment',
)
PLATFORM = (
    'employee_draft_store', 'calendar_draft_store', 'calendar_gateway',
    'organization_gateway', 'organization_draft_store', 'private_hr_gateway',
    'private_hr_draft', 'workforce_gateway', 'clock_import_adapter',
    'sensitive_leave_draft', 'payroll_gateway', 'sensitive_payroll_draft',
    'payroll_correction_gateway', 'sensitive_payroll_correction_draft',
    'projects_gateway', 'project_command_acknowledgement',
    'project_finance_gateway', 'milestone_gateway', 'service_gateway',
    'assets_gateway', 'asset_command_acknowledgement',
    'expense_evidence_gateway', 'sensitive_expense_evidence_draft',
    'expense_evidence_files',
    'asset_equipment_gateway',
)
DESKTOP = (
    'employee_workspace', 'calendar_workspace', 'calendar_resolution_dialog',
    'organization_workspace', 'private_hr_workspace', 'workforce_workspace',
    'payroll_workspace', 'payroll_correction_workspace', 'projects_workspace',
    'project_finance_workspace', 'milestones_workspace', 'service_workspace',
    'service_acknowledgement', 'assets_workspace', 'expense_evidence_workspace',
    'asset_equipment_workspace',
)


def tests(package, names):
    paths = ['test/' + name + '_test.dart' for name in names]
    for path in paths:
        if not (ROOT / package / path).is_file():
            raise ValueError('Required vertical test is missing: ' + package + '/' + path)
    return paths


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--snapshot-evidence', required=True)
    parser.add_argument('--manifest', required=True)
    parser.add_argument('--task', required=True)
    args = parser.parse_args()
    evidence_path = (ROOT / args.snapshot_evidence).resolve()
    destination = (ROOT / args.manifest).resolve()
    if not all(p.is_relative_to(ROOT) for p in (evidence_path, destination)):
        raise ValueError('Preparation files must stay inside the workspace')
    if destination.exists():
        raise ValueError('Preserve previous verification manifests; use a fresh name')
    evidence = json.loads(evidence_path.read_text(encoding='utf-8'))
    if not evidence['source_stable']:
        raise ValueError('The complete source snapshot was not stable')
    sources = sorted(evidence['source_hashes'])
    commands = []
    # Analyze the final app integration and every library, including dependencies.
    # Required Wave 4 tests are analyzed separately from unrelated Wave 3 tests.
    analyzer_paths = [package + '/lib' for package in (
        'apps/jentra_desktop', 'packages/jentra_design_system',
        'packages/jentra_domain', 'packages/jentra_platform')]
    for package, names in (
        ('packages/jentra_domain', DOMAIN),
        ('packages/jentra_platform', PLATFORM),
        ('apps/jentra_desktop', DESKTOP),
    ):
        selected = tests(package, names)
        if any(package + '/' + path not in sources for path in selected):
            raise ValueError('A required test is absent from the source snapshot')
        analyzer_paths.extend(package + '/' + path for path in selected)
        commands.append({'cwd': package, 'argv': [DART, FLUTTER, 'test',
            '--no-pub', '--concurrency=1', *selected, '--reporter', 'expanded'],
            'timeout_seconds': 900})
    commands.insert(0, {'cwd': '.', 'argv': [DART, 'analyze', *analyzer_paths],
                       'timeout_seconds': 600})
    commands.append({'cwd': 'apps/jentra_desktop',
        'argv': [DART, FLUTTER, 'build', 'windows', '--release', '--no-pub'],
        'timeout_seconds': 1200})
    manifest = {'scope': 'Current whole-app build and automated Wave 4 checks; '
        'installation, authenticated runtime, contention, load, restart and owner acceptance remain separate',
        'tasks': {args.task: {'snapshot': evidence['snapshot'],
                            'sources': sources, 'commands': commands}}}
    destination.parent.mkdir(parents=True, exist_ok=True)
    destination.write_text(json.dumps(manifest, indent=2) + '\n', encoding='utf-8')
    print(json.dumps({'manifest': str(destination), 'task': args.task,
                      'source_files': len(sources), 'real_commands': len(commands)}))


if __name__ == '__main__':
    main()
