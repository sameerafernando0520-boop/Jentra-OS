[CmdletBinding()]
param(
  [Parameter(Mandatory=$true)][string]$PublicConfigPath,
  [ValidatePattern('^\d+\.\d+\.\d+$')][string]$Version='0.3.1',
  [ValidateRange(1,65535)][int]$BuildNumber=2301,
  [string]$FlutterRoot='C:\src\flutter'
)
$ErrorActionPreference='Stop'
$repo=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..'))
$stamp=[DateTime]::UtcNow.ToString('yyyyMMdd-HHmmss')+'-'+[Guid]::NewGuid().ToString('N').Substring(0,4)
$snapshot=Join-Path $repo ('build\w'+[Guid]::NewGuid().ToString('N').Substring(0,6))
$output=Join-Path $repo ('build\web-release\'+$Version+'-'+$BuildNumber+'-development-'+$stamp)
& node (Join-Path $repo 'tools\desktop-release\prepare.mjs') $snapshot $output ([IO.Path]::GetFullPath($PublicConfigPath)) development $Version $BuildNumber
if ($LASTEXITCODE -ne 0) { throw 'WEB_SOURCE_PREPARATION_FAILED' }
$dart=Join-Path $FlutterRoot 'bin\cache\dart-sdk\bin\dart.exe'
$flutter=Join-Path $FlutterRoot 'bin\cache\flutter_tools.snapshot'
Push-Location -LiteralPath $snapshot
try {
  $previousPreference=$ErrorActionPreference
  try {
    # Windows PowerShell reports native stderr as ErrorRecord objects. Flutter
    # warnings must remain visible without replacing its authoritative exit code.
    $ErrorActionPreference='Continue'
    & $dart $flutter --suppress-analytics pub get --offline --enforce-lockfile 2>&1 | ForEach-Object { $_.ToString() } | Tee-Object -FilePath (Join-Path $output 'pub-get.log')
    $dependencyExit=$LASTEXITCODE
  } finally { $ErrorActionPreference=$previousPreference }
  if ($dependencyExit -ne 0) { throw 'WEB_LOCKED_DEPENDENCIES_FAILED' }
} finally { Pop-Location }
Push-Location -LiteralPath (Join-Path $snapshot 'apps\jentra_desktop')
try {
  $previousPreference=$ErrorActionPreference
  try {
    $ErrorActionPreference='Continue'
    & $dart $flutter --suppress-analytics build web --release --no-pub --no-web-resources-cdn --no-wasm-dry-run --pwa-strategy=none ('--build-name='+$Version) ('--build-number='+$BuildNumber) ('--dart-define-from-file='+(Join-Path $snapshot 'public-build-config.json')) 2>&1 | ForEach-Object { $_.ToString() } | Tee-Object -FilePath (Join-Path $output 'web-build.log')
    $buildExit=$LASTEXITCODE
  } finally { $ErrorActionPreference=$previousPreference }
  if ($buildExit -ne 0) { throw 'WEB_RELEASE_BUILD_FAILED' }
} finally { Pop-Location }
& (Join-Path $snapshot 'tools\web-release\package.ps1') -OutputDirectory $output
