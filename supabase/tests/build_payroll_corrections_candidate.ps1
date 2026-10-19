[CmdletBinding()]
param([switch]$InstalledPrerequisites,[switch]$Installed,[switch]$ClientSamples)
$ErrorActionPreference='Stop'
$taskRoot=Split-Path $PSScriptRoot -Parent
if($Installed){throw 'Installed corrections requires a dedicated installed fixture; this builder is candidate-only.'}
$taskQuery=& (Join-Path $PSScriptRoot 'build_payroll_candidate.ps1') -InstalledPrerequisites:$InstalledPrerequisites
$taskCut=$taskQuery.LastIndexOf('do $$declare failed text;begin')
if($taskCut -lt 0){throw 'Payroll candidate diagnostic boundary changed.'}
$taskBase=$taskQuery.Substring(0,$taskCut)
$taskCandidate=Get-Content -LiteralPath (Join-Path $taskRoot 'migrations/20261001110000_wave4_payroll_corrections.sql') -Raw
$taskTests=Get-Content -LiteralPath (Join-Path $PSScriptRoot '../wave_tests/wave4_payroll_corrections_test.sql') -Raw
$taskTests=[regex]::Replace($taskTests,'(?m)^select (is|ok|throws_ok)\(','insert into payroll_assertions select $1(')
$taskDiagnostic=@'
do $$declare failed text;begin
 select string_agg(message,chr(10)) into failed from payroll_assertions where message like 'not ok%';
 if failed is not null then raise exception using errcode='P0001',message=failed;end if;
end $$;
'@
$taskSamples=@'
select jsonb_object_agg(name,response) as samples from correction_client_samples;
'@
$taskQuery=@($taskBase,$taskCandidate,$taskTests,$taskDiagnostic,'set constraints all immediate;','select * from finish(true);')
if($ClientSamples){$taskQuery+=$taskSamples}
$taskQuery=($taskQuery+@('rollback;')) -join [Environment]::NewLine
if($taskQuery -match '(?im)^\s*commit\s*;' -or -not $taskQuery.TrimEnd().EndsWith('rollback;')){throw 'Corrections must end in rollback.'}
$taskQuery
