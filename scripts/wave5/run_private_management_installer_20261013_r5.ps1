param([ValidateSet('ValidateOnly','Preflight','Execute','VerifyInstalled','ValidateAuth','ProvisionAuth','ValidateMfa','EnrollMfa','ValidateBootstrap','ExecuteBootstrap','ValidateAccess','InspectAccess','ValidateSourceWorkflow','ExecuteSourceWorkflow','RefreshOwnerScope','RefreshOwnerScopeA3','RefreshOwnerScopeA4','RefreshOwnerScopeA5','RefreshOwnerScopeA6','RefreshOwnerScopeA7','RefreshOwnerScopeA8','RefreshOwnerScopeA9','RefreshOwnerScopeA10','InspectSourceFailure','ResumeSourceWorkflows','ContinueSourceWorkflowsA3','ValidateActivation','ExecuteActivation','ValidatePersistentSetup','ExecutePersistentSetup','ExecutePersistentSetupA2','ExecutePersistentSetupA3','ExecutePersistentSetupA4','ExecuteDeliveryLease','ExecuteDeliveryFixtures','StartScheduledDelivery','InspectScheduledError','ReadAuthQuota','PauseFailedSchedules','ValidateFinanceWorkflow','ExecuteFinanceWorkflow','ResumeFinanceWorkflow','ValidateRemainingFinance','ExecuteRemainingFinance','ValidateRemainingFinanceA3','ExecuteRemainingFinanceA3')][string]$Mode = 'ValidateOnly')

$ErrorActionPreference = 'Stop'
$taskRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..'))
$taskInstaller = Join-Path $taskRoot 'tools/wave5/approved_management_installer.mjs'
$taskReadyFile = Join-Path $taskRoot 'docs/verification/wave5/private-owner-input-ready-20261013-r5.json'
if ($Mode -notin @('RefreshOwnerScope','RefreshOwnerScopeA3','RefreshOwnerScopeA4','RefreshOwnerScopeA5','RefreshOwnerScopeA6','RefreshOwnerScopeA7','RefreshOwnerScopeA8','RefreshOwnerScopeA9','RefreshOwnerScopeA10') -and (Test-Path -LiteralPath (Join-Path $taskRoot 'docs/verification/wave5/private-owner-input-ready-20261013-r5-a2.json'))) {
    $taskReadyFile = Join-Path $taskRoot 'docs/verification/wave5/private-owner-input-ready-20261013-r5-a2.json'
}
if ($Mode -notin @('RefreshOwnerScope','RefreshOwnerScopeA3','RefreshOwnerScopeA4','RefreshOwnerScopeA5','RefreshOwnerScopeA6','RefreshOwnerScopeA7','RefreshOwnerScopeA8','RefreshOwnerScopeA9','RefreshOwnerScopeA10') -and (Test-Path -LiteralPath (Join-Path $taskRoot 'docs/verification/wave5/private-owner-input-ready-20261013-r5-a3.json'))) {
    $taskReadyFile = Join-Path $taskRoot 'docs/verification/wave5/private-owner-input-ready-20261013-r5-a3.json'
}
if ($Mode -notin @('RefreshOwnerScope','RefreshOwnerScopeA3','RefreshOwnerScopeA4','RefreshOwnerScopeA5','RefreshOwnerScopeA6','RefreshOwnerScopeA7','RefreshOwnerScopeA8','RefreshOwnerScopeA9','RefreshOwnerScopeA10') -and (Test-Path -LiteralPath (Join-Path $taskRoot 'docs/verification/wave5/private-owner-input-ready-20261013-r5-a4.json'))) {
    $taskReadyFile = Join-Path $taskRoot 'docs/verification/wave5/private-owner-input-ready-20261013-r5-a4.json'
}
if ($Mode -notin @('RefreshOwnerScope','RefreshOwnerScopeA3','RefreshOwnerScopeA4','RefreshOwnerScopeA5','RefreshOwnerScopeA6','RefreshOwnerScopeA7','RefreshOwnerScopeA8','RefreshOwnerScopeA9','RefreshOwnerScopeA10') -and (Test-Path -LiteralPath (Join-Path $taskRoot 'docs/verification/wave5/private-owner-input-ready-20261013-r5-a5.json'))) {
    $taskReadyFile = Join-Path $taskRoot 'docs/verification/wave5/private-owner-input-ready-20261013-r5-a5.json'
}
if ($Mode -notin @('RefreshOwnerScope','RefreshOwnerScopeA3','RefreshOwnerScopeA4','RefreshOwnerScopeA5','RefreshOwnerScopeA6','RefreshOwnerScopeA7','RefreshOwnerScopeA8','RefreshOwnerScopeA9','RefreshOwnerScopeA10') -and (Test-Path -LiteralPath (Join-Path $taskRoot 'docs/verification/wave5/private-owner-input-ready-20261014-r5-a6.json'))) {
    $taskReadyFile = Join-Path $taskRoot 'docs/verification/wave5/private-owner-input-ready-20261014-r5-a6.json'
}
if ($Mode -notin @('RefreshOwnerScope','RefreshOwnerScopeA3','RefreshOwnerScopeA4','RefreshOwnerScopeA5','RefreshOwnerScopeA6','RefreshOwnerScopeA7','RefreshOwnerScopeA8','RefreshOwnerScopeA9','RefreshOwnerScopeA10') -and (Test-Path -LiteralPath (Join-Path $taskRoot 'docs/verification/wave5/private-owner-input-ready-20261014-r5-a7.json'))) {
    $taskReadyFile = Join-Path $taskRoot 'docs/verification/wave5/private-owner-input-ready-20261014-r5-a7.json'
}
if ($Mode -notin @('RefreshOwnerScope','RefreshOwnerScopeA3','RefreshOwnerScopeA4','RefreshOwnerScopeA5','RefreshOwnerScopeA6','RefreshOwnerScopeA7','RefreshOwnerScopeA8','RefreshOwnerScopeA9','RefreshOwnerScopeA10') -and (Test-Path -LiteralPath (Join-Path $taskRoot 'docs/verification/wave5/private-owner-input-ready-20261014-r5-a8.json'))) {
    $taskReadyFile = Join-Path $taskRoot 'docs/verification/wave5/private-owner-input-ready-20261014-r5-a8.json'
}
if ($Mode -notin @('RefreshOwnerScope','RefreshOwnerScopeA3','RefreshOwnerScopeA4','RefreshOwnerScopeA5','RefreshOwnerScopeA6','RefreshOwnerScopeA7','RefreshOwnerScopeA8','RefreshOwnerScopeA9','RefreshOwnerScopeA10') -and (Test-Path -LiteralPath (Join-Path $taskRoot 'docs/verification/wave5/private-owner-input-ready-20261014-r5-a9.json'))) {
    $taskReadyFile = Join-Path $taskRoot 'docs/verification/wave5/private-owner-input-ready-20261014-r5-a9.json'
}
if ($Mode -notin @('RefreshOwnerScope','RefreshOwnerScopeA3','RefreshOwnerScopeA4','RefreshOwnerScopeA5','RefreshOwnerScopeA6','RefreshOwnerScopeA7','RefreshOwnerScopeA8','RefreshOwnerScopeA9','RefreshOwnerScopeA10') -and (Test-Path -LiteralPath (Join-Path $taskRoot 'docs/verification/wave5/private-owner-input-ready-20261014-r5-a10.json'))) {
    $taskReadyFile = Join-Path $taskRoot 'docs/verification/wave5/private-owner-input-ready-20261014-r5-a10.json'
}
$taskSecret = $null
$taskBstr = [IntPtr]::Zero
$taskPlain = $null
$taskChild = $null
$taskPhase = 'source-validation'
$taskNeedsPrivate = $Mode -in @('Preflight','Execute','VerifyInstalled','ProvisionAuth','EnrollMfa','ExecuteBootstrap','InspectAccess','ExecuteSourceWorkflow','RefreshOwnerScope','RefreshOwnerScopeA3','RefreshOwnerScopeA4','RefreshOwnerScopeA5','RefreshOwnerScopeA6','RefreshOwnerScopeA7','RefreshOwnerScopeA8','RefreshOwnerScopeA9','RefreshOwnerScopeA10','InspectSourceFailure','ResumeSourceWorkflows','ContinueSourceWorkflowsA3','ExecuteActivation','ExecutePersistentSetup','ExecutePersistentSetupA2','ExecutePersistentSetupA3','ExecutePersistentSetupA4','ExecuteDeliveryLease','ExecuteDeliveryFixtures','StartScheduledDelivery','InspectScheduledError','ReadAuthQuota','PauseFailedSchedules','ExecuteFinanceWorkflow','ResumeFinanceWorkflow','ExecuteRemainingFinance','ExecuteRemainingFinanceA3')

function Assert-TaskPrivateAcl([string]$TaskPath, [Security.Principal.SecurityIdentifier]$TaskSid, [bool]$TaskFolder) {
    $taskItem = Get-Item -LiteralPath $TaskPath
    if (($taskItem.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { throw 'PRIVATE_REPARSE_POINT_FORBIDDEN' }
    $taskAcl = Get-Acl -LiteralPath $TaskPath
    $taskRules = @($taskAcl.GetAccessRules($true,$true,[Security.Principal.SecurityIdentifier]))
    if ($taskRules.Count -ne 1 -or $taskRules[0].IdentityReference.Value -ne $TaskSid.Value -or
        $taskRules[0].AccessControlType -ne 'Allow' -or
        $taskRules[0].FileSystemRights -ne [Security.AccessControl.FileSystemRights]::FullControl -or
        ($TaskFolder -and -not $taskAcl.AreAccessRulesProtected)) { throw 'PRIVATE_CURRENT_SID_ACL_REQUIRED' }
}

function Convert-TaskUtcTimestamp([object]$TaskValue) {
    # PowerShell 7.6 decodes ISO JSON dates as DateTime. Parsing its culture-based
    # string form discards Z and shifts expiry by the machine's UTC offset.
    if ($TaskValue -is [DateTimeOffset]) {
        if ($TaskValue.Offset -ne [TimeSpan]::Zero) { throw 'EXACT_UTC_METADATA_REQUIRED' }
        return $TaskValue
    }
    if ($TaskValue -is [DateTime]) {
        if ($TaskValue.Kind -ne [DateTimeKind]::Utc) { throw 'EXACT_UTC_METADATA_REQUIRED' }
        return [DateTimeOffset]::new($TaskValue)
    }
    if ($TaskValue -isnot [string] -or $TaskValue -notmatch '^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(\.\d+)?(Z|\+00:00)$') {
        throw 'EXACT_UTC_METADATA_REQUIRED'
    }
    return [DateTimeOffset]::Parse($TaskValue,[Globalization.CultureInfo]::InvariantCulture)
}

try {
    if ((Get-FileHash -LiteralPath $taskInstaller -Algorithm SHA256).Hash.ToLowerInvariant() -ne
        'f6266b37e9c5eb254a794aedd512984d35865e2ff4ddfd19f6a67cf5f9750bd5') { throw 'INSTALLER_SOURCE_CHANGED' }
    if ($Mode -eq 'VerifyInstalled') {
        $taskInstaller = Join-Path $taskRoot 'tools/wave5/verify_installed_management_20261013_r5.mjs'
        if ((Get-FileHash -LiteralPath $taskInstaller -Algorithm SHA256).Hash.ToLowerInvariant() -ne
            '7a0b1b872c4338be4849365313f47bb3729742c39c500c2ce5acd11f7972c70d') { throw 'VERIFIER_SOURCE_CHANGED' }
    }
    if ($Mode -in @('ValidateAuth','ProvisionAuth')) {
        $taskInstaller = Join-Path $taskRoot 'tools/wave5/provision_auth_management_20261013_r5.mjs'
        if ((Get-FileHash -LiteralPath $taskInstaller -Algorithm SHA256).Hash.ToLowerInvariant() -ne
            'e2c4905e60b8e0a66ef494c296dd0a1e2d26577e60ef48effd530c6de912a5a7') { throw 'AUTH_PROVISIONER_SOURCE_CHANGED' }
    }
    if ($Mode -in @('ValidateMfa','EnrollMfa')) {
        $taskInstaller = Join-Path $taskRoot 'tools/wave5/enroll_mfa_management_20261013_r5.mjs'
        if ((Get-FileHash -LiteralPath $taskInstaller -Algorithm SHA256).Hash.ToLowerInvariant() -ne
            'ede49ffd20a111a063b00b375b32fdef40c69b09364a4ae72e5f2a5e7a608240') { throw 'MFA_VERIFIER_SOURCE_CHANGED' }
    }
    if ($Mode -in @('ValidateBootstrap','ExecuteBootstrap')) {
        $taskInstaller = Join-Path $taskRoot 'tools/wave5/bootstrap_management_20261013_r5.mjs'
        if ((Get-FileHash -LiteralPath $taskInstaller -Algorithm SHA256).Hash.ToLowerInvariant() -ne
            '8ac8cdeab26341c0a53500c4cce3231440d5d171edbd8f340b4fbcbeab1c1d07') { throw 'BOOTSTRAP_EXECUTOR_SOURCE_CHANGED' }
    }
    if ($Mode -in @('ValidateAccess','InspectAccess')) {
        $taskInstaller = Join-Path $taskRoot 'tools/wave5/inspect_runtime_access_20261013_r5.mjs'
        if ((Get-FileHash -LiteralPath $taskInstaller -Algorithm SHA256).Hash.ToLowerInvariant() -ne
            '2b8896abe8d91988655826bddf34a3f1f3569c52362a02f2af8870149e473993') { throw 'ACCESS_INSPECTOR_SOURCE_CHANGED' }
    }
    if ($Mode -in @('ValidateSourceWorkflow','ExecuteSourceWorkflow')) {
        $taskInstaller = Join-Path $taskRoot 'tools/wave5/source_workflow_management_20261013_r5.mjs'
        if ((Get-FileHash -LiteralPath $taskInstaller -Algorithm SHA256).Hash.ToLowerInvariant() -ne
            'aabbeae5af299178bd35784fb8ffefd378ae324a25749c42f9e3d7cd22e107ea') { throw 'SOURCE_WORKFLOW_EXECUTOR_CHANGED' }
    }
    if ($Mode -in @('RefreshOwnerScope','RefreshOwnerScopeA3','RefreshOwnerScopeA4','RefreshOwnerScopeA5','RefreshOwnerScopeA6','RefreshOwnerScopeA7','RefreshOwnerScopeA8','RefreshOwnerScopeA9','RefreshOwnerScopeA10')) {
        $taskInstaller = Join-Path $taskRoot 'tools/wave5/refresh_private_owner_scope_20261013_r5.mjs'
        if ((Get-FileHash -LiteralPath $taskInstaller -Algorithm SHA256).Hash.ToLowerInvariant() -ne
            '1049309eccbec8247cfffc426fa2592547886467cda09f156ddd9636afba5a59') { throw 'OWNER_SCOPE_REFRESH_SOURCE_CHANGED' }
    }
    if ($Mode -eq 'InspectSourceFailure') {
        $taskInstaller = Join-Path $taskRoot 'tools/wave5/inspect_source_failure_20261013_r5.mjs'
        if ((Get-FileHash -LiteralPath $taskInstaller -Algorithm SHA256).Hash.ToLowerInvariant() -ne
            '480e1fa64775553fc19b1eb75f96888780991db410f51914374cab6f9c05f260') { throw 'SOURCE_FAILURE_INSPECTOR_CHANGED' }
    }
    if ($Mode -eq 'ResumeSourceWorkflows') {
        $taskInstaller = Join-Path $taskRoot 'tools/wave5/resume_source_workflows_20261013_r5.mjs'
        if ((Get-FileHash -LiteralPath $taskInstaller -Algorithm SHA256).Hash.ToLowerInvariant() -ne
            '9058710e0468e3b44dee99ae1a6c3c8a414146a50e5b3060df3094030d912200') { throw 'SOURCE_WORKFLOW_RESUME_CHANGED' }
    }
    if ($Mode -eq 'ContinueSourceWorkflowsA3') {
        $taskInstaller = Join-Path $taskRoot 'tools/wave5/continue_source_workflows_20261013_r5_a3.mjs'
        if ((Get-FileHash -LiteralPath $taskInstaller -Algorithm SHA256).Hash.ToLowerInvariant() -ne
            '55c06f4732ec1b15ad235b5c9f461072369e1b94ec1c6ac18ebd3892841adf1b') { throw 'SOURCE_WORKFLOW_A3_CHANGED' }
    }
    if ($Mode -in @('ValidatePersistentSetup','ExecutePersistentSetup')) {
        $taskInstaller = Join-Path $taskRoot 'tools/wave5/persistent_setup_20261013_r5.mjs'
        if ((Get-FileHash -LiteralPath $taskInstaller -Algorithm SHA256).Hash.ToLowerInvariant() -ne
            '3318912e74ae08f17647dd506cc360c735b0d9db15df17984fefde79b40ed724') { throw 'PERSISTENT_SETUP_SOURCE_CHANGED' }
    }
    if ($Mode -eq 'StartScheduledDelivery') {
        $taskInstaller = Join-Path $taskRoot 'tools/wave5/start_scheduled_delivery_20261013_r5_a4.mjs'
        if ((Get-FileHash -LiteralPath $taskInstaller -Algorithm SHA256).Hash.ToLowerInvariant() -ne
            '930e6c3ca3bc26c0a91448df834746c234e6e211280d900747f2f4ddf17ff096') { throw 'EXACT_SCHEDULE_START_SOURCE_REQUIRED' }
    }
    if ($Mode -eq 'RefreshOwnerScopeA3') {
        $taskInstaller = Join-Path $taskRoot 'tools/wave5/refresh_private_owner_scope_20261013_r5_a3.mjs'
        if ((Get-FileHash -LiteralPath $taskInstaller -Algorithm SHA256).Hash.ToLowerInvariant() -ne
            '55e8038bd5054e0a4e6fa01297efdf1ad3eeecc09e24b65346ae858822672ac2') { throw 'OWNER_SCOPE_A3_SOURCE_CHANGED' }
    }
    if ($Mode -eq 'RefreshOwnerScopeA4') {
        $taskInstaller = Join-Path $taskRoot 'tools/wave5/refresh_private_owner_scope_20261013_r5_a4.mjs'
        if ((Get-FileHash -LiteralPath $taskInstaller -Algorithm SHA256).Hash.ToLowerInvariant() -ne
            '474923aaef21c8330b6dfe699d291b3e3469f046f7b32c5a2ef1bb1d83b36d84') { throw 'OWNER_SCOPE_A4_SOURCE_CHANGED' }
    }
    if ($Mode -eq 'RefreshOwnerScopeA5') {
        $taskInstaller = Join-Path $taskRoot 'tools/wave5/refresh_private_owner_scope_20261013_r5_a5.mjs'
        if ((Get-FileHash -LiteralPath $taskInstaller -Algorithm SHA256).Hash.ToLowerInvariant() -ne
            '98e4a71b61af17f121349cd23d8349c3329860a772c124005024704a91e04b71') { throw 'OWNER_SCOPE_A5_SOURCE_CHANGED' }
    }
    if ($Mode -eq 'RefreshOwnerScopeA6') {
        $taskInstaller = Join-Path $taskRoot 'tools/wave5/refresh_private_owner_scope_20261014_r5_a6.mjs'
        if ((Get-FileHash -LiteralPath $taskInstaller -Algorithm SHA256).Hash.ToLowerInvariant() -ne
            '3910f1311d69ac9b2bc8a682174e5546f24b6edcf176ab7bc56a8f0087480022') { throw 'OWNER_SCOPE_A6_SOURCE_CHANGED' }
    }
    if ($Mode -eq 'RefreshOwnerScopeA7') {
        $taskInstaller = Join-Path $taskRoot 'tools/wave5/refresh_private_owner_scope_20261014_r5_a7.mjs'
        if ((Get-FileHash -LiteralPath $taskInstaller -Algorithm SHA256).Hash.ToLowerInvariant() -ne
            '5aec90224966338275149917bf6a9f0d30e53db159a33c1c65a9a32f529b9ddf') { throw 'OWNER_SCOPE_A7_SOURCE_CHANGED' }
    }
    if ($Mode -eq 'RefreshOwnerScopeA8') {
        $taskInstaller = Join-Path $taskRoot 'tools/wave5/refresh_private_owner_scope_20261014_r5_a8.mjs'
        if ((Get-FileHash -LiteralPath $taskInstaller -Algorithm SHA256).Hash.ToLowerInvariant() -ne
            '42bfdaa042aedac533e2b72552b45995b4e480aea593b4ee3b62f71d2c18ee11') { throw 'OWNER_SCOPE_A8_SOURCE_CHANGED' }
    }
    if ($Mode -eq 'RefreshOwnerScopeA9') {
        $taskInstaller = Join-Path $taskRoot 'tools/wave5/refresh_private_owner_scope_20261014_r5_a9.mjs'
        if ((Get-FileHash -LiteralPath $taskInstaller -Algorithm SHA256).Hash.ToLowerInvariant() -ne
            'b8ddcb732628bb28a9e0a511d6ef2fc83892529c2a58b9c023bae2fcec8242c7') { throw 'OWNER_SCOPE_A9_SOURCE_CHANGED' }
    }
    if ($Mode -eq 'RefreshOwnerScopeA10') {
        $taskInstaller = Join-Path $taskRoot 'tools/wave5/refresh_private_owner_scope_20261014_r5_a10.mjs'
        if ((Get-FileHash -LiteralPath $taskInstaller -Algorithm SHA256).Hash.ToLowerInvariant() -ne
            'a3fe771a022dac5ba3a81a33591e7017fb6f446a2e813affd09fc6e40738d07a') { throw 'OWNER_SCOPE_A10_SOURCE_CHANGED' }
    }
    if ($Mode -eq 'ReadAuthQuota') {
        $taskInstaller = Join-Path $taskRoot 'tools/wave5/read_private_auth_quota_20261014_r5.mjs'
        if ((Get-FileHash -LiteralPath $taskInstaller -Algorithm SHA256).Hash.ToLowerInvariant() -ne
            '2684b51d6522ad3cd9843eae7df2a1decb113e680b89ecf0a3c8cc6b6ae1b1eb') { throw 'AUTH_QUOTA_READER_SOURCE_CHANGED' }
    }
    if ($Mode -eq 'InspectScheduledError') {
        $taskInstaller = Join-Path $taskRoot 'tools/wave5/inspect_scheduled_read_error_20261013_r5.mjs'
        if ((Get-FileHash -LiteralPath $taskInstaller -Algorithm SHA256).Hash.ToLowerInvariant() -ne
            '51850afbd880528cfadddab92741ac3e7d96feb79613f8dbd524d8bd7952dac5') { throw 'ERROR_INSPECTOR_SOURCE_CHANGED' }
    }
    if ($Mode -eq 'PauseFailedSchedules') {
        $taskInstaller = Join-Path $taskRoot 'tools/wave5/pause_failed_scheduled_delivery_20261013_r5.mjs'
        if ((Get-FileHash -LiteralPath $taskInstaller -Algorithm SHA256).Hash.ToLowerInvariant() -ne
            '0fca4ff46f810a636f9e31f5316caa46cb816c614b9a3634ededaF7a78706fe6'.ToLowerInvariant()) { throw 'EXACT_PAUSE_SOURCE_CHANGED' }
    }
    $taskPhase = 'node-location'
    if ($Mode -eq 'ExecuteDeliveryFixtures') {
        $taskInstaller = Join-Path $taskRoot 'tools/wave5/prepare_actual_delivery_fixtures_20261013_r5.mjs'
        if ((Get-FileHash -LiteralPath $taskInstaller -Algorithm SHA256).Hash.ToLowerInvariant() -ne
            '3a37978cf79456aa6e7624cf6cd3428ffe36b70617c73442cf458d24238cfd74') { throw 'DELIVERY_FIXTURE_SOURCE_CHANGED' }
        if ((Get-FileHash -LiteralPath (Join-Path $taskRoot 'tools/wave5/delivery_transport_20261013_r5.mjs') -Algorithm SHA256).Hash.ToLowerInvariant() -ne
            'ce733b5093e7c53ded4742111af33f5d254d8f488513f800f39e05b882899dfe') { throw 'DELIVERY_TRANSPORT_SOURCE_CHANGED' }
    }
    if ($Mode -eq 'ExecuteDeliveryLease') {
        $taskInstaller = Join-Path $taskRoot 'tools/wave5/genuine_delivery_lease_20261013_r5.mjs'
        if ((Get-FileHash -LiteralPath $taskInstaller -Algorithm SHA256).Hash.ToLowerInvariant() -ne
            'a5ccccab1163c0563361a1d56d9bb71030868d005fb24d077a91db05a902ccf9') { throw 'DELIVERY_LEASE_SOURCE_CHANGED' }
        if ((Get-FileHash -LiteralPath (Join-Path $taskRoot 'tools/wave5/delivery_transport_20261013_r5.mjs') -Algorithm SHA256).Hash.ToLowerInvariant() -ne
            'ce733b5093e7c53ded4742111af33f5d254d8f488513f800f39e05b882899dfe') { throw 'DELIVERY_TRANSPORT_SOURCE_CHANGED' }
        if ((Get-FileHash -LiteralPath (Join-Path $taskRoot 'tools/wave5/private_existing_actor_session_20261013_r5.mjs') -Algorithm SHA256).Hash.ToLowerInvariant() -ne
            '0d9dc4bfbd703fb7637f0acc89eaa195c2b6a17bdf4f4e566b0ba925f76c4540') { throw 'EXISTING_ACTOR_SESSION_SOURCE_CHANGED' }
    }
    if ($Mode -eq 'ExecutePersistentSetupA4') {
        $taskInstaller = Join-Path $taskRoot 'tools/wave5/persistent_setup_20261013_r5_a4.mjs'
        if ((Get-FileHash -LiteralPath $taskInstaller -Algorithm SHA256).Hash.ToLowerInvariant() -ne
            '54d4e13973fcf27f9c334176315c5e6dcb37a515ed6d0c4a62471de1030d6795') { throw 'PERSISTENT_SETUP_A4_SOURCE_CHANGED' }
    }
    if ($Mode -eq 'ExecutePersistentSetupA3') {
        $taskInstaller = Join-Path $taskRoot 'tools/wave5/persistent_setup_20261013_r5_a3.mjs'
        if ((Get-FileHash -LiteralPath $taskInstaller -Algorithm SHA256).Hash.ToLowerInvariant() -ne
            '53f2e198f8f99b43c3c191a75064588f837e3faa4fa424e23b3e13f2cad36586') { throw 'PERSISTENT_SETUP_A3_SOURCE_CHANGED' }
    }
    if ($Mode -eq 'ExecutePersistentSetupA2') {
        $taskInstaller = Join-Path $taskRoot 'tools/wave5/persistent_setup_20261013_r5_a2.mjs'
        if ((Get-FileHash -LiteralPath $taskInstaller -Algorithm SHA256).Hash.ToLowerInvariant() -ne
            '8d60a4a779904c7274838200b8ef18626b9e8b1ebd72fec4c978bf2c4fed81f8') { throw 'PERSISTENT_SETUP_A2_SOURCE_CHANGED' }
    }
    if ($Mode -in @('ValidateActivation','ExecuteActivation')) {
        $taskInstaller = Join-Path $taskRoot 'tools/wave5/synthetic_activation_contention_20261013_r5.mjs'
        if ((Get-FileHash -LiteralPath $taskInstaller -Algorithm SHA256).Hash.ToLowerInvariant() -ne
            '23cf50d1f0956ee2eaed298163ac7a0c1ea8fa267facebf488a5c13f90800a08') { throw 'ACTIVATION_EXECUTOR_SOURCE_CHANGED' }
        if ((Get-FileHash -LiteralPath (Join-Path $taskRoot 'tools/wave5/private_existing_actor_session_20261013_r5.mjs') -Algorithm SHA256).Hash.ToLowerInvariant() -ne
            '0d9dc4bfbd703fb7637f0acc89eaa195c2b6a17bdf4f4e566b0ba925f76c4540') { throw 'EXISTING_ACTOR_SESSION_SOURCE_CHANGED' }
    }
    if ($Mode -in @('ValidateFinanceWorkflow','ExecuteFinanceWorkflow','ResumeFinanceWorkflow')) {
        $taskInstaller = Join-Path $taskRoot 'tools/wave5/finance_cash_workflows_20261013_r5.mjs'
        if ((Get-FileHash -LiteralPath $taskInstaller -Algorithm SHA256).Hash.ToLowerInvariant() -ne
            '15758ebee2def57d0b3796cd9911090207ba7c9d49bbcbaa8b4201b9a420b64c') { throw 'EXACT_FINANCE_WORKFLOW_SOURCE_REQUIRED' }
        if ((Get-FileHash -LiteralPath (Join-Path $taskRoot 'tools/wave5/finance_https_transport_20261013_r5.mjs') -Algorithm SHA256).Hash.ToLowerInvariant() -ne
            '5eb2b839a9249fd457073d4b63523d311f06ecc2d392710db2f823259395ba0f') { throw 'EXACT_FINANCE_TRANSPORT_SOURCE_REQUIRED' }
        if ((Get-FileHash -LiteralPath (Join-Path $taskRoot 'docs/verification/wave5/finance-cash-workflow-preparation-20261013-r5-a3.json') -Algorithm SHA256).Hash.ToLowerInvariant() -ne
            '2290874b4d90865fea02d0c070c0342962a440f391fb9863df052fcbcc1f4913') { throw 'EXACT_FINANCE_WORKFLOW_PLAN_REQUIRED' }
    }
    if ($Mode -in @('ValidateRemainingFinance','ExecuteRemainingFinance')) {
        $taskExecutionRoot = Join-Path $taskRoot 'build/wave5-approved-execution-20261013-r5-a2'
        $taskSnapshotManifest = Join-Path $taskRoot 'docs/verification/wave5/approved-isolated-execution-snapshot-20261013-r5-a2.json'
        if ((Get-FileHash -LiteralPath $taskSnapshotManifest -Algorithm SHA256).Hash.ToLowerInvariant() -ne
            '9c9e856c2cfdb852a3a9b9e66474f14c86a32dc72cc5b613e806699b2fb78c01') { throw 'EXACT_APPROVED_EXECUTION_SNAPSHOT_REQUIRED' }
        $taskInstaller = Join-Path $taskExecutionRoot 'tools/wave5/finance_remaining_20261013_r5_a2.mjs'
        if ((Get-FileHash -LiteralPath $taskInstaller -Algorithm SHA256).Hash.ToLowerInvariant() -ne
            '73dd2d45688f0dbe47185f685501aa1397a8145976eafe6bb5719e4e9b80d666') { throw 'EXACT_REMAINING_FINANCE_SOURCE_REQUIRED' }
        $taskRemainingPlan = Join-Path $taskExecutionRoot 'docs/verification/wave5/finance-remaining-preparation-20261013-r5-a2.json'
        if ((Get-FileHash -LiteralPath $taskRemainingPlan -Algorithm SHA256).Hash.ToLowerInvariant() -ne
            'a7153af4d8585bee09ff9d9e17274f6aa847345e294a503475b9b6393414a456') { throw 'EXACT_REMAINING_FINANCE_PLAN_REQUIRED' }
        if ($Mode -eq 'ExecuteRemainingFinance') {
            # This remains fail-closed until the independent source review is
            # completed and its exact bytes are pinned. Validate never unseals input.
            $taskRemainingPeerExpectedSha256 = '1435a64ea6c4a720a4ba952757eae12b791646508cc1af09dad99b3aeecafa5f'
            if ($taskRemainingPeerExpectedSha256 -notmatch '^[a-f0-9]{64}$') { throw 'INDEPENDENT_REMAINING_FINANCE_REVIEW_PENDING' }
            $taskRemainingPeer = Join-Path $taskRoot 'docs/verification/wave5/finance-remaining-successor-independent-review-20261013-r5-a2.json'
            if ((Get-FileHash -LiteralPath $taskRemainingPeer -Algorithm SHA256).Hash.ToLowerInvariant() -ne
                $taskRemainingPeerExpectedSha256) { throw 'EXACT_REMAINING_FINANCE_PEER_REQUIRED' }
            $taskRemainingPeerReview = Get-Content -Raw -LiteralPath $taskRemainingPeer | ConvertFrom-Json
            if ($taskRemainingPeerReview.passed -ne $true -or $taskRemainingPeerReview.runtimePlan.sha256 -ne
                'a7153af4d8585bee09ff9d9e17274f6aa847345e294a503475b9b6393414a456' -or
                $taskRemainingPeerReview.checks.failed -ne 0) { throw 'PASSED_EXACT_REMAINING_FINANCE_PEER_REQUIRED' }
        }
    }
    if ($Mode -in @('ValidateRemainingFinanceA3','ExecuteRemainingFinanceA3')) {
        $taskExecutionRoot = Join-Path $taskRoot 'build/wave5-approved-execution-20261013-r5-a2'
        $taskSnapshotManifest = Join-Path $taskRoot 'docs/verification/wave5/approved-isolated-execution-snapshot-20261013-r5-a2.json'
        if ((Get-FileHash -LiteralPath $taskSnapshotManifest -Algorithm SHA256).Hash.ToLowerInvariant() -ne
            '9c9e856c2cfdb852a3a9b9e66474f14c86a32dc72cc5b613e806699b2fb78c01') { throw 'EXACT_APPROVED_EXECUTION_SNAPSHOT_REQUIRED' }
        $taskInstaller = Join-Path $taskExecutionRoot 'tools/wave5/finance_remaining_20261014_r5_a3.mjs'
        if ((Get-FileHash -LiteralPath $taskInstaller -Algorithm SHA256).Hash.ToLowerInvariant() -ne
            '8cf6068a4f4863c27d234b96755b2e1f9332c13590a25e5b66ef4742da87bd52') { throw 'EXACT_FINANCE_A3_SOURCE_REQUIRED' }
        $taskRemainingPlan = Join-Path $taskExecutionRoot 'docs/verification/wave5/finance-remaining-preparation-20261014-r5-a3.json'
        if ((Get-FileHash -LiteralPath $taskRemainingPlan -Algorithm SHA256).Hash.ToLowerInvariant() -ne
            '6c39a389ebaec0315774500af2af1e71874486173d85a3e352ef5782153e1198') { throw 'EXACT_FINANCE_A3_PLAN_REQUIRED' }
        $taskFinanceA3RootReview = Join-Path $taskRoot 'docs/verification/wave5/finance-remaining-root-source-review-20261014-r5-a3.json'
        if ((Get-FileHash -LiteralPath $taskFinanceA3RootReview -Algorithm SHA256).Hash.ToLowerInvariant() -ne
            'f661da3175194cdf472e8c24046804023b545485e13dbd40279d39991ff5d135') { throw 'EXACT_FINANCE_A3_ROOT_REVIEW_REQUIRED' }
        $taskFinanceA3Peer = Join-Path $taskRoot 'docs/verification/wave5/task3-completion-20261013/finance-a3-independent-source-and-plan-review.json'
        if ((Get-FileHash -LiteralPath $taskFinanceA3Peer -Algorithm SHA256).Hash.ToLowerInvariant() -ne
            '8399666dc0528532cd3462e26a70ac89a340b6484a7b3fe911172d291aae814e') { throw 'EXACT_FINANCE_A3_INDEPENDENT_REVIEW_REQUIRED' }
        $taskFinanceA3Decision = Get-Content -Raw -LiteralPath $taskFinanceA3Peer | ConvertFrom-Json
        if ($taskFinanceA3Decision.technicalVerdict -notlike 'approve exact*' -or
            $taskFinanceA3Decision.generatedPlan.sha256 -ne '6c39a389ebaec0315774500af2af1e71874486173d85a3e352ef5782153e1198' -or
            $taskFinanceA3Decision.personalHumanExactSourceSignatureClaimed -ne $false) { throw 'PASSED_EXACT_FINANCE_A3_REVIEW_REQUIRED' }
    }
    $taskNode = (Get-Command node -CommandType Application -ErrorAction Stop | Select-Object -First 1).Source
    $taskFlag = switch ($Mode) { 'Preflight' { '--preflight' } 'Execute' { '--execute' } 'VerifyInstalled' { '--verify' }
        'ProvisionAuth' { '--provision' } 'EnrollMfa' { '--enroll' } 'ExecuteBootstrap' { '--execute' } 'ExecuteFinanceWorkflow' { '--execute-finance' } 'ResumeFinanceWorkflow' { '--resume-finance' } 'ExecuteRemainingFinance' { '--execute' } 'ExecuteRemainingFinanceA3' { '--execute' }
        'InspectAccess' { '--inspect' } 'InspectSourceFailure' { '--inspect' } 'ExecuteSourceWorkflow' { '--execute' } 'ReadAuthQuota' { '--read' } 'RefreshOwnerScopeA7' { '--refresh' } 'RefreshOwnerScopeA8' { '--refresh' } 'RefreshOwnerScopeA9' { '--refresh' } 'RefreshOwnerScopeA10' { '--refresh' }
        'RefreshOwnerScope' { '--refresh' } 'RefreshOwnerScopeA3' { '--refresh' } 'RefreshOwnerScopeA4' { '--refresh' } 'RefreshOwnerScopeA5' { '--refresh' } 'RefreshOwnerScopeA6' { '--refresh' } 'ResumeSourceWorkflows' { '--resume' } 'ContinueSourceWorkflowsA3' { '--resume' } 'ExecuteActivation' { '--execute' } 'ExecutePersistentSetup' { '--execute' } 'ExecutePersistentSetupA2' { '--execute' } 'ExecutePersistentSetupA3' { '--execute' } 'ExecutePersistentSetupA4' { '--execute' } 'ExecuteDeliveryLease' { '--execute' } 'ExecuteDeliveryFixtures' { '--execute' } 'StartScheduledDelivery' { '--execute' } 'InspectScheduledError' { '--inspect' } 'PauseFailedSchedules' { '--execute' } default { '--validate' } }
    if ($taskNeedsPrivate) {
        $taskPhase = 'private-metadata-validation'
        $taskMetadataText = Get-Content -Raw -LiteralPath $taskReadyFile
        $taskMetadata = $taskMetadataText | ConvertFrom-Json -DateKind String
        $taskSid = [Security.Principal.WindowsIdentity]::GetCurrent().User
        $taskNow = [DateTimeOffset]::UtcNow
        $taskCreated = Convert-TaskUtcTimestamp $taskMetadata.createdAt
        $taskExpiry = Convert-TaskUtcTimestamp $taskMetadata.expiresAt
        if ($taskMetadata.kind -ne 'wave5-private-owner-input-metadata' -or
            $taskMetadata.projectId -ne 'xpdoufauvrbdmxgngetv' -or
            $taskMetadata.runtimeBundleSha256 -ne 'db525758554036fa99ec02d00c85bd8401ef7ebce787e2a983db1c69a08baf7b' -or
            $taskMetadata.ownerSid -ne $taskSid.Value -or
            $taskMetadata.helperSha256 -notin @('3e760848688dbd82b0eb0ed83cef2c6cbf1c65c721241801870ed23555ccb199',
                'e96cd439df228ba41f211d70338f59bd74fa21fd10791e5a3d850c31d2678e49',
                '1049309eccbec8247cfffc426fa2592547886467cda09f156ddd9636afba5a59','55e8038bd5054e0a4e6fa01297efdf1ad3eeecc09e24b65346ae858822672ac2','474923aaef21c8330b6dfe699d291b3e3469f046f7b32c5a2ef1bb1d83b36d84',
                '98e4a71b61af17f121349cd23d8349c3329860a772c124005024704a91e04b71','3910f1311d69ac9b2bc8a682174e5546f24b6edcf176ab7bc56a8f0087480022','5aec90224966338275149917bf6a9f0d30e53db159a33c1c65a9a32f529b9ddf','42bfdaa042aedac533e2b72552b45995b4e480aea593b4ee3b62f71d2c18ee11','b8ddcb732628bb28a9e0a511d6ef2fc83892529c2a58b9c023bae2fcec8242c7','a3fe771a022dac5ba3a81a33591e7017fb6f446a2e813affd09fc6e40738d07a') -or
            $taskMetadata.containsPlaintextCredential -ne $false -or
            ($taskExpiry -le $taskNow -and $Mode -notin @('RefreshOwnerScope','RefreshOwnerScopeA3','RefreshOwnerScopeA4','RefreshOwnerScopeA5','RefreshOwnerScopeA6','RefreshOwnerScopeA7','RefreshOwnerScopeA8','RefreshOwnerScopeA9','RefreshOwnerScopeA10')) -or
            ($Mode -in @('RefreshOwnerScope','RefreshOwnerScopeA3','RefreshOwnerScopeA4','RefreshOwnerScopeA5','RefreshOwnerScopeA6','RefreshOwnerScopeA7','RefreshOwnerScopeA8','RefreshOwnerScopeA9','RefreshOwnerScopeA10') -and $taskCreated -lt $taskNow.AddDays(-7)) -or
            $taskCreated -gt $taskNow.AddSeconds(10) -or
            ($taskExpiry - $taskCreated).TotalHours -gt 2.01) { throw 'EXACT_FRESH_PRIVATE_INPUT_REQUIRED' }
        $taskFolder = [IO.Path]::GetFullPath($taskMetadata.privateFolder)
        $taskTemp = [IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\') + '\'
        if (-not $taskFolder.StartsWith($taskTemp,[StringComparison]::OrdinalIgnoreCase) -or
            [IO.Path]::GetFileName($taskFolder) -notmatch '^JentraOS-Wave5-owner-[a-f0-9]{32}$') { throw 'EXACT_PRIVATE_TEMP_FOLDER_REQUIRED' }
        $taskSealedPath = Join-Path $taskFolder 'owner-pat.dpapi'
        if ([IO.Path]::GetFullPath($taskMetadata.sealedTokenPath) -ne $taskSealedPath) { throw 'EXACT_SEALED_INPUT_PATH_REQUIRED' }
        Assert-TaskPrivateAcl $taskFolder $taskSid $true
        Assert-TaskPrivateAcl $taskSealedPath $taskSid $false
        $taskMetadataName = if ($taskReadyFile.EndsWith('-a10.json')) { 'metadata-renewed-a10.json' } elseif ($taskReadyFile.EndsWith('-a9.json')) { 'metadata-renewed-a9.json' } elseif ($taskReadyFile.EndsWith('-a8.json')) { 'metadata-renewed-a8.json' } elseif ($taskReadyFile.EndsWith('-a7.json')) { 'metadata-renewed-a7.json' } elseif ($taskReadyFile.EndsWith('-a6.json')) { 'metadata-renewed-a6.json' } elseif ($taskReadyFile.EndsWith('-a5.json')) { 'metadata-renewed-a5.json' } elseif ($taskReadyFile.EndsWith('-a4.json')) { 'metadata-renewed-a4.json' } elseif ($taskReadyFile.EndsWith('-a3.json')) { 'metadata-renewed-a3.json' } elseif ($taskReadyFile.EndsWith('-a2.json')) { 'metadata-renewed-a2.json' } else { 'metadata.json' }
        Assert-TaskPrivateAcl (Join-Path $taskFolder $taskMetadataName) $taskSid $false
        if ((Get-Content -Raw -LiteralPath (Join-Path $taskFolder $taskMetadataName)) -ne $taskMetadataText) { throw 'PRIVATE_METADATA_CHANGED' }
        $taskSecret = ConvertTo-SecureString -String (Get-Content -Raw -LiteralPath $taskSealedPath)
        $taskBstr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($taskSecret)
        $taskPlain = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($taskBstr)
        if ($taskPlain.Length -lt 9 -or $taskPlain.Length -gt 2048 -or $taskPlain -match '\s') { throw 'PRIVATE_INPUT_INVALID' }
        if ($Mode -in @('RefreshOwnerScope','RefreshOwnerScopeA3','RefreshOwnerScopeA4','RefreshOwnerScopeA5','RefreshOwnerScopeA6','RefreshOwnerScopeA7','RefreshOwnerScopeA8','RefreshOwnerScopeA9','RefreshOwnerScopeA10')) {
            $taskPlain = @{ projectId=$taskMetadata.projectId;bundleSha256=$taskMetadata.runtimeBundleSha256;
                ownerToken=$taskPlain;originalMetadata=$taskMetadata } | ConvertTo-Json -Compress -Depth 12
        }
        if ($Mode -in @('ExecuteBootstrap','ExecutePersistentSetup','ExecutePersistentSetupA2','ExecutePersistentSetupA3')) {
            $taskPlain = @{ projectId=$taskMetadata.projectId;bundleSha256=$taskMetadata.runtimeBundleSha256;
                ownerToken=$taskPlain } | ConvertTo-Json -Compress
        }
        if ($Mode -in @('ProvisionAuth','EnrollMfa','ExecuteSourceWorkflow','InspectSourceFailure','ResumeSourceWorkflows','ContinueSourceWorkflowsA3','ExecuteActivation','ExecutePersistentSetupA4','ExecuteDeliveryLease','ExecuteDeliveryFixtures','StartScheduledDelivery','InspectScheduledError','PauseFailedSchedules','ExecuteFinanceWorkflow','ResumeFinanceWorkflow','ExecuteRemainingFinance','ExecuteRemainingFinanceA3')) {
            $taskPhase = 'private-runtime-key'
            $taskRuntimeSeal = Join-Path $taskFolder 'runtime-seal.dpapi'
            if (-not (Test-Path -LiteralPath $taskRuntimeSeal)) {
                if ($Mode -ne 'ProvisionAuth') { throw 'EXISTING_RUNTIME_SEAL_REQUIRED' }
                $taskKeyBytes = [byte[]]::new(32)
                $taskRng = [Security.Cryptography.RandomNumberGenerator]::Create()
                try { $taskRng.GetBytes($taskKeyBytes) } finally { $taskRng.Dispose() }
                $taskKeySecure = ConvertTo-SecureString -String ([Convert]::ToBase64String($taskKeyBytes)) -AsPlainText -Force
                [Array]::Clear($taskKeyBytes,0,$taskKeyBytes.Length)
                try { $taskKeyCipher = ConvertFrom-SecureString -SecureString $taskKeySecure } finally { $taskKeySecure.Dispose() }
                $taskSealStream = [IO.File]::Open($taskRuntimeSeal,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::None)
                try { $taskCipherBytes = [Text.Encoding]::UTF8.GetBytes($taskKeyCipher)
                    $taskSealStream.Write($taskCipherBytes,0,$taskCipherBytes.Length); $taskSealStream.Flush($true)
                } finally { $taskSealStream.Dispose(); $taskKeyCipher = $null }
            }
            Assert-TaskPrivateAcl $taskRuntimeSeal $taskSid $false
            $taskKeySecure = ConvertTo-SecureString -String (Get-Content -Raw -LiteralPath $taskRuntimeSeal)
            $taskKeyBstr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($taskKeySecure)
            try { $taskKeyText = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($taskKeyBstr)
                $taskPlain = @{ projectId=$taskMetadata.projectId;bundleSha256=$taskMetadata.runtimeBundleSha256;
                    ownerToken=$taskPlain;privateDirectory=$taskFolder;encryptionKey=$taskKeyText } | ConvertTo-Json -Compress
            } finally { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($taskKeyBstr);$taskKeySecure.Dispose();$taskKeyText=$null }
        }
    }
    $taskPhase = 'child-process-configuration'
    $taskInfo = [Diagnostics.ProcessStartInfo]::new()
    $taskInfo.FileName = $taskNode
    $taskInfo.Arguments = '"' + $taskInstaller + '" ' + $taskFlag
    $taskInfo.WorkingDirectory = $taskRoot
    $taskInfo.UseShellExecute = $false
    $taskInfo.CreateNoWindow = $true
    $taskInfo.RedirectStandardInput = $true
    $taskInfo.RedirectStandardOutput = $true
    $taskInfo.RedirectStandardError = $true
    [void]$taskInfo.EnvironmentVariables.Remove('SUPABASE_ACCESS_TOKEN')
    $taskChild = [Diagnostics.Process]::new()
    $taskChild.StartInfo = $taskInfo
    $taskPhase = 'child-process-start'
    if (-not $taskChild.Start()) { throw 'PRIVATE_CHILD_START_FAILED' }
    $taskErrorTask = $taskChild.StandardError.ReadToEndAsync()
    if ($taskNeedsPrivate) { $taskChild.StandardInput.WriteLine($taskPlain) }
    $taskChild.StandardInput.Close()
    $taskPlain = $null
    if ($taskBstr -ne [IntPtr]::Zero) { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($taskBstr); $taskBstr = [IntPtr]::Zero }
    if ($null -ne $taskSecret) { $taskSecret.Dispose(); $taskSecret = $null }
    $taskPhase = 'public-child-output'
    while ($null -ne ($taskLine = $taskChild.StandardOutput.ReadLine())) {
        # The source-bound child emits public JSON only; malformed output stops
        # printing instead of exposing an unknown process message.
        $taskPublic = $taskLine | ConvertFrom-Json
        $taskPublic | ConvertTo-Json -Compress -Depth 20
    }
    $taskPhase = 'child-exit'
    $taskChild.WaitForExit()
    $taskChildError = $taskErrorTask.GetAwaiter().GetResult()
    if ($taskChildError.Trim().Length -gt 0) {
        $taskFailure = $taskChildError | ConvertFrom-Json
        if ($taskFailure.failureCode -notmatch '^[A-Z_]+$') { throw 'CHILD_OUTPUT_INVALID' }
        @{ failureCode=$taskFailure.failureCode; rawErrorOrCredentialPrinted=$false; automaticRetryPerformed=$false } | ConvertTo-Json -Compress
    }
    exit $taskChild.ExitCode
} catch {
    $taskSafeGuardCode = if ($_.Exception.Message -cmatch '^[A-Z][A-Z_]{3,100}$') { $_.Exception.Message } else { 'PRIVATE_OWNER_HANDOFF_FAILED' }
    @{ failureCode='PRIVATE_OWNER_HANDOFF_FAILED'; phase=$taskPhase;
        guardCode=$taskSafeGuardCode; scriptLine=$_.InvocationInfo.ScriptLineNumber;
        exceptionType=$_.Exception.GetType().FullName;
        rawErrorOrCredentialPrinted=$false; automaticRetryPerformed=$false } | ConvertTo-Json -Compress
    exit 1
} finally {
    $taskPlain = $null
    if ($taskBstr -ne [IntPtr]::Zero) { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($taskBstr) }
    if ($null -ne $taskSecret) { $taskSecret.Dispose() }
    if ($null -ne $taskChild) { $taskChild.Dispose() }
}
