[CmdletBinding()]
param()
$ErrorActionPreference='Stop'
$taskQuery=& (Join-Path $PSScriptRoot 'build_remaining_wave3_candidate.ps1') -Suite procurement
$taskAt=$taskQuery.LastIndexOf('set constraints all immediate;')
if($taskAt -lt 0){throw 'Missing final constraint boundary'}
$taskQuery=$taskQuery.Insert($taskAt,(Get-Content -Raw -LiteralPath (Join-Path $PSScriptRoot '../wave_tests/wave3_representative_read_plans_test.sql'))+"`n")
$taskNeedle="'read_plans',(select jsonb_agg(plan) from control_read_plans)"
if(-not $taskQuery.Contains($taskNeedle)){throw 'Missing plan evidence output boundary'}
$taskQuery=$taskQuery.Replace($taskNeedle,$taskNeedle+",'representative_read_plans',(select jsonb_agg(evidence) from representative_read_plans)")
if($taskQuery -notmatch 'finish\(true\)' -or $taskQuery -match '(?im)^\s*commit\s*;' -or $taskQuery.TrimEnd() -notmatch 'rollback;$'){
 throw 'Strict rollback required'
}
$taskQuery
