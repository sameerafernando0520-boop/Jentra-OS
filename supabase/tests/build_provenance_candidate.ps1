[CmdletBinding()]
param([ValidateSet('procurement','inventory','receivables')][string]$Suite='procurement')
$ErrorActionPreference = 'Stop'
$procurement = & (Join-Path $PSScriptRoot 'build_procurement_candidate.ps1')
$offset = $procurement.IndexOf('create extension if not exists pgtap')
if ($offset -lt 0) { throw 'Missing fixture boundary.' }
$query = $procurement.Substring(0,$offset)
foreach ($name in @('20260916001000_inventory_transfers.sql','20260916002000_inventory_stock_counts.sql','20260918001000_inventory_reservation_release.sql','20260919181407_inventory_receipt_provenance.sql')) {
 $query += "`n" + (Get-Content -Raw -LiteralPath (Join-Path $PSScriptRoot "../migrations/$name"))
}
if ($Suite -eq 'procurement') {
 $fixture = $procurement.Substring($offset)
 $marker = "select pg_temp.actor('outsider');"
 $at = $fixture.LastIndexOf($marker)
 if ($at -lt 0) { throw 'Missing final security boundary.' }
 $fixture = $fixture.Insert($at,(Get-Content -Raw -LiteralPath (Join-Path $PSScriptRoot 'wave3_receipt_provenance_test.sql')) + "`n")
} elseif ($Suite -eq 'inventory') {
 $inventory = & (Join-Path $PSScriptRoot 'build_inventory_candidate.ps1')
 $fixture = $inventory.Substring($inventory.IndexOf('create extension if not exists pgtap'))
} else {
 $reservations = & (Join-Path $PSScriptRoot 'build_reservation_candidate.ps1')
 $fixture = $reservations.Substring($reservations.IndexOf('create extension if not exists pgtap'))
}
$query += "`n" + $fixture
if ($query -match '(?im)^\s*commit\s*;' -or $query.TrimEnd() -notmatch 'rollback;$') { throw 'Rollback required.' }
$query
