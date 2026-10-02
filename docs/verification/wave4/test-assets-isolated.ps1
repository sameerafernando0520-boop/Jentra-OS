[CmdletBinding()]
param([Parameter(Mandatory=$true)][string]$Target,[switch]$RefreshOwned)
$ErrorActionPreference='Stop'
$taskSource=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../..'))
$taskTarget=[IO.Path]::GetFullPath($Target)
if($taskTarget -notmatch '^C:\\jw4-assets-[a-z0-9-]+$' -or $taskTarget.StartsWith($taskSource,[StringComparison]::OrdinalIgnoreCase)){
 throw 'Use a separate task-owned C:\jw4-assets-... directory.'
}
$taskEvidencePath=Join-Path $PSScriptRoot 'assets-native-tests-20261001.json'
if(Test-Path -LiteralPath $taskTarget){
 if(-not $RefreshOwned){throw 'An existing target requires explicit owned refresh.'}
 $taskPrior=Get-Content -LiteralPath $taskEvidencePath -Raw | ConvertFrom-Json
 if($taskPrior.path -ne $taskTarget -or -not $taskPrior.isolated){throw 'Target is not the verified asset checkout.'}
}else{
 if($RefreshOwned){throw 'Refresh requires a verified asset checkout.'}
 New-Item -ItemType Directory -Path $taskTarget | Out-Null
}
foreach($taskFile in @('pubspec.yaml','pubspec.lock')){
 Copy-Item -LiteralPath (Join-Path $taskSource $taskFile) -Destination (Join-Path $taskTarget $taskFile)
}
foreach($taskFolder in @('packages','apps')){
 & robocopy (Join-Path $taskSource $taskFolder) (Join-Path $taskTarget $taskFolder) /E /XJ /NFL /NDL /NJH /NJS /NP /R:1 /W:1 /XD .git .dart_tool build .codex .agents .idea .vscode node_modules ephemeral failures /XF '.env*' '*.env' '*secret*.json' 'env.*.json' '*.local.json' '.flutter-plugins-dependencies' '*.sqlite*' '*.db*'
 if($LASTEXITCODE -ge 8){throw "Isolated asset copy failed: $LASTEXITCODE"}
}
$taskPaths=@('pubspec.yaml','pubspec.lock','apps/jentra_desktop/pubspec.yaml',
 'packages/jentra_domain/pubspec.yaml','packages/jentra_platform/pubspec.yaml',
 'apps/jentra_desktop/lib/main.dart','apps/jentra_desktop/lib/src/router.dart','apps/jentra_desktop/lib/src/shell/navigation.dart',
 'apps/jentra_desktop/lib/src/features/assets/assets_controller.dart','apps/jentra_desktop/lib/src/features/assets/assets_screen.dart',
 'apps/jentra_desktop/test/assets_workspace_test.dart',
 'packages/jentra_domain/lib/jentra_assets.dart','packages/jentra_domain/lib/src/fixed_asset_schedule.dart','packages/jentra_domain/lib/src/assets_repository.dart',
 'packages/jentra_domain/test/fixed_asset_schedule_test.dart','packages/jentra_domain/test/assets_repository_test.dart',
 'packages/jentra_platform/lib/jentra_assets_platform.dart','packages/jentra_platform/lib/src/supabase_assets_gateway.dart',
 'packages/jentra_platform/lib/src/scoped_command_draft_store.dart',
 'packages/jentra_platform/test/assets_gateway_test.dart','packages/jentra_platform/test/fixtures/assets_rollback_projections.json')
$taskManifest=foreach($taskPath in $taskPaths){
 $taskCopied=(Get-FileHash -Algorithm SHA256 -LiteralPath (Join-Path $taskTarget $taskPath)).Hash
 $taskOriginal=(Get-FileHash -Algorithm SHA256 -LiteralPath (Join-Path $taskSource $taskPath)).Hash
 if($taskCopied -ne $taskOriginal){throw "Source changed during asset copy: $taskPath"}
 [PSCustomObject]@{path=$taskPath;sha256=$taskCopied}
}
$taskManifest | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $PSScriptRoot 'assets-source-hashes-20261001.json') -Encoding utf8
Set-Location -LiteralPath $taskTarget
$env:CI='true'
& 'C:\src\flutter\bin\cache\dart-sdk\bin\dart.exe' 'C:\src\flutter\bin\cache\flutter_tools.snapshot' pub get --offline
if($LASTEXITCODE -ne 0){throw 'Isolated asset dependency resolution failed.'}
Set-Location -LiteralPath (Join-Path $taskTarget 'apps/jentra_desktop')
& 'C:\src\flutter\bin\cache\dart-sdk\bin\dart.exe' 'C:\src\flutter\bin\cache\flutter_tools.snapshot' test --no-pub test/assets_workspace_test.dart
if($LASTEXITCODE -ne 0){throw 'Isolated asset native checks failed.'}
[PSCustomObject]@{path=$taskTarget;verifiedAt=(Get-Date).ToUniversalTime().ToString('o');nativeTests=20;isolated=$true;installed=$false;launched=$false} |
 ConvertTo-Json | Set-Content -LiteralPath $taskEvidencePath -Encoding utf8
