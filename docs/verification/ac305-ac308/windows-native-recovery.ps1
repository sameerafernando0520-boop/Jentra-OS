param(
  [string]$FlutterRoot = 'C:\src\flutter'
)
$ErrorActionPreference = 'Stop'
$recoveryWorkspace = (Resolve-Path (Join-Path $PSScriptRoot '../../..')).Path
$recoveryApp = Join-Path $recoveryWorkspace 'apps/jentra_desktop'
$recoveryDart = Join-Path $FlutterRoot 'bin/cache/dart-sdk/bin/dart.exe'
$recoveryTools = Join-Path $FlutterRoot 'packages/flutter_tools'
$recoveryRunId = [Guid]::NewGuid().ToString()
$recoveryRun = Join-Path $recoveryApp "build/native-recovery-$recoveryRunId"
$recoveryRelease = Join-Path $recoveryApp 'build/windows/x64/runner/Release'
$recoveryBinary = Join-Path $recoveryRun 'application/jentra_desktop.exe'
$recoveryEvidenceFile = Join-Path $PSScriptRoot 'windows-native-recovery.json'
$recoveryResults = [System.Collections.Generic.List[object]]::new()
$recoveryBuildChanged = $false

function Invoke-RecoveryBuild([string]$Target) {
  Push-Location -LiteralPath $recoveryApp
  try {
    & $recoveryDart "--packages=$recoveryTools/.dart_tool/package_config.json" (Join-Path $FlutterRoot 'bin/cache/flutter_tools.snapshot') build windows --release --no-pub --target $Target
    if ($LASTEXITCODE -ne 0) { throw "Windows build failed for $Target" }
  }
  finally { Pop-Location }
}

function Invoke-RecoveryPhase([string]$Phase) {
  $recoveryResultFile = Join-Path $recoveryRun "$Phase.json"
  $recoveryArguments = @($Phase, ('"' + $recoveryRun + '"'), $recoveryRunId)
  $recoveryProcess = Start-Process -FilePath $recoveryBinary -ArgumentList $recoveryArguments -WorkingDirectory (Split-Path $recoveryBinary) -WindowStyle Hidden -PassThru
  try {
    $recoveryDeadline = [DateTime]::UtcNow.AddSeconds(30)
    $recoveryResult = $null
    while ([DateTime]::UtcNow -lt $recoveryDeadline) {
      if (Test-Path -LiteralPath $recoveryResultFile) {
        try { $recoveryResult = Get-Content -LiteralPath $recoveryResultFile -Raw | ConvertFrom-Json } catch { }
        if ($null -ne $recoveryResult) { break }
      }
      $recoveryProcess.Refresh()
      if ($recoveryProcess.HasExited) { throw "Native probe exited before $Phase completed." }
      Start-Sleep -Milliseconds 100
    }
    if ($null -eq $recoveryResult) { throw "Native probe timed out in $Phase." }
    if (-not $recoveryResult.passed) { throw ($recoveryResult | ConvertTo-Json -Depth 8) }
    if ($recoveryResult.pid -ne $recoveryProcess.Id) { throw 'Probe process identity mismatch.' }
    $recoveryResults.Add($recoveryResult)
    Write-Host "Native recovery phase passed: $Phase (process $($recoveryProcess.Id))"
  }
  finally {
    $recoveryProcess.Refresh()
    if (-not $recoveryProcess.HasExited) {
      Stop-Process -Id $recoveryProcess.Id -Force
      if (-not $recoveryProcess.WaitForExit(10000)) { throw 'Probe process did not terminate.' }
    }
    $recoveryProcess.Dispose()
  }
}

New-Item -ItemType Directory -Path $recoveryRun | Out-Null
[ordered]@{ runId = $recoveryRunId; passed = $false; status = 'running' } |
  ConvertTo-Json | Set-Content -LiteralPath $recoveryEvidenceFile
try {
  $recoveryBuildChanged = $true
  Invoke-RecoveryBuild 'tool/windows_recovery_probe.dart'
  Copy-Item -LiteralPath $recoveryRelease -Destination (Join-Path $recoveryRun 'application') -Recurse
  foreach ($recoveryPhase in @('seed', 'interrupt', 'retry', 'verify')) {
    Invoke-RecoveryPhase $recoveryPhase
  }
}
catch {
  [ordered]@{
    runId = $recoveryRunId
    passed = $false
    status = 'failed'
    error = $_.Exception.Message
    phasesDirectory = $recoveryRun
  } | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $recoveryEvidenceFile
  throw
}
finally {
  try {
    if (Test-Path -LiteralPath $recoveryBinary) { Invoke-RecoveryPhase 'cleanup' }
  }
  finally {
    # Always restore the ordinary app build after using an alternate entry point.
    if ($recoveryBuildChanged) { Invoke-RecoveryBuild 'lib/main.dart' }
  }
}

$recoveryReport = [ordered]@{
  checkedAtUtc = [DateTime]::UtcNow.ToString('o')
  sourceHead = (git -C $recoveryWorkspace rev-parse HEAD)
  runId = $recoveryRunId
  configuration = 'Windows release; native secure storage and disk SQLite; synthetic gateway'
  passed = ($recoveryResults.Count -eq 5)
  status = 'passed'
  phaseResults = $recoveryResults.ToArray()
  forcedTerminationWithDatabaseOpen = @('seed', 'interrupt')
  ordinaryReleaseBuildRestored = $true
  authenticatedWorkflowVerified = $false
  crossProcessSimultaneousFirstLaunchVerified = $false
  phasesDirectory = $recoveryRun
}
$recoveryReport | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $recoveryEvidenceFile
$recoveryReport | ConvertTo-Json -Depth 8
