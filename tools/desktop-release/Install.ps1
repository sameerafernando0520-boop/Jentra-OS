[CmdletBinding()]
param(
  [string]$PackageRoot = $PSScriptRoot,
  [string]$InstallRoot,
  [switch]$NoShortcuts,
  [switch]$NoRegistration
)
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2

function Get-Sha256([string]$Path) {
  $stream = [IO.File]::OpenRead($Path); $hasher = [Security.Cryptography.SHA256]::Create()
  try { return ([BitConverter]::ToString($hasher.ComputeHash($stream))).Replace('-','').ToLowerInvariant() }
  finally { $stream.Dispose(); $hasher.Dispose() }
}

function Resolve-ChildPath([string]$Root, [string]$Relative) {
  if ([string]::IsNullOrWhiteSpace($Relative) -or [IO.Path]::IsPathRooted($Relative) -or
      $Relative.Contains(':') -or $Relative.Contains('..')) { throw 'INVALID_PACKAGE_PATH' }
  $full = [IO.Path]::GetFullPath((Join-Path $Root $Relative))
  $prefix = [IO.Path]::GetFullPath($Root).TrimEnd('\') + '\'
  if (!$full.StartsWith($prefix, [StringComparison]::OrdinalIgnoreCase)) { throw 'PACKAGE_PATH_OUTSIDE_ROOT' }
  return $full
}

function Test-Payload([string]$Root, $Manifest) {
  $expected = @{}
  foreach ($file in $Manifest.files) {
    if ($file.path -eq 'release-manifest.json' -or $expected.ContainsKey($file.path.ToLowerInvariant())) { throw 'DUPLICATE_PACKAGE_PATH' }
    $expected[$file.path.ToLowerInvariant()] = $true
    $path = Resolve-ChildPath $Root $file.path
    $item = Get-Item -LiteralPath $path
    if ($item.PSIsContainer -or ($item.Attributes -band [IO.FileAttributes]::ReparsePoint)) { throw 'INVALID_PACKAGE_FILE' }
    if ($item.Length -ne $file.bytes -or (Get-Sha256 $path) -ne $file.sha256) { throw 'PACKAGE_HASH_MISMATCH' }
  }
  $actual = @(Get-ChildItem -LiteralPath $Root -File -Recurse | Where-Object { $_.FullName -ne (Join-Path $Root 'release-manifest.json') })
  if ($actual.Count -ne $expected.Count) { throw 'UNEXPECTED_PACKAGE_FILE' }
  foreach ($item in $actual) {
    $relative = $item.FullName.Substring($Root.TrimEnd('\').Length + 1).Replace('\','/').ToLowerInvariant()
    if (!$expected.ContainsKey($relative)) { throw 'UNEXPECTED_PACKAGE_FILE' }
  }
}

$PackageRoot = [IO.Path]::GetFullPath($PackageRoot)
$payload = Join-Path $PackageRoot 'Payload'
$manifestPath = Join-Path $payload 'release-manifest.json'
$manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
if ($manifest.schemaVersion -ne 1 -or $manifest.product -ne 'Jentra OS' -or
    $manifest.channel -notin @('development','production') -or
    $manifest.releaseId -notmatch '^\d+\.\d+\.\d+-\d+-(development|production)-[a-f0-9]{12}$' -or
    $manifest.sourceSha256 -notmatch '^[a-f0-9]{64}$' -or
    $manifest.executable -ne 'jentra_desktop.exe' -or @($manifest.files).Count -lt 2) { throw 'INVALID_RELEASE_MANIFEST' }
Test-Payload $payload $manifest
$defaultInstall = [string]::IsNullOrWhiteSpace($InstallRoot)
if ($defaultInstall) {
  $folder = if ($manifest.channel -eq 'production') { 'Jentra OS' } else { 'Jentra OS Development' }
  $InstallRoot = Join-Path $env:LOCALAPPDATA ('Programs\' + $folder)
}
$InstallRoot = [IO.Path]::GetFullPath($InstallRoot)
if ($InstallRoot -eq [IO.Path]::GetPathRoot($InstallRoot) -or $InstallRoot -eq [IO.Path]::GetFullPath($env:USERPROFILE)) { throw 'UNSAFE_INSTALL_ROOT' }
if (!$defaultInstall -and (!$NoShortcuts -or !$NoRegistration)) { throw 'CUSTOM_ROOT_REQUIRES_NO_SHORTCUTS_AND_NO_REGISTRATION' }
New-Item -ItemType Directory -Path $InstallRoot -Force | Out-Null
if ((Get-Item -LiteralPath $InstallRoot).Attributes -band [IO.FileAttributes]::ReparsePoint) { throw 'INSTALL_ROOT_REPARSE_POINT' }
$lockPath = Join-Path $InstallRoot 'install.lock'
$lock = $null
$stagePath = $null
try {
  $lock = [IO.File]::Open($lockPath, [IO.FileMode]::CreateNew, [IO.FileAccess]::Write, [IO.FileShare]::None)
  $versions = Join-Path $InstallRoot 'versions'
  New-Item -ItemType Directory -Path $versions -Force | Out-Null
  if ((Get-Item -LiteralPath $versions).Attributes -band [IO.FileAttributes]::ReparsePoint) { throw 'VERSIONS_REPARSE_POINT' }
  $releasePath = Resolve-ChildPath $versions $manifest.releaseId
  $currentPath = Join-Path $InstallRoot 'current.json'
  if (Test-Path -LiteralPath $currentPath) {
    $current = Get-Content -LiteralPath $currentPath -Raw | ConvertFrom-Json
    if ($current.channel -ne $manifest.channel) { throw 'RELEASE_CHANNEL_MISMATCH' }
    if ([long]$current.buildNumber -gt [long]$manifest.buildNumber) { throw 'OLDER_BUILD_REQUIRES_EXPLICIT_ROLLBACK' }
  }
  if (Test-Path -LiteralPath $releasePath) {
    Test-Payload $releasePath $manifest
    if ((Get-Sha256 (Join-Path $releasePath 'release-manifest.json')) -ne (Get-Sha256 $manifestPath)) { throw 'EXISTING_RELEASE_ID_COLLISION' }
  } else {
    $stagePath = Resolve-ChildPath $versions ('.stage-' + [Guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $stagePath | Out-Null
    foreach ($file in $manifest.files) {
      $target = Resolve-ChildPath $stagePath $file.path
      New-Item -ItemType Directory -Path (Split-Path $target) -Force | Out-Null
      Copy-Item -LiteralPath (Resolve-ChildPath $payload $file.path) -Destination $target
    }
    Copy-Item -LiteralPath $manifestPath -Destination (Join-Path $stagePath 'release-manifest.json')
    Test-Payload $stagePath $manifest
    Move-Item -LiteralPath $stagePath -Destination $releasePath
    $stagePath = $null
  }
  foreach ($installerFile in @('Launch.ps1','Rollback.ps1','Uninstall.ps1')) {
    Copy-Item -LiteralPath (Join-Path $PackageRoot $installerFile) -Destination (Join-Path $InstallRoot $installerFile) -Force
  }
  $pointer = [ordered]@{ releaseId=$manifest.releaseId; channel=$manifest.channel; version=$manifest.version; buildNumber=$manifest.buildNumber; sourceSha256=$manifest.sourceSha256; installedAtUtc=[DateTime]::UtcNow.ToString('o') }
  $nextPointer = Join-Path $InstallRoot ('current-' + [Guid]::NewGuid().ToString('N') + '.json')
  [IO.File]::WriteAllText($nextPointer, ($pointer | ConvertTo-Json) + "`n", (New-Object Text.UTF8Encoding($false)))
  if (Test-Path -LiteralPath $currentPath) {
    if ((Get-Content -LiteralPath $currentPath -Raw | ConvertFrom-Json).releaseId -ne $manifest.releaseId) {
      [IO.File]::Replace($nextPointer, $currentPath, (Join-Path $InstallRoot 'previous.json'))
    } else { Remove-Item -LiteralPath $nextPointer }
  } else { [IO.File]::Move($nextPointer, $currentPath) }
  $displayName = if ($manifest.channel -eq 'production') { 'Jentra OS' } else { 'Jentra OS (Development)' }
  if (!$NoShortcuts) {
    $shell = New-Object -ComObject WScript.Shell
    $shortcut = $shell.CreateShortcut((Join-Path ([Environment]::GetFolderPath('Programs')) ($displayName + '.lnk')))
    $shortcut.TargetPath = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
    $shortcut.Arguments = '-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File "' + (Join-Path $InstallRoot 'Launch.ps1') + '"'
    $shortcut.WorkingDirectory = $InstallRoot
    $shortcut.IconLocation = (Join-Path $releasePath $manifest.executable) + ',0'
    $shortcut.Description = $displayName + ' ' + $manifest.version
    $shortcut.Save()
  }
  if (!$NoRegistration) {
    $key = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\JentraOS-' + $manifest.channel
    New-Item -Path $key -Force | Out-Null
    $uninstall = 'powershell.exe -NoProfile -ExecutionPolicy Bypass -File "' + (Join-Path $InstallRoot 'Uninstall.ps1') + '"'
    foreach ($entry in @{DisplayName=$displayName;DisplayVersion=$manifest.version;Publisher='Jentra';InstallLocation=$InstallRoot;DisplayIcon=(Join-Path $releasePath $manifest.executable);UninstallString=$uninstall}.GetEnumerator()) { New-ItemProperty -LiteralPath $key -Name $entry.Key -Value $entry.Value -PropertyType String -Force | Out-Null }
    New-ItemProperty -LiteralPath $key -Name NoModify -Value 1 -PropertyType DWord -Force | Out-Null
    New-ItemProperty -LiteralPath $key -Name NoRepair -Value 1 -PropertyType DWord -Force | Out-Null
  }
  $receipt = [ordered]@{releaseId=$manifest.releaseId;version=$manifest.version;channel=$manifest.channel;installRoot=$InstallRoot;executable=(Join-Path $releasePath $manifest.executable);verifiedFiles=@($manifest.files).Count;previousReleaseRetained=(Test-Path -LiteralPath (Join-Path $InstallRoot 'previous.json'));shortcutsCreated=(!$NoShortcuts);registered=(!$NoRegistration);processesStopped=0;userDataChanged=$false}
  [IO.File]::WriteAllText((Join-Path $InstallRoot 'installation-receipt.json'), ($receipt | ConvertTo-Json) + "`n", (New-Object Text.UTF8Encoding($false)))
  $receipt | ConvertTo-Json
} finally {
  if ($lock) { $lock.Dispose(); Remove-Item -LiteralPath $lockPath -ErrorAction SilentlyContinue }
  # Leave a failed staging directory for inspection; never recursively remove an inferred path.
}
