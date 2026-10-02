-- UNAPPLIED additive candidate: contract 53, metadata only, no payload exposure.
create index wave3_dead_letter_scope on core.outbox_events(tenant_id,command_id,id)
 where status='dead_letter';
create function api.wave3_observability_status(p_tenant_id uuid,p_legal_entity_id uuid,p_branch_id uuid)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare n integer;
begin
 perform core.wave3_require_scope(p_tenant_id,'core.roles.manage',p_legal_entity_id,p_branch_id);
 if p_legal_entity_id is null or p_branch_id is null then
  raise exception using errcode='22023',message='OBSERVABILITY_SCOPE_REQUIRED';end if;
 if not exists(select 1 from core.legal_entities where tenant_id=p_tenant_id and id=p_legal_entity_id and status='active')
  or not exists(select 1 from core.branches where tenant_id=p_tenant_id and legal_entity_id=p_legal_entity_id
    and id=p_branch_id and status='active') then
  raise exception using errcode='42501',message='SOURCE_UNAVAILABLE';end if;
 select count(*) into n from (
  select o.id from core.outbox_events o join core.command_receipts r
    on r.tenant_id=o.tenant_id and r.command_id=o.command_id
  where o.tenant_id=p_tenant_id and o.status='dead_letter'
    and r.legal_entity_id=p_legal_entity_id and r.branch_id=p_branch_id
    and (o.aggregate_type in ('sales_quotation','sales_order','delivery','sales_invoice','customer_receipt','sales_return',
      'purchase_requisition','request_for_quote','purchase_order','goods_receipt','supplier_bill','supplier_payment',
      'purchase_return','manual_journal','stock_count','inventory_transfer','stock_reservation','landed_value_adjustment',
      'landed_extension','stock_disposition','inventory_disposition','inventory_value_adjustment',
      'bank_reconciliation','close_control_review','control_reconciliation_report',
      'financial_statement','tax_summary','budget','fx_valuation',
      'crm_lead','crm_opportunity','crm_activity','customer_allocation','customer_allocation_reversal',
      'supplier_allocation','supplier_allocation_reversal','financial_dimension','financial_statement_report',
      'tax_summary_report','budget_variance_report','cash_flow_mapping','fiscal_period_event','fx_revaluation',
      'inventory_valuation_report','operational_report','report_export','payment_proposal','receipt_controls',
      'receipt_allowance','supplier_bill_controls','product_unit_conversion','reservation_maintenance',
      'stock_count_partition_group','wave3_notification_subscription','wave3_due_scan')
      or o.aggregate_type like 'bank\_%' escape '\')
  limit 10001
 )q;
 if n>10000 then raise exception using errcode='54000',message='LIMIT_EXCEEDED';end if;
 return jsonb_build_object('tenant_id',p_tenant_id,'legal_entity_id',p_legal_entity_id,'branch_id',p_branch_id,
   'observed_at',statement_timestamp(),'dead_letter_depth',n::text);
end $$;
revoke all on function api.wave3_observability_status(uuid,uuid,uuid) from public,anon,authenticated;
grant execute on function api.wave3_observability_status(uuid,uuid,uuid) to authenticated;
notify pgrst,'reload schema';
