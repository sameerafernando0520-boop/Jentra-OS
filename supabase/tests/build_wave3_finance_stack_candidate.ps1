[CmdletBinding()]
param([ValidateSet('procurement','inventory','receivables')][string]$Suite='procurement')
$ErrorActionPreference='Stop'
# Final-stack regression: apply every candidate before any synthetic fixture.
# The per-feature builders retain their historical phased verification behavior.
$query=& (Join-Path $PSScriptRoot 'build_financial_dimensions_candidate.ps1') -Suite $Suite
# Avoid compilation noise in the large synthetic fixture transaction. This is
# test execution configuration, not evidence of default-runtime performance.
if(-not $query.StartsWith('begin;')){throw 'Missing opening transaction'}
$query=$query.Insert(6,"`nset local jit=off;")
$names=@(
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
 '20260916001000_inventory_transfers.sql'
 '20260916002000_inventory_stock_counts.sql'
 '20260918001000_inventory_reservation_release.sql'
 '20260919181407_inventory_receipt_provenance.sql'
 '20260919185538_inventory_landed_value.sql'
 '20260920202547_inventory_valuation_reports.sql'
 '20260921041348_manual_journals.sql'
 '20260922001000_ar_ap_control_reconciliation.sql'
 '20260923225202_bank_reconciliation.sql'
 '20260924185321_wave3_period_governance.sql'
 '20260925002000_wave3_financial_statements.sql'
 '20260925003000_wave3_cash_flow.sql'
 '20260925004000_wave3_budgets.sql'
 '20260926001000_wave3_tax_summary.sql'
 '20260926002000_wave3_tax_summary_hardening.sql'
 '20260926003000_wave3_tax_control_reconciliation.sql'
 '20260926005000_wave3_governed_journal_tax.sql'
 '20260926006000_wave3_tax_control_movements.sql'
 '20260926007000_wave3_grni_control_reconciliation.sql'
 '20260926008000_wave3_close_control_review.sql'
 '20260926009000_wave3_governed_report_exports.sql'
 '20260926010000_wave3_financial_dimensions.sql'
)
$bodies=foreach($name in $names){
 $body=Get-Content -Raw -LiteralPath (Join-Path $PSScriptRoot "../migrations/$name")
 $at=$query.IndexOf($body,[StringComparison]::Ordinal)
 if($at -lt 0){throw "Missing candidate body: $name"}
 $query=$query.Remove($at,$body.Length)
 if($query.IndexOf($body,[StringComparison]::Ordinal) -ge 0){throw "Duplicate candidate body: $name"}
 $body
}
$fixture=$query.IndexOf('create extension if not exists pgtap')
if($fixture -lt 0){throw 'Missing initial synthetic fixture boundary'}
# Earlier posting-only fixtures seed period state with privileged SQL. Seed
# immutable events as well, so the final governance guard stays enabled. This
# helper is synthetic setup, never hard-close/independent-approval evidence.
$seed=@'
create function pg_temp.fixture_period_state(i uuid,wanted text) returns void language plpgsql set search_path='' as $$
declare p finance.fiscal_periods%rowtype;next_state text;begin
 loop
  select * into strict p from finance.fiscal_periods where id=i for update;
  if p.state=wanted then return;end if;
  next_state:=case when wanted='open' and p.state='soft_locked' then 'hard_locked' else wanted end;
  insert into finance.period_events(id,tenant_id,legal_entity_id,period_id,action,from_state,to_state,period_version,
   reason,actor_id,transaction_id)
  values(gen_random_uuid(),p.tenant_id,p.legal_entity_id,p.id,
   case next_state when 'soft_locked' then 'soft_lock' when 'hard_locked' then 'hard_lock' else 'reopened' end,
   p.state,next_state,p.version,'Synthetic posting-only fixture state; not close acceptance',auth.uid(),txid_current());
  update finance.fiscal_periods set state=next_state where id=i;
 end loop;
end$$;
'@
$tail=$query.Substring($fixture)
if($Suite -eq 'procurement'){
 # Earlier procurement fixtures represent pre-versioning posted bills. Only
 # the new tax provenance trigger is absent during that historical seed phase;
 # journal, source immutability, dimension and authorization guards stay active.
 # Prospective tax/GRNI/dimension tests run with the trigger enabled.
 $tail="alter table procurement.supplier_bill_lines disable trigger bill_tax_snapshot;`n"+$tail
 $tail=$tail.Replace('-- Legacy tax lines are deliberately not silently certified. All fixtures roll back.',
  "alter table procurement.supplier_bill_lines enable trigger bill_tax_snapshot;`n-- Legacy tax lines are deliberately not silently certified. All fixtures roll back.")
 # Cash flow is now supported. Preserve the invalid-kind invariant with an
 # actually unsupported kind rather than the historical unsupported example.
 $tail=$tail.Replace("pg_temp.report_call('report.invalid','cash_flow')","pg_temp.report_call('report.invalid','unsupported')")
 $tail=$tail.Replace("and action='hard_lock'),1::bigint,'reopen retains prior hard close event'",
  "and action='hard_lock' and reason<>'Synthetic posting-only fixture state; not close acceptance'),1::bigint,'reopen retains prior hard close event'")
 $clean=@'
insert into finance.accounts(id,tenant_id,legal_entity_id,code,name,account_type,normal_balance,created_by,updated_by)
values(pg_temp.fid('clean.grni'),pg_temp.fid('tenant'),pg_temp.fid('clean.entity'),'GRNI','Synthetic GRNI control','liability','credit',pg_temp.fid('creator'),pg_temp.fid('creator'));
insert into procurement.receipt_controls(tenant_id,legal_entity_id,grni_account_id,expense_account_id,updated_by)
values(pg_temp.fid('tenant'),pg_temp.fid('clean.entity'),pg_temp.fid('clean.grni'),pg_temp.fid('clean.variance'),pg_temp.fid('creator'));
'@
 $tail=$tail.Replace("select pg_temp.clean_close_call('soft_lock','clean.soft');",$clean+"`nselect pg_temp.clean_close_call('soft_lock','clean.soft');")
}
foreach($state in @('soft_locked','hard_locked','open')){
 $tail=$tail.Replace("update finance.fiscal_periods set state='$state' where tenant_id=pg_temp.fid('tenant') and legal_entity_id=pg_temp.fid('entity') and '2026-09-20' between start_date and end_date;",
  "select pg_temp.fixture_period_state(id,'$state') from finance.fiscal_periods where tenant_id=pg_temp.fid('tenant') and legal_entity_id=pg_temp.fid('entity') and '2026-09-20' between start_date and end_date;")
 $tail=$tail.Replace("update finance.fiscal_periods set state='$state' where id=pg_temp.fid('period');",
  "perform pg_temp.fixture_period_state(pg_temp.fid('period'),'$state');")
 # Ordinary fixture statements use SELECT; only the correction probe is PL/pgSQL.
 $tail=$tail.Replace("`nperform pg_temp.fixture_period_state(pg_temp.fid('period'),'$state');",
  "`nselect pg_temp.fixture_period_state(pg_temp.fid('period'),'$state');")
}
$query=$query.Substring(0,$fixture)+[string]::Join("`n",$bodies)+"`n"+$seed+"`n"+$tail
if($Suite -eq 'receivables'){
 # Supabase returns the last result set. Preserve every TAP assertion, including
 # checks made while SET ROLE authenticated is active, for reviewable evidence.
 $query=$query.Insert(6,"`ncreate temp table final_stack_results(message text);`ngrant insert on final_stack_results to authenticated;`n")
 $query=[regex]::Replace($query,'(?im)^select (?=(?:is|ok|throws_ok|lives_ok|has_table|has_function|cmp_ok)\s*\()',
  'insert into final_stack_results select ')
 $query=$query.Replace('select * from finish(true);','insert into final_stack_results select * from finish(true);')
 $at=$query.LastIndexOf('rollback;')
 $query=$query.Insert($at,"select jsonb_agg(message) as results from final_stack_results;`n")
}
if($query -notmatch 'finish\(true\)' -or $query -match '(?im)^\s*commit\s*;' -or $query.TrimEnd() -notmatch 'rollback;$'){
 throw 'Strict rollback required'
}
$query
