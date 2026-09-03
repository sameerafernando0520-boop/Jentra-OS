-- Cover every Wave 2 foreign-key enforcement path. Tenant-scoped list indexes
-- remain tenant-leading; actor/currency reference indexes lead with the actual
-- FK column so parent updates/deletes are bounded as well.

create index attachments_created_by_idx on core.attachments (created_by, tenant_id);
create index attachments_updated_by_idx on core.attachments (updated_by, tenant_id);

create index document_sequences_created_by_idx
  on core.document_sequences (created_by, tenant_id);
create index document_sequences_tenant_branch_idx
  on core.document_sequences (tenant_id, branch_id);
create index document_sequences_updated_by_idx
  on core.document_sequences (updated_by, tenant_id);

create index export_jobs_actor_idx on core.export_jobs (actor_id, tenant_id);
create index import_jobs_actor_idx on core.import_jobs (actor_id, tenant_id);
create index import_jobs_tenant_entity_idx
  on core.import_jobs (tenant_id, legal_entity_id);

create index report_definitions_created_by_idx
  on core.report_definitions (created_by, tenant_id);
create index report_definitions_owner_idx
  on core.report_definitions (owner_id, tenant_id);
create index report_definitions_updated_by_idx
  on core.report_definitions (updated_by, tenant_id);

create index contacts_created_by_idx on crm.contacts (created_by, tenant_id);
create index contacts_updated_by_idx on crm.contacts (updated_by, tenant_id);
create index parties_created_by_idx on crm.parties (created_by, tenant_id);
create index parties_credit_currency_idx
  on crm.parties (credit_currency_code, tenant_id);
create index parties_updated_by_idx on crm.parties (updated_by, tenant_id);

create index accounts_created_by_idx
  on finance.accounts (created_by, tenant_id, legal_entity_id);
create index accounts_currency_idx
  on finance.accounts (currency_code, tenant_id, legal_entity_id);
create index accounts_updated_by_idx
  on finance.accounts (updated_by, tenant_id, legal_entity_id);

create index exchange_rates_created_by_idx
  on finance.exchange_rates (created_by, tenant_id, legal_entity_id);
create index exchange_rates_source_currency_idx
  on finance.exchange_rates (source_currency_code, tenant_id, legal_entity_id);
create index exchange_rates_target_currency_idx
  on finance.exchange_rates (target_currency_code, tenant_id, legal_entity_id);
create index exchange_rates_updated_by_idx
  on finance.exchange_rates (updated_by, tenant_id, legal_entity_id);

create index fiscal_periods_created_by_idx
  on finance.fiscal_periods (created_by, tenant_id, legal_entity_id);
create index fiscal_periods_updated_by_idx
  on finance.fiscal_periods (updated_by, tenant_id, legal_entity_id);
create index tax_definitions_created_by_idx
  on finance.tax_definitions (created_by, tenant_id, legal_entity_id);
create index tax_definitions_updated_by_idx
  on finance.tax_definitions (updated_by, tenant_id, legal_entity_id);

create index products_created_by_idx
  on inventory.products (created_by, tenant_id, legal_entity_id);
create index products_tenant_unit_idx
  on inventory.products (tenant_id, base_unit_id);
create index products_tenant_entity_cogs_idx
  on inventory.products (tenant_id, legal_entity_id, cogs_account_id);
create index products_tenant_entity_expense_idx
  on inventory.products (tenant_id, legal_entity_id, expense_account_id);
create index products_tenant_entity_inventory_idx
  on inventory.products (tenant_id, legal_entity_id, inventory_account_id);
create index products_tenant_entity_revenue_idx
  on inventory.products (tenant_id, legal_entity_id, revenue_account_id);
create index products_tenant_entity_tax_idx
  on inventory.products (tenant_id, legal_entity_id, tax_definition_id);
create index products_updated_by_idx
  on inventory.products (updated_by, tenant_id, legal_entity_id);
create index units_created_by_idx on inventory.units (created_by, tenant_id);
create index units_updated_by_idx on inventory.units (updated_by, tenant_id);

create index approval_steps_created_by_idx
  on workflow.approval_matrix_steps (created_by, tenant_id);
create index approval_steps_currency_idx
  on workflow.approval_matrix_steps (currency_code, tenant_id);
create index approval_steps_tenant_role_idx
  on workflow.approval_matrix_steps (tenant_id, role_id);
create index approval_steps_updated_by_idx
  on workflow.approval_matrix_steps (updated_by, tenant_id);
create index notifications_created_by_idx
  on workflow.notifications (created_by, tenant_id);
create index notifications_updated_by_idx
  on workflow.notifications (updated_by, tenant_id);
create index workflow_definitions_created_by_idx
  on workflow.workflow_definitions (created_by, tenant_id);
create index workflow_definitions_updated_by_idx
  on workflow.workflow_definitions (updated_by, tenant_id);
