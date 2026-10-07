[CmdletBinding()]
param([switch]$ClientSamples)
$ErrorActionPreference='Stop'
$taskRoot=Split-Path $PSScriptRoot -Parent
$taskQuery=& (Join-Path $PSScriptRoot 'build_project_finance_candidate.ps1')
$taskCut=$taskQuery.LastIndexOf('do $$declare failed text;begin')
if($taskCut -lt 0){throw 'Finance diagnostic boundary changed.'}
$taskTests=Get-Content -LiteralPath (Join-Path $PSScriptRoot 'wave4_expense_evidence_test.sql') -Raw
$taskTests=[regex]::Replace($taskTests,'(?m)^select (is|ok|throws_ok|lives_ok)\(','insert into project_assertions select $1(')
$taskTail=$taskQuery.Substring($taskCut)
if($ClientSamples){$taskTail=$taskTail.Replace('rollback;','select jsonb_object_agg(label,body) expense_evidence_samples from expense_evidence_samples;'+[Environment]::NewLine+'rollback;')}
$taskQuery=@($taskQuery.Substring(0,$taskCut),(Get-Content -LiteralPath (Join-Path $taskRoot 'migrations/20261005120000_wave4_project_expense_evidence.sql') -Raw),$taskTests,$taskTail)-join [Environment]::NewLine
if($taskQuery -match '(?im)^\s*commit\s*;' -or -not $taskQuery.TrimEnd().EndsWith('rollback;')){throw 'Evidence verification must end in rollback.'}
$taskQuery
