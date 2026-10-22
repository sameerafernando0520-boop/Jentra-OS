[CmdletBinding()]
param([string]$InstallRoot = $PSScriptRoot, [switch]$VerifyOnly, [switch]$VerifyPrevious)
$ErrorActionPreference = 'Stop'
function Get-Sha256([string]$Path) {
  $stream = [IO.File]::OpenRead($Path); $hasher = [Security.Cryptography.SHA256]::Create()
  try { return ([BitConverter]::ToString($hasher.ComputeHash($stream))).Replace('-','').ToLowerInvariant() }
  finally { $stream.Dispose(); $hasher.Dispose() }
}
$InstallRoot = [IO.Path]::GetFullPath($InstallRoot)
if ($VerifyPrevious -and !$VerifyOnly) { throw 'PREVIOUS_RELEASE_VERIFICATION_ONLY' }
$pointerName = if ($VerifyPrevious) { 'previous.json' } else { 'current.json' }
$current = Get-Content -LiteralPath (Join-Path $InstallRoot $pointerName) -Raw | ConvertFrom-Json
if ($current.releaseId -notmatch '^\d+\.\d+\.\d+-\d+-(development|production)-[a-f0-9]{12}$') { throw 'INVALID_CURRENT_RELEASE' }
$versionRoot = [IO.Path]::GetFullPath((Join-Path $InstallRoot ('versions\' + $current.releaseId)))
if (!$versionRoot.StartsWith(($InstallRoot.TrimEnd('\') + '\versions\'), [StringComparison]::OrdinalIgnoreCase)) { throw 'INVALID_CURRENT_RELEASE' }
$manifest = Get-Content -LiteralPath (Join-Path $versionRoot 'release-manifest.json') -Raw | ConvertFrom-Json
if ($manifest.releaseId -ne $current.releaseId -or $manifest.sourceSha256 -ne $current.sourceSha256 -or $manifest.channel -ne $current.channel -or $manifest.version -ne $current.version -or $manifest.buildNumber -ne $current.buildNumber) { throw 'RELEASE_IDENTITY_MISMATCH' }
foreach ($relative in @('jentra_desktop.exe','data/app.so')) {
  $file = @($manifest.files | Where-Object { $_.path -eq $relative })
  if ($file.Count -ne 1) { throw 'RELEASE_ENTRY_MISSING' }
}
$expected = @{}
foreach ($file in $manifest.files) {
  $relative = [string]$file.path
  if ([string]::IsNullOrWhiteSpace($relative) -or [IO.Path]::IsPathRooted($relative) -or $relative.Contains(':') -or $relative.Contains('..') -or $relative -eq 'release-manifest.json' -or $expected.ContainsKey($relative.ToLowerInvariant())) { throw 'INVALID_INSTALLED_RELEASE_PATH' }
  $expected[$relative.ToLowerInvariant()] = $true
  $target = [IO.Path]::GetFullPath((Join-Path $versionRoot $relative))
  if (!$target.StartsWith(($versionRoot.TrimEnd('\') + '\'), [StringComparison]::OrdinalIgnoreCase)) { throw 'INVALID_INSTALLED_RELEASE_PATH' }
  $item = Get-Item -LiteralPath $target
  if ($item.PSIsContainer -or ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -or $item.Length -ne $file.bytes -or (Get-Sha256 $target) -ne $file.sha256) { throw 'INSTALLED_RELEASE_HASH_MISMATCH' }
}
$executable = Join-Path $versionRoot 'jentra_desktop.exe'
if ($VerifyOnly) { [PSCustomObject]@{releaseId=$manifest.releaseId;version=$manifest.version;channel=$manifest.channel;executable=$executable;sourceSha256=$manifest.sourceSha256} | ConvertTo-Json }
else { Start-Process -FilePath $executable -WorkingDirectory $versionRoot }
