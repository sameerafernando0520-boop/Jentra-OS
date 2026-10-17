# Source template only. Its unresolved SHA markers prevent private execution.
param(
    [ValidateSet('Renewal','Health','Scheduler')][string]$Target = 'Health',
    [ValidateSet('Validate','Execute')][string]$Action = 'Validate',
    [Parameter(Mandatory=$true)][ValidatePattern('^[a-f0-9]{64}$')][string]$FinalReviewSha256
)
$ErrorActionPreference = 'Stop'
$taskRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..'))
$taskProject = 'xpdoufauvrbdmxgngetv'
$taskBundle = 'db525758554036fa99ec02d00c85bd8401ef7ebce787e2a983db1c69a08baf7b'
$taskMetadataPath = 'docs/verification/wave5/private-owner-input-ready-20261014-r5-a10.json'
$taskLaunchers = @{
    Renewal = @{
        source='tools/wave5/renew_runtime_authority_20261015_r5_a1.mjs'
        sha256='b3d8d2dda66e0945b1451d2d5f57d4daefbdf00cb2799d59543220a7d952956d'
        plan='docs/verification/wave5/root-runtime-renewal-20261015/execution-plan-a1.json'
        review='docs/verification/wave5/root-runtime-renewal-20261015/final-operation-review-a1.json'
    }
    Health = @{
        source='tools/wave5/run_worker_v7_health_20261015_r5.mjs'
        sha256='86d881ed3587b6bde28fb8e8ad33c9526d50b6ebc305fb1ff432f44bf4edbd75'
        plan='docs/verification/wave5/task3-health-readiness-20261014/execution-plan-20261015-a1.json'
        review='docs/verification/wave5/task3-health-readiness-20261014/final-operation-review-20261015-a1.json'
    }
    Scheduler = @{
        source='tools/wave5/resume_worker_schedules_20261015_r5_a1.mjs'
        sha256='2b823d111990d2f93f1dcefe62d2bc48c2498a40b333311e4894738928a8604f'
        plan='docs/verification/wave5/task3-schedule-resume-20261014/renewed-execution-plan-20261015-r5-a1.json'
        review='docs/verification/wave5/task3-schedule-resume-20261014/final-operation-review-20261015-r5-a1.json'
    }
}
$taskSecret = $null
$taskBstr = [IntPtr]::Zero
$taskPlain = $null
$taskChild = $null
$taskPhase = 'public-source-validation'
function Assert-TaskFile([string]$Relative, [string]$Sha256) {
    if ($Sha256 -cnotmatch '^[a-f0-9]{64}$' -or $Relative -notmatch '^[a-zA-Z0-9_./-]+$' -or $Relative.Contains('..')) { throw 'EXACT_PUBLIC_SOURCE_BINDING_REQUIRED' }
    $taskAbsolute = [IO.Path]::GetFullPath((Join-Path $taskRoot $Relative))
    if (-not $taskAbsolute.StartsWith($taskRoot.TrimEnd('\') + '\',[StringComparison]::OrdinalIgnoreCase)) { throw 'PUBLIC_PATH_OUTSIDE_WORKSPACE' }
    $taskItem = Get-Item -LiteralPath $taskAbsolute
    if (($taskItem.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0 -or $taskItem.PSIsContainer -or $taskItem.Length -gt 2097152) { throw 'BOUNDED_PUBLIC_SOURCE_FILE_REQUIRED' }
    if ((Get-FileHash -LiteralPath $taskAbsolute -Algorithm SHA256).Hash.ToLowerInvariant() -cne $Sha256) { throw 'PUBLIC_SOURCE_HASH_CHANGED' }
    return $taskAbsolute
}
function Convert-TaskUtc([object]$Value) {
    if ($Value -isnot [string] -or $Value -cnotmatch '^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(\.\d{1,6})?(Z|\+00:00)$') { throw 'EXPLICIT_UTC_TIMESTAMP_REQUIRED' }
    return [DateTimeOffset]::Parse($Value,[Globalization.CultureInfo]::InvariantCulture)
}
function Assert-TaskPrivateAcl([string]$File, [Security.Principal.SecurityIdentifier]$Sid, [bool]$Folder) {
    $taskItem = Get-Item -LiteralPath $File
    if (($taskItem.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0 -or $taskItem.PSIsContainer -ne $Folder) { throw 'PRIVATE_PATH_TYPE_OR_REDIRECTION_INVALID' }
    $taskAcl = Get-Acl -LiteralPath $File
    $taskRules = @($taskAcl.GetAccessRules($true,$true,[Security.Principal.SecurityIdentifier]))
    if ($taskRules.Count -ne 1 -or $taskRules[0].IdentityReference.Value -ne $Sid.Value -or
        $taskRules[0].AccessControlType -ne 'Allow' -or $taskRules[0].FileSystemRights -ne [Security.AccessControl.FileSystemRights]::FullControl -or
        ($Folder -and -not $taskAcl.AreAccessRulesProtected)) { throw 'PRIVATE_CURRENT_SID_ACL_REQUIRED' }
}
function New-TaskProcess([string]$Flag) {
    $taskInfo = [Diagnostics.ProcessStartInfo]::new()
    $taskInfo.FileName = $taskNode
    [void]$taskInfo.ArgumentList.Add($taskInstaller)
    [void]$taskInfo.ArgumentList.Add($Flag)
    [void]$taskInfo.ArgumentList.Add($FinalReviewSha256)
    $taskInfo.WorkingDirectory = $taskRoot
    $taskInfo.UseShellExecute = $false
    $taskInfo.CreateNoWindow = $true
    $taskInfo.RedirectStandardInput = $true
    $taskInfo.RedirectStandardOutput = $true
    $taskInfo.RedirectStandardError = $true
    [void]$taskInfo.EnvironmentVariables.Remove('SUPABASE_ACCESS_TOKEN')
    $taskProcess = [Diagnostics.Process]::new()
    $taskProcess.StartInfo = $taskInfo
    return $taskProcess
}
# Embedded verbatim in the reviewed adapters. These functions read public files only.
$taskPublicHolds = [Collections.Generic.List[IO.FileStream]]::new()
$taskPublicHeldPaths = [Collections.Generic.Dictionary[string,string]]::new([StringComparer]::OrdinalIgnoreCase)
function Add-TaskReviewedReadHold([string]$Base, [string]$Relative, [string]$ExpectedSha256) {
    if ($ExpectedSha256 -cnotmatch '^[a-f0-9]{64}$' -or $Relative -cnotmatch '^[a-zA-Z0-9_./-]+$' -or
        $Relative.StartsWith('/') -or @($Relative.Split('/') | Where-Object { $_ -eq '..' -or $_ -eq '.' -or $_ -eq '' }).Count -ne 0) {
        throw 'EXACT_REVIEWED_PUBLIC_FILE_REQUIRED'
    }
    $taskBasePath = [IO.Path]::GetFullPath($Base).TrimEnd('\')
    $taskAbsolutePath = [IO.Path]::GetFullPath((Join-Path $taskBasePath $Relative))
    if (-not $taskAbsolutePath.StartsWith($taskBasePath + '\',[StringComparison]::OrdinalIgnoreCase)) { throw 'REVIEWED_FILE_OUTSIDE_BOUND_ROOT' }
    $taskCursor = $taskBasePath
    $taskBaseItem = Get-Item -LiteralPath $taskCursor -Force
    if (-not $taskBaseItem.PSIsContainer -or ($taskBaseItem.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { throw 'REVIEWED_ROOT_REDIRECTION_FORBIDDEN' }
    $taskParts = $Relative.Split('/')
    for ($taskIndex = 0; $taskIndex -lt $taskParts.Length; $taskIndex++) {
        $taskCursor = Join-Path $taskCursor $taskParts[$taskIndex]
        $taskItem = Get-Item -LiteralPath $taskCursor -Force
        if (($taskItem.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0 -or
            ($taskIndex -lt $taskParts.Length - 1 -and -not $taskItem.PSIsContainer)) { throw 'REVIEWED_FILE_REDIRECTION_FORBIDDEN' }
    }
    if ($taskItem.PSIsContainer -or $taskItem.Length -gt 2097152) { throw 'BOUNDED_REVIEWED_PUBLIC_FILE_REQUIRED' }
    if ($taskPublicHeldPaths.ContainsKey($taskAbsolutePath)) {
        if ($taskPublicHeldPaths[$taskAbsolutePath] -cne $ExpectedSha256) { throw 'REVIEWED_FILE_HASH_COLLISION' }
        return
    }
    $taskReadHandle = $null
    try {
        $taskReadHandle = [IO.File]::Open($taskAbsolutePath,[IO.FileMode]::Open,[IO.FileAccess]::Read,[IO.FileShare]::Read)
        if ($taskReadHandle.Length -gt 2097152) { throw 'BOUNDED_REVIEWED_PUBLIC_FILE_REQUIRED' }
        $taskHasher = [Security.Cryptography.SHA256]::Create()
        try { $taskHeldHash = [Convert]::ToHexString($taskHasher.ComputeHash($taskReadHandle)).ToLowerInvariant() }
        finally { $taskHasher.Dispose() }
        if ($taskHeldHash -cne $ExpectedSha256) { throw 'REVIEWED_FILE_HASH_CHANGED' }
        $taskReadHandle.Position = 0
        $taskPublicHolds.Add($taskReadHandle)
        $taskPublicHeldPaths.Add($taskAbsolutePath,$ExpectedSha256)
        $taskReadHandle = $null
    } finally { if ($null -ne $taskReadHandle) { $taskReadHandle.Dispose() } }
}
function Close-TaskReviewedReadHolds {
    foreach ($taskHeldFile in $taskPublicHolds) { $taskHeldFile.Dispose() }
    $taskPublicHolds.Clear()
    $taskPublicHeldPaths.Clear()
}

try {
    $taskSelected = $taskLaunchers[$Target]
    $taskInstaller = Assert-TaskFile $taskSelected.source $taskSelected.sha256
    $taskReviewFile = Assert-TaskFile $taskSelected.review $FinalReviewSha256
    Add-TaskReviewedReadHold $taskRoot $taskSelected.review $FinalReviewSha256
    $taskReview = Get-Content -Raw -LiteralPath $taskReviewFile | ConvertFrom-Json -DateKind String
    if ($taskReview.privateAdapter.path -cne 'scripts/wave5/run_private_health_scheduler_20261015_r5_a1.ps1' -or
        $taskReview.privateAdapter.afterSha256 -cne (Get-FileHash -LiteralPath $PSCommandPath -Algorithm SHA256).Hash.ToLowerInvariant() -or
        $taskReview.generatedPlan.path -cne $taskSelected.plan) { throw 'EXACT_REVIEWED_ADAPTER_AND_PLAN_REQUIRED' }
    Add-TaskReviewedReadHold $taskRoot $taskSelected.plan $taskReview.generatedPlan.sha256
    $taskPlanFile = Assert-TaskFile $taskSelected.plan $taskReview.generatedPlan.sha256
    $taskPlan = Get-Content -Raw -LiteralPath $taskPlanFile | ConvertFrom-Json -DateKind String
    if ($taskPlan.controlBindings.metadata.path -cne $taskMetadataPath) { throw 'EXACT_A10_METADATA_BINDING_REQUIRED' }
    $taskReadyFile = Assert-TaskFile $taskMetadataPath $taskPlan.controlBindings.metadata.sha256
    if (@($taskPlan.sourceBindings).Count -lt 1 -or @($taskPlan.publicBindings).Count -lt 1) { throw 'EXPLICIT_REVIEWED_MANAGEMENT_FILE_INVENTORY_REQUIRED' }
    foreach ($taskBinding in @($taskPlan.sourceBindings) + @($taskPlan.publicBindings)) {
        Add-TaskReviewedReadHold $taskRoot $taskBinding.path $taskBinding.sha256
    }
    Add-TaskReviewedReadHold $taskRoot $taskSelected.source $taskSelected.sha256
    Add-TaskReviewedReadHold $taskRoot $taskSelected.plan $taskReview.generatedPlan.sha256
    Add-TaskReviewedReadHold $taskRoot $taskSelected.review $FinalReviewSha256
    Add-TaskReviewedReadHold $taskRoot $taskMetadataPath $taskPlan.controlBindings.metadata.sha256
    $taskSelfRelative = [IO.Path]::GetRelativePath($taskRoot,$PSCommandPath).Replace('\','/')
    Add-TaskReviewedReadHold $taskRoot $taskSelfRelative $taskReview.privateAdapter.afterSha256
    $taskNode = (Get-Command node -CommandType Application -ErrorAction Stop | Select-Object -First 1).Source
    $taskPhase = 'public-preflight'
    $taskChild = New-TaskProcess '--preflight'
    if (-not $taskChild.Start()) { throw 'PUBLIC_PREFLIGHT_START_FAILED' }
    $taskChild.StandardInput.Close()
    $taskOut = $taskChild.StandardOutput.ReadToEndAsync()
    $taskErr = $taskChild.StandardError.ReadToEndAsync()
    if (-not $taskChild.WaitForExit(60000)) { $taskChild.Kill($true); throw 'PUBLIC_PREFLIGHT_TIMEOUT' }
    $taskOutput = $taskOut.GetAwaiter().GetResult()
    $taskError = $taskErr.GetAwaiter().GetResult()
    if ($taskChild.ExitCode -ne 0 -or $taskOutput.Length -gt 16000 -or $taskError.Trim().Length -ne 0) { throw 'PUBLIC_PREFLIGHT_FAILED' }
    $taskProof = $taskOutput | ConvertFrom-Json -DateKind String
    if ($taskProof.passed -ne $true -or $taskProof.privateInputsRead -ne $false -or $taskProof.networkCalls -ne 0 -or
        $taskProof.planSha256 -cne $taskReview.generatedPlan.sha256 -or $taskProof.finalReviewSha256 -cne $FinalReviewSha256) { throw 'EXACT_PUBLIC_PREFLIGHT_PROOF_REQUIRED' }
    $taskChild.Dispose(); $taskChild = $null; $taskOutput = $null; $taskError = $null
    if ($Action -eq 'Validate') {
        @{passed=$true;target=$Target;networkCalls=0;privateInputsRead=$false;planSha256=$taskProof.planSha256;finalReviewSha256=$FinalReviewSha256} | ConvertTo-Json -Compress
        exit 0
    }
    $taskPhase = 'private-metadata-validation'
    $taskNow = [DateTimeOffset]::UtcNow
    $taskStart = Convert-TaskUtc $taskPlan.window.notBefore
    $taskEnd = Convert-TaskUtc $taskPlan.window.expiresAt
    if ($taskStart -gt $taskNow -or $taskEnd -le $taskNow.AddSeconds(90) -or ($taskEnd - $taskStart).TotalMinutes -gt 120) { throw 'CURRENT_APPROVED_WINDOW_REQUIRED' }
    $taskMetadataText = Get-Content -Raw -LiteralPath $taskReadyFile
    $taskMetadata = $taskMetadataText | ConvertFrom-Json -DateKind String
    $taskSid = [Security.Principal.WindowsIdentity]::GetCurrent().User
    $taskCreated = Convert-TaskUtc $taskMetadata.createdAt
    $taskExpires = Convert-TaskUtc $taskMetadata.expiresAt
    if ($taskMetadata.kind -cne 'wave5-private-owner-input-metadata' -or $taskMetadata.projectId -cne $taskProject -or
        $taskMetadata.runtimeBundleSha256 -cne $taskBundle -or $taskMetadata.ownerSid -cne $taskSid.Value -or
        $taskMetadata.helperSha256 -cne 'a3fe771a022dac5ba3a81a33591e7017fb6f446a2e813affd09fc6e40738d07a' -or $taskMetadata.metadataFilename -cne 'metadata-renewed-a10.json' -or
        $taskMetadata.containsPlaintextCredential -ne $false -or $taskCreated -gt $taskNow -or $taskExpires -lt $taskEnd -or
        $taskExpires -le $taskNow -or ($taskExpires - $taskCreated).TotalMinutes -gt 120 -or $taskExpires -le $taskCreated) { throw 'EXACT_FRESH_PRIVATE_INPUT_REQUIRED' }
    $taskFolder = [IO.Path]::GetFullPath($taskMetadata.privateFolder)
    $taskTemp = [IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\') + '\'
    if (-not $taskFolder.StartsWith($taskTemp,[StringComparison]::OrdinalIgnoreCase) -or
        [IO.Path]::GetFileName($taskFolder) -cnotmatch '^JentraOS-Wave5-owner-[a-f0-9]{32}$') { throw 'EXACT_PRIVATE_TEMP_FOLDER_REQUIRED' }
    $taskSealed = Join-Path $taskFolder 'owner-pat.dpapi'
    $taskPrivateMetadata = Join-Path $taskFolder 'metadata-renewed-a10.json'
    if ([IO.Path]::GetFullPath($taskMetadata.sealedTokenPath) -cne $taskSealed) { throw 'EXACT_PRIVATE_TOKEN_PATH_REQUIRED' }
    Assert-TaskPrivateAcl $taskFolder $taskSid $true
    Assert-TaskPrivateAcl $taskSealed $taskSid $false
    Assert-TaskPrivateAcl $taskPrivateMetadata $taskSid $false
    if ((Get-Content -Raw -LiteralPath $taskPrivateMetadata) -cne $taskMetadataText) { throw 'PRIVATE_METADATA_CHANGED' }
    $null = Assert-TaskFile $taskMetadataPath $taskPlan.controlBindings.metadata.sha256
    $null = Assert-TaskFile $taskSelected.source $taskSelected.sha256
    $null = Assert-TaskFile $taskSelected.review $FinalReviewSha256
    $null = Assert-TaskFile $taskSelected.plan $taskReview.generatedPlan.sha256
    if ([DateTimeOffset]::UtcNow.AddSeconds(90) -ge $taskEnd) { throw 'PRIVATE_HANDOFF_WINDOW_EXPIRED' }
    $taskPhase = 'private-handoff'
    $taskSecret = ConvertTo-SecureString -String (Get-Content -Raw -LiteralPath $taskSealed)
    $taskBstr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($taskSecret)
    $taskPlain = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($taskBstr)
    if ($taskPlain.Length -lt 9 -or $taskPlain.Length -gt 2048 -or $taskPlain -match '\s') { throw 'PRIVATE_INPUT_INVALID' }
    $taskPlain = @{projectId=$taskProject;bundleSha256=$taskBundle;ownerToken=$taskPlain} | ConvertTo-Json -Compress
    $taskChild = New-TaskProcess '--execute'
    if (-not $taskChild.Start()) { throw 'PRIVATE_CHILD_START_FAILED' }
    $taskOut = $taskChild.StandardOutput.ReadToEndAsync()
    $taskErr = $taskChild.StandardError.ReadToEndAsync()
    $taskChild.StandardInput.WriteLine($taskPlain)
    $taskChild.StandardInput.Close()
    $taskPlain = $null
    [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($taskBstr); $taskBstr = [IntPtr]::Zero
    $taskSecret.Dispose(); $taskSecret = $null
    $taskWaitMs = [Math]::Min(900000,[Math]::Max(1,($taskEnd - [DateTimeOffset]::UtcNow).TotalMilliseconds))
    if (-not $taskChild.WaitForExit([int]$taskWaitMs)) { $taskChild.Kill($true); throw 'PRIVATE_CHILD_DEADLINE_REACHED' }
    $taskOutput = $taskOut.GetAwaiter().GetResult()
    $taskError = $taskErr.GetAwaiter().GetResult()
    if ($taskOutput.Length -gt 65536 -or $taskError.Length -gt 16000) { throw 'BOUNDED_PUBLIC_CHILD_OUTPUT_REQUIRED' }
    $taskResult = if ($taskChild.ExitCode -eq 0) { $taskOutput | ConvertFrom-Json -DateKind String } else { $taskError | ConvertFrom-Json -DateKind String }
    if ($taskChild.ExitCode -eq 0 -and $taskResult.passed -ne $true) { throw 'EXACT_SUCCESSFUL_PUBLIC_RESULT_REQUIRED' }
    if ($taskChild.ExitCode -eq 0 -and $taskResult.passed -eq $true) {
        @{passed=$true;target=$Target;childExitCode=0;privateValuesPrinted=$false;finalReviewSha256=$FinalReviewSha256} | ConvertTo-Json -Compress
    } else {
        $taskCode = if ($taskResult.failureCode -cmatch '^[A-Z][A-Z0-9_]{3,100}$') { $taskResult.failureCode } else { 'MANAGEMENT_CONTROL_STOPPED' }
        @{passed=$false;target=$Target;failureCode=$taskCode;privateValuesPrinted=$false;automaticRetryPerformed=$false} | ConvertTo-Json -Compress
    }
    exit $taskChild.ExitCode
} catch {
    $taskCode = if ($_.Exception.Message -cmatch '^[A-Z][A-Z0-9_]{3,100}$') { $_.Exception.Message } else { 'PRIVATE_MANAGEMENT_HANDOFF_FAILED' }
    @{passed=$false;target=$Target;phase=$taskPhase;failureCode=$taskCode;privateValuesPrinted=$false;automaticRetryPerformed=$false} | ConvertTo-Json -Compress
    exit 1
} finally {
    $taskPlain = $null; $taskOutput = $null; $taskError = $null
    if ($taskBstr -ne [IntPtr]::Zero) { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($taskBstr) }
    if ($null -ne $taskSecret) { $taskSecret.Dispose() }
    try {
        if ($null -ne $taskChild) {
            try {
                if (-not $taskChild.HasExited) {
                    $taskChild.Kill($true)
                    if (-not $taskChild.WaitForExit(10000)) { throw 'MANAGEMENT_CHILD_DID_NOT_EXIT' }
                }
            } finally { $taskChild.Dispose() }
        }
    } finally { Close-TaskReviewedReadHolds }
}
