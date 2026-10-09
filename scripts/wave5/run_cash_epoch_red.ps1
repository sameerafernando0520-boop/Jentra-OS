param([string]$Revision = 'r13')
$ErrorActionPreference = 'Stop'
$epochRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..'))
$epochFinal = Join-Path $epochRoot ('build/w5win9' + $Revision + '/preview')
$epochOld = Join-Path $epochRoot 'build/w5win9r10/preview'
$epochControl = Join-Path $epochRoot ('build/w5win9' + $Revision + '/regression-control')
if (Test-Path -LiteralPath $epochControl) { throw 'NEW_REGRESSION_CONTROL_REQUIRED' }
$epochManifest = Get-Content -LiteralPath (Join-Path $epochRoot ('docs/verification/wave5/windows-test-preview-source-20261009-' + $Revision + '.json')) -Raw | ConvertFrom-Json
$epochFiles = @('apps/jentra_desktop/lib/src/features/analytics/cash_scenario_screen.dart', 'apps/jentra_desktop/lib/src/features/analytics/cash_payment_dates_section.dart', 'packages/jentra_platform/lib/src/analytics/cash_scenario_store.dart', 'packages/jentra_platform/lib/src/analytics/wave5_command_store.dart')
$epochBindings = @()
foreach ($epochFile in $epochFiles) {
 $epochTarget = Join-Path $epochFinal $epochFile
 $epochHash = (Get-FileHash -LiteralPath $epochTarget -Algorithm SHA256).Hash.ToLowerInvariant()
 if ($epochHash -ne $epochManifest.buildSourceHashes.$epochFile) { throw 'FROZEN_SNAPSHOT_DRIFT' }
 $epochBackup = Join-Path $epochControl $epochFile
 New-Item -ItemType Directory -Path ([IO.Path]::GetDirectoryName($epochBackup)) -Force | Out-Null
 Copy-Item -LiteralPath $epochTarget -Destination $epochBackup
 $epochBindings += [pscustomobject]@{path=$epochFile; finalSha256=$epochHash; originalR10Sha256=(Get-FileHash -LiteralPath (Join-Path $epochOld $epochFile) -Algorithm SHA256).Hash.ToLowerInvariant()}
}
$epochExit = $null
try {
 foreach ($epochFile in $epochFiles) { Copy-Item -LiteralPath (Join-Path $epochOld $epochFile) -Destination (Join-Path $epochFinal $epochFile) }
 & (Join-Path $PSScriptRoot 'run_windows_test_build.ps1') -Mode Preview -Stage cashEpochRed -Revision $Revision
 $epochExit = $LASTEXITCODE
} finally {
 foreach ($epochBinding in $epochBindings) {
  Copy-Item -LiteralPath (Join-Path $epochControl $epochBinding.path) -Destination (Join-Path $epochFinal $epochBinding.path)
  if ((Get-FileHash -LiteralPath (Join-Path $epochFinal $epochBinding.path) -Algorithm SHA256).Hash.ToLowerInvariant() -ne $epochBinding.finalSha256) { throw 'FINAL_SOURCE_NOT_RESTORED' }
 }
}
$epochLog = 'docs/verification/wave5/windows-test-preview-cashEpochRed-20261009-' + $Revision + '.log'
$epochText = Get-Content -LiteralPath (Join-Path $epochRoot $epochLog) -Raw
$epochRed = $epochExit -ne 0 -and $epochText.Contains('Some tests failed.') -and -not $epochText.Contains('Compilation failed')
[pscustomobject]@{revision=$Revision; originalControlRevision='r10'; sourceRestored=$true; redObserved=$epochRed; exitCode=$epochExit; log=$epochLog; bindings=$epochBindings; workspaceSourceChanged=$false} | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath (Join-Path $epochRoot ('docs/verification/wave5/cash-epoch-red-20261009-' + $Revision + '.json'))
if (-not $epochRed) { throw 'EXPECTED_BEHAVIOR_REGRESSION_NOT_OBSERVED' }
