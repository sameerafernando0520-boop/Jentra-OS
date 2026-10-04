[CmdletBinding()]
param()
$ErrorActionPreference='Stop'
$taskBase=& (Join-Path $PSScriptRoot 'build_project_payroll_impacts_candidate.ps1')
$taskCut=$taskBase.LastIndexOf('do $$declare failed text;begin')
if($taskCut -lt 0){throw 'Project impact diagnostic boundary changed.'}
$taskBase=$taskBase.Substring(0,$taskCut)
$taskFixture=Get-Content -LiteralPath (Join-Path $PSScriptRoot 'wave4_project_billed_payroll_impacts_test.sql') -Raw
$taskMarker='-- BILLING_TEST_BODY'
$taskSplit=$taskFixture.IndexOf($taskMarker)
if($taskSplit -lt 0){throw 'Billed fixture setup boundary changed.'}
$taskSetup=$taskFixture.Substring(0,$taskSplit)
$taskTests=$taskFixture.Substring($taskSplit)
$taskInsert=$taskBase.IndexOf('create temporary table project_impact_samples')
if($taskInsert -lt 0){throw 'Project impact fixture boundary changed.'}
$taskBase=$taskBase.Insert($taskInsert,$taskSetup+[Environment]::NewLine)
$taskCreate="'name','Synthetic direct payroll project','manager_id'"
if(-not $taskBase.Contains($taskCreate)){throw 'Direct project fixture source changed.'}
$taskBase=$taskBase.Replace($taskCreate,"'name','Synthetic direct payroll project','customer_id',pg_temp.wid('pb.customer'),'manager_id'")
$taskTests=[regex]::Replace($taskTests,'(?m)^select (is|ok|throws_ok|lives_ok)\(','insert into payroll_assertions select $1(')
$taskDiagnostic=@'
do $$declare failed text;begin
 select string_agg(message,chr(10)) into failed from payroll_assertions where message like 'not ok%';
 if failed is not null then raise exception using errcode='P0001',message=failed;end if;
end $$;
'@
$taskQuery=(@($taskBase,$taskTests,$taskDiagnostic,'set constraints all immediate;','select * from finish(true);',
 'select count(*) assertions from payroll_assertions;','rollback;')) -join [Environment]::NewLine
if($taskQuery -match '(?im)^\s*commit\s*;' -or -not $taskQuery.TrimEnd().EndsWith('rollback;')){throw 'Billed project impact verification must roll back.'}
$taskQuery
