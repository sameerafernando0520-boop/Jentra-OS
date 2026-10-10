param([Parameter(Mandatory=$true)][ValidateSet('Preview','Connected')][string]$Mode,
 [Parameter(Mandatory=$true)][string]$Executable)
$ErrorActionPreference='Stop'
function Get-TestSha256([string]$Path){$testHashStream=[IO.File]::OpenRead($Path);$testHasher=[Security.Cryptography.SHA256]::Create();try{return ([BitConverter]::ToString($testHasher.ComputeHash($testHashStream))).Replace('-','').ToLowerInvariant()}finally{$testHashStream.Dispose();$testHasher.Dispose()}}
$testRoot=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..'))
$testActual=[IO.Path]::GetFullPath($Executable)
$testRelease=Join-Path $testRoot ('build/w5win10r3/' + $Mode.ToLowerInvariant() + '/apps/jentra_desktop/build/windows/x64/runner/Release/Jentra_OS.exe')
$testPackaged=Join-Path $testRoot ('dist/Jentra OS Windows Test 20261010 r3/' + $Mode + '/Jentra_OS.exe')
if($testActual -ne $testRelease -and $testActual -ne $testPackaged){throw 'EXACT_R3_EXECUTABLE_PATH_REQUIRED'}
$testItem=Get-Item -LiteralPath $testActual
if($testItem.Attributes -band [IO.FileAttributes]::ReparsePoint){throw 'EXECUTABLE_LINK_REFUSED'}
# FileVersionInfo reads PE resources; it does not launch the executable.
$testVersion=[Diagnostics.FileVersionInfo]::GetVersionInfo($testActual)
$testProduct='JentraOS_WindowsTest_20261010-r3_' + $Mode
$testDescription='Jentra OS Windows Test - 20261010 r3 ' + $Mode
if($testVersion.CompanyName -ne 'com.jentra.test' -or $testVersion.ProductName -ne $testProduct -or
 $testVersion.OriginalFilename -ne 'Jentra_OS.exe' -or $testVersion.FileDescription -ne $testDescription){throw 'COMPILED_RUNNER_IDENTITY_MISMATCH'}
[pscustomobject]@{observedAt=[DateTime]::UtcNow.ToString('o');mode=$Mode;executable=$testActual;method='System.Diagnostics.FileVersionInfo PE resource read';
 CompanyName=$testVersion.CompanyName;ProductName=$testVersion.ProductName;OriginalFilename=$testVersion.OriginalFilename;FileDescription=$testVersion.FileDescription;
 sha256=(Get-TestSha256 $testActual);bytes=$testItem.Length;readOnly=$true;nativeLaunched=$false} | ConvertTo-Json
