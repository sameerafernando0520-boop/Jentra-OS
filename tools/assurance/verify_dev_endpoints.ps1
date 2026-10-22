param(
  [string]$ConfigPath = '.env.acceptance.json',
  [string]$OutputPath = 'docs/verification/assurance/dev-endpoints-20261021.json'
)

$ErrorActionPreference = 'Stop'
$config = Get-Content -LiteralPath $ConfigPath -Raw | ConvertFrom-Json
$expectedHost = 'xpdoufauvrbdmxgngetv.supabase.co'
$baseUri = [Uri]$config.SUPABASE_URL
if ($config.JENTRA_ENVIRONMENT -ne 'development' -or
    $baseUri.Scheme -ne 'https' -or $baseUri.Host -ne $expectedHost -or
    -not $baseUri.IsDefaultPort -or $baseUri.AbsolutePath -ne '/' -or
    $baseUri.Query -or $baseUri.Fragment -or $baseUri.UserInfo -or
    [string]::IsNullOrWhiteSpace($config.SUPABASE_PUBLISHABLE_KEY)) {
  throw 'This check is restricted to the approved development project.'
}

function Get-RefusalStatus([string]$Slug, [bool]$InvalidToken) {
  $headers = @{ apikey = $config.SUPABASE_PUBLISHABLE_KEY }
  if ($InvalidToken) { $headers.Authorization = 'Bearer assurance-invalid-test-token' }
  try {
    $response = Invoke-WebRequest -UseBasicParsing -Method Post -Uri (
      $baseUri.AbsoluteUri.TrimEnd('/') + '/functions/v1/' + $Slug
    ) -Headers $headers -ContentType 'application/json' -Body '{}' -TimeoutSec 30
    return [int]$response.StatusCode
  } catch {
    if ($null -ne $_.Exception.Response) {
      return [int]$_.Exception.Response.StatusCode
    }
    throw 'Development endpoint could not be reached; provider diagnostics were withheld.'
  }
}

$settings = Invoke-RestMethod -Method Get -Uri (
  $baseUri.AbsoluteUri.TrimEnd('/') + '/auth/v1/settings'
) -Headers @{ apikey = $config.SUPABASE_PUBLISHABLE_KEY } -TimeoutSec 30
$checks = @()
foreach ($slug in @('assurance-evidence-verify', 'assurance-evidence-download')) {
  foreach ($invalidToken in @($false, $true)) {
    $status = Get-RefusalStatus $slug $invalidToken
    $checks += [ordered]@{
      function = $slug
      credential = $(if ($invalidToken) { 'invalid synthetic bearer' } else { 'no bearer' })
      expectedStatus = 401
      actualStatus = $status
      passed = ($status -eq 401)
    }
  }
}
$record = [ordered]@{
  checkedAtUtc = (Get-Date).ToUniversalTime().ToString('o')
  project = 'xpdoufauvrbdmxgngetv'
  environment = 'development'
  checks = $checks
  auth = [ordered]@{
    signupDisabled = [bool]$settings.disable_signup
    emailEnabled = [bool]$settings.external.email
    emailAutoconfirm = [bool]$settings.mailer_autoconfirm
    anonymousUsersEnabled = [bool]$settings.external.anonymous_users
  }
  testAccountsCreated = $false
  accountProvisioning = 'This public-key check does not provision accounts. Use an authenticated admin connection or a confirmation mailbox; never weaken Auth settings to create fixtures.'
  notEstablished = @('authenticated function/storage behavior', 'member role grants', 'native Windows walkthrough', 'screen-reader walkthrough', 'production state')
}
$json = $record | ConvertTo-Json -Depth 8
[System.IO.File]::WriteAllText(
  [System.IO.Path]::GetFullPath($OutputPath), $json + [Environment]::NewLine,
  (New-Object System.Text.UTF8Encoding($false))
)
Write-Output $json
if (@($checks | Where-Object { -not $_.passed }).Count -gt 0) { exit 1 }
