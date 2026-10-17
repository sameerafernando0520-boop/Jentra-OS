param()
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$taskWorkspace = 'C:\Users\sheha\Desktop\Jentra OS'
$taskOwned = Join-Path $taskWorkspace 'docs\verification\wave5\seven-area-completion-20261016\area1-windows'
if (-not [IO.Path]::GetFullPath($PSScriptRoot).Equals($taskOwned, [StringComparison]::OrdinalIgnoreCase)) { throw 'EXACT_AREA1_DIRECTORY_REQUIRED' }
$taskInputs = @(
    'scripts/wave5/prepare_native_runtime_profile_20261013_r5_a2.ps1',
    'dist/Jentra OS Isolated Windows Setup 20261013 r5 a2.cmd',
    'docs/verification/wave5/task3-acceptance-20261013/delegated-technical-acceptance-matrix.json',
    'docs/verification/wave5/task3-windows-20261013/native-acceptance-protocol.md',
    'apps/jentra_desktop/lib/src/features/analytics/process_metric_controller.dart',
    'apps/jentra_desktop/lib/src/features/analytics/process_metric_screen.dart',
    'packages/jentra_platform/lib/src/analytics/process_filter_store.dart',
    'packages/jentra_platform/lib/src/draft_repository.dart',
    'packages/jentra_platform/lib/src/local_draft_storage_failure.dart',
    'apps/jentra_desktop/test/process_metric_workspace_test.dart',
    'packages/jentra_platform/test/analytics/process_filter_store_test.dart',
    'packages/jentra_platform/test/local_draft_storage_failure_test.dart'
)
function Get-TaskBinding([string]$Relative) {
    $taskFile = Join-Path $taskWorkspace $Relative
    [ordered]@{ path = $Relative; bytes = (Get-Item -LiteralPath $taskFile).Length; sha256 = (Get-FileHash -LiteralPath $taskFile -Algorithm SHA256).Hash.ToLowerInvariant() }
}
$taskBefore = @($taskInputs | ForEach-Object { Get-TaskBinding $_ })
if ($taskBefore[0].sha256 -ne 'ed59d1a53d50ddc79187cb2ddcd7512d3e0310fd56b9b873ba20298b5c3f6bcf' -or $taskBefore[1].sha256 -ne '4ed8321673f8b65894666b4867e8cc479a0ba311240878d2203cc8691aa51549') { throw 'APPROVED_HELPER_OR_LAUNCHER_CHANGED' }
$taskStarted = [DateTimeOffset]::UtcNow.ToString('o')
$taskOutput = @(& (Join-Path $taskWorkspace $taskInputs[0]) -Mode Validate)
$taskValidation = (($taskOutput | ForEach-Object { [string]$_ }) -join [Environment]::NewLine) | ConvertFrom-Json
if ($taskValidation.kind -ne 'wave5-native-profile-read-only-validation' -or $taskValidation.passed -ne $true -or $taskValidation.privateInputRead -ne $false -or $taskValidation.networkCalls -ne 0 -or $taskValidation.nativeLaunched -ne $false) { throw 'READ_ONLY_VALIDATION_REQUIRED' }
$taskAfter = @($taskInputs | ForEach-Object { Get-TaskBinding $_ })
if (($taskBefore | ConvertTo-Json -Compress) -ne ($taskAfter | ConvertTo-Json -Compress)) { throw 'SOURCE_CHANGED_DURING_OBSERVATION' }
$taskIds = @('FR-530','FR-531','NFR-508','AC-515','EC-513','FR-558','FR-559','AC-556','EC-558')
$taskMatrix = Get-Content -Raw -LiteralPath (Join-Path $taskWorkspace $taskInputs[2]) | ConvertFrom-Json
$taskRows = @($taskMatrix.rows | Where-Object { $_.id -in $taskIds } | Select-Object id,fullStatement,statementSha256,decision,accepted,nextEvidence)
if ($taskRows.Count -ne 9 -or @($taskRows | Where-Object { $_.accepted -ne $false }).Count -ne 0) { throw 'EXACT_NINE_OPEN_ROWS_REQUIRED' }
$taskReport = [ordered]@{
    kind = 'wave5-seven-area-native-prerequisites-readonly'; startedAt = $taskStarted; observedAt = [DateTimeOffset]::UtcNow.ToString('o');
    prerequisiteValidation = $taskValidation; exactNewProfileDirectoryPresent = Test-Path -LiteralPath 'C:\Users\jentra-w5-runtime';
    sourceInputs = $taskAfter; sourceInputsUnchanged = $true; requirementRows = $taskRows;
    observerSha256 = (Get-FileHash -LiteralPath $PSCommandPath -Algorithm SHA256).Hash.ToLowerInvariant();
    nativeActionsExecuted = 0; authenticatedNative = $false; newAcceptanceDecisions = 0; SDKExecuted = $false; networkCalls = 0;
    privateCredentialsRead = $false; existingProfilesOrStoresReadOrCopied = $false; securityPromptsAutomated = $false;
    boundary = 'Validation checks package/source integrity only. It does not establish native keyboard, login, MFA, recovery, context change, revocation, or Windows failure behavior.'
}
$taskPath = Join-Path $taskOwned ('native-prerequisites-' + [DateTimeOffset]::UtcNow.ToString('yyyyMMddTHHmmssfffZ') + '.json')
$taskBytes = [Text.UTF8Encoding]::new($false).GetBytes(($taskReport | ConvertTo-Json -Depth 16) + [Environment]::NewLine)
$taskStream = [IO.FileStream]::new($taskPath, [IO.FileMode]::CreateNew, [IO.FileAccess]::Write, [IO.FileShare]::None)
try { $taskStream.Write($taskBytes,0,$taskBytes.Length); $taskStream.Flush($true) } finally { $taskStream.Dispose() }
[ordered]@{ path = $taskPath; sha256 = (Get-FileHash -LiteralPath $taskPath -Algorithm SHA256).Hash.ToLowerInvariant(); passed = $true; approvedSourceInputsVerified = $taskValidation.sourceInputsVerified; connectedFilesVerified = $taskValidation.connectedReleaseFilesVerified; accountPresent = $taskValidation.targetAccountExists; packagePresent = $taskValidation.targetPackageExists; profilePresent = $taskReport.exactNewProfileDirectoryPresent; nativeActions = 0; accepted = 0 } | ConvertTo-Json -Compress
