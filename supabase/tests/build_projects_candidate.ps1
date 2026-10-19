[CmdletBinding()]
param([switch]$InstalledPrerequisites,[switch]$Installed,[switch]$ClientSamples)
$ErrorActionPreference='Stop'
$taskRoot=Split-Path $PSScriptRoot -Parent
$taskMigrations=@()
if(-not $InstalledPrerequisites -and -not $Installed){
 $taskMigrations+=Get-Content -LiteralPath (Join-Path $taskRoot 'migrations/20260926160000_wave4_calendar_resolution.sql') -Raw
 $taskMigrations+=Get-Content -LiteralPath (Join-Path $taskRoot 'migrations/20260926161000_wave4_organization.sql') -Raw
 $taskMigrations+=Get-Content -LiteralPath (Join-Path $taskRoot 'migrations/20260928082234_wave4_attendance_intervals.sql') -Raw
}
if(-not $Installed){$taskMigrations+=Get-Content -LiteralPath (Join-Path $taskRoot 'migrations/20261001080000_wave4_projects_time.sql') -Raw}
$taskFixture=Get-Content -LiteralPath (Join-Path $PSScriptRoot '../wave_tests/wave4_synthetic_fixture.sql') -Raw
$taskTests=Get-Content -LiteralPath (Join-Path $PSScriptRoot '../wave_tests/wave4_projects_test.sql') -Raw
$taskTests=[regex]::Replace($taskTests,'(?m)^select (is|ok|throws_ok)\(','insert into project_assertions select $1(')
$taskDiagnostic=@'
do $$declare failed text;begin
 select string_agg(message,chr(10)) into failed from project_assertions where message like 'not ok%';
 if failed is not null then raise exception using errcode='P0001',message=failed;end if;
end $$;
'@
$taskQuery=(@('begin;',"set local lock_timeout='3s';","set local statement_timeout='60s';")+$taskMigrations+@(
 'create temporary table project_assertions(message text);','grant insert on project_assertions to authenticated,service_role;',
 $taskFixture,$taskTests,$taskDiagnostic,'set constraints all immediate;','select * from finish(true);'
)+$(if($ClientSamples){'select (select count(*) from project_assertions) assertions,jsonb_object_agg(label,body) project_client_samples from project_client_samples;'}else{'select count(*) assertions from project_assertions;'})+@('rollback;'))-join [Environment]::NewLine
if($taskQuery -match '(?im)^\s*commit\s*;' -or $taskQuery.TrimEnd() -notmatch 'rollback;$'){throw 'Project verification must end in rollback.'}
$taskQuery
