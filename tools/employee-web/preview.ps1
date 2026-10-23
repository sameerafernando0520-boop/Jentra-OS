param(
    [Parameter(Mandatory = $true)][string]$ReleaseDirectory,
    [Parameter(Mandatory = $true)][ValidatePattern('^employee-(qa|preview)-[a-z0-9-]{1,40}$')][string]$Channel,
    [string]$FirebaseCommand = 'firebase',
    [string]$NodeCommand = 'node'
)

$ErrorActionPreference = 'Stop'
$previewRelease = (Resolve-Path -LiteralPath $ReleaseDirectory).Path
& $NodeCommand (Join-Path $PSScriptRoot 'prepare.mjs') verify $previewRelease
if ($LASTEXITCODE -ne 0) { throw 'The preview package failed integrity checks.' }

# This tool intentionally has no live deployment or promotion path.
Push-Location -LiteralPath $previewRelease
try {
    & $FirebaseCommand hosting:channel:deploy $Channel --expires 7d --project jentra-os --config firebase.json
    if ($LASTEXITCODE -ne 0) { throw "Preview deployment failed with exit code $LASTEXITCODE." }
} finally {
    Pop-Location
}
