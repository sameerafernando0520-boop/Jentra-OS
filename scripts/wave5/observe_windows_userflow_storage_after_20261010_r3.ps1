$ErrorActionPreference='Stop'
$testRoot=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..'))
$testBeforePath=Join-Path $testRoot 'docs/verification/wave5/windows-userflow-storage-before-20261010-r3.json'
$testAfterPath=Join-Path $testRoot 'docs/verification/wave5/windows-userflow-storage-after-20261010-r3.json'
if(Test-Path -LiteralPath $testAfterPath){throw 'NEW_PATH_OBSERVATION_REQUIRED'}
$testBefore=Get-Content -LiteralPath $testBeforePath -Raw | ConvertFrom-Json
if($testBefore.allExpectedPathsAbsent -ne $true -or $testBefore.paths.Count -ne 4){throw 'EXACT_PRELAUNCH_FOUR_PATHS_REQUIRED'}
$testResults=@()
foreach($testPath in $testBefore.paths){
 $testBase=if($testPath.kind -eq 'applicationSupport'){[Environment]::GetFolderPath([Environment+SpecialFolder]::ApplicationData)}else{[Environment]::GetFolderPath([Environment+SpecialFolder]::LocalApplicationData)}
 $testExpected=[IO.Path]::GetFullPath((Join-Path $testBase ('com.jentra.test/JentraOS_WindowsTest_20261010-r3_' + $testPath.mode)))
 if($testPath.expectedPath -ne $testExpected){throw 'EXACT_ISOLATED_PRODUCT_PATH_REQUIRED'}
 $testResults += [pscustomobject]@{mode=$testPath.mode;kind=$testPath.kind;expectedPath=$testExpected;beforeExists=$false;afterExists=(Test-Path -LiteralPath $testExpected)}
}
$testRecord=[pscustomobject]@{observedAt=[DateTime]::UtcNow.ToString('o');kind='exact-product-postlaunch-path-existence';revision='r3';paths=$testResults;
 method='Test-Path on the same four exact product directories after ordinary Preview user actions';pathContentsRead=$false;defaultAcceptanceStoresRead=$false;
 localStoresCopied=$false;OSUserCreated=$false;authenticatedNative=$false;formalRuntimeProfileProvisioned=$false;
 boundary='Directory existence only; no file contents, credentials, sessions or other product directories inspected. Native UI evidence is recorded separately.'}
$testStream=[IO.File]::Open($testAfterPath,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::None)
try{$testWriter=[IO.StreamWriter]::new($testStream,[Text.UTF8Encoding]::new($false));$testWriter.WriteLine(($testRecord|ConvertTo-Json -Depth 12));$testWriter.Flush()}
finally{if($testWriter){$testWriter.Dispose()}else{$testStream.Dispose()}}
$testRecord|ConvertTo-Json -Depth 12
