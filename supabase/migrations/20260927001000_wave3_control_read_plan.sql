-- UNAPPLIED additive read-plan candidate. Existing immutable engines untouched.
create index stock_movements_finance_command_source on inventory.stock_movements
 (tenant_id,legal_entity_id,command_id,source_type);

create or replace function finance.close_inventory_accounts(t uuid,e uuid,d date) returns jsonb
language plpgsql stable security definer set search_path='' as $$declare ids jsonb;begin
 with stock_commands as materialized (
  select distinct m.command_id,s.source_type from inventory.stock_movements m
  cross join lateral(values(m.source_type),(m.source_type||'.stock'))s(source_type)
  where m.tenant_id=t and m.legal_entity_id=e and m.command_id is not null
 ), controls as (
  select inventory_account_id id from inventory.products where tenant_id=t and legal_entity_id=e
  union
  select l.account_id from finance.journal_lines l
  join finance.journal_entries j on j.tenant_id=l.tenant_id and j.id=l.journal_entry_id
  join stock_commands s on s.command_id=j.command_id and s.source_type=j.source_type
  join finance.accounts a on a.tenant_id=l.tenant_id and a.id=l.account_id and a.account_type='asset'
  where l.tenant_id=t and l.legal_entity_id=e and j.status='posted' and l.posting_date<=d
 )
 select coalesce(jsonb_agg(id order by id),'[]') into ids
 from (select id from controls where id is not null order by id limit 51)q;
 if jsonb_array_length(ids)>50 then raise exception using errcode='54000',message='CLOSE_INVENTORY_ACCOUNT_LIMIT';end if;
 return ids;
end$$;
revoke all on function finance.close_inventory_accounts(uuid,uuid,date) from public,anon,authenticated;
