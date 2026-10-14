import fs from 'node:fs/promises';
import { hashBytes } from './runtime_contract.mjs';

const root = new URL('../../', import.meta.url);
const predecessor = 'tools/wave5/refresh_private_owner_scope_20261014_r5_a8.mjs';
const successor = 'tools/wave5/refresh_private_owner_scope_20261014_r5_a9.mjs';
const adapterPath = 'scripts/wave5/run_private_management_installer_20261013_r5.ps1';
const oldHelper = await fs.readFile(new URL(predecessor, root));
const oldAdapter = await fs.readFile(new URL(adapterPath, root));
if (hashBytes(oldHelper) !== '42bfdaa042aedac533e2b72552b45995b4e480aea593b4ee3b62f71d2c18ee11') throw Error('EXACT_A8_REFRESH_SOURCE_REQUIRED');
if (hashBytes(oldAdapter) !== '99f9af0c2204ce7d745d125c6db724aaef3e2bbac1bf3c0f9f135e9df7489091') throw Error('EXACT_A8_ADAPTER_REQUIRED');
let helper = oldHelper.toString('utf8');
if ((helper.match(/-a8\.json/g) ?? []).length !== 4) throw Error('EXACT_FOUR_PUBLICATION_FILENAMES_REQUIRED');
helper = helper.replaceAll('-a8.json', '-a9.json');
const helperSha256 = hashBytes(helper);
let adapter = oldAdapter.toString('utf8');
if ((adapter.match(/,'RefreshOwnerScopeA8'/g) ?? []).length !== 13) throw Error('EXACT_REFRESH_MODE_LISTS_REQUIRED');
adapter = adapter.replaceAll(",'RefreshOwnerScopeA8'", ",'RefreshOwnerScopeA8','RefreshOwnerScopeA9'");
function once(before, after) {
  if (adapter.split(before).length !== 2) throw Error('EXACT_A9_ADAPTER_ANCHOR_REQUIRED');
  adapter = adapter.replace(before, after);
}
once("$taskSecret = $null\n$taskBstr = [IntPtr]::Zero", "if ($Mode -notin @('RefreshOwnerScope','RefreshOwnerScopeA3','RefreshOwnerScopeA4','RefreshOwnerScopeA5','RefreshOwnerScopeA6','RefreshOwnerScopeA7','RefreshOwnerScopeA8','RefreshOwnerScopeA9') -and (Test-Path -LiteralPath (Join-Path $taskRoot 'docs/verification/wave5/private-owner-input-ready-20261014-r5-a9.json'))) {\n    $taskReadyFile = Join-Path $taskRoot 'docs/verification/wave5/private-owner-input-ready-20261014-r5-a9.json'\n}\n$taskSecret = $null\n$taskBstr = [IntPtr]::Zero");
once("    if ($Mode -eq 'ReadAuthQuota') {", `    if ($Mode -eq 'RefreshOwnerScopeA9') {\n        $taskInstaller = Join-Path $taskRoot '${successor}'\n        if ((Get-FileHash -LiteralPath $taskInstaller -Algorithm SHA256).Hash.ToLowerInvariant() -ne\n            '${helperSha256}') { throw 'OWNER_SCOPE_A9_SOURCE_CHANGED' }\n    }\n    if ($Mode -eq 'ReadAuthQuota') {`);
once("if ($taskReadyFile.EndsWith('-a8.json'))", "if ($taskReadyFile.EndsWith('-a9.json')) { 'metadata-renewed-a9.json' } elseif ($taskReadyFile.EndsWith('-a8.json'))");
once("'42bfdaa042aedac533e2b72552b45995b4e480aea593b4ee3b62f71d2c18ee11') -or", `'42bfdaa042aedac533e2b72552b45995b4e480aea593b4ee3b62f71d2c18ee11','${helperSha256}') -or`);
once("'RefreshOwnerScopeA8' { '--refresh' }", "'RefreshOwnerScopeA8' { '--refresh' } 'RefreshOwnerScopeA9' { '--refresh' }");
await fs.writeFile(new URL(successor, root), helper, { flag: 'wx' });
await fs.writeFile(new URL(adapterPath, root), adapter);
const record = {
  kind: 'same-authorized-owner-scope-readonly-expiry-recovery-source', recordedAt: new Date().toISOString(),
  helperPath: successor, helperPredecessorSha256: hashBytes(oldHelper), helperSha256,
  adapterBeforeSha256: hashBytes(oldAdapter), adapterAfterSha256: hashBytes(adapter),
  helperChanges: 'Exactly four -a8.json publication filenames become -a9.json; private credential, UTC, SID, ACL, project, original approval and read-only identity guards preserved.',
  newPrivateHelperMode: 'RefreshOwnerScopeA9', liveOperations: 0,
  nextOperation: 'One bounded read-only owner/project GET. Charge one attempted call to cumulative finance accounting before exports.',
  priorCumulativeFinanceCalls: 130, cumulativeAfterOneAttempt: 131,
  originalAuthorityExpiresAt: '2026-10-14T09:57:07.481942Z', authorityExtended: false,
  oldSourcesPlansMetadataAndConsumedIntentsPreserved: true, newCredentialRequested: false
};
await fs.writeFile(new URL('docs/verification/wave5/private-owner-scope-expiry-recovery-20261014-r5-a9.json', root), JSON.stringify(record, null, 2) + '\n', { flag: 'wx' });
process.stdout.write(JSON.stringify(record) + '\n');
