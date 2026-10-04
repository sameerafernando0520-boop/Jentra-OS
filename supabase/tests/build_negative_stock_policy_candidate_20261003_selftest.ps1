$ErrorActionPreference='Stop'
$workspace=Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$output=Join-Path $workspace 'build/remaining-wave3/negative-stock-builder-offline-selftest'
[void](New-Item -ItemType Directory -Path $output -Force)
$candidate=Join-Path $output 'candidate.sql'
$assertions=Join-Path $output 'assertions.sql'
$bad=Join-Path $output 'bad.sql'
$candidateText="-- wrapper-only offline composition sentinel`nselect 46 as offline_composition_only;`n"
$assertionText="-- wrapper-only offline assertion sentinel`nselect ok(true,'offline wrapper composition sentinel');`n"
[IO.File]::WriteAllText($candidate,$candidateText,[Text.UTF8Encoding]::new($false))
[IO.File]::WriteAllText($assertions,$assertionText,[Text.UTF8Encoding]::new($false))
$builder=Join-Path $PSScriptRoot 'build_negative_stock_policy_candidate_20261003.ps1'
$original=Join-Path $PSScriptRoot 'build_remaining_wave3_candidate.ps1'
$originalHash=(Get-FileHash -LiteralPath $original -Algorithm SHA256).Hash
$checks=0
foreach($suite in @('procurement','inventory','receivables')){
 $before=& $original -Suite $suite
 $query=& $builder -Suite $suite -CandidatePath $candidate -AssertionsPath $assertions
 if($query.Replace($candidateText+"`n",'').Replace($assertionText+"`n",'') -cne $before){throw "Historical composition changed in $suite"};$checks++
 if($query.IndexOf($candidateText) -ge $query.IndexOf('create extension if not exists pgtap')){throw 'Tail not before pgTAP'};$checks++
 if($query.IndexOf($assertionText) -ge $query.LastIndexOf('set constraints all immediate;')){throw 'Assertions not before final constraints'};$checks++
 if($query -notmatch 'finish\(true\)' -or $query.TrimEnd() -notmatch 'rollback;$' -or $query -match '(?im)^\s*commit\s*;'){throw 'Strict transaction guard failed'};$checks++
}
foreach($badText in @('commit;','begin;','rollback;','')){
 [IO.File]::WriteAllText($bad,$badText,[Text.UTF8Encoding]::new($false))
 $failed=$false
 try{[void](& $builder -CandidatePath $bad -AssertionsPath $assertions)}catch{$failed=$true}
 if(!$failed){throw 'Bad candidate unexpectedly accepted'};$checks++
}
foreach($suite in @('inventory','receivables')){
 $before=& $original -Suite $suite
 $query=& $builder -Suite $suite -CandidatePath $candidate
 if($query.Replace($candidateText+"`n",'') -cne $before){throw 'Tail-only regression composition changed historical assertions'};$checks++
}
$failed=$false
try{[void](& $builder -CandidatePath $candidate)}catch{$failed=$true}
if(!$failed){throw 'Procurement policy fixture unexpectedly omitted'};$checks++
$captureQuery=& $builder -Suite procurement -CandidatePath $candidate -AssertionsPath $assertions -IncludeSchemaCapture
if($captureQuery.IndexOf("select '45_before_tail'") -ge $captureQuery.IndexOf($candidateText) -or $captureQuery.IndexOf("select '46_after_tail'") -le $captureQuery.IndexOf($candidateText)){throw 'Metadata review phase order invalid'};$checks++
if($captureQuery.IndexOf("select '46_after_tail'") -ge $captureQuery.IndexOf('create extension if not exists pgtap')){throw 'Metadata review is not before synthetic fixtures'};$checks++
if($captureQuery -notmatch "'negative_stock_schema_review',\(select jsonb_object_agg\(phase,evidence\) from wave3_negative_policy_schema_review\)" -or ($captureQuery.Split($candidateText).Count-1) -ne 1){throw 'Metadata aggregation or exact tail differs'};$checks++
if($captureQuery -notmatch 'finish\(true\)' -or $captureQuery.TrimEnd() -notmatch 'rollback;$' -or $captureQuery -match '(?im)^\s*commit\s*;'){throw 'Metadata review lost strict transaction guard'};$checks++
$failed=$false
try{[void](& $builder -Suite inventory -CandidatePath $candidate -IncludeSchemaCapture)}catch{$failed=$true}
if(!$failed){throw 'Metadata procurement aggregate allowed for another suite'};$checks++
[IO.File]::WriteAllText($bad,'select * from finish(true);',[Text.UTF8Encoding]::new($false))
$failed=$false
try{[void](& $builder -CandidatePath $candidate -AssertionsPath $bad)}catch{$failed=$true}
if(!$failed){throw 'Premature assertion finish unexpectedly accepted'};$checks++
if((Get-FileHash -LiteralPath $original -Algorithm SHA256).Hash -cne $originalHash){throw 'Historical builder was modified'};$checks++
$evidence=[ordered]@{observed_at=[DateTime]::UtcNow.ToString('o');checks=$checks;passed=$checks;sql_executions=0;historical_builder_sha256=$originalHash.ToLowerInvariant();boundary='Offline composition/guard checks only; sentinel SQL was not executed. Historical builder preserved. No new policy/database/native/load acceptance is inferred.'}
$evidencePath=Join-Path $workspace 'docs/verification/remaining-wave3/negative-stock-builder-offline-selftest-20261003.json'
[IO.File]::WriteAllText($evidencePath,($evidence|ConvertTo-Json -Depth 6)+"`n",[Text.UTF8Encoding]::new($false))
$evidence|ConvertTo-Json -Compress
