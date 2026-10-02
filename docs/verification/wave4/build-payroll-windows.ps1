[CmdletBinding()]
param()
$ErrorActionPreference='Stop'
$taskSource=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../..'))
$taskEvidence=Get-Content -LiteralPath (Join-Path $PSScriptRoot 'payroll-native-tests-20260930.json') -Raw | ConvertFrom-Json
$taskTarget=[IO.Path]::GetFullPath($taskEvidence.path)
if($taskTarget -notmatch '^C:\\jw4-payroll-[a-z0-9-]+$' -or -not $taskEvidence.isolated){throw 'Build requires the verified isolated payroll checkout.'}
$taskHashes=Get-Content -LiteralPath (Join-Path $PSScriptRoot 'payroll-source-hashes-20260930.json') -Raw | ConvertFrom-Json
foreach($taskHash in $taskHashes){
 if((Get-FileHash -Algorithm SHA256 -LiteralPath (Join-Path $taskTarget $taskHash.path)).Hash -ne $taskHash.sha256 -or
  (Get-FileHash -Algorithm SHA256 -LiteralPath (Join-Path $taskSource $taskHash.path)).Hash -ne $taskHash.sha256){
  throw "Source changed since payroll native verification: $($taskHash.path)"
 }
}
Set-Location -LiteralPath (Join-Path $taskTarget 'apps/jentra_desktop')
$env:CI='true'
& 'C:\src\flutter\bin\cache\dart-sdk\bin\dart.exe' 'C:\src\flutter\bin\cache\flutter_tools.snapshot' build windows --release --no-pub
if($LASTEXITCODE -ne 0){throw "Payroll isolated Windows build failed: $LASTEXITCODE"}
$taskBinary=Join-Path $taskTarget 'apps/jentra_desktop/build/windows/x64/runner/Release/jentra_desktop.exe'
$taskAot=Join-Path $taskTarget 'apps/jentra_desktop/build/windows/x64/runner/Release/data/app.so'
$taskResult=[PSCustomObject]@{path=$taskBinary;sha256=(Get-FileHash -Algorithm SHA256 -LiteralPath $taskBinary).Hash;
 aotPath=$taskAot;aotSha256=(Get-FileHash -Algorithm SHA256 -LiteralPath $taskAot).Hash;builtAt=(Get-Date).ToUniversalTime().ToString('o');installed=$false;launched=$false}
$taskResult | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $PSScriptRoot 'payroll-windows-build-20260930.json') -Encoding utf8
$taskResult | ConvertTo-Json
