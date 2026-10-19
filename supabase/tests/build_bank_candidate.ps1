[CmdletBinding()]
param([ValidateSet('procurement','inventory','receivables')][string]$Suite='procurement')
$ErrorActionPreference='Stop'
$query=& (Join-Path $PSScriptRoot 'build_control_candidate.ps1') -Suite $Suite
$at=$query.IndexOf('create extension if not exists pgtap')
if($at -lt 0){throw 'Missing fixture boundary'}
$query=$query.Insert($at,(Get-Content -Raw (Join-Path $PSScriptRoot '../migrations/20260923225202_bank_reconciliation.sql'))+"`n")
if($Suite -eq 'procurement'){
 $at=$query.LastIndexOf("select pg_temp.actor('outsider');")
 $query=$query.Insert($at,(Get-Content -Raw (Join-Path $PSScriptRoot '../wave_tests/wave3_bank_test.sql'))+"`n")
}
$query=$query.Replace('select * from finish();','select * from finish(true);')
if($query -match '(?im)^\s*commit\s*;' -or $query.TrimEnd() -notmatch 'rollback;$'){throw 'Rollback required'}
$query
