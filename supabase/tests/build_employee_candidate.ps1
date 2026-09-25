[CmdletBinding()]
param()
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
$migration = Get-Content -LiteralPath (Join-Path $root 'migrations/20260925001000_wave4_employee_foundation.sql') -Raw
$tests = Get-Content -LiteralPath (Join-Path $PSScriptRoot 'wave4_employee_test.sql') -Raw
$tests = [regex]::Replace($tests, '(?m)^select (is|ok|throws_ok)\(', 'insert into employee_assertions select $1(')
$diagnostic = @'
do $$
declare v_failed text;
begin
  select string_agg(message, E'\n') into v_failed
  from employee_assertions where message like 'not ok%';
  if v_failed is not null then
    raise exception using errcode='P0001', message=v_failed;
  end if;
end $$;
'@
$query = "begin;`nset local lock_timeout='3s';`nset local statement_timeout='60s';`n$migration`ncreate temporary table employee_assertions(message text);`ngrant insert on employee_assertions to authenticated;`n$tests`n$diagnostic`nselect * from finish(true);`nrollback;"
if ($query -match '(?im)^\s*commit\s*;' -or $query.TrimEnd() -notmatch 'rollback;$') {
  throw 'Employee verification must end with rollback.'
}
$query
