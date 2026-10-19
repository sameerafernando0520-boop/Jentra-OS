[CmdletBinding()]
param(
 [ValidateSet('procurement','inventory','receivables')][string]$Suite='procurement',
 [Parameter(Mandatory=$true)][string]$CandidatePath,
 [string]$AssertionsPath,
 [switch]$IncludeSchemaCapture
)
$ErrorActionPreference='Stop'
if($IncludeSchemaCapture -and $Suite -ne 'procurement'){throw 'The schema review capture belongs to the procurement aggregation only'}
$query=& (Join-Path $PSScriptRoot 'build_remaining_wave3_candidate.ps1') -Suite $Suite
$candidate=Get-Content -Raw -LiteralPath $CandidatePath
$assertions=if([string]::IsNullOrWhiteSpace($AssertionsPath)){''}else{Get-Content -Raw -LiteralPath $AssertionsPath}
if([string]::IsNullOrWhiteSpace($candidate) -or ($Suite -eq 'procurement' -and [string]::IsNullOrWhiteSpace($assertions))){
 throw 'Candidate source is required; procurement requires its full policy assertion fixture'
}
if($candidate -match '(?im)^\s*(begin|commit|rollback)\s*;' -or $assertions -match '(?im)^\s*(begin|commit|rollback)\s*;' -or $assertions -match 'finish\s*\('){
 throw 'Inserted sources must not open, finish or commit the enclosing rollback transaction'
}
$at=$query.IndexOf('create extension if not exists pgtap')
if($at -lt 0){throw 'Missing synthetic fixture boundary'}
$tail=$candidate+"`n"
if($IncludeSchemaCapture){
 $capture=Get-Content -Raw -LiteralPath (Join-Path $PSScriptRoot '../wave_tests/capture_wave3_schema.sql')
 $capture=$capture.TrimEnd().TrimEnd(';')
 if($capture -notmatch "'schema_version','observed-20260930-45'" -or $capture -notmatch 'as schema_evidence$'){throw 'Original metadata capture contract drift'}
 $before=$capture.Replace("'schema_version','observed-20260930-45'","'schema_version','45-before-negative-stock-tail-20261003'")
 $after=$capture.Replace("'schema_version','observed-20260930-45'","'schema_version','46-after-negative-stock-tail-20261003'")
 $tail="create temporary table wave3_negative_policy_schema_review(phase text primary key,evidence jsonb not null);`n"+
  "insert into wave3_negative_policy_schema_review select '45_before_tail',schema_evidence from (`n$before`n) captured;`n"+
  $tail+"insert into wave3_negative_policy_schema_review select '46_after_tail',schema_evidence from (`n$after`n) captured;`n"
 $aggregate="select jsonb_build_object('results',(select jsonb_agg(message) from procurement_test_results),'read_plans',(select jsonb_agg(plan) from control_read_plans)) as evidence;"
 if(($query.Split($aggregate).Count-1) -ne 1){throw 'Missing unique original procurement aggregate boundary'}
 $enhanced="select jsonb_build_object('results',(select jsonb_agg(message) from procurement_test_results),'read_plans',(select jsonb_agg(plan) from control_read_plans),'negative_stock_schema_review',(select jsonb_object_agg(phase,evidence) from wave3_negative_policy_schema_review)) as evidence;"
 $query=$query.Replace($aggregate,$enhanced)
}
$query=$query.Insert($at,$tail)
$at=$query.LastIndexOf('set constraints all immediate;')
if($at -lt 0){throw 'Missing final constraint verification boundary'}
if(![string]::IsNullOrWhiteSpace($assertions)){$query=$query.Insert($at,$assertions+"`n")}
if($query -notmatch '(?is)^\s*begin;' -or $query -notmatch 'finish\(true\)' -or $query -match '(?im)^\s*commit\s*;' -or $query.TrimEnd() -notmatch 'rollback;$'){
 throw 'Strict finish(true) and final rollback are required'
}
$query
