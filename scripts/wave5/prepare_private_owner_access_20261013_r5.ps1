param([switch]$ValidateOnly)

# Local human input only. This helper does not connect, install SQL, or change
# the existing CLI token, Supabase connection, Auth configuration or sessions.
$ErrorActionPreference = 'Stop'
$taskRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..'))
$taskProject = 'xpdoufauvrbdmxgngetv'
$taskBundle = 'db525758554036fa99ec02d00c85bd8401ef7ebce787e2a983db1c69a08baf7b'
$taskReviewFile = Join-Path $taskRoot 'docs/verification/wave5/complete-app-runtime-review-20261010-r5.json'
$taskOwnerFile = Join-Path $taskRoot 'docs/verification/wave5/runtime-owner-decision-20261012-r5.json'
$taskReadyFile = Join-Path $taskRoot 'docs/verification/wave5/private-owner-input-ready-20261013-r5.json'
$taskSecureToken = $null

function Write-TaskNewFile([string]$TaskPath, [string]$TaskText) {
    $taskBytes = [Text.UTF8Encoding]::new($false).GetBytes($TaskText)
    $taskStream = [IO.FileStream]::new($TaskPath, [IO.FileMode]::CreateNew,
        [IO.FileAccess]::Write, [IO.FileShare]::None, 4096, [IO.FileOptions]::WriteThrough)
    try { $taskStream.Write($taskBytes, 0, $taskBytes.Length); $taskStream.Flush($true) }
    finally { $taskStream.Dispose() }
}

try {
    if ($env:OS -ne 'Windows_NT') { throw 'WINDOWS_REQUIRED' }
    if ((Get-FileHash -LiteralPath $taskReviewFile -Algorithm SHA256).Hash.ToLowerInvariant() -ne
        'b1b0cb94a8aa705b5cc6ff674ed215a8487a960ff0a594f7abffadfbc4e57cc3') { throw 'REVIEW_CHANGED' }
    if ((Get-FileHash -LiteralPath $taskOwnerFile -Algorithm SHA256).Hash.ToLowerInvariant() -ne
        '90daa67a459bd985a1bec824bf0e8e09bf69537c2febdae85238336604c655ab') { throw 'OWNER_DECISION_CHANGED' }
    $taskReview = Get-Content -Raw -LiteralPath $taskReviewFile | ConvertFrom-Json
    $taskOwner = Get-Content -Raw -LiteralPath $taskOwnerFile | ConvertFrom-Json
    if ($taskReview.projectId -ne $taskProject -or $taskReview.bundleSha256 -ne $taskBundle -or
        $taskOwner.decision -ne 'approve' -or $taskOwner.projectId -ne $taskProject) { throw 'EXACT_APPROVAL_REQUIRED' }
    $taskSid = [Security.Principal.WindowsIdentity]::GetCurrent().User
    if ($ValidateOnly) {
        @{ kind='wave5-private-owner-input-helper-validation'; passed=$true;
            projectId=$taskProject; actualInputRead=$false; secretFilesCreated=0;
            networkCalls=0; databaseWrites=0; authWrites=0; production=$false } | ConvertTo-Json -Compress
        exit 0
    }
    if (Test-Path -LiteralPath $taskReadyFile) { throw 'EXISTING_PRIVATE_INPUT_METADATA_PRESERVED' }
    Write-Host 'Jentra OS approved isolated runtime setup'
    Write-Host ('Project: ' + $taskProject)
    Write-Host 'Enter a valid Supabase owner personal access token in the hidden prompt.'
    Write-Host 'Keep the token out of chat. This stores only Windows-encrypted input in a private temporary folder.'
    Write-Host 'The developer will validate access before any approved operation. This helper makes no network request.'
    $taskSecureToken = Read-Host 'Supabase access token (hidden)' -AsSecureString
    if ($taskSecureToken.Length -lt 9) { throw 'PRIVATE_INPUT_REQUIRED' }
    $taskPrivateFolder = Join-Path ([IO.Path]::GetTempPath()) ('JentraOS-Wave5-owner-' + [Guid]::NewGuid().ToString('N'))
    if (Test-Path -LiteralPath $taskPrivateFolder) { throw 'NEW_PRIVATE_FOLDER_REQUIRED' }
    [void][IO.Directory]::CreateDirectory($taskPrivateFolder)
    $taskAcl = [Security.AccessControl.DirectorySecurity]::new()
    $taskAcl.SetOwner($taskSid)
    $taskAcl.SetAccessRuleProtection($true, $false)
    $taskRule = [Security.AccessControl.FileSystemAccessRule]::new($taskSid,
        [Security.AccessControl.FileSystemRights]::FullControl,
        [Security.AccessControl.InheritanceFlags]'ContainerInherit, ObjectInherit',
        [Security.AccessControl.PropagationFlags]::None, [Security.AccessControl.AccessControlType]::Allow)
    [void]$taskAcl.AddAccessRule($taskRule)
    Set-Acl -LiteralPath $taskPrivateFolder -AclObject $taskAcl
    $taskFolderInfo = Get-Item -LiteralPath $taskPrivateFolder
    if (($taskFolderInfo.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { throw 'PRIVATE_REPARSE_POINT_FORBIDDEN' }
    $taskActualAcl = Get-Acl -LiteralPath $taskPrivateFolder
    $taskActualRules = @($taskActualAcl.GetAccessRules($true,$true,[Security.Principal.SecurityIdentifier]))
    if (-not $taskActualAcl.AreAccessRulesProtected -or $taskActualRules.Count -ne 1 -or
        $taskActualRules[0].IdentityReference.Value -ne $taskSid.Value -or
        $taskActualRules[0].AccessControlType -ne 'Allow') { throw 'PRIVATE_ACL_REQUIRED' }
    $taskSealedPath = Join-Path $taskPrivateFolder 'owner-pat.dpapi'
    $taskSealed = ConvertFrom-SecureString -SecureString $taskSecureToken
    Write-TaskNewFile $taskSealedPath $taskSealed
    $taskNow = [DateTimeOffset]::UtcNow
    $taskMetadata = [ordered]@{
        kind='wave5-private-owner-input-metadata'; projectId=$taskProject;
        runtimeBundleSha256=$taskBundle; ownerSid=$taskSid.Value;
        createdAt=$taskNow.ToString('o'); expiresAt=$taskNow.AddHours(2).ToString('o');
        purpose='Exact already-approved isolated test setup; no production or real billing';
        storage='Windows CurrentUser DPAPI; current SID only protected ACL';
        privateFolder=$taskPrivateFolder; sealedTokenPath=$taskSealedPath;
        helperSha256=(Get-FileHash -LiteralPath $PSCommandPath -Algorithm SHA256).Hash.ToLowerInvariant();
        containsPlaintextCredential=$false; networkCalls=0; databaseWrites=0; authWrites=0
    }
    $taskMetadataText = ($taskMetadata | ConvertTo-Json) + [Environment]::NewLine
    Write-TaskNewFile (Join-Path $taskPrivateFolder 'metadata.json') $taskMetadataText
    Write-TaskNewFile $taskReadyFile $taskMetadataText
    Write-Host 'Private input saved. Reply ready in chat; do not send the token.'
} catch {
    Write-Error 'Private owner input was not completed. Existing credentials and sessions were preserved.' -ErrorAction Continue
    exit 1
} finally {
    if ($null -ne $taskSecureToken) { $taskSecureToken.Dispose() }
    $taskSealed = $null
}
