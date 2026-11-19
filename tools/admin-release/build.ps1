[CmdletBinding()]
param(
  [string]$PublicConfigPath,
  [string]$ApprovedProjectRef,
  [ValidatePattern('^\d+\.\d+\.\d+$')][string]$Version = '0.1.0',
  [ValidateRange(1,65535)][int]$BuildNumber = 1,
  [string]$FlutterRoot = 'C:\src\flutter',
  [switch]$PrepareOnly
)
$ErrorActionPreference = 'Stop'
$repo = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..'))
$stamp = [DateTime]::UtcNow.ToString('yyyyMMdd-HHmmss') + '-' + [Guid]::NewGuid().ToString('N').Substring(0,4)
$snapshot = Join-Path $repo ('build\a' + [Guid]::NewGuid().ToString('N').Substring(0,5))
$output = Join-Path $repo ('build\admin-release\' + $Version + '-' + $BuildNumber + '-' + $stamp)
$config = if ($PublicConfigPath) { [IO.Path]::GetFullPath($PublicConfigPath) } else { '-' }
$project = if ($ApprovedProjectRef) { $ApprovedProjectRef } else { '-' }
& node (Join-Path $PSScriptRoot 'prepare.mjs') $snapshot $output $config $project $Version $BuildNumber
if ($LASTEXITCODE -ne 0) { throw 'ADMIN_SOURCE_PREPARATION_FAILED' }
if ($PrepareOnly) { return }

$dart = Join-Path $FlutterRoot 'bin\cache\dart-sdk\bin\dart.exe'
$flutter = Join-Path $FlutterRoot 'bin\cache\flutter_tools.snapshot'
$app = Join-Path $snapshot 'apps\jentra_desktop'
Push-Location -LiteralPath $snapshot
try {
  & $dart $flutter --suppress-analytics --no-version-check pub get --offline --enforce-lockfile 2>&1 | Tee-Object -FilePath (Join-Path $output 'pub-get.log')
  if ($LASTEXITCODE -ne 0) { throw 'LOCKED_DEPENDENCY_RESOLUTION_FAILED' }
} finally { Pop-Location }
Push-Location -LiteralPath $app
try {
  & $dart $flutter --suppress-analytics --no-version-check build windows --release --no-pub --target=lib/main_admin.dart ('--build-name=' + $Version) ('--build-number=' + $BuildNumber) ('--dart-define-from-file=' + (Join-Path $snapshot 'public-build-config.json')) 2>&1 | Tee-Object -FilePath (Join-Path $output 'windows-build.log')
  if ($LASTEXITCODE -ne 0) { throw 'ADMIN_WINDOWS_RELEASE_BUILD_FAILED' }
} finally { Pop-Location }
& (Join-Path $snapshot 'tools\admin-release\package.ps1') -BundlePath (Join-Path $app 'build\windows\x64\runner\Release') -OutputDirectory $output
