[CmdletBinding()]
param(
  [ValidateSet('A1','A2','A4','A4b','A3','A5','A6','A7','A8','A9','A10','A11','A12','A14')][string]$Slice = 'A1',
  # Installed variant: runs the same suites against the installed schema
  # (no candidate DDL) and expects the final 24-table schema at every stage.
  [switch]$Installed,
  # pgTAP variant for `supabase test db`: the installed suite with raw TAP
  # output, ending in finish() and rollback. Implies -Installed.
  [switch]$Pgtap
)
if ($Pgtap) { $Installed = $true }
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
# Fragments live outside supabase/tests so `supabase test db` does not run them alone.
$fragments = Join-Path $root 'assurance_tests'
$migration = Get-Content -LiteralPath (Join-Path $root 'candidates/20261018090000_assurance_engagement_core.sql') -Raw
$tests = Get-Content -LiteralPath (Join-Path $fragments 'assurance_core_test.sql') -Raw
if ($Slice -in 'A2','A4','A4b','A3','A5','A6','A7','A8','A9','A10','A11','A12','A14') {
  # A2 is applied on top of A1 after A1's assertions, as a sequential install would be.
  $tests += "`n" + (Get-Content -LiteralPath (Join-Path $root 'candidates/20261018120000_assurance_testing_carry_forward.sql') -Raw)
  $tests += "`n" + (Get-Content -LiteralPath (Join-Path $fragments 'assurance_testing_test.sql') -Raw)
}
if ($Slice -in 'A4','A4b','A3','A5','A6','A7','A8','A9','A10','A11','A12','A14') {
  $tests += "`n" + (Get-Content -LiteralPath (Join-Path $root 'candidates/20261018150000_assurance_evidence_adapters_export.sql') -Raw)
  $tests += "`n" + (Get-Content -LiteralPath (Join-Path $fragments 'assurance_evidence_test.sql') -Raw)
}
if ($Slice -in 'A4b','A3','A5','A6','A7','A8','A9','A10','A11','A12','A14') {
  $tests += "`n" + (Get-Content -LiteralPath (Join-Path $root 'candidates/20261018170000_assurance_adapters_monitoring.sql') -Raw)
  $tests += "`n" + (Get-Content -LiteralPath (Join-Path $fragments 'assurance_monitoring_test.sql') -Raw)
}
if ($Slice -in 'A3','A5','A6','A7','A8','A9','A10','A11','A12','A14') {
  # A3 installs after A4b (later timestamp) and reuses the earlier fixtures.
  $tests += "`n" + (Get-Content -LiteralPath (Join-Path $root 'candidates/20261018190000_assurance_universe_plans.sql') -Raw)
  $tests += "`n" + (Get-Content -LiteralPath (Join-Path $fragments 'assurance_planning_test.sql') -Raw)
}
if ($Slice -in 'A5','A6','A7','A8','A9','A10','A11','A12','A14') {
  $tests += "`n" + (Get-Content -LiteralPath (Join-Path $root 'candidates/20261018210000_assurance_workspace.sql') -Raw)
  $tests += "`n" + (Get-Content -LiteralPath (Join-Path $fragments 'assurance_workspace_test.sql') -Raw)
}
if ($Slice -in 'A6','A7','A8','A9','A10','A11','A12','A14') {
  # Version-guard candidate (PR #1 review), applied after the installed A1-A5.
  $tests += "`n" + (Get-Content -LiteralPath (Join-Path $root 'candidates/20261019090000_assurance_version_guard.sql') -Raw)
  $tests += "`n" + (Get-Content -LiteralPath (Join-Path $fragments 'assurance_version_guard_test.sql') -Raw)
  # Plan register candidate (desktop planning screens).
  $tests += "`n" + (Get-Content -LiteralPath (Join-Path $root 'candidates/20261019130000_assurance_plan_register.sql') -Raw)
  $tests += "`n" + (Get-Content -LiteralPath (Join-Path $fragments 'assurance_plan_register_test.sql') -Raw)
}
if ($Slice -in 'A7','A8','A9','A10','A11','A12','A14') {
  # Evidence storage and byte verification (PR #1 review), after the guard.
  $tests += "`n" + (Get-Content -LiteralPath (Join-Path $root 'candidates/20261019120000_assurance_evidence_storage.sql') -Raw)
  $tests += "`n" + (Get-Content -LiteralPath (Join-Path $fragments 'assurance_evidence_storage_test.sql') -Raw)
}
if ($Slice -in 'A8','A9','A10','A11','A12','A14') {
  # Access: owner backfill, seeded assurance roles and the access APIs.
  $tests += "`n" + (Get-Content -LiteralPath (Join-Path $root 'candidates/20261020090000_assurance_access.sql') -Raw)
  $tests += "`n" + (Get-Content -LiteralPath (Join-Path $fragments 'assurance_access_test.sql') -Raw)
}
if ($Slice -in 'A9','A10','A11','A12','A14') {
  # Settings and plan revision; replaces the plan, evidence and workspace functions.
  $tests += "`n" + (Get-Content -LiteralPath (Join-Path $root 'candidates/20261020120000_assurance_settings.sql') -Raw)
  $tests += "`n" + (Get-Content -LiteralPath (Join-Path $fragments 'assurance_settings_test.sql') -Raw)
}
if ($Slice -in 'A10','A11','A12','A14') {
  # Reminder delivery into workflow.notifications.
  $tests += "`n" + (Get-Content -LiteralPath (Join-Path $root 'candidates/20261020150000_assurance_reminders.sql') -Raw)
  $tests += "`n" + (Get-Content -LiteralPath (Join-Path $fragments 'assurance_reminders_test.sql') -Raw)
}
if ($Slice -in 'A11','A12','A14') {
  # Process metrics (FR-6825) from events and current state.
  $tests += "`n" + (Get-Content -LiteralPath (Join-Path $root 'candidates/20261020180000_assurance_metrics.sql') -Raw)
  $tests += "`n" + (Get-Content -LiteralPath (Join-Path $fragments 'assurance_metrics_test.sql') -Raw)
}
if ($Slice -in 'A12','A14') {
  # Reviewer download of verified evidence (needs the A7 storage candidate).
  $tests += "`n" + (Get-Content -LiteralPath (Join-Path $root 'candidates/20261020210000_assurance_evidence_download.sql') -Raw)
  $tests += "`n" + (Get-Content -LiteralPath (Join-Path $fragments 'assurance_evidence_download_test.sql') -Raw)
}
if ($Slice -eq 'A14') {
  # People for pickers (A13 added no SQL).
  $tests += "`n" + (Get-Content -LiteralPath (Join-Path $root 'candidates/20261020230000_assurance_people.sql') -Raw)
  $tests += "`n" + (Get-Content -LiteralPath (Join-Path $fragments 'assurance_people_test.sql') -Raw)
}
if ($Installed) {
  $migration = '-- installed variant: schema already installed; no candidate DDL'
  foreach ($candidate in Get-ChildItem -LiteralPath (Join-Path $root 'candidates') -Filter '20261018*_assurance_*.sql') {
    $tests = $tests.Replace((Get-Content -LiteralPath $candidate.FullName -Raw), '')
  }
  $tests = [regex]::Replace($tests, 'count\(\*\)=(12|14|16|17) and bool_and', 'count(*)=24 and bool_and')
}
if ($Pgtap) {
  # A fresh database has no synthetic People plan; create it inside the
  # transaction, as the Wave 4 fixture does for its own plan.
  $fixture = @'
insert into billing.plans(code,name) select 'w4_employee_synthetic','Internal W4 Employee Synthetic Test'
  where not exists (select 1 from billing.plans where code='w4_employee_synthetic');
insert into billing.plan_entitlements(plan_code,entitlement_code,enabled)
  select 'w4_employee_synthetic','module.people',true where not exists (select 1 from billing.plan_entitlements
    where plan_code='w4_employee_synthetic' and entitlement_code='module.people');
'@
  $query = "-- Generated by supabase/tests/build_assurance_candidate.ps1 -Slice $Slice -Pgtap; do not edit.`nbegin;`n$fixture`n$tests`nreset role;`nselect * from finish();`nrollback;"
  if ($query -match '(?im)^\s*commit\s*;' -or $query.TrimEnd() -notmatch 'rollback;$') {
    throw 'Assurance verification must end with rollback.'
  }
  return $query
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
