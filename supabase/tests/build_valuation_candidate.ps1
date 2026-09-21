[CmdletBinding()]
param([ValidateSet('procurement','inventory','receivables')][string]$Suite='procurement')
$ErrorActionPreference='Stop'
$query=& (Join-Path $PSScriptRoot 'build_landed_candidate.ps1') -Suite $Suite
$at=$query.IndexOf('create extension if not exists pgtap')
if($at -lt 0){throw 'Missing fixture boundary'}
$query=$query.Insert($at,(Get-Content -Raw (Join-Path $PSScriptRoot '../migrations/20260920202547_inventory_valuation_reports.sql'))+"`n")
if($Suite -eq 'procurement'){
 $at=$query.LastIndexOf("select pg_temp.actor('outsider');")
 $query=$query.Insert($at,(Get-Content -Raw (Join-Path $PSScriptRoot 'wave3_inventory_valuation_test.sql'))+"`n")
}
if($query -match '(?im)^\s*commit\s*;' -or $query.TrimEnd() -notmatch 'rollback;$'){throw 'Rollback required'}
$query
