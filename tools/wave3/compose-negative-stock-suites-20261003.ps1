[CmdletBinding()]
param(
 [Parameter(Mandatory=$true)][ValidatePattern('^[a-f0-9]{64}$')][string]$CandidateSha256,
 [Parameter(Mandatory=$true)][ValidatePattern('^[a-f0-9]{64}$')][string]$AssertionsSha256,
 [Parameter(Mandatory=$true)][ValidatePattern('^[a-z0-9-]+$')][string]$ArtifactTag,
 [Parameter(Mandatory=$true)][string]$RefreshPath,
 [ValidatePattern('^2026100[34]$')][string]$ArtifactDate='20261003'
)
$ErrorActionPreference='Stop'
$workspace=Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
if((Get-Location).Path -ne $workspace){throw 'Run this preparation from the repository root'}
$candidate='supabase/migrations/20261003090000_wave3_negative_stock_policy.sql'
$assertions='supabase/wave_tests/wave3_negative_stock_policy_20261003_test.sql'
if((Get-FileHash -LiteralPath $candidate -Algorithm SHA256).Hash.ToLowerInvariant() -ne $CandidateSha256){throw 'Frozen candidate hash drift'}
if((Get-FileHash -LiteralPath $assertions -Algorithm SHA256).Hash.ToLowerInvariant() -ne $AssertionsSha256){throw 'Frozen assertion hash drift'}
$prefix='docs/verification/remaining-wave3/'
$outputs=foreach($suite in @('procurement','inventory','receivables')){"${prefix}database-strict-$suite-negative-stock-policy-$ArtifactTag-$ArtifactDate.sql"}
$outputs+=@("${prefix}migration-order-negative-stock-policy-$ArtifactTag-$ArtifactDate-46.json","${prefix}database-installation-package-negative-stock-policy-$ArtifactTag-$ArtifactDate-46.json")
foreach($output in $outputs){if(Test-Path -LiteralPath $output){throw "Retain existing iteration artifact: $output"}}
foreach($suite in @('procurement','inventory','receivables')){
 $compose=@{Suite=$suite;CandidatePath=$candidate}
 if($suite -eq 'procurement'){$compose.AssertionsPath=$assertions;$compose.IncludeSchemaCapture=$true}
 $query=& './supabase/tests/build_negative_stock_policy_candidate_20261003.ps1' @compose
 $output="${prefix}database-strict-$suite-negative-stock-policy-$ArtifactTag-$ArtifactDate.sql"
 [IO.File]::WriteAllText((Join-Path $workspace $output),$query,[Text.UTF8Encoding]::new($false))
 [PSCustomObject]@{suite=$suite;path=$output;sha256=(Get-FileHash -LiteralPath $output -Algorithm SHA256).Hash.ToLowerInvariant();characters=$query.Length;bytes=[Text.Encoding]::UTF8.GetByteCount($query);executed=$false}|ConvertTo-Json -Compress
}
& node './tools/wave3/prepare-negative-stock-database-package-20261003.mjs' "${prefix}database-strict-procurement-negative-stock-policy-$ArtifactTag-$ArtifactDate.sql" $RefreshPath $candidate $assertions $ArtifactTag $ArtifactDate
if($LASTEXITCODE -ne 0){throw 'Prepared query files retained; package review failed. Inspect the source/refresh mismatch.'}
