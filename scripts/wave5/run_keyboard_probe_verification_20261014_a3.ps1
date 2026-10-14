$ErrorActionPreference = 'Stop'
$taskRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..'))
$taskProbe = Join-Path $taskRoot 'build/w5kbdprobe20261014'
$taskEvidence = Join-Path $taskRoot 'docs/verification/wave5/keyboard-audit-20261014'
$taskRepair = Join-Path $taskEvidence 'probe-source-repair-a3.json'
if ((Get-FileHash -LiteralPath $taskRepair -Algorithm SHA256).Hash.ToLowerInvariant() -ne 'a1705863b306b3b58dc5a37997c7abbc6eadde0d5aa9be2cf8f7e4d2f7ed1c6f') { throw 'EXACT_PROBE_REPAIR_REQUIRED' }
$taskBinding = Get-Content -LiteralPath $taskRepair -Raw | ConvertFrom-Json
foreach ($taskSource in $taskBinding.projectSources) {
    if ((Get-FileHash -LiteralPath $taskSource.path -Algorithm SHA256).Hash.ToLowerInvariant() -ne $taskSource.sha256) { throw 'EXACT_PROBE_SOURCE_BINDINGS_REQUIRED' }
}
$taskPriorPub = Get-Content -LiteralPath (Join-Path $taskEvidence 'actual-probe-pubget-a2.json') -Raw | ConvertFrom-Json
if ($taskPriorPub.exitCode -ne 0) { throw 'ACTUAL_PRIOR_OFFLINE_PUBGET_REQUIRED' }
$taskDart = 'C:/src/flutter/bin/cache/dart-sdk/bin/dart.exe'
$taskSnapshot = 'C:/src/flutter/bin/cache/flutter_tools.snapshot'
$taskStages = @(
    @{ name='analysis'; arguments=@('analyze','--no-pub','lib/main.dart') },
    @{ name='build'; arguments=@('build','windows','--release','--no-pub','--target=lib/main.dart') }
)
Push-Location -LiteralPath $taskProbe
try {
    foreach ($taskStage in $taskStages) {
        $taskLog = Join-Path $taskEvidence ('actual-probe-' + $taskStage.name + '-a3.log')
        $taskRecord = Join-Path $taskEvidence ('actual-probe-' + $taskStage.name + '-a3.json')
        if ((Test-Path -LiteralPath $taskLog) -or (Test-Path -LiteralPath $taskRecord)) { throw 'PROBE_STAGE_ALREADY_RECORDED' }
        $taskStarted = [DateTimeOffset]::UtcNow.ToString('o')
        & $taskDart $taskSnapshot --suppress-analytics @($taskStage.arguments) > $taskLog 2>&1
        $taskExit = $LASTEXITCODE
        $taskMetadata = [ordered]@{ stage=$taskStage.name; project=$taskProbe; startedAt=$taskStarted; finishedAt=[DateTimeOffset]::UtcNow.ToString('o'); exitCode=$taskExit; arguments=$taskStage.arguments; log=$taskLog; sourceRepairSha256='a1705863b306b3b58dc5a37997c7abbc6eadde0d5aa9be2cf8f7e4d2f7ed1c6f'; priorActualOfflinePubgetReused=$true; productSourceEdited=$false; sdkJobsSerialized=$true; privateInputsRead=$false; networkedApp=$false; priorFailuresPreserved=$true; actualNativeInputVerified=$false }
        [IO.File]::WriteAllText($taskRecord,($taskMetadata | ConvertTo-Json -Depth 8) + [Environment]::NewLine,[Text.UTF8Encoding]::new($false))
        $taskMetadata | ConvertTo-Json -Compress -Depth 8
        if ($taskExit -ne 0) { throw 'KEYBOARD_PROBE_STAGE_FAILED' }
    }
} finally { Pop-Location }
