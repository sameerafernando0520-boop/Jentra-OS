[CmdletBinding()]
param()
$ErrorActionPreference='Stop'
$milestoneBase=& (Join-Path $PSScriptRoot 'build_project_finance_candidate.ps1')
$milestoneCut=$milestoneBase.LastIndexOf('do $$declare failed text;begin')
if($milestoneCut -lt 0){throw 'Finance diagnostic boundary changed.'}
$milestoneBase=$milestoneBase.Substring(0,$milestoneCut)
$milestoneDdl=Get-Content (Join-Path (Split-Path $PSScriptRoot -Parent) 'migrations/20261004090000_project_milestones.sql') -Raw
$milestoneTests=Get-Content (Join-Path $PSScriptRoot '../wave_tests/wave4_milestones_test.sql') -Raw
$milestoneTests=[regex]::Replace($milestoneTests,'(?m)^select (is|ok|throws_ok|lives_ok)\(','insert into project_assertions select $1(')
$milestoneDiagnostic=@'
do $$declare failed text;begin
 select string_agg(message,chr(10)) into failed from project_assertions where message like 'not ok%';
 if failed is not null then raise exception using errcode='P0001',message=failed;end if;
end $$;
'@
$milestoneQuery=(@($milestoneBase,$milestoneDdl,$milestoneTests,$milestoneDiagnostic,'set constraints all immediate;',
 'select * from finish(true);','select (select count(*) from project_assertions) assertions,jsonb_object_agg(label,body) milestone_client_samples from milestone_client_samples;','rollback;')) -join [Environment]::NewLine
if($milestoneQuery -match '(?im)^\s*commit\s*;' -or -not $milestoneQuery.TrimEnd().EndsWith('rollback;')){throw 'Milestones must roll back.'}
$milestoneQuery
