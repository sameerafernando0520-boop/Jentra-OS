param(
 [Parameter(Mandatory=$true)][ValidateSet('pubget','analyzer','domainTests','platformTests','nativeTests','windowsBuild')][string]$Stage,
 [string]$Snapshot = 'build/w5dates3',
 [ValidatePattern('^\d{8}$')][string]$EvidenceDate = '20261008'
)
$ErrorActionPreference = 'Stop'
$cashRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..'))
$cashSnapshot = [IO.Path]::GetFullPath((Join-Path $cashRoot $Snapshot))
$cashBuildRoot = [IO.Path]::GetFullPath((Join-Path $cashRoot 'build')) + [IO.Path]::DirectorySeparatorChar
if (-not $cashSnapshot.StartsWith($cashBuildRoot, [StringComparison]::OrdinalIgnoreCase)) { throw 'SNAPSHOT_OUTSIDE_WORKSPACE_BUILD' }
$cashWorking = $cashSnapshot
$cashPackage = $null
$cashSdk = 'C:\src\flutter\bin\flutter.bat'
switch ($Stage) {
 'pubget' { $cashArguments = @('pub','get') }
 'analyzer' {
  $cashSdk = 'C:\src\flutter\bin\dart.bat'
  $cashArguments = @('analyze','apps/jentra_desktop/lib/src/features/analytics','apps/jentra_desktop/lib/main.dart','apps/jentra_desktop/test/wave5_continuation_test.dart','packages/jentra_domain/lib/src/analytics','packages/jentra_domain/test/analytics','packages/jentra_platform/lib/src/analytics','packages/jentra_platform/test/analytics')
 }
 'domainTests' { $cashPackage = 'packages/jentra_domain'; $cashArguments = @('test','--no-pub','--concurrency=1','--reporter=expanded','test/analytics') }
 'platformTests' { $cashPackage = 'packages/jentra_platform'; $cashArguments = @('test','--no-pub','--concurrency=1','--reporter=expanded','test/analytics') }
 'nativeTests' {
  $cashPackage = 'apps/jentra_desktop'
  $cashArguments = @('test','--no-pub','--concurrency=1','--reporter=expanded','test/process_metric_workspace_test.dart','test/wave5_workspaces_test.dart','test/wave5_continuation_test.dart')
  $env:W5_CASH_FRAME_DIR = Join-Path $cashRoot ('docs/verification/wave5/cash-dates-frames-' + $EvidenceDate)
 }
 'windowsBuild' { $cashPackage = 'apps/jentra_desktop'; $cashArguments = @('build','windows','--release','--no-pub') }
}
if ($cashPackage) { $cashWorking = Join-Path $cashSnapshot $cashPackage }
$cashName = switch ($Stage) { 'pubget' {'pubget'} 'domainTests' {'domain-tests'} 'platformTests' {'platform-tests'} 'nativeTests' {'native-tests'} 'windowsBuild' {'windows-build'} default {'analyzer-final'} }
$cashLog = 'docs/verification/wave5/cash-dates-' + $cashName + '-' + $EvidenceDate + '.log'
$cashMeta = 'docs/verification/wave5/cash-dates-' + $cashName + '-' + $EvidenceDate + '.json'
$cashStarted = [DateTime]::UtcNow
$cashExit = 1
Push-Location -LiteralPath $cashWorking
try {
 & $cashSdk @cashArguments 2>&1 | Tee-Object -FilePath (Join-Path $cashRoot $cashLog)
 $cashExit = $LASTEXITCODE
} finally {
 Pop-Location
 [pscustomobject]@{workingDirectory=$cashWorking;package=$cashPackage;command=($cashSdk + ' ' + ($cashArguments -join ' '));log=$cashLog;startedAt=$cashStarted.ToString('o');finishedAt=[DateTime]::UtcNow.ToString('o');exitCode=$cashExit} |
  ConvertTo-Json | Set-Content -LiteralPath (Join-Path $cashRoot $cashMeta)
}
exit $cashExit
