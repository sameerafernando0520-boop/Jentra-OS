#requires -Version 5.1
# Synthetic files only. Never opens a real signing directory or invokes a build.
$ErrorActionPreference = 'Stop'
$repo = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../..'))
$helper = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../release_artifact_provenance.ps1'))
. $helper
$testRoot = Join-Path $repo ('build/employee-release-verification-' + [Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $testRoot | Out-Null
$fixture = Join-Path $testRoot 'source'
New-Item -ItemType Directory -Path $fixture | Out-Null
$results = New-Object 'Collections.Generic.List[object]'
function Check([string]$Name,[bool]$Passed) {
    if (!$Passed) { throw ('RELEASE_PROVENANCE_CHECK_FAILED: ' + $Name) }
    $results.Add([ordered]@{name=$Name;passed=$true})
}
function Refuses([scriptblock]$Action) { try { & $Action | Out-Null; return $false } catch { return $true } }
function Put([string]$Relative,[string]$Contents) {
    $path = Join-Path $fixture $Relative
    $parent = Split-Path -Parent $path
    if (!(Test-Path -LiteralPath $parent)) { New-Item -ItemType Directory -Path $parent -Force | Out-Null }
    [IO.File]::WriteAllText($path,$Contents)
}
foreach ($name in @('pubspec.yaml','pubspec.lock','apps/jentra_employee/pubspec.yaml','.dart_tool/package_config.json',
    'scripts/employee/build_production_release.ps1','scripts/employee/release_artifact_provenance.ps1',
    'scripts/android/assert_flutter_apk_abi.ps1',
    'apps/jentra_employee/lib/main.dart','apps/jentra_employee/android/app/build.gradle.kts',
    'packages/example/pubspec.yaml','packages/example/lib/shared.dart','packages/example/assets/icon.txt')) { Put $name ('SYNTHETIC_' + $name) }
foreach ($name in @('apps/jentra_employee/android/.env.private','apps/jentra_employee/android/key.properties',
    'apps/jentra_employee/android/release.p12','apps/jentra_employee/android/local.properties',
    'apps/jentra_employee/android/.gradle/generated.txt','apps/jentra_employee/android/app/build/generated.txt',
    'apps/jentra_employee/android/.kotlin/sessions/compiler.salive',
    'apps/jentra_employee/android/hs_err_pid42.log','apps/jentra_employee/android/replay_pid42.log',
    'apps/jentra_employee/android/java_pid42.hprof',
    'apps/jentra_employee/android/app/src/main/java/io/flutter/plugins/GeneratedPluginRegistrant.java')) { Put $name 'SYNTHETIC_EXCLUDED_VALUE' }
$config = Join-Path $testRoot 'public-config.json'
[IO.File]::WriteAllText($config,'SYNTHETIC_CONFIG_VALUE')
$tool = Join-Path $testRoot 'mock-tool.exe'
[IO.File]::WriteAllText($tool,'SYNTHETIC_TOOL_BYTES')
$tools = [ordered]@{mockTool=$tool}
$provenance = New-EmployeeReleaseProvenance $fixture $config $tools
$paths = @($provenance.sourceFiles | ForEach-Object { $_.path })
Check 'actual employee, Android, shared assets and dependency-lock inputs are hashed' ($paths -contains 'apps/jentra_employee/lib/main.dart' -and $paths -contains 'apps/jentra_employee/android/app/build.gradle.kts' -and $paths -contains 'packages/example/assets/icon.txt' -and $paths -contains 'pubspec.lock' -and $paths -contains '.dart_tool/package_config.json')
Check 'the APK ABI release guard is hashed' ($paths -contains 'scripts/android/assert_flutter_apk_abi.ps1')
Check 'generated output and local signing/configuration files are excluded' (@($paths | Where-Object { $_ -match 'private|properties|release\.p12|generated|GeneratedPluginRegistrant' }).Count -eq 0)
Check 'manifest stores hashes, not source, tool or configuration contents' (($provenance | ConvertTo-Json -Depth 10) -notmatch 'SYNTHETIC_')
Check 'JVM crash diagnostics stay outside release provenance' (@($paths | Where-Object { $_ -match 'hs_err_pid|replay_pid|java_pid' }).Count -eq 0)
$again = New-EmployeeReleaseProvenance $fixture $config $tools
Check 'unchanged input bytes produce stable provenance' ($again.sourceSha256 -eq $provenance.sourceSha256 -and $again.configurationSha256 -eq $provenance.configurationSha256 -and $again.toolchainSha256 -eq $provenance.toolchainSha256)
Assert-EmployeeReleaseInputsUnchanged $provenance $fixture $config $tools
Put 'apps/jentra_employee/lib/main.dart' 'SYNTHETIC_CHANGED_SOURCE'
Check 'source mutation blocks publication' (Refuses { Assert-EmployeeReleaseInputsUnchanged $provenance $fixture $config $tools })
$provenance = New-EmployeeReleaseProvenance $fixture $config $tools
Put 'apps/jentra_employee/lib/new_source.dart' 'SYNTHETIC_NEW_SOURCE'
Check 'new source membership blocks publication' (Refuses { Assert-EmployeeReleaseInputsUnchanged $provenance $fixture $config $tools })
$provenance = New-EmployeeReleaseProvenance $fixture $config $tools
Put '.dart_tool/package_config.json' 'SYNTHETIC_CHANGED_RESOLUTION'
Check 'resolved dependency mutation blocks publication' (Refuses { Assert-EmployeeReleaseInputsUnchanged $provenance $fixture $config $tools })
$provenance = New-EmployeeReleaseProvenance $fixture $config $tools
[IO.File]::WriteAllText($config,'SYNTHETIC_CHANGED_CONFIG')
Check 'public configuration mutation blocks publication' (Refuses { Assert-EmployeeReleaseInputsUnchanged $provenance $fixture $config $tools })
$provenance = New-EmployeeReleaseProvenance $fixture $config $tools
[IO.File]::WriteAllText($tool,'SYNTHETIC_CHANGED_TOOL')
Check 'toolchain mutation blocks publication' (Refuses { Assert-EmployeeReleaseInputsUnchanged $provenance $fixture $config $tools })

$deliverables = Join-Path $testRoot 'deliverables'
$first = New-EmployeeReleaseDirectory $deliverables '0.5.0' 7 'fixture'
Check 'release path includes explicit version and build number' ((Split-Path -Leaf $first) -eq '0.5.0-7-signed-production-identity-fixture')
[IO.File]::WriteAllText((Join-Path $first 'keep.txt'),'SYNTHETIC_PREVIOUS_ARTIFACT')
Check 'existing release directory is refused and preserved' ((Refuses { New-EmployeeReleaseDirectory $deliverables '0.5.0' 7 'fixture' }) -and (Get-Content -LiteralPath (Join-Path $first 'keep.txt') -Raw) -eq 'SYNTHETIC_PREVIOUS_ARTIFACT')
$second = New-EmployeeReleaseDirectory $deliverables '0.5.0' 7
$third = New-EmployeeReleaseDirectory $deliverables '0.5.0' 7
Check 'same version rebuilds receive separate immutable directories' ($second -ne $third -and $second -ne $first)

# Two independent PowerShell processes contend on the exact directory name.
$worker = Join-Path $testRoot 'race-worker.ps1'
[IO.File]::WriteAllText($worker,@'
param($Helper,$Root,$Result)
$ErrorActionPreference='Stop'
. $Helper
try { $null=New-EmployeeReleaseDirectory $Root '0.5.0' 8 'race'; [IO.File]::WriteAllText($Result,'created') }
catch { [IO.File]::WriteAllText($Result,'refused') }
'@)
$powershell = Join-Path $env:SystemRoot 'System32/WindowsPowerShell/v1.0/powershell.exe'
$processes = @()
foreach ($number in @(1,2)) {
    $result = Join-Path $testRoot ('race-' + $number + '.txt')
    $arguments = @('-NoProfile','-ExecutionPolicy','Bypass','-File',('"'+$worker+'"'),('"'+$helper+'"'),('"'+$deliverables+'"'),('"'+$result+'"'))
    $processes += Start-Process -FilePath $powershell -ArgumentList $arguments -WindowStyle Hidden -PassThru
}
foreach ($process in $processes) { if (!$process.WaitForExit(30000)) { throw 'Synthetic directory race timed out.' } }
$race = @((Get-Content -LiteralPath (Join-Path $testRoot 'race-1.txt') -Raw),(Get-Content -LiteralPath (Join-Path $testRoot 'race-2.txt') -Raw))
Check 'concurrent directory creation has one winner and one refusal' (@($race | Where-Object { $_ -eq 'created' }).Count -eq 1 -and @($race | Where-Object { $_ -eq 'refused' }).Count -eq 1)

$mockApk = Join-Path $testRoot 'mock.apk'
[IO.File]::WriteAllText($mockApk,'SYNTHETIC_VERIFIED_BUILD_OUTPUT')
$copiedPath = Join-Path $first 'mock.apk'
$copied = Copy-EmployeeReleaseArtifact $mockApk $copiedPath
Check 'synthetic verified output retains exact bytes and hash when copied' ($copied.sha256 -eq (Get-FileHash -LiteralPath $mockApk -Algorithm SHA256).Hash.ToLowerInvariant() -and (Get-Content -LiteralPath $copiedPath -Raw) -eq 'SYNTHETIC_VERIFIED_BUILD_OUTPUT')
[IO.File]::WriteAllText($mockApk,'SYNTHETIC_REPLACEMENT')
Check 'artifact overwrite is refused and prior bytes preserved' ((Refuses { Copy-EmployeeReleaseArtifact $mockApk $copiedPath }) -and (Get-Content -LiteralPath $copiedPath -Raw) -eq 'SYNTHETIC_VERIFIED_BUILD_OUTPUT')
$manifest = Join-Path $first 'release-manifest.json'
Write-EmployeeReleaseManifest $manifest ([ordered]@{provenance=$provenance;actualDeviceAcceptance=$false;storePublication=$false})
$manifestBefore = (Get-FileHash -LiteralPath $manifest -Algorithm SHA256).Hash
Check 'manifest overwrite is refused and prior evidence preserved' ((Refuses { Write-EmployeeReleaseManifest $manifest @{changed=$true} }) -and (Get-FileHash -LiteralPath $manifest -Algorithm SHA256).Hash -eq $manifestBefore)
Check 'manifest retains unverified acceptance and publication states' (!(Get-Content -LiteralPath $manifest -Raw | ConvertFrom-Json).actualDeviceAcceptance -and !(Get-Content -LiteralPath $manifest -Raw | ConvertFrom-Json).storePublication)
$report = [ordered]@{syntheticOnly=$true;signingMaterialOpened=$false;buildInvoked=$false;checks=$results;testDirectory=$testRoot}
[IO.File]::WriteAllText((Join-Path $testRoot 'verification.json'),($report | ConvertTo-Json -Depth 10))
$report | ConvertTo-Json -Depth 10
