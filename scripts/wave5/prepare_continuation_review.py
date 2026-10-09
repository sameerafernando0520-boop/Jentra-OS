"""Prepare a new exact-file review; never installs, provisions, deploys or sends."""
import datetime
import hashlib
import json
from pathlib import Path
import re

ROOT = Path(__file__).resolve().parents[2]
E = ROOT / 'docs/verification/wave5'
SOURCES = [
    'supabase/migrations/20260925002000_wave3_financial_statements.sql',
    'supabase/migrations/20260926009000_wave3_governed_report_exports.sql',
    'supabase/migrations/20261008090000_wave5_historical_pipeline.sql',
    'supabase/migrations/20261008093000_wave5_persistent_delivery.sql',
    'supabase/migrations/20261008100000_wave5_invocation_storage.sql',
    'supabase/migrations/20261008103000_wave5_dated_cash.sql',
    'supabase/migrations/20261008110000_wave5_governed_export_adapter.sql',
    'supabase/migrations/20261008113000_wave5_statement_classifications.sql',
]
PURPOSES = [
    'W3 prerequisite: immutable trial balance, P&L and balance-sheet publications',
    'W3 prerequisite: governed report export preview/registration using existing core.export_jobs',
    'Immutable CRM history and closed frozen-cohort invoice/credit gross realization',
    'Scoped integration revisions, key rotation, leases, attempts, outcomes, reviewed replay and probes',
    'Hashed scoped credentials, atomic throttle/quota, named dispatch, durable model results and due scheduler',
    'Limited dated bank cash/positive AR basis and immutable scenario revisions',
    'Extend governed export sources with W5 pipeline/scenarios and current-access reopen',
    'Immutable statement classification review and six exact named financial ratios',
]

def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()

def read(name):
    return json.loads((E / name).read_text(encoding='utf-8'))

def main():
    hashes = read('remaining-candidate-20261008.hashes.json')
    result = read('remaining-candidate-final-result-20261008.json')
    live = read('continuation-live-final-20261008.json')
    build = read('continuation-build-final-20261008.json')
    if result['passed'] != 100 or not result['rolledBack'] or not result['strictFinish'] or result['result'].get('isError'):
        raise ValueError('Strict candidate evidence is not verified')
    if sha(E / 'remaining-candidate-20261008.sql') != result['querySha256'] or result['querySha256'] != hashes['querySha256']:
        raise ValueError('Strict query does not match source binding')
    if not build['buildSucceeded'] or not build['current_source_match']:
        raise ValueError('Final build does not match the reviewed client source')
    if live['fingerprintComparison']['unchanged'] != 120 or live['fingerprintComparison']['changedOrMissing']:
        raise ValueError('Installed API/core authority drift requires a new review')
    items = []
    functions = []
    tables = []
    for index, (name, purpose) in enumerate(zip(SOURCES, PURPOSES), 1):
        path = ROOT / name
        if sha(path) != hashes['candidateSources'][name]:
            raise ValueError('SQL source changed after strict checks: ' + name)
        text = path.read_text(encoding='utf-8')
        apis = re.findall(r'create (?:or replace )?function\s+(api\.\w+)\s*\((.*?)\)\s*returns\s+(\w+)', text, re.S | re.I)
        api_rows = [{'name': api, 'arguments': ' '.join(args.split()), 'returns': returns} for api, args, returns in apis]
        for row in api_rows:
            row['source'] = name
        functions.extend(api_rows)
        new_tables = re.findall(r'create table\s+(\w+\.\w+)', text, re.I)
        tables.extend(new_tables)
        items.append({'order': index, 'path': name, 'bytesSha256': sha(path),
            'normalizedSqlSha256': hashlib.sha256(text.encode('utf-8')).hexdigest(),
            'purpose': purpose, 'ownerWave': 3 if index <= 2 else 5,
            'apiFunctions': api_rows, 'newTables': new_tables})
    if len(functions) != 26 or len(tables) != 16:
        raise ValueError('Reconcile candidate API/table composition')
    counts = {}
    for name, expected in [('domain', 71), ('platform', 41), ('native', 90)]:
        log = (E / f'{name}-continuation-verified-20261008.log').read_text(encoding='utf-8')
        found = re.search(r'\+(\d+): All tests passed!', log)
        if not found or int(found.group(1)) != expected:
            raise ValueError('Missing successful ' + name + ' evidence')
        counts[name] = expected
    worker_log = (E / 'worker-continuation-verified-20261008.log').read_text(encoding='utf-8')
    if not re.search(r'pass 31\b', worker_log) or not re.search(r'fail 0\b', worker_log):
        raise ValueError('Missing controlled worker evidence')
    if 'No issues found!' not in (E / 'continuation-source-analyzer-verified-20261008.log').read_text(encoding='utf-8'):
        raise ValueError('Final application/package analysis is not clean')
    evidence_names = [
        'remaining-candidate-20261008.hashes.json', 'remaining-candidate-final-result-20261008.json',
        'continuation-live-final-20261008.json', 'designated-runtime-labels-20261008.json',
        'continuation-build-final-20261008.json', 'continuation-build-final-snapshot-20261008.json',
        'continuation-windows-build-final-20261008.log', 'continuation-source-analyzer-verified-20261008.log',
        'domain-continuation-verified-20261008.log', 'platform-continuation-verified-20261008.log',
        'native-continuation-verified-20261008.log', 'worker-continuation-verified-20261008.log',
        'shared-golden-investigation-20261008.json', 'shared-golden-investigation-20261008.md',
    ]
    report = {
        'preparedAt': datetime.datetime.now(datetime.timezone.utc).isoformat(),
        'targetProjectId': 'xpdoufauvrbdmxgngetv', 'installationAuthorized': False,
        'additionalMigrationsInstalled': False, 'originalInstalledSixExcluded': True,
        'installedBaseline': {'migrations': 43, 'apiFunctions': 107, 'forcedRlsWave5Tables': 15,
            'checkedAt': live['checkedAt'], 'unchangedApiCoreFingerprints': 120},
        'candidatesInOrder': items, 'newWave5ApiFunctions': 21, 'prerequisiteWave3ApiFunctions': 5,
        'newWave5Tables': 15, 'prerequisiteWave3Tables': 1,
        'projectedAfterApprovedInstallation': {'migrations': 51, 'apiFunctions': 133, 'wave5Tables': 30},
        'permissionDefinitions': ['integrations.manage', 'finance.classifications.approve', 'finance.reports.export if absent'],
        'roleAssignmentsAdded': False, 'entitlementsActivated': False,
        'newDirectClientTableAccess': False, 'privateHelperPublicAccess': False,
        'developmentChecks': {'candidateSql': 100, **counts, 'controlledWorker': 31, 'analyzerClean': True,
            'buildSourceMatches': True, 'sharedGoldenFailures': 13},
        'candidateQuerySha256': result['querySha256'],
        'fullCashProvidersImplemented': False, 'nonemptyRealizedSqlEvidence': False,
        'authenticatedNativeAcceptance': False, 'realMfaAcceptance': False,
        'actualWorkerDelivery': False, 'actualModelRequest': False,
        'independentSessionContention': False, 'targetScaleLoad': False, 'ownerAcceptedCriteria': 0,
        'bootstrapAuthorized': False, 'secretProvisioningAuthorized': False, 'workerDeploymentAuthorized': False,
        'externalDeliveryAuthorized': False, 'realBillingAuthorized': False,
        'excluded': ['original six installed migrations', 'other Wave 3/4 migrations', 'acceptance stores',
            'synthetic bootstrap, roles, operator grants and entitlements', 'server/model/vault/receiver secrets',
            'worker deployment, model calls and external delivery', 'real billing and production', 'Git staging/commit/push'],
        'evidenceHashes': {name: sha(E / name) for name in evidence_names},
        'workerSourceHashes': {p.relative_to(ROOT).as_posix(): sha(p) for p in sorted((ROOT / 'workers/wave5').glob('*.mjs'))},
        'renderedFrames': {p.relative_to(ROOT).as_posix(): sha(p) for p in sorted((E / 'continuation-frames-20261008').glob('*.png'))},
        'renderedFixturesAreAuthenticatedAcceptance': False,
    }
    (E / 'continuation-review-20261008.json').write_text(json.dumps(report, indent=2) + '\n', encoding='utf-8')
    rows = ['| Order | Exact source | Purpose | Bytes SHA-256 |', '|---|---|---|---|']
    for item in items:
        rows.append(f"| {item['order']} | [{Path(item['path']).name}](../../../{item['path']}) | {item['purpose']} | `{item['bytesSha256']}` |")
    api_rows = ['| API | Arguments | Returns |', '|---|---|---|']
    for item in functions:
        api_rows.append(f"| `{item['name']}` | `{item['arguments']}` | `{item['returns']}` |")
    doc = '''# Wave 5 continuation review — October 8, 2026

The implementation now includes historical pipeline analytics, authoritative statement ratios, limited dated cash scenarios with encrypted recovery, governed export creation/download/reopen, persistent integration/model adapters and five additional native analytics workspaces. Wave 5 remains incomplete. This review proposes **eight new migration files** for `xpdoufauvrbdmxgngetv`: two separately owned Wave 3 prerequisites and six new Wave 5 candidates. **No additional installation is authorized or performed.** The original six installed Wave 5 migrations are excluded.

## Exact proposed installation scope

Install order and byte hashes are fixed below. The machine-readable [review](continuation-review-20261008.json) includes normalized SQL hashes, exact API arguments, table names, test/build/source hashes and excluded scopes. Approval of a directory, a CLI bulk push or the original six files must not be inferred from this review.

''' + '\n'.join(rows) + '''

The freshly checked baseline is 43 migrations, 107 API functions and 15 forced-RLS Wave 5 tables. All 120 installed API/core fingerprints are unchanged. A successful installation of this exact new list would be expected to yield 51 ledger entries, 133 API functions, 30 Wave 5 tables and one additional W3 `finance.financial_reports` table. Those are projected counts, not installed evidence. The connector can assign new ledger versions; record the filename/version mapping after any separately approved installation and refresh schema signatures. Both W3 sources are preserved byte-for-byte and still require inclusion in the owner's explicit installation scope.

## Behavior and persistent effects

History uses complete immutable CRM revisions 1..n, original amount/probability/owner/stage/currency, scoped source access and exact UTC cutoffs. Revision gaps reject the cohort. Conversion is won/decided opportunities; aging is current open-stage duration; velocity is won opportunity value per mean won lifecycle day, grouped by currency. Realized accuracy maps the frozen cohort to posted invoice gross minus order-linked posted credit-return gross in the half-open horizon. Capture must precede horizon end and realization requires a closed horizon. This definition can include an in-progress horizon; it does not claim a forecast captured before horizon start or recognized ledger revenue. Line-only returns affecting that cohort reject incomplete mapping. The SQL fixture currently exercises an empty mapped cohort; typed gateway fixtures exercise nonempty exact signed invoice/credit totals. Nonempty installed SQL mapping and owner approval of these definitions remain gates.

Ratios consume matching immutable P&L and balance-sheet publications from W3. Formula revision 1 returns net profit margin, liabilities/assets and assets/equity; an immutable MFA-reviewed account map additionally enables current ratio, quick ratio and gross profit margin. The server verifies full classification coverage, both publication hashes, scope, period, currency and source population; the gateway independently recalculates exact six-decimal half-away results. Zero and negative denominators carry explicit reasons. Classifications are not published live by installing their table.

Cash version 1 is explicitly **limited bank transaction cash and positive dated AR**. It reconciles opening cash to posted transaction-currency journals and AR to allocations/write-offs/discounts, without counting the receipt as another forecast inflow. Overdue-before-horizon and unallocated credits are excluded. AP, payroll and project expenses are not certified. Supplier bills and corrected allocation/reversal providers are absent live. W4 `people_payroll.obligations` and `projects.reimbursements` lack an authoritative payment due-date field. Complete corrected AP and dated payroll/reimbursement residual/deduplication adapters still need their own reviewed source contract and implementation. Posting/service dates cannot be substituted for payment due dates. Future allocation-reversal installation must trigger a cash contract review; this AR-only provider does not adapt that additional relation.

Scenario rows retain their source hash, exact original canonical basis, immutable assumptions and reason-coded overrides. They have no journal/document mutation path. Encrypted local recovery is actor/scope bound and keeps a pending original command separate from the editable draft. Native restart/revocation fixtures pass; actual signed-in process restart is not exercised. Governed exports reuse W3 preview/registration and existing **`core.export_jobs`**, add pipeline/scenario sources and recheck current source/export permissions on reopen/download. The original W3 export helper is retained under a new private name and the wrapper delegates its existing six source families. SQL tests register synthetic metadata; platform codecs recreate actual exact CSV/XLSX bytes and verify the registered hash. Real authenticated file creation/download/reopen remains open.

The delivery candidate adds seven forced-RLS tables for explicitly reviewed hosts, scoped subscriptions and changes, durable heads/leases, attempts, outcomes and reviews. Registration/rotation/revocation and receiver reconciliation require current MFA, exact versions and stable audit commands. Committed outbox IDs map to named allowlisted redacted events. Unknown send outcomes never retry automatically; reviewed receiver evidence is required. Known failures have a bounded eight-attempt policy. Native listing uses 50-row keyset pages for subscriptions and delivery outcomes. No host, receiver, vault key or subscription is provisioned by the migration.

The invocation candidate adds six forced-RLS tables for hashed scoped credentials, quota periods, requests, throttle slots and durable model invocations/outcomes. Credential effective dates are bounded and revocation is checked before dispatch/reservation. A trusted server reads current membership/roles and uses an explicitly delegated aal1 actor for the named forecast command; it never fabricates MFA. Atomic billing-row/advisory locks enforce current hard caps and a 60/minute throttle; duplicate identities reuse one reservation/slot. Outcomes are immutable, persist before settlement and can reopen without repeating a send. Unknown results require reconciliation. A bounded 50-row due-revision scheduler reuses installed synthetic activation; queue/quota health probes preserve unknown missing data. Neither scheduler nor health collection is deployed or activated.

All fifteen new W5 tables force RLS and deny direct public/anonymous/authenticated table access. Twenty-one new W5 API functions include fifteen authenticated and six server-only functions; private helpers and public/anonymous API execute are denied. The two W3 prerequisites add five authenticated API functions and one immutable forced-RLS statement table. The candidates define `integrations.manage`, `finance.classifications.approve` and `finance.reports.export` if absent; they assign no roles or entitlements. Human approval rules on the original installed proposal commands remain intact.

## Worker/model code and configuration review

Concrete Supabase RPC ports, Request/Response handlers, DNS-pinned TLS/HMAC delivery, bounded streaming JSON, activation and delivery scheduling are implemented under `workers/wave5`. Factories do not open a listener or deploy a worker. Explicit reviewed launch configuration must supply the server key, allowed hostname/receiver, vault reference/key material, credential and any model provider. No credentials or sessions are discovered from another chat or acceptance store.

The reviewed model adapter accepts an eight-field numeric publication projection, rejects private/free-text inputs, fixes a five-field suggestion to the captured source hash/horizon and does not invoke a business command. Human submission and distinct MFA approval remain required. The optional OpenAI Responses adapter requires an explicitly approved model/policy, counts the complete input including its strict output schema, disables tools/background execution and requests `store=false`. Token settlement uses trusted provider usage within the original reservation; unavailable/unknown results stay unconfirmed. No model or receiver request has occurred. Provider contract details were checked against [official structured output documentation](https://developers.openai.com/api/docs/guides/structured-outputs?api-mode=responses) and [token-counting documentation](https://developers.openai.com/api/docs/guides/token-counting). Configuring or calling that provider requires a separate exact review.

## Development evidence and separate acceptance gates

| Gate | Evidence | Limit |
|---|---|---|
| New SQL composition | [100 strict checks](remaining-candidate-final-result-20261008.json), `finish(true)`, final rollback; query SHA-256 `''' + result['querySha256'] + '''` | Eight-file candidates only; original six were not replayed; JWT/MFA assertions use injected claims |
| Installed refresh | [Current catalog](continuation-live-final-20261008.json): 43/107/15, 120 unchanged fingerprints; no fixture users/tenant, candidate permissions/tables, allowlist/operator/grants/probes | Previous 126 installed checks belong to the original installation report and were not rerun here |
| Domain/platform | [71 domain](domain-continuation-verified-20261008.log), [41 platform](platform-continuation-verified-20261008.log) | Focused development tests; temporary encrypted-store close/reopen is not native acceptance |
| Desktop/controller/render | [90 passing tests](native-continuation-verified-20261008.log); final [scoped analysis](continuation-source-analyzer-verified-20261008.log) clean | Injected identities/providers; actual MFA, process restart and revocation remain open |
| Workers | [31 controlled tests](worker-continuation-verified-20261008.log) | Persistent-port tests use controlled transports; no actual worker delivery/model usage |
| Windows compilation | [Final attribution](continuation-build-final-20261008.json), [build log](continuation-windows-build-final-20261008.log); 1,047 selected sources and 34 release files | Fresh isolate excludes local stores; no signed-in launch, installer or owner acceptance |
| Shared dashboard/setup | [13 investigated failures](shared-golden-investigation-20261008.md) | Capability experiment still red; original fixture restored; approved goldens untouched |
| Real runtime/load/owner | [Runtime protocol](integrated-runtime-protocol-20261006.md), [109-ID matrix](requirement-matrix-20261008.md) | Not executed; zero owner-accepted criteria |

Five new workspaces render at 1024/1440 widths, light/dark, both densities and 200% text: forty variants and twenty current top/lower PNGs. Seven representative fresh frames were inspected, including integration controls after the final input-scope fix. Real font loading is included. These captures show forms; only cash/integration captures contain injected results. Existing process/pipeline/control renders cover their original thirty-six variants. Full keyboard reachability, real authenticated populated views and prescribed 1920px coverage for the new workspaces remain acceptance work. Earlier critical-branch coverage and limited credential scans retain their original source/data scope; they do not establish new whole-wave coverage or privacy of actual exports/model/runtime data.

An earlier automatic approval review failed because its usage allowance was exhausted. No command executed at that failure. After the user selected retry when available and account usage reported available, final native verification, scoped analysis and the fresh Windows build proceeded through approval review. The failed test fixture and stale earlier build evidence are retained alongside the successful final evidence.

## Runtime identities and excluded actions

[Read-only label evidence](designated-runtime-labels-20261008.json) confirms repository-designated Jentra Acceptance Lab, tenant `a1d9ee78-de36-4408-9948-0f6ab7749b95`, JAT entity and HQ branch. Its only active member is `test@test.com`, user `8b1ace26-0574-411e-81a8-6b8481c231a9`, with one verified MFA factor. Former repository label `test@lh.com` is absent. A verified factor does not prove an aal2 runtime session. Proposer, distinct MFA approver, executor, billing administrator, separate operator and foreign-tenant member labels remain unconfirmed; another branch and an approved foreign synthetic scope are also needed. No credentials, sessions or acceptance databases were extracted.

Any installation approval must name **this exact eight-file list and project**. It covers no synthetic bootstrap, plan/role/operator grants, entitlement activation, statement/classification publication, hostname/vault/model secrets, worker deployment, external delivery, real billing, production or Git staging/commit/push. Those future actions need their own concrete reviews. Full cash providers, nonempty realized SQL mapping, authenticated MFA/native restart/revocation/export, actual worker/model delivery, independent-session contention, 500-tenant/2,000-session load and owner signoff remain required before Wave 5 can be called complete.
'''
    (E / 'continuation-review-20261008.md').write_text(doc + '\n## Exact API surface\n\n' + '\n'.join(api_rows) + '\n', encoding='utf-8')
    print(json.dumps({'review': 'docs/verification/wave5/continuation-review-20261008.md',
        'newFiles': len(items), 'newApiFunctions': len(functions), 'newTables': len(tables),
        'installationAuthorized': False, 'wholeWaveComplete': False}))

if __name__ == '__main__':
    main()
