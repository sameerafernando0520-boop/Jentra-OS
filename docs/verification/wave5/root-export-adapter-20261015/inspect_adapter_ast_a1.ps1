$ErrorActionPreference = 'Stop'
$taskRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../../..'))
$taskPaths = @(
    'scripts/wave5/run_private_management_installer_20261013_r5.ps1',
    'scripts/wave5/run_private_management_installer_20261015_r5_a1.candidate.ps1'
)
$taskAsts = @()
foreach ($taskPath in $taskPaths) {
    $taskTokens = $null
    $taskErrors = $null
    $taskAsts += [Management.Automation.Language.Parser]::ParseFile((Join-Path $taskRoot $taskPath), [ref]$taskTokens, [ref]$taskErrors)
    if ($taskErrors.Count -ne 0) { throw 'ADAPTER_SYNTAX_ERRORS' }
}
$taskChecks = [Collections.Generic.List[string]]::new()
function Assert-Review([bool]$Condition, [string]$Label) {
    if (-not $Condition) { throw $Label }
    $taskChecks.Add($Label)
}
$taskOld = $taskAsts[0]
$taskNew = $taskAsts[1]
Assert-Review ($taskOld.ParamBlock.Parameters.Count -eq 1 -and $taskNew.ParamBlock.Parameters.Count -eq 2) 'only_final_review_parameter_added'
$taskOldModes = @($taskOld.ParamBlock.Parameters[0].Attributes[0].PositionalArguments | ForEach-Object Value)
$taskNewModes = @($taskNew.ParamBlock.Parameters[0].Attributes[0].PositionalArguments | ForEach-Object Value)
Assert-Review (($taskNewModes -join ',') -eq (($taskOldModes + @('ValidateExportsA6','ExecuteExportsA6')) -join ',')) 'all_old_modes_preserved_in_order'
foreach ($taskName in @('Assert-TaskPrivateAcl','Convert-TaskUtcTimestamp')) {
    $taskPrior = $taskOld.Find({param($n) $n -is [Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq $taskName}, $true)
    $taskNext = $taskNew.Find({param($n) $n -is [Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq $taskName}, $true)
    Assert-Review ($taskPrior.Extent.Text -ceq $taskNext.Extent.Text) ('unchanged_function_' + $taskName)
}
$taskOldPrivate = $taskOld.Find({param($n) $n -is [Management.Automation.Language.AssignmentStatementAst] -and $n.Left.Extent.Text -eq '$taskNeedsPrivate'}, $true)
$taskNewPrivate = $taskNew.Find({param($n) $n -is [Management.Automation.Language.AssignmentStatementAst] -and $n.Left.Extent.Text -eq '$taskNeedsPrivate'}, $true)
Assert-Review ($taskNewPrivate.Extent.Text -ceq $taskOldPrivate.Extent.Text.Replace("'ExecuteRemainingFinanceA3')","'ExecuteRemainingFinanceA3','ExecuteExportsA6')")) 'only_export_execution_gains_private_access'
$taskCommands = @($taskNew.FindAll({param($n) $n -is [Management.Automation.Language.CommandAst]}, $true))
$taskNewSecrets = @($taskCommands | Where-Object { $_.GetCommandName() -eq 'ConvertTo-SecureString' })
$taskOldSecrets = @($taskOld.FindAll({param($n) $n -is [Management.Automation.Language.CommandAst] -and $n.GetCommandName() -eq 'ConvertTo-SecureString'}, $true))
Assert-Review ($taskNewSecrets.Count -eq $taskOldSecrets.Count) 'no_new_decryption_or_seal_creation_command'
$taskText = $taskNew.Extent.Text
$taskPreflightStart = $taskText.IndexOf('$taskPhase = ''public-export-preflight''', [StringComparison]::Ordinal)
$taskPrivateStart = $taskText.IndexOf('$taskPhase = ''private-metadata-validation''', [StringComparison]::Ordinal)
$taskFirstDecrypt = $taskText.IndexOf('$taskSecret = ConvertTo-SecureString', [StringComparison]::Ordinal)
Assert-Review ($taskPreflightStart -gt 0 -and $taskPreflightStart -lt $taskPrivateStart -and $taskPrivateStart -lt $taskFirstDecrypt) 'public_preflight_precedes_all_private_metadata_and_dpapi'
$taskPreflightBranch = $taskNew.FindAll({param($n) $n -is [Management.Automation.Language.IfStatementAst] -and $n.Extent.Text.Contains('$taskPhase = ''public-export-preflight''')}, $true) | Sort-Object { $_.Extent.Text.Length } | Select-Object -First 1
Assert-Review ($taskPreflightBranch.Clauses[0].Item1.Extent.Text -ceq '$Mode -eq ''ExecuteExportsA6''') 'preflight_is_mandatory_for_export_execution'
Assert-Review ($taskText.Contains('$taskPreflightInfo.CreateNoWindow = $true') -and $taskText.Contains('$taskPreflightInfo.UseShellExecute = $false')) 'preflight_uses_hidden_direct_process'
Assert-Review ($taskText.Contains('$taskPreflight.StandardInput.Close()') -and $taskText.Contains('$taskPreflight.WaitForExit(60000)')) 'preflight_has_closed_stdin_and_bounded_wait'
Assert-Review ($taskText.IndexOf('EXPORT_PUBLIC_INPUT_CHANGED_BEFORE_PRIVATE_INPUT') -lt $taskFirstDecrypt) 'metadata_review_and_window_rechecked_before_unseal'
Assert-Review ($taskText.Contains('$taskExportConfig | Add-Member -NotePropertyName exportWindow -NotePropertyValue $taskExportWindow')) 'exact_reviewed_window_passed_to_child'
Assert-Review ($taskText.Contains('$taskExportConfig.ownerToken = $null; $taskExportConfig.encryptionKey = $null; $taskExportConfig = $null')) 'temporary_private_config_cleared'
[pscustomobject]@{ kind='root_adapter_ast_review'; passed=$true; parseErrors=0; checks=@($taskChecks); candidateExecuted=$false; privateInputsRead=$false; networkCalls=0 } | ConvertTo-Json -Compress -Depth 4
