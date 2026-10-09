param(
 [Parameter(Mandatory=$true)][ValidateSet('Preview','Connected')][string]$Mode,
 [Parameter(Mandatory=$true)][ValidateSet('pubget','analyzer','startupTests','build')][string]$Stage
)
$ErrorActionPreference = 'Stop'
$testRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..'))
$testSnapshot = Join-Path $testRoot ('build/w5win9b1/' + $Mode.ToLowerInvariant())
$testWorking = $testSnapshot
$testSdk = 'C:\src\flutter\bin\flutter.bat'
switch ($Stage) {
 'pubget' { $testArguments = @('pub','get') }
 'analyzer' {
  $testSdk = 'C:\src\flutter\bin\dart.bat'
  $testArguments = @('analyze','apps/jentra_desktop/lib/main.dart','apps/jentra_desktop/lib/src/app.dart','apps/jentra_desktop/lib/src/app_providers.dart','apps/jentra_desktop/lib/src/router.dart','packages/jentra_platform/lib/src/runtime_config.dart','packages/jentra_platform/lib/src/supabase_platform.dart')
 }
 'startupTests' {
  $testWorking = Join-Path $testSnapshot 'apps/jentra_desktop'
  $testArguments = @('test','--no-pub','--concurrency=1','--reporter=expanded','--name=unconfigured startup|foundation shell exposes routes and command palette','test/main_preview_startup_test.dart','test/jentra_app_test.dart')
 }
 'build' {
  $testWorking = Join-Path $testSnapshot 'apps/jentra_desktop'
  $testArguments = @('build','windows','--release','--no-pub','--target=lib/main.dart')
  if ($Mode -eq 'Connected') {
   $testConfig = Join-Path $testSnapshot 'public-build-config.json'
   if (-not (Test-Path -LiteralPath $testConfig)) { throw 'CONNECTED_PUBLIC_CONFIG_REQUIRED' }
   $testArguments += '--dart-define-from-file=' + $testConfig
  } else { $testArguments += '--dart-define=JENTRA_ENVIRONMENT=preview' }
 }
}
$testBase = 'docs/verification/wave5/windows-test-' + $Mode.ToLowerInvariant() + '-' + $Stage + '-20261009'
$testLog = Join-Path $testRoot ($testBase + '.log')
$testStarted = [DateTime]::UtcNow
$testExit = 1
Push-Location -LiteralPath $testWorking
try {
 & $testSdk @testArguments 2>&1 | Tee-Object -FilePath $testLog
 $testExit = $LASTEXITCODE
} finally {
 Pop-Location
 [pscustomobject]@{mode=$Mode;stage=$Stage;workingDirectory=$testWorking;command=($testSdk + ' ' + ($testArguments -join ' '));log=($testBase + '.log');startedAt=$testStarted.ToString('o');finishedAt=[DateTime]::UtcNow.ToString('o');exitCode=$testExit} |
  ConvertTo-Json | Set-Content -LiteralPath (Join-Path $testRoot ($testBase + '.json'))
}
exit $testExit
