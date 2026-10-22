[CmdletBinding()]
param([string]$InstallRoot = $PSScriptRoot, [switch]$ConfirmRollback)
$ErrorActionPreference = 'Stop'
if (!$ConfirmRollback) { throw 'Use -ConfirmRollback to select the retained previous desktop release; backend and user data are not rolled back.' }
$InstallRoot = [IO.Path]::GetFullPath($InstallRoot)
$lockPath = Join-Path $InstallRoot 'install.lock'
$lock = $null
try {
  $lock = [IO.File]::Open($lockPath, [IO.FileMode]::CreateNew, [IO.FileAccess]::Write, [IO.FileShare]::None)
  $current = Join-Path $InstallRoot 'current.json'
  $previous = Join-Path $InstallRoot 'previous.json'
  $pointer = Get-Content -LiteralPath $previous -Raw | ConvertFrom-Json
  $active = Get-Content -LiteralPath $current -Raw | ConvertFrom-Json
  if ($pointer.channel -ne $active.channel) { throw 'ROLLBACK_CHANNEL_MISMATCH' }
  # Validate every retained runtime byte before changing the working pointer.
  $verified = & (Join-Path $InstallRoot 'Launch.ps1') -InstallRoot $InstallRoot -VerifyOnly -VerifyPrevious
  $temporary = Join-Path $InstallRoot ('rollback-' + [Guid]::NewGuid().ToString('N') + '.json')
  Copy-Item -LiteralPath $previous -Destination $temporary
  [IO.File]::Replace($temporary, $current, (Join-Path $InstallRoot 'before-rollback.json'))
  $verified
} finally {
  if ($lock) { $lock.Dispose(); Remove-Item -LiteralPath $lockPath -ErrorAction SilentlyContinue }
}
