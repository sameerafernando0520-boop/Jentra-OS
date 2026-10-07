[CmdletBinding()]
param()
$ErrorActionPreference='Stop'
$taskSource=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../..'))
$taskTarget=[IO.Path]::GetFullPath('C:/jw4-integrated-20261004-a')
if($taskTarget -ne 'C:\jw4-integrated-20261004-a' -or -not(Test-Path -LiteralPath (Join-Path $taskTarget 'pubspec.yaml'))){throw 'Expected existing isolated verification snapshot.'}
$taskPrior=Get-Content -Raw -LiteralPath (Join-Path $PSScriptRoot 'service-milestone-native-snapshot-20261005.json')|ConvertFrom-Json
$taskPaths=@($taskPrior.path)+@(
 'packages/jentra_domain/lib/jentra_asset_equipment.dart','packages/jentra_domain/lib/src/asset_equipment.dart',
 'packages/jentra_domain/test/asset_equipment_test.dart','packages/jentra_domain/test/service_values_test.dart',
 'packages/jentra_platform/lib/jentra_asset_equipment_platform.dart','packages/jentra_platform/lib/src/supabase_asset_equipment_gateway.dart',
 'packages/jentra_platform/test/asset_equipment_gateway_test.dart','packages/jentra_platform/test/service_gateway_test.dart',
 'packages/jentra_platform/test/fixtures/asset_equipment_rollback_projections.json','packages/jentra_platform/test/support/wave4_gateway_harness.dart',
 'apps/jentra_desktop/lib/src/features/service/asset_equipment_controller.dart','apps/jentra_desktop/lib/src/features/service/asset_equipment_screen.dart',
 'apps/jentra_desktop/test/asset_equipment_workspace_test.dart')
$taskPaths=@($taskPaths|Sort-Object -Unique)
$taskBefore=@{}
foreach($taskPath in $taskPaths){
 $taskOriginal=[IO.Path]::GetFullPath((Join-Path $taskSource $taskPath))
 $taskCopy=[IO.Path]::GetFullPath((Join-Path $taskTarget $taskPath))
 if(-not $taskOriginal.StartsWith($taskSource+'\',[StringComparison]::OrdinalIgnoreCase) -or -not $taskCopy.StartsWith($taskTarget+'\',[StringComparison]::OrdinalIgnoreCase) -or $taskPath -match '(^|[/\\])(?:\.git|build|\.dart_tool|\.env)([/\\]|$)'){throw "Unexpected source selection: $taskPath"}
 $taskBefore[$taskPath]=(Get-FileHash -LiteralPath $taskOriginal).Hash
 New-Item -ItemType Directory -Path (Split-Path $taskCopy -Parent) -Force|Out-Null
 Copy-Item -LiteralPath $taskOriginal -Destination $taskCopy
}
$taskManifest=@(foreach($taskPath in $taskPaths){
 $taskCurrent=(Get-FileHash -LiteralPath (Join-Path $taskSource $taskPath)).Hash
 $taskCopied=(Get-FileHash -LiteralPath (Join-Path $taskTarget $taskPath)).Hash
 if($taskBefore[$taskPath] -ne $taskCurrent -or $taskCurrent -ne $taskCopied){throw "Source changed during copy: $taskPath"}
 [ordered]@{path=$taskPath;source=$taskCurrent;snapshot=$taskCopied}
})
[IO.File]::WriteAllText((Join-Path $PSScriptRoot 'service-asset-native-snapshot-20261006.json'),($taskManifest|ConvertTo-Json -Depth 8),[Text.UTF8Encoding]::new($false))
Write-Output "Copied and matched $($taskManifest.Count) explicit source/dependency files. Global snapshot remains unverified."
