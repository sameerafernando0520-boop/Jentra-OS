[CmdletBinding()]
param([ValidateSet('procurement','inventory','receivables')][string]$Suite='procurement')
$ErrorActionPreference='Stop'
$query=& (Join-Path $PSScriptRoot 'build_report_export_candidate.ps1') -Suite $Suite
$at=$query.LastIndexOf('set constraints all immediate;')
if($at -lt 0){throw 'Missing fixture boundary'}
$query=$query.Insert($at,(Get-Content -Raw (Join-Path $PSScriptRoot '../migrations/20260926010000_wave3_financial_dimensions.sql'))+"`n")
if($Suite -eq 'procurement'){
 $at=$query.LastIndexOf('set constraints all immediate;')
 $query=$query.Insert($at,(Get-Content -Raw (Join-Path $PSScriptRoot 'wave3_financial_dimensions_test.sql'))+"`n")
}
if($query -notmatch 'finish\(true\)' -or $query -match '(?im)^\s*commit\s*;' -or $query.TrimEnd() -notmatch 'rollback;$'){throw 'Strict rollback required'}
$query

