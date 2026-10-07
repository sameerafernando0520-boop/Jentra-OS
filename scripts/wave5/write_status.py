"""Write the reviewable Wave 5 status from attributable, bounded evidence."""
import datetime
import json
from pathlib import Path
import re

ROOT = Path(__file__).resolve().parents[2]
E = ROOT / 'docs/verification/wave5'
DATE = '20261008'


def read_json(name):
    return json.loads((E / name).read_text(encoding='utf-8'))


def write(path, text):
    (ROOT / path).write_text(text.rstrip() + '\n', encoding='utf-8')


def main():
    review = read_json('installation-review-' + DATE + '.json')
    attribution = read_json('windows-build-attribution-' + DATE + '.json')
    baseline = read_json('live-baseline-' + DATE + '.json')
    scan = read_json('secret-projection-scan-' + DATE + '.json')
    if not attribution['current_source_match'] or scan['findingCount']:
        raise ValueError('Source or scan evidence requires review')
    bundles = {
        'shared': ('Scope, permission and complete bounded evidence',
                   'Verified development behavior for implemented providers; full provider/export surface is partial',
                   ['supabase/migrations/20261006140000_wave5_process_metrics.sql',
                    'supabase/migrations/20261006143000_wave5_pipeline_forecasts.sql',
                    'packages/jentra_platform/test/analytics/process_metric_gateway_test.dart',
                    'packages/jentra_platform/test/analytics/pipeline_forecast_gateway_test.dart'],
                   'Install reviewed providers; verify real authenticated access/revocation and foreign scopes. Extend the same checks to finance, exports and persistent workers.'),
        'process': ('W5-01 process metrics',
                    'Verified domain, strict rollback RPC, adapter, encrypted filter and widget behavior',
                    ['packages/jentra_domain/test/analytics/process_metrics_test.dart',
                     'supabase/tests/wave5_process_metrics_test.sql',
                     'packages/jentra_platform/test/analytics/process_metric_hasher_test.dart',
                     'packages/jentra_platform/test/analytics/process_filter_store_test.dart',
                     'apps/jentra_desktop/test/process_metric_workspace_test.dart'],
                    'Installed/authenticated native source access, process restart and owner acceptance remain open. Stage dwell/work/rework stay explicitly uncertified under the source contract.'),
        'pipeline': ('W5-02 current pipeline forecasts',
                     'Current observation freeze/reopen verified; historical metrics and realized accuracy incomplete',
                     ['packages/jentra_domain/test/analytics/forecast_metrics_test.dart',
                      'supabase/tests/wave5_pipeline_forecasts_test.sql',
                      'packages/jentra_platform/test/analytics/pipeline_forecast_gateway_test.dart',
                      'apps/jentra_desktop/test/wave5_workspaces_test.dart'],
                     'Reviewed immutable opportunity amount/probability/stage/owner history and realized-result mapping are missing. Install/authenticate current forecasts; certify historical metrics only from those providers.'),
        'finance': ('W5-03 exact ratio basis',
                    'Exact ratio arithmetic and publication compatibility verified; named authoritative adapters unimplemented',
                    ['packages/jentra_domain/lib/src/analytics/forecast_metrics.dart',
                     'packages/jentra_domain/test/analytics/forecast_metrics_test.dart',
                     'docs/blueprint/wave5/W5_02_03_FORECAST_AND_RATIO_CONTRACT.md'],
                    'Upstream statement publication must expose governed classifications and source versions for each named formula. Define/review that authority and implement its adapter/native integration; the generic quotient cannot certify a financial ratio.'),
        'cash': ('W5-03 cash scenarios and governed export',
                 'Bounded exact dated-control/residual-obligation calculation verified; durable scenario/export integration unimplemented',
                 ['packages/jentra_domain/lib/src/analytics/cash_scenarios.dart',
                  'packages/jentra_domain/test/analytics/cash_scenarios_test.dart',
                  'docs/blueprint/wave5/W5_02_03_FORECAST_AND_RATIO_CONTRACT.md'],
                 'Review and implement dated bank/cash and complete AR/AP/payroll/project residual adapters, immutable scenario revisions/overrides, encrypted draft recovery, native workspace, and governed export create/download/reopen with live permission checks.'),
        'ai': ('W5-04 human proposal controls',
               'Manual immutable proposal/decision/execution development path verified; model invocation adapter absent',
               ['supabase/tests/wave5_human_proposals_test.sql',
                'packages/jentra_domain/test/analytics/governed_controls_test.dart',
                'packages/jentra_platform/test/analytics/wave5_control_gateway_test.dart',
                'apps/jentra_desktop/test/wave5_workspaces_test.dart'],
               'Install and test distinct real MFA actors, revocation, cohort change and overlapping execution. Configure/review the server model/redaction adapter and trusted token metering before model invocation; manual proposals retain human origin and zero model units.'),
        'integration': ('W5-05 webhook/API policies and worker orchestration',
                        'Pinned transport, credential policy and injected orchestration tests verified; persistent server ports absent',
                        ['workers/wave5/integration_policy.mjs', 'workers/wave5/worker_runtime.mjs',
                         'workers/wave5/integration_policy.test.mjs', 'workers/wave5/worker_runtime.test.mjs'],
                        'Implement durable scoped subscription registration/key rotation, credential/revocation lookup, committed-outbox lease/attempt/dead-letter/reviewed replay storage, atomic throttle/quota adapter, authenticated named dispatcher and scheduler. Server vault and an explicitly authorized receiver are required for real sends. Unknown outcomes require reconciliation.'),
        'billing': ('W5-06 synthetic subscriptions and trusted usage',
                    'Effective trial revisions, seat guard, exact reservations/settlement/corrections and native recovery verified in development',
                    ['supabase/tests/wave5_trusted_metering_test.sql',
                     'supabase/tests/wave5_synthetic_subscriptions_test.sql',
                     'packages/jentra_platform/test/analytics/wave5_command_store_test.dart',
                     'apps/jentra_desktop/test/wave5_workspaces_test.dart'],
                    'Record owner-approved synthetic tenant/private plan and actor scope, install candidates, configure trusted activation/metering worker, and prove independent-session quota/seat races and trial boundaries. No shared starter plan is enabled.'),
        'operator': ('W5-07 separate operator authority and health',
                     'Forced-RLS isolation, expiring MFA grants, audit and unknown probes verified in rollback/adapter/widgets',
                     ['supabase/tests/wave5_operator_isolation_test.sql',
                      'packages/jentra_platform/test/analytics/wave5_control_gateway_test.dart',
                      'apps/jentra_desktop/test/wave5_workspaces_test.dart'],
                     'Owner must name the separate synthetic operator/grant scope; install, configure real probes and verify authenticated owner denial, MFA and grant expiry. No operator is seeded.'),
        'native': ('Native workspaces and recovery',
                   'Process/pipeline/control and original uncertain envelope recovery verified; scenario/integration workspaces incomplete',
                   ['apps/jentra_desktop/lib/src/features/analytics/',
                    'apps/jentra_desktop/test/wave5_workspaces_test.dart',
                    'packages/jentra_platform/test/analytics/wave5_command_store_test.dart',
                    'docs/verification/wave5/render-review-' + DATE + '.json'],
                   'Implement dependent finance/cash/export/integration workspaces after their reviewed adapters. Perform real native process restart, authenticated access changes, keyboard review and owner signoff in all prescribed variants.'),
        'provider': ('Provider readiness',
                     'Existing adapters fail closed on missing/mismatched contracts; unsupported operations are explained',
                     ['packages/jentra_domain/lib/src/analytics/governed_controls.dart',
                      'packages/jentra_domain/test/analytics/governed_controls_test.dart',
                      'workers/wave5/worker_runtime.test.mjs',
                      'docs/verification/wave5/live-baseline-' + DATE + '.json'],
                     'Install/recheck candidate contract revisions and supply reviewed financial/model/worker adapters. An unavailable readiness card is not implementation of the dependent feature.'),
        'ownership': ('Shared checkout and installation boundary',
                      'Owned changes and rollback evidence recorded; persistent installation approval pending',
                      ['docs/verification/wave5/installation-review-' + DATE + '.json',
                       'docs/verification/wave5/windows-build-attribution-' + DATE + '.json',
                       'docs/verification/wave5/subscription-native-development-20261006.hashes.json'],
                      'Preserve concurrent W3/W4 edits. FR-534 requires separately recorded owner target/list authorization before installation; refresh hashes/provider fingerprints immediately before any approved installation.'),
        'quality': ('Evidence and quality gates',
                    'Zero-issue analyzer, critical-domain branch coverage and limited secret/projection scan verified; full acceptance incomplete',
                    ['docs/verification/wave5/analyzer-final-20261006.log',
                     'docs/verification/wave5/coverage-final-20261006.json',
                     'docs/verification/wave5/secret-projection-scan-' + DATE + '.json',
                     'docs/verification/wave5/shared-golden-case-comparison-20261006.json'],
                    'Thirteen shared dashboard/setup golden cases still fail. Full criterion/edge fixtures are missing for incomplete features. Scan real exports/model prompts/authenticated runtime logs, obtain native/worker/load evidence and owner signoff; none is inferred from development tests.'),
        'load': ('Real contention and target-scale performance',
                 'Sequential 100-retry fixtures and bounded input tests exist; contention/load acceptance absent',
                 ['supabase/tests/wave5_pipeline_forecasts_test.sql',
                  'supabase/tests/wave5_trusted_metering_test.sql',
                  'supabase/tests/wave5_synthetic_subscriptions_test.sql',
                  'docs/verification/wave5/integrated-runtime-protocol-20261006.md'],
                 'Use independent overlapping sessions/barriers, measure authoritative before/after effects and no quota/seat overshoot. Publish hardware/workload and p95 for 500 tenants/2,000 concurrent sessions. Oversized work is currently rejected; resumable larger jobs require implementation if supported.'),
    }
    assigned = {}

    def assign(group, kind, numbers):
        for number in numbers:
            key = f'{kind}-{number}'
            if key in assigned:
                raise ValueError('Duplicate assignment: ' + key)
            assigned[key] = group

    assign('shared', 'FR', [501, 502, 503, 504, 505, 508])
    assign('process', 'FR', [506, 507] + list(range(551, 560)))
    assign('pipeline', 'FR', [509, 510, 511])
    assign('finance', 'FR', [512])
    assign('cash', 'FR', [513, 514, 515])
    assign('ai', 'FR', list(range(516, 521)))
    assign('integration', 'FR', [521, 522, 523, 535])
    assign('billing', 'FR', [524, 525, 526])
    assign('operator', 'FR', [527, 528, 529])
    assign('native', 'FR', [530, 531])
    assign('provider', 'FR', [532])
    assign('ownership', 'FR', [533, 534, 560])
    assign('quality', 'FR', [536])
    assign('shared', 'NFR', [501, 502, 503, 510])
    assign('load', 'NFR', [504, 505, 506])
    assign('quality', 'NFR', [507, 509])
    assign('native', 'NFR', [508])
    assign('process', 'NFR', list(range(551, 555)))
    assign('shared', 'AC', [501, 503])
    assign('process', 'AC', [502] + list(range(551, 557)) + [558])
    assign('pipeline', 'AC', [504])
    assign('finance', 'AC', [505])
    assign('cash', 'AC', [506])
    assign('ai', 'AC', [507, 508, 509])
    assign('integration', 'AC', [510, 511])
    assign('billing', 'AC', [512, 513])
    assign('operator', 'AC', [514])
    assign('native', 'AC', [515])
    assign('ownership', 'AC', [516, 557])
    assign('quality', 'AC', [517])
    assign('shared', 'EC', [501, 514])
    assign('process', 'EC', [502, 503] + list(range(551, 559)))
    assign('pipeline', 'EC', [504])
    assign('cash', 'EC', [505, 506])
    assign('ai', 'EC', [507, 508])
    assign('integration', 'EC', [509, 510])
    assign('billing', 'EC', [511])
    assign('operator', 'EC', [512])
    assign('native', 'EC', [513])
    assign('ownership', 'EC', [515])
    assign('quality', 'EC', [516])
    rows = []
    for path in ['docs/blueprint/wave5/WAVE5_INTELLIGENCE_AND_CONTROL_SPEC.md',
                 'docs/blueprint/wave5/W5_01_PROCESS_METRICS_CONTRACT.md']:
        contents = (ROOT / path).read_text(encoding='utf-8')
        for match in re.finditer(r'(?m)^(?:- |### )((?:FR|NFR|AC|EC)-[0-9]{3}):[^\n]+', contents):
            identity = match.group(1)
            group = assigned[identity]
            heading, status, paths, remaining = bundles[group]
            for source in paths:
                if not (ROOT / source).exists():
                    raise ValueError('Missing evidence source: ' + source)
            rows.append({'id': identity, 'specification': path,
                         'specificationLine': contents[:match.start()].count('\n') + 1,
                         'statement': match.group().removeprefix('- ').removeprefix('### '),
                         'bundle': group, 'developmentStatus': status, 'evidence': paths,
                         'remaining': remaining, 'ownerAccepted': False})
    if len(rows) != 109 or set(assigned) != {row['id'] for row in rows}:
        raise ValueError('Requirement identifier coverage differs from the approved 109 IDs')
    (E / ('requirement-matrix-' + DATE + '.json')).write_text(json.dumps({
        'updatedAt': datetime.datetime.now(datetime.timezone.utc).isoformat(),
        'requirementCount': 109, 'ownerAcceptedCriteria': 0, 'wholeWaveComplete': False,
        'rows': rows}, indent=2) + '\n', encoding='utf-8')
    matrix = ['# Wave 5 requirement matrix - October 8, 2026', '',
              'All 109 approved identifiers are mapped below. These are development statuses, not owner acceptance. '
              'No acceptance criterion is marked accepted. See the [checkpoint](checkpoint-20261008.md) for test/build/install boundaries.', '',
              '| ID | Evidence bundle | Development status |', '|---|---|---|']
    for row in rows:
        matrix.append(f"| {row['id']} | [{bundles[row['bundle']][0]}](#evidence-{row['bundle']}) | {row['developmentStatus']} |")
    for key, (title, status, paths, remaining) in bundles.items():
        matrix.extend(['', f'<a id="evidence-{key}"></a>', f'## {title}', '', status + '.', '',
                       'Evidence: ' + ', '.join(f'[{Path(p).name}](../../../{p})' for p in paths) + '.', '',
                       'Remaining: ' + remaining])
    write('docs/verification/wave5/requirement-matrix-' + DATE + '.md', '\n'.join(matrix))
    install = ['# Wave 5 candidate installation review - October 8, 2026', '',
               '**Status: unapplied; owner authorization pending.**', '',
               'Proposed target: synthetic development project `xpdoufauvrbdmxgngetv`. '
               'The read-only [baseline](live-baseline-20261008.json) remains at 37 migrations through `20260929224939` and 85 API functions. '
               'The `analytics` and `intelligence_control` schemas are absent. '
               'The six files below introduce 22 API functions plus private helpers; the predicted API count after only this list is 107, subject to a fresh installed check.', '',
               'The approved [parent specification](../../blueprint/wave5/WAVE5_INTELLIGENCE_AND_CONTROL_SPEC.md#native-delivery-and-concurrency), FR-534, requires:', '',
               '> installation/deployment MUST have a separately recorded owner-authorized target and migration/function list.', '',
               'The October 6 request authorizes additive development. It has not separately recorded approval to persist this exact target/list. '
               'This review makes that installation scope concrete; it does not approve it.', '',
               '## Exact migration order and byte hashes', '',
               '| Order | Migration | SHA-256 of file bytes |', '|---|---|---|']
    for i, candidate in enumerate(review['candidatesInOrder'], 1):
        install.append(f"| {i} | [{Path(candidate['path']).name}](../../../{candidate['path']}) | `{candidate['bytesSha256']}` |")
    install.extend(['', 'The [machine-readable review](installation-review-20261008.json) also records normalized UTF-8 SQL hashes, '
                    'function signatures and table names. Windows CRLF file-byte hashes differ from the normalized SQL hashes '
                    'used by the strict composition. Both are retained; no newline normalization is treated as a new migration version.', '',
                    '## Persistent effects in this list', '',
                    '- Add nullable `billing.tenant_subscriptions.trial_started_at` and the process cohort index.',
                    '- Add private forced-RLS forecast, usage, operator, proposal and synthetic subscription evidence tables, indexes and RPCs.',
                    '- Add four AI permission definitions and `billing.synthetic.manage`; assign them to no roles.',
                    '- Insert disabled `quota.ai.tokens`, `quota.webhook.deliveries` and `module.ai` definitions for existing plans if missing; enable none.',
                    '- Add the membership seat trigger. Enforcement is restricted to rows explicitly allowlisted in the initially empty synthetic-target table.', '',
                    '## Excluded and required follow-up scopes', '',
                    'No W3/W4 candidate, SQL fixture, tenant/account/operator/grant bootstrap, role assignment, subscription activation, '
                    'secret/key/model provisioning, worker deployment, receiver request or real billing is included. '
                    'Installing these six files alone leaves entitlement-gated and synthetic/operator paths unavailable.', '',
                    'A later bootstrap review must name the synthetic tenant/entity/two branches and proposer, distinct MFA approver, '
                    'executor, billing administrator, separate operator and foreign-tenant account labels. '
                    'Use a private synthetic plan or an equivalently reviewed tenant-specific arrangement. '
                    'Enabling analytics/AI/quota entitlements on the shared `starter` plan would affect other tenants and is outside this list.', '',
                    '## Verification and installation procedure', '',
                    'The [strict rollback result](subscription-native-development-result-20261006.json) has 126 passing assertions. '
                    'The [source hashes](subscription-native-development-20261006.hashes.json) and all six fixture inputs still match on October 8. '
                    'The [current command dependency fingerprints](command-dependencies-20261008.json) retain the existing command/scope/optimistic-version authority. '
                    'Sequential duplicate loops do not establish contention safety.', '',
                    'After owner authorization, refresh the live ledger, all file hashes, provider column signatures and command fingerprints. '
                    'Stop for any unreviewed drift or candidate collision. Apply only this ordered list through the migration connector, '
                    'verify each ledger entry and installed function signature/grant/forced-RLS state, and refresh the API schema. '
                    'Perform authenticated allowed/denied checks after the separately reviewed synthetic bootstrap. '
                    'Record installation separately from runtime/worker/load/owner acceptance. Any function-list or byte change requires an updated review.'])
    install.extend(['', '## API function list', '',
                    'These signatures are introduced by the six reviewed files; the JSON review also lists their private helper functions.', ''])
    for candidate in review['candidatesInOrder']:
        for function in candidate['functions']:
            if function['name'].startswith('api.'):
                install.append(f"- `{function['name']}({function['arguments']})`")
    write('docs/verification/wave5/installation-review-' + DATE + '.md', '\n'.join(install))
    status = '''# Wave 5 development status

Updated October 8, 2026. **Wave 5 remains incomplete.** Additive process/pipeline/control development is reviewable and verified; upstream financial authority, persistent integration adapters and integrated acceptance are still open. The October 6 source/tests/build were checked against the current checkout on October 8. The worker unknown-outcome fix and its tests are from October 8.

| Slice | Current development behavior | Remaining work |
|---|---|---|
| W5-01 Process | Exact event-duration P50/P90, immutable source digest/cutoffs, scoped read/detail RPC candidate, verified gateway, encrypted filters and native workspace | Install/authenticate; native restart/keyboard/runtime/load/owner gates. Stage dwell/work/rework remain uncertified |
| W5-02 Pipeline | Freeze/reopen current scoped opportunity revisions and exact per-currency weighted totals; immutable command evidence and original uncertain-command recovery | Reviewed historical stage/value/owner and realized-result providers; installed/authenticated acceptance |
| W5-03 Ratios/cash | Exact ratio publication compatibility and dated-control/residual cash primitives; absent families remain unavailable | Named authoritative statement/classification and remaining-obligation adapters; durable immutable scenarios/overrides/encrypted drafts; native integration and governed export/download/reopen |
| W5-04 AI controls | Human-origin immutable proposals, hash-bound distinct MFA decision, live source/cohort/approver recheck, stable single command, encrypted pending recovery | Server model/redaction provider and trusted token worker; real authenticated MFA and concurrent execution evidence |
| W5-05 Integrations | Scoped allowlist/credential policy, DNS-pinned HTTPS, exact HMAC bytes, bounded known retries, unknown reconciliation state and injected worker orchestration | Persistent subscription/key rotation/credential/outbox lease/attempt/dead-letter/replay/throttle/dispatcher/scheduler adapters; approved receiver/vault and real worker evidence |
| W5-06 Billing | Existing billing authority, explicit synthetic trial/seat revision and worker activation candidates; exact immutable trusted metering/corrections; shared billing lock/seat guard; native trial recovery | Approved private synthetic tenant/plan/actors; installation and trusted worker; independent-session quota/seat races |
| W5-07 Operator | Separate operator authority, reasoned expiring MFA grant, immutable access audit, redacted health and unknown missing/stale probes | Approved synthetic operator/grants, real probes, installed/authenticated acceptance |
| W5-08 Acceptance | Evidence matrix, strict rollback, current-source attribution, rendered review and Windows build | Full feature completion, installation, authenticated native restart/keyboard, actual worker/receiver, 500-tenant/2,000-session load and owner signoff |

The live read-only refresh remains **37 migrations**, latest `20260929224939`, **85 API functions**. Neither Wave 5 schema is installed; checked financial statement, attendance and payroll source relations are absent. All six Wave 5 candidates are unapplied. Existing concurrent W3/W4 candidates and local acceptance stores are preserved.

Verification is bounded to the owned changes:

- 126 strict SQL assertions passed; every candidate effect rolled back. Sequential 100-retry cases are not contention evidence.
- 61 focused domain and 29 platform tests passed; 46 Wave 5 desktop/controller/render cases passed. The broader desktop run finished 57 passes and 13 shared dashboard/setup golden failures. Their case names match the earlier pre-W5 run; pixel equivalence is not claimed and approved goldens were not rewritten.
- 15 injected worker tests passed on October 8. Timeout outcomes are `unknown`, have no automatic retry delay, and keep their reservation pending reconciliation. No real request was sent.
- Full workspace analysis reported zero issues. Critical changed domain branches reached 193/199 (96.98%); this is not whole-wave coverage or fixture coverage for unimplemented features.
- The Windows release build succeeded on October 6. All 1,025 selected client sources and the isolate still match on October 8. The executable and 34 release files are hashed. No installer, real signed-in launch or native acceptance is claimed.
- 36 synthetic rendered variants covered three workspaces, both themes/densities, three viewports and 200% text. Twelve fresh captures are retained and four were visually inspected. Real native keyboard/owner review remains open.
- Structured credential and projection-key scans found zero findings in those release files, six selected logs and four SQL projection wires. Actual export/model/runtime data are absent; this limited scan does not close NFR-507.

See the [current checkpoint](../verification/wave5/checkpoint-20261008.md), [109-ID requirement matrix](../verification/wave5/requirement-matrix-20261008.md), [exact installation review](../verification/wave5/installation-review-20261008.md) and [integrated runtime protocol](../verification/wave5/integrated-runtime-protocol-20261006.md). FR-534 requires separately recorded owner target/list approval before persistent installation. The review excludes all synthetic bootstrap, entitlement activation, real billing and external provisioning/delivery.
'''
    write('docs/development/wave5-status.md', status)
    checkpoint = f'''# Wave 5 development checkpoint - October 8, 2026

Wave 5 remains incomplete. The October 6 continuation implemented process, current pipeline forecast, human proposal, trusted metering, synthetic subscription and separate operator development paths. October 8 recovered the completed build result after the interruption, proved current source attribution, repaired unknown webhook outcomes, refreshed live fingerprints and completed this review packet. Earlier W3/W4 work and acceptance stores are preserved.

## Evidence and limits

| Gate | Result | Evidence |
|---|---|---|
| Current client source | All {attribution['sourceFileCount']} selected files match the tested/build isolate; no additions or removals | [attribution](windows-build-attribution-20261008.json) |
| Domain | 61 focused tests pass | [log](domain-final-checked-20261006.log) |
| Platform | 29 focused tests pass, including actual temporary encrypted-store close/reopen | [log](platform-final-checked-20261006.log) |
| SQL | 126 strict assertions; `finish(true)` and rollback; inputs still match | [result](subscription-native-development-result-20261006.json), [hashes](subscription-native-development-20261006.hashes.json) |
| Desktop | 46 owned W5 cases pass; broader run 57 pass / 13 shared golden failures | [log](native-final-20261006.log), [comparison](shared-golden-case-comparison-20261006.json) |
| Worker source | 15 injected tests pass; unknown outcomes keep reservation and require reconciliation | [log](workers-final-20261008.log), [source attribution](worker-source-attribution-20261008.json) |
| Analysis/coverage | Zero analyzer issues; critical domain 193/199 branches, 96.98% | [analysis](analyzer-final-20261006.log), [coverage](coverage-final-20261006.json) |
| Windows | October 6 release build succeeded; executable plus {attribution['releaseFileCount']} release-file hashes and current source match checked October 8 | [build log](windows-build-final-20261006.log), [attribution](windows-build-attribution-20261008.json) |
| Rendered fixtures | 36 variants pass; 12 captures, four inspected; synthetic data | [review](render-review-20261008.json) |
| Limited credential/projection scan | Zero findings in captured release/log/wire scope; exhaustive PII and real export/prompt/runtime inspection absent | [scan](secret-projection-scan-20261008.json) |
| Installed state | {baseline['migrationCount']} migrations, {baseline['apiFunctionCount']} API functions; W5 schemas absent | [live baseline](live-baseline-20261008.json), [command fingerprints](command-dependencies-20261008.json) |
| Real native/MFA/restart, workers, contention/load, owner | Not performed or accepted | [runtime protocol](integrated-runtime-protocol-20261006.md) |

Executable: `{attribution['executable']}`. SHA-256: `{attribution['executableSha256']}`. Build/source verification does not imply an installable signed release or authenticated native acceptance.

The thirteen shared golden failures have the same names as the pre-W5 October 6 run. That comparison does not prove identical pixels or exclude every integration effect. No approved golden was automatically updated. Focused successful tests do not make the broader desktop regression green.

## Exact remaining implementation

1. Historical CRM and realized-result contracts: immutable amount/probability/owner/stage history and realized cohort mapping. Mutable current rows cannot establish conversion, dwell, velocity or accuracy. Changing/backfilling W3/4 producers requires their compatible owner contract.
2. Financial publication authority: named formulas need governed classifications and source revisions on complete immutable statement publications. Existing generic exact arithmetic is insufficient. Define/review the upstream provider shape, then implement the adapter and native ratios.
3. Cash/scenario/export delivery: reviewed dated bank/cash controls and complete remaining AR/AP/payroll/project obligations; deduplicate settlements/reversals/allocations, freeze immutable assumptions and overrides, recover encrypted drafts, expose native scenarios and reuse governed export creation/download/reopen with current source access.
4. Server model provider: reviewed allowlisted redaction and invocation adapter, trusted reservation/settlement and unknown-outcome reconciliation. Human-created proposals currently expose `origin=human`, unavailable model and zero model units.
5. Persistent integration service: scoped subscription/key rotation and credential storage, committed-outbox leases, append-only attempts/dead letters/reviewed replay, atomic throttle/quota, authenticated named dispatch and scheduler. Vault/key provisioning and actual receiver sends need the separately named synthetic authorization.
6. Finish dependent native finance/cash/export/integration workspaces and real keyboard navigation after those reviewed adapters exist.

These items are implementation gaps, not gates closed by an unavailable card or passing policy test. Missing upstream classification/residual/history contracts are identified explicitly; no source certification is invented or shared provider overwritten.

## Next integrated gates

The [installation review](installation-review-20261008.md) lists the exact six candidates, byte hashes, 22 API signatures, persistent effects and excluded scopes for project `xpdoufauvrbdmxgngetv`. All remain unapplied. Parent FR-534 requires a separately recorded owner-authorized target/list before installation. No bootstrap is included; a private synthetic plan/tenant/entity/branches and named real account labels are still needed for the runtime protocol.

After those inputs, install/recheck only the approved list and reviewed synthetic setup, then use real logins/MFA, native process restart, access revocation, independent overlapping sessions for quota/seat/execution, real probes/workers/receiver, target-scale p95 and owner signoff. Each gate must retain its own evidence. No commit, push, PR, migration installation, secret issuance, real billing, native acceptance-store write or external send occurred in this continuation.

The [requirement matrix](requirement-matrix-20261008.md) maps all 109 approved IDs to evidence and remaining work. The [development status](../../development/wave5-status.md) is the current entry point; earlier September 30/October 6 artifacts remain preserved.
'''
    write('docs/verification/wave5/checkpoint-' + DATE + '.md', checkpoint)
    print(json.dumps({'requirements': len(rows), 'candidates': len(review['candidatesInOrder']),
                      'wholeWaveComplete': False, 'installationApproved': False}))


if __name__ == '__main__':
    main()
