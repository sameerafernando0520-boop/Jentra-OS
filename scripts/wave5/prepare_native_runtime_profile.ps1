param(
    [ValidateSet('Plan', 'Provision')][string]$Mode = 'Plan',
    [string]$ReviewPath,
    [string]$ApprovalPath,
    [string]$VerifiedBuildManifestPath,
    [Security.SecureString]$NativeProfilePassword
)
$ErrorActionPreference = 'Stop'
$wave5NativeName = 'jentra-w5-runtime'
$wave5PackageDirectory = 'C:\Users\Public\Documents\JentraWave5Runtime\20261009'
$wave5Workspace = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..'))
if ($Mode -eq 'Plan') {
    [pscustomobject]@{
        WindowsAccount = $wave5NativeName
        StandardUserOnly = $true
        PackageDirectory = $wave5PackageDirectory
        StoreIsolation = 'Fresh Windows profile: default AppData, secure keys and Supabase sessions'
        Provisioned = $false
        PasswordReference = 'Jentra/W5/20261009/native-profile/password'
    } | ConvertTo-Json
    return
}
if (-not $ReviewPath -or -not $ApprovalPath -or -not $VerifiedBuildManifestPath -or -not $NativeProfilePassword) {
    throw 'EXACT_REVIEW_APPROVAL_BUILD_AND_PRIVATE_PASSWORD_REQUIRED'
}
& node (Join-Path $wave5Workspace 'workers\wave5\validate_runtime_review.mjs') $ReviewPath $ApprovalPath $wave5Workspace
if ($LASTEXITCODE -ne 0) { throw 'OWNER_APPROVAL_OR_SOURCE_HASH_REQUIRED' }
$wave5Review = Get-Content -LiteralPath $ReviewPath -Raw | ConvertFrom-Json
if ($wave5Review.workerConfiguration.nativeIsolation.windowsAccount -ne $wave5NativeName -or
    $wave5Review.workerConfiguration.nativeIsolation.packageDirectory -ne $wave5PackageDirectory) {
    throw 'NATIVE_TARGET_NOT_REVIEWED'
}
$wave5Principal = [Security.Principal.WindowsPrincipal]::new([Security.Principal.WindowsIdentity]::GetCurrent())
if (-not $wave5Principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) { throw 'NATIVE_PROFILE_SETUP_REQUIRES_ADMINISTRATOR' }
if (Get-LocalUser -Name $wave5NativeName -ErrorAction SilentlyContinue) { throw 'NATIVE_ACCOUNT_COLLISION_REFRESH_REVIEW' }
if (Test-Path -LiteralPath $wave5PackageDirectory) { throw 'NATIVE_PACKAGE_COLLISION_REFRESH_REVIEW' }
$wave5Build = Get-Content -LiteralPath $VerifiedBuildManifestPath -Raw | ConvertFrom-Json
if ($wave5Build.entrypoint -ne 'lib/main.dart' -or $wave5Build.controlledEvidence -ne $false -or
    $wave5Build.current_source_match -ne $true -or -not $wave5Build.releaseFiles -or -not $wave5Build.sourceHashes) {
    throw 'FRESH_ORDINARY_RUNTIME_BUILD_REQUIRED'
}
$wave5ReleaseRoot = [IO.Path]::GetFullPath($wave5Build.releaseDirectory).TrimEnd('\') + '\'
if (-not $wave5ReleaseRoot.StartsWith($wave5Workspace.TrimEnd('\') + '\', [StringComparison]::OrdinalIgnoreCase)) {
    throw 'BUILD_OUTSIDE_REVIEWED_WORKSPACE'
}
# Verify every source/release byte before creating an OS account or directory.
foreach ($wave5Source in $wave5Build.sourceHashes.PSObject.Properties) {
    $wave5SourcePath = [IO.Path]::GetFullPath((Join-Path $wave5Workspace $wave5Source.Name))
    if (-not $wave5SourcePath.StartsWith($wave5Workspace.TrimEnd('\') + '\', [StringComparison]::OrdinalIgnoreCase) -or
        (Get-FileHash -LiteralPath $wave5SourcePath -Algorithm SHA256).Hash.ToLowerInvariant() -ne $wave5Source.Value) { throw 'RUNTIME_SOURCE_CHANGED' }
}
foreach ($wave5File in $wave5Build.releaseFiles) {
    $wave5ResolvedFile = [IO.Path]::GetFullPath((Join-Path $wave5ReleaseRoot $wave5File.path))
    if (-not $wave5ResolvedFile.StartsWith($wave5ReleaseRoot, [StringComparison]::OrdinalIgnoreCase) -or
        (Get-FileHash -LiteralPath $wave5ResolvedFile -Algorithm SHA256).Hash.ToLowerInvariant() -ne $wave5File.sha256) { throw 'RUNTIME_RELEASE_CHANGED' }
}
# Authorization covers this one new standard local account. Password arrives as
# SecureString from the reviewed private store; it is never printed or saved.
$wave5NativeUser = New-LocalUser -Name $wave5NativeName -Password $NativeProfilePassword -Description 'Owner-reviewed isolated Wave 5 native acceptance'
Add-LocalGroupMember -SID 'S-1-5-32-545' -Member $wave5NativeUser
New-Item -ItemType Directory -Path $wave5PackageDirectory | Out-Null
$wave5Acl = [Security.AccessControl.DirectorySecurity]::new()
$wave5Acl.SetAccessRuleProtection($true, $false)
$wave5AclTargets = @(
    @{ Sid = [Security.Principal.SecurityIdentifier]::new('S-1-5-18'); Rights = 'FullControl' },
    @{ Sid = [Security.Principal.SecurityIdentifier]::new('S-1-5-32-544'); Rights = 'FullControl' },
    @{ Sid = [Security.Principal.WindowsIdentity]::GetCurrent().User; Rights = 'FullControl' },
    @{ Sid = $wave5NativeUser.SID; Rights = 'ReadAndExecute' }
)
foreach ($wave5Target in $wave5AclTargets) {
    $wave5Acl.AddAccessRule([Security.AccessControl.FileSystemAccessRule]::new($wave5Target.Sid, $wave5Target.Rights,
        'ContainerInherit,ObjectInherit', 'None', 'Allow'))
}
Set-Acl -LiteralPath $wave5PackageDirectory -AclObject $wave5Acl
foreach ($wave5File in $wave5Build.releaseFiles) {
    $wave5Destination = [IO.Path]::GetFullPath((Join-Path $wave5PackageDirectory $wave5File.path))
    if (-not $wave5Destination.StartsWith($wave5PackageDirectory + '\', [StringComparison]::OrdinalIgnoreCase)) { throw 'DESTINATION_OUTSIDE_REVIEWED_PACKAGE' }
    New-Item -ItemType Directory -Path ([IO.Path]::GetDirectoryName($wave5Destination)) -Force | Out-Null
    Copy-Item -LiteralPath (Join-Path $wave5ReleaseRoot $wave5File.path) -Destination $wave5Destination
    if ((Get-FileHash -LiteralPath $wave5Destination -Algorithm SHA256).Hash.ToLowerInvariant() -ne $wave5File.sha256) { throw 'COPIED_BUILD_HASH_MISMATCH' }
}
[pscustomobject]@{ WindowsAccount = $wave5NativeName; Sid = $wave5NativeUser.SID.Value; StandardUserOnly = $true;
    PackageDirectory = $wave5PackageDirectory; OwnerApprovedBundle = $wave5Review.bundleSha256; Created = $true } | ConvertTo-Json
# Launch interactive native acceptance under this account with LoadUserProfile.
# Sign-out/restart stays within this fresh profile. Do not read the old user
# profile, acceptance database, secure keys or other chats' sessions.
