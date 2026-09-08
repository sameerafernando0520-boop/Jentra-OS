-- Invoice integration only. Preserve the published AC-304 migration and API signatures.
create function sales.flow_order_uninvoiced(p_tenant uuid,p_order uuid) returns numeric
language sql stable security definer set search_path='' as $$
 select greatest(o.grand_total-coalesce((select sum(il.line_total) from sales.sales_invoice_lines il
 join sales.sales_invoices i on i.tenant_id=il.tenant_id and i.id=il.document_id
 join sales.sales_order_lines ol on ol.tenant_id=il.tenant_id and ol.id=il.sales_order_line_id
 where il.tenant_id=p_tenant and ol.sales_order_id=p_order and i.status='posted'),0),0)
 from sales.sales_orders o where o.tenant_id=p_tenant and o.id=p_order $$;
revoke all on function sales.flow_order_uninvoiced(uuid,uuid) from public,anon,authenticated;

do $$ declare v_oid oid;v_body text;v_changed text;v_count integer:=0;begin
 for v_oid in select p.oid from pg_proc p join pg_namespace n on n.oid=p.pronamespace
 where n.nspname='api' and p.proname in ('get_sales_order_credit_preview','transition_operational_document') loop
 v_count:=v_count+1;
 v_body:=pg_get_functiondef(v_oid);
 if v_body like '%select coalesce(sum(grand_total),0) into v_existing from sales.sales_orders%' then
 v_changed:=replace(v_body,'select coalesce(sum(grand_total),0) into v_existing from sales.sales_orders',
 'select coalesce(sum(sales.flow_order_uninvoiced(tenant_id,id)),0) into v_existing from sales.sales_orders');
 v_changed:=replace(v_changed,'status in (''confirmed'',''partially_reserved'',''reserved'')','status in (''confirmed'',''partially_reserved'',''reserved'',''fulfilled'')');
 v_changed:=replace(v_changed,'v_order.grand_total','sales.flow_order_uninvoiced(p_tenant_id,v_order.id)');
 elsif v_body like '%select coalesce(sum(o.grand_total), 0)::numeric(20, 6)%' then
 v_changed:=replace(v_body,'select coalesce(sum(o.grand_total), 0)::numeric(20, 6)',
 'select coalesce(sum(sales.flow_order_uninvoiced(o.tenant_id,o.id)), 0)::numeric(20, 6)');
 v_changed:=replace(v_changed,'o.status in (''confirmed'', ''partially_reserved'', ''reserved'')',
 'o.status in (''confirmed'', ''partially_reserved'', ''reserved'', ''fulfilled'')');
 else raise exception 'AC304_CREDIT_INTEGRATION_CONTRACT_CHANGED';end if;
 execute v_changed;
 end loop;
 if v_count<>2 then raise exception 'AC304_CREDIT_INTEGRATION_CONTRACT_CHANGED';end if;
end $$;
