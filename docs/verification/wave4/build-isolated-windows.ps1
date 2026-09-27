[CmdletBinding()]
param([Parameter(Mandatory=$true)][string]$Target)
$ErrorActionPreference = 'Stop'
$taskSource = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../..'))
$taskTarget = [IO.Path]::GetFullPath($Target)
if ($taskTarget.StartsWith($taskSource,[StringComparison]::OrdinalIgnoreCase) -or
    $taskTarget -notmatch '^C:\\jw4[a-z0-9-]+$' -or (Test-Path -LiteralPath $taskTarget)) {
  throw 'Use a new short, task-owned C:\jw4... directory outside the shared source.'
}
New-Item -ItemType Directory -Path $taskTarget | Out-Null
& robocopy $taskSource $taskTarget /E /XJ /NFL /NDL /NJH /NJS /NP /R:1 /W:1 `
  /XD .git .dart_tool build .codex .agents .idea .vscode .supabase node_modules ephemeral `
  /XF '.env*' '*.env' '*secret*.json' 'env.*.json' '*.local.json' '.flutter-plugins-dependencies' '*auth*.sqlite' '*auth*.db'
if ($LASTEXITCODE -ge 8) { throw "Isolated source copy failed: $LASTEXITCODE" }
$taskOwnedPaths = @(
  'apps/jentra_desktop/lib/main.dart','apps/jentra_desktop/lib/src/router.dart',
  'apps/jentra_desktop/lib/src/shell/navigation.dart',
  'apps/jentra_desktop/lib/src/features/people/calendar_screen.dart',
  'apps/jentra_desktop/lib/src/features/people/calendar_resolution_dialog.dart',
  'apps/jentra_desktop/lib/src/features/people/organization_controller.dart',
  'apps/jentra_desktop/lib/src/features/people/organization_screen.dart',
  'packages/jentra_domain/lib/src/calendar_resolution.dart','packages/jentra_domain/lib/src/organization.dart',
  'packages/jentra_domain/lib/jentra_people.dart','packages/jentra_platform/lib/jentra_people_platform.dart',
  'packages/jentra_platform/lib/src/scoped_command_draft_store.dart',
  'packages/jentra_platform/lib/src/supabase_calendar_gateway.dart',
  'packages/jentra_platform/lib/src/supabase_organization_gateway.dart'
)
$taskManifest = foreach ($taskPath in $taskOwnedPaths) {
  $taskCopied = (Get-FileHash -Algorithm SHA256 -LiteralPath (Join-Path $taskTarget $taskPath)).Hash
  $taskOriginal = (Get-FileHash -Algorithm SHA256 -LiteralPath (Join-Path $taskSource $taskPath)).Hash
  if ($taskCopied -ne $taskOriginal) { throw "Source changed during copy: $taskPath" }
  [PSCustomObject]@{path=$taskPath;sha256=$taskCopied}
}
$taskManifest | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $PSScriptRoot 'organization-build-source-hashes-20260927.json') -Encoding utf8
Set-Location -LiteralPath $taskTarget
$env:CI = 'true'
& 'C:\src\flutter\bin\cache\dart-sdk\bin\dart.exe' 'C:\src\flutter\bin\cache\flutter_tools.snapshot' pub get --offline
if ($LASTEXITCODE -ne 0) { throw "Isolated dependency resolution failed: $LASTEXITCODE" }
Set-Location -LiteralPath (Join-Path $taskTarget 'apps/jentra_desktop')
& 'C:\src\flutter\bin\cache\dart-sdk\bin\dart.exe' 'C:\src\flutter\bin\cache\flutter_tools.snapshot' build windows --release --no-pub
if ($LASTEXITCODE -ne 0) { throw "Isolated Windows build failed: $LASTEXITCODE" }
$taskBinary = Join-Path $taskTarget 'apps/jentra_desktop/build/windows/x64/runner/Release/jentra_desktop.exe'
Get-FileHash -Algorithm SHA256 -LiteralPath $taskBinary | Select-Object Path,Hash | ConvertTo-Json
