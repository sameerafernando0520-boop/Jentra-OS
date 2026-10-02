[CmdletBinding()]
param()
$ErrorActionPreference='Stop'
$serviceRoot=Split-Path $PSScriptRoot -Parent
$serviceBase=& (Join-Path $PSScriptRoot 'build_payroll_corrections_candidate.ps1')
$serviceCut=$serviceBase.LastIndexOf('do $$declare failed text;begin')
if($serviceCut -lt 0){throw 'Correction diagnostic boundary changed.'}
$serviceBase=$serviceBase.Substring(0,$serviceCut)
$serviceDdl=@()
foreach($serviceName in @('20261001080000_wave4_projects_time.sql','20261001100000_wave4_project_expenses_billing.sql','20261001090000_wave4_service.sql')){
 $serviceDdl+=Get-Content -LiteralPath (Join-Path $serviceRoot "migrations/$serviceName") -Raw
}
$serviceTests=Get-Content -LiteralPath (Join-Path $PSScriptRoot 'wave4_service_payroll_impacts_test.sql') -Raw
$serviceTests+=[Environment]::NewLine+(Get-Content -LiteralPath (Join-Path $PSScriptRoot 'wave4_service_billing_impacts_test.sql') -Raw)
$serviceTests=[regex]::Replace($serviceTests,'(?m)^select (is|ok|throws_ok|lives_ok)\(','insert into payroll_assertions select $1(')
$serviceDiagnostic=@'
do $$declare failed text;begin
 select string_agg(message,chr(10)) into failed from payroll_assertions where message like 'not ok%';
 if failed is not null then raise exception using errcode='P0001',message=failed;end if;
end $$;
'@
$serviceQuery=(@($serviceBase)+$serviceDdl+@($serviceTests,$serviceDiagnostic,'set constraints all immediate;',
 'select * from finish(true);','select count(*) assertions from payroll_assertions;','rollback;')) -join [Environment]::NewLine
$serviceQuery=$serviceQuery.Replace("(now() at time zone 'Asia/Colombo')::date","((now()-interval '1 day') at time zone 'Asia/Colombo')::date")
if($serviceQuery -match '(?im)^\s*commit\s*;' -or -not $serviceQuery.TrimEnd().EndsWith('rollback;')){throw 'Service impacts must roll back.'}
$serviceQuery
