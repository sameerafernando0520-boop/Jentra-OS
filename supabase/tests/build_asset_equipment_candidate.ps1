[CmdletBinding()]
param()
$ErrorActionPreference='Stop'
$taskRoot=Split-Path $PSScriptRoot -Parent
$fixture=Get-Content (Join-Path $PSScriptRoot 'wave4_synthetic_fixture.sql') -Raw
$fixture=$fixture.Replace("(now() at time zone 'Asia/Colombo')::date","((now()-interval '1 day') at time zone 'Asia/Colombo')::date")
$ddl=@('20260926160000_wave4_calendar_resolution.sql','20260926161000_wave4_organization.sql','20260928082234_wave4_attendance_intervals.sql','20261001090000_wave4_service.sql','20260930071000_wave4_fixed_assets.sql','20261005090000_service_asset_equipment.sql') | ForEach-Object {Get-Content (Join-Path $taskRoot "migrations/$_") -Raw}
$tests=@()
foreach($pair in @(@('wave4_service_test.sql','service_assertions'),@('wave4_assets_test.sql','asset_assertions'),@('wave4_asset_equipment_test.sql','link_assertions'))){
 $body=Get-Content (Join-Path $PSScriptRoot $pair[0]) -Raw
 if($pair[1]-ne 'service_assertions'){$body=$body.Replace('select no_plan();','')}
 $body=[regex]::Replace($body,'(?m)^select (is|ok|throws_ok|lives_ok)\(',"insert into $($pair[1]) select `$1(")
 $tests+=$body
}
$diagnostic=@'
do $$declare failed text;begin
 select string_agg(message,chr(10)) into failed from(select message from service_assertions union all select message from asset_assertions union all select message from link_assertions) q where message like 'not ok%';
 if failed is not null then raise exception using errcode='P0001',message=failed;end if;
end $$;
'@
$query=(@('begin;',"set local lock_timeout='3s';","set local statement_timeout='90s';")+$ddl+@(
 'create temporary table service_assertions(message text);create temporary table asset_assertions(message text);create temporary table link_assertions(message text);',
 'grant insert on service_assertions,asset_assertions,link_assertions to authenticated;', $fixture)+$tests+@($diagnostic,'set constraints all immediate;','select * from finish(true);',
 'select(select count(*) from service_assertions)+(select count(*) from asset_assertions)+(select count(*) from link_assertions) assertion_count,jsonb_object_agg(label,body) asset_equipment_client_samples from asset_equipment_samples;','rollback;')) -join [Environment]::NewLine
if($query -match '(?im)^\s*commit\s*;' -or -not $query.TrimEnd().EndsWith('rollback;')){throw 'Asset equipment verification must roll back.'}
$query
