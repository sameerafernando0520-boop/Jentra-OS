[CmdletBinding()]
param([switch]$Installed)
$ErrorActionPreference = 'Stop'
$taskRoot = Split-Path $PSScriptRoot -Parent
$taskMigration = if ($Installed) { '' } else {
  Get-Content -LiteralPath (Join-Path $taskRoot 'migrations/20260929224939_wave4_private_hr.sql') -Raw
}
$taskFixture = Get-Content -LiteralPath (Join-Path $PSScriptRoot '../wave_tests/wave4_synthetic_fixture.sql') -Raw
$taskTests = Get-Content -LiteralPath (Join-Path $PSScriptRoot '../wave_tests/wave4_private_hr_test.sql') -Raw
$taskTests = [regex]::Replace($taskTests, '(?m)^select (is|ok|throws_ok)\(', 'insert into private_hr_assertions select $1(')
$taskDiagnostic = @'
do $$declare v_failed text;begin
 select string_agg(message,chr(10)) into v_failed from private_hr_assertions where message like 'not ok%';
 if v_failed is not null then raise exception using errcode='P0001',message=v_failed;end if;
end $$;
'@
$taskQuery = @(
 'begin;', "set local lock_timeout='3s';", "set local statement_timeout='60s';",
 $taskMigration, 'create temporary table private_hr_assertions(message text);',
 'grant insert on private_hr_assertions to authenticated,service_role;',
 $taskFixture, $taskTests, $taskDiagnostic, 'set constraints all immediate;',
 'select * from finish(true);', 'rollback;'
) -join [Environment]::NewLine
if ($taskQuery -match '(?im)^\s*commit\s*;' -or $taskQuery.TrimEnd() -notmatch 'rollback;$') {
  throw 'Private HR verification must end with rollback.'
}
$taskQuery
