[CmdletBinding()]
param([Parameter(Mandatory=$true)][string]$Target,[switch]$RefreshOwned)
$ErrorActionPreference = 'Stop'
$taskSource = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../..'))
$taskTarget = [IO.Path]::GetFullPath($Target)
if ($taskTarget.StartsWith($taskSource,[StringComparison]::OrdinalIgnoreCase) -or
    $taskTarget -notmatch '^C:\\jw4-client-[a-z0-9-]+$') {
  throw 'Use a new task-owned C:\jw4-client-... directory outside the shared source.'
}
if (Test-Path -LiteralPath $taskTarget) {
  if (-not $RefreshOwned) { throw 'Existing build directory requires explicit task-owned refresh.' }
  $taskPrevious = Get-Content -LiteralPath (Join-Path $PSScriptRoot 'client-windows-build-20260930.json') -Raw | ConvertFrom-Json
  $taskExpectedBinary = Join-Path $taskTarget 'apps/jentra_desktop/build/windows/x64/runner/Release/jentra_desktop.exe'
  if ($taskPrevious.path -ne $taskExpectedBinary -or
      (Get-FileHash -Algorithm SHA256 -LiteralPath $taskExpectedBinary).Hash -ne $taskPrevious.sha256) {
    throw 'Existing directory does not match this task verified build.'
  }
} else {
  if ($RefreshOwned) { throw 'Refresh requires this task existing verified build.' }
  New-Item -ItemType Directory -Path $taskTarget | Out-Null
}
& robocopy $taskSource $taskTarget /E /XJ /NFL /NDL /NJH /NJS /NP /R:1 /W:1 /XD .git .dart_tool build .codex .agents .idea .vscode .supabase node_modules ephemeral /XF '.env*' '*.env' '*secret*.json' 'env.*.json' '*.local.json' '.flutter-plugins-dependencies' '*.sqlite*' '*.db*'
if ($LASTEXITCODE -ge 8) { throw "Isolated copy failed: $LASTEXITCODE" }
$taskPaths = @(
  'pubspec.lock','apps/jentra_desktop/pubspec.yaml',
  'apps/jentra_desktop/lib/main.dart','apps/jentra_desktop/lib/src/router.dart','apps/jentra_desktop/lib/src/shell/navigation.dart',
  'apps/jentra_desktop/lib/src/features/people/workforce_controller.dart','apps/jentra_desktop/lib/src/features/people/workforce_screen.dart',
  'apps/jentra_desktop/lib/src/features/people/private_hr_controller.dart','apps/jentra_desktop/lib/src/features/people/private_hr_screen.dart',
  'packages/jentra_domain/lib/jentra_people.dart','packages/jentra_domain/lib/src/workforce.dart','packages/jentra_domain/lib/src/work_time.dart','packages/jentra_domain/lib/src/private_hr.dart',
  'packages/jentra_platform/lib/jentra_people_platform.dart','packages/jentra_platform/lib/src/supabase_workforce_gateway.dart','packages/jentra_platform/lib/src/sensitive_leave_draft_store.dart',
  'packages/jentra_platform/lib/src/supabase_private_hr_gateway.dart','packages/jentra_platform/lib/src/private_hr_files.dart',
  'supabase/migrations/20260929224939_wave4_private_hr.sql','supabase/migrations/20260928082234_wave4_attendance_intervals.sql','supabase/migrations/20260928083449_wave4_leave_ledger.sql'
)
$taskManifest = foreach ($taskPath in $taskPaths) {
  $taskCopied = (Get-FileHash -Algorithm SHA256 -LiteralPath (Join-Path $taskTarget $taskPath)).Hash
  $taskOriginal = (Get-FileHash -Algorithm SHA256 -LiteralPath (Join-Path $taskSource $taskPath)).Hash
  if ($taskCopied -ne $taskOriginal) { throw "Source changed during copy: $taskPath" }
  [PSCustomObject]@{path=$taskPath;sha256=$taskCopied}
}
$taskManifest | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $PSScriptRoot 'client-source-hashes-20260930.json') -Encoding utf8
Set-Location -LiteralPath $taskTarget
$env:CI = 'true'
& 'C:\src\flutter\bin\cache\dart-sdk\bin\dart.exe' 'C:\src\flutter\bin\cache\flutter_tools.snapshot' pub get --offline
if ($LASTEXITCODE -ne 0) { throw "Isolated dependency resolution failed: $LASTEXITCODE" }
Set-Location -LiteralPath (Join-Path $taskTarget 'apps/jentra_desktop')
& 'C:\src\flutter\bin\cache\dart-sdk\bin\dart.exe' 'C:\src\flutter\bin\cache\flutter_tools.snapshot' build windows --release --no-pub
if ($LASTEXITCODE -ne 0) { throw "Isolated Windows build failed: $LASTEXITCODE" }
$taskBinary = Join-Path $taskTarget 'apps/jentra_desktop/build/windows/x64/runner/Release/jentra_desktop.exe'
$taskAot = Join-Path $taskTarget 'apps/jentra_desktop/build/windows/x64/runner/Release/data/app.so'
$taskResult = [PSCustomObject]@{path=$taskBinary;sha256=(Get-FileHash -Algorithm SHA256 -LiteralPath $taskBinary).Hash;aotPath=$taskAot;aotSha256=(Get-FileHash -Algorithm SHA256 -LiteralPath $taskAot).Hash;builtAt=(Get-Date).ToUniversalTime().ToString('o')}
$taskResult | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $PSScriptRoot 'client-windows-build-20260930.json') -Encoding utf8
$taskResult | ConvertTo-Json
