param([switch]$ValidateOnly)
$ErrorActionPreference='Stop'
$taskRoot=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..'))
$taskReady=Join-Path $taskRoot 'docs/verification/wave5/private-owner-input-ready-20261013-r5.json'
$taskOutput=Join-Path $taskRoot 'docs/verification/wave5/private-runtime-input-ready-20261013-r5.json'
$taskSecret=$null
function Write-TaskCipher([string]$TaskFile,[Security.SecureString]$TaskValue) {
    $taskCipher=ConvertFrom-SecureString -SecureString $TaskValue
    $taskBytes=[Text.Encoding]::UTF8.GetBytes($taskCipher)
    $taskStream=[IO.File]::Open($TaskFile,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::None)
    try { $taskStream.Write($taskBytes,0,$taskBytes.Length);$taskStream.Flush($true) }
    finally { $taskStream.Dispose();$taskCipher=$null;[Array]::Clear($taskBytes,0,$taskBytes.Length) }
}
try {
    $taskMetadata=Get-Content -Raw -LiteralPath $taskReady | ConvertFrom-Json
    $taskSid=[Security.Principal.WindowsIdentity]::GetCurrent().User
    if ($taskMetadata.projectId -ne 'xpdoufauvrbdmxgngetv' -or
        $taskMetadata.runtimeBundleSha256 -ne 'db525758554036fa99ec02d00c85bd8401ef7ebce787e2a983db1c69a08baf7b' -or
        $taskMetadata.ownerSid -ne $taskSid.Value) { throw 'EXACT_PRIVATE_RUNTIME_TARGET_REQUIRED' }
    if ($ValidateOnly) {
        @{passed=$true;hiddenPrompts=2;networkCalls=0;databaseWrites=0;secretsPrinted=$false;ownerTokenRequested=$false} | ConvertTo-Json -Compress
        exit 0
    }
    if (Test-Path -LiteralPath $taskOutput) { throw 'PRIVATE_RUNTIME_INPUT_ALREADY_RECORDED' }
    $taskFolder=[IO.Path]::GetFullPath($taskMetadata.privateFolder)
    $taskTemp=[IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\')+'\'
    if (-not $taskFolder.StartsWith($taskTemp,[StringComparison]::OrdinalIgnoreCase) -or
        [IO.Path]::GetFileName($taskFolder) -notmatch '^JentraOS-Wave5-owner-[a-f0-9]{32}$' -or
        ((Get-Item -LiteralPath $taskFolder).Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { throw 'EXACT_PRIVATE_FOLDER_REQUIRED' }
    $taskAcl=Get-Acl -LiteralPath $taskFolder
    $taskRules=@($taskAcl.GetAccessRules($true,$true,[Security.Principal.SecurityIdentifier]))
    if (-not $taskAcl.AreAccessRulesProtected -or $taskRules.Count -ne 1 -or
        $taskRules[0].IdentityReference.Value -ne $taskSid.Value -or $taskRules[0].AccessControlType -ne 'Allow' -or
        $taskRules[0].FileSystemRights -ne [Security.AccessControl.FileSystemRights]::FullControl) { throw 'PRIVATE_CURRENT_SID_ACL_REQUIRED' }
    $host.UI.RawUI.WindowTitle='Jentra OS Private Runtime Inputs'
    Write-Host 'Approved isolated Jentra OS test setup - xpdoufauvrbdmxgngetv'
    Write-Host 'No Supabase owner token is needed here. Keep every value out of chat.'
    Write-Host 'Enter an existing DATABASE password, not the desktop account password.'
    Write-Host 'Leave a prompt blank to skip it. This helper makes no network calls.'
    $taskDatabasePresent=$false;$taskModelPresent=$false
    $taskSecret=Read-Host 'Existing Supabase database password (hidden; Enter to skip)' -AsSecureString
    if ($taskSecret.Length -gt 0) { Write-TaskCipher (Join-Path $taskFolder 'database-password.dpapi') $taskSecret;$taskDatabasePresent=$true }
    $taskSecret.Dispose();$taskSecret=$null
    $taskSecret=Read-Host 'OpenAI API key for at most four approved test calls (hidden; Enter to skip)' -AsSecureString
    if ($taskSecret.Length -gt 0) { Write-TaskCipher (Join-Path $taskFolder 'openai-key.dpapi') $taskSecret;$taskModelPresent=$true }
    $taskSecret.Dispose();$taskSecret=$null
    $taskNow=[DateTimeOffset]::UtcNow
    $taskPublic=[ordered]@{kind='wave5-private-runtime-input-metadata';projectId=$taskMetadata.projectId;
        bundleSha256=$taskMetadata.runtimeBundleSha256;ownerSid=$taskSid.Value;privateFolder=$taskFolder;
        createdAt=$taskNow.ToString('o');expiresAt=$taskNow.AddHours(24).ToString('o');
        databasePasswordProvided=$taskDatabasePresent;modelKeyProvided=$taskModelPresent;
        credentialValuesPrinted=$false;plaintextFilesCreated=$false;networkCalls=0;databaseWrites=0;
        settingsChanged=$false;production=$false;realBilling=$false;
        helperSha256=(Get-FileHash -LiteralPath $PSCommandPath -Algorithm SHA256).Hash.ToLowerInvariant()}
    $taskText=($taskPublic|ConvertTo-Json)+[Environment]::NewLine
    $taskBytes=[Text.Encoding]::UTF8.GetBytes($taskText)
    $taskStream=[IO.File]::Open($taskOutput,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::None)
    try {$taskStream.Write($taskBytes,0,$taskBytes.Length);$taskStream.Flush($true)}finally{$taskStream.Dispose()}
    Write-Host 'Private inputs saved. Return to the chat and reply ready.'
    Read-Host 'Press Enter to close' | Out-Null
} catch {
    @{failureCode='PRIVATE_RUNTIME_INPUT_SETUP_FAILED';exceptionType=$_.Exception.GetType().FullName;
        secretsPrinted=$false;networkCalls=0;databaseWrites=0} | ConvertTo-Json -Compress
    exit 1
} finally { if ($null -ne $taskSecret) {$taskSecret.Dispose()} }
