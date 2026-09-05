-- Cover every Wave 3 lead-to-cash foreign-key path reported by the Supabase
-- performance advisor. Existing operational indexes remain unchanged.

create index stock_balances_tenant_branch_fk_idx
  on inventory.stock_balances (tenant_id, branch_id);
create index stock_balances_product_fk_idx
  on inventory.stock_balances (tenant_id, legal_entity_id, product_id);
create index stock_balances_warehouse_fk_idx
  on inventory.stock_balances (tenant_id, warehouse_id);

create index stock_reservations_entity_fk_idx
  on inventory.stock_reservations (tenant_id, legal_entity_id);
create index stock_reservations_product_fk_idx
  on inventory.stock_reservations (tenant_id, legal_entity_id, product_id);
create index stock_reservations_order_fk_idx
  on inventory.stock_reservations (tenant_id, legal_entity_id, sales_order_id);
create index stock_reservations_order_line_fk_idx
  on inventory.stock_reservations (
    tenant_id, sales_order_id, sales_order_line_id
  );

create index credit_decisions_currency_fk_idx
  on sales.credit_decisions (currency_code);
create index credit_decisions_entity_fk_idx
  on sales.credit_decisions (tenant_id, legal_entity_id);
create index credit_decisions_entity_order_fk_idx
  on sales.credit_decisions (tenant_id, legal_entity_id, sales_order_id);

create index credit_exposures_currency_fk_idx
  on sales.customer_credit_exposures (currency_code);
create index credit_exposures_branch_fk_idx
  on sales.customer_credit_exposures (tenant_id, branch_id);
create index credit_exposures_customer_fk_idx
  on sales.customer_credit_exposures (tenant_id, customer_id);

create index quotation_lines_currency_fk_idx
  on sales.quotation_lines (currency_code);
create index quotation_lines_entity_document_fk_idx
  on sales.quotation_lines (tenant_id, legal_entity_id, quotation_id);
create index quotation_revisions_entity_fk_idx
  on sales.quotation_revisions (tenant_id, legal_entity_id);
create index quotation_revisions_entity_document_fk_idx
  on sales.quotation_revisions (tenant_id, legal_entity_id, quotation_id);
create index quotations_base_currency_fk_idx
  on sales.quotations (base_currency_code);
create index quotations_currency_fk_idx
  on sales.quotations (currency_code);
create index quotations_branch_fk_idx
  on sales.quotations (tenant_id, branch_id);

create index sales_order_lines_currency_fk_idx
  on sales.sales_order_lines (currency_code);
create index sales_order_lines_branch_fk_idx
  on sales.sales_order_lines (tenant_id, branch_id);
create index sales_order_lines_entity_document_fk_idx
  on sales.sales_order_lines (tenant_id, legal_entity_id, sales_order_id);
create index sales_orders_base_currency_fk_idx
  on sales.sales_orders (base_currency_code);
create index sales_orders_currency_fk_idx
  on sales.sales_orders (currency_code);
create index sales_orders_customer_fk_idx
  on sales.sales_orders (tenant_id, customer_id);
create index sales_orders_source_quote_fk_idx
  on sales.sales_orders (tenant_id, legal_entity_id, source_quotation_id);
