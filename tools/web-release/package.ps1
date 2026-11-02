[CmdletBinding()]
param([Parameter(Mandatory=$true)][string]$OutputDirectory)
$ErrorActionPreference='Stop'
$output=[IO.Path]::GetFullPath($OutputDirectory)
$manifest=Get-Content -LiteralPath (Join-Path $output 'source-manifest.json') -Raw | ConvertFrom-Json
$identity=$manifest.identity
if ($identity.channel -ne 'development' -or $identity.sourceSha256 -notmatch '^[a-f0-9]{64}$') { throw 'WEB_DEVELOPMENT_SOURCE_IDENTITY_REQUIRED' }
foreach ($inputFile in $manifest.buildFiles) {
  if ((Get-FileHash -LiteralPath (Join-Path $manifest.snapshot $inputFile.path) -Algorithm SHA256).Hash.ToLowerInvariant() -ne $inputFile.sha256) { throw 'WEB_BUILD_SOURCE_CHANGED' }
}
$package=Join-Path $output 'package'
if (Test-Path -LiteralPath $package) { throw 'NEW_WEB_PACKAGE_DIRECTORY_REQUIRED' }
New-Item -ItemType Directory -Path $package | Out-Null
$bundle=Join-Path $manifest.snapshot 'apps\jentra_desktop\build\web'
Copy-Item -LiteralPath $bundle -Destination (Join-Path $package 'site') -Recurse
foreach ($required in @('index.html','main.dart.js','flutter_bootstrap.js','manifest.json','assets\packages\jentra_platform\assets\web\sqlite3.wasm','assets\packages\jentra_platform\assets\web\drift_worker.js')) {
  if (!(Test-Path -LiteralPath (Join-Path $package ('site\'+$required)) -PathType Leaf)) { throw 'WEB_RUNTIME_FILE_MISSING' }
}
$ref=$identity.projectRef
$headers=@"
/*
  Cache-Control: no-store
  X-Content-Type-Options: nosniff
  X-Frame-Options: DENY
  Referrer-Policy: no-referrer
  Content-Security-Policy: default-src 'self'; script-src 'self' 'wasm-unsafe-eval'; style-src 'self' 'unsafe-inline'; img-src 'self' data: blob: https://$ref.supabase.co; font-src 'self' data:; connect-src 'self' https://$ref.supabase.co wss://$ref.supabase.co; worker-src 'self' blob:; frame-src 'self' blob:; object-src 'none'; base-uri 'self'; frame-ancestors 'none'
/*.wasm
  Content-Type: application/wasm
"@
[IO.File]::WriteAllText((Join-Path $package 'site\_headers'),$headers,(New-Object Text.UTF8Encoding($false)))
[IO.File]::WriteAllText((Join-Path $package 'site\_redirects'),"/* /index.html 200`n",(New-Object Text.UTF8Encoding($false)))
Copy-Item -LiteralPath (Join-Path $manifest.snapshot 'tools\web-release\Serve-Web.ps1') -Destination (Join-Path $package 'Serve-Web.ps1')
Copy-Item -LiteralPath (Join-Path $output 'build-identity.json') -Destination (Join-Path $package 'build-identity.json')
[IO.File]::WriteAllText((Join-Path $package 'Start Jentra OS Web.cmd'),"@echo off`r`npowershell.exe -NoProfile -ExecutionPolicy Bypass -File `"%~dp0Serve-Web.ps1`" -OpenBrowser`r`npause`r`n",(New-Object Text.ASCIIEncoding))
$instructions=@'
Jentra OS Development web application

Windows local use: extract this whole ZIP and double-click Start Jentra OS Web.cmd.
The browser opens http://127.0.0.1:8485/ . Keep the console open; close it to stop.
The server binds only loopback, requires no administrator, and installs no backend.
If port 8485 is already occupied, keep the existing service and run Serve-Web.ps1 -Port <another free port> -OpenBrowser.

Company account required. This connects to the existing Development Supabase target.
Use one browser tab for editing/recovery. Allow persistent browser storage.
Browser privacy modes or denied storage can block saving; no plaintext or memory-only recovery fallback is used.
Do not clear site data or move to another origin while a command is unconfirmed.

Hosting: publish only the site directory to a reviewed HTTPS static host.
Retain _headers and _redirects for a compatible host, or configure equivalent headers/routing.
Serve every .wasm file as application/wasm. Do not proxy/cache authentication or private API responses.
Auth email/OAuth callback allowlists must be reviewed for that actual domain.
Never upload public-build-config.json, .env files, signing files or user data.

The Sales app, candidate backend rollout, push activation, hosted AI verification,
statutory payroll, restoration/monitoring, release signing and company acceptance
remain separate launch gates. This ZIP is not a production-readiness certificate.
'@
[IO.File]::WriteAllText((Join-Path $package 'README.txt'),$instructions,(New-Object Text.UTF8Encoding($false)))
$files=@(Get-ChildItem -LiteralPath $package -File -Recurse | ForEach-Object {
  [ordered]@{path=$_.FullName.Substring($package.Length+1).Replace('\','/');bytes=$_.Length;sha256=(Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash.ToLowerInvariant()}
})
. (Join-Path $manifest.snapshot 'tools\desktop-release\archive.ps1')
$zip=Join-Path $output ('Jentra-OS-'+$identity.releaseId+'-Web.zip')
New-JentraReleaseArchive -SourceDirectory $package -DestinationPath $zip
$archive=[IO.Compression.ZipFile]::OpenRead($zip)
try {
  foreach ($file in $files) {
    $entry=$archive.GetEntry($file.path)
    if (!$entry -or $entry.Length -ne $file.bytes) { throw 'WEB_ARCHIVE_ENTRY_MISMATCH' }
    $stream=$entry.Open();$hasher=[Security.Cryptography.SHA256]::Create()
    try { if (([BitConverter]::ToString($hasher.ComputeHash($stream))).Replace('-','').ToLowerInvariant() -ne $file.sha256) { throw 'WEB_ARCHIVE_HASH_MISMATCH' } }
    finally { $stream.Dispose();$hasher.Dispose() }
  }
} finally { $archive.Dispose() }
$delivery=[ordered]@{identity=$identity;platform='web';archive=[ordered]@{path=$zip;bytes=(Get-Item -LiteralPath $zip).Length;sha256=(Get-FileHash -LiteralPath $zip -Algorithm SHA256).Hash.ToLowerInvariant()};files=$files;hosted=$false;browserAcceptance=$false;backendChanged=$false;productionCertified=$false}
[IO.File]::WriteAllText((Join-Path $output 'delivery.json'),($delivery | ConvertTo-Json -Depth 10)+"`n",(New-Object Text.UTF8Encoding($false)))
[PSCustomObject]$delivery | Select-Object identity,platform,archive,hosted,backendChanged,productionCertified | ConvertTo-Json -Depth 6
