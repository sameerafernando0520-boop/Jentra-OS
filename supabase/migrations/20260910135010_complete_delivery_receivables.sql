-- AC-305–AC-308 atomic development expansion.
-- Consolidated from the seven un-applied 20260907100000..20260907100600 candidates.
-- Preserve applied history; subsequent corrections must be additive.

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

-- Private, exact posting helpers. All mutations run inside the calling RPC transaction.
create function sales.flow_assert_transition(p_lifecycle jsonb,p_from text,p_to text) returns void
language plpgsql immutable set search_path='' as $$ begin
 if p_from='pending_approval' then p_from:='submitted';end if;
 if p_to='pending_approval' then p_to:='submitted';end if;
 if p_lifecycle is null or not (coalesce(p_lifecycle->'transitions','[]'::jsonb)||coalesce(p_lifecycle->'posting_transitions','[]'::jsonb))
 @> jsonb_build_array(jsonb_build_array(p_from,p_to)) then raise exception using errcode='55000',message='WORKFLOW_TRANSITION_INVALID';end if;end $$;
create function sales.flow_document(p_kind text,p_tenant uuid,p_id uuid,p_lock boolean default false)
returns jsonb language plpgsql security definer set search_path='' as $$
declare v_doc jsonb;v_lines jsonb;v_table text:=sales.flow_table(p_kind);begin
 if v_table is null then raise exception using errcode='22023',message='DOCUMENT_TYPE_INVALID';end if;
 execute format('select sales.flow_exact_json(to_jsonb(d)) from sales.%I d where tenant_id=$1 and id=$2%s',v_table,
 case when p_lock then ' for update' else '' end) into v_doc using p_tenant,p_id;
 if v_doc is null then return null;end if;
 v_doc:=v_doc||jsonb_build_object('customer_name',(select coalesce(display_name,legal_name) from crm.parties where tenant_id=p_tenant and id=(v_doc->>'customer_id')::uuid));
 execute format('select coalesce(jsonb_agg(sales.flow_exact_json(to_jsonb(l)) order by line_number),''[]''::jsonb) from sales.%I l where tenant_id=$1 and document_id=$2',sales.flow_lines_table(p_kind))
 into v_lines using p_tenant,p_id;return v_doc||jsonb_build_object('lines',v_lines);end $$;

create function finance.flow_account(p_tenant uuid,p_entity uuid,p_account uuid,p_type text,p_currency text default null)
returns uuid language plpgsql security definer set search_path='' as $$
begin if p_account is null or not exists(select 1 from finance.accounts a
 where a.tenant_id=p_tenant and a.legal_entity_id=p_entity and a.id=p_account
 and a.status='active' and a.is_posting and a.account_type=p_type
 and (a.currency_code is null or a.currency_code=p_currency)) then
 raise exception using errcode='55000',message='ACCOUNT_MAPPING_INVALID';end if;return p_account;end $$;
create function finance.flow_mapping(p_tenant uuid,p_entity uuid,p_purpose text,p_currency text)
returns uuid language plpgsql security definer set search_path='' as $$
declare v_id uuid;begin select account_id into v_id from finance.posting_mappings
 where tenant_id=p_tenant and legal_entity_id=p_entity and purpose=p_purpose and status='active';
 return finance.flow_account(p_tenant,p_entity,v_id,case p_purpose when 'receivable_control' then 'asset'
 when 'output_tax' then 'liability' when 'exchange_gain' then 'revenue' else 'expense' end,p_currency);end $$;

create function finance.flow_rate(p_tenant uuid,p_entity uuid,p_currency text,p_date date,p_rate_id uuid)
returns jsonb language plpgsql security definer set search_path='' as $$
declare v_base text;v_rate finance.exchange_rates%rowtype;begin
 select currency_code into v_base from core.legal_entities where tenant_id=p_tenant and id=p_entity;
 if not exists(select 1 from core.currencies where code=p_currency and active) then
 raise exception using errcode='22023',message='CURRENCY_INVALID';end if;
 if p_currency=v_base then
 if p_rate_id is not null then raise exception using errcode='22023',message='EXCHANGE_RATE_INVALID';end if;
 return jsonb_build_object('base_currency_code',v_base,'exchange_rate','1.0000000000','exchange_rate_id',null,'rate_date',p_date);
 end if;
 select * into v_rate from finance.exchange_rates where tenant_id=p_tenant and legal_entity_id=p_entity
 and id=p_rate_id and source_currency_code=p_currency and target_currency_code=v_base and status='active' and effective_date<=p_date;
 if not found then raise exception using errcode='22023',message='EXCHANGE_RATE_INVALID';end if;
 return jsonb_build_object('base_currency_code',v_base,'exchange_rate',v_rate.rate::text,
 'exchange_rate_id',v_rate.id,'rate_date',v_rate.effective_date);end $$;

create function finance.flow_residual(p_tenant uuid,p_id uuid,p_as_of date default null)
returns jsonb language sql stable security definer set search_path='' as $$
 select jsonb_build_object('amount',(o.original_amount+
 coalesce((select sum(a.source_amount) from finance.open_item_allocations a where a.tenant_id=o.tenant_id and a.source_open_item_id=o.id and (p_as_of is null or a.posting_date<=p_as_of)),0)-
 coalesce((select sum(a.transaction_amount+a.write_off+a.discount_amount) from finance.open_item_allocations a where a.tenant_id=o.tenant_id and a.target_open_item_id=o.id and (p_as_of is null or a.posting_date<=p_as_of)),0))::text,
 'base_amount',(o.original_base_amount+
 coalesce((select sum(a.source_base_amount) from finance.open_item_allocations a where a.tenant_id=o.tenant_id and a.source_open_item_id=o.id and (p_as_of is null or a.posting_date<=p_as_of)),0)-
 coalesce((select sum(a.target_base_amount+a.adjustment_base_amount) from finance.open_item_allocations a where a.tenant_id=o.tenant_id and a.target_open_item_id=o.id and (p_as_of is null or a.posting_date<=p_as_of)),0))::text)
 from finance.open_items o where o.tenant_id=p_tenant and o.id=p_id and (p_as_of is null or o.posting_date<=p_as_of) $$;

create function finance.flow_journal_guard() returns trigger language plpgsql security definer set search_path='' as $$
declare v_id uuid;v_status text;v_count bigint;v_diff numeric;begin
 v_id:=case when tg_table_name='journal_entries' then new.id else (to_jsonb(new)->>'journal_entry_id')::uuid end;
 select status into v_status from finance.journal_entries where id=v_id;
 select count(*),sum(base_debit-base_credit) into v_count,v_diff from finance.journal_lines where journal_entry_id=v_id;
 if v_status<>'posted' or v_count<2 or v_diff is distinct from 0 then
 raise exception using errcode='23514',message='UNBALANCED_JOURNAL';end if;return null;end $$;
create constraint trigger journal_balanced after insert or update on finance.journal_entries
deferrable initially deferred for each row execute function finance.flow_journal_guard();
create constraint trigger journal_lines_balanced after insert on finance.journal_lines
deferrable initially deferred for each row execute function finance.flow_journal_guard();
create function finance.flow_journal_line_guard() returns trigger language plpgsql security definer set search_path='' as $$
begin if not exists(select 1 from finance.journal_entries j where j.id=new.journal_entry_id
 and j.tenant_id=new.tenant_id and j.legal_entity_id=new.legal_entity_id and j.branch_id=new.branch_id and j.status='draft') then
 raise exception using errcode='55000',message='POSTED_JOURNAL_IMMUTABLE';end if;return new;end $$;
create trigger protect_posted_lines before insert on finance.journal_lines
for each row execute function finance.flow_journal_line_guard();

-- Each input contains account_id and signed transaction/base amounts (debits positive).
create function finance.flow_post_journal(p_doc jsonb,p_lines jsonb,p_source_type text,p_source_id uuid,p_request uuid,p_command uuid)
returns uuid language plpgsql security definer set search_path='' as $$
declare v_id uuid:=gen_random_uuid();v_t uuid:=(p_doc->>'tenant_id')::uuid;v_e uuid:=(p_doc->>'legal_entity_id')::uuid;
 v_b uuid:=(p_doc->>'branch_id')::uuid;v_date date:=(p_doc->>'document_date')::date;v_period uuid;v_item jsonb;
 v_diff numeric;v_transaction numeric;v_base numeric;v_ord integer:=0;v_account finance.accounts%rowtype;begin
 if jsonb_array_length(p_lines)=0 then return null;end if;
 select sum((x->>'base_amount')::numeric) into v_diff from jsonb_array_elements(p_lines) x;
 if v_diff<>0 then raise exception using errcode='23514',message='UNBALANCED_JOURNAL';end if;
 v_period:=finance.wave3_lock_open_period(v_t,v_e,v_date);
 insert into finance.journal_entries(id,tenant_id,legal_entity_id,branch_id,fiscal_period_id,document_number,
 posting_date,source_type,source_id,currency_code,base_currency_code,exchange_rate,request_id,command_id,correlation_id,created_by)
 values(v_id,v_t,v_e,v_b,v_period,sales.wave3_reserve_document_number(v_t,v_e,v_b,'journal_entry',v_date,auth.uid()),
 v_date,p_source_type,p_source_id,p_doc->>'currency_code',p_doc->>'base_currency_code',(p_doc->>'exchange_rate')::numeric,
 p_request,p_command,p_request,auth.uid());
 for v_item in select value from jsonb_array_elements(p_lines) loop
 v_base:=(v_item->>'base_amount')::numeric;v_transaction:=(v_item->>'amount')::numeric;
 if v_base=0 then
 if v_transaction<>0 then raise exception using errcode='22023',message='AMOUNT_BELOW_BASE_PRECISION';end if;continue;end if;
 select * into v_account from finance.accounts where tenant_id=v_t and legal_entity_id=v_e
 and id=(v_item->>'account_id')::uuid and is_posting and status='active'
 and (currency_code is null or currency_code=p_doc->>'currency_code');
 if not found then raise exception using errcode='55000',message='ACCOUNT_MAPPING_INVALID';end if;
 v_ord:=v_ord+1;
 insert into finance.journal_lines(tenant_id,legal_entity_id,branch_id,journal_entry_id,line_number,account_id,party_id,
 source_line_id,currency_code,transaction_debit,transaction_credit,base_debit,base_credit,posting_date,created_by)
 values(v_t,v_e,v_b,v_id,v_ord,v_account.id,(p_doc->>'customer_id')::uuid,(v_item->>'source_line_id')::uuid,
 p_doc->>'currency_code',greatest(v_transaction,0),greatest(-v_transaction,0),greatest(v_base,0),greatest(-v_base,0),v_date,auth.uid());
 end loop;
 if v_ord<2 then raise exception using errcode='23514',message='UNBALANCED_JOURNAL';end if;
 update finance.journal_entries set status='posted' where id=v_id;return v_id;end $$;

create function finance.flow_jline(p_account uuid,p_amount numeric,p_base numeric,p_source uuid default null)
returns jsonb language sql immutable set search_path='' as $$
 select jsonb_build_object('account_id',p_account,'amount',p_amount::text,'base_amount',p_base::text,'source_line_id',p_source) $$;

create function sales.flow_price(p_kind text,p_doc jsonb,p_inputs jsonb)
returns jsonb language plpgsql security definer set search_path='' as $$
declare v_t uuid:=(p_doc->>'tenant_id')::uuid;v_e uuid:=(p_doc->>'legal_entity_id')::uuid;v_b uuid:=(p_doc->>'branch_id')::uuid;
 v_scale integer:=(p_doc->>'rounding_scale')::integer;v_input jsonb;v_result jsonb:='[]';v_line jsonb;
 v_product inventory.products%rowtype;v_order sales.sales_orders%rowtype;v_order_line sales.sales_order_lines%rowtype;
 v_delivery sales.deliveries%rowtype;v_dl sales.delivery_lines%rowtype;v_invoice sales.sales_invoices%rowtype;v_il sales.sales_invoice_lines%rowtype;
 v_q numeric;v_txq numeric;v_prior numeric;v_limit numeric;v_net numeric;v_tax numeric;v_price jsonb;v_ord integer:=0;
 v_amount numeric;v_total numeric:=0;v_tax_total numeric:=0;v_subtotal numeric:=0;v_discount numeric:=0;
 v_fraction numeric;v_gross numeric;v_discount_line numeric;
 v_prior_credit numeric;v_return_base numeric:=0;
begin
 if p_kind='customer_receipt' then
 v_amount:=sales.wave3_decimal_string(p_doc->'amount','Receipt amount',6,true,0,null)::numeric;
 if v_amount<=0 or v_amount<>round(v_amount,v_scale) then raise exception using errcode='22023',message='RECEIPT_AMOUNT_INVALID';end if;
 return jsonb_build_object('lines','[]'::jsonb,'subtotal',v_amount::text,'discount_total','0','tax_total','0','grand_total',v_amount::text,
 'base_total',round(v_amount*(p_doc->>'exchange_rate')::numeric,v_scale)::text);end if;
 if jsonb_typeof(p_inputs) is distinct from 'array' or jsonb_array_length(p_inputs) not between 1 and 500 then
 raise exception using errcode='22023',message='DOCUMENT_LINES_INVALID';end if;
 if (select count(*)<>count(distinct coalesce(x->>'line_id',x->>'id')) from jsonb_array_elements(p_inputs) x) then
 raise exception using errcode='22023',message='LINE_IDENTITIES_INVALID';end if;
 for v_input in select value from jsonb_array_elements(p_inputs) loop
 v_ord:=v_ord+1;v_order_line:=null;v_dl:=null;v_il:=null;v_line:=null;v_net:=0;v_tax:=0;
 v_q:=sales.wave3_decimal_string(v_input->'base_quantity','Base quantity',6,true,0,null)::numeric;
 if v_q<=0 then raise exception using errcode='22023',message='QUANTITY_INVALID';end if;
 if p_kind='sales_return' then
 if nullif(trim(p_doc->>'reason'),'') is null or coalesce(v_input->>'disposition','') not in ('saleable','no_restock') then
 raise exception using errcode='22023',message='RETURN_REASON_DISPOSITION_REQUIRED';end if;
 if v_input->>'sales_invoice_line_id' is not null then
 select l.* into v_il from sales.sales_invoice_lines l join sales.sales_invoices i on i.tenant_id=l.tenant_id and i.id=l.document_id
 where l.tenant_id=v_t and l.id=(v_input->>'sales_invoice_line_id')::uuid and i.legal_entity_id=v_e and i.branch_id=v_b
 and i.customer_id=(p_doc->>'customer_id')::uuid and i.status='posted' and i.document_date<=(p_doc->>'document_date')::date;
 if not found then raise exception using errcode='22023',message='RETURN_SOURCE_INVALID';end if;
 select * into v_invoice from sales.sales_invoices where id=v_il.document_id;
 if v_invoice.currency_code<>p_doc->>'currency_code' then raise exception using errcode='22023',message='SOURCE_CURRENCY_MISMATCH';end if;
 if v_invoice.exchange_rate<>(p_doc->>'exchange_rate')::numeric then
 raise exception using errcode='22023',message='RETURN_ORIGINAL_RATE_REQUIRED';end if;
 v_line:=v_il.snapshot;v_limit:=v_il.base_quantity;
 select coalesce(sum(l.base_quantity),0) into v_prior from sales.sales_return_lines l join sales.sales_returns r on r.id=l.document_id and r.tenant_id=l.tenant_id
 where l.tenant_id=v_t and l.sales_invoice_line_id=v_il.id and r.status='posted';
 v_net:=round(v_il.taxable_amount*(v_prior+v_q)/v_limit,v_scale)-round(v_il.taxable_amount*v_prior/v_limit,v_scale);
 v_tax:=round(v_il.tax_amount*(v_prior+v_q)/v_limit,v_scale)-round(v_il.tax_amount*v_prior/v_limit,v_scale);
 select coalesce(sum(rl.line_total),0) into v_prior_credit from sales.sales_return_lines rl
 join sales.sales_returns r on r.tenant_id=rl.tenant_id and r.id=rl.document_id
 join sales.sales_invoice_lines il on il.tenant_id=rl.tenant_id and il.id=rl.sales_invoice_line_id
 where rl.tenant_id=v_t and il.document_id=v_invoice.id and r.status='posted';
 v_prior_credit:=v_prior_credit+coalesce((select sum((x->>'line_total')::numeric) from jsonb_array_elements(v_result) x
 join sales.sales_invoice_lines il on il.tenant_id=v_t and il.id=(x->>'sales_invoice_line_id')::uuid where il.document_id=v_invoice.id),0);
 if v_invoice.grand_total>0 then
 v_return_base:=v_return_base+round(v_invoice.base_total*(v_prior_credit+v_net+v_tax)/v_invoice.grand_total,v_scale)
 -round(v_invoice.base_total*v_prior_credit/v_invoice.grand_total,v_scale);end if;
 v_input:=v_input||jsonb_build_object('delivery_line_id',v_il.delivery_line_id,'sales_order_line_id',v_il.sales_order_line_id);
 else
 select l.* into v_dl from sales.delivery_lines l join sales.deliveries d on d.id=l.document_id and d.tenant_id=l.tenant_id
 where l.tenant_id=v_t and l.id=(v_input->>'delivery_line_id')::uuid and d.legal_entity_id=v_e and d.branch_id=v_b
 and d.customer_id=(p_doc->>'customer_id')::uuid and d.status='posted' and d.document_date<=(p_doc->>'document_date')::date;
 if not found then raise exception using errcode='22023',message='RETURN_SOURCE_INVALID';end if;
 -- An invoiced delivery must be credited against its invoice, preserving AR links.
 if exists(select 1 from sales.sales_invoice_lines l join sales.sales_invoices i on i.id=l.document_id
 where l.tenant_id=v_t and l.delivery_line_id=v_dl.id and i.status='posted') then
 raise exception using errcode='22023',message='RETURN_INVOICE_SOURCE_REQUIRED';end if;
 v_line:=v_dl.snapshot;v_limit:=v_dl.base_quantity;
 select coalesce(sum(l.base_quantity),0) into v_prior from sales.sales_return_lines l join sales.sales_returns r on r.id=l.document_id
 where l.tenant_id=v_t and l.delivery_line_id=v_dl.id and r.status='posted';
 v_input:=v_input||jsonb_build_object('sales_order_line_id',v_dl.sales_order_line_id);
 end if;
 if v_prior+v_q>v_limit then raise exception using errcode='22023',message='SOURCE_QUANTITY_EXCEEDED';end if;
 else
 if v_input->>'delivery_line_id' is not null then
 select l.* into v_dl from sales.delivery_lines l join sales.deliveries d on d.id=l.document_id and d.tenant_id=l.tenant_id
 where l.tenant_id=v_t and l.id=(v_input->>'delivery_line_id')::uuid and d.legal_entity_id=v_e and d.branch_id=v_b
 and d.customer_id=(p_doc->>'customer_id')::uuid and d.status='posted' and d.document_date<=(p_doc->>'document_date')::date;
 if not found then raise exception using errcode='22023',message='DELIVERY_SOURCE_INVALID';end if;
 if v_input->>'sales_order_line_id' is not null and (v_input->>'sales_order_line_id')::uuid<>v_dl.sales_order_line_id then
 raise exception using errcode='22023',message='SOURCE_LINE_MISMATCH';end if;
 v_input:=v_input||jsonb_build_object('sales_order_line_id',v_dl.sales_order_line_id);
 select coalesce(sum(l.base_quantity),0) into v_prior from sales.sales_invoice_lines l join sales.sales_invoices i on i.id=l.document_id
 where l.tenant_id=v_t and l.delivery_line_id=v_dl.id and i.status='posted';
 if v_prior+v_q>v_dl.base_quantity then raise exception using errcode='22023',message='SOURCE_QUANTITY_EXCEEDED';end if;
 end if;
 if v_input->>'sales_order_line_id' is not null then
 select * into v_order_line from sales.sales_order_lines where tenant_id=v_t and legal_entity_id=v_e and branch_id=v_b
 and id=(v_input->>'sales_order_line_id')::uuid;
 select * into v_order from sales.sales_orders where tenant_id=v_t and id=v_order_line.sales_order_id;
 if v_order.id is null or v_order.customer_id<>(p_doc->>'customer_id')::uuid
 or v_order.status not in ('confirmed','partially_reserved','reserved','fulfilled')
 or v_order.order_date>(p_doc->>'document_date')::date
 or (p_doc->>'sales_order_id' is not null and v_order.id<>(p_doc->>'sales_order_id')::uuid)
 or v_order.currency_code<>p_doc->>'currency_code' then raise exception using errcode='22023',message='ORDER_SOURCE_INVALID';end if;
 v_line:=sales.flow_exact_json(to_jsonb(v_order_line));
 if p_kind='delivery' then
 if v_order.id<>(p_doc->>'sales_order_id')::uuid or v_order.warehouse_id<>(p_doc->>'warehouse_id')::uuid then
 raise exception using errcode='22023',message='DELIVERY_WAREHOUSE_INVALID';end if;
 v_limit:=v_order_line.base_ordered_quantity-v_order_line.cancelled_quantity;v_prior:=v_order_line.delivered_quantity;
 else
 if v_order_line.product_kind='stocked' and v_dl.id is null then raise exception using errcode='22023',message='STOCKED_INVOICE_REQUIRES_DELIVERY';end if;
 v_limit:=case when v_order_line.product_kind='stocked' then v_order_line.delivered_quantity else v_order_line.base_ordered_quantity-v_order_line.cancelled_quantity end;
 v_prior:=v_order_line.invoiced_quantity;
 v_net:=round(v_order_line.taxable_amount*(v_prior+v_q)/v_order_line.base_ordered_quantity,v_scale)-round(v_order_line.taxable_amount*v_prior/v_order_line.base_ordered_quantity,v_scale);
 v_tax:=round(v_order_line.tax_amount*(v_prior+v_q)/v_order_line.base_ordered_quantity,v_scale)-round(v_order_line.tax_amount*v_prior/v_order_line.base_ordered_quantity,v_scale);
 end if;
 if v_prior+v_q>v_limit then raise exception using errcode='22023',message='SOURCE_QUANTITY_EXCEEDED';end if;
 elsif p_kind='sales_invoice' then
 -- Saved snapshots use line_discount_amount and nullable percentage keys;
 -- reconstruct the public pricing input without treating JSON null as a value.
 v_input:=jsonb_strip_nulls(v_input);
 if not (v_input ? 'discount_percent') and not (v_input ? 'discount_amount') and v_input ? 'line_discount_amount' then
 v_input:=v_input||jsonb_build_object('discount_amount',v_input->'line_discount_amount');end if;
 v_price:=sales.wave3_price_lines(v_t,v_e,(p_doc->>'document_date')::date,p_doc->>'currency_code',jsonb_build_array(v_input),null,null);
 v_line:=v_price->'lines'->0;
 if v_line->>'product_kind'='stocked' then raise exception using errcode='22023',message='STOCKED_INVOICE_REQUIRES_DELIVERY';end if;
 v_net:=(v_line->>'taxable_amount')::numeric;v_tax:=(v_line->>'tax_amount')::numeric;
 else raise exception using errcode='22023',message='ORDER_SOURCE_REQUIRED';end if;
 end if;
 select * into v_product from inventory.products where tenant_id=v_t and legal_entity_id=v_e and id=(v_line->>'product_id')::uuid and status='active' and can_sell;
 if not found then raise exception using errcode='22023',message='PRODUCT_REFERENCE_INACTIVE';end if;
 if p_kind='sales_invoice' and v_order_line.id is null and v_product.kind='stocked' then
 raise exception using errcode='22023',message='STOCKED_INVOICE_REQUIRES_DELIVERY';end if;
 v_line:=v_line||jsonb_build_object('product_kind',v_product.kind);
 if not exists(select 1 from inventory.units where tenant_id=v_t and id=(v_line->>'unit_id')::uuid and status='active') then
 raise exception using errcode='22023',message='UNIT_REFERENCE_INACTIVE';end if;
 if p_kind<>'sales_return' and v_line->>'tax_definition_id' is not null and not exists(
 select 1 from finance.tax_definitions t where t.tenant_id=v_t and t.legal_entity_id=v_e and t.id=(v_line->>'tax_definition_id')::uuid
 and t.status='active' and t.version=(v_line->>'tax_definition_version')::bigint
 and (p_doc->>'document_date')::date>=t.valid_from and (t.valid_to is null or (p_doc->>'document_date')::date<=t.valid_to)) then
 raise exception using errcode='22023',message='SOURCE_TAX_CHANGED';end if;
 v_txq:=v_q*(v_line->>'conversion_denominator')::numeric/(v_line->>'conversion_numerator')::numeric;
 if v_txq<>round(v_txq,6) then raise exception using errcode='22023',message='UNIT_CONVERSION_INEXACT';end if;
 -- Prorate source gross and discount snapshots just as net/tax amounts are
 -- prorated, so a partial document never displays the full original discount.
 v_fraction:=case when v_il.id is not null then v_il.base_quantity when v_order_line.id is not null then v_order_line.base_ordered_quantity else v_q end;
 if p_kind='delivery' or (p_kind='sales_return' and v_il.id is null) then v_gross:=0;v_discount_line:=0;
 elsif v_il.id is not null or v_order_line.id is not null then
 v_gross:=round(coalesce((v_line->>'gross_amount')::numeric,0)*(v_prior+v_q)/v_fraction,v_scale)-round(coalesce((v_line->>'gross_amount')::numeric,0)*v_prior/v_fraction,v_scale);
 v_discount_line:=round((coalesce((v_line->>'line_discount_amount')::numeric,0)+coalesce((v_line->>'header_discount_amount')::numeric,0))*(v_prior+v_q)/v_fraction,v_scale)
 -round((coalesce((v_line->>'line_discount_amount')::numeric,0)+coalesce((v_line->>'header_discount_amount')::numeric,0))*v_prior/v_fraction,v_scale);
 else v_gross:=(v_line->>'gross_amount')::numeric;v_discount_line:=coalesce((v_line->>'line_discount_amount')::numeric,0);end if;
 v_line:=v_line||jsonb_build_object('line_id',coalesce(v_input->>'line_id',v_input->>'id'),
 'line_number',v_ord,'quantity',v_txq::numeric(20,6)::text,'base_quantity',v_q::numeric(20,6)::text,'tracking_mode',v_product.tracking_mode,
 'sales_order_line_id',v_input->>'sales_order_line_id','delivery_line_id',v_input->>'delivery_line_id',
 'sales_invoice_line_id',v_input->>'sales_invoice_line_id','tracking',coalesce(v_input->'tracking','{}'::jsonb),
 'disposition',v_input->>'disposition','taxable_amount',v_net::text,'tax_amount',v_tax::text,'line_total',(v_net+v_tax)::text,
 'gross_amount',v_gross::text,'line_discount_amount',v_discount_line::text,'header_discount_amount','0');
 v_total:=v_total+v_net+v_tax;v_tax_total:=v_tax_total+v_tax;v_subtotal:=v_subtotal+v_gross;v_discount:=v_discount+v_discount_line;
 v_result:=v_result||jsonb_build_array(v_line);
 end loop;
 -- Repeated source lines could each pass an independent residual check: reject them.
 if exists(select 1 from jsonb_array_elements(v_result) x where x->>'sales_invoice_line_id' is not null
 group by x->>'sales_invoice_line_id' having count(*)>1)
 or exists(select 1 from jsonb_array_elements(v_result) x where x->>'delivery_line_id' is not null
 group by x->>'delivery_line_id' having count(*)>1)
 or exists(select 1 from jsonb_array_elements(v_result) x where x->>'sales_order_line_id' is not null
 group by x->>'sales_order_line_id' having count(*)>1) then raise exception using errcode='22023',message='DUPLICATE_SOURCE_LINE';end if;
 return jsonb_build_object('lines',v_result,'subtotal',v_subtotal::text,'discount_total',v_discount::text,
 'tax_total',v_tax_total::text,'grand_total',v_total::text,'base_total',case when p_kind='sales_return' then v_return_base::text else round(v_total*(p_doc->>'exchange_rate')::numeric,v_scale)::text end);
end $$;

-- Explicit grants only; private helpers are invoked by the named command owner.
do $$ declare v_proc record;begin for v_proc in select n.nspname,p.proname,pg_get_function_identity_arguments(p.oid) args
 from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname in ('sales','finance') and p.proname like 'flow_%'
 and p.proname not in ('flow_read_allowed','flow_exact_json') loop
 execute format('revoke all on function %I.%I(%s) from public,anon,authenticated',v_proc.nspname,v_proc.proname,v_proc.args);
end loop;end $$;

-- AC-305..AC-308 command implementation. Each command is atomic and idempotent.
create function sales.flow_upsert(p_kind text,p_tenant_id uuid,p_legal_entity_id uuid,p_branch_id uuid,
 p_command_id uuid,p_idempotency_key uuid,p_client_timestamp timestamptz,p_payload jsonb,p_expected_entity_version bigint)
returns jsonb language plpgsql security definer set search_path='' as $$
declare v_table text:=sales.flow_table(p_kind);v_id uuid:=coalesce((p_payload->>'id')::uuid,gen_random_uuid());
 v_command text:='sales.'||p_kind||'.upsert';v_hash text;v_replay jsonb;v_before jsonb;v_doc jsonb;v_price jsonb;
 v_rate jsonb;v_scale integer;v_line jsonb;v_request uuid:=gen_random_uuid();v_cols text;v_values text;
 v_allowed text[]:=array['id','customer_id','document_date','due_date','currency_code','sales_order_id','warehouse_id',
 'cash_bank_account_id','external_reference','terms','notes','reason','tender_metadata','source_context'];
begin
 perform core.wave3_require_scope(p_tenant_id,sales.flow_permission(p_kind,'manage'),p_legal_entity_id,p_branch_id);
 if v_table is null or p_branch_id is null or p_client_timestamp is null or jsonb_typeof(p_payload) is distinct from 'object'
 or p_legal_entity_id is null then raise exception using errcode='22023',message='DOCUMENT_PAYLOAD_INVALID';end if;
 v_hash:=core.wave3_request_hash(v_command,p_command_id,p_tenant_id,p_legal_entity_id,p_branch_id,p_payload,p_expected_entity_version);
 v_replay:=core.wave3_replay(p_tenant_id,v_command,p_command_id,p_idempotency_key,v_hash);if v_replay is not null then return v_replay;end if;
 v_before:=sales.flow_document(p_kind,p_tenant_id,v_id,true);
 if v_before is not null then
 if (v_before->>'legal_entity_id')::uuid<>p_legal_entity_id or (v_before->>'branch_id')::uuid<>p_branch_id then
 raise exception using errcode='42501',message='DOCUMENT_SCOPE_INVALID';end if;
 perform core.wave3_assert_expected_version((v_before->>'version')::bigint,p_expected_entity_version,v_before);
 if v_before->>'status'<>'draft' then raise exception using errcode='55000',message='DOCUMENT_NOT_EDITABLE';end if;
 elsif p_expected_entity_version is not null then raise exception using errcode='40001',message='VERSION_CONFLICT';end if;
 if not exists(select 1 from crm.parties where tenant_id=p_tenant_id and id=(p_payload->>'customer_id')::uuid
 and status='active' and kind in ('customer','both')) then raise exception using errcode='22023',message='CUSTOMER_INACTIVE';end if;
 select rounding_scale into v_scale from core.legal_entities where tenant_id=p_tenant_id and id=p_legal_entity_id;
 v_rate:=finance.flow_rate(p_tenant_id,p_legal_entity_id,p_payload->>'currency_code',(p_payload->>'document_date')::date,(p_payload->>'exchange_rate_id')::uuid);
 select coalesce(jsonb_object_agg(key,value),'{}') into v_doc from jsonb_each(p_payload) where key=any(v_allowed);
 v_doc:=v_doc||v_rate||jsonb_build_object('id',v_id,'tenant_id',p_tenant_id,'legal_entity_id',p_legal_entity_id,
 'branch_id',p_branch_id,'document_type',p_kind,'status','draft','rounding_scale',v_scale,
 'due_date',coalesce(p_payload->>'due_date',p_payload->>'document_date'),'request_id',v_request,'command_id',p_command_id,
 'correlation_id',v_request,'client_timestamp',p_client_timestamp,'created_by',coalesce(v_before->>'created_by',auth.uid()::text),
 'updated_by',auth.uid(),'version',coalesce((v_before->>'version')::bigint,1),
 'created_at',coalesce(v_before->>'created_at',clock_timestamp()::text),'updated_at',clock_timestamp(),
 'source_context',coalesce(p_payload->'source_context','{}'::jsonb),'tender_metadata',coalesce(p_payload->'tender_metadata','{}'::jsonb),
 'document_number',v_before->>'document_number');
 if p_kind='delivery' and (v_doc->>'sales_order_id' is null or v_doc->>'warehouse_id' is null) then
 raise exception using errcode='22023',message='DELIVERY_SOURCE_REQUIRED';end if;
 if p_kind='customer_receipt' and not exists(select 1 from finance.cash_bank_accounts a where a.tenant_id=p_tenant_id
 and a.legal_entity_id=p_legal_entity_id and a.branch_id=p_branch_id and a.id=(v_doc->>'cash_bank_account_id')::uuid
 and a.status='active' and a.currency_code=v_doc->>'currency_code') then raise exception using errcode='22023',message='CASH_BANK_ACCOUNT_INVALID';end if;
 v_price:=sales.flow_price(p_kind,v_doc||jsonb_build_object('amount',p_payload->'amount'),p_payload->'lines');
 v_doc:=v_doc||(v_price-'lines');
 -- Explicitly populated record includes only whitelisted and server-owned fields.
 select string_agg(quote_ident(a.attname),',' order by a.attnum),string_agg('x.'||quote_ident(a.attname),',' order by a.attnum)
 into v_cols,v_values from pg_attribute a where a.attrelid=format('sales.%I',v_table)::regclass and a.attnum>0 and not a.attisdropped;
 if v_before is null then execute format('insert into sales.%I(%s) select %s from jsonb_populate_record(null::sales.%I,$1) x',v_table,v_cols,v_values,v_table) using v_doc;
 else
 execute format('update sales.%I d set (%s)=(select %s from jsonb_populate_record(null::sales.%I,$1) x) where d.tenant_id=$2 and d.id=$3',v_table,v_cols,v_values,v_table)
 using v_doc,p_tenant_id,v_id;
 execute format('delete from sales.%I where tenant_id=$1 and document_id=$2',sales.flow_lines_table(p_kind)) using p_tenant_id,v_id;
 end if;
 for v_line in select value from jsonb_array_elements(v_price->'lines') loop
 execute format('insert into sales.%I(id,tenant_id,legal_entity_id,branch_id,document_id,line_number,product_id,description,quantity,base_quantity,unit_id,sales_order_line_id,delivery_line_id,sales_invoice_line_id,taxable_amount,tax_amount,line_total,snapshot,created_by) values($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12,$13,$14,$15,$16,$17,$18,$19)',sales.flow_lines_table(p_kind))
 using (v_line->>'line_id')::uuid,p_tenant_id,p_legal_entity_id,p_branch_id,v_id,(v_line->>'line_number')::integer,
 (v_line->>'product_id')::uuid,v_line->>'description',(v_line->>'quantity')::numeric,(v_line->>'base_quantity')::numeric,
 (v_line->>'unit_id')::uuid,(v_line->>'sales_order_line_id')::uuid,(v_line->>'delivery_line_id')::uuid,
 (v_line->>'sales_invoice_line_id')::uuid,(v_line->>'taxable_amount')::numeric,(v_line->>'tax_amount')::numeric,
 (v_line->>'line_total')::numeric,v_line,auth.uid();end loop;
 v_doc:=sales.flow_document(p_kind,p_tenant_id,v_id);
 return core.wave3_finish_command(p_tenant_id,v_command,p_command_id,p_kind,v_id,p_idempotency_key,v_hash,v_before,v_doc,
 p_legal_entity_id,p_branch_id,coalesce(p_payload->'source_context','{}'),null,
 jsonb_build_array(jsonb_build_object('topic',v_command,'payload',jsonb_build_object('status','draft'))),'[]',v_request,v_request);
end $$;

create function sales.flow_revalidate(p_kind text,p_doc jsonb) returns jsonb
language plpgsql security definer set search_path='' as $$
declare v_price jsonb;v_inputs jsonb;v_rate jsonb;v_scale integer;begin
 if not exists(select 1 from crm.parties where tenant_id=(p_doc->>'tenant_id')::uuid and id=(p_doc->>'customer_id')::uuid
 and status='active' and kind in ('customer','both')) then raise exception using errcode='22023',message='CUSTOMER_INACTIVE';end if;
 v_rate:=finance.flow_rate((p_doc->>'tenant_id')::uuid,(p_doc->>'legal_entity_id')::uuid,p_doc->>'currency_code',
 (p_doc->>'document_date')::date,(p_doc->>'exchange_rate_id')::uuid);
 select rounding_scale into v_scale from core.legal_entities where id=(p_doc->>'legal_entity_id')::uuid;
 if (v_rate->>'exchange_rate')::numeric<>(p_doc->>'exchange_rate')::numeric or v_scale<>(p_doc->>'rounding_scale')::integer then
 raise exception using errcode='55000',message='DOCUMENT_RECALCULATION_REQUIRED';end if;
 select coalesce(jsonb_agg(x->'snapshot' order by (x->>'line_number')::integer),'[]') into v_inputs from jsonb_array_elements(p_doc->'lines') x;
 v_price:=sales.flow_price(p_kind,p_doc||jsonb_build_object('amount',p_doc->'grand_total'),v_inputs);
 if (v_price->>'grand_total')::numeric<>(p_doc->>'grand_total')::numeric
 or (v_price->>'tax_total')::numeric<>(p_doc->>'tax_total')::numeric
 or (v_price->>'base_total')::numeric<>(p_doc->>'base_total')::numeric
 or exists(select 1 from jsonb_array_elements(v_price->'lines') n join jsonb_array_elements(p_doc->'lines') o
 on n->>'line_id'=o->>'id' where (n->>'taxable_amount')::numeric<>(o->>'taxable_amount')::numeric
 or (n->>'tax_amount')::numeric<>(o->>'tax_amount')::numeric
 or n->>'product_kind' is distinct from o#>>'{snapshot,product_kind}'
 or n->>'tracking_mode' is distinct from o#>>'{snapshot,tracking_mode}') then
 raise exception using errcode='55000',message='DOCUMENT_RECALCULATION_REQUIRED';end if;return v_price;end $$;

create function sales.flow_transition(p_tenant_id uuid,p_legal_entity_id uuid,p_branch_id uuid,p_command_id uuid,
 p_idempotency_key uuid,p_client_timestamp timestamptz,p_payload jsonb,p_expected_entity_version bigint)
returns jsonb language plpgsql security definer set search_path='' as $$
declare v_kind text:=p_payload->>'document_type';v_id uuid:=(p_payload->>'document_id')::uuid;
 v_action text:=p_payload->>'action';v_decision text:=p_payload->>'decision';v_command text;
 v_doc jsonb;v_before jsonb;v_hash text;v_replay jsonb;v_to text;v_snapshot jsonb;
 v_workflow workflow.workflow_definitions%rowtype;v_request uuid:=gen_random_uuid();v_first integer;
 v_ar workflow.approval_requests%rowtype;v_step jsonb;v_number text;
begin
 v_command:='sales.'||v_kind||case when v_decision is null then '.transition' else '.decide' end;
 perform core.wave3_require_scope(p_tenant_id,case when v_decision is null then sales.flow_permission(v_kind,'manage') else 'workflow.approvals.decide' end,p_legal_entity_id,p_branch_id);
 if sales.flow_table(v_kind) is null or p_branch_id is null or p_client_timestamp is null then raise exception using errcode='22023',message='DOCUMENT_PAYLOAD_INVALID';end if;
 v_hash:=core.wave3_request_hash(v_command,p_command_id,p_tenant_id,p_legal_entity_id,p_branch_id,p_payload,p_expected_entity_version);
 v_replay:=core.wave3_replay(p_tenant_id,v_command,p_command_id,p_idempotency_key,v_hash);if v_replay is not null then return v_replay;end if;
 v_doc:=sales.flow_document(v_kind,p_tenant_id,v_id,true);v_before:=v_doc;
 if v_doc is null or (v_doc->>'legal_entity_id')::uuid<>p_legal_entity_id or (v_doc->>'branch_id')::uuid<>p_branch_id then
 raise exception using errcode='P0002',message='DOCUMENT_NOT_FOUND';end if;
 perform core.wave3_assert_expected_version((v_doc->>'version')::bigint,p_expected_entity_version,v_doc);
 if v_doc->>'status'='posted' then raise exception using errcode='55000',message='POSTED_DOCUMENT_IMMUTABLE';end if;
 v_snapshot:=v_doc->'workflow_snapshot';v_number:=v_doc->>'document_number';
 if v_decision is not null then
 if v_decision not in ('approved','rejected') or v_doc->>'status'<>'pending_approval' then raise exception using errcode='55000',message='APPROVAL_NOT_PENDING';end if;
 select * into v_ar from workflow.approval_requests where tenant_id=p_tenant_id and document_type=v_kind and document_id=v_id and status='submitted' for update;
 if not found then raise exception using errcode='55000',message='APPROVAL_REQUEST_NOT_FOUND';end if;
 if v_ar.submitted_by=auth.uid() then raise exception using errcode='42501',message='SEGREGATION_OF_DUTIES_VIOLATION';end if;
 select x into v_step from jsonb_array_elements(v_snapshot->'steps') x where (x->>'step_order')::integer=v_ar.current_step;
 if v_step is null or not exists(select 1 from core.memberships m join core.role_assignments ra on ra.tenant_id=m.tenant_id and ra.membership_id=m.id
 join core.roles r on r.id=ra.role_id and r.tenant_id=m.tenant_id
 where m.tenant_id=p_tenant_id and m.user_id=auth.uid() and m.status='active' and ra.role_id=(v_step->>'role_id')::uuid
 and (ra.legal_entity_id is null or ra.legal_entity_id=p_legal_entity_id) and (ra.branch_id is null or ra.branch_id=p_branch_id)
 and (not r.requires_mfa or auth.jwt()->>'aal'='aal2')) then raise exception using errcode='42501',message='APPROVAL_ROLE_REQUIRED';end if;
 if v_decision='rejected' and nullif(trim(p_payload->>'note'),'') is null then raise exception using errcode='22023',message='REASON_REQUIRED';end if;
 perform sales.flow_assert_transition(v_snapshot->'lifecycle','submitted',v_decision);
 insert into workflow.approval_decisions(tenant_id,approval_request_id,workflow_definition_id,workflow_revision,
 approval_matrix_step_id,step_order,actor_id,decision,note,amount,currency_code,request_id,command_id,correlation_id)
 values(p_tenant_id,v_ar.id,v_ar.workflow_definition_id,v_ar.workflow_revision,(v_step->>'id')::uuid,v_ar.current_step,
 auth.uid(),v_decision,p_payload->>'note',v_ar.amount,v_ar.currency_code,v_request,p_command_id,v_request);
 if v_decision='approved' then select min((x->>'step_order')::integer) into v_first from jsonb_array_elements(v_snapshot->'steps') x
 where (x->>'step_order')::integer>v_ar.current_step;end if;
 v_to:=case when v_decision='rejected' then 'rejected' when v_first is null then 'approved' else 'pending_approval' end;
 if v_first is null then update workflow.approval_requests set status=v_to,decision_by=auth.uid(),decision_note=p_payload->>'note',decided_at=clock_timestamp() where id=v_ar.id;
 else update workflow.approval_requests set current_step=v_first where id=v_ar.id;end if;
 elsif v_action='submit' then
 if v_doc->>'status'<>'draft' then raise exception using errcode='55000',message='DOCUMENT_NOT_EDITABLE';end if;
 perform sales.flow_revalidate(v_kind,v_doc);
 select * into v_workflow from workflow.workflow_definitions where tenant_id=p_tenant_id and document_type=v_kind and status='active'
 and (legal_entity_id is null or legal_entity_id=p_legal_entity_id) order by (legal_entity_id is not null) desc limit 1;
 if not found then raise exception using errcode='55000',message='WORKFLOW_CONFIGURATION_ERROR';end if;
 select jsonb_build_object('definition_id',v_workflow.id,'revision',v_workflow.revision,'lifecycle',v_workflow.lifecycle,
 'steps',coalesce(jsonb_agg(sales.flow_exact_json(to_jsonb(s)) order by s.step_order),'[]'::jsonb)) into v_snapshot
 from workflow.approval_matrix_steps s where s.tenant_id=p_tenant_id and s.workflow_definition_id=v_workflow.id and s.status='active'
 and (s.currency_code is null or s.currency_code=v_doc->>'currency_code')
 and (s.minimum_amount is null or (v_doc->>'grand_total')::numeric>=s.minimum_amount)
 and (s.maximum_amount is null or (v_doc->>'grand_total')::numeric<=s.maximum_amount);
 if v_workflow.lifecycle->'requires_approval' is distinct from 'false'::jsonb then
 select min((x->>'step_order')::integer) into v_first from jsonb_array_elements(v_snapshot->'steps') x;
 if v_first is null then raise exception using errcode='55000',message='WORKFLOW_CONFIGURATION_ERROR';end if;end if;
 v_to:=case when v_first is null then 'submitted' else 'pending_approval' end;
 perform sales.flow_assert_transition(v_workflow.lifecycle,'draft','submitted');
 v_number:=coalesce(v_number,sales.wave3_reserve_document_number(p_tenant_id,p_legal_entity_id,p_branch_id,v_kind,(v_doc->>'document_date')::date,auth.uid()));
 if v_first is not null then insert into workflow.approval_requests(tenant_id,legal_entity_id,branch_id,document_type,document_id,status,
 submitted_by,workflow_definition_id,workflow_revision,current_step,amount,currency_code,command_id,request_id,correlation_id)
 values(p_tenant_id,p_legal_entity_id,p_branch_id,v_kind,v_id,'submitted',auth.uid(),v_workflow.id,v_workflow.revision,v_first,
 (v_doc->>'grand_total')::numeric,v_doc->>'currency_code',p_command_id,v_request,v_request);end if;
 elsif v_action in ('recall','cancel') then
 if nullif(trim(p_payload->>'reason'),'') is null then raise exception using errcode='22023',message='REASON_REQUIRED';end if;
 if v_snapshot is null and v_doc->>'status'='draft' then
 select jsonb_build_object('lifecycle',lifecycle) into v_snapshot from workflow.workflow_definitions
 where tenant_id=p_tenant_id and document_type=v_kind and status='active'
 and (legal_entity_id is null or legal_entity_id=p_legal_entity_id) order by (legal_entity_id is not null) desc limit 1;
 end if;
 v_to:=case when v_action='recall' then 'draft' else 'cancelled' end;
 perform sales.flow_assert_transition(v_snapshot->'lifecycle',v_doc->>'status',v_to);
 update workflow.approval_requests set status='cancelled',decision_by=auth.uid(),decision_note=p_payload->>'reason',decided_at=clock_timestamp()
 where tenant_id=p_tenant_id and document_type=v_kind and document_id=v_id and status='submitted';
 if v_action='recall' then v_snapshot:=null;end if;
 else raise exception using errcode='22023',message='DOCUMENT_ACTION_INVALID';end if;
 execute format('update sales.%I set status=$1,workflow_snapshot=$2,document_number=$3,submitted_by=case when $4=''submit'' then $5 else submitted_by end,updated_by=$5,request_id=$6,command_id=$7,correlation_id=$6,client_timestamp=$8 where tenant_id=$9 and id=$10',sales.flow_table(v_kind))
 using v_to,v_snapshot,v_number,v_action,auth.uid(),v_request,p_command_id,p_client_timestamp,p_tenant_id,v_id;
 return core.wave3_finish_command(p_tenant_id,v_command,p_command_id,v_kind,v_id,p_idempotency_key,v_hash,v_before,
 sales.flow_document(v_kind,p_tenant_id,v_id),p_legal_entity_id,p_branch_id,coalesce(p_payload->'source_context','{}'),
 jsonb_build_object('from_status',v_doc->>'status','to_status',v_to,'reason',coalesce(p_payload->>'reason',p_payload->>'note')),
 jsonb_build_array(jsonb_build_object('topic',v_command,'payload',jsonb_build_object('status',v_to))),'[]',v_request,v_request);
end $$;

-- Keep generic transition signatures and preserve the latest AC-304 implementation.
-- A tiny dispatch branch is added to each existing function; all original paths remain.
do $$ declare v_name text;v_definition text;v_marker integer;v_dispatch text;begin
 foreach v_name in array array['transition_operational_document','decide_operational_approval'] loop
 select pg_get_functiondef(p.oid) into v_definition from pg_proc p join pg_namespace n on n.oid=p.pronamespace
 where n.nspname='api' and p.proname=v_name and p.pronargs=8;
 v_marker:=strpos(v_definition,E'\nbegin\n');
 if v_marker=0 then raise exception 'Operational dispatch integration requires a reviewed function body';end if;
 v_dispatch:=E'\n  if p_payload->>''document_type'' in (''delivery'',''sales_invoice'',''customer_receipt'',''sales_return'') then\n    return sales.flow_transition(p_tenant_id,p_legal_entity_id,p_branch_id,p_command_id,p_idempotency_key,p_client_timestamp,p_payload,p_expected_entity_version);\n  end if;';
 v_definition:=overlay(v_definition placing E'\nbegin'||v_dispatch||E'\n' from v_marker for 7);
 execute v_definition;
 end loop;end $$;

-- Declare typed named draft commands while sharing their invariants privately.
do $$ declare v_kind text;v_name text;begin
 for v_kind,v_name in select * from (values ('delivery','upsert_delivery'),('sales_invoice','upsert_sales_invoice'),
 ('customer_receipt','upsert_customer_receipt'),('sales_return','upsert_sales_return')) x loop
 execute format($ddl$create function api.%I(p_tenant_id uuid,p_legal_entity_id uuid,p_branch_id uuid,p_command_id uuid,
 p_idempotency_key uuid,p_client_timestamp timestamptz,p_payload jsonb,p_expected_entity_version bigint default null)
 returns jsonb language sql security definer set search_path='' as $body$
 select sales.flow_upsert(%L,p_tenant_id,p_legal_entity_id,p_branch_id,p_command_id,p_idempotency_key,p_client_timestamp,p_payload,p_expected_entity_version) $body$ $ddl$,v_name,v_kind);
 execute format('revoke all on function api.%I(uuid,uuid,uuid,uuid,uuid,timestamptz,jsonb,bigint) from public,anon,authenticated',v_name);
 execute format('grant execute on function api.%I(uuid,uuid,uuid,uuid,uuid,timestamptz,jsonb,bigint) to authenticated',v_name);
 end loop;end $$;
revoke all on function sales.flow_upsert(text,uuid,uuid,uuid,uuid,uuid,timestamptz,jsonb,bigint),sales.flow_revalidate(text,jsonb),
 sales.flow_transition(uuid,uuid,uuid,uuid,uuid,timestamptz,jsonb,bigint) from public,anon,authenticated;

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

create function finance.flow_allocate(p_source uuid,p_target uuid,p_tenant uuid,p_entity uuid,p_branch uuid,
 p_payload jsonb,p_date date,p_request uuid,p_command uuid)
returns jsonb language plpgsql security definer set search_path='' as $$
declare v_s finance.open_items%rowtype;v_t finance.open_items%rowtype;v_sr jsonb;v_tr jsonb;
 v_source numeric;v_target numeric;v_write numeric;v_discount numeric;v_sb numeric;v_tb numeric;v_ab numeric;
 v_fx numeric;v_rate finance.exchange_rates%rowtype;v_scale integer;v_conversion numeric:=1;v_id uuid:=gen_random_uuid();
 v_journal uuid;v_lines jsonb:='[]';v_doc jsonb;v_control uuid;v_prior numeric;v_adjust numeric;
begin
 perform 1 from finance.open_items where tenant_id=p_tenant and id in (p_source,p_target) order by id for update;
 select * into v_s from finance.open_items where tenant_id=p_tenant and legal_entity_id=p_entity and branch_id=p_branch and id=p_source;
 select * into v_t from finance.open_items where tenant_id=p_tenant and legal_entity_id=p_entity and branch_id=p_branch and id=p_target;
 if v_s.id is null or v_t.id is null or v_s.party_id<>v_t.party_id or v_s.original_amount>=0 or v_t.original_amount<=0
 or v_s.kind<>'AR' or v_t.kind<>'AR' or v_s.base_currency_code<>v_t.base_currency_code
 or p_date<greatest(v_s.posting_date,v_t.posting_date) then raise exception using errcode='22023',message='ALLOCATION_SOURCE_INVALID';end if;
 if exists(select 1 from finance.open_item_allocations where tenant_id=p_tenant and
 (source_open_item_id in (p_source,p_target) or target_open_item_id in (p_source,p_target)) and posting_date>p_date) then
 raise exception using errcode='22023',message='ALLOCATION_DATE_BEFORE_LATEST';end if;
 select rounding_scale into v_scale from core.legal_entities where id=p_entity and tenant_id=p_tenant;
 v_source:=sales.wave3_decimal_string(p_payload->'source_amount','Source amount',6,true,0,null)::numeric;
 v_target:=sales.wave3_decimal_string(p_payload->'transaction_amount','Target amount',6,true,0,null)::numeric;
 v_write:=sales.wave3_decimal_string(coalesce(p_payload->'write_off','"0"'),'Write-off',6,true,0,null)::numeric;
 v_discount:=sales.wave3_decimal_string(coalesce(p_payload->'discount_amount','"0"'),'Discount',6,true,0,null)::numeric;
 if v_source<=0 or v_target<=0 or v_source<>round(v_source,v_scale) or v_target<>round(v_target,v_scale)
 or v_write<>round(v_write,v_scale) or v_discount<>round(v_discount,v_scale) then raise exception using errcode='22023',message='ALLOCATION_AMOUNT_INVALID';end if;
 if v_write+v_discount>0 then
 perform core.wave3_require_scope(p_tenant,'finance.receipts.adjust',p_entity,p_branch);
 if nullif(trim(p_payload->>'reason'),'') is null then raise exception using errcode='22023',message='REASON_REQUIRED';end if;end if;
 if v_s.currency_code<>v_t.currency_code then
 select * into v_rate from finance.exchange_rates where tenant_id=p_tenant and legal_entity_id=p_entity and status='active'
 and id=(p_payload->>'exchange_rate_id')::uuid and source_currency_code=v_s.currency_code and target_currency_code=v_t.currency_code and effective_date<=p_date;
 if not found then raise exception using errcode='22023',message='ALLOCATION_EXCHANGE_RATE_REQUIRED';end if;v_conversion:=v_rate.rate;
 end if;
 if round(v_source*v_conversion,v_scale)<>v_target then raise exception using errcode='22023',message='ALLOCATION_CURRENCY_MISMATCH';end if;
 v_sr:=finance.flow_residual(p_tenant,p_source);v_tr:=finance.flow_residual(p_tenant,p_target);
 if v_source>-(v_sr->>'amount')::numeric or v_target+v_write+v_discount>(v_tr->>'amount')::numeric then
 raise exception using errcode='22023',message='ALLOCATION_EXCEEDED';end if;
 v_prior:=v_s.original_amount-(v_sr->>'amount')::numeric;
 v_sb:=round((-v_s.original_base_amount)*(-v_prior+v_source)/(-v_s.original_amount),v_scale)-round((-v_s.original_base_amount)*(-v_prior)/(-v_s.original_amount),v_scale);
 v_prior:=v_t.original_amount-(v_tr->>'amount')::numeric;
 v_tb:=round(v_t.original_base_amount*(v_prior+v_target)/v_t.original_amount,v_scale)-round(v_t.original_base_amount*v_prior/v_t.original_amount,v_scale);
 v_ab:=round(v_t.original_base_amount*(v_prior+v_target+v_write+v_discount)/v_t.original_amount,v_scale)-round(v_t.original_base_amount*(v_prior+v_target)/v_t.original_amount,v_scale);
 if v_sb<=0 or v_tb<=0 then raise exception using errcode='22023',message='AMOUNT_BELOW_BASE_PRECISION';end if;
 v_fx:=v_sb-v_tb;
 v_doc:=jsonb_build_object('tenant_id',p_tenant,'legal_entity_id',p_entity,'branch_id',p_branch,'document_date',p_date,
 'customer_id',v_s.party_id,'currency_code',v_s.base_currency_code,'base_currency_code',v_s.base_currency_code,'exchange_rate','1');
 if v_fx<>0 or v_ab<>0 then
 v_control:=finance.flow_mapping(p_tenant,p_entity,'receivable_control',v_s.base_currency_code);
 if v_fx<>0 then
 v_lines:=v_lines||jsonb_build_array(finance.flow_jline(v_control,v_fx,v_fx),finance.flow_jline(
 finance.flow_mapping(p_tenant,p_entity,case when v_fx>0 then 'exchange_gain' else 'exchange_loss' end,v_s.base_currency_code),-v_fx,-v_fx));end if;
 if v_ab>0 then
 v_lines:=v_lines||jsonb_build_array(finance.flow_jline(v_control,-v_ab,-v_ab));
 v_adjust:=round(v_ab*v_write/(v_write+v_discount),v_scale);
 if v_adjust>0 then v_lines:=v_lines||jsonb_build_array(finance.flow_jline(finance.flow_mapping(p_tenant,p_entity,'write_off',v_s.base_currency_code),v_adjust,v_adjust));end if;
 if v_ab-v_adjust>0 then v_lines:=v_lines||jsonb_build_array(finance.flow_jline(finance.flow_mapping(p_tenant,p_entity,'settlement_discount',v_s.base_currency_code),v_ab-v_adjust,v_ab-v_adjust));end if;
 end if;
 v_journal:=finance.flow_post_journal(v_doc,v_lines,'customer_allocation',v_id,p_request,p_command);end if;
 insert into finance.open_item_allocations(id,tenant_id,legal_entity_id,branch_id,source_open_item_id,target_open_item_id,
 source_amount,transaction_amount,source_base_amount,target_base_amount,exchange_difference,write_off,discount_amount,
 adjustment_base_amount,exchange_rate_id,conversion_rate,posting_date,reason,journal_entry_id,request_id,command_id,correlation_id,created_by)
 values(v_id,p_tenant,p_entity,p_branch,p_source,p_target,v_source,v_target,v_sb,v_tb,v_fx,v_write,v_discount,v_ab,v_rate.id,v_conversion,
 p_date,p_payload->>'reason',v_journal,p_request,p_command,p_request,auth.uid());
 return jsonb_build_object('allocation_id',v_id,'journal_entry_id',v_journal,'source_open_item_id',p_source,'target_open_item_id',p_target,
 'source_amount',v_source::text,'transaction_amount',v_target::text,'exchange_difference',v_fx::text,
 'source_residual',finance.flow_residual(p_tenant,p_source),'target_residual',finance.flow_residual(p_tenant,p_target));end $$;

create function api.allocate_customer_receipt(p_tenant_id uuid,p_legal_entity_id uuid,p_branch_id uuid,p_command_id uuid,
 p_idempotency_key uuid,p_client_timestamp timestamptz,p_payload jsonb,p_expected_entity_version bigint default null)
returns jsonb language plpgsql security definer set search_path='' as $$
declare v_command text:='finance.customer_receipt.allocate';v_hash text;v_replay jsonb;v_source finance.open_items%rowtype;
 v_item jsonb;v_result jsonb;v_results jsonb:='[]';v_request uuid:=gen_random_uuid();v_date date:=(p_payload->>'posting_date')::date;v_id uuid;
begin
 perform core.wave3_require_scope(p_tenant_id,'finance.receipts.allocate',p_legal_entity_id,p_branch_id);
 if p_legal_entity_id is null or p_branch_id is null or p_client_timestamp is null or v_date is null
 or jsonb_typeof(p_payload->'allocations') is distinct from 'array' or jsonb_array_length(p_payload->'allocations') not between 1 and 500 then
 raise exception using errcode='22023',message='ALLOCATION_PAYLOAD_INVALID';end if;
 v_hash:=core.wave3_request_hash(v_command,p_command_id,p_tenant_id,p_legal_entity_id,p_branch_id,p_payload,p_expected_entity_version);
 v_replay:=core.wave3_replay(p_tenant_id,v_command,p_command_id,p_idempotency_key,v_hash);if v_replay is not null then return v_replay;end if;
 select * into v_source from finance.open_items where tenant_id=p_tenant_id and legal_entity_id=p_legal_entity_id and branch_id=p_branch_id and id=(p_payload->>'source_open_item_id')::uuid;
 if not found or v_source.original_amount>=0 then raise exception using errcode='22023',message='ALLOCATION_SOURCE_INVALID';end if;
 perform 1 from crm.parties where tenant_id=p_tenant_id and id=v_source.party_id and status='active' for update;
 if not found then raise exception using errcode='22023',message='CUSTOMER_INACTIVE';end if;
 perform finance.wave3_lock_open_period(p_tenant_id,p_legal_entity_id,v_date);
 if v_date>(clock_timestamp() at time zone 'UTC')::date then raise exception using errcode='22023',message='FUTURE_POSTING_DATE';end if;
 for v_id in select id from finance.open_items where tenant_id=p_tenant_id and (id=v_source.id or id in
 (select (x->>'target_open_item_id')::uuid from jsonb_array_elements(p_payload->'allocations') x)) order by id loop
 perform 1 from finance.open_items where id=v_id for update;end loop;
 for v_item in select value from jsonb_array_elements(p_payload->'allocations') loop
 v_result:=finance.flow_allocate(v_source.id,(v_item->>'target_open_item_id')::uuid,p_tenant_id,p_legal_entity_id,p_branch_id,v_item,v_date,v_request,p_command_id);
 v_results:=v_results||jsonb_build_array(v_result);end loop;
 perform finance.flow_refresh_credit(jsonb_build_object('tenant_id',p_tenant_id,'legal_entity_id',p_legal_entity_id,'branch_id',p_branch_id,'customer_id',v_source.party_id));
 return core.wave3_finish_command(p_tenant_id,v_command,p_command_id,'customer_allocation',p_command_id,p_idempotency_key,v_hash,null,
 jsonb_build_object('id',p_command_id,'source_open_item_id',v_source.id,'allocations',v_results,'source_residual',finance.flow_residual(p_tenant_id,v_source.id)),
 p_legal_entity_id,p_branch_id,coalesce(p_payload->'source_context','{}'),
 jsonb_build_object('from_status','open','to_status','allocated'),
 jsonb_build_array(jsonb_build_object('topic',v_command,'payload',jsonb_build_object('source_open_item_id',v_source.id))),'[]',v_request,v_request);end $$;

-- Bounded exact report: no aggregate ever silently drops rows.
create function api.customer_statement(p_tenant_id uuid,p_legal_entity_id uuid,p_branch_id uuid,p_customer_id uuid,
 p_currency_code text,p_as_of date,p_buckets integer[] default array[30,60,90])
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare v_rows jsonb;v_amount numeric;v_base numeric;v_bucket jsonb;v_count integer;begin
 perform core.wave3_require_scope(p_tenant_id,'finance.receivables.view',p_legal_entity_id,p_branch_id);
 if p_branch_id is null or p_customer_id is null or p_as_of is null or p_as_of>(now() at time zone 'UTC')::date
 or p_currency_code is null or p_currency_code!~'^[A-Z]{3}$'
 or p_buckets is null or cardinality(p_buckets) not between 1 and 12 or exists(select 1 from unnest(p_buckets) x where x is null or x<=0)
 or p_buckets<>(select array_agg(distinct x order by x) from unnest(p_buckets) x) then
 raise exception using errcode='22023',message='STATEMENT_FILTER_INVALID';end if;
 select count(*) into v_count from (select id from finance.open_items where tenant_id=p_tenant_id and legal_entity_id=p_legal_entity_id
 and branch_id=p_branch_id and party_id=p_customer_id and kind='AR' and currency_code=p_currency_code and posting_date<=p_as_of limit 10001) bounded;
 if v_count>10000 then raise exception using errcode='54000',message='LIMIT_EXCEEDED';end if;
 with items as (select o.*,finance.flow_residual(p_tenant_id,o.id,p_as_of) residual from finance.open_items o
 where o.tenant_id=p_tenant_id and o.legal_entity_id=p_legal_entity_id and o.branch_id=p_branch_id and o.party_id=p_customer_id
 and o.kind='AR' and o.currency_code=p_currency_code and o.posting_date<=p_as_of), rows as (
 select id,source_type,source_id,document_number,currency_code,posting_date,due_date,original_amount::text,original_base_amount::text,
 residual->>'amount' as open_amount,residual->>'base_amount' as open_base_amount,
 case when original_amount<0 then -1 when due_date>=p_as_of then 0 else
 1+(select count(*) from unnest(p_buckets) b where p_as_of-due_date>b) end bucket from items)
 select coalesce(jsonb_agg(to_jsonb(rows) order by posting_date,id),'[]'),coalesce(sum(open_amount::numeric),0),coalesce(sum(open_base_amount::numeric),0)
 into v_rows,v_amount,v_base from rows;
 select coalesce(jsonb_agg(jsonb_build_object('bucket',bucket,'amount',amount::text,'base_amount',base_amount::text) order by bucket),'[]') into v_bucket
 from (select (x->>'bucket')::integer bucket,sum((x->>'open_amount')::numeric) amount,sum((x->>'open_base_amount')::numeric) base_amount
 from jsonb_array_elements(v_rows) x group by (x->>'bucket')::integer) b;
 return jsonb_build_object('customer_id',p_customer_id,'currency_code',p_currency_code,'as_of',p_as_of,
 'rows',v_rows,'aging',v_bucket,'bucket_days',p_buckets,'open_amount',v_amount::text,'open_base_amount',v_base::text,
 'basis','posting_date','unapplied_credits_separate',true);end $$;

-- Private RLS-compliant residual views for current item and receipt detail.
create function finance.flow_visible_residual(p_tenant uuid,p_id uuid) returns jsonb
language plpgsql stable security definer set search_path='' as $$
declare v_o finance.open_items%rowtype;begin select * into v_o from finance.open_items where tenant_id=p_tenant and id=p_id;
 if not found or not core.is_tenant_member(p_tenant) or not core.has_permission(p_tenant,'finance.receivables.view',v_o.legal_entity_id,v_o.branch_id) then return null;end if;
 return finance.flow_residual(p_tenant,p_id);end $$;
create view api.receivable_balances with(security_invoker=true) as
select o.id,o.tenant_id,o.legal_entity_id,o.branch_id,o.party_id,o.currency_code,o.source_type,o.source_id,o.posting_date,o.due_date,
 sales.flow_exact_json(to_jsonb(o))||finance.flow_visible_residual(o.tenant_id,o.id) as detail from finance.open_items o;

revoke all on function finance.flow_allocate(uuid,uuid,uuid,uuid,uuid,jsonb,date,uuid,uuid),
 api.allocate_customer_receipt(uuid,uuid,uuid,uuid,uuid,timestamptz,jsonb,bigint),
 api.customer_statement(uuid,uuid,uuid,uuid,text,date,integer[]),finance.flow_visible_residual(uuid,uuid) from public,anon,authenticated;
grant execute on function api.allocate_customer_receipt(uuid,uuid,uuid,uuid,uuid,timestamptz,jsonb,bigint),
 api.customer_statement(uuid,uuid,uuid,uuid,text,date,integer[]),finance.flow_visible_residual(uuid,uuid) to authenticated;
revoke all on api.receivable_balances from public,anon,authenticated;
grant select on api.receivable_balances to authenticated;
notify pgrst,'reload schema';

-- Governed posting prerequisites; no client has direct table writes.
create function api.upsert_receivables_setup(p_tenant_id uuid,p_legal_entity_id uuid,p_branch_id uuid,p_command_id uuid,
 p_idempotency_key uuid,p_client_timestamp timestamptz,p_payload jsonb,p_expected_entity_version bigint default null)
returns jsonb language plpgsql security definer set search_path='' as $$
declare v_resource text:=p_payload->>'resource';v_id uuid:=coalesce((p_payload->>'id')::uuid,gen_random_uuid());
 v_command text:='finance.receivables_setup.upsert';v_request uuid:=gen_random_uuid();v_hash text;v_replay jsonb;
 v_before jsonb;v_after jsonb;v_mapping finance.posting_mappings%rowtype;v_bank finance.cash_bank_accounts%rowtype;
 v_purpose text:=p_payload->>'purpose';v_account uuid:=(p_payload->>'account_id')::uuid;
begin
 perform core.wave3_require_scope(p_tenant_id,'finance.setup.manage',p_legal_entity_id,p_branch_id);
 if p_legal_entity_id is null or p_branch_id is null or p_client_timestamp is null or coalesce(v_resource,'') not in ('posting_mapping','cash_bank_account') then
 raise exception using errcode='22023',message='SETUP_PAYLOAD_INVALID';end if;
 v_hash:=core.wave3_request_hash(v_command,p_command_id,p_tenant_id,p_legal_entity_id,p_branch_id,p_payload,p_expected_entity_version);
 v_replay:=core.wave3_replay(p_tenant_id,v_command,p_command_id,p_idempotency_key,v_hash);if v_replay is not null then return v_replay;end if;
 perform pg_advisory_xact_lock(hashtextextended(p_tenant_id::text||':'||p_legal_entity_id::text||':receivables_setup',0));
 if v_resource='posting_mapping' then
 select * into v_mapping from finance.posting_mappings where tenant_id=p_tenant_id and legal_entity_id=p_legal_entity_id and purpose=v_purpose for update;
 if found then v_id:=v_mapping.id;v_before:=sales.flow_exact_json(to_jsonb(v_mapping));
 perform core.wave3_assert_expected_version(v_mapping.version,p_expected_entity_version,v_before);
 if (v_mapping.account_id<>v_account or coalesce(p_payload->>'status','active')<>v_mapping.status)
 and exists(select 1 from finance.journal_entries where tenant_id=p_tenant_id and legal_entity_id=p_legal_entity_id) then
 raise exception using errcode='55000',message='POSTING_MAPPING_IN_USE';end if;
 elsif p_expected_entity_version is not null then raise exception using errcode='40001',message='VERSION_CONFLICT';end if;
 perform finance.flow_account(p_tenant_id,p_legal_entity_id,v_account,
 case v_purpose when 'receivable_control' then 'asset' when 'output_tax' then 'liability' when 'exchange_gain' then 'revenue' else 'expense' end,
 (select currency_code from core.legal_entities where id=p_legal_entity_id));
 insert into finance.posting_mappings(id,tenant_id,legal_entity_id,purpose,account_id,status,created_by,updated_by)
 values(v_id,p_tenant_id,p_legal_entity_id,v_purpose,v_account,coalesce(p_payload->>'status','active'),auth.uid(),auth.uid())
 on conflict(tenant_id,legal_entity_id,purpose) do update set account_id=excluded.account_id,status=excluded.status,updated_by=auth.uid();
 select sales.flow_exact_json(to_jsonb(m)) into v_after from finance.posting_mappings m where id=v_id;
 else
 select * into v_bank from finance.cash_bank_accounts where tenant_id=p_tenant_id and id=v_id for update;
 if found then
 if v_bank.legal_entity_id<>p_legal_entity_id or v_bank.branch_id<>p_branch_id then raise exception using errcode='42501',message='DOCUMENT_SCOPE_INVALID';end if;
 v_before:=sales.flow_exact_json(to_jsonb(v_bank));perform core.wave3_assert_expected_version(v_bank.version,p_expected_entity_version,v_before);
 if (v_bank.account_id<>v_account or v_bank.currency_code<>p_payload->>'currency_code')
 and exists(select 1 from sales.customer_receipts where tenant_id=p_tenant_id and cash_bank_account_id=v_id and status='posted') then
 raise exception using errcode='55000',message='CASH_BANK_ACCOUNT_IN_USE';end if;
 elsif p_expected_entity_version is not null then raise exception using errcode='40001',message='VERSION_CONFLICT';end if;
 perform finance.flow_account(p_tenant_id,p_legal_entity_id,v_account,'asset',p_payload->>'currency_code');
 if not exists(select 1 from core.currencies where code=p_payload->>'currency_code' and active) then raise exception using errcode='22023',message='CURRENCY_INVALID';end if;
 insert into finance.cash_bank_accounts(id,tenant_id,legal_entity_id,branch_id,code,name,account_kind,account_id,currency_code,status,created_by,updated_by)
 values(v_id,p_tenant_id,p_legal_entity_id,p_branch_id,p_payload->>'code',p_payload->>'name',p_payload->>'account_kind',v_account,
 p_payload->>'currency_code',coalesce(p_payload->>'status','active'),auth.uid(),auth.uid())
 on conflict(id) do update set code=excluded.code,name=excluded.name,account_kind=excluded.account_kind,
 account_id=excluded.account_id,currency_code=excluded.currency_code,status=excluded.status,updated_by=auth.uid();
 select sales.flow_exact_json(to_jsonb(b)) into v_after from finance.cash_bank_accounts b where id=v_id;
 end if;
 return core.wave3_finish_command(p_tenant_id,v_command,p_command_id,v_resource,v_id,p_idempotency_key,v_hash,v_before,v_after,
 p_legal_entity_id,p_branch_id,'{}',null,jsonb_build_array(jsonb_build_object('topic',v_command,'payload',jsonb_build_object('resource',v_resource))),'[]',v_request,v_request);
end $$;
revoke all on function api.upsert_receivables_setup(uuid,uuid,uuid,uuid,uuid,timestamptz,jsonb,bigint) from public,anon,authenticated;
grant execute on function api.upsert_receivables_setup(uuid,uuid,uuid,uuid,uuid,timestamptz,jsonb,bigint) to authenticated;
create policy setup_or_receipt_reference on finance.cash_bank_accounts for select to authenticated using(
 core.is_tenant_member(tenant_id) and (core.has_permission(tenant_id,'finance.receipts.manage',legal_entity_id,branch_id)
 or core.has_permission(tenant_id,'finance.setup.view',legal_entity_id,branch_id)
 or core.has_permission(tenant_id,'finance.setup.manage',legal_entity_id,branch_id)));
notify pgrst,'reload schema';

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
