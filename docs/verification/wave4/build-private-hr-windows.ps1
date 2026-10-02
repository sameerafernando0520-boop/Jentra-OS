[CmdletBinding()]
param([Parameter(Mandatory=$true)][string]$Target)
$ErrorActionPreference='Stop'
$taskSource=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../..'))
$taskTarget=[IO.Path]::GetFullPath($Target)
if($taskTarget.StartsWith($taskSource,[StringComparison]::OrdinalIgnoreCase) -or
 $taskTarget -notmatch '^C:\\jw4hr-[a-z0-9-]+$' -or (Test-Path -LiteralPath $taskTarget)){
 throw 'Use a new short, task-owned C:\jw4hr-... directory outside the shared source.'
}
New-Item -ItemType Directory -Path $taskTarget|Out-Null
& robocopy $taskSource $taskTarget /E /XJ /NFL /NDL /NJH /NJS /NP /R:1 /W:1 /XD .git .dart_tool build .codex .agents .idea .vscode .supabase node_modules ephemeral /XF '.env*' '*.env' '*secret*.json' 'env.*.json' '*.local.json' '.flutter-plugins-dependencies' '*.sqlite*' '*.db*'
if($LASTEXITCODE -ge 8){throw "Isolated source copy failed: $LASTEXITCODE"}
$taskOwnedPaths=@(
 'pubspec.lock','apps/jentra_desktop/pubspec.yaml',
 'apps/jentra_desktop/lib/main.dart','apps/jentra_desktop/lib/src/router.dart','apps/jentra_desktop/lib/src/shell/navigation.dart',
 'apps/jentra_desktop/lib/src/features/people/private_hr_controller.dart','apps/jentra_desktop/lib/src/features/people/private_hr_screen.dart',
 'packages/jentra_domain/lib/src/private_hr.dart','packages/jentra_domain/lib/jentra_people.dart',
 'packages/jentra_platform/lib/jentra_people_platform.dart','packages/jentra_platform/lib/src/draft_repository.dart',
 'packages/jentra_platform/lib/src/private_hr_draft_store.dart','packages/jentra_platform/lib/src/supabase_private_hr_gateway.dart',
 'packages/jentra_platform/lib/src/private_hr_files.dart','supabase/migrations/20260929224939_wave4_private_hr.sql',
 'supabase/functions/people-private-documents/index.ts','supabase/functions/people-private-documents/handler.mjs',
 'supabase/functions/people-private-purge/index.ts','supabase/functions/people-private-purge/handler.mjs'
)
$taskManifest=foreach($taskPath in $taskOwnedPaths){
 $taskCopied=(Get-FileHash -Algorithm SHA256 -LiteralPath (Join-Path $taskTarget $taskPath)).Hash
 $taskOriginal=(Get-FileHash -Algorithm SHA256 -LiteralPath (Join-Path $taskSource $taskPath)).Hash
 if($taskCopied -ne $taskOriginal){throw "Source changed during copy: $taskPath"}
 [PSCustomObject]@{path=$taskPath;sha256=$taskCopied}
}
$taskManifest|ConvertTo-Json|Set-Content -LiteralPath (Join-Path $PSScriptRoot 'private-hr-build-source-hashes-20260928.json') -Encoding utf8
Set-Location -LiteralPath $taskTarget
$env:CI='true'
& 'C:\src\flutter\bin\cache\dart-sdk\bin\dart.exe' 'C:\src\flutter\bin\cache\flutter_tools.snapshot' pub get --offline
if($LASTEXITCODE -ne 0){throw "Isolated dependency resolution failed: $LASTEXITCODE"}
Set-Location -LiteralPath (Join-Path $taskTarget 'apps/jentra_desktop')
& 'C:\src\flutter\bin\cache\dart-sdk\bin\dart.exe' 'C:\src\flutter\bin\cache\flutter_tools.snapshot' build windows --release --no-pub
if($LASTEXITCODE -ne 0){throw "Isolated Windows build failed: $LASTEXITCODE"}
$taskBinary=Join-Path $taskTarget 'apps/jentra_desktop/build/windows/x64/runner/Release/jentra_desktop.exe'
Get-FileHash -Algorithm SHA256 -LiteralPath $taskBinary|Select-Object Path,Hash|ConvertTo-Json
