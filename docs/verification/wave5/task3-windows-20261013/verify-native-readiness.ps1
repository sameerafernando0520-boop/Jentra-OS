param()
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$taskWorkspace = 'C:\Users\sheha\Desktop\Jentra OS'
$taskEvidenceDirectory = Join-Path $taskWorkspace 'docs\verification\wave5\task3-windows-20261013'
if (-not [IO.Path]::GetFullPath($PSScriptRoot).Equals($taskEvidenceDirectory, [StringComparison]::OrdinalIgnoreCase)) {
    throw 'EXACT_OWNED_EVIDENCE_DIRECTORY_REQUIRED'
}
$taskHelper = Join-Path $taskWorkspace 'scripts\wave5\prepare_native_runtime_profile_20261013_r5_a2.ps1'
$taskLauncher = Join-Path $taskWorkspace 'dist\Jentra OS Isolated Windows Setup 20261013 r5 a2.cmd'
$taskHelperHash = (Get-FileHash -LiteralPath $taskHelper -Algorithm SHA256).Hash.ToLowerInvariant()
$taskLauncherHash = (Get-FileHash -LiteralPath $taskLauncher -Algorithm SHA256).Hash.ToLowerInvariant()
if ($taskHelperHash -ne 'ed59d1a53d50ddc79187cb2ddcd7512d3e0310fd56b9b873ba20298b5c3f6bcf' -or
    $taskLauncherHash -ne '4ed8321673f8b65894666b4867e8cc479a0ba311240878d2203cc8691aa51549') {
    throw 'APPROVED_NATIVE_HELPER_OR_LAUNCHER_CHANGED'
}
$taskStartedAt = [DateTimeOffset]::UtcNow.ToString('o')
$taskOutput = @(& $taskHelper -Mode Validate)
$taskOutputText = ($taskOutput | ForEach-Object { [string]$_ }) -join [Environment]::NewLine
$taskValidation = $taskOutputText | ConvertFrom-Json
if ($taskValidation.kind -ne 'wave5-native-profile-read-only-validation' -or $taskValidation.passed -ne $true) {
    throw 'APPROVED_NATIVE_VALIDATION_REQUIRED'
}
$taskReport = [ordered]@{
    kind = 'wave5-task3-native-prerequisites'; startedAt = $taskStartedAt;
    finishedAt = [DateTimeOffset]::UtcNow.ToString('o');
    prerequisiteValidation = $taskValidation;
    helperSha256 = $taskHelperHash; launcherSha256 = $taskLauncherHash;
    observerSha256 = (Get-FileHash -LiteralPath $PSCommandPath -Algorithm SHA256).Hash.ToLowerInvariant();
    exactNewProfileDirectoryPresent = Test-Path -LiteralPath 'C:\Users\jentra-w5-runtime';
    connectedNativeLaunch = 'unverified'; connectedNativeAuthentication = 'unverified';
    connectedNativeMfa = 'unverified'; nativeKeyboard = 'unverified';
    encryptedNativeRestartRecovery = 'unverified'; actorSwitchAndRevocation = 'unverified';
    existingPreviewWindowOwnedByOtherChat = $true;
    nativeActionsExecuted = 0; privateCredentialsRead = $false;
    existingProfilesOrStoresReadOrCopied = $false; securityPromptsAutomated = $false;
    acceptanceDecisionsAdded = 0;
    frozenHelperAcceptanceCountMeaning = 'Historical runtime operation approval binding; not a new current owner decision.';
    requiredPrivateAction = 'Human runs the exact approved r5 a2 launcher as administrator, enters the new Windows password in its hidden prompts, initializes only the new profile by private Windows sign-in, and privately completes Connected-app sign-in/MFA.';
    preservation = 'Do not control the other chat Preview window, close its process, read or copy its stores, reset accounts, or rerun a partial provision.'
}
$taskReportPath = Join-Path $taskEvidenceDirectory ('native-prerequisites-' + [DateTimeOffset]::UtcNow.ToString('yyyyMMddTHHmmssfffZ') + '.json')
$taskBytes = [Text.UTF8Encoding]::new($false).GetBytes(($taskReport | ConvertTo-Json -Depth 12) + [Environment]::NewLine)
$taskStream = [IO.FileStream]::new($taskReportPath, [IO.FileMode]::CreateNew, [IO.FileAccess]::Write, [IO.FileShare]::None)
try { $taskStream.Write($taskBytes, 0, $taskBytes.Length); $taskStream.Flush($true) }
finally { $taskStream.Dispose() }
[pscustomobject]@{
    evidencePath = $taskReportPath; prerequisiteValidationPassed = $taskValidation.passed;
    sourceInputsVerified = $taskValidation.sourceInputsVerified;
    connectedReleaseFilesVerified = $taskValidation.connectedReleaseFilesVerified;
    targetAccountExists = $taskValidation.targetAccountExists;
    targetPackageExists = $taskValidation.targetPackageExists;
    currentTokenAdministrator = $taskValidation.currentTokenAdministrator;
    authenticatedNative = 'unverified'; nativeActionsExecuted = 0
} | ConvertTo-Json -Compress
