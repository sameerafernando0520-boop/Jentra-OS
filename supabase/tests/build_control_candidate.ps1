[CmdletBinding()]
param([ValidateSet('procurement','inventory','receivables')][string]$Suite='procurement')
$ErrorActionPreference='Stop'
$query=& (Join-Path $PSScriptRoot 'build_journal_candidate.ps1') -Suite $Suite
$at=$query.IndexOf('create extension if not exists pgtap')
if($at -lt 0){throw 'Missing fixture boundary'}
$query=$query.Insert($at,(Get-Content -Raw (Join-Path $PSScriptRoot '../migrations/20260922001000_ar_ap_control_reconciliation.sql'))+"`n")
$test=Join-Path $PSScriptRoot "wave3_control_${Suite}_test.sql"
if(Test-Path $test){
 if($Suite -eq 'procurement'){$at=$query.LastIndexOf("select pg_temp.actor('outsider');")}
 else {$at=$query.LastIndexOf('set constraints all immediate;')}
 $query=$query.Insert($at,(Get-Content -Raw $test)+"`n")
}
if($query -match '(?im)^\s*commit\s*;' -or $query.TrimEnd() -notmatch 'rollback;$'){throw 'Rollback required'}
$query
