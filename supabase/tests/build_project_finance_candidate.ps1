[CmdletBinding()]
param([switch]$InstalledPrerequisites,[switch]$Installed,[switch]$ClientSamples)
$ErrorActionPreference='Stop'
$taskRoot=Split-Path $PSScriptRoot -Parent
$taskMigrations=@()
if(-not $InstalledPrerequisites -and -not $Installed){
 foreach($taskName in @('20260926160000_wave4_calendar_resolution.sql','20260926161000_wave4_organization.sql','20260928082234_wave4_attendance_intervals.sql','20261001080000_wave4_projects_time.sql')){
  $taskMigrations+=Get-Content -LiteralPath (Join-Path $taskRoot "migrations/$taskName") -Raw
 }
}
if(-not $Installed){$taskMigrations+=Get-Content -LiteralPath (Join-Path $taskRoot 'migrations/20261001100000_wave4_project_expenses_billing.sql') -Raw}
$taskTests=(Get-Content -LiteralPath (Join-Path $PSScriptRoot 'wave4_projects_test.sql') -Raw)+[Environment]::NewLine+(Get-Content -LiteralPath (Join-Path $PSScriptRoot 'wave4_project_finance_test.sql') -Raw)
$taskTests=[regex]::Replace($taskTests,'(?m)^select (is|ok|throws_ok|lives_ok)\(','insert into project_assertions select $1(')
$taskDiagnostic=@'
do $$declare failed text;begin
 select string_agg(message,chr(10)) into failed from project_assertions where message like 'not ok%';
 if failed is not null then raise exception using errcode='P0001',message=failed;end if;
end $$;
'@
$taskQuery=(@('begin;',"set local lock_timeout='3s';","set local statement_timeout='90s';")+$taskMigrations+@(
 'create temporary table project_assertions(message text);','grant insert on project_assertions to authenticated,service_role;',
 (Get-Content -LiteralPath (Join-Path $PSScriptRoot 'wave4_synthetic_fixture.sql') -Raw),$taskTests,$taskDiagnostic,'set constraints all immediate;','select * from finish(true);',
 $(if($ClientSamples){'select jsonb_object_agg(label,body) project_finance_client_samples,(select count(*) from project_assertions) assertions from project_finance_client_samples;'}else{"select count(*) assertions from project_assertions;"}),'rollback;'))-join [Environment]::NewLine
if($taskQuery -match '(?im)^\s*commit\s*;' -or $taskQuery.TrimEnd() -notmatch 'rollback;$'){throw 'Finance verification must end in rollback.'}
$taskQuery
