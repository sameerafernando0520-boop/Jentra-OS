#requires -Version 5.1
<#
.SYNOPSIS
Read-only public Auth and invalid-token redirect diagnostic for Jentra development.
.DESCRIPTION
No actual email, account, confirmation token or Auth setting is used or changed.
Redirects are never followed. Provider bodies and full Location URLs are not logged.
#>
[CmdletBinding()]
param(
  [string]$ConfigPath = '.env.acceptance.json',
  [string]$OutputPath = 'docs/verification/auth/email-confirmation-redirect-20261021.json'
)

$ErrorActionPreference = 'Stop'
$repoRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..'))
$expectedRef = 'xpdoufauvrbdmxgngetv'
$expectedBase = 'https://xpdoufauvrbdmxgngetv.supabase.co'
if (-not [IO.Path]::IsPathRooted($ConfigPath)) { $ConfigPath = Join-Path $repoRoot $ConfigPath }
if (-not [IO.Path]::IsPathRooted($OutputPath)) { $OutputPath = Join-Path $repoRoot $OutputPath }
$client = $null
$handler = $null

function Read-RedirectProbe([string]$RequestUri, [Uri]$RequestedCallback) {
  $response = $null
  try {
    $response = $client.GetAsync($RequestUri, [System.Net.Http.HttpCompletionOption]::ResponseHeadersRead).GetAwaiter().GetResult()
    $location = $response.Headers.Location
    $origin = $null
    $safePath = $null
    $matches = $false
    if ($null -ne $location) {
      if (-not $location.IsAbsoluteUri) { $location = New-Object Uri ([Uri]$expectedBase, $location) }
      # SchemeAndServer excludes any user-info; query and fragment are omitted.
      $origin = $location.GetComponents([UriComponents]::SchemeAndServer, [UriFormat]::UriEscaped)
      $safePath = $location.AbsolutePath
      if ($null -ne $RequestedCallback) {
        $matches = $location.Scheme -eq $RequestedCallback.Scheme -and
          $location.Host -eq $RequestedCallback.Host -and
          $location.Port -eq $RequestedCallback.Port -and
          $location.AbsolutePath -eq $RequestedCallback.AbsolutePath
        if ($matches) { $safePath = '/auth/callback/[synthetic-probe-nonce]' }
      }
    }
    return [ordered]@{
      httpStatus = [int]$response.StatusCode
      observedRedirectOrigin = $origin
      observedRedirectPath = $safePath
      requestedWindowsCallbackPreserved = $(if ($null -ne $RequestedCallback) { $matches } else { $null })
    }
  } finally {
    if ($null -ne $response) { $response.Dispose() }
  }
}

try {
  $config = Get-Content -LiteralPath $ConfigPath -Raw | ConvertFrom-Json
  $baseUri = [Uri]$config.SUPABASE_URL
  if ($config.JENTRA_ENVIRONMENT -ne 'development' -or
      $baseUri.AbsoluteUri -ne ($expectedBase + '/') -or
      [string]::IsNullOrWhiteSpace([string]$config.SUPABASE_PUBLISHABLE_KEY)) {
    throw 'Only the approved Jentra development configuration is allowed.'
  }
  Add-Type -AssemblyName System.Net.Http
  $handler = New-Object System.Net.Http.HttpClientHandler
  $handler.AllowAutoRedirect = $false
  $client = New-Object System.Net.Http.HttpClient ($handler)
  $client.Timeout = [TimeSpan]::FromSeconds(30)
  $null = $client.DefaultRequestHeaders.TryAddWithoutValidation('apikey', [string]$config.SUPABASE_PUBLISHABLE_KEY)
  $settingsResponse = $null
  try {
    $settingsResponse = $client.GetAsync($expectedBase + '/auth/v1/settings').GetAwaiter().GetResult()
    if ([int]$settingsResponse.StatusCode -ne 200) { throw 'Public settings lookup failed.' }
    $settings = $settingsResponse.Content.ReadAsStringAsync().GetAwaiter().GetResult() | ConvertFrom-Json
    if ($settings.external.email -isnot [bool] -or
        $settings.mailer_autoconfirm -isnot [bool] -or
        $settings.disable_signup -isnot [bool]) { throw 'Public settings response was incomplete.' }
  } finally {
    if ($null -ne $settingsResponse) { $settingsResponse.Dispose() }
  }

  $nonceBytes = New-Object byte[] 32
  $random = [Security.Cryptography.RandomNumberGenerator]::Create()
  try { $random.GetBytes($nonceBytes) } finally { $random.Dispose() }
  $nonce = [Convert]::ToBase64String($nonceBytes).TrimEnd('=').Replace('+', '-').Replace('/', '_')
  $callback = [Uri]('http://127.0.0.1:56327/auth/callback/' + $nonce)
  # Deliberately not a token-hash format; it cannot identify a real confirmation.
  $invalidToken = 'jentra-invalid-readonly-probe-' + [Guid]::NewGuid().ToString('N')
  $verify = $expectedBase + '/auth/v1/verify?token=' + [Uri]::EscapeDataString($invalidToken) + '&type=signup'
  $defaultProbe = Read-RedirectProbe $verify $null
  $windowsProbe = Read-RedirectProbe ($verify + '&redirect_to=' + [Uri]::EscapeDataString($callback.AbsoluteUri)) $callback
  $record = [ordered]@{
    checkedAtUtc = [DateTime]::UtcNow.ToString('o')
    project = $expectedRef
    environment = 'development'
    publicAuthSettings = [ordered]@{
      emailEnabled = $settings.external.email
      emailAutoconfirm = $settings.mailer_autoconfirm
      signupDisabled = $settings.disable_signup
    }
    method = 'GET /auth/v1/verify with a deliberately invalid synthetic token, type=signup; redirects disabled'
    defaultErrorRedirect = $defaultProbe
    requestedWindowsErrorRedirect = $windowsProbe
    expectedWindowsRedirectPattern = 'http://127.0.0.1:56327/auth/callback/*'
    changesMade = $false
    emailsSent = $false
    accountsCreated = $false
    realConfirmationTokensUsed = $false
    redirectsFollowed = $false
    inferenceLimit = 'An invalid-token error redirect reveals effective redirect selection only. It does not read private Site URL/allowlist/template configuration or prove a valid email confirmation, PKCE exchange or native session.'
    notVerified = @('private Site URL and redirect allowlist', 'deployed email template', 'real confirmation delivery and consumption', 'native confirmation/session acceptance')
    sources = @('https://supabase.com/docs/guides/auth/auth-email-templates', 'https://supabase.com/docs/guides/auth/redirect-urls', 'https://github.com/supabase/auth/blob/master/internal/api/verify.go')
  }
  $json = $record | ConvertTo-Json -Depth 8
  $null = New-Item -ItemType Directory -Path ([IO.Path]::GetDirectoryName($OutputPath)) -Force
  [IO.File]::WriteAllText($OutputPath, $json + [Environment]::NewLine, (New-Object Text.UTF8Encoding($false)))
  Write-Output $json
} catch {
  throw 'Email-confirmation redirect diagnostic could not complete; provider details withheld. No settings, emails or accounts were changed.'
} finally {
  if ($null -ne $client) { $client.Dispose() }
  if ($null -ne $handler) { $handler.Dispose() }
}
