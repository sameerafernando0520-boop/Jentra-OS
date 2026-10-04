"""Compose the reviewable additive supersessions from unchanged prior candidates.

Run only while authoring the dated candidate. This does not execute SQL or mutate
prior migrations. Every replacement asserts its exact source boundary.
"""
from pathlib import Path
import re

ROOT = Path(__file__).resolve().parents[2]
TARGET = ROOT / "supabase/migrations/20261003090000_wave3_negative_stock_policy.sql"
MARKER = "-- GENERATED ADDITIVE SUPERSESSIONS: source boundaries asserted by dated composer."
END_MARKER = "-- END GENERATED ADDITIVE SUPERSESSIONS."

def read(name):
    return (ROOT / "supabase/migrations" / name).read_text(encoding="utf-8-sig")

def extract(source, name):
    pattern = r"create (?:or replace )?function " + re.escape(name) + r"\([\s\S]*?\$\$;"
    result = re.search(pattern, source, re.I)
    if not result:
        raise RuntimeError("Missing exact function: " + name)
    return result.group(0)

def replace(body, old, new):
    if body.count(old) != 1:
        raise RuntimeError("Ambiguous replacement: " + old[:100])
    return body.replace(old, new)

reserve = extract(read("20260907044241_complete_sales_order_workspace.sql"), "api.reserve_sales_order_stock")
reserve = reserve.replace("create or replace function", "create function", 1)
reserve = replace(reserve, "  v_to_status text;", """  v_to_status text;
  v_policy inventory.negative_stock_policy_versions%rowtype;
  v_basis inventory.negative_stock_cost_bases%rowtype;
  v_val inventory.stock_valuations%rowtype;
  v_tracking text;
  v_has_override boolean := coalesce(p_payload ? 'negative_stock_override',false);
  v_used_override boolean := false;""")
reserve = replace(reserve, "begin\n  perform core.wave3_require_scope(", """begin
  if not v_has_override then
    if (p_payload->'source_context') ? 'negative_stock_override' then
      raise exception using errcode='22023',message='NEGATIVE_STOCK_OVERRIDE_INPUT_INVALID';
    end if;
  end if;
  if v_has_override then
  perform core.wave3_require_scope(p_tenant_id,'inventory.reservations.manage',p_legal_entity_id,p_branch_id);
  perform core.wave3_require_scope(p_tenant_id,'inventory.stock.override',p_legal_entity_id,p_branch_id);
  v_request_hash := core.wave3_request_hash(v_command_name,p_command_id,p_tenant_id,p_legal_entity_id,p_branch_id,p_payload,p_expected_entity_version);
  v_replay := core.wave3_replay(p_tenant_id,v_command_name,p_command_id,p_idempotency_key,v_request_hash);
  if v_replay is not null then return v_replay;end if;
  v_policy := inventory.require_negative_stock_policy(p_tenant_id,p_legal_entity_id,p_branch_id,p_payload->'negative_stock_override');
  v_source_context := v_source_context || jsonb_build_object('negative_stock_override',jsonb_build_object(
    'policy_version',v_policy.version::text,'reason',trim(p_payload#>>'{negative_stock_override,reason}'),'policy_id',v_policy.id,'authorized_by',auth.uid()));
  end if;
  perform core.wave3_require_scope(""")
reserve = replace(reserve, "    v_allocate := least(v_requested, v_remaining, v_available)::numeric(20, 6);", """    if least(v_requested,v_remaining)>v_available then
      select tracking_mode into v_tracking from inventory.products where tenant_id=p_tenant_id and legal_entity_id=p_legal_entity_id and id=v_line.product_id;
      if v_tracking<>'none' then raise exception using errcode='55000',message='NEGATIVE_STOCK_TRACKING_REQUIRED';end if;
      v_basis := inventory.capture_negative_stock_basis(p_tenant_id,p_legal_entity_id,p_branch_id,v_order.warehouse_id,v_line.product_id,
        jsonb_build_object('sales_order_id',v_order_id,'sales_order_line_id',v_line.id,'command_id',p_command_id));
      v_available := v_remaining;
    end if;
    v_allocate := least(v_requested, v_remaining, v_available)::numeric(20, 6);""")
reserve = replace(reserve, "    if least(v_requested,v_remaining)>v_available then", "    if v_has_override and least(v_requested,v_remaining)>v_available then")
reserve = replace(reserve, "      update inventory.stock_balances set\n        allocated_quantity = allocated_quantity + v_allocate,", """      if v_balance.allocated_quantity+v_allocate>v_balance.on_hand_quantity then
        select * into v_val from inventory.stock_valuations where tenant_id=p_tenant_id and stock_balance_id=v_balance.id for update;
        perform inventory.authorize_negative_stock_projection(v_balance,v_val,v_policy.id,'reserve',v_order_id,v_line.id,p_command_id,v_request_id,
          v_allocate,trim(p_payload#>>'{negative_stock_override,reason}'),v_balance.on_hand_quantity,v_balance.allocated_quantity+v_allocate,v_val.carrying_value);
        v_used_override := true;
      end if;
      update inventory.stock_balances set
        allocated_quantity = allocated_quantity + v_allocate,""")
reserve = replace(reserve, "  update sales.sales_orders set\n    status = v_to_status", """  if v_used_override then v_warnings := v_warnings || jsonb_build_array('NEGATIVE_STOCK_OVERRIDDEN'); end if;
  update sales.sales_orders set
    status = v_to_status""")
reserve = replace(reserve, "'from_status', v_order.status, 'to_status', v_to_status,", "'from_status', case when v_order.status=v_to_status then null else v_order.status end, 'to_status', v_to_status,")

stock = extract(read("20260910135010_complete_delivery_receivables.sql"), "sales.flow_post_stock")
stock = replace(stock, " v_inventory uuid;v_cogs uuid;", """ v_negative_policy inventory.negative_stock_policy_versions%rowtype;v_basis inventory.negative_stock_cost_bases%rowtype;
 v_deficit_quantity numeric;v_provisional numeric;v_override bigint;v_mline uuid;v_def inventory.negative_stock_deficits%rowtype;
 v_inventory uuid;v_cogs uuid;""")
stock = replace(stock, "begin\n -- Lock stock products", """begin
 if p_kind='delivery' then perform pg_advisory_xact_lock(hashtextextended('negative-policy:'||v_t::text||':'||v_e::text,0));end if;
 -- Lock stock products""")
stock = replace(stock, " v_snapshot:=v_line->'snapshot';v_q:=(v_line->>'base_quantity')::numeric;", """ v_snapshot:=v_line->'snapshot';v_q:=(v_line->>'base_quantity')::numeric;v_mline:=gen_random_uuid();v_deficit_quantity:=0;v_provisional:=0;""")
stock = replace(stock, " if v_balance.on_hand_quantity<v_q or v_balance.allocated_quantity<v_q then raise exception using errcode='55000',message='INSUFFICIENT_STOCK';end if;\n v_cost:=case when v_q=v_balance.on_hand_quantity then v_value.carrying_value else round(v_value.carrying_value*v_q/v_balance.on_hand_quantity,6) end;", """ if v_balance.allocated_quantity<v_q then raise exception using errcode='55000',message='INSUFFICIENT_STOCK';end if;
 if v_product.tracking_mode='none' and v_balance.on_hand_quantity>0 then
  v_basis:=inventory.capture_negative_stock_basis(v_t,v_e,v_b,v_warehouse,v_product.id,jsonb_build_object('delivery_id',v_id,'delivery_line_id',v_line->>'id','command_id',p_command));
 end if;
 if v_balance.on_hand_quantity<v_q then
  if v_product.tracking_mode<>'none' then raise exception using errcode='55000',message='NEGATIVE_STOCK_TRACKING_REQUIRED';end if;
  v_negative_policy:=inventory.require_negative_stock_policy(v_t,v_e,v_b,v_res.source_context->'negative_stock_override');
  if not exists(select 1 from inventory.negative_stock_overrides a where a.tenant_id=v_t and a.balance_id=v_balance.id and a.effect='reserve'
   and a.source_id=(p_doc->>'sales_order_id')::uuid and a.source_line_id=v_ol.id and a.command_id=v_res.command_id
   and a.policy_id=v_negative_policy.id and a.created_by::text=v_res.source_context#>>'{negative_stock_override,authorized_by}'
   and a.reason=trim(v_res.source_context#>>'{negative_stock_override,reason}')) then
   raise exception using errcode='55000',message='NEGATIVE_STOCK_RESERVATION_AUTHORIZATION_REQUIRED';end if;
  v_basis:=inventory.capture_negative_stock_basis(v_t,v_e,v_b,v_warehouse,v_product.id,jsonb_build_object('delivery_id',v_id,'delivery_line_id',v_line->>'id','command_id',p_command));
  v_deficit_quantity:=v_q-greatest(v_balance.on_hand_quantity,0);
  v_provisional:=round(v_basis.carrying_value*v_deficit_quantity/v_basis.positive_quantity,6);
  v_cost:=case when v_balance.on_hand_quantity>0 then v_value.carrying_value else 0 end+v_provisional;
  v_override:=inventory.authorize_negative_stock_projection(v_balance,v_value,v_negative_policy.id,'issue',v_id,(v_line->>'id')::uuid,p_command,p_request,
   v_deficit_quantity,v_res.source_context#>>'{negative_stock_override,reason}',v_balance.on_hand_quantity-v_q,v_balance.allocated_quantity-v_q,v_value.carrying_value-v_cost);
  insert into inventory.negative_stock_deficits(tenant_id,legal_entity_id,branch_id,warehouse_id,product_id,issue_movement_line_id,policy_id,basis_id,override_id,
   quantity,provisional_value,inventory_account_id,cogs_account_id,posting_date,command_id,created_by)
  values(v_t,v_e,v_b,v_warehouse,v_product.id,v_mline,v_negative_policy.id,v_basis.id,v_override,v_deficit_quantity,v_provisional,
   v_product.inventory_account_id,v_product.cogs_account_id,v_date,p_command,auth.uid());
 else
  v_cost:=case when v_q=v_balance.on_hand_quantity then v_value.carrying_value else round(v_value.carrying_value*v_q/v_balance.on_hand_quantity,6) end;
 end if;""")
stock = replace(stock, " else update inventory.stock_balances set on_hand_quantity=on_hand_quantity+v_q,updated_by=auth.uid() where id=v_balance.id;end if;", """ else
  select * into v_def from inventory.negative_stock_deficits where tenant_id=v_t and issue_movement_line_id=v_original.id;
  if found then
   v_cost:=inventory.negative_stock_return_cost(v_original,v_mline,v_q,v_date,p_command,p_request);
   perform inventory.authorize_negative_stock_projection(v_balance,v_value,v_def.policy_id,'customer_return',v_id,(v_line->>'id')::uuid,p_command,p_request,
    v_q,'Source-linked customer return',v_balance.on_hand_quantity+v_q,v_balance.allocated_quantity,v_value.carrying_value+v_cost);
  end if;
  update inventory.stock_balances set on_hand_quantity=on_hand_quantity+v_q,updated_by=auth.uid() where id=v_balance.id;end if;""")
stock = replace(stock, " insert into inventory.stock_movement_lines(tenant_id,legal_entity_id,branch_id,stock_movement_id,warehouse_id,product_id,", " insert into inventory.stock_movement_lines(id,tenant_id,legal_entity_id,branch_id,stock_movement_id,warehouse_id,product_id,")
stock = replace(stock, " values(v_t,v_e,v_b,v_movement,v_warehouse,v_product.id,(v_line->>'id')::uuid,v_original.id,", " values(v_mline,v_t,v_e,v_b,v_movement,v_warehouse,v_product.id,(v_line->>'id')::uuid,v_original.id,")
stock = replace(stock, " if p_kind='sales_return' then\n select jl.account_id into v_inventory", """ if p_kind='sales_return' then
 if v_def.id is not null then v_inventory:=v_def.inventory_account_id;v_cogs:=v_def.cogs_account_id;
 else
 select jl.account_id into v_inventory""")
stock = replace(stock, " and j.source_type='delivery.stock' and a.account_type='expense';\n end if;", " and j.source_type='delivery.stock' and a.account_type='expense';\n end if;end if;")
stock = replace(stock, " v_original:=null;v_lot:=null;v_lb:=null;", " v_original:=null;v_lot:=null;v_lb:=null;v_def:=null;")

provenance = extract(read("20260919181407_inventory_receipt_provenance.sql"), "inventory.record_receipt_provenance")
provenance = replace(provenance, "begin\n if new.base_quantity=0", """begin
 if inventory.negative_stock_provenance(new) then return new;end if;
 if new.base_quantity=0""")
provenance = replace(provenance, " end loop;\n return new;\nend $$;", """ end loop;
 -- All legacy projection changes precede the movement insert. Capture only the
 -- aligned final positive quantity/value after normal provenance succeeds.
 if new.lot_id is null and cardinality(new.serial_ids)=0
  and exists(select 1 from inventory.products p where p.tenant_id=new.tenant_id and p.id=new.product_id and p.tracking_mode='none')
  and exists(select 1 from inventory.stock_balances b join inventory.stock_valuations v on v.tenant_id=b.tenant_id and v.stock_balance_id=b.id
   where b.tenant_id=new.tenant_id and b.warehouse_id=new.warehouse_id and b.product_id=new.product_id and b.on_hand_quantity>0 and v.carrying_value>=0) then
  perform inventory.capture_negative_stock_basis(new.tenant_id,new.legal_entity_id,new.branch_id,new.warehouse_id,new.product_id,jsonb_build_object('movement_line_id',new.id,'snapshot_stage','after_aligned_movement'));
 end if;
 return new;
end $$;""")

tail = f"""{MARKER}
-- Original helpers remain available internally with their original bodies.
alter function api.reserve_sales_order_stock(uuid,uuid,uuid,uuid,uuid,timestamptz,jsonb,bigint) rename to reserve_sales_order_stock_without_negative_policy;
revoke all on function api.reserve_sales_order_stock_without_negative_policy(uuid,uuid,uuid,uuid,uuid,timestamptz,jsonb,bigint) from public,anon,authenticated;
{reserve}
alter function sales.flow_post_stock(text,jsonb,uuid,uuid) rename to flow_post_stock_without_negative_policy;
revoke all on function sales.flow_post_stock_without_negative_policy(text,jsonb,uuid,uuid) from public,anon,authenticated;
{stock}
-- Trigger bindings resolve by OID. Reattach it to the additive dispatcher;
-- the renamed original trigger helper retains its byte-identical body.
alter function inventory.record_receipt_provenance() rename to record_receipt_provenance_without_negative_policy;
{provenance}
drop trigger receipt_provenance on inventory.stock_movement_lines;
create trigger receipt_provenance after insert on inventory.stock_movement_lines for each row execute function inventory.record_receipt_provenance();
-- Take policy before the original source/order locks, as reservation does.
alter function sales.flow_post(text,uuid,uuid,uuid,uuid,uuid,timestamptz,jsonb,bigint) rename to flow_post_without_negative_policy;
create function sales.flow_post(p_kind text,p_tenant_id uuid,p_legal_entity_id uuid,p_branch_id uuid,p_command_id uuid,p_idempotency_key uuid,
 p_client_timestamp timestamptz,p_payload jsonb,p_expected_entity_version bigint) returns jsonb
language plpgsql security definer set search_path='' as $$begin
 if p_kind='delivery' then perform pg_advisory_xact_lock(hashtextextended('negative-policy:'||p_tenant_id::text||':'||p_legal_entity_id::text,0));end if;
 return sales.flow_post_without_negative_policy(p_kind,p_tenant_id,p_legal_entity_id,p_branch_id,p_command_id,p_idempotency_key,p_client_timestamp,p_payload,p_expected_entity_version);
end $$;
{END_MARKER}
"""

previous = TARGET.read_text(encoding="utf-8")
body = previous.split(MARKER)[0]
after = previous.split(END_MARKER,1)[1] if END_MARKER in previous else ""
TARGET.write_text(body.rstrip() + "\n\n" + tail + after, encoding="utf-8")
print("Composed additive reservation, stock posting and provenance bodies.")
