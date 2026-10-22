[CmdletBinding()]
param([string]$OutputRoot)
$ErrorActionPreference = 'Stop'
$repo = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..'))
if (!$OutputRoot) { $OutputRoot = Join-Path $repo ('build\desktop-release-installer-check-' + [Guid]::NewGuid().ToString('N').Substring(0,8)) }
$OutputRoot = [IO.Path]::GetFullPath($OutputRoot)
if (!$OutputRoot.StartsWith(($repo.TrimEnd('\') + '\build\'),[StringComparison]::OrdinalIgnoreCase) -or (Test-Path -LiteralPath $OutputRoot)) { throw 'NEW_WORKSPACE_BUILD_TEST_DIRECTORY_REQUIRED' }
New-Item -ItemType Directory -Path $OutputRoot | Out-Null
$powershell = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
$installRoot = Join-Path $OutputRoot 'installed'
$results = New-Object 'Collections.Generic.List[object]'
function Record([string]$Name, [bool]$Passed) { if (!$Passed) { throw ('INSTALLER_CHECK_FAILED: ' + $Name) }; $results.Add([PSCustomObject]@{name=$Name;passed=$true}) }
function New-Fixture([string]$Name, [int]$BuildNumber, [string]$Channel = 'development') {
  $packageRoot = Join-Path $OutputRoot $Name
  $payload = Join-Path $packageRoot 'Payload'
  New-Item -ItemType Directory -Path (Join-Path $payload 'data') -Force | Out-Null
  [IO.File]::WriteAllBytes((Join-Path $payload 'jentra_desktop.exe'), [Text.Encoding]::UTF8.GetBytes('SYNTHETIC_INSTALLER_FIXTURE_' + $BuildNumber))
  [IO.File]::WriteAllBytes((Join-Path $payload 'data\app.so'), [Text.Encoding]::UTF8.GetBytes('SYNTHETIC_APP_FIXTURE_' + $BuildNumber))
  [IO.File]::WriteAllBytes((Join-Path $payload 'vcruntime140.dll'), [Text.Encoding]::UTF8.GetBytes('SYNTHETIC_RUNTIME_FIXTURE_' + $BuildNumber))
  $sourceSha = ('{0:x64}' -f $BuildNumber)
  $manifest = [ordered]@{schemaVersion=1;product='Jentra OS';releaseId=('0.2.0-' + $BuildNumber + '-' + $Channel + '-' + $sourceSha.Substring(0,12));version=('0.2.0+' + $BuildNumber);buildNumber=$BuildNumber;channel=$Channel;sourceSha256=$sourceSha;executable='jentra_desktop.exe';files=@()}
  foreach ($relative in @('jentra_desktop.exe','data/app.so','vcruntime140.dll')) { $file = Get-Item -LiteralPath (Join-Path $payload $relative); $manifest.files += [ordered]@{path=$relative;bytes=$file.Length;sha256=(Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256).Hash.ToLowerInvariant()} }
  [IO.File]::WriteAllText((Join-Path $payload 'release-manifest.json'), ($manifest | ConvertTo-Json -Depth 8), (New-Object Text.UTF8Encoding($false)))
  foreach ($script in @('Install.ps1','Launch.ps1','Rollback.ps1','Uninstall.ps1')) { Copy-Item -LiteralPath (Join-Path $PSScriptRoot $script) -Destination (Join-Path $packageRoot $script) }
  return $packageRoot
}
function Invoke-Install([string]$PackageRoot, [bool]$ExpectedSuccess) {
  $savedPreference = $ErrorActionPreference
  try {
    $ErrorActionPreference = 'Continue'
    $output = & $powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PackageRoot 'Install.ps1') -PackageRoot $PackageRoot -InstallRoot $installRoot -NoShortcuts -NoRegistration 2>&1
    $actual = $LASTEXITCODE -eq 0
  } finally { $ErrorActionPreference = $savedPreference }
  if ($actual -ne $ExpectedSuccess) { $output | Out-String | Write-Output; throw 'UNEXPECTED_INSTALL_EXIT' }
}
function Invoke-Rollback([bool]$ExpectedSuccess) {
  $savedPreference = $ErrorActionPreference
  try {
    $ErrorActionPreference = 'Continue'
    $output = & $powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $installRoot 'Rollback.ps1') -InstallRoot $installRoot -ConfirmRollback 2>&1
    $actual = $LASTEXITCODE -eq 0
  } finally { $ErrorActionPreference = $savedPreference }
  if ($actual -ne $ExpectedSuccess) { $output | Out-String | Write-Output; throw 'UNEXPECTED_ROLLBACK_EXIT' }
  if ($actual) { return ($output | Out-String | ConvertFrom-Json) }
}
$first = New-Fixture 'first' 2200
Invoke-Install $first $true
$firstPointer = Get-Content -LiteralPath (Join-Path $installRoot 'current.json') -Raw | ConvertFrom-Json
Record 'first install selects verified release' ($firstPointer.buildNumber -eq 2200)
$second = New-Fixture 'second' 2201
Invoke-Install $second $true
$secondPointer = Get-Content -LiteralPath (Join-Path $installRoot 'current.json') -Raw | ConvertFrom-Json
$previousPointer = Get-Content -LiteralPath (Join-Path $installRoot 'previous.json') -Raw | ConvertFrom-Json
Record 'update selects new release' ($secondPointer.buildNumber -eq 2201)
Record 'update retains previous release and runtime bytes' ($previousPointer.buildNumber -eq 2200 -and (Test-Path -LiteralPath (Join-Path $installRoot ('versions\' + $previousPointer.releaseId + '\jentra_desktop.exe'))))
Invoke-Install $second $true
Record 'idempotent reinstall retains rollback pointer' ((Get-Content -LiteralPath (Join-Path $installRoot 'previous.json') -Raw | ConvertFrom-Json).buildNumber -eq 2200)
$verify = & $powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $installRoot 'Launch.ps1') -InstallRoot $installRoot -VerifyOnly
Record 'launcher resolves current bundle without starting fixture' (($LASTEXITCODE -eq 0) -and (($verify | Out-String | ConvertFrom-Json).version -eq '0.2.0+2201'))
Invoke-Install $first $false
Record 'older build refused' ((Get-Content -LiteralPath (Join-Path $installRoot 'current.json') -Raw | ConvertFrom-Json).buildNumber -eq 2201)
$corrupt = New-Fixture 'corrupt' 2202
[IO.File]::AppendAllText((Join-Path $corrupt 'Payload\data\app.so'), 'TAMPER')
Invoke-Install $corrupt $false
Record 'corrupt runtime refused without switching current' ((Get-Content -LiteralPath (Join-Path $installRoot 'current.json') -Raw | ConvertFrom-Json).buildNumber -eq 2201)
$unexpected = New-Fixture 'unexpected' 2202
[IO.File]::WriteAllText((Join-Path $unexpected 'Payload\extra.txt'), 'SYNTHETIC')
Invoke-Install $unexpected $false
Record 'unlisted runtime refused' ((Get-Content -LiteralPath (Join-Path $installRoot 'current.json') -Raw | ConvertFrom-Json).buildNumber -eq 2201)
$foreign = New-Fixture 'foreign' 2202 'production'
Invoke-Install $foreign $false
Record 'cross-channel update refused' ((Get-Content -LiteralPath (Join-Path $installRoot 'current.json') -Raw | ConvertFrom-Json).channel -eq 'development')
$traversal = New-Fixture 'traversal' 2202
$traversalPath = Join-Path $traversal 'Payload\release-manifest.json'
$traversalManifest = Get-Content -LiteralPath $traversalPath -Raw | ConvertFrom-Json
$traversalManifest.files[0].path = '../escape.exe'
[IO.File]::WriteAllText($traversalPath, ($traversalManifest | ConvertTo-Json -Depth 8), (New-Object Text.UTF8Encoding($false)))
Invoke-Install $traversal $false
Record 'path traversal refused' (!(Test-Path -LiteralPath (Join-Path $OutputRoot 'escape.exe')))
$currentBeforeRollback = (Get-FileHash -LiteralPath (Join-Path $installRoot 'current.json') -Algorithm SHA256).Hash
$retainedRuntime = Join-Path $installRoot ('versions\' + $previousPointer.releaseId + '\vcruntime140.dll')
[IO.File]::AppendAllText($retainedRuntime, 'TAMPER')
Invoke-Rollback $false
Record 'corrupt retained DLL refuses rollback without changing current pointer' ((Get-FileHash -LiteralPath (Join-Path $installRoot 'current.json') -Algorithm SHA256).Hash -eq $currentBeforeRollback)
Copy-Item -LiteralPath (Join-Path $first 'Payload\vcruntime140.dll') -Destination $retainedRuntime -Force
$heldLock = [IO.File]::Open((Join-Path $installRoot 'install.lock'), [IO.FileMode]::CreateNew, [IO.FileAccess]::Write, [IO.FileShare]::None)
try {
  Invoke-Rollback $false
  Record 'rollback refuses an active install lock and preserves its pointer and lock' (((Get-FileHash -LiteralPath (Join-Path $installRoot 'current.json') -Algorithm SHA256).Hash -eq $currentBeforeRollback) -and (Test-Path -LiteralPath (Join-Path $installRoot 'install.lock')))
  Invoke-Install $second $false
  Record 'installer and rollback use the same exclusive lock' ((Get-FileHash -LiteralPath (Join-Path $installRoot 'current.json') -Algorithm SHA256).Hash -eq $currentBeforeRollback)
} finally { $heldLock.Dispose(); Remove-Item -LiteralPath (Join-Path $installRoot 'install.lock') }
$rollback = Invoke-Rollback $true
Record 'explicit rollback selects retained bundle and verifies hashes' ($rollback.version -eq '0.2.0+2200')
$report = [ordered]@{kind='synthetic-installer-verification';atUtc=[DateTime]::UtcNow.ToString('o');checks=$results;passed=$results.Count;fixtureDirectory=$OutputRoot;actualApplicationLaunched=$false;userProfileInstalled=$false;shortcutsCreated=$false;registryChanged=$false;backendChanged=$false}
[IO.File]::WriteAllText((Join-Path $OutputRoot 'verification.json'), ($report | ConvertTo-Json -Depth 8) + "`n", (New-Object Text.UTF8Encoding($false)))
$report | ConvertTo-Json -Depth 8
