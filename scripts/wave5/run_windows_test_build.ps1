param(
 [Parameter(Mandatory=$true)][ValidateSet('Preview','Connected')][string]$Mode,
 [Parameter(Mandatory=$true)][ValidateSet('pubget','analyzer','startupTests','keyboardTests','cashTests','cashFrames','modelGatewayTests','modelTests','modelFrames','authGatewayTests','authTests','authFrames','platformAll','desktopAll','build')][string]$Stage,
 [ValidatePattern('^[a-z][a-z0-9]{1,10}$')][string]$Revision = 'b1'
)
$ErrorActionPreference = 'Stop'
$testRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..'))
$testSuffix = if ($Revision -eq 'b1') { '' } else { '-' + $Revision }
$testSnapshot = Join-Path $testRoot ('build/w5win9' + $Revision + '/' + $Mode.ToLowerInvariant())
$testWorking = $testSnapshot
$testSdk = 'C:\src\flutter\bin\cache\dart-sdk\bin\dart.exe'
$testFlutterTool = 'C:\src\flutter\bin\cache\flutter_tools.snapshot'
# Each image stage owns its output. Later full-suite runs must not overwrite
# already inspected render files through inherited process environment values.
foreach ($testCaptureName in @('W5_CASH_FRAME_DIR','W5_MODEL_FRAME_DIR','W5_AUTH_FRAME_DIR')) {
 [Environment]::SetEnvironmentVariable($testCaptureName, $null, 'Process')
}
switch ($Stage) {
 'pubget' { $testArguments = @('pub','get') }
 'analyzer' {
  $testArguments = @('--suppress-analytics','analyze','apps/jentra_desktop/lib/main.dart','apps/jentra_desktop/lib/src/app.dart','apps/jentra_desktop/lib/src/app_providers.dart','apps/jentra_desktop/lib/src/router.dart','apps/jentra_desktop/lib/src/shell/jentra_shell.dart','apps/jentra_desktop/test/command_palette_keyboard_test.dart','apps/jentra_desktop/test/reviewed_model_workspace_test.dart','apps/jentra_desktop/lib/src/features/analytics','apps/jentra_desktop/lib/src/features/auth','apps/jentra_desktop/test/login_account_screen_test.dart','packages/jentra_platform/lib/src/auth','packages/jentra_platform/test/auth','packages/jentra_platform/lib/src/supabase_foundation_gateway.dart','packages/jentra_platform/lib/src/analytics/reviewed_model_gateway.dart','packages/jentra_platform/lib/src/analytics/wave5_command_store.dart','packages/jentra_platform/test/analytics/reviewed_model_gateway_test.dart','packages/jentra_platform/lib/src/runtime_config.dart','packages/jentra_platform/lib/src/supabase_platform.dart')
 }
 'startupTests' {
  $testWorking = Join-Path $testSnapshot 'apps/jentra_desktop'
  $testArguments = @('test','--no-pub','--concurrency=1','--reporter=expanded','--name=unconfigured startup|foundation shell exposes routes and command palette','test/main_preview_startup_test.dart','test/jentra_app_test.dart')
 }
 'keyboardTests' {
  $testWorking = Join-Path $testSnapshot 'apps/jentra_desktop'
  $testArguments = @('test','--no-pub','--concurrency=1','--reporter=expanded','test/command_palette_keyboard_test.dart')
 }
 'cashTests' {
  $testWorking = Join-Path $testSnapshot 'apps/jentra_desktop'
  $testArguments = @('test','--no-pub','--concurrency=1','--reporter=expanded','test/wave5_workspaces_test.dart','test/wave5_continuation_test.dart','test/process_metric_workspace_test.dart')
 }
 'cashFrames' {
  $testWorking = Join-Path $testSnapshot 'apps/jentra_desktop'
  $env:W5_CASH_FRAME_DIR = Join-Path $testRoot ('docs/verification/wave5/windows-test-cash-frames-20261009' + $testSuffix)
  $testArguments = @('test','--no-pub','--concurrency=1','--reporter=expanded','--name=cash fresh render','test/wave5_continuation_test.dart')
 }
 'modelGatewayTests' {
  $testWorking = Join-Path $testSnapshot 'packages/jentra_platform'
  $testArguments = @('test','--no-pub','--concurrency=1','--reporter=expanded','test/analytics/reviewed_model_gateway_test.dart','test/analytics/wave5_control_gateway_test.dart')
 }
 'modelTests' {
  $testWorking = Join-Path $testSnapshot 'apps/jentra_desktop'
  $testArguments = @('test','--no-pub','--concurrency=1','--reporter=expanded','test/reviewed_model_workspace_test.dart')
 }
 'modelFrames' {
  $testWorking = Join-Path $testSnapshot 'apps/jentra_desktop'
  $env:W5_MODEL_FRAME_DIR = Join-Path $testRoot ('docs/verification/wave5/windows-test-model-frames-20261009' + $testSuffix)
  $testArguments = @('test','--no-pub','--concurrency=1','--reporter=expanded','--name=model fresh render','test/reviewed_model_workspace_test.dart')
 }
 'authGatewayTests' {
  $testWorking = Join-Path $testSnapshot 'packages/jentra_platform'
  $testArguments = @('test','--no-pub','--concurrency=1','--reporter=expanded','test/auth/google_loopback_test.dart','test/auth/google_provider_settings_test.dart','test/auth/pkce_exchange_http_client_test.dart')
 }
 'authTests' {
  $testWorking = Join-Path $testSnapshot 'apps/jentra_desktop'
  $testArguments = @('test','--no-pub','--concurrency=1','--reporter=expanded','test/login_account_screen_test.dart','test/auth_capabilities_test.dart')
 }
 'authFrames' {
  $testWorking = Join-Path $testSnapshot 'apps/jentra_desktop'
  $env:W5_AUTH_FRAME_DIR = Join-Path $testRoot ('docs/verification/wave5/windows-test-auth-frames-20261009' + $testSuffix)
  $testArguments = @('test','--no-pub','--concurrency=1','--reporter=expanded','--name=auth fresh render','test/login_account_screen_test.dart')
 }
 'platformAll' {
  $testWorking = Join-Path $testSnapshot 'packages/jentra_platform'
  $testArguments = @('test','--no-pub','--concurrency=1','--reporter=expanded')
 }
 'desktopAll' {
  $testWorking = Join-Path $testSnapshot 'apps/jentra_desktop'
  $testArguments = @('test','--no-pub','--concurrency=1','--reporter=expanded')
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
if ($Stage -ne 'analyzer') { $testArguments = @($testFlutterTool,'--suppress-analytics') + $testArguments }
$testBase = 'docs/verification/wave5/windows-test-' + $Mode.ToLowerInvariant() + '-' + $Stage + '-20261009' + $testSuffix
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
