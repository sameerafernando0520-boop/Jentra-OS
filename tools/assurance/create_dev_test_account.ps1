#requires -Version 5.1
<#
.SYNOPSIS
Creates or resumes one isolated assurance Auth fixture on the development project.
.DESCRIPTION
Requires an authenticated Supabase CLI and .env.acceptance.json with the exact
development URL, publishable key and JENTRA_ENVIRONMENT=development. API keys are
captured in memory. Credentials are saved with Windows DPAPI under ignored build/.
No Auth settings, existing accounts or existing tenants are changed. An optional
bootstrap uses only the public api.bootstrap_tenant contract and a persisted key.
This script does not enroll MFA, grant assurance roles or perform native acceptance.
.EXAMPLE
& .\tools\assurance\create_dev_test_account.ps1
.EXAMPLE
& .\tools\assurance\create_dev_test_account.ps1 -BootstrapSyntheticTenant
#>
[CmdletBinding()]
param(
  [string]$ConfigPath = '.env.acceptance.json',
  [switch]$BootstrapSyntheticTenant
)

$ErrorActionPreference = 'Stop'
$expectedRef = 'xpdoufauvrbdmxgngetv'
$expectedBase = 'https://xpdoufauvrbdmxgngetv.supabase.co'
$repoRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..'))
$privateRoot = Join-Path $repoRoot 'build\assurance-private'
$checkpointPath = Join-Path $privateRoot 'dev-test-account.clixml'
$lockPath = Join-Path $privateRoot 'dev-test-account.lock'
$lock = $null
$serviceKey = $null
$keyJson = $null
$plainPassword = $null
$accessToken = $null
$sessionClosed = $false
$operationStage = 'configuration'

function Save-FixtureCheckpoint([object]$State) {
  $temporaryPath = $checkpointPath + '.' + [Guid]::NewGuid().ToString('N') + '.tmp'
  try {
    $State | Export-Clixml -LiteralPath $temporaryPath -Depth 8 -Force
    if ([IO.File]::Exists($checkpointPath)) {
      [IO.File]::Replace($temporaryPath, $checkpointPath, $null)
    } else {
      [IO.File]::Move($temporaryPath, $checkpointPath)
    }
  } finally {
    if ([IO.File]::Exists($temporaryPath)) { [IO.File]::Delete($temporaryPath) }
  }
}

function Invoke-DevJson {
  param(
    [string]$Method,
    [string]$Path,
    [hashtable]$Headers,
    [object]$Body = $null,
    [int]$AllowedFailureStatus = 0
  )
  if ($Path -notmatch '^/(auth/v1|rest/v1)/' -or $Path.Contains('..')) {
    throw 'Fixture request path is not allowed.'
  }
  $arguments = @{
    Method = $Method
    Uri = $expectedBase + $Path
    Headers = $Headers
    UseBasicParsing = $true
    MaximumRedirection = 0
    TimeoutSec = 30
    ErrorAction = 'Stop'
    Verbose = $false
    Debug = $false
  }
  if ($null -ne $Body) {
    $arguments.ContentType = 'application/json'
    $arguments.Body = $Body | ConvertTo-Json -Depth 8 -Compress
  }
  try {
    $response = Invoke-WebRequest @arguments
    $value = $null
    if ($response.Content) { $value = $response.Content | ConvertFrom-Json }
    return [pscustomobject]@{ Status = [int]$response.StatusCode; Value = $value }
  } catch {
    $status = 0
    if ($null -ne $_.Exception.Response) {
      $status = [int]$_.Exception.Response.StatusCode
    }
    if ($AllowedFailureStatus -ne 0 -and $status -eq $AllowedFailureStatus) {
      return [pscustomobject]@{ Status = $status; Value = $null }
    }
    throw ('Development fixture request failed (HTTP {0}); provider diagnostics withheld.' -f $status)
  }
}

function Assert-FixtureUser([object]$User, [object]$State) {
  if ($null -eq $User -or $User.id -ne $State.UserId -or
      $User.email -ne $State.Credential.UserName -or
      $User.app_metadata.assurance_fixture_id -ne $State.FixtureId -or
      $User.app_metadata.assurance_fixture_project -ne $expectedRef -or
      [string]::IsNullOrWhiteSpace([string]$User.email_confirmed_at)) {
    throw 'Auth fixture identity or confirmation does not match its checkpoint.'
  }
}

try {
  if ([Environment]::OSVersion.Platform -ne [PlatformID]::Win32NT) {
    throw 'Windows DPAPI is required; this fixture script cannot run on this platform.'
  }
  if (-not [IO.Path]::IsPathRooted($ConfigPath)) {
    $ConfigPath = Join-Path $repoRoot $ConfigPath
  }
  $config = Get-Content -LiteralPath $ConfigPath -Raw | ConvertFrom-Json
  $baseUri = [Uri]$config.SUPABASE_URL
  if ($config.JENTRA_ENVIRONMENT -ne 'development' -or
      $baseUri.Scheme -ne 'https' -or $baseUri.Host -ne ($expectedRef + '.supabase.co') -or
      -not $baseUri.IsDefaultPort -or $baseUri.AbsolutePath -ne '/' -or
      $baseUri.Query -or $baseUri.Fragment -or $baseUri.UserInfo -or
      [string]::IsNullOrWhiteSpace([string]$config.SUPABASE_PUBLISHABLE_KEY)) {
    throw 'Fixture provisioning is restricted to the approved development project.'
  }
  # Fail closed if the private checkpoint directory could enter source control.
  $null = & git -C $repoRoot check-ignore --quiet 'build/assurance-private/dev-test-account.clixml' 2>$null
  if ($LASTEXITCODE -ne 0) { throw 'The private fixture checkpoint must be Git-ignored.' }
  $null = New-Item -ItemType Directory -Path $privateRoot -Force
  $operationStage = 'checkpoint'
  try {
    $lock = [IO.File]::Open($lockPath, [IO.FileMode]::OpenOrCreate,
      [IO.FileAccess]::ReadWrite, [IO.FileShare]::None)
  } catch { throw 'Another fixture run owns the checkpoint; wait for it to finish.' }

  if ([IO.File]::Exists($checkpointPath)) {
    try { $state = Import-Clixml -LiteralPath $checkpointPath }
    catch { throw 'Fixture checkpoint could not be decrypted by this Windows user.' }
    if ($state.Version -ne 1 -or $state.ProjectRef -ne $expectedRef -or
        $state.Credential -isnot [System.Management.Automation.PSCredential] -or
        $state.Credential.UserName -notmatch '^assurance-fixture-[a-f0-9]{32}@example\.test$' -or
        $state.UserId -notmatch '^[a-f0-9-]{36}$' -or
        $state.BootstrapKey -notmatch '^[a-f0-9-]{36}$' -or
        $state.FixtureId -notmatch '^[a-f0-9]{32}$' -or
        $state.Credential.UserName -ne ('assurance-fixture-' + $state.FixtureId + '@example.test')) {
      throw 'Fixture checkpoint contract is invalid; no live requests were made.'
    }
  } else {
    $fixtureId = [Guid]::NewGuid().ToString('N')
    $randomBytes = New-Object byte[] 32
    $rng = [Security.Cryptography.RandomNumberGenerator]::Create()
    try { $rng.GetBytes($randomBytes) } finally { $rng.Dispose() }
    $plainPassword = [Convert]::ToBase64String($randomBytes) + '!aA9'
    $credential = New-Object System.Management.Automation.PSCredential (
      ('assurance-fixture-' + $fixtureId + '@example.test'),
      (ConvertTo-SecureString -String $plainPassword -AsPlainText -Force)
    )
    $state = [pscustomobject]@{
      Version = 1
      ProjectRef = $expectedRef
      FixtureId = $fixtureId
      UserId = [Guid]::NewGuid().ToString()
      Credential = $credential
      BootstrapKey = [Guid]::NewGuid().ToString()
      BootstrapResult = $null
      Stage = 'prepared'
      PreparedAtUtc = [DateTime]::UtcNow.ToString('o')
      LastVerifiedAtUtc = $null
    }
    # Persist the exact UUID, email and DPAPI password before any Auth mutation.
    Save-FixtureCheckpoint $state
  }

  # CLI syntax verified with `supabase projects api-keys --help`.
  # Capture stdout in memory and suppress provider stderr; never use --debug.
  $operationStage = 'management_key_lookup'
  try {
    $keyJson = & supabase projects api-keys --project-ref $expectedRef --output json 2>$null
    if ($LASTEXITCODE -ne 0) { throw 'CLI failed.' }
    $keys = ($keyJson -join [Environment]::NewLine) | ConvertFrom-Json
  } catch { throw 'Supabase CLI authentication is unavailable; reconnect and rerun this checkpoint.' }
  $serviceKeys = @($keys | Where-Object { $_.name -eq 'service_role' -and $_.api_key })
  if ($serviceKeys.Count -ne 1) { throw 'Expected exactly one development service-role API key.' }
  $serviceKey = [string]$serviceKeys[0].api_key
  $adminHeaders = @{ apikey = $serviceKey; Authorization = 'Bearer ' + $serviceKey }

  # A preassigned UUID makes a successful-but-interrupted create recoverable
  # without listing unrelated users or changing another account's password.
  $operationStage = 'account_lookup'
  $account = Invoke-DevJson -Method Get -Path ('/auth/v1/admin/users/' + $state.UserId) `
    -Headers $adminHeaders -AllowedFailureStatus 404
  if ($account.Status -eq 404) {
    if ($state.Stage -ne 'prepared') {
      throw 'A previously verified fixture account is missing; refusing to recreate it.'
    }
    $operationStage = 'account_create'
    $plainPassword = $state.Credential.GetNetworkCredential().Password
    $account = Invoke-DevJson -Method Post -Path '/auth/v1/admin/users' -Headers $adminHeaders -Body @{
      id = $state.UserId
      email = $state.Credential.UserName
      password = $plainPassword
      email_confirm = $true
      app_metadata = @{
        assurance_fixture_id = $state.FixtureId
        assurance_fixture_project = $expectedRef
      }
      user_metadata = @{ name = 'Synthetic assurance acceptance fixture' }
    }
  }
  Assert-FixtureUser $account.Value $state
  $state.Stage = 'account_verified'
  Save-FixtureCheckpoint $state

  $operationStage = 'signin'
  $plainPassword = $state.Credential.GetNetworkCredential().Password
  $publicHeaders = @{ apikey = [string]$config.SUPABASE_PUBLISHABLE_KEY }
  $session = Invoke-DevJson -Method Post -Path '/auth/v1/token?grant_type=password' `
    -Headers $publicHeaders -Body @{ email = $state.Credential.UserName; password = $plainPassword }
  $plainPassword = $null
  $accessToken = [string]$session.Value.access_token
  if ([string]::IsNullOrWhiteSpace($accessToken)) { throw 'Sign-in returned no access token.' }
  Assert-FixtureUser $session.Value.user $state
  $userHeaders = @{ apikey = $publicHeaders.apikey; Authorization = 'Bearer ' + $accessToken }
  $operationStage = 'identity_verification'
  $identity = Invoke-DevJson -Method Get -Path '/auth/v1/user' -Headers $userHeaders
  Assert-FixtureUser $identity.Value $state

  if ($BootstrapSyntheticTenant) {
    # Contract: foundation migration core.bootstrap_tenant_impl + API wrapper;
    # the Flutter foundation gateway uses this exact API schema and argument set.
    # The function creates only new tenant records and replays its command receipt.
    $operationStage = 'bootstrap'
    $rpcHeaders = @{
      apikey = $publicHeaders.apikey
      Authorization = 'Bearer ' + $accessToken
      'Content-Profile' = 'api'
      'Accept-Profile' = 'api'
    }
    $bootstrap = Invoke-DevJson -Method Post -Path '/rest/v1/rpc/bootstrap_tenant' `
      -Headers $rpcHeaders -Body @{
        p_name = 'Synthetic assurance fixture ' + $state.FixtureId.Substring(0, 8)
        p_slug = 'assurance-fixture-' + $state.FixtureId
        p_legal_entity_name = 'Synthetic assurance entity'
        p_legal_entity_code = 'SYNTH'
        p_branch_name = 'Synthetic acceptance branch'
        p_branch_code = 'TEST'
        p_timezone = 'Asia/Colombo'
        p_currency_code = 'LKR'
        p_idempotency_key = $state.BootstrapKey
      }
    foreach ($field in @('tenant_id', 'legal_entity_id', 'branch_id', 'membership_id', 'request_id')) {
      $parsedGuid = [Guid]::Empty
      if (-not [Guid]::TryParse([string]$bootstrap.Value.$field, [ref]$parsedGuid) -or
          $parsedGuid -eq [Guid]::Empty) { throw 'Synthetic bootstrap returned an invalid identity.' }
    }
    if ($bootstrap.Value.mfa_required -ne $true) { throw 'Synthetic tenant must retain its MFA requirement.' }
    if ($null -ne $state.BootstrapResult -and
        $state.BootstrapResult.tenant_id -ne $bootstrap.Value.tenant_id) {
      throw 'Synthetic bootstrap replay returned a different tenant.'
    }
    $state.BootstrapResult = $bootstrap.Value
  }
  $state.Stage = 'signin_verified'
  $state.LastVerifiedAtUtc = [DateTime]::UtcNow.ToString('o')
  Save-FixtureCheckpoint $state

  $operationStage = 'session_cleanup'
  $null = Invoke-DevJson -Method Post -Path '/auth/v1/logout?scope=local' -Headers $userHeaders
  $sessionClosed = $true
  $accessToken = $null
  [pscustomobject]@{
    project = $expectedRef
    environment = 'development'
    fixtureId = $state.FixtureId
    userId = $state.UserId
    email = $state.Credential.UserName
    identityVerified = $true
    smokeSessionClosed = $sessionClosed
    syntheticTenantPrepared = ($null -ne $state.BootstrapResult)
    tenantId = $(if ($null -ne $state.BootstrapResult) { $state.BootstrapResult.tenant_id } else { $null })
    credentials = 'Windows DPAPI checkpoint under ignored build/assurance-private; not printed'
    pending = @('MFA enrollment', 'assurance role acceptance', 'native Windows walkthrough', 'screen-reader walkthrough', 'owner sign-off')
  } | ConvertTo-Json -Depth 5
} catch {
  # Local JSON/serialization errors can also contain values. Never forward an
  # arbitrary exception message, provider body, request body or credential.
  throw ('Development fixture did not complete at stage: {0}. Checkpoint retained for retry. Check the development configuration and Supabase CLI login; provider diagnostics withheld.' -f $operationStage)
} finally {
  if ($accessToken -and -not $sessionClosed) {
    try {
      $cleanupHeaders = @{ apikey = [string]$config.SUPABASE_PUBLISHABLE_KEY; Authorization = 'Bearer ' + $accessToken }
      $null = Invoke-DevJson -Method Post -Path '/auth/v1/logout?scope=local' -Headers $cleanupHeaders
    } catch { Write-Warning 'Synthetic smoke session could not be closed; retry after restoring the connection.' }
  }
  $plainPassword = $null
  $accessToken = $null
  $serviceKey = $null
  $keyJson = $null
  $keys = $null
  $serviceKeys = $null
  $session = $null
  if ($null -ne $lock) { $lock.Dispose() }
}
