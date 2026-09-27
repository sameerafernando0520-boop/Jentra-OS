[CmdletBinding()]
param([ValidateSet('procurement','inventory','receivables')][string]$Suite='procurement')
$ErrorActionPreference='Stop'
$query=& (Join-Path $PSScriptRoot 'build_close_review_candidate.ps1') -Suite $Suite
$at=$query.LastIndexOf('set constraints all immediate;')
if($at -lt 0){throw 'Missing fixture boundary'}
$query=$query.Insert($at,(Get-Content -Raw (Join-Path $PSScriptRoot '../migrations/20260926009000_wave3_governed_report_exports.sql'))+"`n")
if($Suite -eq 'procurement'){
 $at=$query.LastIndexOf('set constraints all immediate;')
 $query=$query.Insert($at,(Get-Content -Raw (Join-Path $PSScriptRoot 'wave3_report_exports_test.sql'))+"`n")
}
if($query -notmatch 'finish\(true\)' -or $query -match '(?im)^\s*commit\s*;' -or $query.TrimEnd() -notmatch 'rollback;$'){throw 'Strict rollback required'}
$query
