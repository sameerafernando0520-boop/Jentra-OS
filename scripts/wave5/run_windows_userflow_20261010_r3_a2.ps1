param(
 [Parameter(Mandatory=$true)][ValidateSet('Preview','Connected')][string]$Mode,
 [Parameter(Mandatory=$true)][ValidateSet('pubget','analyzer','startupTests','keyboardTests','accountingTests','authTests','cashTests','platformAll','desktopAll','build')][string]$Stage,
 [ValidatePattern('^[a-z][a-z0-9]{0,8}$')][string]$Attempt = 'a2',
 [switch]$Offline
)
$ErrorActionPreference = 'Stop'
$testRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..'))
$testSnapshot = Join-Path $testRoot ('build/w5win10r3/' + $Mode.ToLowerInvariant())
$testWorking = $testSnapshot
$testSdk = 'C:\src\flutter\bin\cache\dart-sdk\bin\dart.exe'
$testFlutterTool = 'C:\src\flutter\bin\cache\flutter_tools.snapshot'
$testChecker = Join-Path $testRoot 'scripts/wave5/prepare_windows_userflow_20261010_r3.mjs'
$testWrapper = Join-Path $testRoot 'scripts/wave5/run_flutter_with_capture_env.mjs'
$testBase = 'docs/verification/wave5/windows-test-' + $Mode.ToLowerInvariant() + '-' + $Stage + '-20261010-r3-' + $Attempt
$testLog = Join-Path $testRoot ($testBase + '.log')
$testRecord = Join-Path $testRoot ($testBase + '.json')
$testSdkExitPath = Join-Path $testRoot ($testBase + '.sdk-exit.json')
$testLockPath = Join-Path $testRoot 'build/wave5-flutter-job.lock'
foreach ($testOutput in @($testLog,$testRecord,$testSdkExitPath)) {
 if (Test-Path -LiteralPath $testOutput) { throw 'NEW_STAGE_OUTPUT_REQUIRED_EXISTING_EVIDENCE_PRESERVED' }
}
# This lock cooperates with this runner. Root must also serialize older/manual
# SDK invocations; no script may remove a lock held by another invocation.
$testLock = $null
try { $testLock = [IO.File]::Open($testLockPath,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::None) }
catch { throw 'SERIALIZED_SDK_JOB_LOCK_REQUIRED_PRESERVE_EXISTING_LOCK' }
$testStarted = [DateTime]::UtcNow
$testExit = 1
$testFailure = $null
$testBefore = $null
$testAfter = $null
$testClaimed = $false
$testPushed = $false
$testExecuted = $false
$testSdkExit = $null
function Get-TestSha256([string]$Path) {
 $testHashStream=[IO.File]::OpenRead($Path)
 $testHasher=[Security.Cryptography.SHA256]::Create()
 try { return ([BitConverter]::ToString($testHasher.ComputeHash($testHashStream))).Replace('-','').ToLowerInvariant() }
 finally { $testHashStream.Dispose();$testHasher.Dispose() }
}
function Write-TestJson([string]$Path,$Value,[switch]$New) {
 $testJsonText=$Value | ConvertTo-Json -Depth 18
 $testFileMode=if($New){[IO.FileMode]::CreateNew}else{[IO.FileMode]::Truncate}
 $testJsonStream=[IO.File]::Open($Path,$testFileMode,[IO.FileAccess]::Write,[IO.FileShare]::None)
 $testJsonWriter=[IO.StreamWriter]::new($testJsonStream,[Text.UTF8Encoding]::new($false))
 try {$testJsonWriter.WriteLine($testJsonText);$testJsonWriter.Flush();$testJsonStream.Flush($true)}
 finally {$testJsonWriter.Dispose()}
}
$testArguments = @()
function Test-SourceGuard {
 $testGuardArguments = @($testChecker,'verify',$Mode)
 if ($Mode -eq 'Connected' -and $Stage -eq 'build') { $testGuardArguments += '--config' }
 $testGuardOutput = & node @testGuardArguments
 if ($LASTEXITCODE -ne 0) { throw 'SOURCE_OR_CONFIG_GUARD_FAILED' }
 $testParsed = ($testGuardOutput -join "`n") | ConvertFrom-Json
 if ($testParsed.currentSourceMatches -ne $true -or $testParsed.snapshotSourceMatches -ne $true -or $testParsed.runnerOverlayCount -ne 3) { throw 'SOURCE_GUARD_INCOMPLETE' }
 return $testParsed
}
try {
 $testBefore = Test-SourceGuard
 # Reserve both unique artifacts before launching any SDK process.
 $testClaim = [IO.File]::Open($testRecord,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::None)
 $testClaim.Dispose()
 $testClaimed = $true
 $testLogClaim = [IO.File]::Open($testLog,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::None)
 $testLogClaim.Dispose()
 foreach ($testCaptureName in @('W5_CASH_FRAME_DIR','W5_MODEL_FRAME_DIR','W5_AUTH_FRAME_DIR')) {
  [Environment]::SetEnvironmentVariable($testCaptureName,$null,'Process')
 }
 switch ($Stage) {
  'pubget' { $testArguments = @($testFlutterTool,'--suppress-analytics','pub','get'); if($Offline){$testArguments += '--offline'} }
  'analyzer' { $testArguments = @('--suppress-analytics','analyze','apps/jentra_desktop/lib','apps/jentra_desktop/test','packages/jentra_domain/lib','packages/jentra_platform/lib','packages/jentra_design_system/lib') }
  'startupTests' { $testWorking = Join-Path $testSnapshot 'apps/jentra_desktop'; $testArguments = @($testFlutterTool,'--suppress-analytics','test','--no-pub','--concurrency=1','--reporter=expanded','test/main_preview_startup_test.dart','--name=unconfigured startup') }
  'keyboardTests' { $testWorking = Join-Path $testSnapshot 'apps/jentra_desktop'; $testArguments = @($testFlutterTool,'--suppress-analytics','test','--no-pub','--concurrency=1','--reporter=expanded','test/command_palette_keyboard_test.dart') }
  'accountingTests' { $testWorking = Join-Path $testSnapshot 'apps/jentra_desktop'; $testArguments = @($testFlutterTool,'--suppress-analytics','test','--no-pub','--concurrency=1','--reporter=expanded','test/manual_journal_workspace_test.dart','test/receivables_workspace_test.dart','test/procurement_workspace_test.dart','test/financial_statement_workspace_test.dart','test/bank_reconciliation_workspace_test.dart') }
  'authTests' { $testWorking = Join-Path $testSnapshot 'apps/jentra_desktop'; $testArguments = @($testFlutterTool,'--suppress-analytics','test','--no-pub','--concurrency=1','--reporter=expanded','test/login_account_screen_test.dart','test/auth_capabilities_test.dart') }
  'cashTests' { $testWorking = Join-Path $testSnapshot 'apps/jentra_desktop'; $testArguments = @($testFlutterTool,'--suppress-analytics','test','--no-pub','--concurrency=1','--reporter=expanded','test/wave5_workspaces_test.dart','test/wave5_continuation_test.dart','test/wave5_cash_epoch_test.dart') }
  'platformAll' { $testWorking = Join-Path $testSnapshot 'packages/jentra_platform'; $testArguments = @($testFlutterTool,'--suppress-analytics','test','--no-pub','--concurrency=1','--reporter=expanded') }
  'desktopAll' { $testWorking = Join-Path $testSnapshot 'apps/jentra_desktop'; $testArguments = @($testFlutterTool,'--suppress-analytics','test','--no-pub','--concurrency=1','--reporter=expanded') }
  'build' {
   $testWorking = Join-Path $testSnapshot 'apps/jentra_desktop'
   if (Test-Path -LiteralPath (Join-Path $testWorking 'build/windows')) { throw 'FRESH_WINDOWS_BUILD_OUTPUT_REQUIRED' }
   $testArguments = @($testFlutterTool,'--suppress-analytics','build','windows','--release','--no-pub','--target=lib/main.dart')
   if ($Mode -eq 'Connected') { $testArguments += '--dart-define-from-file=' + (Join-Path $testSnapshot 'public-build-config.json') }
   else { $testArguments += '--dart-define=JENTRA_ENVIRONMENT=preview' }
  }
 }
 Push-Location -LiteralPath $testWorking
 $testPushed = $true
 $testExecuted = $true
 & node $testWrapper $testSdk @testArguments 2>&1 | Tee-Object -FilePath $testLog
 $testSdkExit = $LASTEXITCODE
 if ($null -eq $testSdkExit) { throw 'SDK_EXIT_CODE_UNAVAILABLE' }
 $testExit = $testSdkExit
 # Persist the actual child exit immediately, before hashes/postflight/finally.
 Write-TestJson -Path $testSdkExitPath -New -Value ([pscustomobject]@{
  mode=$Mode;stage=$Stage;attempt=$Attempt;revision='r3';date='20261010';sdkExitCode=$testSdkExit;
  observedAt=[DateTime]::UtcNow.ToString('o');workingDirectory=$testWorking;executable=$testSdk;args=$testArguments;
  sourceGuardBefore=$testBefore;nativeLaunched=$false;boundary='Actual SDK child exit only; later postflight may still fail.'
 })
} catch {
 $testFailure = $_.Exception.Message
 $testExit = 1
} finally {
 try {
  if ($testPushed) { Pop-Location }
  if ($testClaimed) {
   try {
    $testAfter = Test-SourceGuard
    if ($testBefore.publicConfig.sha256 -ne $testAfter.publicConfig.sha256) { throw 'PUBLIC_CONFIG_CHANGED_DURING_SDK_JOB' }
   } catch { $testFailure = if($testFailure){$testFailure + '; ' + $_.Exception.Message}else{$_.Exception.Message}; $testExit = 1 }
   $testLogHash = if(Test-Path -LiteralPath $testLog){Get-TestSha256 -Path $testLog}else{$null}
   $testSdkExitHash = if(Test-Path -LiteralPath $testSdkExitPath){Get-TestSha256 -Path $testSdkExitPath}else{$null}
   Write-TestJson -Path $testRecord -Value ([pscustomobject]@{
    mode=$Mode;stage=$Stage;attempt=$Attempt;revision='r3';date='20261010';status='complete';passed=($testExit -eq 0 -and -not $testFailure);workingDirectory=$testWorking;
    executable=$testSdk;args=$testArguments;captureEnvironmentWrapper='scripts/wave5/run_flutter_with_capture_env.mjs';
    log=($testBase + '.log');logSha256=$testLogHash;startedAt=$testStarted.ToString('o');finishedAt=[DateTime]::UtcNow.ToString('o');
    sdkExitCode=$testSdkExit;sdkExitRecord=($testBase + '.sdk-exit.json');sdkExitRecordSha256=$testSdkExitHash;
    exitCode=$testExit;failure=$testFailure;SDKExecuted=$testExecuted;sourceGuardBefore=$testBefore;sourceGuardAfter=$testAfter;
    runner='scripts/wave5/run_windows_userflow_20261010_r3_a2.ps1';runnerSha256=(Get-TestSha256 -Path $PSCommandPath);
    nativeLaunched=$false;authenticatedAcceptance=$false;actualAccountingPosting=$false;storesRead=$false;
    boundary='SDK evidence only. Tests use controlled fixtures; no native user flow, live mutation or acceptance-store inspection is implied.'
   })
  }
 } catch {
  $testFailure=if($testFailure){$testFailure + '; ' + $_.Exception.Message}else{$_.Exception.Message};$testExit=1
 } finally {
  # This finally always runs even if logging or source postflight throws.
  try {$testLock.Dispose()} finally {
   try {Remove-Item -LiteralPath $testLockPath -ErrorAction Stop}
   catch {$testFailure=if($testFailure){$testFailure + '; ' + $_.Exception.Message}else{$_.Exception.Message};$testExit=1}
  }
 }
}
if ($testFailure) { Write-Error $testFailure -ErrorAction Continue }
exit $testExit
