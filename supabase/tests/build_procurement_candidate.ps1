[CmdletBinding()]
param()
$ErrorActionPreference = 'Stop'
# Emits a single rollback-only transaction. It does not connect to any database.
$migrationNames = @(
  '20260912152000_product_unit_conversions.sql'
  '20260912153000_procurement_requisition_drafts.sql'
  '20260913001000_procurement_requisition_workflow.sql'
  '20260913002000_procurement_reference_options.sql'
  '20260913003000_procurement_sourcing.sql'
  '20260913004000_procurement_purchase_orders.sql'
  '20260913005000_procurement_order_workflow.sql'
  '20260913006000_procurement_goods_receipts.sql'
  '20260913007000_procurement_supplier_bills.sql'
  '20260914001000_procurement_supplier_settlement.sql'
  '20260915001000_payable_allocation_corrections.sql'
  '20260915002000_procurement_purchase_returns.sql'
)
$migrationBodies = foreach ($migrationName in $migrationNames) {
  Get-Content -Raw -LiteralPath (Join-Path $PSScriptRoot "../migrations/$migrationName")
}
$fixture = Get-Content -Raw -LiteralPath (Join-Path $PSScriptRoot 'wave3_procurement_test.sql')
$beginOffset = $fixture.IndexOf('begin;')
if ($beginOffset -lt 0) { throw 'Missing fixture transaction boundary.' }
$fixture = $fixture.Remove($beginOffset, 6)
$extraTests = [string]::Join("`n", @(
  (Get-Content -Raw -LiteralPath (Join-Path $PSScriptRoot 'wave3_purchase_orders_test.sql'))
  (Get-Content -Raw -LiteralPath (Join-Path $PSScriptRoot 'wave3_product_units_test.sql'))
  (Get-Content -Raw -LiteralPath (Join-Path $PSScriptRoot 'wave3_goods_receipts_test.sql'))
  (Get-Content -Raw -LiteralPath (Join-Path $PSScriptRoot 'wave3_supplier_bills_test.sql'))
  (Get-Content -Raw -LiteralPath (Join-Path $PSScriptRoot 'wave3_supplier_settlement_test.sql'))
  (Get-Content -Raw -LiteralPath (Join-Path $PSScriptRoot 'wave3_purchase_returns_test.sql'))
))
$marker = "select pg_temp.actor('outsider');"
$insertOffset = $fixture.IndexOf($marker)
if ($insertOffset -lt 0) { throw 'Missing final security test boundary.' }
$fixture = $fixture.Insert($insertOffset, "$extraTests`n")
$query = "begin;`nset local lock_timeout='2s';`nset local statement_timeout='30s';`n" +
  [string]::Join("`n", $migrationBodies) + "`n" + $fixture
if ($query -match '(?im)^\s*commit\s*;' -or $query.TrimEnd() -notmatch 'rollback;$') {
  throw 'Candidate verification must end in rollback and never commit.'
}
$query
