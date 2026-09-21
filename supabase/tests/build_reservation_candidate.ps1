[CmdletBinding()]
param()
$ErrorActionPreference = 'Stop'
# Emits only. All synthetic records and candidate DDL roll back together.
$procurement = & (Join-Path $PSScriptRoot 'build_procurement_candidate.ps1')
$fixtureOffset = $procurement.IndexOf('create extension if not exists pgtap')
if ($fixtureOffset -lt 0) { throw 'Missing procurement fixture boundary.' }
$query = $procurement.Substring(0, $fixtureOffset)
foreach ($name in @('20260916001000_inventory_transfers.sql', '20260916002000_inventory_stock_counts.sql', '20260918001000_inventory_reservation_release.sql')) {
  $query += "`n" + (Get-Content -Raw -LiteralPath (Join-Path $PSScriptRoot "../migrations/$name"))
}
$fixture = Get-Content -Raw -LiteralPath (Join-Path $PSScriptRoot 'wave3_delivery_receivables_test.sql')
$fixture = $fixture.Remove($fixture.IndexOf('begin;'), 6)
$extra = Get-Content -Raw -LiteralPath (Join-Path $PSScriptRoot 'wave3_reservation_release_test.sql')
$fixture = $fixture.Replace('set constraints all immediate;', "$extra`nset constraints all immediate;")
$query += "`n" + $fixture
if ($query -match '(?im)^\s*commit\s*;' -or $query.TrimEnd() -notmatch 'rollback;$') { throw 'Rollback boundary required.' }
$query
