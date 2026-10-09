param([ValidatePattern('^[a-z][a-z0-9]{1,10}$')][string]$Revision = 'b1')
$ErrorActionPreference='Stop'
$testRoot=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..'))
$testSuffix=if($Revision -eq 'b1'){''}else{'-' + $Revision}
$testName='Jentra OS Windows Test 20261009' + $(if($Revision -eq 'b1'){''}else{' ' + $Revision})
$testPackage=Join-Path $testRoot ('dist/' + $testName)
$testZip=Join-Path $testRoot ('dist/' + $testName + '.zip')
if(Test-Path -LiteralPath $testZip) {throw 'ZIP_ALREADY_EXISTS'}
foreach($testMode in @('Preview','Connected')) {
 if(-not (Test-Path -LiteralPath (Join-Path $testPackage ($testMode + '/Jentra_OS.exe')))) {throw 'BOTH_TEST_APPS_REQUIRED'}
}
@'
@echo off
start "" "%~dp0Preview\Jentra_OS.exe"
'@ | Set-Content -LiteralPath (Join-Path $testPackage 'Start Preview.cmd') -Encoding ascii
@'
@echo off
start "" "%~dp0Connected\Jentra_OS.exe"
'@ | Set-Content -LiteralPath (Join-Path $testPackage 'Start Connected.cmd') -Encoding ascii
@'
JENTRA OS - WINDOWS TEST BUILD

START HERE
Double-click Start Preview.cmd to explore the interface without logging in.
Double-click Start Connected.cmd to sign in to your development account.
The owner-created test login desktop-test-20261009@jentra.invalid is confirmed
and has a recorded real sign-in. Use only the password entered privately by you.
This account has no business membership. Set up a business or use an invitation
before expecting access to business workspaces. See Desktop test login.md.
Use Create account for a new email/password login and follow email confirmation.
Continue with Google opens your browser. Google must first be enabled privately
in Supabase and this Windows return allowed:
http://127.0.0.1:56327/auth/callback/*
See Account and Google setup.md beside these launchers for exact setup steps.
No password or Google client secret is included in this package.
The six proposed Wave 5 accounts have not been created.

TRY THESE
- Dashboard, tenant/entity/branch selectors and the side navigation.
- Ctrl+K opens the command palette. Escape closes it.
- Up/Down select a command; Enter opens the selected permitted destination.
- Light/dark theme, compact/comfortable density and a resized window.
- Setup, CRM, Sales, Inventory, Finance, People, Projects and Analytics.
- Analytics includes Process, Pipeline, Historical pipeline, Financial ratios,
  Cash scenarios, Integrations, Governed exports and Control.
- Control includes reviewed model requests and encrypted original-request recovery.
  Actual model responses require the reviewed worker/provider setup below.

PREVIEW AND CONNECTED
Preview uses the existing local example dashboard/context. Authoritative actions
and providers require a backend and remain unavailable in this mode.
Connected uses project xpdoufauvrbdmxgngetv and the currently installed backend.
Sign-in and real commands follow the account's current permissions and MFA.
Additional cash/history/statement/integration providers are still uninstalled.
Real Wave 5 runtime, worker delivery and acceptance remain unfinished.

LOCAL DATA
The two apps use separate application identities under:
%APPDATA%\com.jentra.test\JentraOS_WindowsTest_20261009_Preview
%APPDATA%\com.jentra.test\JentraOS_WindowsTest_20261009_Connected
Their preferences, sessions and encrypted drafts are separate from the acceptance
app. No previous session, local database or credential was copied into this build.
The formal runtime-review Windows account was not created.

PORTABLE PACKAGE
Extract the entire ZIP before running. Keep each EXE, its DLLs and data directory
together. This is a portable x64 test package built for this Windows PC.
This package does not deploy an installer, backend migration, account,
entitlement or worker. It does not prove native keyboard or runtime acceptance.
release-manifest.json in each app directory records every shipped release hash.

FEEDBACK
Record which mode/page/action you tried, expected and actual behavior, window
size, theme and density. Keep passwords, MFA codes and private data out of feedback.
'@ | ForEach-Object { $_.Replace('20261009_Preview',('20261009' + $testSuffix + '_Preview')).Replace('20261009_Connected',('20261009' + $testSuffix + '_Connected')) } | Set-Content -LiteralPath (Join-Path $testPackage 'Start Here.txt') -Encoding utf8
$testGuide = [IO.File]::ReadAllText((Join-Path $testRoot 'docs/verification/wave5/windows-account-google-setup-20261009.md'))
$testGuide = $testGuide.Replace('[development status](../../development/wave5-status.md)', 'development status in the source workspace').Replace('[public Auth settings](public-auth-settings-20261009.json)', 'public Auth settings').Replace('[public Auth settings](public-auth-settings-20261010.json)', 'public Auth settings').Replace('[remaining-work record](complete-app-remaining-work-20261009.md)', 'remaining-work record in the source workspace')
$testGuide = $testGuide.Replace('[desktop test login](desktop-test-login-20261009.md)', '[desktop test login](Desktop%20test%20login.md)')
$testGuide | Set-Content -LiteralPath (Join-Path $testPackage 'Account and Google setup.md') -Encoding utf8
$testLoginGuide = [IO.File]::ReadAllText((Join-Path $testRoot 'docs/verification/wave5/desktop-test-login-20261009.md'))
$testLoginGuide = $testLoginGuide.Replace('[creation verification](desktop-test-login-result-20261009.json)', 'creation verification in the source workspace').Replace('[sign-in verification](desktop-test-login-signin-20261009.json)', 'sign-in verification in the source workspace').Replace('[private configuration steps](windows-account-google-setup-20261009.md)', '[private configuration steps](Account%20and%20Google%20setup.md)')
$testLoginGuide | Set-Content -LiteralPath (Join-Path $testPackage 'Desktop test login.md') -Encoding utf8
Compress-Archive -LiteralPath $testPackage -DestinationPath $testZip -CompressionLevel Optimal
Add-Type -AssemblyName System.IO.Compression.FileSystem
$testArchive=[IO.Compression.ZipFile]::OpenRead($testZip)
$testChecked=0
try {
 foreach($testMode in @('Preview','Connected')) {
  $testManifest=Get-Content -LiteralPath (Join-Path $testPackage ($testMode + '/release-manifest.json')) -Raw | ConvertFrom-Json
  foreach($testFile in $testManifest.releaseFiles) {
   $testEntryPath=$testName + '/' + $testMode + '/' + $testFile.path
   $testEntry=$testArchive.GetEntry($testEntryPath)
   if(-not $testEntry) {throw 'ZIP_RELEASE_FILE_MISSING'}
   $testStream=$testEntry.Open()
   $testHasher=[Security.Cryptography.SHA256]::Create()
   try {
    $testHash=([BitConverter]::ToString($testHasher.ComputeHash($testStream))).Replace('-','').ToLowerInvariant()
    if($testHash -ne $testFile.sha256) {throw 'ZIP_RELEASE_HASH_MISMATCH'}
    $testChecked++
   } finally {$testStream.Dispose();$testHasher.Dispose()}
  }
 }
} finally {$testArchive.Dispose()}
$testReport=[pscustomobject]@{createdAt=[DateTime]::UtcNow.ToString('o');packageDirectory=$testPackage;zip=$testZip;zipSha256=(Get-FileHash -LiteralPath $testZip -Algorithm SHA256).Hash.ToLowerInvariant();zipBytes=(Get-Item -LiteralPath $testZip).Length;verifiedReleaseEntries=$testChecked;bothAppsIncluded=$true;installerCreated=$false;acceptanceStoresCopied=$false;backendChanged=$false}
$testReport | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $testRoot ('docs/verification/wave5/windows-test-delivery-20261009' + $testSuffix + '.json'))
$testReport | ConvertTo-Json
