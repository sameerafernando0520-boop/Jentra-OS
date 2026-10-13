# NEW r5 successor; preserved r4 predecessor scripts/wave5/finalize_windows_userflow_20261010_r4.ps1 SHA-256 c2a17ad1fcb1e9588bf96dcad7aacd7e9e92dbd6860c084810f67d4414711c1b.
# NEW r5 variant; preserved predecessor finalize_windows_userflow_20261010_r3_a2.ps1 SHA-256 05bc2fd2eb77a0abe95a34a7d8386547aa789f9b90eafeb6dd07f54a05b58b29.
$ErrorActionPreference='Stop'
function Get-TestSha256([string]$Path){$testHashStream=[IO.File]::OpenRead($Path);$testHasher=[Security.Cryptography.SHA256]::Create();try{return ([BitConverter]::ToString($testHasher.ComputeHash($testHashStream))).Replace('-','').ToLowerInvariant()}finally{$testHashStream.Dispose();$testHasher.Dispose()}}
$testRoot=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..'))
$testName='Jentra OS Windows Test 20261010 r5'
$testPackage=Join-Path $testRoot ('dist/' + $testName)
$testZip=Join-Path $testRoot ('dist/' + $testName + '.zip')
$testEvidence=Join-Path $testRoot 'docs/verification/wave5/windows-test-delivery-20261010-r5.json'
foreach($testOutput in @($testZip,$testEvidence)){if(Test-Path -LiteralPath $testOutput){throw 'NEW_DELIVERY_OUTPUT_REQUIRED'}}
$testInputsPath=Join-Path $testRoot 'docs/verification/wave5/windows-test-package-inputs-20261010-r5.json'
$testInputs=Get-Content -LiteralPath $testInputsPath -Raw | ConvertFrom-Json
if($testInputs.packageDirectory -ne $testPackage -or $testInputs.nativeLaunched -ne $false -or $testInputs.compiledRunnerIdentitiesVerified -ne $true){throw 'EXACT_R5_PACKAGE_INPUTS_REQUIRED'}
foreach($testFile in $testInputs.packageFiles){
 $testPath=[IO.Path]::GetFullPath((Join-Path $testPackage $testFile.path))
 if(-not $testPath.StartsWith($testPackage + [IO.Path]::DirectorySeparatorChar,[StringComparison]::OrdinalIgnoreCase)){throw 'PACKAGE_PATH_ESCAPE'}
 $testItem=Get-Item -LiteralPath $testPath
 if($testItem.Attributes -band [IO.FileAttributes]::ReparsePoint){throw 'PACKAGE_LINK_REFUSED'}
 if($testItem.Length -ne $testFile.bytes -or (Get-TestSha256 $testPath) -ne $testFile.sha256){throw 'PACKAGE_INPUT_HASH_OR_SIZE_DRIFT'}
}
Add-Type -AssemblyName System.IO.Compression.FileSystem
# ZipFile includes every file, including hidden files, and preserves base folder.
[IO.Compression.ZipFile]::CreateFromDirectory($testPackage,$testZip,[IO.Compression.CompressionLevel]::Optimal,$true)
$testArchive=[IO.Compression.ZipFile]::OpenRead($testZip)
$testChecked=0
try {
 $testFileEntries=@($testArchive.Entries | Where-Object { -not $_.FullName.Replace('\','/').EndsWith('/') })
 if($testFileEntries.Count -ne $testInputs.packageFiles.Count){throw 'ZIP_FILE_SET_COUNT_MISMATCH'}
 foreach($testFile in $testInputs.packageFiles){
  $testEntryName=$testName + '/' + $testFile.path
  $testMatches=@($testFileEntries | Where-Object { $_.FullName.Replace('\','/') -eq $testEntryName })
  if($testMatches.Count -ne 1){throw 'EXACT_ZIP_ENTRY_REQUIRED'}
  $testEntry=$testMatches[0]
  if($testEntry.Length -ne $testFile.bytes){throw 'ZIP_ENTRY_SIZE_MISMATCH'}
  $testStream=$testEntry.Open();$testHasher=[Security.Cryptography.SHA256]::Create()
  try {
   $testHash=([BitConverter]::ToString($testHasher.ComputeHash($testStream))).Replace('-','').ToLowerInvariant()
   if($testHash -ne $testFile.sha256){throw 'ZIP_ENTRY_HASH_MISMATCH'}
   $testChecked++
  } finally {$testStream.Dispose();$testHasher.Dispose()}
 }
} finally {$testArchive.Dispose()}
$testReport=[pscustomobject]@{createdAt=[DateTime]::UtcNow.ToString('o');revision='r5';date='20261010';attempt='a1';packageDirectory=$testPackage;zip=$testZip;
 finalizer='scripts/wave5/finalize_windows_userflow_20261010_r5.ps1';finalizerSha256=(Get-TestSha256 $PSCommandPath);
 zipSha256=(Get-TestSha256 $testZip);zipBytes=(Get-Item -LiteralPath $testZip).Length;
 packageInputs='docs/verification/wave5/windows-test-package-inputs-20261010-r5.json';packageInputsSha256=(Get-TestSha256 $testInputsPath);
 verifiedPackageEntries=$testChecked;verifiedReleaseEntries=($testInputs.manifests | Measure-Object -Property releaseFiles -Sum).Sum;bothAppsIncluded=$true;
 installerCreated=$false;acceptanceStoresCopied=$false;backendChanged=$false;nativeLaunched=$false}
$testReportJson=$testReport | ConvertTo-Json -Depth 10
$testStream=[IO.File]::Open($testEvidence,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::None)
try {$testWriter=[IO.StreamWriter]::new($testStream,[Text.UTF8Encoding]::new($false));$testWriter.WriteLine($testReportJson);$testWriter.Flush()}
finally {if($testWriter){$testWriter.Dispose()}else{$testStream.Dispose()}}
$testReportJson
