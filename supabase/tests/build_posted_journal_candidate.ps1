[CmdletBinding()]
param([ValidateSet('procurement','inventory','receivables')][string]$Suite='procurement')
$ErrorActionPreference='Stop'
$query=& (Join-Path $PSScriptRoot 'build_control_read_plan_candidate.ps1') -Suite $Suite
$at=$query.IndexOf('create extension if not exists pgtap')
if($at -lt 0){throw 'Missing synthetic fixture boundary'}
$query=$query.Insert($at,(Get-Content -Raw (Join-Path $PSScriptRoot '../migrations/20260928001000_wave3_posted_journal_evidence.sql'))+"`n")
if($Suite -eq 'procurement'){
 $at=$query.LastIndexOf('set constraints all immediate;')
 $query=$query.Insert($at,(Get-Content -Raw (Join-Path $PSScriptRoot '../wave_tests/wave3_posted_journal_test.sql'))+"`n")
}
if($query -notmatch 'finish\(true\)' -or $query -match '(?im)^\s*commit\s*;' -or $query.TrimEnd() -notmatch 'rollback;$'){
 throw 'Strict rollback required'
}
$query
