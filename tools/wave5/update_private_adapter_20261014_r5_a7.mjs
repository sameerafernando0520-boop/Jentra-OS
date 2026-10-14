import fs from 'node:fs/promises';
import {hashBytes} from './runtime_contract.mjs';
const root=new URL('../../',import.meta.url),file='scripts/wave5/run_private_management_installer_20261013_r5.ps1';
const b=await fs.readFile(new URL(file,root));
if(hashBytes(b)!=='f592ed065716260ca9688b31c191bc55303978ea3d10b49001a8c8431c4b9bd5')throw Error('EXACT_MUTABLE_ADAPTER_PREDECESSOR_REQUIRED');
let s=b.toString('utf8');const lists=(s.match(/,'RefreshOwnerScopeA6'/g)||[]).length;
if(lists!==11)throw Error('EXACT_REFRESH_LIST_COUNT_REQUIRED');
s=s.replaceAll(",'RefreshOwnerScopeA6'",",'RefreshOwnerScopeA6','RefreshOwnerScopeA7'");
function once(a,c){if(s.split(a).length!==2)throw Error('EXACT_A7_ADAPTER_ANCHOR_REQUIRED');s=s.replace(a,c);}
once("$taskSecret = $null\n$taskBstr = [IntPtr]::Zero", "if ($Mode -notin @('RefreshOwnerScope','RefreshOwnerScopeA3','RefreshOwnerScopeA4','RefreshOwnerScopeA5','RefreshOwnerScopeA6','RefreshOwnerScopeA7') -and (Test-Path -LiteralPath (Join-Path $taskRoot 'docs/verification/wave5/private-owner-input-ready-20261014-r5-a7.json'))) {\n    $taskReadyFile = Join-Path $taskRoot 'docs/verification/wave5/private-owner-input-ready-20261014-r5-a7.json'\n}\n$taskSecret = $null\n$taskBstr = [IntPtr]::Zero");
once("    if ($Mode -eq 'ReadAuthQuota') {", "    if ($Mode -eq 'RefreshOwnerScopeA7') {\n        $taskInstaller = Join-Path $taskRoot 'tools/wave5/refresh_private_owner_scope_20261014_r5_a7.mjs'\n        if ((Get-FileHash -LiteralPath $taskInstaller -Algorithm SHA256).Hash.ToLowerInvariant() -ne\n            '5aec90224966338275149917bf6a9f0d30e53db159a33c1c65a9a32f529b9ddf') { throw 'OWNER_SCOPE_A7_SOURCE_CHANGED' }\n    }\n    if ($Mode -eq 'ReadAuthQuota') {");
once("if ($taskReadyFile.EndsWith('-a6.json'))", "if ($taskReadyFile.EndsWith('-a7.json')) { 'metadata-renewed-a7.json' } elseif ($taskReadyFile.EndsWith('-a6.json'))");
once("'3910f1311d69ac9b2bc8a682174e5546f24b6edcf176ab7bc56a8f0087480022') -or", "'3910f1311d69ac9b2bc8a682174e5546f24b6edcf176ab7bc56a8f0087480022','5aec90224966338275149917bf6a9f0d30e53db159a33c1c65a9a32f529b9ddf') -or");
once("'ReadAuthQuota' { '--read' }", "'ReadAuthQuota' { '--read' } 'RefreshOwnerScopeA7' { '--refresh' }");
await fs.writeFile(new URL(file,root),s);
process.stdout.write(JSON.stringify({adapterUpdated:true,sourceBeforeSha256:hashBytes(b),sourceAfterSha256:hashBytes(s),refreshListsUpdated:lists,originalSealedCredentialUnchanged:true,frozenInstallersChanged:false})+'\n');
