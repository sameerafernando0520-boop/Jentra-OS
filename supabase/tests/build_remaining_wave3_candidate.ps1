[CmdletBinding()]
param([ValidateSet('procurement','inventory','receivables')][string]$Suite='procurement')
$ErrorActionPreference='Stop'
$query=& (Join-Path $PSScriptRoot 'build_posted_journal_candidate.ps1') -Suite $Suite
$names=@('20260927200629_wave3_operational_evidence.sql','20260927200703_wave3_historical_controls.sql','20260927200706_wave3_inventory_extensions.sql','20260929001000_wave3_notifications.sql','20260930001000_wave3_landed_extensions.sql','20260930002000_wave3_count_partitions.sql','20260930003000_wave3_stock_disposition.sql','20260930004000_wave3_dashboard_metrics.sql','20260930005000_wave3_observability.sql')
$at=$query.IndexOf('create extension if not exists pgtap')
if($at -lt 0){throw 'Missing synthetic fixture boundary'}
$bodies=foreach($name in $names){Get-Content -Raw (Join-Path $PSScriptRoot "../migrations/$name")}
$query=$query.Insert($at,[string]::Join("`n",$bodies)+"`n")
if($Suite -eq 'procurement'){
 $at=$query.LastIndexOf('set constraints all immediate;')
 foreach($name in @('wave3_operational_evidence_test.sql','wave3_notification_test.sql','wave3_dashboard_metrics_test.sql','wave3_landed_extensions_test.sql','wave3_stock_disposition_test.sql','wave3_observability_test.sql')){
  $at=$query.LastIndexOf('set constraints all immediate;')
  $tests=Join-Path $PSScriptRoot $name
  if(Test-Path -LiteralPath $tests){$query=$query.Insert($at,(Get-Content -Raw -LiteralPath $tests)+"`n")}
 }
} elseif($Suite -eq 'inventory') {
 $at=$query.LastIndexOf('set constraints all immediate;')
 $query=$query.Insert($at,(Get-Content -Raw (Join-Path $PSScriptRoot 'wave3_count_partitions_test.sql'))+"`n")
} elseif($Suite -eq 'receivables') {
 $at=$query.LastIndexOf('set constraints all immediate;')
 $tests=Join-Path $PSScriptRoot 'wave3_historical_controls_receivables_test.sql'
 $query=$query.Insert($at,(Get-Content -Raw -LiteralPath $tests)+"`n")
 $at=$query.LastIndexOf('set constraints all immediate;')
 $tests=Join-Path $PSScriptRoot 'wave3_reservation_maintenance_test.sql'
 $query=$query.Insert($at,(Get-Content -Raw -LiteralPath $tests)+"`n")
}
if($query -notmatch 'finish\(true\)' -or $query -match '(?im)^\s*commit\s*;' -or $query.TrimEnd() -notmatch 'rollback;$'){
 throw 'Strict rollback required'
}
$query
