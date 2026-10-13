param(
    [ValidateSet('Validate', 'Provision')][string]$Mode = 'Validate',
    [string]$ReviewPath,
    [string]$ApprovalPath,
    [string]$VerifiedBuildManifestPath
)

# Compatibility successor for the exact already-approved r5 native target.
# Default validation is read-only. Provision must be run by the human in an
# elevated PowerShell process. Passwords are prompted privately and never saved.
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$taskWorkspace = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..')).TrimEnd('\')
$taskAccountName = 'jentra-w5-runtime'
$taskPackageDirectory = 'C:\Users\Public\Documents\JentraWave5Runtime\20261009'
$taskApprovedSourceWorkspace = Join-Path $taskWorkspace 'build/wave5-approved-execution-20261013-r5-a2'
$taskProject = 'xpdoufauvrbdmxgngetv'
$taskBundle = 'db525758554036fa99ec02d00c85bd8401ef7ebce787e2a983db1c69a08baf7b'
$taskReviewRelative = 'docs/verification/wave5/complete-app-runtime-review-20261010-r5.json'
$taskApprovalRelative = 'docs/verification/wave5/runtime-owner-decision-20261012-r5.json'
$taskBuildRelative = 'docs/verification/wave5/windows-test-connected-package-20261010-r5.json'
$taskFailureCode = 'NATIVE_VALIDATION_NOT_COMPLETED'
$taskPassword = $null
$taskPasswordConfirmation = $null
$taskAccountCreated = $false
$taskPackageCreated = $false
$taskCopiedFileCount = 0
$taskJournalPath = $null
$taskStarted = [DateTimeOffset]::UtcNow.ToString('o')

function Require-Task([bool]$Condition, [string]$Code) {
    if (-not $Condition) {
        $script:taskFailureCode = $Code
        throw $Code
    }
}

function Get-TaskHash([string]$Path) {
    (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
}

function Resolve-TaskRelative([string]$Root, [string]$Relative) {
    Require-Task (-not [string]::IsNullOrWhiteSpace($Relative)) 'RELATIVE_PATH_REQUIRED'
    Require-Task (-not [IO.Path]::IsPathRooted($Relative)) 'ROOTED_RELATIVE_PATH_FORBIDDEN'
    Require-Task (-not $Relative.Contains(':')) 'ALTERNATE_STREAM_PATH_FORBIDDEN'
    $taskResolvedRoot = [IO.Path]::GetFullPath($Root).TrimEnd('\') + '\'
    $taskResolved = [IO.Path]::GetFullPath((Join-Path $taskResolvedRoot ($Relative.Replace('/', '\'))))
    Require-Task ($taskResolved.StartsWith($taskResolvedRoot, [StringComparison]::OrdinalIgnoreCase)) 'PATH_OUTSIDE_EXACT_ROOT'
    return $taskResolved
}

function Assert-TaskNoReparse([string]$Path) {
    $taskCheckPath = [IO.Path]::GetFullPath($Path)
    while (-not [string]::IsNullOrEmpty($taskCheckPath)) {
        if (Test-Path -LiteralPath $taskCheckPath) {
            $taskCheckItem = Get-Item -LiteralPath $taskCheckPath -Force
            Require-Task (($taskCheckItem.Attributes -band [IO.FileAttributes]::ReparsePoint) -eq 0) 'REPARSE_PATH_FORBIDDEN'
        }
        $taskParent = [IO.Path]::GetDirectoryName($taskCheckPath)
        if ($taskParent -eq $taskCheckPath) { break }
        $taskCheckPath = $taskParent
    }
}

function Write-TaskNewJson([string]$Path, $Value) {
    $taskJsonBytes = [Text.UTF8Encoding]::new($false).GetBytes(($Value | ConvertTo-Json -Depth 12) + [Environment]::NewLine)
    $taskStream = [IO.FileStream]::new($Path, [IO.FileMode]::CreateNew,
        [IO.FileAccess]::Write, [IO.FileShare]::None, 4096, [IO.FileOptions]::WriteThrough)
    try { $taskStream.Write($taskJsonBytes, 0, $taskJsonBytes.Length); $taskStream.Flush($true) }
    finally { $taskStream.Dispose() }
}

function Get-TaskTargetUser {
    # Exact local LSA lookup avoids a demonstrated LocalAccounts lookup failure.
    # It reads no profiles, credentials, sessions or other account inventory.
    try {
        $taskLookupAccount = [Security.Principal.NTAccount]::new([Environment]::MachineName, $taskAccountName)
        return $taskLookupAccount.Translate([Security.Principal.SecurityIdentifier])
    }
    catch [Security.Principal.IdentityNotMappedException] { return $null }
    catch {
        $script:taskFailureCode = 'LOCAL_ACCOUNT_LOOKUP_FAILED'
        throw
    }
}

function Compare-TaskSecureStrings([Security.SecureString]$First, [Security.SecureString]$Second) {
    if ($First.Length -ne $Second.Length) { return $false }
    $taskFirstPointer = [IntPtr]::Zero
    $taskSecondPointer = [IntPtr]::Zero
    try {
        $taskFirstPointer = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($First)
        $taskSecondPointer = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($Second)
        $taskDifference = 0
        for ($taskCharacter = 0; $taskCharacter -lt $First.Length; $taskCharacter++) {
            $taskDifference = $taskDifference -bor (
                [Runtime.InteropServices.Marshal]::ReadInt16($taskFirstPointer, $taskCharacter * 2) -bxor
                [Runtime.InteropServices.Marshal]::ReadInt16($taskSecondPointer, $taskCharacter * 2))
        }
        return $taskDifference -eq 0
    } finally {
        if ($taskFirstPointer -ne [IntPtr]::Zero) { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($taskFirstPointer) }
        if ($taskSecondPointer -ne [IntPtr]::Zero) { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($taskSecondPointer) }
    }
}

try {
    Require-Task ($env:OS -eq 'Windows_NT') 'WINDOWS_REQUIRED'
    $taskExactReview = Resolve-TaskRelative $taskWorkspace $taskReviewRelative
    $taskExactApproval = Resolve-TaskRelative $taskWorkspace $taskApprovalRelative
    $taskExactBuild = Resolve-TaskRelative $taskWorkspace $taskBuildRelative
    if (-not $ReviewPath) { $ReviewPath = $taskExactReview }
    if (-not $ApprovalPath) { $ApprovalPath = $taskExactApproval }
    if (-not $VerifiedBuildManifestPath) { $VerifiedBuildManifestPath = $taskExactBuild }
    foreach ($taskPathPair in @(
        @{ Provided = $ReviewPath; Exact = $taskExactReview },
        @{ Provided = $ApprovalPath; Exact = $taskExactApproval },
        @{ Provided = $VerifiedBuildManifestPath; Exact = $taskExactBuild }
    )) {
        Require-Task ([IO.Path]::GetFullPath($taskPathPair.Provided).Equals($taskPathPair.Exact, [StringComparison]::OrdinalIgnoreCase)) 'EXACT_BOUND_INPUT_PATH_REQUIRED'
        Assert-TaskNoReparse $taskPathPair.Exact
    }
    Require-Task ((Get-TaskHash $taskExactReview) -eq 'b1b0cb94a8aa705b5cc6ff674ed215a8487a960ff0a594f7abffadfbc4e57cc3') 'EXACT_RUNTIME_REVIEW_REQUIRED'
    Require-Task ((Get-TaskHash $taskExactApproval) -eq '90daa67a459bd985a1bec824bf0e8e09bf69537c2febdae85238336604c655ab') 'EXACT_DIRECT_APPROVAL_REQUIRED'
    Require-Task ((Get-TaskHash $taskExactBuild) -eq '976055e2095ff23db46fb9540727628dd6dd6de4dd817128c3e32a7d43880d6b') 'EXACT_CONNECTED_PACKAGE_REQUIRED'
    $taskReview = Get-Content -Raw -LiteralPath $taskExactReview | ConvertFrom-Json
    $taskApproval = Get-Content -Raw -LiteralPath $taskExactApproval | ConvertFrom-Json
    $taskBuild = Get-Content -Raw -LiteralPath $taskExactBuild | ConvertFrom-Json
    Require-Task ($taskReview.projectId -eq $taskProject -and $taskReview.bundleSha256 -eq $taskBundle) 'EXACT_RUNTIME_SCOPE_REQUIRED'
    Require-Task ($taskApproval.kind -eq 'wave5-runtime-owner-decision' -and $taskApproval.decision -eq 'approve' -and
        $taskApproval.source.kind -eq 'direct_user_message' -and $taskApproval.projectId -eq $taskProject -and
        $taskApproval.runtimeBundleSha256 -eq $taskBundle -and
        $taskApproval.runtimeFileSha256 -eq 'b1b0cb94a8aa705b5cc6ff674ed215a8487a960ff0a594f7abffadfbc4e57cc3' -and
        $taskApproval.operationScopeSha256 -eq 'fcdab89d242dc578793eba1d520ea0251699b70b7730c02aea94232805286e63' -and
        $taskApproval.production -eq $false -and $taskApproval.realBilling -eq $false -and
        $taskApproval.installOriginalSix -eq $false -and $taskApproval.noGlobalAuthChanges -eq $true -and
        $taskApproval.ownerAcceptedCriteria -eq 3 -and $taskApproval.additionalCriteriaAccepted -eq 0) 'DIRECT_APPROVAL_SCOPE_MISMATCH'
    $taskNative = $taskReview.workerConfiguration.nativeIsolation
    Require-Task ($taskNative.windowsAccount -eq $taskAccountName -and
        [IO.Path]::GetFullPath($taskNative.packageDirectory).Equals([IO.Path]::GetFullPath($taskPackageDirectory), [StringComparison]::OrdinalIgnoreCase) -and
        $taskNative.administratorSetupOnly -eq $true) 'EXACT_NATIVE_TARGET_REQUIRED'
    $taskReviewedBuildPath = Resolve-TaskRelative $taskWorkspace $taskNative.connectedBuildManifest
    Require-Task ($taskReviewedBuildPath.Equals($taskExactBuild, [StringComparison]::OrdinalIgnoreCase)) 'REVIEWED_CONNECTED_MANIFEST_MISMATCH'
    $taskBuildBindings = @($taskReview.artifacts | Where-Object {
        $_.path.Replace('/', '\').Equals($taskBuildRelative.Replace('/', '\'), [StringComparison]::OrdinalIgnoreCase)
    })
    Require-Task ($taskBuildBindings.Count -eq 1 -and $taskBuildBindings[0].sha256 -eq (Get-TaskHash $taskExactBuild)) 'CONNECTED_BUILD_NOT_BOUND'
    Require-Task ($taskBuild.entrypoint -eq 'lib/main.dart' -and $taskBuild.controlledEvidence -eq $false -and
        $taskBuild.current_source_match -eq $true -and $taskBuild.base_source_match -eq $true -and
        $taskBuild.mode -eq 'connected' -and $taskBuild.projectId -eq $taskProject -and
        $taskBuild.date -eq '20261010' -and $taskBuild.revision -eq 'r5') 'ORDINARY_CONNECTED_BUILD_REQUIRED'
    $taskSourceInputs = @($taskBuild.sourceHashes.PSObject.Properties)
    $taskReleaseFiles = @($taskBuild.releaseFiles)
    Require-Task ($taskSourceInputs.Count -eq 1068 -and $taskReleaseFiles.Count -eq 34) 'EXACT_SOURCE_AND_CONNECTED_RELEASE_COUNTS_REQUIRED'
    $taskSourceManifest = Resolve-TaskRelative $taskWorkspace $taskBuild.sourceManifest
    Require-Task ((Get-TaskHash $taskSourceManifest) -eq $taskBuild.sourceManifestSha256) 'CONNECTED_SOURCE_MANIFEST_CHANGED'
    $taskReleaseRoot = [IO.Path]::GetFullPath($taskBuild.releaseDirectory).TrimEnd('\')
    Require-Task (($taskReleaseRoot + '\').StartsWith($taskWorkspace + '\', [StringComparison]::OrdinalIgnoreCase)) 'RELEASE_OUTSIDE_REVIEWED_WORKSPACE'
    Assert-TaskNoReparse $taskReleaseRoot
    $taskExpectedRelativeFiles = @($taskReleaseFiles | ForEach-Object { $_.path.Replace('/', '\').ToLowerInvariant() } | Sort-Object)
    Require-Task (@($taskExpectedRelativeFiles | Select-Object -Unique).Count -eq 34) 'DUPLICATE_RELEASE_PATH_FORBIDDEN'
    $taskActualRelativeFiles = @(Get-ChildItem -LiteralPath $taskReleaseRoot -Recurse -File -Force | ForEach-Object {
        Require-Task (($_.Attributes -band [IO.FileAttributes]::ReparsePoint) -eq 0) 'RELEASE_REPARSE_FILE_FORBIDDEN'
        $_.FullName.Substring(($taskReleaseRoot + '\').Length).ToLowerInvariant()
    } | Sort-Object)
    Require-Task ($taskActualRelativeFiles.Count -eq 34 -and
        @((Compare-Object -ReferenceObject $taskExpectedRelativeFiles -DifferenceObject $taskActualRelativeFiles)).Count -eq 0) 'RELEASE_FILE_SET_CHANGED'
    # The executable and its manifest remain the exact already-approved r5 bytes.
    # Concurrent source work stays in the main checkout; no hash is reapproved.
    Assert-TaskNoReparse $taskApprovedSourceWorkspace
    $taskApprovedSnapshotRecord = Resolve-TaskRelative $taskWorkspace 'docs/verification/wave5/approved-isolated-execution-snapshot-20261013-r5-a2.json'
    Require-Task ((Get-TaskHash $taskApprovedSnapshotRecord) -eq '9c9e856c2cfdb852a3a9b9e66474f14c86a32dc72cc5b613e806699b2fb78c01') 'EXACT_APPROVED_SOURCE_SNAPSHOT_REQUIRED'
    foreach ($taskSource in $taskSourceInputs) {
        $taskSourceFile = Resolve-TaskRelative $taskApprovedSourceWorkspace $taskSource.Name
        Require-Task ((Get-TaskHash $taskSourceFile) -eq $taskSource.Value) 'CURRENT_SOURCE_CHANGED'
    }
    foreach ($taskFile in $taskReleaseFiles) {
        $taskSourceFile = Resolve-TaskRelative $taskReleaseRoot $taskFile.path
        Assert-TaskNoReparse $taskSourceFile
        Require-Task ((Get-TaskHash $taskSourceFile) -eq $taskFile.sha256 -and
            (Get-Item -LiteralPath $taskSourceFile).Length -eq $taskFile.bytes) 'CONNECTED_RELEASE_CHANGED'
    }
    $taskExecutable = Resolve-TaskRelative $taskReleaseRoot 'Jentra_OS.exe'
    $taskExecutableInfo = [Diagnostics.FileVersionInfo]::GetVersionInfo($taskExecutable)
    Require-Task ((Get-TaskHash $taskExecutable) -eq 'f625e4e09ff5a8f6a796547fbfdcecbd66d0129b28acb455e8d35e31d68e6906' -and
        $taskExecutableInfo.CompanyName -eq 'com.jentra.test' -and
        $taskExecutableInfo.ProductName -eq 'JentraOS_WindowsTest_20261010-r5_Connected') 'ISOLATED_CONNECTED_IDENTITY_REQUIRED'
    Assert-TaskNoReparse $taskPackageDirectory
    $taskAccountExists = $null -ne (Get-TaskTargetUser)
    $taskPackageExists = Test-Path -LiteralPath $taskPackageDirectory
    $taskCurrentIdentity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $taskPrincipal = [Security.Principal.WindowsPrincipal]::new($taskCurrentIdentity)
    $taskAdministrator = $taskPrincipal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    if ($Mode -eq 'Validate') {
        [ordered]@{ kind = 'wave5-native-profile-read-only-validation'; startedAt = $taskStarted;
            finishedAt = [DateTimeOffset]::UtcNow.ToString('o'); passed = $true;
            projectId = $taskProject; ownerApprovedBundle = $taskBundle; windowsAccount = $taskAccountName;
            packageDirectory = $taskPackageDirectory; sourceInputsVerified = 1068; connectedReleaseFilesVerified = 34;
            sourceInputsWorkspace = $taskApprovedSourceWorkspace; currentConcurrentSourceReplaced = $false;
            approvedSourceSnapshotSha256 = '9c9e856c2cfdb852a3a9b9e66474f14c86a32dc72cc5b613e806699b2fb78c01';
            exactReleaseFileSetVerified = $true; currentTokenAdministrator = $taskAdministrator;
            targetAccountExists = $taskAccountExists; targetPackageExists = [bool]$taskPackageExists;
            currentTokenCanProvision = ($taskAdministrator -and -not $taskAccountExists -and -not $taskPackageExists);
            accountCreated = $false; packageCreated = $false; privateInputRead = $false;
            networkCalls = 0; SDKExecuted = $false; nativeLaunched = $false; nativeKeyboardVerified = $false;
            authenticatedNative = $false; ownerAcceptedCriteria = 3; existingStoresReadOrCopied = $false
        } | ConvertTo-Json -Compress
        return
    }
    Require-Task $taskAdministrator 'HUMAN_ADMINISTRATOR_UAC_REQUIRED'
    Require-Task (-not $taskAccountExists) 'EXISTING_ACCOUNT_PRESERVED'
    Require-Task (-not $taskPackageExists) 'EXISTING_NATIVE_PACKAGE_PRESERVED'
    Write-Host 'Jentra OS approved isolated Windows runtime setup'
    Write-Host 'Create only jentra-w5-runtime as a standard local account.'
    Write-Host 'Enter its NEW password privately. Keep it out of chat. No password is saved by this helper.'
    $taskPassword = Read-Host 'New isolated Windows account password (hidden)' -AsSecureString
    $taskPasswordConfirmation = Read-Host 'Repeat new isolated Windows account password (hidden)' -AsSecureString
    Require-Task ($taskPassword.Length -gt 0 -and (Compare-TaskSecureStrings $taskPassword $taskPasswordConfirmation)) 'PRIVATE_PASSWORD_CONFIRMATION_REQUIRED'
    $taskPasswordConfirmation.Dispose(); $taskPasswordConfirmation = $null
    # Recheck byte bindings and collisions after the human prompt, before mutation.
    Require-Task ((Get-TaskHash $taskExactReview) -eq 'b1b0cb94a8aa705b5cc6ff674ed215a8487a960ff0a594f7abffadfbc4e57cc3' -and
        (Get-TaskHash $taskExactApproval) -eq '90daa67a459bd985a1bec824bf0e8e09bf69537c2febdae85238336604c655ab' -and
        (Get-TaskHash $taskExactBuild) -eq '976055e2095ff23db46fb9540727628dd6dd6de4dd817128c3e32a7d43880d6b') 'INPUT_CHANGED_DURING_PRIVATE_PROMPT'
    Require-Task ($null -eq (Get-TaskTargetUser)) 'EXISTING_ACCOUNT_PRESERVED'
    Require-Task (-not (Test-Path -LiteralPath $taskPackageDirectory)) 'EXISTING_NATIVE_PACKAGE_PRESERVED'
    foreach ($taskSource in $taskSourceInputs) {
        Require-Task ((Get-TaskHash (Resolve-TaskRelative $taskApprovedSourceWorkspace $taskSource.Name)) -eq $taskSource.Value) 'CURRENT_SOURCE_CHANGED_DURING_PROMPT'
    }
    foreach ($taskFile in $taskReleaseFiles) {
        Require-Task ((Get-TaskHash (Resolve-TaskRelative $taskReleaseRoot $taskFile.path)) -eq $taskFile.sha256) 'CONNECTED_RELEASE_CHANGED_DURING_PROMPT'
    }
    $taskRunId = [Guid]::NewGuid().ToString('N')
    $taskJournalBase = Join-Path $taskWorkspace 'docs\verification\wave5'
    $taskJournalPath = Join-Path $taskJournalBase ('native-profile-provision-20261013-r5-' + $taskRunId + '-result.json')
    Write-TaskNewJson (Join-Path $taskJournalBase ('native-profile-provision-20261013-r5-' + $taskRunId + '-before.json')) ([ordered]@{
        kind = 'wave5-native-profile-provision-before'; recordedAt = [DateTimeOffset]::UtcNow.ToString('o');
        ownerApprovedBundle = $taskBundle; projectId = $taskProject; account = $taskAccountName;
        packageDirectory = $taskPackageDirectory; sourceInputsVerified = 1068; releaseFilesVerified = 34;
        existingAccount = $false; existingPackage = $false; privatePasswordPrintedOrSaved = $false;
        helperSha256 = Get-TaskHash $PSCommandPath; actualMutationStarted = $false
    })
    $taskFailureCode = 'ACCOUNT_CREATION_FAILED'
    $taskCreatedUser = New-LocalUser -Name $taskAccountName -Password $taskPassword -Description 'Owner-approved isolated Wave 5 native acceptance' -ErrorAction Stop
    $taskAccountCreated = $true
    $taskPassword.Dispose(); $taskPassword = $null
    $taskFailureCode = 'STANDARD_GROUP_SETUP_FAILED'
    $taskUsersMembers = @(Get-LocalGroupMember -SID 'S-1-5-32-545' -ErrorAction Stop)
    if (-not ($taskUsersMembers | Where-Object { $_.SID.Value -eq $taskCreatedUser.SID.Value })) {
        Add-LocalGroupMember -SID 'S-1-5-32-545' -Member $taskCreatedUser -ErrorAction Stop
    }
    Require-Task (-not (@(Get-LocalGroupMember -SID 'S-1-5-32-544' -ErrorAction Stop) | Where-Object { $_.SID.Value -eq $taskCreatedUser.SID.Value })) 'NEW_USER_MUST_BE_STANDARD'
    $taskFailureCode = 'PACKAGE_DIRECTORY_CREATION_FAILED'
    [void][IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($taskPackageDirectory))
    New-Item -ItemType Directory -Path $taskPackageDirectory -ErrorAction Stop | Out-Null
    $taskPackageCreated = $true
    $taskAcl = [Security.AccessControl.DirectorySecurity]::new()
    $taskAcl.SetAccessRuleProtection($true, $false)
    $taskAcl.SetOwner($taskCurrentIdentity.User)
    foreach ($taskAclTarget in @(
        @{ Sid = [Security.Principal.SecurityIdentifier]::new('S-1-5-18'); Rights = 'FullControl' },
        @{ Sid = [Security.Principal.SecurityIdentifier]::new('S-1-5-32-544'); Rights = 'FullControl' },
        @{ Sid = $taskCurrentIdentity.User; Rights = 'FullControl' },
        @{ Sid = $taskCreatedUser.SID; Rights = 'ReadAndExecute' }
    )) {
        [void]$taskAcl.AddAccessRule([Security.AccessControl.FileSystemAccessRule]::new($taskAclTarget.Sid,
            $taskAclTarget.Rights, 'ContainerInherit,ObjectInherit', 'None', 'Allow'))
    }
    $taskFailureCode = 'PACKAGE_ACL_FAILED'
    Set-Acl -LiteralPath $taskPackageDirectory -AclObject $taskAcl
    $taskWrittenAcl = Get-Acl -LiteralPath $taskPackageDirectory
    Require-Task $taskWrittenAcl.AreAccessRulesProtected 'PACKAGE_ACL_NOT_PROTECTED'
    $taskRules = @($taskWrittenAcl.GetAccessRules($true, $true, [Security.Principal.SecurityIdentifier]))
    $taskAllowedSids = @('S-1-5-18', 'S-1-5-32-544', $taskCurrentIdentity.User.Value, $taskCreatedUser.SID.Value)
    Require-Task (@($taskRules | Where-Object { $_.AccessControlType -ne 'Allow' -or $_.IdentityReference.Value -notin $taskAllowedSids }).Count -eq 0) 'PACKAGE_UNREVIEWED_ACCESS_RULE'
    $taskNewUserRules = @($taskRules | Where-Object { $_.IdentityReference.Value -eq $taskCreatedUser.SID.Value })
    $taskExpectedUserRights = [Security.AccessControl.FileSystemRights]::ReadAndExecute -bor [Security.AccessControl.FileSystemRights]::Synchronize
    Require-Task ($taskNewUserRules.Count -eq 1 -and
        ($taskNewUserRules[0].FileSystemRights -bor [Security.AccessControl.FileSystemRights]::Synchronize) -eq $taskExpectedUserRights) 'NEW_USER_READ_EXECUTE_ONLY_REQUIRED'
    $taskFailureCode = 'RELEASE_COPY_FAILED'
    foreach ($taskFile in $taskReleaseFiles) {
        $taskSourceFile = Resolve-TaskRelative $taskReleaseRoot $taskFile.path
        $taskDestination = Resolve-TaskRelative $taskPackageDirectory $taskFile.path
        Assert-TaskNoReparse $taskSourceFile
        Assert-TaskNoReparse $taskDestination
        Require-Task ((Get-TaskHash $taskSourceFile) -eq $taskFile.sha256) 'RELEASE_CHANGED_BEFORE_COPY'
        [void][IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($taskDestination))
        [IO.File]::Copy($taskSourceFile, $taskDestination, $false)
        Require-Task ((Get-TaskHash $taskDestination) -eq $taskFile.sha256 -and
            (Get-Item -LiteralPath $taskDestination).Length -eq $taskFile.bytes) 'COPIED_RELEASE_HASH_MISMATCH'
        $taskCopiedFileCount++
    }
    $taskFailureCode = 'FINAL_STANDARD_ACCOUNT_VERIFICATION_FAILED'
    $taskConfirmedSid = Get-TaskTargetUser
    Require-Task ($null -ne $taskConfirmedSid -and $taskConfirmedSid.Value -eq $taskCreatedUser.SID.Value) 'CREATED_ACCOUNT_NOT_FOUND'
    Require-Task (@(Get-LocalGroupMember -SID 'S-1-5-32-545' -ErrorAction Stop | Where-Object { $_.SID.Value -eq $taskCreatedUser.SID.Value }).Count -eq 1) 'STANDARD_USERS_MEMBERSHIP_NOT_VERIFIED'
    Require-Task (@(Get-LocalGroupMember -SID 'S-1-5-32-544' -ErrorAction Stop | Where-Object { $_.SID.Value -eq $taskCreatedUser.SID.Value }).Count -eq 0) 'ADMINISTRATOR_MEMBERSHIP_FORBIDDEN'
    $taskProvisionResult = [ordered]@{
        kind = 'wave5-native-profile-provision-result'; startedAt = $taskStarted;
        finishedAt = [DateTimeOffset]::UtcNow.ToString('o'); passed = $true; ownerApprovedBundle = $taskBundle;
        projectId = $taskProject; account = $taskAccountName; sid = $taskCreatedUser.SID.Value;
        standardUserOnly = $true; accountCreated = $true; packageCreated = $true;
        packageDirectory = $taskPackageDirectory; copiedReleaseFiles = $taskCopiedFileCount;
        allCopiedReleaseHashesMatched = $true; nativeExecutable = Join-Path $taskPackageDirectory 'Jentra_OS.exe';
        passwordPrintedOrSaved = $false; existingAccountOrStoreChanged = $false;
        profileInitializedByWindowsSignIn = $false; nativeLaunched = $false; authenticatedNative = $false;
        nativeKeyboardVerified = $false; realMfaVerified = $false; ownerAcceptedCriteria = 3;
        nextAction = 'Human signs in to the NEW Windows account privately and opens its isolated Jentra_OS.exe. Keep old sessions signed in.'
    }
    Write-TaskNewJson $taskJournalPath $taskProvisionResult
    $taskProvisionResult | ConvertTo-Json -Compress
    Write-Host 'Created the standard account and copied the verified release. No native acceptance is claimed.'
    Write-Host 'Keep existing Windows sessions signed in. Sign in privately to jentra-w5-runtime and open the isolated Jentra_OS.exe.'
} catch {
    $taskFailure = [ordered]@{ kind = 'wave5-native-profile-setup-failure'; startedAt = $taskStarted;
        recordedAt = [DateTimeOffset]::UtcNow.ToString('o'); passed = $false; failureCode = $taskFailureCode;
        exceptionType = $_.Exception.GetType().FullName; mode = $Mode; accountCreated = $taskAccountCreated;
        packageCreated = $taskPackageCreated; copiedReleaseFiles = $taskCopiedFileCount;
        automaticRollbackOrDeletion = $false; passwordPrintedOrSaved = $false;
        nativeLaunched = $false; nativeKeyboardVerified = $false; existingAccountsAndStoresPreserved = $true
    }
    if ($taskJournalPath) {
        try { Write-TaskNewJson $taskJournalPath $taskFailure } catch { }
    }
    $taskFailure | ConvertTo-Json -Compress
    Write-Host 'Setup stopped. Any newly created partial account/package is preserved for inspection; do not reset or retry blindly.'
    exit 1
} finally {
    if ($null -ne $taskPassword) { $taskPassword.Dispose() }
    if ($null -ne $taskPasswordConfirmation) { $taskPasswordConfirmation.Dispose() }
}
