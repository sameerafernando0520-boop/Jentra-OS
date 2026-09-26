[CmdletBinding()]
param([switch]$Installed)
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
$migration = if ($Installed) { '' } else {
  Get-Content -LiteralPath (Join-Path $root 'migrations/20260926082441_wave4_calendar_versions.sql') -Raw
}
$tests = Get-Content -LiteralPath (Join-Path $PSScriptRoot 'wave4_calendar_test.sql') -Raw
$tests = [regex]::Replace($tests, '(?m)^select (is|ok|throws_ok)\(', 'insert into calendar_assertions select $1(')
$diagnostic = @'
do $$
declare v_failed text;
begin
  select string_agg(message, E'\n') into v_failed
  from calendar_assertions where message like 'not ok%';
  if v_failed is not null then
    raise exception using errcode='P0001', message=v_failed;
  end if;
end $$;
'@
$query = "begin;`nset local lock_timeout='3s';`nset local statement_timeout='60s';`n$migration`ncreate temporary table calendar_assertions(message text);`ngrant insert on calendar_assertions to authenticated;`n$tests`n$diagnostic`nselect * from finish(true);`nrollback;"
if ($query -match '(?im)^\s*commit\s*;' -or $query.TrimEnd() -notmatch 'rollback;$') {
  throw 'Calendar verification must end with rollback.'
}
$query
