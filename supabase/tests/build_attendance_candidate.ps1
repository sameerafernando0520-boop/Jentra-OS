[CmdletBinding()]
param([switch]$InstalledPrerequisites, [switch]$Installed, [switch]$IncludeClockBatches)
$ErrorActionPreference = 'Stop'
$taskRoot = Split-Path $PSScriptRoot -Parent
$taskMigrations = @()
if (-not $InstalledPrerequisites -and -not $Installed) {
  $taskMigrations += Get-Content -LiteralPath (Join-Path $taskRoot 'migrations/20260926160000_wave4_calendar_resolution.sql') -Raw
  $taskMigrations += Get-Content -LiteralPath (Join-Path $taskRoot 'migrations/20260926161000_wave4_organization.sql') -Raw
}
if (-not $Installed) {
  $taskMigrations += Get-Content -LiteralPath (Join-Path $taskRoot 'migrations/20260928082234_wave4_attendance_intervals.sql') -Raw
  if ($IncludeClockBatches) {
    $taskMigrations += Get-Content -LiteralPath (Join-Path $taskRoot 'migrations/20260930070500_wave4_clock_batches.sql') -Raw
  }
}
$taskFixture = Get-Content -LiteralPath (Join-Path $PSScriptRoot '../wave_tests/wave4_synthetic_fixture.sql') -Raw
$taskTests = Get-Content -LiteralPath (Join-Path $PSScriptRoot '../wave_tests/wave4_attendance_test.sql') -Raw
if ($IncludeClockBatches) {
  $taskTests += [Environment]::NewLine + (Get-Content -LiteralPath (Join-Path $PSScriptRoot '../wave_tests/wave4_clock_batch_test.sql') -Raw)
}
$taskTests = [regex]::Replace($taskTests, '(?m)^select (is|ok|throws_ok)\(', 'insert into attendance_assertions select $1(')
$taskDiagnostic = @'
do $$declare v_failed text;begin
 select string_agg(message,chr(10)) into v_failed from attendance_assertions where message like 'not ok%';
 if v_failed is not null then raise exception using errcode='P0001',message=v_failed;end if;
end $$;
'@
$taskQuery = (@(
 'begin;', "set local lock_timeout='3s';", "set local statement_timeout='60s';"
) + $taskMigrations + @(
 'create temporary table attendance_assertions(message text);',
 'grant insert on attendance_assertions to authenticated,service_role;',
 $taskFixture, $taskTests, $taskDiagnostic, 'set constraints all immediate;',
 'select * from finish(true);', 'rollback;'
)) -join [Environment]::NewLine
if ($taskQuery -match '(?im)^\s*commit\s*;' -or $taskQuery.TrimEnd() -notmatch 'rollback;$') {
  throw 'Attendance verification must end with rollback.'
}
$taskQuery
