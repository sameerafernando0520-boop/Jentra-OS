$ErrorActionPreference = 'Stop'
$taskRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..'))
$taskProbe = Join-Path $taskRoot 'build/w5kbdprobe20261014'
$taskEvidence = Join-Path $taskRoot 'docs/verification/wave5/keyboard-audit-20261014'
if ((Get-FileHash -LiteralPath (Join-Path $taskEvidence 'probe-preparation.json') -Algorithm SHA256).Hash.ToLowerInvariant() -ne '31611534b10221ea0e438a0f0b0c1e4f50b4c433b91008ff537a51c31a16a878') { throw 'EXACT_KEYBOARD_PROBE_PREPARATION_REQUIRED' }
if ((Get-FileHash -LiteralPath (Join-Path $taskProbe 'lib/main.dart') -Algorithm SHA256).Hash.ToLowerInvariant() -ne 'b123e0b7ba447bef7620e82c5030434601315730b4137a0d36aa6e067fb53dfc') { throw 'EXACT_SYNTHETIC_PROBE_SOURCE_REQUIRED' }
$taskDart = 'C:/src/flutter/bin/cache/dart-sdk/bin/dart.exe'
$taskSnapshot = 'C:/src/flutter/bin/cache/flutter_tools.snapshot'
$taskStages = @(
    @{ name='pubget'; arguments=@('pub','get','--offline') },
    @{ name='analysis'; arguments=@('analyze','--no-pub','lib/main.dart') },
    @{ name='build'; arguments=@('build','windows','--release','--no-pub','--target=lib/main.dart') }
)
Push-Location -LiteralPath $taskProbe
try {
    foreach ($taskStage in $taskStages) {
        $taskLog = Join-Path $taskEvidence ('actual-probe-' + $taskStage.name + '-a2.log')
        $taskRecord = Join-Path $taskEvidence ('actual-probe-' + $taskStage.name + '-a2.json')
        if ((Test-Path -LiteralPath $taskLog) -or (Test-Path -LiteralPath $taskRecord)) { throw 'PROBE_STAGE_ALREADY_RECORDED' }
        $taskStarted = [DateTimeOffset]::UtcNow.ToString('o')
        & $taskDart $taskSnapshot --suppress-analytics @($taskStage.arguments) > $taskLog 2>&1
        $taskExit = $LASTEXITCODE
        $taskMetadata = [ordered]@{ stage=$taskStage.name; project=$taskProbe; startedAt=$taskStarted; finishedAt=[DateTimeOffset]::UtcNow.ToString('o'); exitCode=$taskExit; arguments=$taskStage.arguments; log=$taskLog; productSourceEdited=$false; sdkJobsSerialized=$true; privateInputsRead=$false; networkedApp=$false; priorSdkLockPermissionFailurePreserved=$true; actualNativeInputVerified=$false }
        [IO.File]::WriteAllText($taskRecord,($taskMetadata | ConvertTo-Json -Depth 8) + [Environment]::NewLine,[Text.UTF8Encoding]::new($false))
        $taskMetadata | ConvertTo-Json -Compress -Depth 8
        if ($taskExit -ne 0) { throw 'KEYBOARD_PROBE_STAGE_FAILED' }
    }
} finally { Pop-Location }
