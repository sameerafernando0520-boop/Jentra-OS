"""Refresh installation gates without claiming unperformed runtime acceptance."""
import datetime
import json
from pathlib import Path
import re

ROOT = Path(__file__).resolve().parents[2]
E = ROOT / 'docs/verification/wave5'


def main():
    result = json.loads((E / 'installation-result-20261008.json').read_text(encoding='utf-8'))
    if not result['installationComplete'] or result['installedStrictSqlPassed'] != 126:
        raise ValueError('Installed evidence is incomplete')
    path = E / 'requirement-matrix-20261008.json'
    matrix = json.loads(path.read_text(encoding='utf-8'))
    updated = {
        'shared': ('Installed scoped provider behavior verified in strict rollback; finance/export/worker surface remains partial',
                   'Verify real authenticated access/revocation and foreign scopes. Extend equivalent checks to the missing finance, exports and persistent workers.'),
        'process': ('Domain, installed read/detail RPCs, adapter, encrypted filters and widgets verified',
                    'Authenticated native source access, process restart and owner acceptance remain open. Stage dwell/work/rework remain explicitly uncertified under the source contract.'),
        'pipeline': ('Installed current forecast freeze/reopen verified; historical metrics and realized accuracy incomplete',
                     'Reviewed immutable opportunity amount/probability/stage/owner history and realized-result mapping remain missing. Authenticate current forecasts; certify historical metrics only from reviewed providers.'),
        'ai': ('Installed manual immutable proposal/decision/execution path verified; model invocation adapter absent',
               'Test distinct real MFA actors, revocation, cohort change and overlapping execution. Configure/review server model/redaction and trusted token metering before invocation; manual proposals retain human origin and zero model units.'),
        'billing': ('Installed trial revisions, seat guard and trusted reservations/settlement/corrections verified in strict rollback; native recovery tested',
                    'Name and review the synthetic tenant/private plan and actor scope, separately review/bootstrap only that scope, configure trusted activation/metering worker and prove independent-session quota/seat races and trial boundaries. No shared starter plan is enabled.'),
        'operator': ('Installed operator isolation, expiring MFA grants, audit and unknown probes verified in strict rollback/adapter/widgets',
                     'Name/review the separate synthetic operator/grant scope, configure real probes and verify authenticated owner denial, MFA and grant expiry. No operator is seeded.'),
        'provider': ('Installed provider signatures and grants verified; missing/mismatched adapters still fail closed',
                     'Verify real cached authenticated endpoint behavior and supply reviewed financial/model/worker adapters. An unavailable readiness card does not implement its dependent feature.'),
        'ownership': ('Owner target/list approval recorded; six migrations installed and 98 existing provider fingerprints preserved',
                      'Preserve concurrent W3/W4 source and unapproved candidates. Synthetic bootstrap/provider deployment are excluded. Use the recorded connector ledger mapping to prevent reinstallation.'),
    }
    for row in matrix['rows']:
        if row['bundle'] in updated:
            row['developmentStatus'], row['remaining'] = updated[row['bundle']]
            installed_evidence = 'docs/verification/wave5/installation-result-20261008.json'
            if installed_evidence not in row['evidence']:
                row['evidence'].append(installed_evidence)
        if row['ownerAccepted']:
            raise ValueError('Whole criterion owner acceptance has not been recorded')
    matrix['updatedAt'] = datetime.datetime.now(datetime.timezone.utc).isoformat()
    matrix['installationComplete'] = True
    matrix['installationResult'] = 'docs/verification/wave5/installation-result-20261008.json'
    matrix['wholeWaveComplete'] = False
    path.write_text(json.dumps(matrix, indent=2) + '\n', encoding='utf-8')
    markdown_path = E / 'requirement-matrix-20261008.md'
    original = markdown_path.read_text(encoding='utf-8')
    titles = dict(re.findall(r'<a id="evidence-([^"]+)"></a>\s*## ([^\n]+)', original))
    rows_by_id = {row['id']: row for row in matrix['rows']}
    text = ['# Wave 5 requirement matrix - October 8, 2026', '',
            'All 109 approved identifiers are mapped below. The [six owner-approved migrations are installed](installation-result-20261008.md): '
            '43 migrations, 107 API functions and 126 passing strict installed checks. These statuses do not imply authenticated native, worker, '
            'contention/load or owner acceptance. No entire acceptance criterion is marked owner-accepted.', '',
            '| ID | Evidence bundle | Current status |', '|---|---|---|']
    for row in matrix['rows']:
        text.append(f"| {row['id']} | [{titles[row['bundle']]}](#evidence-{row['bundle']}) | {row['developmentStatus']} |")
    for group, title in titles.items():
        row = next(r for r in matrix['rows'] if r['bundle'] == group)
        text.extend(['', f'<a id="evidence-{group}"></a>', f'## {title}', '', row['developmentStatus'] + '.', '',
                     'Evidence: ' + ', '.join(f'[{Path(p).name}](../../../{p})' for p in row['evidence']) + '.', '',
                     'Remaining: ' + row['remaining']])
    markdown_path.write_text('\n'.join(text) + '\n', encoding='utf-8')
    print(json.dumps({'identifiers': len(rows_by_id), 'installationComplete': True, 'wholeWaveComplete': False}))


if __name__ == '__main__':
    main()
