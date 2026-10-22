[CmdletBinding()]
param([switch]$ConfirmUninstall)
$ErrorActionPreference = 'Stop'
if (!$ConfirmUninstall) {
  Add-Type -AssemblyName PresentationFramework
  if ([System.Windows.MessageBox]::Show('Remove the Jentra OS shortcut and app registration? App versions and your sign-in, settings and drafts will be retained.','Jentra OS uninstall','YesNo','Question') -ne 'Yes') { exit 0 }
}
$pointer = Get-Content -LiteralPath (Join-Path $PSScriptRoot 'current.json') -Raw | ConvertFrom-Json
if ($pointer.channel -notin @('development','production')) { throw 'INVALID_RELEASE_CHANNEL' }
$displayName = if ($pointer.channel -eq 'production') { 'Jentra OS' } else { 'Jentra OS (Development)' }
$shortcut = Join-Path ([Environment]::GetFolderPath('Programs')) ($displayName + '.lnk')
if (Test-Path -LiteralPath $shortcut) { Remove-Item -LiteralPath $shortcut }
$key = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\JentraOS-' + $pointer.channel
if (Test-Path -LiteralPath $key) { Remove-Item -LiteralPath $key }
Write-Output 'Shortcut and registration removed. Installed versions and user data were retained.'
