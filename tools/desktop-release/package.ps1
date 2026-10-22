[CmdletBinding()]
param([Parameter(Mandatory=$true)][string]$BundlePath, [Parameter(Mandatory=$true)][string]$OutputDirectory)
$ErrorActionPreference = 'Stop'
$BundlePath = [IO.Path]::GetFullPath($BundlePath)
$OutputDirectory = [IO.Path]::GetFullPath($OutputDirectory)
$sourceManifest = Get-Content -LiteralPath (Join-Path $OutputDirectory 'source-manifest.json') -Raw | ConvertFrom-Json
$identity = $sourceManifest.identity
if ($identity.sourceSha256 -notmatch '^[a-f0-9]{64}$' -or $identity.releaseId -notmatch '^\d+\.\d+\.\d+-\d+-(development|production)-[a-f0-9]{12}$') { throw 'SOURCE_IDENTITY_REQUIRED' }
$expectedBundle = [IO.Path]::GetFullPath((Join-Path $sourceManifest.snapshot 'apps\jentra_desktop\build\windows\x64\runner\Release'))
if ($BundlePath -ne $expectedBundle) { throw 'BUNDLE_MUST_BELONG_TO_RECORDED_SOURCE_SNAPSHOT' }
foreach ($sourceFile in $sourceManifest.buildFiles) {
  if ((Get-FileHash -LiteralPath (Join-Path $sourceManifest.snapshot $sourceFile.path) -Algorithm SHA256).Hash.ToLowerInvariant() -ne $sourceFile.sha256) { throw 'BUILD_SOURCE_CHANGED' }
}
$installerSourceRoot = Join-Path $sourceManifest.snapshot 'tools\desktop-release'
if ((Get-FileHash -LiteralPath $PSCommandPath -Algorithm SHA256).Hash -ne (Get-FileHash -LiteralPath (Join-Path $installerSourceRoot 'package.ps1') -Algorithm SHA256).Hash) { throw 'PACKAGER_MUST_MATCH_RECORDED_SOURCE_SNAPSHOT' }
. (Join-Path $installerSourceRoot 'vc-runtime.ps1')
$cmakeCache = Get-Content -LiteralPath (Join-Path $BundlePath '..\..\CMakeCache.txt')
$instanceLine = @($cmakeCache | Where-Object { $_ -match '^CMAKE_GENERATOR_INSTANCE:INTERNAL=' })
if ($instanceLine.Count -ne 1) { throw 'BUILD_VISUAL_STUDIO_INSTANCE_REQUIRED' }
$vcRuntime = Get-JentraVcRuntimeFiles ($instanceLine[0] -replace '^CMAKE_GENERATOR_INSTANCE:INTERNAL=', '')
foreach ($required in @('jentra_desktop.exe','flutter_windows.dll','data/app.so','data/icudtl.dat')) { if (!(Test-Path -LiteralPath (Join-Path $BundlePath $required))) { throw 'WINDOWS_BUNDLE_INCOMPLETE' } }
$executableVersion = [Diagnostics.FileVersionInfo]::GetVersionInfo((Join-Path $BundlePath 'jentra_desktop.exe'))
if ($executableVersion.ProductVersion -ne $identity.version -or $executableVersion.ProductName -ne $identity.applicationProductName) { throw 'WINDOWS_EXECUTABLE_IDENTITY_MISMATCH' }
$package = Join-Path $OutputDirectory 'package'
if (Test-Path -LiteralPath $package) { throw 'NEW_PACKAGE_DIRECTORY_REQUIRED' }
$payload = Join-Path $package 'Payload'
New-Item -ItemType Directory -Path $payload -Force | Out-Null
$files = @()
foreach ($file in (Get-ChildItem -LiteralPath $BundlePath -File -Recurse | Sort-Object FullName)) {
  $relative = $file.FullName.Substring($BundlePath.TrimEnd('\').Length + 1).Replace('\','/')
  if ($relative -match '(?i)(^|/)(\.env[^/]*|[^/]*firebase-adminsdk[^/]*|[^/]*service[_-]?account[^/]*|[^/]*private[_-]?key[^/]*)$' -or $relative -match '\.(pfx|p12|pem|key)$') { throw 'FORBIDDEN_RUNTIME_FILE' }
  if ($file.Attributes -band [IO.FileAttributes]::ReparsePoint) { throw 'RUNTIME_REPARSE_POINT' }
  $target = Join-Path $payload $relative
  New-Item -ItemType Directory -Path (Split-Path $target) -Force | Out-Null
  Copy-Item -LiteralPath $file.FullName -Destination $target
  $files += [ordered]@{path=$relative;bytes=$file.Length;sha256=(Get-FileHash -LiteralPath $target -Algorithm SHA256).Hash.ToLowerInvariant()}
}
$vcRuntimeFiles = @()
foreach ($runtimeFile in $vcRuntime.files) {
  $target = Join-Path $payload $runtimeFile.Name
  $sourceHash = (Get-FileHash -LiteralPath $runtimeFile.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
  $existing = @($files | Where-Object { $_.path -eq $runtimeFile.Name })
  if ($existing.Count -gt 1 -or ($existing.Count -eq 1 -and $existing[0].sha256 -ne $sourceHash)) { throw 'VISUAL_CPP_RUNTIME_COLLISION' }
  if ($existing.Count -eq 0) {
    Copy-Item -LiteralPath $runtimeFile.FullName -Destination $target
    if ((Get-FileHash -LiteralPath $target -Algorithm SHA256).Hash.ToLowerInvariant() -ne $sourceHash) { throw 'VISUAL_CPP_RUNTIME_COPY_CHANGED' }
    $files += [ordered]@{path=$runtimeFile.Name;bytes=$runtimeFile.Length;sha256=$sourceHash}
  }
  $vcRuntimeFiles += [ordered]@{path=$runtimeFile.Name;bytes=$runtimeFile.Length;sha256=$sourceHash;fileVersion=$runtimeFile.VersionInfo.FileVersion}
}
$runtimeProvenance = [ordered]@{origin='Visual Studio x64 CRT redistributable';visualStudioInstance=$vcRuntime.visualStudioInstance;version=$vcRuntime.version;redistDirectory=$vcRuntime.redistDirectory;files=$vcRuntimeFiles}
$manifest = [ordered]@{schemaVersion=1;product='Jentra OS';releaseId=$identity.releaseId;version=$identity.version;buildNumber=$identity.buildNumber;channel=$identity.channel;projectRef=$identity.projectRef;revision=$identity.revision;sourceSha256=$identity.sourceSha256;sourceDirty=$identity.sourceDirty;preparedAtUtc=$identity.preparedAtUtc;packagedAtUtc=[DateTime]::UtcNow.ToString('o');executable='jentra_desktop.exe';authenticode='unsigned';productionReadiness='Not established by build or packaging; production deployment and human acceptance remain separate gates';vcRuntime=$runtimeProvenance;files=$files}
[IO.File]::WriteAllText((Join-Path $payload 'release-manifest.json'), ($manifest | ConvertTo-Json -Depth 10) + "`n", (New-Object Text.UTF8Encoding($false)))
foreach ($name in @('Install.ps1','Launch.ps1','Rollback.ps1','Uninstall.ps1')) { Copy-Item -LiteralPath (Join-Path $installerSourceRoot $name) -Destination (Join-Path $package $name) }
[IO.File]::WriteAllText((Join-Path $package 'Install.cmd'), '@echo off' + "`r`n" + 'powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0Install.ps1"' + "`r`n" + 'pause' + "`r`n", (New-Object Text.ASCIIEncoding))
$guide = @'
Jentra OS Windows release candidate

Install: double-click the Setup.exe beside this ZIP, or extract this ZIP and run Install.cmd.
Then open Jentra OS (Development), or Jentra OS for a production-channel package, in Start.
The installer verifies every runtime hash, keeps older versions and switches the launcher to this bundle.
It never kills a running app, changes a backend, copies credentials or removes user data.
Close any old app yourself and open the Start shortcut to see the updated release.
Check About Jentra OS for version, channel, project, revision and source SHA-256.

This candidate is unsigned. Packaging does not establish production approval or native acceptance.
Development has a separate installation name/ProductName. Existing sessions/drafts are not migrated or erased.
You may need to sign in again. A database login is not bundled.
The package includes the Microsoft Visual C++ x64 CRT redistributable from the build's installed Visual Studio. Microsoft retains its copyright in those DLLs.

Rollback: powershell.exe -NoProfile -ExecutionPolicy Bypass -File "<install folder>\Rollback.ps1" -ConfirmRollback
This selects the previous desktop bundle only. It does not roll back backend changes or user data.
Uninstall removes shortcut/registration and retains installed versions and user data for recovery.
'@
[IO.File]::WriteAllText((Join-Path $package 'README.txt'), $guide + "`n", (New-Object Text.UTF8Encoding($false)))
$zipPath = Join-Path $OutputDirectory ('Jentra-OS-' + $identity.releaseId + '-Windows.zip')
Add-Type -AssemblyName System.IO.Compression.FileSystem
[IO.Compression.ZipFile]::CreateFromDirectory($package, $zipPath, [IO.Compression.CompressionLevel]::Optimal, $false)
$setupPath = Join-Path $OutputDirectory ('Jentra-OS-' + $identity.releaseId + '-Setup.exe')
$csc = Join-Path $env:WINDIR 'Microsoft.NET\Framework64\v4.0.30319\csc.exe'
$icon = Join-Path $sourceManifest.snapshot 'apps\jentra_desktop\windows\runner\resources\app_icon.ico'
& $csc /nologo /target:winexe /platform:anycpu /reference:System.Windows.Forms.dll /reference:System.IO.Compression.dll /reference:System.IO.Compression.FileSystem.dll ('/win32icon:' + $icon) ('/resource:' + $zipPath + ',JentraPackage') ('/out:' + $setupPath) (Join-Path $installerSourceRoot 'Setup.cs')
if ($LASTEXITCODE -ne 0) { throw 'SETUP_COMPILATION_FAILED' }
$archive = [IO.Compression.ZipFile]::OpenRead($zipPath)
$verified = 0
try {
  foreach ($file in $files) {
    $entry = $archive.GetEntry('Payload/' + $file.path)
    if (!$entry -or $entry.Length -ne $file.bytes) { throw 'ARCHIVE_FILE_MISSING_OR_SIZE_CHANGED' }
    $stream = $entry.Open(); $hasher = [Security.Cryptography.SHA256]::Create()
    try { $hash = ([BitConverter]::ToString($hasher.ComputeHash($stream))).Replace('-','').ToLowerInvariant(); if ($hash -ne $file.sha256) { throw 'ARCHIVE_HASH_MISMATCH' }; $verified++ }
    finally { $stream.Dispose(); $hasher.Dispose() }
  }
} finally { $archive.Dispose() }
$delivery = [ordered]@{identity=$identity;unsigned=$true;installer=[ordered]@{path=$setupPath;bytes=(Get-Item -LiteralPath $setupPath).Length;sha256=(Get-FileHash -LiteralPath $setupPath -Algorithm SHA256).Hash.ToLowerInvariant()};portableZip=[ordered]@{path=$zipPath;bytes=(Get-Item -LiteralPath $zipPath).Length;sha256=(Get-FileHash -LiteralPath $zipPath -Algorithm SHA256).Hash.ToLowerInvariant()};verifiedRuntimeFiles=$verified;backendChanged=$false;userProfileInstalled=$false;nativeAcceptance=$false;ownerAccepted=$false}
[IO.File]::WriteAllText((Join-Path $OutputDirectory 'delivery.json'), ($delivery | ConvertTo-Json -Depth 10) + "`n", (New-Object Text.UTF8Encoding($false)))
$delivery | ConvertTo-Json -Depth 10
