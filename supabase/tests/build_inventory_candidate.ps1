[CmdletBinding()]
param()
$ErrorActionPreference = 'Stop'
# No database connection and no installation. The entire output rolls back.
$bodies = @(
  '20260912152000_product_unit_conversions.sql'
  '20260916001000_inventory_transfers.sql'
  '20260916002000_inventory_stock_counts.sql'
) | ForEach-Object { Get-Content -Raw -LiteralPath (Join-Path $PSScriptRoot "../migrations/$_") }
$fixture = Get-Content -Raw -LiteralPath (Join-Path $PSScriptRoot '../wave_tests/wave3_inventory_transfers_test.sql')
$countTests = Get-Content -Raw -LiteralPath (Join-Path $PSScriptRoot '../wave_tests/wave3_stock_counts_test.sql')
$countTests += "`n" + (Get-Content -Raw -LiteralPath (Join-Path $PSScriptRoot '../wave_tests/wave3_tracked_counts_test.sql'))
$fixture = $fixture.Replace("select pg_temp.actor('actor','aal1');", "$countTests`nselect pg_temp.actor('actor','aal1');")
$query = "begin;`nset local lock_timeout='2s';`nset local statement_timeout='30s';`n" + [string]::Join("`n", $bodies) + "`n" + $fixture
if ($query -match '(?im)^\s*commit\s*;' -or $query.TrimEnd() -notmatch 'rollback;$') { throw 'Rollback boundary required.' }
$query
