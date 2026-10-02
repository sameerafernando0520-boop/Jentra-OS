[CmdletBinding()]
param([switch]$ClientSamples)
$ErrorActionPreference='Stop'
$taskRoot=Split-Path $PSScriptRoot -Parent
$taskBase=& (Join-Path $PSScriptRoot 'build_payroll_corrections_candidate.ps1')
$taskCut=$taskBase.LastIndexOf('do $$declare failed text;begin')
if($taskCut -lt 0){throw 'Correction diagnostic boundary changed.'}
$taskBase=$taskBase.Substring(0,$taskCut)
$taskDdl=@()
foreach($taskName in @('20261001080000_wave4_projects_time.sql','20261001100000_wave4_project_expenses_billing.sql','20261002080000_wave4_project_payroll_impacts.sql')){
 $taskDdl+=Get-Content -LiteralPath (Join-Path $taskRoot "migrations/$taskName") -Raw
}
$taskTests=Get-Content -LiteralPath (Join-Path $PSScriptRoot 'wave4_project_payroll_impacts_test.sql') -Raw
$taskTests=[regex]::Replace($taskTests,'(?m)^select (is|ok|throws_ok|lives_ok)\(','insert into payroll_assertions select $1(')
$taskDiagnostic=@'
do $$declare failed text;begin
 select string_agg(message,chr(10)) into failed from payroll_assertions where message like 'not ok%';
 if failed is not null then raise exception using errcode='P0001',message=failed;end if;
end $$;
'@
$taskParts=@($taskBase)+$taskDdl+@($taskTests,$taskDiagnostic,'set constraints all immediate;','select * from finish(true);')
if($ClientSamples){$taskParts+='select (select count(*) from payroll_assertions) as assertions, jsonb_object_agg(name,body) as project_impact_samples from project_impact_samples;'}
else{$taskParts+='select count(*) assertions from payroll_assertions;'}
$taskQuery=($taskParts+@('rollback;')) -join [Environment]::NewLine
if($taskQuery -match '(?im)^\s*commit\s*;' -or -not $taskQuery.TrimEnd().EndsWith('rollback;')){throw 'Project impact verification must roll back.'}
$taskQuery
