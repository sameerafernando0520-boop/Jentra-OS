[CmdletBinding()]
param([switch]$ClientSamples)
$ErrorActionPreference='Stop'
$taskQuery=& (Join-Path $PSScriptRoot 'build_expense_evidence_candidate.ps1')
$taskCut=$taskQuery.LastIndexOf('do $$declare failed text;begin')
if($taskCut -lt 0){throw 'Evidence diagnostic boundary changed.'}
$taskTests=Get-Content -LiteralPath (Join-Path $PSScriptRoot 'wave4_project_expense_evidence_integration_test.sql') -Raw
$taskTests=[regex]::Replace($taskTests,'(?m)^select (is|ok|throws_ok|lives_ok)\(','insert into project_assertions select $1(')
$taskTail=$taskQuery.Substring($taskCut)
if($ClientSamples){$taskTail=$taskTail.Replace('rollback;','select jsonb_object_agg(label,body) project_finance_client_samples,(select count(*) from project_assertions) assertions from project_finance_client_samples;'+[Environment]::NewLine+'rollback;')}
$taskQuery=@($taskQuery.Substring(0,$taskCut),$taskTests,$taskTail)-join [Environment]::NewLine
if($taskQuery -match '(?im)^\s*commit\s*;' -or -not $taskQuery.TrimEnd().EndsWith('rollback;')){throw 'Expense integration verification must end in rollback.'}
$taskQuery
