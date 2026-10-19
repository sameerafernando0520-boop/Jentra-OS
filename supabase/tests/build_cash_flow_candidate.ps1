[CmdletBinding()]
param([ValidateSet('procurement','inventory','receivables')][string]$Suite='procurement')
$ErrorActionPreference='Stop'
$query=& (Join-Path $PSScriptRoot 'build_financial_statement_candidate.ps1') -Suite $Suite
$at=$query.LastIndexOf('set constraints all immediate;')
if($at -lt 0){throw 'Missing fixture boundary'}
$query=$query.Insert($at,(Get-Content -Raw (Join-Path $PSScriptRoot '../migrations/20260925003000_wave3_cash_flow.sql'))+"`n")
if($Suite -eq 'procurement'){
 $at=$query.LastIndexOf('set constraints all immediate;')
 $query=$query.Insert($at,(Get-Content -Raw (Join-Path $PSScriptRoot '../wave_tests/wave3_cash_flow_test.sql'))+"`n")
}
$query=$query.Replace('select * from finish();','select * from finish(true);')
if($query -match '(?im)^\s*commit\s*;' -or $query.TrimEnd() -notmatch 'rollback;$'){throw 'Rollback required'}
$query
