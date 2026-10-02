[CmdletBinding()]
param([switch]$Installed,[switch]$ClientSamples)
$ErrorActionPreference='Stop'
$taskRoot=Split-Path $PSScriptRoot -Parent
$taskMigrations=@()
if(-not $Installed){
 $taskMigrations+=Get-Content -LiteralPath (Join-Path $taskRoot 'migrations/20260930071000_wave4_fixed_assets.sql') -Raw
}
$taskFixture=Get-Content -LiteralPath (Join-Path $PSScriptRoot 'wave4_synthetic_fixture.sql') -Raw
$taskTests=Get-Content -LiteralPath (Join-Path $PSScriptRoot 'wave4_assets_test.sql') -Raw
$taskTests=[regex]::Replace($taskTests,'(?m)^select (is|ok|throws_ok)\(','insert into asset_assertions select $1(')
$taskSamples=$(if($ClientSamples){'select jsonb_object_agg(label,body order by label) as asset_client_samples from asset_client_samples;'}else{''})
$taskDiagnostic=@'
do $$declare failed text;begin
 select string_agg(message,chr(10)) into failed from asset_assertions where message like 'not ok%';
 if failed is not null then raise exception using errcode='P0001',message=failed;end if;
end $$;
'@
$taskQuery=(@('begin;',"set local lock_timeout='3s';","set local statement_timeout='90s';")+
 $taskMigrations+@('create temporary table asset_assertions(message text);',
 'grant insert on asset_assertions to authenticated,service_role;',
 $taskFixture,$taskTests,$taskDiagnostic,'set constraints all immediate;',
 'select * from finish(true);',$taskSamples,'rollback;')) -join [Environment]::NewLine
if($taskQuery -match '(?im)^\s*commit\s*;' -or -not $taskQuery.TrimEnd().EndsWith('rollback;')){
 throw 'Asset verification must end with rollback.'
}
$taskQuery
