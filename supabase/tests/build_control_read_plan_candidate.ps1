[CmdletBinding()]
param([ValidateSet('procurement','inventory','receivables')][string]$Suite='procurement')
$ErrorActionPreference='Stop'
$query=& (Join-Path $PSScriptRoot 'build_wave3_finance_stack_candidate.ps1') -Suite $Suite
$query=$query.Replace('set local jit=off;','set local jit=on;')
$at=$query.IndexOf('create extension if not exists pgtap')
if($at -lt 0){throw 'Missing synthetic fixture boundary'}
$query=$query.Insert($at,(Get-Content -Raw (Join-Path $PSScriptRoot '../migrations/20260927001000_wave3_control_read_plan.sql'))+"`n")
if($Suite -eq 'procurement'){
 $at=$query.LastIndexOf('set constraints all immediate;')
 $query=$query.Insert($at,(Get-Content -Raw (Join-Path $PSScriptRoot 'wave3_control_read_plan_test.sql'))+"`n")
 $query=$query.Replace('select jsonb_agg(message) as results from procurement_test_results;',
  "select jsonb_build_object('results',(select jsonb_agg(message) from procurement_test_results),'read_plans',(select jsonb_agg(plan) from control_read_plans)) as evidence;")
}
if($query -notmatch 'finish\(true\)' -or $query -match '(?im)^\s*commit\s*;' -or $query.TrimEnd() -notmatch 'rollback;$'){
 throw 'Strict rollback required'
}
$query
