[CmdletBinding()]
param([switch]$Installed, [switch]$ClientSamples)
$ErrorActionPreference='Stop'
$taskRoot=Split-Path $PSScriptRoot -Parent
$taskDdl=@()
if (-not $Installed) {
  foreach ($taskName in @('20260926160000_wave4_calendar_resolution.sql','20260926161000_wave4_organization.sql','20260928082234_wave4_attendance_intervals.sql','20261001090000_wave4_service.sql')) {
    $taskDdl+=Get-Content -LiteralPath (Join-Path $taskRoot "migrations/$taskName") -Raw
  }
}
$taskFixture=Get-Content -LiteralPath (Join-Path $PSScriptRoot 'wave4_synthetic_fixture.sql') -Raw
# This suite performs same-day 09:00-14:00 historical work. Use the previous
# Colombo civil day so overnight runs do not submit future observed instants.
$taskFixture=$taskFixture.Replace("(now() at time zone 'Asia/Colombo')::date","((now()-interval '1 day') at time zone 'Asia/Colombo')::date")
$taskTests=Get-Content -LiteralPath (Join-Path $PSScriptRoot 'wave4_service_test.sql') -Raw
$taskTests=[regex]::Replace($taskTests,'(?m)^select (is|ok|throws_ok)\(','insert into service_assertions select $1(')
$taskSql=(@('begin;',"set local lock_timeout='3s';","set local statement_timeout='60s';")+$taskDdl+@(
 'create temporary table service_assertions(message text);','grant insert on service_assertions to authenticated;',
 $taskFixture,$taskTests,
 'do $$declare failed text;begin select string_agg(message,chr(10)) into failed from service_assertions where message like ''not ok%'';if failed is not null then raise exception ''%'',failed;end if;end $$;',
 'set constraints all immediate;',
 'select * from finish(true);',
 $(if($ClientSamples){'select (select count(*) from service_assertions) as assertion_count,jsonb_object_agg(name,body) as service_client_samples from service_samples;'}else{"select count(*) assertion_count from service_assertions;"}),
 'rollback;')) -join [Environment]::NewLine
if ($taskSql -match '(?im)^\s*commit\s*;' -or $taskSql.TrimEnd() -notmatch 'rollback;$') {throw 'Service checks must end with rollback.'}
$taskSql
