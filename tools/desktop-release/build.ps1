[CmdletBinding()]
param(
  [Parameter(Mandatory=$true)][string]$PublicConfigPath,
  [ValidateSet('development','production')][string]$Channel = 'development',
  [ValidatePattern('^\d+\.\d+\.\d+$')][string]$Version = '0.2.0',
  [ValidateRange(1,65535)][int]$BuildNumber = 2201,
  [string]$FlutterRoot = 'C:\src\flutter',
  [string]$ApprovedProductionProjectRef,
  [switch]$PrepareOnly
)
$ErrorActionPreference = 'Stop'
$repo = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..'))
$stamp = [DateTime]::UtcNow.ToString('yyyyMMdd-HHmmss') + '-' + [Guid]::NewGuid().ToString('N').Substring(0,4)
# MSBuild still has legacy MAX_PATH consumers in plugin tracking directories.
# Keep the checkout name short; the output/manifest retain the complete identity.
$snapshot = Join-Path $repo ('build\b' + [Guid]::NewGuid().ToString('N').Substring(0,6))
$output = Join-Path $repo ('build\desktop-release\' + $Version + '-' + $BuildNumber + '-' + $Channel + '-' + $stamp)
& node (Join-Path $PSScriptRoot 'prepare.mjs') $snapshot $output ([IO.Path]::GetFullPath($PublicConfigPath)) $Channel $Version $BuildNumber $ApprovedProductionProjectRef
if ($LASTEXITCODE -ne 0) { throw 'SOURCE_PREPARATION_FAILED' }
if ($PrepareOnly) { Write-Output ('Prepared: ' + $output); exit 0 }
$dart = Join-Path $FlutterRoot 'bin\cache\dart-sdk\bin\dart.exe'
$flutter = Join-Path $FlutterRoot 'bin\cache\flutter_tools.snapshot'
$app = Join-Path $snapshot 'apps\jentra_desktop'
$started = [DateTime]::UtcNow
Push-Location -LiteralPath $snapshot
try {
  & $dart $flutter --suppress-analytics pub get --offline --enforce-lockfile 2>&1 | Tee-Object -FilePath (Join-Path $output 'pub-get.log')
  if ($LASTEXITCODE -ne 0) { throw 'LOCKED_DEPENDENCY_RESOLUTION_FAILED' }
} finally { Pop-Location }
Push-Location -LiteralPath $app
try {
  & $dart $flutter --suppress-analytics build windows --release --no-pub --target=lib/main.dart ('--build-name=' + $Version) ('--build-number=' + $BuildNumber) ('--dart-define-from-file=' + (Join-Path $snapshot 'public-build-config.json')) 2>&1 | Tee-Object -FilePath (Join-Path $output 'windows-build.log')
  if ($LASTEXITCODE -ne 0) { throw 'WINDOWS_RELEASE_BUILD_FAILED' }
} finally { Pop-Location }
& (Join-Path $snapshot 'tools\desktop-release\package.ps1') -BundlePath (Join-Path $app 'build\windows\x64\runner\Release') -OutputDirectory $output
if ($LASTEXITCODE -and $LASTEXITCODE -ne 0) { throw 'WINDOWS_PACKAGING_FAILED' }
[PSCustomObject]@{outputDirectory=$output;sourceSnapshot=$snapshot;startedAtUtc=$started.ToString('o');finishedAtUtc=[DateTime]::UtcNow.ToString('o');backendChanged=$false;installedToUserProfile=$false} | ConvertTo-Json
