[CmdletBinding()]
param([ValidateSet('procurement','inventory','receivables')][string]$Suite='procurement')
$ErrorActionPreference='Stop'
$query=& (Join-Path $PSScriptRoot 'build_budget_candidate.ps1') -Suite $Suite
$at=$query.LastIndexOf('set constraints all immediate;')
if($at -lt 0){throw 'Missing fixture boundary'}
$query=$query.Insert($at,(Get-Content -Raw (Join-Path $PSScriptRoot '../migrations/20260926001000_wave3_tax_summary.sql'))+"`n"+
 (Get-Content -Raw (Join-Path $PSScriptRoot '../migrations/20260926002000_wave3_tax_summary_hardening.sql'))+"`n"+
 (Get-Content -Raw (Join-Path $PSScriptRoot '../migrations/20260926003000_wave3_tax_control_reconciliation.sql'))+"`n"+
 (Get-Content -Raw (Join-Path $PSScriptRoot '../migrations/20260926005000_wave3_governed_journal_tax.sql'))+"`n"+
 (Get-Content -Raw (Join-Path $PSScriptRoot '../migrations/20260926006000_wave3_tax_control_movements.sql'))+"`n")
if($Suite -eq 'procurement'){
 $at=$query.LastIndexOf('set constraints all immediate;')
 $query=$query.Insert($at,(Get-Content -Raw (Join-Path $PSScriptRoot 'wave3_tax_summary_test.sql'))+"`n")
 $at=$query.LastIndexOf('set constraints all immediate;')
 $query=$query.Insert($at,(Get-Content -Raw (Join-Path $PSScriptRoot 'wave3_tax_controls_test.sql'))+"`n")
 $at=$query.LastIndexOf('set constraints all immediate;')
 $query=$query.Insert($at,(Get-Content -Raw (Join-Path $PSScriptRoot 'wave3_journal_tax_test.sql'))+"`n")
 $at=$query.LastIndexOf('set constraints all immediate;')
 $query=$query.Insert($at,(Get-Content -Raw (Join-Path $PSScriptRoot 'wave3_tax_movements_test.sql'))+"`n")
}elseif($Suite -eq 'receivables'){
 $at=$query.LastIndexOf('set constraints all immediate;')
 $query=$query.Insert($at,(Get-Content -Raw (Join-Path $PSScriptRoot 'wave3_tax_sales_test.sql'))+"`n")
}
$query=$query.Replace('select * from finish();','select * from finish(true);')
if($query -match '(?im)^\s*commit\s*;' -or $query.TrimEnd() -notmatch 'rollback;$'){throw 'Rollback required'}
$query
