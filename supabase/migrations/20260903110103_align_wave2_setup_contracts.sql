insert into core.currencies (
  code, name, numeric_code, minor_units, symbol, display_order
) values (
  'SAR', 'Saudi Riyal', '682', 2, 'ر.س', 110
)
on conflict (code) do update set
  name = excluded.name,
  numeric_code = excluded.numeric_code,
  minor_units = excluded.minor_units,
  symbol = excluded.symbol,
  active = true,
  display_order = excluded.display_order;

create function inventory.enforce_product_reference_scope()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if not exists (
    select 1
    from inventory.units as unit_record
    where unit_record.id = new.base_unit_id
      and unit_record.tenant_id = new.tenant_id
      and unit_record.status = 'active'
  ) then
    raise exception using
      errcode = '22023',
      message = 'Product base unit is invalid.';
  end if;

  if new.tax_definition_id is not null and not exists (
    select 1
    from finance.tax_definitions as tax_record
    where tax_record.id = new.tax_definition_id
      and tax_record.tenant_id = new.tenant_id
      and tax_record.legal_entity_id = new.legal_entity_id
      and tax_record.status = 'active'
  ) then
    raise exception using
      errcode = '22023',
      message = 'Product tax definition must be active in this entity.';
  end if;

  if new.revenue_account_id is not null and not exists (
    select 1
    from finance.accounts as account_record
    where account_record.id = new.revenue_account_id
      and account_record.tenant_id = new.tenant_id
      and account_record.legal_entity_id = new.legal_entity_id
      and account_record.status = 'active'
      and account_record.is_posting
  ) then
    raise exception using
      errcode = '22023',
      message = 'Product revenue account must be an active posting account in this entity.';
  end if;

  if new.expense_account_id is not null and not exists (
    select 1
    from finance.accounts as account_record
    where account_record.id = new.expense_account_id
      and account_record.tenant_id = new.tenant_id
      and account_record.legal_entity_id = new.legal_entity_id
      and account_record.status = 'active'
      and account_record.is_posting
  ) then
    raise exception using
      errcode = '22023',
      message = 'Product expense account must be an active posting account in this entity.';
  end if;

  if new.inventory_account_id is not null and not exists (
    select 1
    from finance.accounts as account_record
    where account_record.id = new.inventory_account_id
      and account_record.tenant_id = new.tenant_id
      and account_record.legal_entity_id = new.legal_entity_id
      and account_record.status = 'active'
      and account_record.is_posting
  ) then
    raise exception using
      errcode = '22023',
      message = 'Product inventory account must be an active posting account in this entity.';
  end if;

  if new.cogs_account_id is not null and not exists (
    select 1
    from finance.accounts as account_record
    where account_record.id = new.cogs_account_id
      and account_record.tenant_id = new.tenant_id
      and account_record.legal_entity_id = new.legal_entity_id
      and account_record.status = 'active'
      and account_record.is_posting
  ) then
    raise exception using
      errcode = '22023',
      message = 'Product cost-of-goods account must be an active posting account in this entity.';
  end if;

  return new;
end;
$$;

revoke all on function inventory.enforce_product_reference_scope()
  from public, anon, authenticated;

create trigger products_enforce_reference_scope
before insert or update of
  tenant_id,
  legal_entity_id,
  base_unit_id,
  tax_definition_id,
  revenue_account_id,
  expense_account_id,
  inventory_account_id,
  cogs_account_id
on inventory.products
for each row
execute function inventory.enforce_product_reference_scope();

comment on function inventory.enforce_product_reference_scope() is
  'Defence-in-depth tenant, entity, active-state, and posting validation for product defaults.';
