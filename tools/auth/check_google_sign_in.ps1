#requires -Version 5.1
param(
  [string]$ConfigPath = '.env.acceptance.json',
  [string]$OutputPath = 'docs/verification/auth/google-provider-20261021.json'
)

$ErrorActionPreference = 'Stop'
$config = Get-Content -LiteralPath $ConfigPath -Raw | ConvertFrom-Json
$baseUri = [Uri]$config.SUPABASE_URL
if ($config.JENTRA_ENVIRONMENT -ne 'development' -or
    $baseUri.Scheme -ne 'https' -or
    $baseUri.Host -ne 'xpdoufauvrbdmxgngetv.supabase.co' -or
    -not $baseUri.IsDefaultPort -or $baseUri.AbsolutePath -ne '/' -or
    $baseUri.Query -or $baseUri.Fragment -or $baseUri.UserInfo -or
    [string]::IsNullOrWhiteSpace($config.SUPABASE_PUBLISHABLE_KEY)) {
  throw 'Google readiness checks are restricted to the Jentra development project.'
}

try {
  $settings = Invoke-RestMethod -Uri ($baseUri.AbsoluteUri.TrimEnd('/') + '/auth/v1/settings') `
    -Headers @{apikey=$config.SUPABASE_PUBLISHABLE_KEY} -TimeoutSec 30
} catch {
  throw 'Could not read public Auth settings; provider diagnostics withheld.'
}
if ($settings.external.google -isnot [bool]) {
  throw 'Public Auth settings did not contain a Google provider flag.'
}
$record = [ordered]@{
  checkedAtUtc = [DateTime]::UtcNow.ToString('o')
  project = 'xpdoufauvrbdmxgngetv'
  environment = 'development'
  googleEnabled = $settings.external.google
  googleClientRedirectUri = 'https://xpdoufauvrbdmxgngetv.supabase.co/auth/v1/callback'
  supabaseWindowsRedirectPattern = 'http://127.0.0.1:56327/auth/callback/*'
  providerSettings = 'https://supabase.com/dashboard/project/xpdoufauvrbdmxgngetv/auth/providers'
  urlSettings = 'https://supabase.com/dashboard/project/xpdoufauvrbdmxgngetv/auth/url-configuration'
  changesMade = $false
  notVerified = @('Google OAuth client ID/secret correctness', 'hosted Windows redirect allowlist', 'real Google consent and native session')
}
$destination = [IO.Path]::GetFullPath($OutputPath)
$null = New-Item -ItemType Directory -Path ([IO.Path]::GetDirectoryName($destination)) -Force
$json = $record | ConvertTo-Json -Depth 5
[IO.File]::WriteAllText($destination, $json + [Environment]::NewLine, (New-Object Text.UTF8Encoding($false)))
Write-Output $json
if (-not $settings.external.google) { exit 1 }
