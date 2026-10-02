[CmdletBinding()]
param([Parameter(Mandatory=$true)][string]$Target,[Parameter(Mandatory=$true)][string]$PriorManifest,[ValidatePattern('^[a-z0-9-]+$')][string]$EvidenceTag)
$ErrorActionPreference='Stop'
$refreshSource=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../..'))
$refreshTarget=[IO.Path]::GetFullPath($Target)
if($refreshTarget -notmatch '^C:\\jw3-[a-z0-9-]+$' -or $refreshTarget.StartsWith($refreshSource,[StringComparison]::OrdinalIgnoreCase) -or !(Test-Path -LiteralPath $refreshTarget)){throw 'Existing task-owned isolated Windows copy required'}
$refreshPrior=@(Get-Content -Raw -LiteralPath $PriorManifest|ConvertFrom-Json)
$refreshOld=@{}; foreach($entry in $refreshPrior){$refreshOld[$entry.path]=$entry.sha256}
$refreshPaths=@(& rg --files apps packages -g '*.dart' -g 'pubspec.yaml' -g '*.h' -g '*.cpp' -g '*.rc' -g 'CMakeLists.txt' -g '*.manifest' -g '*.ico' -g '*.ttf' -g '*.otf' -g '*.svg' -g '*.png' -g '!test/**' -g '!**/test/**' -g '!**/build/**' -g '!**/.dart_tool/**')+@('pubspec.yaml','pubspec.lock')
$refreshBefore=@{}; $refreshChanged=@()
foreach($relative in $refreshPaths){
 $sourceFile=[IO.Path]::GetFullPath((Join-Path $refreshSource $relative))
 $targetFile=[IO.Path]::GetFullPath((Join-Path $refreshTarget $relative))
 if(!$sourceFile.StartsWith($refreshSource+[IO.Path]::DirectorySeparatorChar,[StringComparison]::OrdinalIgnoreCase) -or !$targetFile.StartsWith($refreshTarget+[IO.Path]::DirectorySeparatorChar,[StringComparison]::OrdinalIgnoreCase)){throw 'Source/target escaped validated workspace'}
 $current=(Get-FileHash -LiteralPath $sourceFile -Algorithm SHA256).Hash
 $refreshBefore[$relative]=$current
 if($refreshOld.ContainsKey($relative) -and (Get-FileHash -LiteralPath $targetFile -Algorithm SHA256).Hash -ne $refreshOld[$relative]){throw "Isolated source drift before refresh: $relative"}
 if(!$refreshOld.ContainsKey($relative) -or $current -ne $refreshOld[$relative]){
  New-Item -ItemType Directory -Force -Path ([IO.Path]::GetDirectoryName($targetFile))|Out-Null
  Copy-Item -LiteralPath $sourceFile -Destination $targetFile
  $refreshChanged+=$relative
 }
}
$refreshManifest=foreach($relative in $refreshPaths){
 $copied=(Get-FileHash -LiteralPath (Join-Path $refreshTarget $relative) -Algorithm SHA256).Hash
 if($copied -ne $refreshBefore[$relative] -or (Get-FileHash -LiteralPath (Join-Path $refreshSource $relative) -Algorithm SHA256).Hash -ne $copied){throw "Source changed during refresh: $relative"}
 [PSCustomObject]@{path=$relative;sha256=$copied}
}
$refreshManifest|ConvertTo-Json|Set-Content -Encoding utf8 -LiteralPath (Join-Path $PSScriptRoot "windows-source-hashes-$EvidenceTag.json")
$refreshTimer=[Diagnostics.Stopwatch]::StartNew()
Set-Location -LiteralPath (Join-Path $refreshTarget 'apps/jentra_desktop')
$env:CI='true'
& 'C:\src\flutter\bin\cache\dart-sdk\bin\dart.exe' 'C:\src\flutter\bin\cache\flutter_tools.snapshot' build windows --release --no-pub
$refreshCode=$LASTEXITCODE; $refreshTimer.Stop()
$refreshCurrent=$true
foreach($relative in $refreshPaths){if((Get-FileHash -LiteralPath (Join-Path $refreshSource $relative) -Algorithm SHA256).Hash -ne $refreshBefore[$relative]){$refreshCurrent=$false}}
$refreshBinary=Join-Path $refreshTarget 'apps/jentra_desktop/build/windows/x64/runner/Release/jentra_desktop.exe'
[PSCustomObject]@{target=$refreshTarget;status=$(if($refreshCode -eq 0){'compiled'}else{'failed'});exit_code=$refreshCode;current_source_match=$refreshCurrent;binary=$refreshBinary;sha256=$(if($refreshCode -eq 0){(Get-FileHash -LiteralPath $refreshBinary -Algorithm SHA256).Hash}else{$null});seconds=$refreshTimer.Elapsed.TotalSeconds;source_files=$refreshManifest.Count;refreshed_files=$refreshChanged;boundary='Incremental compile of validated isolated copy only. No executable launch, installation, native or owner acceptance.'}|ConvertTo-Json|Set-Content -Encoding utf8 -LiteralPath (Join-Path $PSScriptRoot "windows-build-$EvidenceTag.json")
exit $refreshCode

