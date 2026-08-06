begin;

-- Create RPC function: post_stock_movement
create or replace function public.post_stock_movement(
  p_company_id uuid,
  p_product_id uuid,
  p_warehouse_id uuid,
  p_movement_type text,
  p_quantity numeric,
  p_unit_cost numeric default null,
  p_reference_type text default null,
  p_reference_id text default null,
  p_notes text default null
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public, private, extensions
as $$
declare
  v_movement_id uuid;
  v_balance_id uuid;
  v_delta numeric;
  v_balance public.stock_balances;
begin
  -- 1. Permission check (company membership)
  if not private.is_company_member(p_company_id) then
    raise exception 'Permission denied.'
      using errcode = '42501';
  end if;

  -- 2. Validate quantity
  if p_quantity is null or p_quantity <= 0 then
    raise exception 'Stock movement quantity must be greater than zero.';
  end if;

  -- 3. Calculate delta (out movements subtract quantity, all others add)
  if p_movement_type = 'out' then
    v_delta := -abs(p_quantity);
  else
    v_delta := p_quantity;
  end if;

  -- 4. Create movement record
  v_movement_id := gen_random_uuid();
  insert into public.stock_movements (
    id,
    company_id,
    product_id,
    warehouse_id,
    movement_type,
    quantity,
    unit_cost,
    reference_type,
    reference_id,
    notes,
    created_by
  ) values (
    v_movement_id,
    p_company_id,
    p_product_id,
    p_warehouse_id,
    p_movement_type,
    p_quantity,
    p_unit_cost,
    p_reference_type,
    p_reference_id,
    p_notes,
    auth.uid()
  );

  -- 5. Lock balance row if it exists (FOR UPDATE) and upsert balance
  select * into v_balance
  from public.stock_balances
  where company_id = p_company_id
    and product_id = p_product_id
    and warehouse_id = p_warehouse_id
  for update;

  if v_balance.id is null then
    insert into public.stock_balances (
      company_id,
      product_id,
      warehouse_id,
      quantity_on_hand,
      quantity_allocated
    ) values (
      p_company_id,
      p_product_id,
      p_warehouse_id,
      v_delta,
      0
    ) returning id into v_balance_id;
  else
    update public.stock_balances
    set quantity_on_hand = quantity_on_hand + v_delta
    where id = v_balance.id;
    v_balance_id := v_balance.id;
  end if;

  return jsonb_build_object(
    'success', true,
    'movement_id', v_movement_id,
    'balance_id', v_balance_id
  );
end;
$$;

revoke all on function public.post_stock_movement(uuid, uuid, uuid, text, numeric, numeric, text, text, text) from public, anon;
grant execute on function public.post_stock_movement(uuid, uuid, uuid, text, numeric, numeric, text, text, text) to authenticated, service_role;

-- Revoke direct mutation grants on stock_balances from authenticated (Blocker 2)
revoke insert, update on public.stock_balances from authenticated;

-- Revoke direct insert grants on journal_entries and journal_lines from authenticated (Blocker 3)
revoke insert on public.journal_entries from authenticated;
revoke insert on public.journal_lines from authenticated;

commit;
