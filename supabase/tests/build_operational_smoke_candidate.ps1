[CmdletBinding()]
param()
$ErrorActionPreference='Stop'
$query=& (Join-Path $PSScriptRoot 'build_posted_journal_candidate.ps1') -Suite procurement
$at=$query.IndexOf('create extension if not exists pgtap')
if($at -lt 0){throw 'Missing fixture boundary'}
$query=$query.Substring(0,$at)
$names=@('20260927200629_wave3_operational_evidence.sql','20260927200703_wave3_historical_controls.sql','20260927200706_wave3_inventory_extensions.sql')
foreach($name in $names){$query+=(Get-Content -Raw (Join-Path $PSScriptRoot "../migrations/$name"))+"`n"}
$tests=(Get-Content -Raw (Join-Path $PSScriptRoot 'wave3_operational_evidence_test.sql')).Split('-- Fixture-only behavior assertions')[0]
$tests=$tests.Replace('insert into procurement_test_results select','select')
$query+="create extension if not exists pgtap;`nselect plan(15);`n"+$tests+"`nselect * from finish(true);`nrollback;"
if($query -match '(?im)^\s*commit\s*;' -or $query.TrimEnd() -notmatch 'rollback;$'){throw 'Strict rollback required'}
$query
