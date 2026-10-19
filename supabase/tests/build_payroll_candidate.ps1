[CmdletBinding()]
param([switch]$InstalledPrerequisites,[switch]$Installed)
$ErrorActionPreference='Stop'
$taskRoot=Split-Path $PSScriptRoot -Parent
$taskMigrations=@()
if(-not $InstalledPrerequisites -and -not $Installed){
 foreach($taskName in @('20260926160000_wave4_calendar_resolution.sql',
  '20260926161000_wave4_organization.sql','20260928082234_wave4_attendance_intervals.sql',
  '20260928083449_wave4_leave_ledger.sql')){
  $taskMigrations+=Get-Content -LiteralPath (Join-Path $taskRoot "migrations/$taskName") -Raw
 }
}
if(-not $Installed){
 $taskMigrations+=Get-Content -LiteralPath (Join-Path $taskRoot 'migrations/20260930070000_wave4_synthetic_payroll.sql') -Raw
}
$taskFixture=Get-Content -LiteralPath (Join-Path $PSScriptRoot '../wave_tests/wave4_synthetic_fixture.sql') -Raw
$taskTests=Get-Content -LiteralPath (Join-Path $PSScriptRoot '../wave_tests/wave4_payroll_test.sql') -Raw
$taskTests=[regex]::Replace($taskTests,'(?m)^select (is|ok|throws_ok)\(','insert into payroll_assertions select $1(')
$taskDiagnostic=@'
do $$declare failed text;begin
 select string_agg(message,chr(10)) into failed from payroll_assertions where message like 'not ok%';
 if failed is not null then raise exception using errcode='P0001',message=failed;end if;
end $$;
'@
$taskQuery=(@('begin;',"set local lock_timeout='3s';","set local statement_timeout='90s';")+
 $taskMigrations+@('create temporary table payroll_assertions(message text);',
 'grant insert on payroll_assertions to authenticated,service_role;',
 $taskFixture,$taskTests,$taskDiagnostic,'set constraints all immediate;',
 'select * from finish(true);','rollback;')) -join [Environment]::NewLine
if($taskQuery -match '(?im)^\s*commit\s*;' -or -not $taskQuery.TrimEnd().EndsWith('rollback;')){
 throw 'Payroll verification must end with rollback.'
}
$taskQuery
