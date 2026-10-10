param(
 [Parameter(Mandatory=$true)][ValidateSet('Preview','Connected')][string]$Mode,
 [Parameter(Mandatory=$true)][ValidateSet('pubget','analyzer','startupTests','keyboardTests','accountingTests','authTests','cashTests','platformAll','desktopAll','build')][string]$Stage,
 [ValidatePattern('^[a-z][a-z0-9]{0,8}$')][string]$Attempt = 'a1',
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
$testLockPath = Join-Path $testRoot 'build/wave5-flutter-job.lock'
foreach ($testOutput in @($testLog,$testRecord)) {
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
 $testExit = $LASTEXITCODE
 if ($null -eq $testExit) { $testExit = 1; throw 'SDK_EXIT_CODE_UNAVAILABLE' }
} catch {
 $testFailure = $_.Exception.Message
 $testExit = 1
} finally {
 if ($testPushed) { Pop-Location }
 if ($testClaimed) {
  try {
   $testAfter = Test-SourceGuard
   if ($testBefore.publicConfig.sha256 -ne $testAfter.publicConfig.sha256) { throw 'PUBLIC_CONFIG_CHANGED_DURING_SDK_JOB' }
  } catch { $testFailure = if($testFailure){$testFailure + '; ' + $_.Exception.Message}else{$_.Exception.Message}; $testExit = 1 }
  $testLogHash = if(Test-Path -LiteralPath $testLog){(Get-FileHash -LiteralPath $testLog -Algorithm SHA256).Hash.ToLowerInvariant()}else{$null}
  [pscustomobject]@{
   mode=$Mode;stage=$Stage;attempt=$Attempt;revision='r3';date='20261010';status='complete';workingDirectory=$testWorking;
   executable=$testSdk;args=$testArguments;captureEnvironmentWrapper='scripts/wave5/run_flutter_with_capture_env.mjs';
   log=($testBase + '.log');logSha256=$testLogHash;startedAt=$testStarted.ToString('o');finishedAt=[DateTime]::UtcNow.ToString('o');
   exitCode=$testExit;failure=$testFailure;SDKExecuted=$testExecuted;sourceGuardBefore=$testBefore;sourceGuardAfter=$testAfter;
   nativeLaunched=$false;authenticatedAcceptance=$false;actualAccountingPosting=$false;storesRead=$false;
   boundary='SDK evidence only. Tests use controlled fixtures; no native user flow, live mutation or acceptance-store inspection is implied.'
  } | ConvertTo-Json -Depth 15 | Set-Content -LiteralPath $testRecord -Encoding utf8
 }
 $testLock.Dispose()
 # The absolute lock target is fixed inside this workspace and belongs only to
 # the FileMode.CreateNew handle acquired above. No recursive deletion occurs.
 Remove-Item -LiteralPath $testLockPath
}
if ($testFailure) { Write-Error $testFailure -ErrorAction Continue }
exit $testExit
