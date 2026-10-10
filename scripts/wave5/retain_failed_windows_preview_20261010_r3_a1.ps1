# Root invokes only when every SDK job is idle. Preserve the exact owned failed
# output and stale cooperative lock before a genuinely new Preview build attempt.
$ErrorActionPreference='Stop'
$testRoot=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..'))
$testSnapshot=Join-Path $testRoot 'build/w5win10r3/preview'
$testSource=[IO.Path]::GetFullPath((Join-Path $testSnapshot 'apps/jentra_desktop/build/windows'))
$testRetained=[IO.Path]::GetFullPath((Join-Path $testSnapshot 'apps/jentra_desktop/build/windows-attempt-a1'))
$testLock=[IO.Path]::GetFullPath((Join-Path $testRoot 'build/wave5-flutter-job.lock'))
$testRetainedLock=[IO.Path]::GetFullPath((Join-Path $testRoot 'build/wave5-flutter-job-attempt-preview-build-a1.retained.lock'))
$testRecord=Join-Path $testRoot 'docs/verification/wave5/windows-test-preview-build-retention-20261010-r3-a1.json'
$testStage=Join-Path $testRoot 'docs/verification/wave5/windows-test-preview-build-20261010-r3-a1.json'
$testLog=Join-Path $testRoot 'docs/verification/wave5/windows-test-preview-build-20261010-r3-a1.log'
$testToolguard=Join-Path $testRoot 'docs/verification/wave5/windows-test-preview-build-toolguard-20261010-r3-a1.json'
function Get-TestSha256([string]$Path){$testStream=[IO.File]::OpenRead($Path);$testHasher=[Security.Cryptography.SHA256]::Create();try{return ([BitConverter]::ToString($testHasher.ComputeHash($testStream))).Replace('-','').ToLowerInvariant()}finally{$testStream.Dispose();$testHasher.Dispose()}}
function Assert-TestWorkspacePath([string]$Path){
 $testFull=[IO.Path]::GetFullPath($Path)
 if(-not $testFull.StartsWith($testRoot + [IO.Path]::DirectorySeparatorChar,[StringComparison]::OrdinalIgnoreCase)){throw 'RETENTION_PATH_OUTSIDE_WORKSPACE'}
 $testParent=$testFull
 while($testParent -ne $testRoot){
  if(Test-Path -LiteralPath $testParent){if((Get-Item -LiteralPath $testParent).Attributes -band [IO.FileAttributes]::ReparsePoint){throw 'RETENTION_PATH_LINK_REFUSED'}}
  $testParent=[IO.Path]::GetDirectoryName($testParent)
 }
}
foreach($testPath in @($testSource,$testRetained,$testLock,$testRetainedLock,$testRecord)){Assert-TestWorkspacePath $testPath}
foreach($testOutput in @($testRetained,$testRetainedLock,$testRecord)){if(Test-Path -LiteralPath $testOutput){throw 'NEW_RETENTION_OUTPUT_REQUIRED'}}
if(-not (Test-Path -LiteralPath $testSource) -or -not (Test-Path -LiteralPath $testLock)){throw 'EXACT_OWNED_FAILED_BUILD_AND_STALE_LOCK_REQUIRED'}
$testFailed=Get-Content -LiteralPath $testToolguard -Raw | ConvertFrom-Json
if($testFailed.mode -ne 'Preview' -or $testFailed.stage -ne 'build' -or $testFailed.attempt -ne 'a1' -or $testFailed.status -ne 'failed'){throw 'EXACT_FAILED_A1_TOOLGUARD_REQUIRED'}
if((Get-Item -LiteralPath $testStage).Length -ne 0 -or -not ([IO.File]::ReadAllText($testLog).Contains('Built build'))){throw 'EXACT_A1_COMPILE_WITH_FAILED_EMPTY_RECORD_REQUIRED'}
# An active handle prevents exclusive open. Never remove or move an active lock.
$testLockProbe=[IO.File]::Open($testLock,[IO.FileMode]::Open,[IO.FileAccess]::Read,[IO.FileShare]::None)
$testLockProbe.Dispose()
$testLockItem=Get-Item -LiteralPath $testLock
$testLockHash=Get-TestSha256 $testLock
$testState=[ordered]@{startedAt=[DateTime]::UtcNow.ToString('o');revision='r3';mode='Preview';attempt='a1';status='retaining';
 source=$testSource;retained=$testRetained;lock=$testLock;retainedLock=$testRetainedLock;lockBytes=$testLockItem.Length;lockCreatedAt=$testLockItem.CreationTimeUtc.ToString('o');lockSha256=$testLockHash;
 actualA1Log='docs/verification/wave5/windows-test-preview-build-20261010-r3-a1.log';actualA1LogSha256=(Get-TestSha256 $testLog);
 failedToolguard='docs/verification/wave5/windows-test-preview-build-toolguard-20261010-r3-a1.json';failedToolguardSha256=(Get-TestSha256 $testToolguard);
 emptyStageRecord='docs/verification/wave5/windows-test-preview-build-20261010-r3-a1.json';emptyStageRecordSha256=(Get-TestSha256 $testStage);
 compileMessageObserved=$true;durableSdkExitEvidence=$false;qualifiedBuild=$false;buildMoved=$false;lockMoved=$false;failure=$null;
 boundary='Exact root-owned failed output is retained in the same snapshot. No new successful SDK exit is inferred; acceptance stores and prior artifacts are untouched.'}
$testClaim=[IO.File]::Open($testRecord,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::None);$testClaim.Dispose()
try {
 # Checked absolute source and destination are both fixed under the same owned
 # preview build directory. No recursive delete or cross-shell command is used.
 Move-Item -LiteralPath $testSource -Destination $testRetained -ErrorAction Stop
 $testState.buildMoved=$true
 if((Get-TestSha256 $testLock) -ne $testLockHash){throw 'STALE_LOCK_CHANGED_ABORT_RETENTION'}
 Move-Item -LiteralPath $testLock -Destination $testRetainedLock -ErrorAction Stop
 $testState.lockMoved=$true
 $testState.status='retained'
} catch {$testState.status='failed';$testState.failure=$_.Exception.Message}
finally {
 $testState.finishedAt=[DateTime]::UtcNow.ToString('o')
 [IO.File]::WriteAllText($testRecord,(ConvertTo-Json -InputObject $testState -Depth 12) + "`n",[Text.UTF8Encoding]::new($false))
}
ConvertTo-Json -InputObject $testState -Depth 12
if($testState.status -ne 'retained'){throw 'RETENTION_INCOMPLETE_PRESERVE_PARTIAL_RECORD'}
