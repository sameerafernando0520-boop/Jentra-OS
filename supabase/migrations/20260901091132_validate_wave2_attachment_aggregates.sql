-- Attachment metadata may only target a real Wave 2 aggregate in the same
-- tenant. Future domain migrations can extend this explicit allowlist.

create function core.validate_attachment_aggregate()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_exists boolean := false;
begin
  v_exists := case new.aggregate_type
    when 'tenant' then exists (
      select 1 from core.tenants as t
      where t.id = new.aggregate_id and t.id = new.tenant_id
    )
    when 'legal_entity' then exists (
      select 1 from core.legal_entities as le
      where le.tenant_id = new.tenant_id and le.id = new.aggregate_id
    )
    when 'branch' then exists (
      select 1 from core.branches as b
      where b.tenant_id = new.tenant_id and b.id = new.aggregate_id
    )
    when 'warehouse' then exists (
      select 1 from core.warehouses as w
      where w.tenant_id = new.tenant_id and w.id = new.aggregate_id
    )
    when 'party' then exists (
      select 1 from crm.parties as p
      where p.tenant_id = new.tenant_id and p.id = new.aggregate_id
    )
    when 'contact' then exists (
      select 1 from crm.contacts as c
      where c.tenant_id = new.tenant_id and c.id = new.aggregate_id
    )
    when 'unit' then exists (
      select 1 from inventory.units as u
      where u.tenant_id = new.tenant_id and u.id = new.aggregate_id
    )
    when 'product' then exists (
      select 1 from inventory.products as p
      where p.tenant_id = new.tenant_id and p.id = new.aggregate_id
    )
    when 'account' then exists (
      select 1 from finance.accounts as a
      where a.tenant_id = new.tenant_id and a.id = new.aggregate_id
    )
    when 'tax_definition' then exists (
      select 1 from finance.tax_definitions as td
      where td.tenant_id = new.tenant_id and td.id = new.aggregate_id
    )
    when 'fiscal_period' then exists (
      select 1 from finance.fiscal_periods as fp
      where fp.tenant_id = new.tenant_id and fp.id = new.aggregate_id
    )
    when 'document_sequence' then exists (
      select 1 from core.document_sequences as ds
      where ds.tenant_id = new.tenant_id and ds.id = new.aggregate_id
    )
    when 'workflow_definition' then exists (
      select 1 from workflow.workflow_definitions as wd
      where wd.tenant_id = new.tenant_id and wd.id = new.aggregate_id
    )
    when 'report_definition' then exists (
      select 1 from core.report_definitions as rd
      where rd.tenant_id = new.tenant_id and rd.id = new.aggregate_id
    )
    when 'import_job' then exists (
      select 1 from core.import_jobs as ij
      where ij.tenant_id = new.tenant_id and ij.id = new.aggregate_id
    )
    when 'export_job' then exists (
      select 1 from core.export_jobs as ej
      where ej.tenant_id = new.tenant_id and ej.id = new.aggregate_id
    )
    else false
  end;

  if not v_exists then
    raise exception using
      errcode = '22023',
      message = 'Attachment aggregate is invalid.';
  end if;
  return new;
end;
$$;

create trigger attachments_validate_aggregate
  before insert or update of tenant_id, aggregate_type, aggregate_id
  on core.attachments
  for each row execute function core.validate_attachment_aggregate();

revoke execute on function core.validate_attachment_aggregate()
  from public, anon, authenticated;
