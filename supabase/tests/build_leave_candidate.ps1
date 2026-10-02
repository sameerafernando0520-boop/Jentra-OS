[CmdletBinding()]
param([switch]$InstalledPrerequisites, [switch]$Installed)
$ErrorActionPreference = 'Stop'
$taskRoot = Split-Path $PSScriptRoot -Parent
$taskMigrations = @()
if (-not $InstalledPrerequisites -and -not $Installed) {
  foreach ($taskName in @(
    '20260926160000_wave4_calendar_resolution.sql',
    '20260926161000_wave4_organization.sql',
    '20260928082234_wave4_attendance_intervals.sql'
  )) {
    $taskMigrations += Get-Content -LiteralPath (Join-Path $taskRoot "migrations/$taskName") -Raw
  }
}
if (-not $Installed) {
  $taskMigrations += Get-Content -LiteralPath (Join-Path $taskRoot 'migrations/20260928083449_wave4_leave_ledger.sql') -Raw
}
$taskFixture = Get-Content -LiteralPath (Join-Path $PSScriptRoot 'wave4_synthetic_fixture.sql') -Raw
$taskTests = Get-Content -LiteralPath (Join-Path $PSScriptRoot 'wave4_leave_test.sql') -Raw
$taskTests = [regex]::Replace($taskTests, '(?m)^select (is|ok|throws_ok)\(', 'insert into leave_assertions select $1(')
$taskDiagnostic = @'
do $$declare v_failed text;begin
 select string_agg(message,chr(10)) into v_failed from leave_assertions where message like 'not ok%';
 if v_failed is not null then raise exception using errcode='P0001',message=v_failed;end if;
end $$;
'@
$taskQuery = (@(
 'begin;', "set local lock_timeout='3s';", "set local statement_timeout='60s';"
) + $taskMigrations + @(
 'create temporary table leave_assertions(message text);',
 'grant insert on leave_assertions to authenticated,service_role;',
 $taskFixture, $taskTests, $taskDiagnostic, 'set constraints all immediate;',
 'select * from finish(true);', 'rollback;'
)) -join [Environment]::NewLine
if ($taskQuery -match '(?im)^\s*commit\s*;' -or $taskQuery.TrimEnd() -notmatch 'rollback;$') {
  throw 'Leave verification must end with rollback.'
}
$taskQuery
