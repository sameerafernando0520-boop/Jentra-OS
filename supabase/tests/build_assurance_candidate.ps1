[CmdletBinding()]
param()
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
$migration = Get-Content -LiteralPath (Join-Path $root 'candidates/20261018090000_assurance_engagement_core.sql') -Raw
$tests = Get-Content -LiteralPath (Join-Path $PSScriptRoot 'assurance_core_test.sql') -Raw
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
$query = "begin;`nset local lock_timeout='3s';`nset local statement_timeout='120s';`n$migration`ncreate temporary table assurance_assertions(message text);`ngrant insert on assurance_assertions to authenticated;`n$tests`n$diagnostic`nselect (select count(*) from assurance_assertions) assertions, (select count(*) from assurance_assertions where message like 'ok%') passed;`nrollback;"
if ($query -match '(?im)^\s*commit\s*;' -or $query.TrimEnd() -notmatch 'rollback;$') {
  throw 'Assurance verification must end with rollback.'
}
$query
