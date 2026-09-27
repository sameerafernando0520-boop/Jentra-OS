[CmdletBinding()]
param([switch]$Installed)
$ErrorActionPreference = 'Stop'
$taskRoot = Split-Path $PSScriptRoot -Parent
$taskMigration = if ($Installed) { '' } else {
  Get-Content -LiteralPath (Join-Path $taskRoot 'migrations/20260926161000_wave4_organization.sql') -Raw
}
$taskFixture = Get-Content -LiteralPath (Join-Path $PSScriptRoot 'wave4_synthetic_fixture.sql') -Raw
$taskTests = Get-Content -LiteralPath (Join-Path $PSScriptRoot 'wave4_organization_test.sql') -Raw
$taskTests = [regex]::Replace($taskTests, '(?m)^select (is|ok|throws_ok)\(', 'insert into organization_assertions select $1(')
$taskDiagnostic = @'
do $$declare v_failed text; begin
  select string_agg(message,E'\n') into v_failed from organization_assertions where message like 'not ok%';
  if v_failed is not null then raise exception using errcode='P0001',message=v_failed; end if;
end $$;
'@
$taskQuery = "begin;`nset local lock_timeout='3s';`nset local statement_timeout='60s';`n$taskMigration`ncreate temporary table organization_assertions(message text);`ngrant insert on organization_assertions to authenticated;`n$taskFixture`n$taskTests`n$taskDiagnostic`nselect * from finish(true);`nrollback;"
if ($taskQuery -match '(?im)^\s*commit\s*;' -or $taskQuery.TrimEnd() -notmatch 'rollback;$') {
  throw 'Organization verification must end with rollback.'
}
$taskQuery
