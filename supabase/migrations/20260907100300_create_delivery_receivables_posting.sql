create function sales.flow_lock_sources(p_kind text,p_doc jsonb) returns void
language plpgsql security definer set search_path='' as $$
declare v_id uuid;v_t uuid:=(p_doc->>'tenant_id')::uuid;begin
 -- AC-304 locks an order before its customer. Preserve that ordering.
 for v_id in select distinct l.sales_order_id from sales.sales_order_lines l
 join jsonb_array_elements(p_doc->'lines') x on l.id=(x->>'sales_order_line_id')::uuid
 where l.tenant_id=v_t order by l.sales_order_id loop
 perform 1 from sales.sales_orders where tenant_id=v_t and id=v_id for update;end loop;
 perform 1 from crm.parties where tenant_id=v_t and id=(p_doc->>'customer_id')::uuid for update;
 -- Customer lock serializes its invoice, receipt and return residual changes.
end $$;

create function sales.flow_post_stock(p_kind text,p_doc jsonb,p_request uuid,p_command uuid)
returns jsonb language plpgsql security definer set search_path='' as $$
declare v_t uuid:=(p_doc->>'tenant_id')::uuid;v_e uuid:=(p_doc->>'legal_entity_id')::uuid;
 v_b uuid:=(p_doc->>'branch_id')::uuid;v_date date:=(p_doc->>'document_date')::date;v_id uuid:=(p_doc->>'id')::uuid;
 v_movement uuid;v_line jsonb;v_snapshot jsonb;v_product inventory.products%rowtype;v_order sales.sales_orders%rowtype;
 v_ol sales.sales_order_lines%rowtype;v_balance inventory.stock_balances%rowtype;v_value inventory.stock_valuations%rowtype;
 v_res inventory.stock_reservations%rowtype;v_original inventory.stock_movement_lines%rowtype;
 v_lot inventory.lots%rowtype;v_lb inventory.lot_balances%rowtype;v_serial inventory.serials%rowtype;
 v_serial_ids uuid[];v_serial_id uuid;v_warehouse uuid;v_lot_id uuid;v_q numeric;v_cost numeric;v_prior numeric;
 v_inventory uuid;v_cogs uuid;v_jlines jsonb:='[]';v_sign integer:=case when p_kind='delivery' then -1 else 1 end;
begin
 -- Lock stock products with exactly the same advisory identity as reservations.
 for v_warehouse,v_serial_id in select distinct
 case when p_kind='delivery' then (p_doc->>'warehouse_id')::uuid else d.warehouse_id end, (x->>'product_id')::uuid
 from jsonb_array_elements(p_doc->'lines') x
 left join sales.delivery_lines dl on dl.tenant_id=v_t and dl.id=(x->>'delivery_line_id')::uuid
 left join sales.deliveries d on d.tenant_id=v_t and d.id=dl.document_id
 where x#>>'{snapshot,product_kind}'='stocked' order by 1,2 loop
 perform pg_advisory_xact_lock(hashtextextended(v_t::text||':'||v_warehouse::text||':'||v_serial_id::text,0));end loop;
 for v_line in select value from jsonb_array_elements(p_doc->'lines') loop
 v_snapshot:=v_line->'snapshot';v_q:=(v_line->>'base_quantity')::numeric;
 if v_snapshot->>'product_kind'<>'stocked' then
 if p_kind='delivery' then update sales.sales_order_lines set delivered_quantity=delivered_quantity+v_q,updated_by=auth.uid()
 where tenant_id=v_t and id=(v_line->>'sales_order_line_id')::uuid;end if;continue;end if;
 if p_kind='sales_return' and v_snapshot->>'disposition'='no_restock' then continue;end if;
 select * into v_product from inventory.products where tenant_id=v_t and legal_entity_id=v_e and id=(v_line->>'product_id')::uuid;
 v_original:=null;v_lot:=null;v_lb:=null;
 if p_kind='sales_return' then
 select ml.* into v_original from inventory.stock_movement_lines ml join inventory.stock_movements m on m.id=ml.stock_movement_id
 where ml.tenant_id=v_t and ml.source_line_id=(v_line->>'delivery_line_id')::uuid and m.movement_kind='delivery';
 if not found then raise exception using errcode='22023',message='RETURN_STOCK_SOURCE_REQUIRED';end if;
 v_warehouse:=v_original.warehouse_id;v_lot_id:=v_original.lot_id;
 select coalesce(sum(base_quantity),0) into v_prior from inventory.stock_movement_lines where tenant_id=v_t and original_movement_line_id=v_original.id;
 if v_prior+v_q> -v_original.base_quantity then raise exception using errcode='22023',message='SOURCE_QUANTITY_EXCEEDED';end if;
 v_cost:=round((-v_original.base_value)*(v_prior+v_q)/(-v_original.base_quantity),6)-round((-v_original.base_value)*v_prior/(-v_original.base_quantity),6);
 else
 v_warehouse:=(p_doc->>'warehouse_id')::uuid;v_lot_id:=(v_snapshot#>>'{tracking,lot_id}')::uuid;
 end if;
 if not exists(select 1 from core.warehouses w where w.tenant_id=v_t and w.legal_entity_id=v_e and w.branch_id=v_b and w.id=v_warehouse and w.status='active') then
 raise exception using errcode='22023',message='WAREHOUSE_INACTIVE';end if;
 if v_movement is not null and exists(select 1 from inventory.stock_movements where id=v_movement and warehouse_id<>v_warehouse) then
 raise exception using errcode='22023',message='RETURN_SINGLE_WAREHOUSE_REQUIRED';end if;
 select * into v_balance from inventory.stock_balances where tenant_id=v_t and legal_entity_id=v_e and branch_id=v_b and warehouse_id=v_warehouse and product_id=v_product.id for update;
 if not found then raise exception using errcode='55000',message='STOCK_BALANCE_UNAVAILABLE';end if;
 select * into v_value from inventory.stock_valuations where tenant_id=v_t and stock_balance_id=v_balance.id for update;
 if not found then raise exception using errcode='55000',message='INVENTORY_COST_UNAVAILABLE';end if;
 if v_product.tracking_mode='lot' then
 select * into v_lot from inventory.lots where tenant_id=v_t and legal_entity_id=v_e and product_id=v_product.id and id=v_lot_id and status='saleable';
 if not found or (v_lot.expiry_date is not null and v_lot.expiry_date<greatest(v_date,(clock_timestamp() at time zone 'UTC')::date)) then
 raise exception using errcode='22023',message='LOT_NOT_SALEABLE';end if;
 select * into v_lb from inventory.lot_balances where tenant_id=v_t and warehouse_id=v_warehouse and product_id=v_product.id and lot_id=v_lot_id for update;
 if not found or (p_kind='delivery' and v_lb.on_hand_quantity<v_q) then raise exception using errcode='22023',message='LOT_QUANTITY_UNAVAILABLE';end if;
 elsif v_lot_id is not null and v_product.tracking_mode='none' then raise exception using errcode='22023',message='TRACKING_INPUT_INVALID';end if;
 select coalesce(array_agg(x::uuid order by x),'{}'::uuid[]) into v_serial_ids
 from jsonb_array_elements_text(coalesce(v_snapshot#>'{tracking,serial_ids}','[]')) x;
 if v_product.tracking_mode='serial' then
 if v_q<>trunc(v_q) or cardinality(v_serial_ids)<>v_q or cardinality(v_serial_ids)<>(select count(distinct x) from unnest(v_serial_ids) x) then
 raise exception using errcode='22023',message='SERIAL_CONFLICT';end if;
 foreach v_serial_id in array v_serial_ids loop
 select * into v_serial from inventory.serials where tenant_id=v_t and legal_entity_id=v_e and branch_id=v_b and product_id=v_product.id and id=v_serial_id for update;
 if not found or v_serial.warehouse_id<>v_warehouse or (p_kind='delivery' and v_serial.status<>'available')
 or (p_kind='sales_return' and (v_serial.status<>'issued' or v_serial.last_delivery_line_id<>(v_line->>'delivery_line_id')::uuid
 or not v_serial.id=any(v_original.serial_ids))) then raise exception using errcode='22023',message='SERIAL_CONFLICT';end if;
 update inventory.serials set status=case when p_kind='delivery' then 'issued' else 'available' end,
 last_delivery_line_id=case when p_kind='delivery' then (v_line->>'id')::uuid else last_delivery_line_id end,updated_by=auth.uid() where id=v_serial_id;
 end loop;
 elsif cardinality(v_serial_ids)>0 then raise exception using errcode='22023',message='TRACKING_INPUT_INVALID';end if;
 if p_kind='delivery' then
 select * into v_ol from sales.sales_order_lines where tenant_id=v_t and id=(v_line->>'sales_order_line_id')::uuid for update;
 select * into v_res from inventory.stock_reservations where tenant_id=v_t and sales_order_line_id=v_ol.id and warehouse_id=v_warehouse and status='active' for update;
 if not found or v_res.expires_at<=clock_timestamp() or v_res.base_quantity<v_q or v_ol.allocated_quantity<v_q then
 raise exception using errcode='55000',message='RESERVATION_INSUFFICIENT';end if;
 if v_balance.on_hand_quantity<v_q or v_balance.allocated_quantity<v_q then raise exception using errcode='55000',message='INSUFFICIENT_STOCK';end if;
 v_cost:=case when v_q=v_balance.on_hand_quantity then v_value.carrying_value else round(v_value.carrying_value*v_q/v_balance.on_hand_quantity,6) end;
 if v_res.base_quantity=v_q then update inventory.stock_reservations set status='fulfilled',released_at=clock_timestamp(),release_reason='Delivery posted',updated_by=auth.uid() where id=v_res.id;
 else update inventory.stock_reservations set base_quantity=base_quantity-v_q,updated_by=auth.uid() where id=v_res.id;end if;
 update inventory.stock_balances set on_hand_quantity=on_hand_quantity-v_q,allocated_quantity=allocated_quantity-v_q,updated_by=auth.uid() where id=v_balance.id;
 update sales.sales_order_lines set allocated_quantity=allocated_quantity-v_q,delivered_quantity=delivered_quantity+v_q,updated_by=auth.uid() where id=v_ol.id;
 else update inventory.stock_balances set on_hand_quantity=on_hand_quantity+v_q,updated_by=auth.uid() where id=v_balance.id;end if;
 update inventory.stock_valuations set carrying_value=carrying_value+v_sign*v_cost,updated_by=auth.uid() where id=v_value.id;
 if v_lb.id is not null then update inventory.lot_balances set on_hand_quantity=on_hand_quantity+v_sign*v_q,updated_by=auth.uid() where id=v_lb.id;end if;
 if v_movement is null then
 v_movement:=gen_random_uuid();
 insert into inventory.stock_movements(id,tenant_id,legal_entity_id,branch_id,source_type,source_id,warehouse_id,posting_date,movement_kind,request_id,command_id,correlation_id,created_by)
 values(v_movement,v_t,v_e,v_b,p_kind,v_id,v_warehouse,v_date,p_kind,p_request,p_command,p_request,auth.uid());end if;
 insert into inventory.stock_movement_lines(tenant_id,legal_entity_id,branch_id,stock_movement_id,warehouse_id,product_id,
 source_line_id,original_movement_line_id,base_quantity,base_value,lot_id,serial_ids,posting_date,created_by)
 values(v_t,v_e,v_b,v_movement,v_warehouse,v_product.id,(v_line->>'id')::uuid,v_original.id,v_sign*v_q,v_sign*v_cost,v_lot_id,v_serial_ids,v_date,auth.uid());
 if v_cost>0 then
 v_inventory:=v_product.inventory_account_id;
 v_cogs:=v_product.cogs_account_id;
 if p_kind='sales_return' then
 select jl.account_id into v_inventory from finance.journal_lines jl join finance.journal_entries j on j.id=jl.journal_entry_id
 join finance.accounts a on a.id=jl.account_id where jl.tenant_id=v_t and jl.source_line_id=v_original.source_line_id
 and j.source_type='delivery.stock' and a.account_type='asset';
 select jl.account_id into v_cogs from finance.journal_lines jl join finance.journal_entries j on j.id=jl.journal_entry_id
 join finance.accounts a on a.id=jl.account_id where jl.tenant_id=v_t and jl.source_line_id=v_original.source_line_id
 and j.source_type='delivery.stock' and a.account_type='expense';
 end if;
 perform finance.flow_account(v_t,v_e,v_inventory,'asset',p_doc->>'base_currency_code');
 perform finance.flow_account(v_t,v_e,v_cogs,'expense',p_doc->>'base_currency_code');
 v_jlines:=v_jlines||jsonb_build_array(finance.flow_jline(v_inventory,v_sign*v_cost,v_sign*v_cost,(v_line->>'id')::uuid),
 finance.flow_jline(v_cogs,-v_sign*v_cost,-v_sign*v_cost,(v_line->>'id')::uuid));end if;
 end loop;
 if p_kind='delivery' then
 update sales.sales_orders o set status=case when not exists(select 1 from sales.sales_order_lines l where l.tenant_id=v_t and l.sales_order_id=o.id
 and l.delivered_quantity+l.cancelled_quantity<l.base_ordered_quantity) then 'fulfilled'
 when exists(select 1 from sales.sales_order_lines l where l.tenant_id=v_t and l.sales_order_id=o.id and l.product_kind='stocked'
 and l.allocated_quantity+l.delivered_quantity+l.cancelled_quantity<l.base_ordered_quantity) then 'partially_reserved' else 'reserved' end,
 updated_by=auth.uid(),request_id=p_request,command_id=p_command,correlation_id=p_request
 where o.tenant_id=v_t and o.id=(p_doc->>'sales_order_id')::uuid;end if;
 return jsonb_build_object('movement_id',v_movement,'journal_lines',v_jlines);end $$;

create function finance.flow_refresh_credit(p_doc jsonb) returns void
language plpgsql security definer set search_path='' as $$
declare v_due numeric;v_overdue numeric;v_t uuid:=(p_doc->>'tenant_id')::uuid;v_e uuid:=(p_doc->>'legal_entity_id')::uuid;
 v_b uuid:=(p_doc->>'branch_id')::uuid;v_customer uuid:=(p_doc->>'customer_id')::uuid;v_currency text;begin
 for v_currency in select distinct currency_code from finance.open_items where tenant_id=v_t and legal_entity_id=v_e and branch_id=v_b and party_id=v_customer loop
 select coalesce(sum(greatest((finance.flow_residual(v_t,id)->>'amount')::numeric,0)),0),
 coalesce(sum(case when due_date<(clock_timestamp() at time zone 'UTC')::date then greatest((finance.flow_residual(v_t,id)->>'amount')::numeric,0) else 0 end),0)
 into v_due,v_overdue from finance.open_items where tenant_id=v_t and legal_entity_id=v_e and branch_id=v_b
 and party_id=v_customer and kind='AR' and currency_code=v_currency;
 insert into sales.customer_credit_exposures(tenant_id,legal_entity_id,branch_id,customer_id,currency_code,due_exposure,overdue_exposure,as_of_at,source_context,created_by,updated_by)
 values(v_t,v_e,v_b,v_customer,v_currency,v_due,v_overdue,clock_timestamp(),'{"source":"receivables_ledger"}',auth.uid(),auth.uid())
 on conflict(tenant_id,legal_entity_id,branch_id,customer_id,currency_code) do update set due_exposure=excluded.due_exposure,
 overdue_exposure=excluded.overdue_exposure,as_of_at=excluded.as_of_at,source_context=excluded.source_context,updated_by=excluded.updated_by;
 end loop;end $$;

create function sales.flow_post(p_kind text,p_tenant_id uuid,p_legal_entity_id uuid,p_branch_id uuid,
 p_command_id uuid,p_idempotency_key uuid,p_client_timestamp timestamptz,p_payload jsonb,p_expected_entity_version bigint)
returns jsonb language plpgsql security definer set search_path='' as $$
declare v_id uuid:=coalesce((p_payload->>'document_id')::uuid,(p_payload->>'id')::uuid);v_command text:='sales.'||p_kind||'.post';
 v_hash text;v_replay jsonb;v_doc jsonb;v_before jsonb;v_request uuid:=gen_random_uuid();v_stock jsonb;
 v_jlines jsonb:='[]';v_journal uuid;v_stock_journal uuid;v_open uuid;v_line jsonb;v_product inventory.products%rowtype;
 v_amount numeric;v_base numeric;v_net numeric;v_tax numeric;v_net_base numeric;v_tax_base numeric;v_diff numeric;
 v_control uuid;v_bank finance.cash_bank_accounts%rowtype;v_sign integer:=case when p_kind='sales_invoice' then 1 else -1 end;
 v_stock_doc jsonb;v_allocation jsonb;v_outputs jsonb;v_scale integer;v_revenue uuid;v_tax_account uuid;
begin
 perform core.wave3_require_scope(p_tenant_id,sales.flow_permission(p_kind,'post'),p_legal_entity_id,p_branch_id);
 if p_branch_id is null or p_client_timestamp is null or v_id is null then raise exception using errcode='22023',message='DOCUMENT_PAYLOAD_INVALID';end if;
 v_hash:=core.wave3_request_hash(v_command,p_command_id,p_tenant_id,p_legal_entity_id,p_branch_id,p_payload,p_expected_entity_version);
 v_replay:=core.wave3_replay(p_tenant_id,v_command,p_command_id,p_idempotency_key,v_hash);if v_replay is not null then return v_replay;end if;
 v_doc:=sales.flow_document(p_kind,p_tenant_id,v_id,true);v_before:=v_doc;
 if v_doc is null or (v_doc->>'legal_entity_id')::uuid<>p_legal_entity_id or (v_doc->>'branch_id')::uuid<>p_branch_id then
 raise exception using errcode='P0002',message='DOCUMENT_NOT_FOUND';end if;
 perform core.wave3_assert_expected_version((v_doc->>'version')::bigint,p_expected_entity_version,v_doc);
 if v_doc->>'status' not in ('submitted','approved') or v_doc->'workflow_snapshot' is null
 or (v_doc#>'{workflow_snapshot,lifecycle,requires_approval}' is distinct from 'false'::jsonb and v_doc->>'status'<>'approved') then
 raise exception using errcode='55000',message='DOCUMENT_NOT_APPROVED';end if;
 perform sales.flow_assert_transition(v_doc#>'{workflow_snapshot,lifecycle}',v_doc->>'status','posted');
 if v_doc#>'{workflow_snapshot,lifecycle,separate_poster}'='true'::jsonb and (v_doc->>'submitted_by')::uuid=auth.uid() then
 raise exception using errcode='42501',message='SEGREGATION_OF_DUTIES_VIOLATION';end if;
 perform sales.flow_lock_sources(p_kind,v_doc);
 perform finance.wave3_lock_open_period(p_tenant_id,p_legal_entity_id,(v_doc->>'document_date')::date);
 if (v_doc->>'document_date')::date>(clock_timestamp() at time zone 'UTC')::date then raise exception using errcode='22023',message='FUTURE_POSTING_DATE';end if;
 perform sales.flow_revalidate(p_kind,v_doc);
 v_scale:=(v_doc->>'rounding_scale')::integer;v_amount:=(v_doc->>'grand_total')::numeric;v_base:=(v_doc->>'base_total')::numeric;
 if p_kind in ('delivery','sales_return') then
 v_stock:=sales.flow_post_stock(p_kind,v_doc,v_request,p_command_id);
 v_stock_doc:=v_doc||jsonb_build_object('currency_code',v_doc->>'base_currency_code','exchange_rate','1');
 v_stock_journal:=finance.flow_post_journal(v_stock_doc,v_stock->'journal_lines',p_kind||'.stock',v_id,v_request,p_command_id);
 end if;
 if p_kind='customer_receipt' then
 select * into v_bank from finance.cash_bank_accounts where tenant_id=p_tenant_id and legal_entity_id=p_legal_entity_id and branch_id=p_branch_id
 and id=(v_doc->>'cash_bank_account_id')::uuid and status='active' and currency_code=v_doc->>'currency_code';
 if not found then raise exception using errcode='55000',message='CASH_BANK_ACCOUNT_INVALID';end if;
 perform finance.flow_account(p_tenant_id,p_legal_entity_id,v_bank.account_id,'asset',v_doc->>'currency_code');
 v_control:=finance.flow_mapping(p_tenant_id,p_legal_entity_id,'receivable_control',v_doc->>'currency_code');
 v_jlines:=jsonb_build_array(finance.flow_jline(v_bank.account_id,v_amount,v_base),finance.flow_jline(v_control,-v_amount,-v_base));
 elsif p_kind in ('sales_invoice','sales_return') and v_amount>0 then
 v_control:=finance.flow_mapping(p_tenant_id,p_legal_entity_id,'receivable_control',v_doc->>'currency_code');
 v_jlines:=jsonb_build_array(finance.flow_jline(v_control,v_sign*v_amount,v_sign*v_base));
 for v_line in select value from jsonb_array_elements(v_doc->'lines') loop
 v_net:=(v_line->>'taxable_amount')::numeric;v_tax:=(v_line->>'tax_amount')::numeric;
 v_net_base:=round(v_net*(v_doc->>'exchange_rate')::numeric,v_scale);v_tax_base:=round(v_tax*(v_doc->>'exchange_rate')::numeric,v_scale);
 select * into v_product from inventory.products where tenant_id=p_tenant_id and legal_entity_id=p_legal_entity_id and id=(v_line->>'product_id')::uuid;
 v_revenue:=v_product.revenue_account_id;
 if p_kind='sales_return' then
 select l.account_id into v_revenue from finance.journal_lines l join finance.journal_entries j on j.id=l.journal_entry_id
 join finance.accounts a on a.id=l.account_id where l.tenant_id=p_tenant_id and j.source_type='sales_invoice'
 and l.source_line_id=(v_line->>'sales_invoice_line_id')::uuid and a.account_type='revenue';
 select l.account_id into v_tax_account from finance.journal_lines l join finance.journal_entries j on j.id=l.journal_entry_id
 join finance.accounts a on a.id=l.account_id where l.tenant_id=p_tenant_id and j.source_type='sales_invoice'
 and l.source_line_id=(v_line->>'sales_invoice_line_id')::uuid and a.account_type='liability';
 elsif v_tax>0 then v_tax_account:=finance.flow_mapping(p_tenant_id,p_legal_entity_id,'output_tax',v_doc->>'currency_code');end if;
 if v_net>0 then v_jlines:=v_jlines||jsonb_build_array(finance.flow_jline(finance.flow_account(p_tenant_id,p_legal_entity_id,
 v_revenue,'revenue',v_doc->>'currency_code'),-v_sign*v_net,-v_sign*v_net_base,(v_line->>'id')::uuid));end if;
 if v_tax>0 then v_jlines:=v_jlines||jsonb_build_array(finance.flow_jline(finance.flow_account(p_tenant_id,p_legal_entity_id,
 v_tax_account,'liability',v_doc->>'currency_code'),-v_sign*v_tax,-v_sign*v_tax_base,(v_line->>'id')::uuid));end if;
 end loop;
 select sum((x->>'base_amount')::numeric) into v_diff from jsonb_array_elements(v_jlines) x;
 if v_diff<>0 then v_jlines:=v_jlines||jsonb_build_array(finance.flow_jline(finance.flow_mapping(p_tenant_id,p_legal_entity_id,'rounding',v_doc->>'currency_code'),0,-v_diff));end if;
 end if;
 -- Zero-value invoices still consume their source quantities.
 if p_kind='sales_invoice' then
 for v_line in select value from jsonb_array_elements(v_doc->'lines') where value->>'sales_order_line_id' is not null loop
 update sales.sales_order_lines set invoiced_quantity=invoiced_quantity+(v_line->>'base_quantity')::numeric,updated_by=auth.uid()
 where tenant_id=p_tenant_id and id=(v_line->>'sales_order_line_id')::uuid;
 update sales.sales_orders set updated_by=auth.uid() where tenant_id=p_tenant_id and id=(select sales_order_id from sales.sales_order_lines where id=(v_line->>'sales_order_line_id')::uuid);
 end loop;end if;
 if jsonb_array_length(v_jlines)>0 then
 v_journal:=finance.flow_post_journal(v_doc,v_jlines,p_kind,v_id,v_request,p_command_id);
 v_open:=gen_random_uuid();insert into finance.open_items(id,tenant_id,legal_entity_id,branch_id,party_id,source_type,source_id,
 document_number,currency_code,base_currency_code,exchange_rate,original_amount,original_base_amount,posting_date,due_date,
 journal_entry_id,request_id,command_id,correlation_id,created_by)
 values(v_open,p_tenant_id,p_legal_entity_id,p_branch_id,(v_doc->>'customer_id')::uuid,p_kind,v_id,v_doc->>'document_number',
 v_doc->>'currency_code',v_doc->>'base_currency_code',(v_doc->>'exchange_rate')::numeric,v_sign*v_amount,v_sign*v_base,
 (v_doc->>'document_date')::date,(v_doc->>'due_date')::date,v_journal,v_request,p_command_id,v_request,auth.uid());
 end if;
 execute format('update sales.%I set status=''posted'',posted_by=$1,posted_at=clock_timestamp(),updated_by=$1,request_id=$2,command_id=$3,correlation_id=$2,client_timestamp=$4 where tenant_id=$5 and id=$6',sales.flow_table(p_kind))
 using auth.uid(),v_request,p_command_id,p_client_timestamp,p_tenant_id,v_id;
 if v_open is not null then perform finance.flow_refresh_credit(v_doc);end if;
 v_outputs:=jsonb_build_object('stock_movement_ids',case when v_stock->>'movement_id' is null then '[]'::jsonb else jsonb_build_array(v_stock->>'movement_id') end,
 'journal_entry_ids',to_jsonb(array_remove(array[v_stock_journal,v_journal],null)),
 'open_item_ids',to_jsonb(array_remove(array[v_open],null)),'allocation_ids','[]'::jsonb,'reconciliation_status','unreconciled');
 return core.wave3_finish_command(p_tenant_id,v_command,p_command_id,p_kind,v_id,p_idempotency_key,v_hash,v_before,
 sales.flow_document(p_kind,p_tenant_id,v_id)||v_outputs,p_legal_entity_id,p_branch_id,coalesce(p_payload->'source_context','{}'),
 jsonb_build_object('from_status',v_before->>'status','to_status','posted'),
 jsonb_build_array(jsonb_build_object('topic',v_command,'payload',v_outputs)),'[]',v_request,v_request);
end $$;

do $$ declare v_kind text;v_name text;begin
 for v_kind,v_name in select * from (values ('delivery','post_delivery'),('sales_invoice','post_sales_invoice'),
 ('customer_receipt','post_customer_receipt'),('sales_return','post_sales_return')) x loop
 execute format($ddl$create function api.%I(p_tenant_id uuid,p_legal_entity_id uuid,p_branch_id uuid,p_command_id uuid,
 p_idempotency_key uuid,p_client_timestamp timestamptz,p_payload jsonb,p_expected_entity_version bigint default null)
 returns jsonb language sql security definer set search_path='' as $body$
 select sales.flow_post(%L,p_tenant_id,p_legal_entity_id,p_branch_id,p_command_id,p_idempotency_key,p_client_timestamp,p_payload,p_expected_entity_version) $body$ $ddl$,v_name,v_kind);
 execute format('revoke all on function api.%I(uuid,uuid,uuid,uuid,uuid,timestamptz,jsonb,bigint) from public,anon,authenticated',v_name);
 execute format('grant execute on function api.%I(uuid,uuid,uuid,uuid,uuid,timestamptz,jsonb,bigint) to authenticated',v_name);
 end loop;end $$;
revoke all on function sales.flow_lock_sources(text,jsonb),sales.flow_post_stock(text,jsonb,uuid,uuid),
 finance.flow_refresh_credit(jsonb),sales.flow_post(text,uuid,uuid,uuid,uuid,uuid,timestamptz,jsonb,bigint) from public,anon,authenticated;
