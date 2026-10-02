[CmdletBinding()]
param([Parameter(Mandatory=$true)][string]$Target,[ValidatePattern('^[a-z0-9-]+$')][string]$EvidenceTag='20260930')
$ErrorActionPreference='Stop'
$taskSource=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../..'))
$taskTarget=[IO.Path]::GetFullPath($Target)
if($taskTarget.StartsWith($taskSource,[StringComparison]::OrdinalIgnoreCase) -or
 $taskTarget -notmatch '^C:\\jw3-[a-z0-9-]+$' -or (Test-Path -LiteralPath $taskTarget)){
 throw 'Use a new short, task-owned C:\jw3-... directory outside the shared source.'
}
$taskPaths=@(& rg --files apps packages -g '*.dart' -g 'pubspec.yaml' -g '*.h' -g '*.cpp' -g '*.rc' -g 'CMakeLists.txt' -g '*.manifest' -g '*.ico' -g '*.ttf' -g '*.otf' -g '*.svg' -g '*.png' -g '!test/**' -g '!**/test/**' -g '!**/build/**' -g '!**/.dart_tool/**') + @('pubspec.yaml','pubspec.lock')
$taskBefore=@{}
foreach($taskPath in $taskPaths){$taskBefore[$taskPath]=(Get-FileHash -Algorithm SHA256 -LiteralPath (Join-Path $taskSource $taskPath)).Hash}
New-Item -ItemType Directory -Path $taskTarget|Out-Null
& robocopy $taskSource $taskTarget /E /XJ /NFL /NDL /NJH /NJS /NP /R:1 /W:1 /XD .git .dart_tool build .codex .agents .idea .vscode .supabase node_modules ephemeral failures /XF '.env*' '*.env' '*secret*.json' 'env.*.json' '*.local.json' '.flutter-plugins-dependencies' '*.sqlite*' '*.db*'
if($LASTEXITCODE -ge 8){throw "Isolated source copy failed: $LASTEXITCODE"}
$taskManifest=foreach($taskPath in $taskPaths){
 $taskCopied=(Get-FileHash -Algorithm SHA256 -LiteralPath (Join-Path $taskTarget $taskPath)).Hash
 $taskOriginal=(Get-FileHash -Algorithm SHA256 -LiteralPath (Join-Path $taskSource $taskPath)).Hash
 if($taskCopied -ne $taskOriginal -or $taskCopied -ne $taskBefore[$taskPath]){throw "Source changed during copy: $taskPath"}
 [PSCustomObject]@{path=$taskPath;sha256=$taskCopied}
}
$taskManifest|ConvertTo-Json|Set-Content -LiteralPath (Join-Path $PSScriptRoot "windows-source-hashes-$EvidenceTag.json") -Encoding utf8
$taskTimer=[Diagnostics.Stopwatch]::StartNew()
Set-Location -LiteralPath $taskTarget
$env:CI='true'
& 'C:\src\flutter\bin\cache\dart-sdk\bin\dart.exe' 'C:\src\flutter\bin\cache\flutter_tools.snapshot' pub get --offline
if($LASTEXITCODE -ne 0){throw "Isolated dependency resolution failed: $LASTEXITCODE"}
Set-Location -LiteralPath (Join-Path $taskTarget 'apps/jentra_desktop')
& 'C:\src\flutter\bin\cache\dart-sdk\bin\dart.exe' 'C:\src\flutter\bin\cache\flutter_tools.snapshot' build windows --release --no-pub
if($LASTEXITCODE -ne 0){
 $taskBuildExit=$LASTEXITCODE
 $taskTimer.Stop()
 [PSCustomObject]@{target=$taskTarget;status='failed';exit_code=$taskBuildExit;seconds=$taskTimer.Elapsed.TotalSeconds;source_files=$taskManifest.Count;boundary='Isolated compilation failed. No executable was launched; installation and native acceptance not performed.'}|ConvertTo-Json|Set-Content -LiteralPath (Join-Path $PSScriptRoot "windows-build-$EvidenceTag.json") -Encoding utf8
 throw "Isolated Windows build failed: $taskBuildExit"
}
$taskTimer.Stop()
$taskBinary=Join-Path $taskTarget 'apps/jentra_desktop/build/windows/x64/runner/Release/jentra_desktop.exe'
$taskCurrentMatch=$true
foreach($taskPath in $taskPaths){if((Get-FileHash -Algorithm SHA256 -LiteralPath (Join-Path $taskSource $taskPath)).Hash -ne $taskBefore[$taskPath]){$taskCurrentMatch=$false}}
[PSCustomObject]@{target=$taskTarget;status='compiled';current_source_match=$taskCurrentMatch;binary=$taskBinary;sha256=(Get-FileHash -Algorithm SHA256 -LiteralPath $taskBinary).Hash;seconds=$taskTimer.Elapsed.TotalSeconds;source_files=$taskManifest.Count;boundary='Compilation only; executable never launched, installation and native acceptance not performed.'}|ConvertTo-Json|Set-Content -LiteralPath (Join-Path $PSScriptRoot "windows-build-$EvidenceTag.json") -Encoding utf8
