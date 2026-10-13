# NEW r5 successor; preserved r4 predecessor scripts/wave5/observe_windows_userflow_storage_20261010_r4.ps1 SHA-256 b4bd43c95063a25c2d27e39bd56d3f7a7a9269b2164e602168bd351580dc2e09.
# NEW r5 variant; preserved predecessor observe_windows_userflow_storage_20261010_r3.ps1 SHA-256 c4f826afcea35f5a3ad089f3ee3524d0cd30e35900bf6ae85f15025efc114994.
$ErrorActionPreference='Stop'
$testRoot=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..'))
$testOutput=Join-Path $testRoot 'docs/verification/wave5/windows-userflow-storage-before-20261010-r5.json'
if(Test-Path -LiteralPath $testOutput){throw 'NEW_PRELAUNCH_OBSERVATION_REQUIRED'}
$testSupport=[Environment]::GetFolderPath([Environment+SpecialFolder]::ApplicationData)
$testCache=[Environment]::GetFolderPath([Environment+SpecialFolder]::LocalApplicationData)
if(-not $testSupport -or -not $testCache){throw 'WINDOWS_APPLICATION_DIRECTORY_BASES_REQUIRED'}
$testIdentities=@()
$testPaths=@()
foreach($testMode in @('Preview','Connected')){
 $testExe=Join-Path $testRoot ('dist/Jentra OS Windows Test 20261010 r5/' + $testMode + '/Jentra_OS.exe')
 $testIdentity=& (Join-Path $PSScriptRoot 'inspect_windows_runner_identity_20261010_r5.ps1') -Mode $testMode -Executable $testExe | ConvertFrom-Json
 $testIdentities += $testIdentity
 foreach($testLocation in @(@{kind='applicationSupport';base=$testSupport},@{kind='applicationCache';base=$testCache})){
  $testExpected=[IO.Path]::GetFullPath((Join-Path $testLocation.base ('com.jentra.test/JentraOS_WindowsTest_20261010-r5_' + $testMode)))
  if(-not $testExpected.StartsWith([IO.Path]::GetFullPath($testLocation.base) + [IO.Path]::DirectorySeparatorChar,[StringComparison]::OrdinalIgnoreCase)){throw 'EXPECTED_PRODUCT_PATH_ESCAPE'}
  # Test-Path checks only these exact new names. No directory/file contents or
  # another product's session, token, key or acceptance store is read.
  $testPaths += [pscustomobject]@{mode=$testMode;kind=$testLocation.kind;expectedPath=$testExpected;exists=(Test-Path -LiteralPath $testExpected)}
 }
}
$testPassed=@($testPaths | Where-Object {$_.exists}).Count -eq 0
$testRecord=[pscustomobject]@{observedAt=[DateTime]::UtcNow.ToString('o');revision='r5';date='20261010';kind='exact-product-prelaunch-path-existence';
 method='Read-only FileVersionInfo and Test-Path for four exact expected new product directories';executableIdentities=$testIdentities;paths=$testPaths;allExpectedPathsAbsent=$testPassed;
 pathContentsRead=$false;defaultAcceptanceStoresRead=$false;localStoresCopied=$false;OSUserCreated=$false;nativeLaunched=$false;
 expectedNativeDirectoriesObservedAfterLaunch=$false;boundary='Expected unique product paths only. Separate products on the same Windows account do not create an OS security boundary; actual postlaunch path behavior remains unverified.'}
$testJson=$testRecord | ConvertTo-Json -Depth 12
$testStream=[IO.File]::Open($testOutput,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::None)
try {$testWriter=[IO.StreamWriter]::new($testStream,[Text.UTF8Encoding]::new($false));$testWriter.WriteLine($testJson);$testWriter.Flush()}
finally {if($testWriter){$testWriter.Dispose()}else{$testStream.Dispose()}}
$testJson
if(-not $testPassed){throw 'EXISTING_ISOLATED_PRODUCT_PATH_COLLISION_LAUNCH_BLOCKED'}
