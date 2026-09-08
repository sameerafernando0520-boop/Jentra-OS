-- AC-305..AC-308. Additive expansion; existing AC-304 objects are unchanged.
-- Inventory values have separate RLS so quantity readers do not gain cost access.

insert into core.permissions(code,module,description,privileged) values
 ('sales.deliveries.view','sales','View deliveries and source quantities.',false),
 ('sales.deliveries.manage','sales','Prepare delivery documents.',true),
 ('sales.returns.view','sales','View sales returns and credits.',true),
 ('sales.returns.manage','sales','Prepare source-linked returns and credits.',true),
 ('finance.receipts.view','finance','View customer receipts and applications.',true),
 ('finance.receipts.manage','finance','Prepare customer receipts.',true),
 ('finance.receipts.allocate','finance','Allocate receipts and customer credits.',true),
 ('finance.receipts.adjust','finance','Apply reasoned settlement discounts and write-offs.',true),
 ('finance.receivables.view','finance','View customer statements and aging.',true)
on conflict(code) do nothing;
insert into core.role_permissions(tenant_id,role_id,permission_code)
select r.tenant_id,r.id,p.code from core.roles r cross join core.permissions p
where r.code='tenant_owner' and p.code in ('sales.deliveries.view','sales.deliveries.manage',
 'sales.returns.view','sales.returns.manage','finance.receipts.view','finance.receipts.manage',
 'finance.receipts.allocate','finance.receipts.adjust','finance.receivables.view')
on conflict(role_id,permission_code) do nothing;

create table finance.posting_mappings (
 id uuid primary key default gen_random_uuid(), tenant_id uuid not null,
 legal_entity_id uuid not null, purpose text not null check(purpose in
 ('receivable_control','output_tax','rounding','exchange_gain','exchange_loss','write_off','settlement_discount')),
 account_id uuid not null, status text not null default 'active' check(status in ('active','inactive')),
 version bigint not null default 1 check(version>0), created_by uuid not null references auth.users(id),
 updated_by uuid not null references auth.users(id), created_at timestamptz not null default now(),
 updated_at timestamptz not null default now(), unique(tenant_id,legal_entity_id,purpose),
 unique(tenant_id,id), foreign key(tenant_id,legal_entity_id) references core.legal_entities(tenant_id,id),
 foreign key(tenant_id,legal_entity_id,account_id) references finance.accounts(tenant_id,legal_entity_id,id)
);
create table finance.cash_bank_accounts (
 id uuid primary key default gen_random_uuid(),tenant_id uuid not null,legal_entity_id uuid not null,
 branch_id uuid not null,code text not null check(code ~ '^[A-Z0-9][A-Z0-9_.-]{0,31}$'),
 name text not null check(length(trim(name)) between 2 and 140),
 account_kind text not null check(account_kind in ('cash','bank')),account_id uuid not null,
 currency_code text not null references core.currencies(code),
 reconciliation_rules jsonb not null default '{}' check(jsonb_typeof(reconciliation_rules)='object'),
 status text not null default 'active' check(status in ('active','inactive')),
 version bigint not null default 1 check(version>0),created_by uuid not null references auth.users(id),
 updated_by uuid not null references auth.users(id),created_at timestamptz not null default now(),
 updated_at timestamptz not null default now(),unique(tenant_id,id),unique(tenant_id,legal_entity_id,code),
 foreign key(tenant_id,legal_entity_id) references core.legal_entities(tenant_id,id),
 foreign key(tenant_id,branch_id) references core.branches(tenant_id,id),
 foreign key(tenant_id,legal_entity_id,account_id) references finance.accounts(tenant_id,legal_entity_id,id)
);

-- Uniform headers retain concrete document tables and typed source links.
do $$ declare v_table text; v_kind text; v_lines text; begin
 for v_table,v_kind,v_lines in select * from (values
 ('deliveries','delivery','delivery_lines'),('sales_invoices','sales_invoice','sales_invoice_lines'),
 ('customer_receipts','customer_receipt','customer_receipt_lines'),
 ('sales_returns','sales_return','sales_return_lines')) x loop
 execute format($ddl$create table sales.%I (
 id uuid primary key default gen_random_uuid(),tenant_id uuid not null,legal_entity_id uuid not null,
 branch_id uuid not null,document_type text not null default %L check(document_type=%L),
 document_number text,customer_id uuid not null,document_date date not null,due_date date not null,
 currency_code text not null references core.currencies(code),base_currency_code text not null references core.currencies(code),
 exchange_rate_id uuid,exchange_rate numeric(20,10) not null check(exchange_rate>0),rate_date date not null,
 rounding_scale smallint not null check(rounding_scale between 0 and 6),
 sales_order_id uuid,warehouse_id uuid,cash_bank_account_id uuid,external_reference text,
 terms text,notes text,reason text,tender_metadata jsonb not null default '{}' check(jsonb_typeof(tender_metadata)='object'),
 subtotal numeric(20,6) not null default 0 check(subtotal>=0),
 discount_total numeric(20,6) not null default 0 check(discount_total>=0),
 tax_total numeric(20,6) not null default 0 check(tax_total>=0),
 grand_total numeric(20,6) not null default 0 check(grand_total>=0),
 base_total numeric(20,6) not null default 0 check(base_total>=0),
 status text not null default 'draft' check(status in ('draft','submitted','pending_approval','approved','rejected','cancelled','posted')),
 version bigint not null default 1 check(version>0),workflow_snapshot jsonb,
 submitted_by uuid references auth.users(id),posted_by uuid references auth.users(id),posted_at timestamptz,
 request_id uuid not null,command_id uuid not null,correlation_id uuid not null,
 source_context jsonb not null default '{}' check(jsonb_typeof(source_context)='object'),
 client_timestamp timestamptz not null,created_by uuid not null references auth.users(id),
 updated_by uuid not null references auth.users(id),created_at timestamptz not null default now(),
 updated_at timestamptz not null default now(),unique(tenant_id,id),unique(tenant_id,legal_entity_id,branch_id,document_number),
 foreign key(tenant_id,legal_entity_id) references core.legal_entities(tenant_id,id),
 foreign key(tenant_id,branch_id) references core.branches(tenant_id,id),
 foreign key(tenant_id,customer_id) references crm.parties(tenant_id,id),
 foreign key(tenant_id,legal_entity_id,sales_order_id) references sales.sales_orders(tenant_id,legal_entity_id,id),
 foreign key(tenant_id,warehouse_id) references core.warehouses(tenant_id,id),
 foreign key(tenant_id,cash_bank_account_id) references finance.cash_bank_accounts(tenant_id,id),
 foreign key(tenant_id,legal_entity_id,exchange_rate_id) references finance.exchange_rates(tenant_id,legal_entity_id,id),
 check(due_date>=document_date),check(currency_code<>base_currency_code or exchange_rate=1),
 check((status='posted')=(posted_at is not null)))$ddl$,v_table,v_kind,v_kind);
 execute format($ddl$create table sales.%I (
 id uuid primary key,tenant_id uuid not null,legal_entity_id uuid not null,branch_id uuid not null,
 document_id uuid not null,line_number integer not null check(line_number between 1 and 500),
 product_id uuid,description text not null,quantity numeric(20,6) not null check(quantity>0),
 base_quantity numeric(20,6) not null check(base_quantity>0),unit_id uuid,
 sales_order_line_id uuid,delivery_line_id uuid,sales_invoice_line_id uuid,
 taxable_amount numeric(20,6) not null default 0 check(taxable_amount>=0),
 tax_amount numeric(20,6) not null default 0 check(tax_amount>=0),
 line_total numeric(20,6) not null default 0 check(line_total>=0),
 snapshot jsonb not null check(jsonb_typeof(snapshot)='object'),
 created_by uuid not null references auth.users(id),created_at timestamptz not null default now(),
 unique(tenant_id,id),unique(tenant_id,document_id,line_number),
 foreign key(tenant_id,document_id) references sales.%I(tenant_id,id),
 foreign key(tenant_id,legal_entity_id,product_id) references inventory.products(tenant_id,legal_entity_id,id),
 foreign key(tenant_id,unit_id) references inventory.units(tenant_id,id),
 foreign key(tenant_id,sales_order_line_id) references sales.sales_order_lines(tenant_id,id))$ddl$,v_lines,v_table);
 end loop;
end $$;
alter table sales.sales_invoice_lines add foreign key(tenant_id,delivery_line_id) references sales.delivery_lines(tenant_id,id);
alter table sales.sales_return_lines add foreign key(tenant_id,delivery_line_id) references sales.delivery_lines(tenant_id,id),
 add foreign key(tenant_id,sales_invoice_line_id) references sales.sales_invoice_lines(tenant_id,id);

create table finance.journal_entries (
 id uuid primary key default gen_random_uuid(),tenant_id uuid not null,legal_entity_id uuid not null,branch_id uuid not null,
 fiscal_period_id uuid not null,document_number text not null,posting_date date not null,
 source_type text not null,source_id uuid not null,currency_code text not null references core.currencies(code),
 base_currency_code text not null references core.currencies(code),exchange_rate numeric(20,10) not null check(exchange_rate>0),
 status text not null default 'draft' check(status in ('draft','posted')),rule_version integer not null default 1,
 request_id uuid not null,command_id uuid not null,correlation_id uuid not null,
 created_by uuid not null references auth.users(id),created_at timestamptz not null default now(),
 unique(tenant_id,id),unique(tenant_id,source_type,source_id),
 unique(tenant_id,legal_entity_id,branch_id,document_number),
 foreign key(tenant_id,legal_entity_id) references core.legal_entities(tenant_id,id),
 foreign key(tenant_id,branch_id) references core.branches(tenant_id,id),
 foreign key(tenant_id,legal_entity_id,fiscal_period_id) references finance.fiscal_periods(tenant_id,legal_entity_id,id)
);
create table finance.journal_lines (
 id uuid primary key default gen_random_uuid(),tenant_id uuid not null,legal_entity_id uuid not null,branch_id uuid not null,
 journal_entry_id uuid not null,line_number integer not null,account_id uuid not null,party_id uuid,
 source_line_id uuid,currency_code text not null references core.currencies(code),
 transaction_debit numeric(20,6) not null default 0 check(transaction_debit>=0),
 transaction_credit numeric(20,6) not null default 0 check(transaction_credit>=0),
 base_debit numeric(20,6) not null default 0 check(base_debit>=0),
 base_credit numeric(20,6) not null default 0 check(base_credit>=0),
 posting_date date not null,created_by uuid not null references auth.users(id),created_at timestamptz not null default now(),
 unique(tenant_id,id),unique(tenant_id,journal_entry_id,line_number),
 foreign key(tenant_id,journal_entry_id) references finance.journal_entries(tenant_id,id),
 foreign key(tenant_id,legal_entity_id,account_id) references finance.accounts(tenant_id,legal_entity_id,id),
 foreign key(tenant_id,party_id) references crm.parties(tenant_id,id),
 check((base_debit>0 and base_credit=0) or (base_credit>0 and base_debit=0)),
 check(transaction_debit=0 or transaction_credit=0)
);
create table finance.open_items (
 id uuid primary key default gen_random_uuid(),tenant_id uuid not null,legal_entity_id uuid not null,branch_id uuid not null,
 kind text not null default 'AR' check(kind in ('AR','AP')),party_id uuid not null,
 source_type text not null,source_id uuid not null,document_number text not null,
 currency_code text not null references core.currencies(code),base_currency_code text not null references core.currencies(code),
 exchange_rate numeric(20,10) not null check(exchange_rate>0),
 original_amount numeric(20,6) not null check(original_amount<>0),
 original_base_amount numeric(20,6) not null check(original_base_amount<>0),
 posting_date date not null,due_date date not null,journal_entry_id uuid not null,
 request_id uuid not null,command_id uuid not null,correlation_id uuid not null,
 created_by uuid not null references auth.users(id),created_at timestamptz not null default now(),
 unique(tenant_id,id),unique(tenant_id,source_type,source_id),
 foreign key(tenant_id,legal_entity_id) references core.legal_entities(tenant_id,id),
 foreign key(tenant_id,branch_id) references core.branches(tenant_id,id),
 foreign key(tenant_id,party_id) references crm.parties(tenant_id,id),
 foreign key(tenant_id,journal_entry_id) references finance.journal_entries(tenant_id,id),
 check(sign(original_amount)=sign(original_base_amount))
);
create table finance.open_item_allocations (
 id uuid primary key default gen_random_uuid(),tenant_id uuid not null,legal_entity_id uuid not null,branch_id uuid not null,
 source_open_item_id uuid not null,target_open_item_id uuid not null,
 source_amount numeric(20,6) not null check(source_amount>0),
 transaction_amount numeric(20,6) not null check(transaction_amount>0),
 source_base_amount numeric(20,6) not null check(source_base_amount>0),
 target_base_amount numeric(20,6) not null check(target_base_amount>0),
 exchange_difference numeric(20,6) not null default 0,
 write_off numeric(20,6) not null default 0 check(write_off>=0),
 discount_amount numeric(20,6) not null default 0 check(discount_amount>=0),
 adjustment_base_amount numeric(20,6) not null default 0 check(adjustment_base_amount>=0),
 exchange_rate_id uuid,conversion_rate numeric(20,10) not null default 1 check(conversion_rate>0),
 posting_date date not null,reason text,journal_entry_id uuid,
 request_id uuid not null,command_id uuid not null,correlation_id uuid not null,
 created_by uuid not null references auth.users(id),created_at timestamptz not null default now(),
 unique(tenant_id,id),foreign key(tenant_id,source_open_item_id) references finance.open_items(tenant_id,id),
 foreign key(tenant_id,target_open_item_id) references finance.open_items(tenant_id,id),
 foreign key(tenant_id,legal_entity_id,exchange_rate_id) references finance.exchange_rates(tenant_id,legal_entity_id,id),
 foreign key(tenant_id,journal_entry_id) references finance.journal_entries(tenant_id,id),
 check(source_open_item_id<>target_open_item_id)
);

create table inventory.lots (
 id uuid primary key default gen_random_uuid(),tenant_id uuid not null,legal_entity_id uuid not null,
 product_id uuid not null,code text not null,manufacture_date date,expiry_date date,
 status text not null default 'saleable' check(status in ('saleable','quarantine','disposed')),
 version bigint not null default 1,created_by uuid not null references auth.users(id),
 updated_by uuid not null references auth.users(id),created_at timestamptz not null default now(),updated_at timestamptz not null default now(),
 unique(tenant_id,id),unique(tenant_id,product_id,code),
 foreign key(tenant_id,legal_entity_id,product_id) references inventory.products(tenant_id,legal_entity_id,id),
 check(expiry_date is null or manufacture_date is null or expiry_date>=manufacture_date)
);
create table inventory.serials (
 id uuid primary key default gen_random_uuid(),tenant_id uuid not null,legal_entity_id uuid not null,
 branch_id uuid not null,warehouse_id uuid not null,product_id uuid not null,lot_id uuid,code text not null,
 status text not null default 'available' check(status in ('available','issued','quarantine','disposed')),
 last_delivery_line_id uuid,version bigint not null default 1,created_by uuid not null references auth.users(id),
 updated_by uuid not null references auth.users(id),created_at timestamptz not null default now(),updated_at timestamptz not null default now(),
 unique(tenant_id,id),unique(tenant_id,product_id,code),
 foreign key(tenant_id,legal_entity_id,product_id) references inventory.products(tenant_id,legal_entity_id,id),
 foreign key(tenant_id,warehouse_id) references core.warehouses(tenant_id,id),
 foreign key(tenant_id,lot_id) references inventory.lots(tenant_id,id),
 foreign key(tenant_id,last_delivery_line_id) references sales.delivery_lines(tenant_id,id)
);
create table inventory.lot_balances (
 id uuid primary key default gen_random_uuid(),tenant_id uuid not null,legal_entity_id uuid not null,
 branch_id uuid not null,warehouse_id uuid not null,product_id uuid not null,lot_id uuid not null,
 on_hand_quantity numeric(20,6) not null check(on_hand_quantity>=0),version bigint not null default 1,
 created_by uuid not null references auth.users(id),updated_by uuid not null references auth.users(id),
 created_at timestamptz not null default now(),updated_at timestamptz not null default now(),
 unique(tenant_id,id),unique(tenant_id,warehouse_id,lot_id),
 foreign key(tenant_id,warehouse_id) references core.warehouses(tenant_id,id),
 foreign key(tenant_id,legal_entity_id,product_id) references inventory.products(tenant_id,legal_entity_id,id),
 foreign key(tenant_id,lot_id) references inventory.lots(tenant_id,id)
);
create table inventory.stock_valuations (
 id uuid primary key default gen_random_uuid(),tenant_id uuid not null,legal_entity_id uuid not null,
 branch_id uuid not null,stock_balance_id uuid not null,carrying_value numeric(20,6) not null check(carrying_value>=0),
 version bigint not null default 1,created_by uuid not null references auth.users(id),updated_by uuid not null references auth.users(id),
 created_at timestamptz not null default now(),updated_at timestamptz not null default now(),
 unique(tenant_id,id),unique(tenant_id,stock_balance_id),
 foreign key(tenant_id,stock_balance_id) references inventory.stock_balances(tenant_id,id)
);
create table inventory.stock_movements (
 id uuid primary key default gen_random_uuid(),tenant_id uuid not null,legal_entity_id uuid not null,branch_id uuid not null,
 source_type text not null,source_id uuid not null,warehouse_id uuid not null,posting_date date not null,
 movement_kind text not null check(movement_kind in ('opening','delivery','sales_return')),
 request_id uuid not null,command_id uuid not null,correlation_id uuid not null,
 created_by uuid not null references auth.users(id),created_at timestamptz not null default now(),
 unique(tenant_id,id),unique(tenant_id,source_type,source_id),
 foreign key(tenant_id,warehouse_id) references core.warehouses(tenant_id,id)
);
create table inventory.stock_movement_lines (
 id uuid primary key default gen_random_uuid(),tenant_id uuid not null,legal_entity_id uuid not null,branch_id uuid not null,
 stock_movement_id uuid not null,warehouse_id uuid not null,product_id uuid not null,
 source_line_id uuid not null,original_movement_line_id uuid,
 base_quantity numeric(20,6) not null check(base_quantity<>0),base_value numeric(20,6) not null,
 lot_id uuid,serial_ids uuid[] not null default '{}',posting_date date not null,
 created_by uuid not null references auth.users(id),created_at timestamptz not null default now(),
 unique(tenant_id,id),unique(tenant_id,stock_movement_id,source_line_id),
 foreign key(tenant_id,stock_movement_id) references inventory.stock_movements(tenant_id,id),
 foreign key(tenant_id,legal_entity_id,product_id) references inventory.products(tenant_id,legal_entity_id,id),
 foreign key(tenant_id,warehouse_id) references core.warehouses(tenant_id,id),
 foreign key(tenant_id,lot_id) references inventory.lots(tenant_id,id),
 foreign key(tenant_id,original_movement_line_id) references inventory.stock_movement_lines(tenant_id,id),
 check(base_value=0 or sign(base_quantity)=sign(base_value))
);

create function sales.flow_table(p_kind text) returns text language plpgsql immutable set search_path='' as $$
begin return case p_kind when 'delivery' then 'deliveries' when 'sales_invoice' then 'sales_invoices'
 when 'customer_receipt' then 'customer_receipts' when 'sales_return' then 'sales_returns'
 else null end; end $$;
create function sales.flow_lines_table(p_kind text) returns text language sql immutable set search_path='' as $$
 select case p_kind when 'delivery' then 'delivery_lines' when 'sales_invoice' then 'sales_invoice_lines'
 when 'customer_receipt' then 'customer_receipt_lines' when 'sales_return' then 'sales_return_lines' end $$;
create function sales.flow_permission(p_kind text,p_action text) returns text language sql immutable set search_path='' as $$
 select case p_kind when 'delivery' then 'sales.deliveries.' when 'sales_invoice' then 'sales.invoices.'
 when 'customer_receipt' then 'finance.receipts.' when 'sales_return' then 'sales.returns.' end || p_action $$;
create function sales.flow_read_allowed(p_tenant uuid,p_entity uuid,p_branch uuid,p_kind text)
returns boolean language sql stable security definer set search_path='' as $$
 select core.is_tenant_member(p_tenant) and (core.has_permission(p_tenant,sales.flow_permission(p_kind,'view'),p_entity,p_branch)
 or core.has_permission(p_tenant,sales.flow_permission(p_kind,'manage'),p_entity,p_branch)
 or core.has_permission(p_tenant,sales.flow_permission(p_kind,'post'),p_entity,p_branch)
 or core.has_permission(p_tenant,'workflow.approvals.decide',p_entity,p_branch)) $$;

-- Convert every exact business numeric to a string before serializing nested JSON.
create function sales.flow_exact_json(p_value jsonb) returns jsonb language plpgsql immutable set search_path='' as $$
declare v_result jsonb;v_key text;v_item jsonb;begin
 if jsonb_typeof(p_value)='array' then select coalesce(jsonb_agg(sales.flow_exact_json(value)),'[]') into v_result
 from jsonb_array_elements(p_value);return v_result;
 elsif jsonb_typeof(p_value)='object' then v_result:='{}';
 for v_key,v_item in select * from jsonb_each(p_value) loop
 if jsonb_typeof(v_item)='number' and v_key not in ('version','line_number','rounding_scale','step_order','revision','definition_version','tax_definition_version','rule_version')
 then v_item:=to_jsonb(v_item#>>'{}');else v_item:=sales.flow_exact_json(v_item);end if;
 v_result:=v_result||jsonb_build_object(v_key,v_item);end loop;return v_result;
 end if;return p_value;end $$;

create function sales.flow_protect_document() returns trigger language plpgsql set search_path='' as $$
begin if old.status='posted' then raise exception using errcode='55000',message='POSTED_DOCUMENT_IMMUTABLE';end if;
 if tg_op='DELETE' then return old;end if;return new;end $$;
create function sales.flow_protect_line() returns trigger language plpgsql security definer set search_path='' as $$
declare v_document jsonb;v_row jsonb;begin
 v_row:=case when tg_op='DELETE' then to_jsonb(old) else to_jsonb(new) end;
 execute format('select to_jsonb(d) from sales.%I d where tenant_id=$1 and id=$2 for update',tg_argv[0])
 into v_document using (v_row->>'tenant_id')::uuid,(v_row->>'document_id')::uuid;
 if v_document is null or v_document->>'status'<>'draft' then
 raise exception using errcode='55000',message='DOCUMENT_LINES_NOT_EDITABLE';end if;
 if tg_op='DELETE' then return old;end if;return new;end $$;

do $$ declare v_table text;v_kind text;v_lines text;begin
 for v_table,v_kind,v_lines in select * from (values
 ('deliveries','delivery','delivery_lines'),('sales_invoices','sales_invoice','sales_invoice_lines'),
 ('customer_receipts','customer_receipt','customer_receipt_lines'),('sales_returns','sales_return','sales_return_lines')) x loop
 execute format('alter table sales.%I enable row level security',v_table);
 execute format('alter table sales.%I force row level security',v_table);
 execute format('alter table sales.%I enable row level security',v_lines);
 execute format('alter table sales.%I force row level security',v_lines);
 execute format('create policy permitted_read on sales.%I for select to authenticated using(sales.flow_read_allowed(tenant_id,legal_entity_id,branch_id,%L))',v_table,v_kind);
 execute format('create policy permitted_read on sales.%I for select to authenticated using(sales.flow_read_allowed(tenant_id,legal_entity_id,branch_id,%L))',v_lines,v_kind);
 execute format('create trigger immutable_posted before update or delete on sales.%I for each row execute function sales.flow_protect_document()',v_table);
 execute format('create trigger touch before update on sales.%I for each row execute function core.touch_mutable_record()',v_table);
 execute format('create trigger protect_lines before insert or update or delete on sales.%I for each row execute function sales.flow_protect_line(%L)',v_lines,v_table);
 execute format('revoke all on sales.%I,sales.%I from public,anon,authenticated',v_table,v_lines);
 execute format('grant select on sales.%I,sales.%I to authenticated',v_table,v_lines);
 execute format('create index %I on sales.%I(tenant_id,legal_entity_id,branch_id,status,id)',v_table||'_scope_idx',v_table);
 execute format('create index %I on sales.%I(tenant_id,customer_id,document_date,id)',v_table||'_customer_idx',v_table);
 execute format('create view api.%I with(security_invoker=true) as select id,tenant_id,legal_entity_id,branch_id,document_id,line_number,product_id,sales_order_line_id,delivery_line_id,sales_invoice_line_id,sales.flow_exact_json(to_jsonb(l)) as detail from sales.%I l',v_lines,v_lines);
 execute format('create view api.%I with(security_invoker=true) as select d.id,d.tenant_id,d.legal_entity_id,d.branch_id,d.document_type,d.document_number,d.customer_id,d.document_date,d.currency_code,d.status,d.version,d.grand_total::text,d.base_total::text,sales.flow_exact_json(to_jsonb(d))||jsonb_build_object(''customer_name'',(select coalesce(p.display_name,p.legal_name) from crm.parties p where p.tenant_id=d.tenant_id and p.id=d.customer_id),''lines'',coalesce((select jsonb_agg(l.detail order by l.line_number) from api.%I l where l.tenant_id=d.tenant_id and l.document_id=d.id),''[]''::jsonb)) as detail from sales.%I d',v_table,v_lines,v_table);
 execute format('revoke all on api.%I,api.%I from public,anon,authenticated',v_table,v_lines);
 execute format('grant select on api.%I,api.%I to authenticated',v_table,v_lines);
 end loop;
end $$;

-- Common RLS/index/immutability installation for new supporting relations only.
do $$ declare v_schema text;v_table text;v_permission text;v_mutable boolean;v_branch text;v_fk record;begin
 for v_schema,v_table,v_permission,v_mutable in select * from (values
 ('finance','posting_mappings','finance.setup.view',true),('finance','cash_bank_accounts','finance.receipts.view',true),
 ('finance','journal_entries','finance.view',false),('finance','journal_lines','finance.view',false),
 ('finance','open_items','finance.receivables.view',false),('finance','open_item_allocations','finance.receivables.view',false),
 ('inventory','lots','inventory.stock.view',true),('inventory','serials','inventory.stock.view',true),
 ('inventory','lot_balances','inventory.stock.view',true),('inventory','stock_valuations','inventory.cost.view',true),
 ('inventory','stock_movements','inventory.stock.view',false),('inventory','stock_movement_lines','inventory.cost.view',false)) x loop
 v_branch:=case when v_table in ('posting_mappings','lots') then 'null' else 'branch_id' end;
 execute format('alter table %I.%I enable row level security',v_schema,v_table);
 execute format('alter table %I.%I force row level security',v_schema,v_table);
 execute format('create policy permitted_read on %I.%I for select to authenticated using(core.is_tenant_member(tenant_id) and core.has_permission(tenant_id,%L,legal_entity_id,%s))',v_schema,v_table,v_permission,v_branch);
 execute format('revoke all on %I.%I from public,anon,authenticated',v_schema,v_table);
 execute format('grant select on %I.%I to authenticated',v_schema,v_table);
 if v_mutable then execute format('create trigger touch before update on %I.%I for each row execute function core.touch_mutable_record()',v_schema,v_table);
 elsif v_table='journal_entries' then execute format('create trigger immutable before update or delete on %I.%I for each row execute function sales.flow_protect_document()',v_schema,v_table);
 else execute format('create trigger immutable before update or delete on %I.%I for each row execute function workflow.reject_history_mutation()',v_schema,v_table);end if;
 execute format('create view api.%I with(security_invoker=true) as select id,tenant_id,legal_entity_id,%s as branch_id,sales.flow_exact_json(to_jsonb(t)) as detail from %I.%I t',v_table,v_branch,v_schema,v_table);
 execute format('revoke all on api.%I from public,anon,authenticated',v_table);
 execute format('grant select on api.%I to authenticated',v_table);
 end loop;
 -- Cover every new FK; include tenant first for actor-only references as well.
 for v_fk in select c.oid,c.conrelid,n.nspname,t.relname,
 (select string_agg(quote_ident(a.attname),',' order by k.ordinality) from unnest(c.conkey) with ordinality k(num,ordinality)
 join pg_attribute a on a.attrelid=c.conrelid and a.attnum=k.num) cols,
 exists(select 1 from pg_attribute a where a.attrelid=c.conrelid and a.attname='tenant_id' and a.attnum=any(c.conkey)) has_tenant
 from pg_constraint c join pg_class t on t.oid=c.conrelid join pg_namespace n on n.oid=t.relnamespace
 where c.contype='f' and n.nspname in ('sales','finance','inventory') and t.relname in
 ('posting_mappings','cash_bank_accounts','deliveries','delivery_lines','sales_invoices','sales_invoice_lines',
 'customer_receipts','customer_receipt_lines','sales_returns','sales_return_lines','journal_entries','journal_lines',
 'open_items','open_item_allocations','lots','serials','lot_balances','stock_valuations','stock_movements','stock_movement_lines')
 loop execute format('create index %I on %I.%I(%s%s)',v_fk.relname||'_fk_'||v_fk.oid,v_fk.nspname,v_fk.relname,
 case when v_fk.has_tenant then '' else 'tenant_id,' end,v_fk.cols);end loop;
end $$;

create index open_items_aging_idx on finance.open_items(tenant_id,legal_entity_id,branch_id,party_id,currency_code,posting_date,due_date,id);
create index allocations_source_asof_idx on finance.open_item_allocations(tenant_id,source_open_item_id,posting_date,id);
create index allocations_target_asof_idx on finance.open_item_allocations(tenant_id,target_open_item_id,posting_date,id);
create index stock_movement_source_idx on inventory.stock_movement_lines(tenant_id,source_line_id,id);

-- Private helpers are never directly executable by desktop roles.
revoke all on function sales.flow_table(text),sales.flow_lines_table(text),sales.flow_permission(text,text),
 sales.flow_read_allowed(uuid,uuid,uuid,text),sales.flow_exact_json(jsonb),sales.flow_protect_document(),sales.flow_protect_line()
 from public,anon,authenticated;
grant execute on function sales.flow_read_allowed(uuid,uuid,uuid,text),sales.flow_exact_json(jsonb) to authenticated;
notify pgrst,'reload schema';
