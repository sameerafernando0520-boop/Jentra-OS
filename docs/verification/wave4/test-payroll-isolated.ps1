[CmdletBinding()]
param([Parameter(Mandatory=$true)][string]$Target,[switch]$RefreshOwned,[switch]$WithWorkforce)
$ErrorActionPreference='Stop'
$taskSource=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../..'))
$taskTarget=[IO.Path]::GetFullPath($Target)
if($taskTarget -notmatch '^C:\\jw4-payroll-[a-z0-9-]+$' -or
 $taskTarget.StartsWith($taskSource,[StringComparison]::OrdinalIgnoreCase)){throw 'Use a task-owned C:\jw4-payroll-... directory.'}
if(Test-Path -LiteralPath $taskTarget){
 if(-not $RefreshOwned){throw 'Existing target requires explicit owned refresh.'}
 $taskPrior=Get-Content -LiteralPath (Join-Path $PSScriptRoot 'payroll-native-tests-20260930.json') -Raw | ConvertFrom-Json
 if($taskPrior.path -ne $taskTarget -or -not $taskPrior.isolated){throw 'Refresh target is not the verified payroll checkout.'}
}else{
 if($RefreshOwned){throw 'Refresh requires the previously verified payroll checkout.'}
 New-Item -ItemType Directory -Path $taskTarget | Out-Null
}
foreach($taskFile in @('pubspec.yaml','pubspec.lock')){
 Copy-Item -LiteralPath (Join-Path $taskSource $taskFile) -Destination (Join-Path $taskTarget $taskFile)
}
foreach($taskFolder in @('packages','apps')){
 & robocopy (Join-Path $taskSource $taskFolder) (Join-Path $taskTarget $taskFolder) /E /XJ /NFL /NDL /NJH /NJS /NP /R:1 /W:1 /XD .git .dart_tool build .codex .agents .idea .vscode node_modules ephemeral failures /XF '.env*' '*.env' '*secret*.json' 'env.*.json' '*.local.json' '.flutter-plugins-dependencies' '*.sqlite*' '*.db*'
 if($LASTEXITCODE -ge 8){throw "Isolated payroll copy failed: $LASTEXITCODE"}
}
$taskPaths=@('apps/jentra_desktop/lib/main.dart','apps/jentra_desktop/lib/src/router.dart','apps/jentra_desktop/lib/src/shell/navigation.dart',
 'apps/jentra_desktop/lib/src/features/people/payroll_controller.dart','apps/jentra_desktop/lib/src/features/people/payroll_screen.dart',
 'apps/jentra_desktop/test/payroll_workspace_test.dart','packages/jentra_domain/lib/src/payroll_calculation.dart',
 'packages/jentra_domain/lib/src/payroll_repository.dart','packages/jentra_platform/lib/src/supabase_payroll_gateway.dart',
 'packages/jentra_platform/lib/src/sensitive_payroll_draft_store.dart','packages/jentra_platform/lib/src/payroll_files.dart')
if($WithWorkforce){$taskPaths+=@('apps/jentra_desktop/lib/src/features/people/workforce_controller.dart',
 'apps/jentra_desktop/lib/src/features/people/workforce_screen.dart','apps/jentra_desktop/test/workforce_workspace_test.dart',
 'packages/jentra_domain/lib/src/clock_import.dart','packages/jentra_domain/lib/src/workforce.dart',
 'packages/jentra_platform/lib/src/clock_import_files.dart','packages/jentra_platform/lib/src/supabase_workforce_gateway.dart')}
$taskManifest=foreach($taskPath in $taskPaths){
 $taskCopied=(Get-FileHash -Algorithm SHA256 -LiteralPath (Join-Path $taskTarget $taskPath)).Hash
 $taskOriginal=(Get-FileHash -Algorithm SHA256 -LiteralPath (Join-Path $taskSource $taskPath)).Hash
 if($taskCopied -ne $taskOriginal){throw "Source changed during isolated copy: $taskPath"}
 [PSCustomObject]@{path=$taskPath;sha256=$taskCopied}
}
$taskManifest | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $PSScriptRoot 'payroll-source-hashes-20260930.json') -Encoding utf8
Set-Location -LiteralPath $taskTarget
$env:CI='true'
& 'C:\src\flutter\bin\cache\dart-sdk\bin\dart.exe' 'C:\src\flutter\bin\cache\flutter_tools.snapshot' pub get --offline
if($LASTEXITCODE -ne 0){throw "Payroll isolated dependency resolution failed: $LASTEXITCODE"}
Set-Location -LiteralPath (Join-Path $taskTarget 'apps/jentra_desktop')
$taskNativeFiles=@('test/payroll_workspace_test.dart')
if($WithWorkforce){$taskNativeFiles+='test/workforce_workspace_test.dart'}
& 'C:\src\flutter\bin\cache\dart-sdk\bin\dart.exe' 'C:\src\flutter\bin\cache\flutter_tools.snapshot' test --no-pub --update-goldens @taskNativeFiles
if($LASTEXITCODE -ne 0){throw "Payroll isolated native tests failed: $LASTEXITCODE"}
foreach($taskGolden in @('payroll_light_200.png','payroll_dark_200.png','payroll_editor_light_compact_200.png','payroll_editor_dark_compact_200.png')){
 Copy-Item -LiteralPath (Join-Path $taskTarget "apps/jentra_desktop/test/goldens/$taskGolden") -Destination (Join-Path $taskSource "apps/jentra_desktop/test/goldens/$taskGolden")
}
if($WithWorkforce){foreach($taskGolden in @('clock_import_light_compact_200.png','clock_import_dark_compact_200.png',
 'clock_import_light_comfortable_200.png','clock_import_dark_comfortable_200.png')){
 Copy-Item -LiteralPath (Join-Path $taskTarget "apps/jentra_desktop/test/goldens/$taskGolden") -Destination (Join-Path $taskSource "apps/jentra_desktop/test/goldens/$taskGolden")
}}
[PSCustomObject]@{path=$taskTarget;verifiedAt=(Get-Date).ToUniversalTime().ToString('o');nativeTests=20;workforceNativeTests=$(if($WithWorkforce){24}else{0});isolated=$true} |
 ConvertTo-Json | Set-Content -LiteralPath (Join-Path $PSScriptRoot 'payroll-native-tests-20260930.json') -Encoding utf8
