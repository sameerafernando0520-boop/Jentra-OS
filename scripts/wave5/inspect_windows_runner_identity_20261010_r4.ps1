# NEW r4 variant; preserved predecessor inspect_windows_runner_identity_20261010_r3.ps1 SHA-256 f961fc2308f61a1251def9ac4e2103cd15a8812307b8a1b72ff7d4b057d3c8b8.
param([Parameter(Mandatory=$true)][ValidateSet('Preview','Connected')][string]$Mode,
 [Parameter(Mandatory=$true)][string]$Executable)
$ErrorActionPreference='Stop'
function Get-TestSha256([string]$Path){$testHashStream=[IO.File]::OpenRead($Path);$testHasher=[Security.Cryptography.SHA256]::Create();try{return ([BitConverter]::ToString($testHasher.ComputeHash($testHashStream))).Replace('-','').ToLowerInvariant()}finally{$testHashStream.Dispose();$testHasher.Dispose()}}
$testRoot=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..'))
$testActual=[IO.Path]::GetFullPath($Executable)
$testRelease=Join-Path $testRoot ('build/w5win10r4/' + $Mode.ToLowerInvariant() + '/apps/jentra_desktop/build/windows/x64/runner/Release/Jentra_OS.exe')
$testPackaged=Join-Path $testRoot ('dist/Jentra OS Windows Test 20261010 r4/' + $Mode + '/Jentra_OS.exe')
if($testActual -ne $testRelease -and $testActual -ne $testPackaged){throw 'EXACT_R4_EXECUTABLE_PATH_REQUIRED'}
$testItem=Get-Item -LiteralPath $testActual
if($testItem.Attributes -band [IO.FileAttributes]::ReparsePoint){throw 'EXECUTABLE_LINK_REFUSED'}
# FileVersionInfo reads PE resources; it does not launch the executable.
$testVersion=[Diagnostics.FileVersionInfo]::GetVersionInfo($testActual)
$testProduct='JentraOS_WindowsTest_20261010-r4_' + $Mode
$testDescription='Jentra OS Windows Test - 20261010 r4 ' + $Mode
if($testVersion.CompanyName -ne 'com.jentra.test' -or $testVersion.ProductName -ne $testProduct -or
 $testVersion.OriginalFilename -ne 'Jentra_OS.exe' -or $testVersion.FileDescription -ne $testDescription){throw 'COMPILED_RUNNER_IDENTITY_MISMATCH'}
[pscustomobject]@{observedAt=[DateTime]::UtcNow.ToString('o');mode=$Mode;executable=$testActual;method='System.Diagnostics.FileVersionInfo PE resource read';
 CompanyName=$testVersion.CompanyName;ProductName=$testVersion.ProductName;OriginalFilename=$testVersion.OriginalFilename;FileDescription=$testVersion.FileDescription;
 sha256=(Get-TestSha256 $testActual);bytes=$testItem.Length;readOnly=$true;nativeLaunched=$false} | ConvertTo-Json
