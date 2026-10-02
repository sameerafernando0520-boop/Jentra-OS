-- UNAPPLIED. Contract 49; strict rollback tests precede installation.
create function core.wave3_source_descriptor(k text) returns jsonb
language sql immutable set search_path='' as $$
 select jsonb_build_object('schema',s,'table',tbl,'permission',permission,'child',child,'parent',parent,'cost',cost)
 from (values
 ('lead','crm','leads','crm.leads.view',null,null,false),
 ('opportunity','crm','opportunities','crm.opportunities.view',null,null,false),
 ('quotation','sales','quotations','sales.quotations.view','quotation_lines','quotation_id',false),
 ('sales_order','sales','sales_orders','sales.orders.view','sales_order_lines','sales_order_id',false),
 ('delivery','sales','deliveries','sales.deliveries.view','delivery_lines','document_id',true),
 ('sales_invoice','sales','sales_invoices','sales.invoices.view','sales_invoice_lines','document_id',false),
 ('customer_receipt','sales','customer_receipts','finance.receipts.view','customer_receipt_lines','document_id',false),
 ('sales_return','sales','sales_returns','sales.returns.view','sales_return_lines','document_id',true),
 ('purchase_requisition','procurement','requisitions','procurement.requisitions.manage','requisition_lines','requisition_id',false),
 ('rfq','procurement','rfqs','procurement.rfq.manage','rfq_lines','rfq_id',false),
 ('purchase_order','procurement','purchase_orders','procurement.orders.view','purchase_order_lines','order_id',false),
 ('goods_receipt','procurement','goods_receipts','procurement.receipts.post','goods_receipt_lines','receipt_id',true),
 ('supplier_bill','procurement','supplier_bills','procurement.bills.view','supplier_bill_lines','bill_id',false),
 ('payment_proposal','procurement','payment_proposals','finance.payments.manage',null,null,false),
 ('supplier_payment','procurement','supplier_payments','finance.payments.manage',null,null,false),
 ('purchase_return','procurement','purchase_returns','procurement.returns.post','purchase_return_lines','return_id',true),
 ('inventory_transfer','inventory','transfers','inventory.stock.view','transfer_lines','transfer_id',true),
 ('stock_count','inventory','stock_counts','inventory.adjustments.post',null,null,true),
 ('inventory_value_adjustment','inventory','value_adjustments','inventory.valuation.post',null,null,true),
 ('landed_extension','inventory','landed_extensions','inventory.valuation.post',null,null,true),
 ('inventory_disposition','inventory','stock_dispositions','inventory.dispositions.post',null,null,true),
 ('manual_journal','finance','manual_journals','finance.view',null,null,false),
 ('budget','finance','budget_versions','finance.view',null,null,false),
 ('bank_statement','finance','bank_statements','finance.view','bank_statement_lines','statement_id',false),
 ('bank_match','finance','bank_matches','finance.view',null,null,false)
 ) x(kind,s,tbl,permission,child,parent,cost) where kind=k;
$$;
revoke all on function core.wave3_source_descriptor(text) from public,anon,authenticated;

create function core.wave3_source_header(t uuid,e uuid,b uuid,k text,i uuid) returns jsonb
language plpgsql stable security definer set search_path='' as $$
declare cfg jsonb:=core.wave3_source_descriptor(k);d jsonb;actual uuid;leg jsonb;target uuid;begin
 if cfg is null or i is null or e is null or b is null then
  raise exception using errcode='42501',message='SOURCE_UNAVAILABLE';end if;
 perform core.wave3_require_scope(t,cfg->>'permission',e,b);
 execute format('select to_jsonb(d) from %I.%I d where d.tenant_id=$1 and d.legal_entity_id=$2 and d.id=$3',
  cfg->>'schema',cfg->>'table') into d using t,e,i;
 if d is null then raise exception using errcode='42501',message='SOURCE_UNAVAILABLE';end if;
 actual:=(d->>'branch_id')::uuid;
 if actual is not null then perform core.require_permission(t,cfg->>'permission',e,actual);end if;
 if (cfg->>'cost')::boolean then
  perform core.wave3_require_scope(t,'inventory.stock.view',e,b);
  perform core.wave3_require_scope(t,'inventory.cost.view',e,b);
  if actual is not null then
   perform core.require_permission(t,'inventory.stock.view',e,actual);
   perform core.require_permission(t,'inventory.cost.view',e,actual);end if;
 end if;
 if k in('inventory_value_adjustment','landed_extension') then
  for leg in select value from jsonb_array_elements(coalesce(d#>'{detail,legs}','[]')) loop
   foreach target in array array[(leg->>'branch_id')::uuid,(leg->>'destination_branch_id')::uuid] loop
    if target is not null then
     perform core.require_permission(t,'inventory.stock.view',e,target);
     perform core.require_permission(t,'inventory.cost.view',e,target);
     perform core.require_permission(t,'inventory.valuation.post',e,target);
    end if;
   end loop;
  end loop;
 end if;
 return d;
exception when insufficient_privilege then raise exception using errcode='42501',message='SOURCE_UNAVAILABLE';
end $$;
revoke all on function core.wave3_source_header(uuid,uuid,uuid,text,uuid) from public,anon,authenticated;

-- The file layer has no selected desktop branch. Recheck the actual source
-- branch and never let file permission alone reveal an aggregate.
create function core.wave3_attachment_access(t uuid,k text,i uuid) returns boolean
language plpgsql stable security definer set search_path='' as $$
declare cfg jsonb:=core.wave3_source_descriptor(k);e uuid;b uuid;d jsonb;leg jsonb;target uuid;begin
 if auth.uid() is null or t is null or i is null or cfg is null or not core.is_tenant_member(t) then return false;end if;
 execute format('select to_jsonb(d) from %I.%I d where tenant_id=$1 and id=$2',cfg->>'schema',cfg->>'table')
  into d using t,i;
 e:=(d->>'legal_entity_id')::uuid;b:=(d->>'branch_id')::uuid;
 if e is null or not core.has_permission(t,cfg->>'permission',e,b) then return false;end if;
 if (cfg->>'cost')::boolean and (not core.has_permission(t,'inventory.stock.view',e,b)
  or not core.has_permission(t,'inventory.cost.view',e,b)) then return false;end if;
 if k in('inventory_value_adjustment','landed_extension') then
  for leg in select value from jsonb_array_elements(coalesce(d#>'{detail,legs}','[]')) loop
   foreach target in array array[(leg->>'branch_id')::uuid,(leg->>'destination_branch_id')::uuid] loop
    if target is not null and (not core.has_permission(t,'inventory.stock.view',e,target)
     or not core.has_permission(t,'inventory.cost.view',e,target)
     or not core.has_permission(t,'inventory.valuation.post',e,target)) then return false;end if;
   end loop;
  end loop;
 end if;
 return true;
end $$;
revoke all on function core.wave3_attachment_access(uuid,text,uuid) from public,anon,authenticated;

create or replace function core.validate_attachment_aggregate()
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
    when 'lead' then core.wave3_attachment_access(new.tenant_id,new.aggregate_type,new.aggregate_id)
    when 'opportunity' then core.wave3_attachment_access(new.tenant_id,new.aggregate_type,new.aggregate_id)
    when 'quotation' then core.wave3_attachment_access(new.tenant_id,new.aggregate_type,new.aggregate_id)
    when 'sales_order' then core.wave3_attachment_access(new.tenant_id,new.aggregate_type,new.aggregate_id)
    when 'delivery' then core.wave3_attachment_access(new.tenant_id,new.aggregate_type,new.aggregate_id)
    when 'sales_invoice' then core.wave3_attachment_access(new.tenant_id,new.aggregate_type,new.aggregate_id)
    when 'customer_receipt' then core.wave3_attachment_access(new.tenant_id,new.aggregate_type,new.aggregate_id)
    when 'sales_return' then core.wave3_attachment_access(new.tenant_id,new.aggregate_type,new.aggregate_id)
    when 'purchase_requisition' then core.wave3_attachment_access(new.tenant_id,new.aggregate_type,new.aggregate_id)
    when 'rfq' then core.wave3_attachment_access(new.tenant_id,new.aggregate_type,new.aggregate_id)
    when 'purchase_order' then core.wave3_attachment_access(new.tenant_id,new.aggregate_type,new.aggregate_id)
    when 'goods_receipt' then core.wave3_attachment_access(new.tenant_id,new.aggregate_type,new.aggregate_id)
    when 'supplier_bill' then core.wave3_attachment_access(new.tenant_id,new.aggregate_type,new.aggregate_id)
    when 'payment_proposal' then core.wave3_attachment_access(new.tenant_id,new.aggregate_type,new.aggregate_id)
    when 'supplier_payment' then core.wave3_attachment_access(new.tenant_id,new.aggregate_type,new.aggregate_id)
    when 'purchase_return' then core.wave3_attachment_access(new.tenant_id,new.aggregate_type,new.aggregate_id)
    when 'inventory_transfer' then core.wave3_attachment_access(new.tenant_id,new.aggregate_type,new.aggregate_id)
    when 'stock_count' then core.wave3_attachment_access(new.tenant_id,new.aggregate_type,new.aggregate_id)
    when 'inventory_value_adjustment' then core.wave3_attachment_access(new.tenant_id,new.aggregate_type,new.aggregate_id)
    when 'manual_journal' then core.wave3_attachment_access(new.tenant_id,new.aggregate_type,new.aggregate_id)
    when 'budget' then core.wave3_attachment_access(new.tenant_id,new.aggregate_type,new.aggregate_id)
    when 'bank_statement' then core.wave3_attachment_access(new.tenant_id,new.aggregate_type,new.aggregate_id)
    when 'bank_match' then core.wave3_attachment_access(new.tenant_id,new.aggregate_type,new.aggregate_id)
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
create function core.wave3_document_rows(t uuid,e uuid,b uuid,k text,filters jsonb,n integer,after_id uuid) returns jsonb
language plpgsql stable security definer set search_path='' as $$
declare cfg jsonb:=core.wave3_source_descriptor(k);rows jsonb;search text:=coalesce(filters->>'search','');begin
 if cfg is null or e is null or b is null or n not between 1 and 10001 or length(search)>200
  or jsonb_typeof(filters) is distinct from 'object'
  or exists(select 1 from jsonb_object_keys(filters)x where x not in('search','status','from_date','to_date'))
  or length(coalesce(filters->>'status',''))>80
  or ((filters->>'from_date')::date>(filters->>'to_date')::date) then
  raise exception using errcode='22023',message='DOCUMENT_FILTER_INVALID';end if;
 perform core.wave3_require_scope(t,cfg->>'permission',e,b);
 if (cfg->>'cost')::boolean then perform core.wave3_require_scope(t,'inventory.cost.view',e,b);
  perform core.wave3_require_scope(t,'inventory.stock.view',e,b);end if;
 execute format($q$select coalesce(jsonb_agg(sales.flow_exact_json(j)-'snapshot'-'source_snapshot'-'lines' order by id),'[]') from (
  select d.id,to_jsonb(d) j from %I.%I d
  where d.tenant_id=$1 and d.legal_entity_id=$2 and (d.branch_id=$3 or d.branch_id is null)
   and ($10 not in('inventory_value_adjustment','landed_extension') or core.wave3_attachment_access($1,$10,d.id))
   and ($4 is null or d.id>$4)
   and ($5='' or position(lower($5) in lower(concat_ws(' ',to_jsonb(d)->>'code',to_jsonb(d)->>'document_number',
    to_jsonb(d)->>'name',to_jsonb(d)->>'reference',to_jsonb(d)->>'supplier_reference'))) > 0)
   and ($6 is null or coalesce(to_jsonb(d)->>'status','posted')=$6)
   and ($7 is null or left(coalesce(to_jsonb(d)->>'document_date',to_jsonb(d)->>'posting_date',to_jsonb(d)->>'created_at'),10)::date >= $7)
   and ($8 is null or left(coalesce(to_jsonb(d)->>'document_date',to_jsonb(d)->>'posting_date',to_jsonb(d)->>'created_at'),10)::date <= $8)
  order by d.id limit $9)q$q$,cfg->>'schema',cfg->>'table') into rows
 using t,e,b,after_id,search,nullif(filters->>'status',''),(filters->>'from_date')::date,(filters->>'to_date')::date,n,k;
 return rows;
end $$;
revoke all on function core.wave3_document_rows(uuid,uuid,uuid,text,jsonb,integer,uuid) from public,anon,authenticated;

create policy wave3_attachment_source_read on core.attachments as restrictive
 for select to authenticated using (
  core.wave3_source_descriptor(aggregate_type) is null
  or core.wave3_attachment_access(tenant_id,aggregate_type,aggregate_id)
 );

create function core.wave3_storage_access(path text,needs_ready boolean default true) returns boolean
language plpgsql stable security definer set search_path='' as $$
declare k text:=split_part(path,'/',2);a core.attachments%rowtype;t uuid;begin
 if core.wave3_source_descriptor(k) is null then return true;end if;
 t:=core.storage_object_tenant(path);
 if t is null or auth.uid() is null then return false;end if;
 select * into a from core.attachments where tenant_id=t and object_path=path
  and aggregate_type=k and aggregate_id=split_part(path,'/',3)::uuid;
 if not found or (needs_ready and a.upload_status<>'ready')
  or (not needs_ready and a.upload_status<>'staged') then return false;end if;
 return core.wave3_attachment_access(t,k,a.aggregate_id);
exception when invalid_text_representation then return false;
end $$;
revoke all on function core.wave3_storage_access(text,boolean) from public,anon,authenticated;
-- RLS expressions execute as the caller. These policy predicates expose only
-- the fixed catalogue and current-access booleans, never source document data.
grant execute on function core.wave3_source_descriptor(text),
 core.wave3_attachment_access(uuid,text,uuid),core.wave3_storage_access(text,boolean) to authenticated;
create policy wave3_storage_source_read on storage.objects as restrictive
 for select to authenticated using (core.wave3_storage_access(name,true));
create policy wave3_storage_source_insert on storage.objects as restrictive
 for insert to authenticated with check (core.wave3_storage_access(name,false));
create policy wave3_storage_no_mutation on storage.objects as restrictive
 for update to authenticated using (core.wave3_source_descriptor(split_part(name,'/',2)) is null)
 with check (core.wave3_source_descriptor(split_part(name,'/',2)) is null);

create or replace function api.register_attachment(
 p_tenant_id uuid,p_payload jsonb,p_idempotency_key uuid default gen_random_uuid())
returns jsonb language plpgsql security definer set search_path='' as $$
declare k text:=p_payload->>'aggregate_type';begin
 if core.wave3_source_descriptor(k) is not null and
  not core.wave3_attachment_access(p_tenant_id,k,(p_payload->>'aggregate_id')::uuid) then
  raise exception using errcode='42501',message='SOURCE_UNAVAILABLE';end if;
 return core.register_attachment_impl(p_tenant_id,p_payload,p_idempotency_key);
end $$;
create or replace function api.complete_attachment(
 p_tenant_id uuid,p_attachment_id uuid,p_checksum_sha256 text,p_expected_version bigint,
 p_idempotency_key uuid default gen_random_uuid())
returns jsonb language plpgsql security definer set search_path='' as $$
declare a core.attachments%rowtype;begin
 select * into a from core.attachments where tenant_id=p_tenant_id and id=p_attachment_id;
 if a.id is not null and core.wave3_source_descriptor(a.aggregate_type) is not null and
  not core.wave3_attachment_access(p_tenant_id,a.aggregate_type,a.aggregate_id) then
  raise exception using errcode='42501',message='SOURCE_UNAVAILABLE';end if;
 return core.complete_attachment_impl(p_tenant_id,p_attachment_id,p_checksum_sha256,p_expected_version,p_idempotency_key);
end $$;

create function api.reject_wave3_attachment(p_tenant_id uuid,p_legal_entity_id uuid,p_branch_id uuid,
 p_command_id uuid,p_idempotency_key uuid,p_client_timestamp timestamptz,p_payload jsonb,
 p_expected_entity_version bigint default null) returns jsonb
language plpgsql security definer set search_path='' as $$
declare a core.attachments%rowtype;before jsonb;result jsonb;h text;req uuid:=gen_random_uuid();begin
 perform core.wave3_require_scope(p_tenant_id,'core.files.manage',p_legal_entity_id,p_branch_id);
 select * into a from core.attachments where tenant_id=p_tenant_id and id=(p_payload->>'id')::uuid for update;
 if a.id is null or core.wave3_source_descriptor(a.aggregate_type) is null or
  not core.wave3_attachment_access(p_tenant_id,a.aggregate_type,a.aggregate_id) then
  raise exception using errcode='42501',message='SOURCE_UNAVAILABLE';end if;
 h:=core.wave3_request_hash('files.wave3.reject',p_command_id,p_tenant_id,p_legal_entity_id,p_branch_id,p_payload,p_expected_entity_version);
 result:=core.wave3_replay(p_tenant_id,'files.wave3.reject',p_command_id,p_idempotency_key,h);
 if result is not null then return result;end if;
 if length(btrim(coalesce(p_payload->>'reason',''))) not between 3 and 1000 or a.upload_status='rejected' then
  raise exception using errcode='22023',message='ATTACHMENT_REJECTION_INVALID';end if;
 perform core.wave3_assert_expected_version(a.version,p_expected_entity_version,to_jsonb(a));
 before:=to_jsonb(a);
 update core.attachments set upload_status='rejected',updated_by=auth.uid() where id=a.id returning * into a;
 result:=jsonb_build_object('id',a.id,'version',a.version,'status','rejected','reason',p_payload->>'reason',
  'aggregate_type',a.aggregate_type,'aggregate_id',a.aggregate_id);
 return core.wave3_finish_command(p_tenant_id,'files.wave3.reject',p_command_id,'attachment',a.id,p_idempotency_key,h,before,result,
  p_legal_entity_id,p_branch_id,'{}',jsonb_build_object('to_status','rejected','reason',p_payload->>'reason'),
  jsonb_build_array(jsonb_build_object('topic','files.wave3.rejected','payload',result)),'[]',req,req);
end $$;
revoke all on function api.reject_wave3_attachment(uuid,uuid,uuid,uuid,uuid,timestamptz,jsonb,bigint) from public,anon,authenticated;
grant execute on function api.reject_wave3_attachment(uuid,uuid,uuid,uuid,uuid,timestamptz,jsonb,bigint) to authenticated;

create function api.wave3_document_page(p_tenant_id uuid,p_legal_entity_id uuid,p_branch_id uuid,p_kind text,
 p_filters jsonb default '{}'::jsonb,p_after uuid default null) returns jsonb
language plpgsql stable security definer set search_path='' as $$declare rows jsonb;cursor text;begin
 rows:=core.wave3_document_rows(p_tenant_id,p_legal_entity_id,p_branch_id,p_kind,p_filters,51,p_after);
 if jsonb_array_length(rows)>50 then cursor:=rows->49->>'id';rows:=rows-50;end if;
 return jsonb_build_object('tenant_id',p_tenant_id,'legal_entity_id',p_legal_entity_id,'branch_id',p_branch_id,
  'kind',p_kind,'filters',p_filters,'basis','current','generated_at',statement_timestamp(),
  'date_basis','document_date_or_posting_date_or_created_utc','items',rows,'next_cursor',cursor);
end $$;

create function api.wave3_document_evidence(p_tenant_id uuid,p_legal_entity_id uuid,p_branch_id uuid,
 p_kind text,p_id uuid,p_after uuid default null) returns jsonb
language plpgsql stable security definer set search_path='' as $$
declare d jsonb;cfg jsonb;children jsonb:='[]';cursor text;timeline jsonb;files jsonb:='[]';result jsonb;
 receipt_id uuid;
 cursor_valid boolean:=false;begin
 d:=core.wave3_source_header(p_tenant_id,p_legal_entity_id,p_branch_id,p_kind,p_id);
 if p_kind='inventory_value_adjustment' then
  select r.id into receipt_id from inventory.stock_movement_lines l
   join procurement.goods_receipts r on r.tenant_id=l.tenant_id and r.stock_movement_id=l.stock_movement_id
   where l.tenant_id=p_tenant_id and l.id=(d->>'receipt_line_id')::uuid
    and r.legal_entity_id=p_legal_entity_id and r.branch_id=(d->>'branch_id')::uuid;
  if receipt_id is null then raise exception using errcode='55000',message='SOURCE_LINEAGE_INVALID';end if;
  d:=d||jsonb_build_object('receipt_id',receipt_id);
 end if;
 cfg:=core.wave3_source_descriptor(p_kind);
 if cfg->>'child' is not null then
  if p_after is not null then
   execute format('select exists(select 1 from %I.%I where tenant_id=$1 and %I=$2 and id=$3)',
    cfg->>'schema',cfg->>'child',cfg->>'parent') into cursor_valid using p_tenant_id,p_id,p_after;
  end if;
  if p_after is not null and not cursor_valid then
   raise exception using errcode='22023',message='DOCUMENT_CURSOR_INVALID';end if;
  execute format('select coalesce(jsonb_agg(sales.flow_exact_json(j) order by id),''[]'') from
   (select l.id,to_jsonb(l) j from %I.%I l where l.tenant_id=$1 and l.%I=$2 and ($3 is null or l.id>$3) order by l.id limit 51)q',
   cfg->>'schema',cfg->>'child',cfg->>'parent') into children using p_tenant_id,p_id,p_after;
  if jsonb_array_length(children)>50 then cursor:=children->49->>'id';children:=children-50;end if;
 elsif p_kind in('stock_count','inventory_disposition') then
  if p_after is not null and not exists(select 1 from jsonb_array_elements(d->'lines') x
   where x->>'line_id'=p_after::text) then
   raise exception using errcode='22023',message='DOCUMENT_CURSOR_INVALID';end if;
  select coalesce(jsonb_agg(x order by x->>'line_id'),'[]') into children from
   (select value x from jsonb_array_elements(d->'lines')
    where p_after is null or (value->>'line_id')::uuid>p_after
    order by value->>'line_id' limit 51)q;
  if jsonb_array_length(children)>50 then cursor:=children->49->>'line_id';children:=children-50;end if;
 elsif p_after is not null then
  raise exception using errcode='22023',message='DOCUMENT_CURSOR_INVALID';
 end if;
 select coalesce(jsonb_agg(jsonb_build_object('id',r.id,'command_id',r.command_id,'request_id',r.request_id,
  'correlation_id',r.correlation_id,'completed_at',r.completed_at,'aggregate_type',r.aggregate_type) order by r.id),'[]')
 into timeline from (select * from core.command_receipts where tenant_id=p_tenant_id and aggregate_id=p_id order by id limit 51)r;
 if jsonb_array_length(timeline)>50 then raise exception using errcode='54000',message='SOURCE_TIMELINE_LIMIT';end if;
 if core.has_permission(p_tenant_id,'core.files.view',p_legal_entity_id,p_branch_id)
  or core.has_permission(p_tenant_id,'core.files.manage',p_legal_entity_id,p_branch_id) then
  select coalesce(jsonb_agg(to_jsonb(q) order by id),'[]') into files from (
   select id,file_name,mime_type,byte_size::text,object_path,upload_status,version,created_at from core.attachments
   where tenant_id=p_tenant_id and aggregate_type=p_kind and aggregate_id=p_id order by id limit 51)q;
  if jsonb_array_length(files)>50 then raise exception using errcode='54000',message='SOURCE_ATTACHMENT_LIMIT';end if;
 end if;
 result:=jsonb_build_object('tenant_id',p_tenant_id,'legal_entity_id',p_legal_entity_id,'branch_id',p_branch_id,
  'kind',p_kind,'id',p_id,'generated_at',statement_timestamp(),'header',sales.flow_exact_json(d)-'snapshot'-'source_snapshot'-'lines',
  'items',children,'next_cursor',cursor,'commands',timeline,'attachments',files);
 if octet_length(result::text)>1048576 then raise exception using errcode='54000',message='SOURCE_EVIDENCE_LIMIT';end if;
 return result;
end $$;

create table core.operational_reports(
 id uuid primary key,tenant_id uuid not null,legal_entity_id uuid not null,branch_id uuid not null,
 kind text not null,evidence jsonb not null,created_by uuid not null references auth.users(id),created_at timestamptz not null default now(),
 unique(tenant_id,id),foreign key(tenant_id,legal_entity_id) references core.legal_entities(tenant_id,id),
 foreign key(tenant_id,branch_id) references core.branches(tenant_id,id)
);
alter table core.operational_reports enable row level security;
alter table core.operational_reports force row level security;
revoke all on core.operational_reports from public,anon,authenticated;
create index operational_reports_scope_idx on core.operational_reports(tenant_id,legal_entity_id,branch_id,id);
create index operational_reports_actor_idx on core.operational_reports(created_by);
create trigger immutable before update or delete on core.operational_reports for each row execute function workflow.reject_history_mutation();

create function core.operational_report_access(t uuid,e uuid,b uuid,kind text,p jsonb) returns void
language plpgsql stable security definer set search_path='' as $$declare cfg jsonb;permission text;begin
 case kind
 when 'current_list' then
  cfg:=core.wave3_source_descriptor(p->>'document_kind');
  if cfg is null then raise exception using errcode='22023',message='OPERATIONAL_REPORT_KIND_INVALID';end if;
  perform core.wave3_require_scope(t,cfg->>'permission',e,b);
  if (cfg->>'cost')::boolean then
   perform core.wave3_require_scope(t,'inventory.stock.view',e,b);
   perform core.wave3_require_scope(t,'inventory.cost.view',e,b);end if;
 when 'customer_statement' then perform core.wave3_require_scope(t,'finance.receivables.view',e,b);
 when 'supplier_statement' then
  if not finance.payable_read_allowed(t,e,b) then raise exception using errcode='42501',message='SOURCE_UNAVAILABLE';end if;
  select allowed.code into permission from unnest(array['procurement.bills.view','procurement.bills.manage','procurement.bills.post',
   'finance.payments.manage','finance.payments.post','finance.payments.allocate','finance.payments.reverse']) allowed(code)
   where core.has_permission(t,allowed.code,e,b) limit 1;
  perform core.wave3_require_scope(t,permission,e,b);
 when 'bank_reconciliation' then perform core.wave3_require_scope(t,'finance.view',e,b);
 else raise exception using errcode='22023',message='OPERATIONAL_REPORT_KIND_INVALID';end case;
end $$;
revoke all on function core.operational_report_access(uuid,uuid,uuid,text,jsonb) from public,anon,authenticated;

create function finance.build_branch_cash_controls(t uuid,e uuid,b uuid,d date) returns jsonb
language plpgsql stable security definer set search_path='' as $$
declare bank record;statement finance.bank_statements%rowtype;gl jsonb;sl jsonb;rows jsonb:='[]';sources jsonb:='[]';
 book numeric;ug numeric;us numeric;sv numeric;bad integer;n integer:=0;status text;base text;begin
 select currency_code into base from core.legal_entities where tenant_id=t and id=e;
 for bank in select * from finance.cash_bank_accounts where tenant_id=t and legal_entity_id=e and branch_id=b order by id loop
  n:=n+1;if n>500 then raise exception using errcode='54000',message='CLOSE_CASH_ACCOUNT_LIMIT';end if;
  select coalesce(jsonb_agg(to_jsonb(q) order by id),'[]') into gl from (
   select l.id,j.id journal_id,j.command_id,j.source_type,j.source_id,l.posting_date,bank.id bank_id,
    bank.branch_id branch_id,bank.currency_code currency_code,
    (case when bank.currency_code=base then l.base_debit-l.base_credit
     else l.transaction_debit-l.transaction_credit end)::text value,
    (bank.currency_code<>base and j.currency_code<>bank.currency_code) invalid_currency,
    exists(select 1 from finance.bank_matches m where m.tenant_id=t and l.id=any(m.journal_line_ids)
     and m.posting_date<=d and not exists(select 1 from finance.bank_match_reversals r
      where r.tenant_id=t and r.match_id=m.id and r.posting_date<=d)) matched
   from finance.journal_lines l join finance.journal_entries j on j.tenant_id=l.tenant_id and j.id=l.journal_entry_id
   where l.tenant_id=t and l.legal_entity_id=e and l.branch_id=bank.branch_id
    and l.account_id=bank.account_id and j.status='posted' and l.posting_date<=d order by l.id limit 10001)q;
  select coalesce(jsonb_agg(to_jsonb(q) order by id),'[]') into sl from (
   select l.id,l.statement_id,l.bank_id,l.posting_date,bank.branch_id branch_id,bank.currency_code currency_code,
    l.reference,l.amount::text value,'bank_statement_line'::text source_type,l.id source_id,
    exists(select 1 from finance.bank_matches m where m.tenant_id=t and l.id=any(m.statement_line_ids)
     and m.posting_date<=d and not exists(select 1 from finance.bank_match_reversals r
      where r.tenant_id=t and r.match_id=m.id and r.posting_date<=d)) matched
   from finance.bank_statement_lines l join finance.bank_statements s on s.tenant_id=l.tenant_id and s.id=l.statement_id
   where l.tenant_id=t and l.bank_id=bank.id and l.posting_date<=d and s.end_date<=d
   order by l.id limit 10001)q;
  if greatest(jsonb_array_length(gl),jsonb_array_length(sl))>10000 then raise exception using errcode='54000',message='CLOSE_CASH_INPUT_LIMIT';end if;
  select coalesce(sum((x->>'value')::numeric),0),coalesce(sum((x->>'value')::numeric) filter(where not (x->>'matched')::boolean),0),
   count(*) filter(where (x->>'invalid_currency')::boolean) into book,ug,bad from jsonb_array_elements(gl)x;
  select coalesce(sum((x->>'value')::numeric) filter(where not (x->>'matched')::boolean),0) into us from jsonb_array_elements(sl)x;
  select * into statement from finance.bank_statements where tenant_id=t and bank_id=bank.id and end_date<=d
   order by end_date desc,created_at desc,id desc limit 1;
  sv:=coalesce(statement.closing,0)-us+ug;
  status:=case when bank.account_kind='cash' then 'ledger_only'
   when bad>0 then 'currency_basis_invalid'
   when exists(select 1 from finance.cash_bank_accounts cb where cb.tenant_id=t and cb.legal_entity_id=e
    and cb.branch_id=bank.branch_id and cb.account_id=bank.account_id and cb.currency_code=bank.currency_code
    and cb.id<>bank.id and (cb.status='active' or exists(select 1 from finance.bank_statements bs where bs.tenant_id=t and bs.bank_id=cb.id))) then 'ambiguous_basis'
   when statement.id is null or statement.end_date<>d then 'statement_coverage_required'
   when sv<>book then 'difference' else 'reconciled' end;
  rows:=rows||jsonb_build_array(jsonb_build_object('id','cash:'||bank.id,'component_key','cash:'||bank.id,
   'kind','CASH','branch_id',bank.branch_id,'name',bank.name,'currency_code',bank.currency_code,'status',status,
   'accounts',jsonb_build_array(jsonb_build_object('id',bank.account_id,'code',bank.code,'name',bank.name)),
   'subledger_value',case when bank.account_kind='cash' then book::text else sv::text end,'gl_value',book::text,
   'difference',case when bank.account_kind='cash' then '0' else (sv-book)::text end,
   'difference_count',case when status in('reconciled','ledger_only') then 0 else 1 end,
   'statement_id',statement.id,'statement_end',statement.end_date,'statement_closing',coalesce(statement.closing,0)::text,
   'unmatched_book',ug::text,'unmatched_bank',us::text));
  select sources||coalesce(jsonb_agg(x||jsonb_build_object('id','cash:'||bank.id||':'||(x->>'id'),
   'component_key','cash:'||bank.id,'origin','journal') order by x->>'id'),'[]') into sources from jsonb_array_elements(gl)x;
  select sources||coalesce(jsonb_agg(x||jsonb_build_object('id','bank:'||bank.id||':'||(x->>'id'),
   'component_key','cash:'||bank.id,'origin','bank') order by x->>'id'),'[]') into sources from jsonb_array_elements(sl)x;
  if jsonb_array_length(sources)>50000 then raise exception using errcode='54000',message='CLOSE_REVIEW_OUTPUT_LIMIT';end if;
 end loop;
 return jsonb_build_object('controls',rows,'sources',sources);
end $$;
revoke all on function finance.build_branch_cash_controls(uuid,uuid,uuid,date) from public,anon,authenticated;

create function api.generate_operational_report(p_tenant_id uuid,p_legal_entity_id uuid,p_branch_id uuid,
 p_command_id uuid,p_idempotency_key uuid,p_client_timestamp timestamptz,p_payload jsonb,p_expected_entity_version bigint default null) returns jsonb
language plpgsql security definer set search_path='' as $$
declare p jsonb:=p_payload;k text:=p->>'kind';id uuid:=(p->>'id')::uuid;d date:=(p->>'as_of')::date;
 rows jsonb;aging jsonb:='[]';data jsonb;summary jsonb;evidence jsonb;result jsonb;h text;req uuid:=gen_random_uuid();currency text;begin
 perform core.operational_report_access(p_tenant_id,p_legal_entity_id,p_branch_id,k,p);
 if id is null or d is null or d>(statement_timestamp() at time zone 'UTC')::date then
  raise exception using errcode='22023',message='OPERATIONAL_REPORT_INPUT_INVALID';end if;
 h:=core.wave3_request_hash('operations.report',p_command_id,p_tenant_id,p_legal_entity_id,p_branch_id,p,p_expected_entity_version);
 result:=core.wave3_replay(p_tenant_id,'operations.report',p_command_id,p_idempotency_key,h);
 if result is not null then return result;end if;
 if k='current_list' and d<>(statement_timestamp() at time zone 'UTC')::date then
  raise exception using errcode='22023',message='CURRENT_LIST_HAS_NO_HISTORICAL_BASIS';end if;
 perform core.wave3_assert_expected_version(0,p_expected_entity_version,'{}');
 select le.currency_code into currency from core.legal_entities le
 where le.tenant_id=p_tenant_id and le.id=p_legal_entity_id;
 if k='current_list' then
  rows:=core.wave3_document_rows(p_tenant_id,p_legal_entity_id,p_branch_id,p->>'document_kind',coalesce(p->'filters','{}'),10001,null);
 elsif k in('customer_statement','supplier_statement') then
  if not exists(select 1 from crm.parties party where party.tenant_id=p_tenant_id and party.id=(p->>'party_id')::uuid) then
   raise exception using errcode='42501',message='SOURCE_UNAVAILABLE';end if;
  if k='customer_statement' then data:=api.customer_statement(p_tenant_id,p_legal_entity_id,p_branch_id,(p->>'party_id')::uuid,p->>'currency_code',d,
   case when p ? 'bucket_days' then array(select value::integer from jsonb_array_elements_text(p->'bucket_days')) else array[30,60,90] end);
  else data:=api.supplier_statement(p_tenant_id,p_legal_entity_id,p_branch_id,(p->>'party_id')::uuid,p->>'currency_code',d,
   case when p ? 'bucket_days' then array(select value::integer from jsonb_array_elements_text(p->'bucket_days')) else array[30,60,90] end);end if;
  rows:=data->'rows';aging:=data->'aging';
 else data:=finance.build_branch_cash_controls(p_tenant_id,p_legal_entity_id,p_branch_id,d);
  rows:=data->'controls';end if;
 if jsonb_array_length(rows)>10000 then raise exception using errcode='54000',message='OPERATIONAL_REPORT_ROW_LIMIT';end if;
 summary:=jsonb_build_object('id',id,'version',1,'tenant_id',p_tenant_id,'legal_entity_id',p_legal_entity_id,'branch_id',p_branch_id,
  'kind',k,'status','generated','basis',case k when 'current_list' then 'current' else 'posting_date' end,'as_of',d,'generated_at',statement_timestamp(),
  'base_currency_code',currency,'currency_code',p->>'currency_code','currency_meaning',case k when 'current_list' then 'row_currency_no_mixed_total' else 'posted_transaction_and_base' end,
  'row_count',jsonb_array_length(rows),'inputs',p-'id','open_amount',data->>'open_amount','open_base_amount',data->>'open_base_amount');
 evidence:=jsonb_build_object('summary',summary,'rows',rows,'aging',aging,'sources',coalesce(data->'sources','[]'));
 if octet_length(evidence::text)>8388608 then raise exception using errcode='54000',message='OPERATIONAL_REPORT_EVIDENCE_LIMIT';end if;
 insert into core.operational_reports(id,tenant_id,legal_entity_id,branch_id,kind,evidence,created_by)
 values(id,p_tenant_id,p_legal_entity_id,p_branch_id,k,evidence,auth.uid());
 return core.wave3_finish_command(p_tenant_id,'operations.report',p_command_id,'operational_report',id,p_idempotency_key,h,null,summary,
  p_legal_entity_id,p_branch_id,'{}',jsonb_build_object('to_status','generated'),
  jsonb_build_array(jsonb_build_object('topic','operations.report.generated','payload',summary)),'[]',req,req);
end $$;

create function core.operational_report_rows_access(t uuid,e uuid,b uuid,evidence jsonb) returns void
language plpgsql stable security definer set search_path='' as $$declare row jsonb;k text:=evidence#>>'{summary,inputs,document_kind}';begin
 if k in('inventory_value_adjustment','landed_extension') then
  for row in select value from jsonb_array_elements(evidence->'rows') loop
   perform core.wave3_source_header(t,e,b,k,(row->>'id')::uuid);
  end loop;
 end if;
end $$;
revoke all on function core.operational_report_rows_access(uuid,uuid,uuid,jsonb) from public,anon,authenticated;

create function api.operational_report_page(p_tenant_id uuid,p_legal_entity_id uuid,p_branch_id uuid,
 p_id uuid,p_section text default 'rows',p_after integer default 0) returns jsonb
language plpgsql stable security definer set search_path='' as $$declare r core.operational_reports%rowtype;rows jsonb;n integer;begin
 select * into r from core.operational_reports where tenant_id=p_tenant_id and legal_entity_id=p_legal_entity_id and branch_id=p_branch_id and id=p_id;
 if not found then raise exception using errcode='42501',message='SOURCE_UNAVAILABLE';end if;
 perform core.operational_report_access(p_tenant_id,p_legal_entity_id,p_branch_id,r.kind,r.evidence#>'{summary,inputs}');
 perform core.operational_report_rows_access(p_tenant_id,p_legal_entity_id,p_branch_id,r.evidence);
 if p_section not in('rows','aging','sources') or p_after is null or p_after<0 then
  raise exception using errcode='22023',message='OPERATIONAL_REPORT_PAGE_INVALID';end if;
 n:=jsonb_array_length(r.evidence->p_section);
 if p_after>n then raise exception using errcode='22023',message='OPERATIONAL_REPORT_CURSOR_INVALID';end if;
 select coalesce(jsonb_agg(x order by ordinal),'[]') into rows from jsonb_array_elements(r.evidence->p_section) with ordinality q(x,ordinal)
 where ordinal>p_after and ordinal<=p_after+50;
 return jsonb_build_object('summary',r.evidence->'summary','section',p_section,'items',rows,
  'next_cursor',case when p_after+50<n then (p_after+50)::text end);
end $$;

alter function finance.report_export_document(uuid,uuid,uuid,text,uuid,text,jsonb) rename to report_export_document_before_operational;
create function finance.report_export_document(t uuid,e uuid,b uuid,resource text,i uuid,section text,filters jsonb) returns jsonb
language plpgsql stable security definer set search_path='' as $$declare probe jsonb;data jsonb;rows jsonb;result jsonb;begin
 if resource<>'operational' then return finance.report_export_document_before_operational(t,e,b,resource,i,section,filters);end if;
 perform core.wave3_require_scope(t,'finance.reports.export',e,null);
 perform core.wave3_require_scope(t,'finance.reports.export',e,b);
 if filters is distinct from '{}'::jsonb then raise exception using errcode='22023',message='REPORT_EXPORT_FILTER_INVALID';end if;
 probe:=api.operational_report_page(t,e,b,i,section,0);
 select evidence into data from core.operational_reports where tenant_id=t and legal_entity_id=e and branch_id=b and id=i;
 rows:=data->section;
 if jsonb_array_length(rows)>10000 then raise exception using errcode='54000',message='REPORT_EXPORT_ROW_LIMIT';end if;
 result:=jsonb_build_object('version',1,'metadata',(data->'summary')||jsonb_build_object('actor_id',auth.uid(),'working_branch_id',b,
  'source_type',resource,'source_id',i,'section',section,'filters',filters,'row_count',jsonb_array_length(rows)),'rows',rows);
 if octet_length(result::text)>8388608 then raise exception using errcode='54000',message='REPORT_EXPORT_EVIDENCE_LIMIT';end if;
 return result;
end $$;
revoke all on function finance.report_export_document_before_operational(uuid,uuid,uuid,text,uuid,text,jsonb),
 finance.report_export_document(uuid,uuid,uuid,text,uuid,text,jsonb) from public,anon,authenticated;

create function api.wave3_dashboard(p_tenant_id uuid,p_legal_entity_id uuid,p_branch_id uuid) returns jsonb
language plpgsql stable security definer set search_path='' as $$
declare k text;cfg jsonb;cards jsonb:='[]';n bigint;begin
 if auth.uid() is null or p_legal_entity_id is null or p_branch_id is null or not core.is_tenant_member(p_tenant_id) then
  raise exception using errcode='42501',message='SOURCE_UNAVAILABLE';end if;
 for k in select kind from unnest(array['lead','opportunity','quotation','sales_order','delivery','sales_invoice','customer_receipt',
  'purchase_requisition','rfq','purchase_order','goods_receipt','supplier_bill','payment_proposal','inventory_transfer','stock_count',
  'manual_journal','budget','bank_statement','bank_match'])kind loop
  cfg:=core.wave3_source_descriptor(k);
  if core.has_permission(p_tenant_id,cfg->>'permission',p_legal_entity_id,p_branch_id)
   and (not (cfg->>'cost')::boolean or (core.has_permission(p_tenant_id,'inventory.cost.view',p_legal_entity_id,p_branch_id)
    and core.has_permission(p_tenant_id,'inventory.stock.view',p_legal_entity_id,p_branch_id))) then
   perform core.wave3_require_scope(p_tenant_id,cfg->>'permission',p_legal_entity_id,p_branch_id);
   execute format('select count(*) from %I.%I d where d.tenant_id=$1 and d.legal_entity_id=$2 and (d.branch_id=$3 or d.branch_id is null)
    and coalesce(to_jsonb(d)->>''status'',''posted'') in(''draft'',''submitted'',''approved'',''active'',''in_transit'')',cfg->>'schema',cfg->>'table')
    into n using p_tenant_id,p_legal_entity_id,p_branch_id;
   cards:=cards||jsonb_build_array(jsonb_build_object('kind',k,'count',n::text,'basis','current_actionable',
    'tenant_id',p_tenant_id,'legal_entity_id',p_legal_entity_id,'branch_id',p_branch_id,
    'destination',case when k in('lead','opportunity') then '/crm'
     when k in('quotation','sales_order','delivery','sales_invoice','customer_receipt') then '/sales'
     when k in('purchase_requisition','rfq','purchase_order','goods_receipt','supplier_bill','payment_proposal') then '/procurement'
     when k='inventory_transfer' then '/inventory/transfers' when k='stock_count' then '/inventory/counts'
     when k='manual_journal' then '/finance/journals' when k='budget' then '/finance/budgets'
     when k in('bank_statement','bank_match') then '/finance/bank' end,
    'generated_at',statement_timestamp()));
  end if;
 end loop;
 return jsonb_build_object('tenant_id',p_tenant_id,'legal_entity_id',p_legal_entity_id,'branch_id',p_branch_id,
  'generated_at',statement_timestamp(),'cards',cards);
end $$;

revoke all on function api.wave3_document_page(uuid,uuid,uuid,text,jsonb,uuid),
 api.wave3_document_evidence(uuid,uuid,uuid,text,uuid,uuid),api.wave3_dashboard(uuid,uuid,uuid),
 api.generate_operational_report(uuid,uuid,uuid,uuid,uuid,timestamptz,jsonb,bigint),
 api.operational_report_page(uuid,uuid,uuid,uuid,text,integer) from public,anon,authenticated;
grant execute on function api.wave3_document_page(uuid,uuid,uuid,text,jsonb,uuid),
 api.wave3_document_evidence(uuid,uuid,uuid,text,uuid,uuid),api.wave3_dashboard(uuid,uuid,uuid),
 api.generate_operational_report(uuid,uuid,uuid,uuid,uuid,timestamptz,jsonb,bigint),
 api.operational_report_page(uuid,uuid,uuid,uuid,text,integer) to authenticated;
