$ErrorActionPreference='Stop'
$testRoot=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..'))
$testPackage=Join-Path $testRoot 'dist/Jentra OS Windows Test 20261009'
$testZip=Join-Path $testRoot 'dist/Jentra OS Windows Test 20261009.zip'
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
JENTRA OS - WINDOWS TEST BUILD - 9 OCTOBER 2026

START HERE
Double-click Start Preview.cmd to explore the interface without logging in.
Double-click Start Connected.cmd to sign in to your existing development account.
Use the credentials you already know; no password is included in this package.
The six proposed Wave 5 accounts have not been created.

TRY THESE
- Dashboard, tenant/entity/branch selectors and the side navigation.
- Ctrl+K opens the command palette. Escape closes it.
- Light/dark theme, compact/comfortable density and a resized window.
- Setup, CRM, Sales, Inventory, Finance, People, Projects and Analytics.
- Analytics includes Process, Pipeline, Historical pipeline, Financial ratios,
  Cash scenarios, Integrations and Governed exports.

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
No installer, backend migration, new account, entitlement or worker was deployed.
release-manifest.json in each app directory records every shipped release hash.

FEEDBACK
Record which mode/page/action you tried, expected and actual behavior, window
size, theme and density. Keep passwords, MFA codes and private data out of feedback.
'@ | Set-Content -LiteralPath (Join-Path $testPackage 'Start Here.txt') -Encoding utf8
Compress-Archive -LiteralPath $testPackage -DestinationPath $testZip -CompressionLevel Optimal
Add-Type -AssemblyName System.IO.Compression.FileSystem
$testArchive=[IO.Compression.ZipFile]::OpenRead($testZip)
$testChecked=0
try {
 foreach($testMode in @('Preview','Connected')) {
  $testManifest=Get-Content -LiteralPath (Join-Path $testPackage ($testMode + '/release-manifest.json')) -Raw | ConvertFrom-Json
  foreach($testFile in $testManifest.releaseFiles) {
   $testEntryPath='Jentra OS Windows Test 20261009/' + $testMode + '/' + $testFile.path
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
$testReport | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $testRoot 'docs/verification/wave5/windows-test-delivery-20261009.json')
$testReport | ConvertTo-Json
