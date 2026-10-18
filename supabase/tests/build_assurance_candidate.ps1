[CmdletBinding()]
param([ValidateSet('A1','A2','A4','A4b','A3','A5')][string]$Slice = 'A1')
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
$migration = Get-Content -LiteralPath (Join-Path $root 'candidates/20261018090000_assurance_engagement_core.sql') -Raw
$tests = Get-Content -LiteralPath (Join-Path $PSScriptRoot 'assurance_core_test.sql') -Raw
if ($Slice -in 'A2','A4','A4b','A3','A5') {
  # A2 is applied on top of A1 after A1's assertions, as a sequential install would be.
  $tests += "`n" + (Get-Content -LiteralPath (Join-Path $root 'candidates/20261018120000_assurance_testing_carry_forward.sql') -Raw)
  $tests += "`n" + (Get-Content -LiteralPath (Join-Path $PSScriptRoot 'assurance_testing_test.sql') -Raw)
}
if ($Slice -in 'A4','A4b','A3','A5') {
  $tests += "`n" + (Get-Content -LiteralPath (Join-Path $root 'candidates/20261018150000_assurance_evidence_adapters_export.sql') -Raw)
  $tests += "`n" + (Get-Content -LiteralPath (Join-Path $PSScriptRoot 'assurance_evidence_test.sql') -Raw)
}
if ($Slice -in 'A4b','A3','A5') {
  $tests += "`n" + (Get-Content -LiteralPath (Join-Path $root 'candidates/20261018170000_assurance_adapters_monitoring.sql') -Raw)
  $tests += "`n" + (Get-Content -LiteralPath (Join-Path $PSScriptRoot 'assurance_monitoring_test.sql') -Raw)
}
if ($Slice -in 'A3','A5') {
  # A3 installs after A4b (later timestamp) and reuses the earlier fixtures.
  $tests += "`n" + (Get-Content -LiteralPath (Join-Path $root 'candidates/20261018190000_assurance_universe_plans.sql') -Raw)
  $tests += "`n" + (Get-Content -LiteralPath (Join-Path $PSScriptRoot 'assurance_planning_test.sql') -Raw)
}
if ($Slice -eq 'A5') {
  $tests += "`n" + (Get-Content -LiteralPath (Join-Path $root 'candidates/20261018210000_assurance_workspace.sql') -Raw)
  $tests += "`n" + (Get-Content -LiteralPath (Join-Path $PSScriptRoot 'assurance_workspace_test.sql') -Raw)
}
$tests = [regex]::Replace($tests, '(?m)^select (is|ok|throws_ok)\(', 'insert into assurance_assertions select $1(')
$diagnostic = @'
reset role;
do $$
declare v_failed text;
begin
  select string_agg(message, E'\n') into v_failed
  from assurance_assertions where message like 'not ok%';
  if v_failed is not null then
    raise exception using errcode='P0001', message=v_failed;
  end if;
end $$;
'@
$query = "begin;`nset local lock_timeout='3s';`nset local statement_timeout='120s';`n$migration`ncreate temporary table assurance_assertions(message text);`ngrant insert on assurance_assertions to authenticated;`n$tests`n$diagnostic`nselect (select count(*) from assurance_assertions) assertions, (select count(*) from assurance_assertions where message like 'ok%') passed, (select string_agg(message, E'\n') from assurance_assertions where message not like 'ok%') failures;`nrollback;"
if ($query -match '(?im)^\s*commit\s*;' -or $query.TrimEnd() -notmatch 'rollback;$') {
  throw 'Assurance verification must end with rollback.'
}
$query
