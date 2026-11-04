-- REVIEWED TARGET: xpdoufauvrbdmxgngetv. Complete buffer only. NEVER select a fragment.
-- No COMMIT, migration ledger insert, Auth fixture, sender enablement or live order.
begin;
set transaction isolation level repeatable read;
set local lock_timeout='2s';
set local statement_timeout='45s';
do $guard$ begin
 if current_setting('server_version_num')::integer/10000<>17 then raise exception 'POSTGRES_17_REQUIRED'; end if;
 if to_regnamespace('field_sales') is not null then raise exception 'CANDIDATE_ALREADY_INSTALLED'; end if;
 if (select md5(string_agg(version,',' order by version)) from supabase_migrations.schema_migrations)<>'6ace1fe895a4615fa01746eb2632ae65' then raise exception 'MIGRATION_LEDGER_CHANGED_REVIEW_AGAIN'; end if;
end $guard$;
create temporary table field_rehearsal_before on commit drop as select jsonb_build_object('definitions',(select coalesce(jsonb_agg(jsonb_build_object('signature',p.oid::regprocedure::text,'definition',pg_get_functiondef(p.oid),'acl',p.proacl::text) order by p.oid),'[]') from pg_proc p where p.oid=any(array['core.has_permission(uuid,text,uuid,uuid)','core.list_capabilities(uuid)','core.wave2_replay(uuid,text,uuid,text)','core.wave3_replay(uuid,text,uuid,uuid,text)','core.bootstrap_tenant_impl(text,text,text,text,text,text,text,text,uuid)','people.require_access(uuid,uuid,uuid,text)']::regprocedure[])),'permissions',(select md5(coalesce(jsonb_agg(to_jsonb(p) order by p.code)::text,'')) from core.permissions p),'entitlements',(select md5(coalesce(jsonb_agg(to_jsonb(p) order by p.plan_code,p.entitlement_code)::text,'')) from billing.plan_entitlements p),'schema_acls',(select jsonb_agg(jsonb_build_object('schema',nspname,'acl',nspacl::text) order by nspname) from pg_namespace where nspname in('api','core','people','storage')),'policies',(select md5(coalesce(jsonb_agg(to_jsonb(p) order by schemaname,tablename,policyname)::text,'')) from pg_policies p)) value;
alter table field_rehearsal_before enable row level security;
savepoint field_rehearsal_candidate;
-- Source: supabase/candidates/20261031090000_field_sales_governance.sql
-- CANDIDATE ONLY. Apply only inside the rollback harness until a separately
-- approved rollout. No sender, challenge, stock, invoice or payment activation.
create schema field_sales;
revoke all on schema field_sales from public, anon, authenticated, service_role;
alter default privileges in schema field_sales revoke execute on functions from public;

insert into core.permissions(code,module,description,privileged) values
 ('sales.field.customers.view','sales','Read a dated assigned customer portfolio.',false),
 ('sales.field.catalogue.view','sales','Read governed assigned-customer prices.',false),
 ('sales.field.orders.submit','sales','Submit a governed order request.',false),
 ('sales.field.portfolios.manage','sales','Administer restricted field accounts and portfolios.',true),
 ('sales.field.prices.manage','sales','Administer dated field price policies.',true),
 ('sales.field.discounts.decide','sales','Independently decide field order discount requests.',true);
-- No role, membership, entitlement or existing permission grant is added.

-- Enrollment is durable. Expiring/revoking an assignment MUST NOT restore the
-- representative's accidentally inherited broad permissions.
create table field_sales.principals (
 tenant_id uuid not null references core.tenants(id), user_id uuid not null references auth.users(id),
 primary key(tenant_id,user_id)
);
create table field_sales.assignments (
 id uuid primary key default gen_random_uuid(), tenant_id uuid not null,
 legal_entity_id uuid not null, branch_id uuid not null, rep_id uuid not null,
 customer_id uuid not null, valid_from timestamptz not null, valid_until timestamptz not null,
 version bigint not null default 1, ship_to jsonb not null, payment_terms_days integer not null,
 delivery_terms text not null,
 foreign key(tenant_id,rep_id) references field_sales.principals(tenant_id,user_id),
 foreign key(tenant_id,legal_entity_id) references core.legal_entities(tenant_id,id),
 foreign key(tenant_id,branch_id) references core.branches(tenant_id,id),
 foreign key(tenant_id,customer_id) references crm.parties(tenant_id,id),
 check(valid_until>valid_from), check(version>0),
 check(jsonb_typeof(ship_to)='object'), check(payment_terms_days between 0 and 3650),
 check(length(trim(delivery_terms)) between 1 and 1000),
 exclude using gist(tenant_id with =,legal_entity_id with =,branch_id with =,
  rep_id with =,customer_id with =,tstzrange(valid_from,valid_until,'[)') with &&)
);
create index assignments_portfolio on field_sales.assignments(tenant_id,rep_id,legal_entity_id,branch_id,customer_id);
create table field_sales.price_policies (
 id uuid primary key default gen_random_uuid(), tenant_id uuid not null,
 legal_entity_id uuid not null, branch_id uuid not null, customer_id uuid not null,
 product_id uuid not null, unit_id uuid not null, currency_code text not null references core.currencies(code),
 unit_price numeric(20,6) not null check(unit_price>=0),
 max_discount_percent numeric(12,6) not null check(max_discount_percent between 0 and 100),
 tax_definition_id uuid, valid_from date not null, valid_until date not null,
 version bigint not null default 1 check(version>0),
 foreign key(tenant_id,legal_entity_id) references core.legal_entities(tenant_id,id),
 foreign key(tenant_id,branch_id) references core.branches(tenant_id,id),
 foreign key(tenant_id,customer_id) references crm.parties(tenant_id,id),
 foreign key(tenant_id,legal_entity_id,product_id) references inventory.products(tenant_id,legal_entity_id,id),
 foreign key(tenant_id,unit_id) references inventory.units(tenant_id,id),
 foreign key(tenant_id,legal_entity_id,tax_definition_id) references finance.tax_definitions(tenant_id,legal_entity_id,id),
 check(valid_until>=valid_from),
 exclude using gist(tenant_id with =,legal_entity_id with =,branch_id with =,customer_id with =,
  product_id with =,unit_id with =,daterange(valid_from,valid_until,'[]') with &&)
);
create table field_sales.order_requests (
 id uuid primary key, tenant_id uuid not null references core.tenants(id),
 legal_entity_id uuid not null, branch_id uuid not null, customer_id uuid not null,
 rep_id uuid not null references auth.users(id), version bigint not null default 1,
 input jsonb not null, preview jsonb not null, source_digest text not null,
 state text not null default 'submitted' check(state in('submitted','approved','rejected')),
 canonical_order_id uuid references sales.sales_orders(id),
 decision_by uuid references auth.users(id), decision_reason text, decided_at timestamptz,
 created_at timestamptz not null default now(),
 check(decision_by is null or decision_by<>rep_id),
 check((state='submitted')=(decision_by is null)),
 check((state='approved')=(canonical_order_id is not null)),
 foreign key(tenant_id,legal_entity_id) references core.legal_entities(tenant_id,id),
 foreign key(tenant_id,branch_id) references core.branches(tenant_id,id),
 foreign key(tenant_id,customer_id) references crm.parties(tenant_id,id)
);
create index requests_scope on field_sales.order_requests(tenant_id,legal_entity_id,branch_id,customer_id,id);
-- Private tables have no client grants or permissive policies.
alter table field_sales.principals enable row level security;
alter table field_sales.assignments enable row level security;
alter table field_sales.price_policies enable row level security;
alter table field_sales.order_requests enable row level security;

create function field_sales.restricted(t uuid) returns boolean
language sql stable security definer set search_path='' as $$
 select exists(select 1 from field_sales.principals where tenant_id=t and user_id=auth.uid())
$$;
-- Preserve the original permission algorithm and identity. The added predicate
-- closes legacy views, commands, reports, exports and file-authorizing helpers.
create or replace function core.has_permission(p_tenant_id uuid,p_permission_code text,
 p_legal_entity_id uuid default null,p_branch_id uuid default null) returns boolean
language sql stable security definer set search_path='' as $$
 select auth.uid() is not null
 and (not field_sales.restricted(p_tenant_id) or p_permission_code in
  ('sales.field.customers.view','sales.field.catalogue.view','sales.field.orders.submit',
   'people.self.view','people.attendance.self.request','people.leave.self.manage',
   'people.payroll.payslip.self','people.hr.cases.self.manage','people.hr.documents.self.view'))
 and exists(select 1 from core.memberships m
  join core.role_assignments ra on ra.tenant_id=m.tenant_id and ra.membership_id=m.id
  join core.roles r on r.tenant_id=ra.tenant_id and r.id=ra.role_id
  join core.role_permissions rp on rp.tenant_id=r.tenant_id and rp.role_id=r.id
  where m.tenant_id=p_tenant_id and m.user_id=auth.uid() and m.status='active'
   and rp.permission_code=p_permission_code
   and (ra.legal_entity_id is null or ra.legal_entity_id=p_legal_entity_id)
   and (ra.branch_id is null or ra.branch_id=p_branch_id)
   and (not r.requires_mfa or coalesce(auth.jwt()->>'aal','aal1')='aal2'))
$$;
create or replace function core.list_capabilities(p_tenant_id uuid)
returns table(permission_code text) language sql stable security definer set search_path='' as $$
 select distinct rp.permission_code from core.memberships m join core.role_assignments ra
  on ra.tenant_id=m.tenant_id and ra.membership_id=m.id
 join core.role_permissions rp on rp.tenant_id=ra.tenant_id and rp.role_id=ra.role_id
 where m.tenant_id=p_tenant_id and m.user_id=auth.uid() and m.status='active'
  and core.has_permission(p_tenant_id,rp.permission_code,ra.legal_entity_id,ra.branch_id)
$$;
-- Employee self endpoints use a linked-subject guard but the shared People
-- helper also requires broad people.view. Skip only that redundant broad gate
-- for explicit self capabilities, preserving its own grant, scope, subscription
-- and entitlement checks. Never permit broad staff endpoints for a field user.
do $$declare f regprocedure; definition text; marker text; replacement text; begin
 f:=to_regprocedure('people.require_access(uuid,uuid,uuid,text)');
 if f is not null then
  definition:=pg_get_functiondef(f);
  marker:='perform core.wave3_require_scope(p_tenant_id, ''people.view'', p_entity_id, p_branch_id);';
  if length(definition)-length(replace(definition,marker,''))<>length(marker) then
   raise exception 'Unreviewed People access helper'; end if;
  replacement:='if not (field_sales.restricted(p_tenant_id) and p_permission in
   (''people.self.view'',''people.attendance.self.request'',''people.leave.self.manage'',
    ''people.payroll.payslip.self'',''people.hr.cases.self.manage'',''people.hr.documents.self.view'')) then '
   ||marker||' end if;';
  execute replace(definition,marker,replacement);
 end if;
end $$;
-- Blanket restrictive policies also cover older member-only credit/process
-- projections, not just rows whose permissive policy calls has_permission.
do $$declare r record; begin
 for r in select n.nspname,c.relname from pg_class c join pg_namespace n on n.oid=c.relnamespace
  where c.relkind in('r','p') and n.nspname in('crm','sales','finance','inventory','procurement','workflow','audit')
   and exists(select 1 from pg_attribute a where a.attrelid=c.oid and a.attname='tenant_id' and not a.attisdropped)
 loop
  execute format('create policy field_legacy_restricted on %I.%I as restrictive for all to authenticated using(not field_sales.restricted(tenant_id)) with check(not field_sales.restricted(tenant_id))',r.nspname,r.relname);
 end loop;
end $$;
-- Preserve original private helper bodies while preventing member-only legacy
-- commands from replaying an old receipt after portfolio revocation. The exact
-- injection point is checked; unexpected installed bodies abort the candidate.
do $$declare f regprocedure; definition text; marker text; guard text; begin
 foreach f in array array['core.wave2_replay(uuid,text,uuid,text)'::regprocedure,
  'core.wave3_replay(uuid,text,uuid,uuid,text)'::regprocedure,
  'core.bootstrap_tenant_impl(text,text,text,text,text,text,text,text,uuid)'::regprocedure] loop
  definition:=pg_get_functiondef(f);marker:=E'\nbegin\n';
  if strpos(definition,marker)=0 then marker:=E'\r\nbegin\r\n'; end if;
  if strpos(definition,marker)=0 then raise exception 'Unreviewed legacy receipt function body: %',f; end if;
  if f='core.bootstrap_tenant_impl(text,text,text,text,text,text,text,text,uuid)'::regprocedure then
   guard:=E'\n if exists(select 1 from field_sales.principals where user_id=auth.uid()) then\n  raise exception using errcode=''42501'',message=''FIELD_ACCOUNT_BOOTSTRAP_DENIED''; end if;\n';
  else
   guard:=E'\n if field_sales.restricted(p_tenant_id) and p_command_name<>''sales.field.order.submit'' then\n  raise exception using errcode=''42501'',message=''FIELD_LEGACY_COMMAND_DENIED''; end if;\n';
  end if;
  definition:=replace(definition,marker,marker||guard);execute definition;
 end loop;
end $$;
-- Actor-only historic receipts/exports may contain formerly authorized data.
-- Keep legacy recovery closed; the new receipt endpoint rechecks the customer.
create policy field_receipts_restricted on core.command_receipts as restrictive
 for select to authenticated using(not field_sales.restricted(tenant_id));
create policy field_exports_restricted on core.export_jobs as restrictive
 for select to authenticated using(not field_sales.restricted(tenant_id));
create policy field_imports_restricted on core.import_jobs as restrictive
 for select to authenticated using(not field_sales.restricted(tenant_id));
-- RLS expressions require this one safe boolean helper; no data helper is public.
grant usage on schema field_sales to authenticated;
grant execute on function field_sales.restricted(uuid) to authenticated;

create function field_sales.exact(j jsonb) returns jsonb
language plpgsql immutable set search_path='' as $$
declare result jsonb; k text; v jsonb; begin
 if jsonb_typeof(j)='number' then return to_jsonb(j#>>'{}'); end if;
 if jsonb_typeof(j)='array' then
  select coalesce(jsonb_agg(field_sales.exact(value)),'[]') into result from jsonb_array_elements(j); return result;
 elsif jsonb_typeof(j)='object' then
  result:='{}'; for k,v in select * from jsonb_each(j) loop
   result:=result||jsonb_build_object(k,field_sales.exact(v)); end loop; return result;
 end if; return j;
end $$;
create function field_sales.assignment(t uuid,e uuid,b uuid,c uuid,rep uuid)
returns field_sales.assignments language plpgsql security definer set search_path='' as $$
declare a field_sales.assignments; begin
 select x.* into a from field_sales.assignments x join core.memberships m
  on m.tenant_id=x.tenant_id and m.user_id=x.rep_id and m.status='active'
 where x.tenant_id=t and x.legal_entity_id=e and x.branch_id=b and x.customer_id=c
  and x.rep_id=rep and statement_timestamp()>=x.valid_from and statement_timestamp()<x.valid_until
 for share of x,m;
 if a.id is null then raise exception using errcode='42501',message='ASSIGNMENT_CHANGED'; end if;
 return a;
end $$;
-- Match the existing Employee self-service Auth-session boundary. An otherwise
-- unexpired access JWT cannot reopen Sales after its Auth session is removed.
create function field_sales.require_session() returns void
language plpgsql stable security definer set search_path='' as $$
declare session_id uuid; begin
 if auth.uid() is null or coalesce(auth.jwt()->>'session_id','') !~*
  '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' then
  raise exception using errcode='42501',message='FIELD_SESSION_REQUIRED'; end if;
 session_id:=(auth.jwt()->>'session_id')::uuid;
 if not exists(select 1 from auth.sessions s where s.id=session_id and s.user_id=auth.uid()
  and (s.not_after is null or s.not_after>clock_timestamp())) then
  raise exception using errcode='42501',message='FIELD_SESSION_REQUIRED'; end if;
end $$;
create function field_sales.require_rep(t uuid,e uuid,b uuid,permission text) returns void
language plpgsql security definer set search_path='' as $$begin
 perform field_sales.require_session();
 perform core.wave3_require_scope(t,permission,e,b);
 if b is null or not field_sales.restricted(t) then
  raise exception using errcode='42501',message='FIELD_ACCOUNT_REQUIRED'; end if;
end $$;
create function field_sales.require_company(t uuid,e uuid,b uuid,permission text) returns void
language plpgsql security definer set search_path='' as $$begin
 perform field_sales.require_session();
 perform core.wave3_require_scope(t,permission,e,b);
 if b is null or coalesce(auth.jwt()->>'aal','aal1')<>'aal2' or field_sales.restricted(t) then
  raise exception using errcode='42501',message='MFA_REQUIRED'; end if;
end $$;

create function api.field_sales_workspace() returns jsonb
language plpgsql stable security definer set search_path='' as $$begin
 perform field_sales.require_session();
 return (select jsonb_build_object('contract_version','1','scopes',coalesce(jsonb_agg(s.scope),'[]')) from (
 select distinct jsonb_build_object('tenant_id',a.tenant_id,'legal_entity_id',a.legal_entity_id,
  'branch_id',a.branch_id,'company_name',le.name,'branch_name',b.name,'warehouses',
  (select coalesce(jsonb_agg(jsonb_build_object('id',w.id,'name',w.name) order by w.id),'[]')
   from core.warehouses w where w.tenant_id=a.tenant_id and w.legal_entity_id=le.id and w.branch_id=b.id and w.status='active')) scope
 from field_sales.assignments a join core.legal_entities le on le.tenant_id=a.tenant_id and le.id=a.legal_entity_id
 join core.branches b on b.tenant_id=a.tenant_id and b.legal_entity_id=le.id and b.id=a.branch_id
 join core.tenants t on t.id=a.tenant_id
 where a.rep_id=auth.uid() and field_sales.restricted(a.tenant_id)
  and statement_timestamp()>=a.valid_from and statement_timestamp()<a.valid_until
  and t.status in('active','trial') and le.status='active' and b.status='active'
  and core.has_permission(a.tenant_id,'sales.field.customers.view',le.id,b.id)) s);
end $$;
create function api.field_sales_customers(p_tenant_id uuid,p_legal_entity_id uuid,p_branch_id uuid,
 p_query text default '',p_after uuid default null,p_limit integer default 50) returns jsonb
language plpgsql security definer set search_path='' as $$declare items jsonb; begin
 perform field_sales.require_rep(p_tenant_id,p_legal_entity_id,p_branch_id,'sales.field.customers.view');
 if p_limit is null or p_limit not between 1 and 200 or length(p_query)>120 then
  raise exception using errcode='22023',message='PAGE_INVALID'; end if;
 select coalesce(jsonb_agg(x.item order by x.id),'[]') into items from (
  select p.id,jsonb_build_object('id',p.id,'name',coalesce(p.display_name,p.legal_name),
   'assignment_version',a.version::text,'ship_to',a.ship_to,'payment_terms_days',a.payment_terms_days::text,
   'delivery_terms',a.delivery_terms) item from field_sales.assignments a join crm.parties p
   on p.tenant_id=a.tenant_id and p.id=a.customer_id
  where a.tenant_id=p_tenant_id and a.legal_entity_id=p_legal_entity_id and a.branch_id=p_branch_id
   and a.rep_id=auth.uid() and statement_timestamp()>=a.valid_from and statement_timestamp()<a.valid_until
   and p.status='active' and p.kind in('customer','both') and (p_after is null or p.id>p_after)
   and coalesce(p.display_name,p.legal_name) ilike '%'||coalesce(p_query,'')||'%'
  order by p.id limit p_limit+1) x;
 return jsonb_build_object('has_more',jsonb_array_length(items)>p_limit,
  'next_cursor',case when jsonb_array_length(items)>p_limit then items->(p_limit-1)->>'id' end,
  'as_of',statement_timestamp()) || jsonb_build_object('items',
   (select coalesce(jsonb_agg(value order by ordinality),'[]') from jsonb_array_elements(items) with ordinality where ordinality<=p_limit));
end $$;

-- One commercial calculator for online review, submission and company review.
-- Only base units and company base currency are in this first slice. Tax and
-- rounding reuse the canonical calculator; stock is explicitly unavailable.
create function field_sales.prepare(t uuid,e uuid,b uuid,rep uuid,input jsonb) returns jsonb
language plpgsql security definer set search_path='' as $$
declare a field_sales.assignments; pp field_sales.price_policies; p inventory.products;
 c crm.parties; wh core.warehouses; le core.legal_entities; ln jsonb; q numeric;
 d date; discount numeric; lines jsonb:='[]'; sources jsonb:='[]'; pricing jsonb; canonical jsonb; snapshot jsonb;
begin
 if jsonb_typeof(input) is distinct from 'object' or exists(select 1 from jsonb_object_keys(input) k
  where k not in('customer_id','warehouse_id','requested_date','reference','notes','discount_percent','discount_reason','lines'))
  or jsonb_typeof(input->'lines') is distinct from 'array' then
  raise exception using errcode='22023',message='ORDER_INPUT_INVALID'; end if;
 if jsonb_array_length(input->'lines') not between 1 and 100
  or length(coalesce(input->>'reference',''))>120 or length(coalesce(input->>'notes',''))>2000
  or length(coalesce(input->>'discount_reason',''))>500 then
  raise exception using errcode='22023',message='ORDER_INPUT_INVALID'; end if;
 a:=field_sales.assignment(t,e,b,(input->>'customer_id')::uuid,rep);
 if not exists(select 1 from core.memberships m join core.role_assignments ra on ra.membership_id=m.id and ra.tenant_id=m.tenant_id
  join core.role_permissions rp on rp.tenant_id=ra.tenant_id and rp.role_id=ra.role_id
  where m.tenant_id=t and m.user_id=rep and m.status='active' and rp.permission_code='sales.field.orders.submit'
   and (ra.legal_entity_id is null or ra.legal_entity_id=e) and (ra.branch_id is null or ra.branch_id=b)) then
  raise exception using errcode='42501',message='ACCESS_REVOKED'; end if;
 select * into c from crm.parties where tenant_id=t and id=a.customer_id for share;
 if c.id is null or c.status<>'active' or c.kind not in('customer','both') then
  raise exception using errcode='55000',message='CUSTOMER_INACTIVE'; end if;
 select * into le from core.legal_entities where tenant_id=t and id=e and status='active' for share;
 d:=(statement_timestamp() at time zone le.timezone)::date;
 select * into wh from core.warehouses where tenant_id=t and legal_entity_id=e and branch_id=b
  and id=(input->>'warehouse_id')::uuid and status='active' for share;
 if wh.id is null or (input->>'requested_date')::date is null or (input->>'requested_date')::date<d then
  raise exception using errcode='22023',message='FULFILLMENT_INVALID'; end if;
 discount:=sales.wave3_decimal_string(input->'discount_percent','Requested discount',2,true,0,100);
 if discount>0 and length(trim(coalesce(input->>'discount_reason','')))=0 then
  raise exception using errcode='22023',message='REASON_REQUIRED'; end if;
 for ln in select value from jsonb_array_elements(input->'lines') loop
  if jsonb_typeof(ln) is distinct from 'object' or exists(select 1 from jsonb_object_keys(ln) k
   where k not in('policy_id','policy_version','quantity')) then
   raise exception using errcode='22023',message='LINE_INPUT_INVALID'; end if;
  select * into pp from field_sales.price_policies where tenant_id=t and legal_entity_id=e and branch_id=b
   and customer_id=c.id and id=(ln->>'policy_id')::uuid and d between valid_from and valid_until for share;
  if pp.id is null or pp.version::text is distinct from ln->>'policy_version' then
   raise exception using errcode='40001',message='PRICE_CHANGED'; end if;
  if pp.currency_code<>le.currency_code then raise exception using errcode='55000',message='CURRENCY_UNAVAILABLE'; end if;
  if discount>pp.max_discount_percent then raise exception using errcode='22023',message='DISCOUNT_LIMIT_EXCEEDED'; end if;
  select * into p from inventory.products where tenant_id=t and legal_entity_id=e and id=pp.product_id for share;
  if p.status<>'active' or not p.can_sell or p.base_unit_id<>pp.unit_id then
   raise exception using errcode='55000',message='PRODUCT_SOURCE_CHANGED'; end if;
  q:=sales.wave3_decimal_string(ln->'quantity','Quantity',3,true,0.001,9999999.999);
  lines:=lines||jsonb_build_array(jsonb_build_object('product_id',p.id,'description',p.name,'unit_id',pp.unit_id,
   'quantity',q::text,'base_quantity',q::text,'conversion_numerator','1','conversion_denominator','1',
   'unit_price',pp.unit_price::text,'tax_definition_id',pp.tax_definition_id));
  sources:=sources||jsonb_build_array(jsonb_build_object('policy',to_jsonb(pp),'product',to_jsonb(p)));
 end loop;
 pricing:=sales.wave3_price_lines(t,e,d,le.currency_code,lines,null,to_jsonb(discount::text));
 canonical:=jsonb_build_object('customer_id',c.id,'warehouse_id',wh.id,'order_date',d,'promised_date',input->>'requested_date',
  'ship_to',a.ship_to,'payment_terms_days',a.payment_terms_days,'delivery_terms',a.delivery_terms,
  'currency_code',le.currency_code,'exchange_rate','1','rate_date',d,
  'header_discount_percent',discount::text,'lines',lines,'notes',nullif(input->>'notes',''));
 snapshot:=jsonb_build_object('input',input,'assignment',to_jsonb(a),'customer_version',c.version::text,
  'customer_credit_currency',c.credit_currency_code,'customer_credit_limit',c.credit_limit::text,
  'warehouse',to_jsonb(wh),'sources',sources,'canonical',canonical,'pricing',pricing);
 return jsonb_build_object('source_digest',encode(extensions.digest(snapshot::text,'sha256'),'hex'),
  'canonical',canonical,'pricing',field_sales.exact(pricing),'currency_code',le.currency_code,
  'terms',jsonb_build_object('ship_to',a.ship_to,'payment_terms_days',a.payment_terms_days::text,
   'delivery_terms',a.delivery_terms,'warehouse_id',wh.id,'requested_date',input->>'requested_date'),
  'discount_percent',discount::text,'discount_state',case when discount>0 then 'requested' else 'none' end,
  'credit_state','company_review_required','stock_state','unavailable');
end $$;
create function api.field_sales_preview(p_tenant_id uuid,p_legal_entity_id uuid,p_branch_id uuid,p_input jsonb) returns jsonb
language plpgsql security definer set search_path='' as $$begin
 perform field_sales.require_rep(p_tenant_id,p_legal_entity_id,p_branch_id,'sales.field.orders.submit');
 return field_sales.prepare(p_tenant_id,p_legal_entity_id,p_branch_id,auth.uid(),p_input)-'canonical';
end $$;

create function field_sales.entity(r field_sales.order_requests) returns jsonb
language sql stable set search_path='' as $$
 select jsonb_build_object('id',r.id,'version',r.version::text,'tenant_id',r.tenant_id,
  'legal_entity_id',r.legal_entity_id,'branch_id',r.branch_id,'customer_id',r.customer_id,'rep_id',r.rep_id,
  'input',r.input,'source_digest',r.source_digest,'preview',r.preview-'canonical','company_state',r.state,
  'canonical_order_id',r.canonical_order_id,'canonical_state',case when r.canonical_order_id is not null then 'draft' end,
  'customer_state','email_link_pending','delivery_state','not_requested','decision_by',r.decision_by,
  'decision_reason',r.decision_reason,'decided_at',r.decided_at,'created_at',r.created_at)
$$;
create function api.field_sales_command(p_tenant_id uuid,p_legal_entity_id uuid,p_branch_id uuid,
 p_command_id uuid,p_idempotency_key uuid,p_client_timestamp timestamptz,p_payload jsonb,
 p_expected_entity_version bigint default null) returns jsonb
language plpgsql security definer set search_path='' as $$
declare reviewed jsonb; replay jsonb; hash text; r field_sales.order_requests; begin
 perform field_sales.require_rep(p_tenant_id,p_legal_entity_id,p_branch_id,'sales.field.orders.submit');
 if p_client_timestamp is null or p_expected_entity_version is not null or jsonb_typeof(p_payload) is distinct from 'object'
  or exists(select 1 from jsonb_object_keys(p_payload) k where k not in('id','input','source_digest')) then
  raise exception using errcode='22023',message='COMMAND_INVALID'; end if;
 perform field_sales.assignment(p_tenant_id,p_legal_entity_id,p_branch_id,(p_payload->'input'->>'customer_id')::uuid,auth.uid());
 hash:=core.wave3_request_hash('sales.field.order.submit',p_command_id,p_tenant_id,p_legal_entity_id,p_branch_id,p_payload,null);
 replay:=core.wave3_replay(p_tenant_id,'sales.field.order.submit',p_command_id,p_idempotency_key,hash);
 if replay is not null then return replay; end if;
 reviewed:=field_sales.prepare(p_tenant_id,p_legal_entity_id,p_branch_id,auth.uid(),p_payload->'input');
 if reviewed->>'source_digest' is distinct from p_payload->>'source_digest' then
  raise exception using errcode='40001',message='SOURCE_CHANGED'; end if;
 insert into field_sales.order_requests(id,tenant_id,legal_entity_id,branch_id,customer_id,rep_id,input,preview,source_digest)
 values((p_payload->>'id')::uuid,p_tenant_id,p_legal_entity_id,p_branch_id,(p_payload->'input'->>'customer_id')::uuid,
  auth.uid(),p_payload->'input',reviewed,reviewed->>'source_digest') returning * into r;
 return core.wave3_finish_command(p_tenant_id,'sales.field.order.submit',p_command_id,'field_order_request',r.id,
  p_idempotency_key,hash,null,field_sales.entity(r),p_legal_entity_id,p_branch_id);
end $$;

create function api.field_sales_subject_page(p_tenant_id uuid,p_legal_entity_id uuid,p_branch_id uuid,
 p_after uuid default null,p_limit integer default 50) returns jsonb
language plpgsql security definer set search_path='' as $$declare items jsonb; company boolean; begin
 company:=core.has_permission(p_tenant_id,'sales.field.discounts.decide',p_legal_entity_id,p_branch_id);
 if company then perform field_sales.require_company(p_tenant_id,p_legal_entity_id,p_branch_id,'sales.field.discounts.decide');
 else perform field_sales.require_rep(p_tenant_id,p_legal_entity_id,p_branch_id,'sales.field.customers.view'); end if;
 if p_limit is null or p_limit not between 1 and 200 then raise exception using errcode='22023',message='PAGE_INVALID'; end if;
 select coalesce(jsonb_agg(x.item order by x.id),'[]') into items from (
 select r.id,field_sales.entity(r) item from field_sales.order_requests r
 where r.tenant_id=p_tenant_id and r.legal_entity_id=p_legal_entity_id and r.branch_id=p_branch_id
  and (p_after is null or r.id>p_after) and (company or exists(select 1 from field_sales.assignments a
   where a.tenant_id=r.tenant_id and a.legal_entity_id=r.legal_entity_id and a.branch_id=r.branch_id
    and a.customer_id=r.customer_id and a.rep_id=auth.uid()
    and statement_timestamp()>=a.valid_from and statement_timestamp()<a.valid_until))
 order by r.id limit p_limit+1) x;
 return jsonb_build_object('items',(select coalesce(jsonb_agg(value order by ordinality),'[]')
  from jsonb_array_elements(items) with ordinality where ordinality<=p_limit),
  'next_cursor',case when jsonb_array_length(items)>p_limit then items->(p_limit-1)->>'id' end,'as_of',statement_timestamp());
end $$;
create function api.field_sales_command_receipt(p_tenant_id uuid,p_legal_entity_id uuid,p_branch_id uuid,p_idempotency_key uuid)
returns jsonb language plpgsql security definer set search_path='' as $$declare receipt core.command_receipts; r field_sales.order_requests; company boolean; begin
 company:=core.has_permission(p_tenant_id,'sales.field.discounts.decide',p_legal_entity_id,p_branch_id);
 if company then
  perform field_sales.require_company(p_tenant_id,p_legal_entity_id,p_branch_id,'sales.field.discounts.decide');
  perform core.wave3_require_scope(p_tenant_id,'sales.orders.manage',p_legal_entity_id,p_branch_id);
 else perform field_sales.require_rep(p_tenant_id,p_legal_entity_id,p_branch_id,'sales.field.orders.submit'); end if;
 select * into receipt from core.command_receipts where tenant_id=p_tenant_id and actor_id=auth.uid()
  and idempotency_key=p_idempotency_key and command_name=case when company then 'sales.field.company.decide' else 'sales.field.order.submit' end;
 if receipt.id is null then return jsonb_build_object('state','not_found'); end if;
 select * into r from field_sales.order_requests where id=(receipt.response->'entity'->>'id')::uuid
  and tenant_id=p_tenant_id and legal_entity_id=p_legal_entity_id and branch_id=p_branch_id;
 if r.id is null then raise exception using errcode='42501',message='RECEIPT_SCOPE_INVALID'; end if;
 if not company then perform field_sales.assignment(p_tenant_id,p_legal_entity_id,p_branch_id,r.customer_id,auth.uid()); end if;
 return jsonb_build_object('state','committed','receipt',receipt.response);
end $$;

create function api.field_sales_company_decide(p_tenant_id uuid,p_legal_entity_id uuid,p_branch_id uuid,
 p_command_id uuid,p_idempotency_key uuid,p_client_timestamp timestamptz,p_payload jsonb,p_expected_entity_version bigint)
returns jsonb language plpgsql security definer set search_path='' as $$
declare r field_sales.order_requests; reviewed jsonb; canonical jsonb; credit jsonb; hash text; replay jsonb; before jsonb; begin
 perform field_sales.require_company(p_tenant_id,p_legal_entity_id,p_branch_id,'sales.field.discounts.decide');
 perform core.wave3_require_scope(p_tenant_id,'sales.orders.manage',p_legal_entity_id,p_branch_id);
 if p_client_timestamp is null or jsonb_typeof(p_payload) is distinct from 'object'
  or exists(select 1 from jsonb_object_keys(p_payload) k where k not in('id','decision','reason','source_digest'))
  or coalesce(p_payload->>'decision','') not in('approve','reject')
  or length(trim(coalesce(p_payload->>'reason',''))) not between 1 and 500 then
  raise exception using errcode='22023',message='DECISION_INVALID'; end if;
 hash:=core.wave3_request_hash('sales.field.company.decide',p_command_id,p_tenant_id,p_legal_entity_id,p_branch_id,p_payload,p_expected_entity_version);
 replay:=core.wave3_replay(p_tenant_id,'sales.field.company.decide',p_command_id,p_idempotency_key,hash);
 select * into r from field_sales.order_requests where tenant_id=p_tenant_id and legal_entity_id=p_legal_entity_id
  and branch_id=p_branch_id and id=(p_payload->>'id')::uuid for update;
 if r.id is null or r.rep_id=auth.uid() then raise exception using errcode='42501',message='INDEPENDENT_APPROVER_REQUIRED'; end if;
 if replay is not null then return replay; end if;
 before:=field_sales.entity(r);
 perform core.wave3_assert_expected_version(r.version,p_expected_entity_version,before);
 if r.state<>'submitted' then raise exception using errcode='55000',message='REQUEST_ALREADY_DECIDED'; end if;
 if r.source_digest is distinct from p_payload->>'source_digest' then raise exception using errcode='40001',message='SOURCE_CHANGED'; end if;
 if p_payload->>'decision'='approve' then
  -- Current rep capability, membership, portfolio and all commercial sources are
  -- checked again under the company's own JWT. No impersonation or role grant.
  if not exists(select 1 from core.memberships where tenant_id=p_tenant_id and user_id=r.rep_id and status='active') then
   raise exception using errcode='42501',message='ASSIGNMENT_CHANGED'; end if;
  reviewed:=field_sales.prepare(p_tenant_id,p_legal_entity_id,p_branch_id,r.rep_id,r.input);
  if reviewed->>'source_digest'<>r.source_digest then raise exception using errcode='40001',message='SOURCE_CHANGED'; end if;
  canonical:=api.upsert_sales_order(p_tenant_id,p_legal_entity_id,p_branch_id,
   core.wave2_derived_uuid(p_command_id,1),core.wave2_derived_uuid(p_idempotency_key,1),p_client_timestamp,
   reviewed->'canonical'||jsonb_build_object('source_context',jsonb_build_object('field_request_id',r.id,'source_digest',r.source_digest,
    'representative_id',r.rep_id,'customer_reference',r.input->>'reference')),null);
  r.canonical_order_id:=(canonical->'entity'->>'id')::uuid;
  credit:=api.get_sales_order_credit_preview(p_tenant_id,p_legal_entity_id,p_branch_id,r.canonical_order_id);
  if not coalesce((credit->>'projection_available')::boolean,false) then
   raise exception using errcode='55000',message='CREDIT_PROVIDER_UNAVAILABLE'; end if;
  if credit->>'reason' is not null or (credit->>'overdue_exposure')::numeric>0 then
   raise exception using errcode='55000',message='CREDIT_HOLD'; end if;
  update sales.sales_orders set salesperson_id=r.rep_id where id=r.canonical_order_id;
 end if;
 update field_sales.order_requests set state=case when p_payload->>'decision'='approve' then 'approved' else 'rejected' end,
  canonical_order_id=r.canonical_order_id,version=version+1,decision_by=auth.uid(),decision_reason=trim(p_payload->>'reason'),
  decided_at=statement_timestamp() where id=r.id returning * into r;
 return core.wave3_finish_command(p_tenant_id,'sales.field.company.decide',p_command_id,'field_order_request',r.id,
  p_idempotency_key,hash,before,field_sales.entity(r),p_legal_entity_id,p_branch_id);
end $$;

-- Until the separately reviewed verified-email slice exists, governed canonical
-- drafts cannot be edited/confirmed through any older command or direct write.
create function field_sales.guard_order() returns trigger
language plpgsql security definer set search_path='' as $$declare order_id uuid; begin
 if tg_table_name='sales_orders' then order_id:=old.id;
 else order_id:=case when tg_op='INSERT' then new.sales_order_id else old.sales_order_id end; end if;
 if exists(select 1 from field_sales.order_requests where canonical_order_id=order_id) then
  raise exception using errcode='55000',message='CUSTOMER_ACCEPTANCE_REQUIRED'; end if;
 if tg_op='DELETE' then return old; end if; return new;
end $$;
create trigger field_governed_order before update or delete on sales.sales_orders
 for each row execute function field_sales.guard_order();
create trigger field_governed_order_line before insert or update or delete on sales.sales_order_lines
 for each row execute function field_sales.guard_order();

-- Configuration is also a named company command, with versions, MFA, audit and
-- immutable receipts. Removal of enrollment is deliberately unavailable.
create function api.field_sales_admin_command(p_tenant_id uuid,p_legal_entity_id uuid,p_branch_id uuid,
 p_command_id uuid,p_idempotency_key uuid,p_client_timestamp timestamptz,p_action text,p_payload jsonb,
 p_expected_entity_version bigint default null) returns jsonb
language plpgsql security definer set search_path='' as $$
declare permission text; name text; hash text; replay jsonb; v_id uuid; before jsonb; entity jsonb;
 a field_sales.assignments; pp field_sales.price_policies; begin
 permission:=case when p_action in('assign_customer','revoke_assignment') then 'sales.field.portfolios.manage'
  when p_action='set_price_policy' then 'sales.field.prices.manage' else null end;
 if permission is null or p_client_timestamp is null or jsonb_typeof(p_payload) is distinct from 'object' then
  raise exception using errcode='22023',message='ADMIN_COMMAND_INVALID'; end if;
 perform field_sales.require_company(p_tenant_id,p_legal_entity_id,p_branch_id,permission);
 name:='sales.field.'||p_action;
 hash:=core.wave3_request_hash(name,p_command_id,p_tenant_id,p_legal_entity_id,p_branch_id,p_payload,p_expected_entity_version);
 replay:=core.wave3_replay(p_tenant_id,name,p_command_id,p_idempotency_key,hash);
 if replay is not null then return replay; end if;
 v_id:=(p_payload->>'id')::uuid;
 if p_action in('assign_customer','revoke_assignment') then
  if exists(select 1 from jsonb_object_keys(p_payload) k where k not in
   ('id','rep_id','customer_id','valid_from','valid_until','ship_to','payment_terms_days','delivery_terms')) then
   raise exception using errcode='22023',message='ASSIGNMENT_FIELDS_INVALID'; end if;
  select * into a from field_sales.assignments where field_sales.assignments.id=v_id for update;
  if a.id is not null and (a.tenant_id<>p_tenant_id or a.legal_entity_id<>p_legal_entity_id or a.branch_id<>p_branch_id) then
   raise exception using errcode='42501',message='CONFIGURATION_SCOPE_INVALID'; end if;
  if a.id is not null then
   before:=field_sales.exact(to_jsonb(a));perform core.wave3_assert_expected_version(a.version,p_expected_entity_version,before);
  elsif p_expected_entity_version is not null or p_action='revoke_assignment' then
   raise exception using errcode='40001',message='VERSION_CONFLICT'; end if;
  if p_action='revoke_assignment' then
   update field_sales.assignments set valid_until=greatest(valid_from+interval '1 microsecond',least(valid_until,statement_timestamp())),
    version=version+1 where field_sales.assignments.id=v_id returning field_sales.exact(to_jsonb(field_sales.assignments.*)) into entity;
  else
   if (p_payload->>'rep_id')::uuid=auth.uid() or exists(select 1 from core.memberships m
    join core.role_assignments ra on ra.tenant_id=m.tenant_id and ra.membership_id=m.id
    join core.roles r on r.tenant_id=ra.tenant_id and r.id=ra.role_id
    where m.tenant_id=p_tenant_id and m.user_id=(p_payload->>'rep_id')::uuid and r.code='tenant_owner') then
    raise exception using errcode='42501',message='FIELD_ENROLLMENT_OWNER_SELF_PROTECTED'; end if;
   if not exists(select 1 from core.memberships where tenant_id=p_tenant_id and user_id=(p_payload->>'rep_id')::uuid and status='active')
    or not exists(select 1 from crm.parties where tenant_id=p_tenant_id and crm.parties.id=(p_payload->>'customer_id')::uuid
     and status='active' and kind in('customer','both')) then
    raise exception using errcode='42501',message='ASSIGNMENT_SUBJECT_INVALID'; end if;
   insert into field_sales.principals values(p_tenant_id,(p_payload->>'rep_id')::uuid) on conflict do nothing;
   insert into field_sales.assignments(id,tenant_id,legal_entity_id,branch_id,rep_id,customer_id,valid_from,valid_until,ship_to,payment_terms_days,delivery_terms)
   values(v_id,p_tenant_id,p_legal_entity_id,p_branch_id,(p_payload->>'rep_id')::uuid,(p_payload->>'customer_id')::uuid,
    (p_payload->>'valid_from')::timestamptz,(p_payload->>'valid_until')::timestamptz,p_payload->'ship_to',
    (p_payload->>'payment_terms_days')::integer,p_payload->>'delivery_terms')
   on conflict on constraint assignments_pkey do update set rep_id=excluded.rep_id,customer_id=excluded.customer_id,
    valid_from=excluded.valid_from,valid_until=excluded.valid_until,ship_to=excluded.ship_to,
    payment_terms_days=excluded.payment_terms_days,delivery_terms=excluded.delivery_terms,version=field_sales.assignments.version+1
   where field_sales.assignments.tenant_id=p_tenant_id and field_sales.assignments.legal_entity_id=p_legal_entity_id
    and field_sales.assignments.branch_id=p_branch_id and field_sales.assignments.version=p_expected_entity_version
   returning field_sales.exact(to_jsonb(field_sales.assignments.*)) into entity;
  end if;
 else
  if exists(select 1 from jsonb_object_keys(p_payload) k where k not in
   ('id','customer_id','product_id','unit_id','currency_code','unit_price','max_discount_percent','tax_definition_id','valid_from','valid_until')) then
   raise exception using errcode='22023',message='PRICE_FIELDS_INVALID'; end if;
  select * into pp from field_sales.price_policies where field_sales.price_policies.id=v_id for update;
  if pp.id is not null and (pp.tenant_id<>p_tenant_id or pp.legal_entity_id<>p_legal_entity_id or pp.branch_id<>p_branch_id) then
   raise exception using errcode='42501',message='CONFIGURATION_SCOPE_INVALID'; end if;
  if pp.id is not null then
   before:=field_sales.exact(to_jsonb(pp));perform core.wave3_assert_expected_version(pp.version,p_expected_entity_version,before);
  elsif p_expected_entity_version is not null then raise exception using errcode='40001',message='VERSION_CONFLICT'; end if;
  if not exists(select 1 from inventory.products where tenant_id=p_tenant_id and legal_entity_id=p_legal_entity_id
   and inventory.products.id=(p_payload->>'product_id')::uuid and base_unit_id=(p_payload->>'unit_id')::uuid and status='active' and can_sell)
   or not exists(select 1 from core.legal_entities where tenant_id=p_tenant_id and core.legal_entities.id=p_legal_entity_id
    and currency_code=p_payload->>'currency_code') then raise exception using errcode='22023',message='PRICE_SOURCE_INVALID'; end if;
  insert into field_sales.price_policies(id,tenant_id,legal_entity_id,branch_id,customer_id,product_id,unit_id,currency_code,
   unit_price,max_discount_percent,tax_definition_id,valid_from,valid_until)
  values(v_id,p_tenant_id,p_legal_entity_id,p_branch_id,(p_payload->>'customer_id')::uuid,(p_payload->>'product_id')::uuid,
   (p_payload->>'unit_id')::uuid,p_payload->>'currency_code',sales.wave3_decimal_string(p_payload->'unit_price','Price',6,true,0,null),
   sales.wave3_decimal_string(p_payload->'max_discount_percent','Discount limit',2,true,0,100),
   (p_payload->>'tax_definition_id')::uuid,(p_payload->>'valid_from')::date,(p_payload->>'valid_until')::date)
  on conflict on constraint price_policies_pkey do update set customer_id=excluded.customer_id,product_id=excluded.product_id,
   unit_id=excluded.unit_id,currency_code=excluded.currency_code,unit_price=excluded.unit_price,max_discount_percent=excluded.max_discount_percent,
   tax_definition_id=excluded.tax_definition_id,valid_from=excluded.valid_from,valid_until=excluded.valid_until,version=field_sales.price_policies.version+1
  where field_sales.price_policies.tenant_id=p_tenant_id and field_sales.price_policies.legal_entity_id=p_legal_entity_id
   and field_sales.price_policies.branch_id=p_branch_id and field_sales.price_policies.version=p_expected_entity_version
  returning field_sales.exact(to_jsonb(field_sales.price_policies.*)) into entity;
 end if;
 if entity is null then raise exception using errcode='40001',message='VERSION_CONFLICT'; end if;
 return core.wave3_finish_command(p_tenant_id,name,p_command_id,'field_sales_configuration',v_id,p_idempotency_key,hash,
  before,entity,p_legal_entity_id,p_branch_id);
end $$;

create function api.field_sales_catalogue(p_tenant_id uuid,p_legal_entity_id uuid,p_branch_id uuid,
 p_customer_id uuid,p_after uuid default null,p_limit integer default 50) returns jsonb
language plpgsql security definer set search_path='' as $$declare d date; items jsonb; begin
 perform field_sales.require_rep(p_tenant_id,p_legal_entity_id,p_branch_id,'sales.field.catalogue.view');
 perform field_sales.assignment(p_tenant_id,p_legal_entity_id,p_branch_id,p_customer_id,auth.uid());
 if p_limit is null or p_limit not between 1 and 200 then raise exception using errcode='22023',message='PAGE_INVALID'; end if;
 select (statement_timestamp() at time zone timezone)::date into d from core.legal_entities where id=p_legal_entity_id;
 select coalesce(jsonb_agg(x.item order by x.id),'[]') into items from (
 select pp.id,jsonb_build_object('id',pp.product_id,'policy_id',pp.id,'policy_version',pp.version::text,
  'name',p.name,'code',p.sku,'unit_id',pp.unit_id,'unit',u.name,'unit_price',pp.unit_price::text,
  'max_discount_percent',pp.max_discount_percent::text,'currency_code',pp.currency_code,
  'stock_state','unavailable') item from field_sales.price_policies pp
 join inventory.products p on p.tenant_id=pp.tenant_id and p.id=pp.product_id
 join inventory.units u on u.tenant_id=pp.tenant_id and u.id=pp.unit_id
 where pp.tenant_id=p_tenant_id and pp.legal_entity_id=p_legal_entity_id and pp.branch_id=p_branch_id
  and pp.customer_id=p_customer_id and d between pp.valid_from and pp.valid_until
  and p.status='active' and p.can_sell and u.status='active' and (p_after is null or pp.id>p_after)
 order by pp.id limit p_limit+1) x;
 return jsonb_build_object('items',(select coalesce(jsonb_agg(value order by ordinality),'[]')
  from jsonb_array_elements(items) with ordinality where ordinality<=p_limit),
  'next_cursor',case when jsonb_array_length(items)>p_limit then items->(p_limit-1)->>'policy_id' end,
  'as_of',statement_timestamp());
end $$;

revoke all on all tables in schema field_sales from public,anon,authenticated,service_role;
revoke execute on all functions in schema field_sales from public,anon,authenticated,service_role;
grant execute on function field_sales.restricted(uuid) to authenticated;
revoke all on function api.field_sales_admin_command(uuid,uuid,uuid,uuid,uuid,timestamptz,text,jsonb,bigint) from public,anon,authenticated,service_role;
grant execute on function api.field_sales_admin_command(uuid,uuid,uuid,uuid,uuid,timestamptz,text,jsonb,bigint) to authenticated;
revoke all on function api.field_sales_workspace(),
 api.field_sales_customers(uuid,uuid,uuid,text,uuid,integer),
 api.field_sales_catalogue(uuid,uuid,uuid,uuid,uuid,integer),
 api.field_sales_preview(uuid,uuid,uuid,jsonb),
 api.field_sales_command(uuid,uuid,uuid,uuid,uuid,timestamptz,jsonb,bigint),
 api.field_sales_subject_page(uuid,uuid,uuid,uuid,integer),
 api.field_sales_command_receipt(uuid,uuid,uuid,uuid),
 api.field_sales_company_decide(uuid,uuid,uuid,uuid,uuid,timestamptz,jsonb,bigint)
 from public,anon,authenticated,service_role;
grant execute on function api.field_sales_workspace(),
 api.field_sales_customers(uuid,uuid,uuid,text,uuid,integer),
 api.field_sales_catalogue(uuid,uuid,uuid,uuid,uuid,integer),
 api.field_sales_preview(uuid,uuid,uuid,jsonb),
 api.field_sales_command(uuid,uuid,uuid,uuid,uuid,timestamptz,jsonb,bigint),
 api.field_sales_subject_page(uuid,uuid,uuid,uuid,integer),
 api.field_sales_command_receipt(uuid,uuid,uuid,uuid),
 api.field_sales_company_decide(uuid,uuid,uuid,uuid,uuid,timestamptz,jsonb,bigint) to authenticated;



-- Source: supabase/candidates/20261102090000_field_order_email_confirmation.sql
-- CANDIDATE ONLY. No migration installation, sender activation or deployment.
-- Requires 20261031090000_field_sales_governance.sql inside the rollback harness.
insert into core.permissions(code,module,description,privileged) values
 ('sales.field.confirmations.manage','sales','Authorize contacts and request scoped verified order responses.',true);
-- Existing role/membership grants are unchanged. Restricted reps cannot inherit this capability.
create table field_sales.confirmation_contacts (
 id uuid primary key, tenant_id uuid not null, legal_entity_id uuid not null,
 branch_id uuid not null, customer_id uuid not null, version bigint not null default 1,
 name text not null, email text not null, authority_note text not null,
 active boolean not null default true, valid_until timestamptz not null,
 authorized_by uuid not null references auth.users(id), authorized_at timestamptz not null default now(),
 foreign key(tenant_id,legal_entity_id) references core.legal_entities(tenant_id,id),
 foreign key(tenant_id,branch_id) references core.branches(tenant_id,id),
 foreign key(tenant_id,customer_id) references crm.parties(tenant_id,id),
 check(version>0),check(length(name) between 1 and 200),
 check(length(email)<=254 and email=lower(trim(email)) and email ~ '^[^[:space:]@]+@[^[:space:]@]+\.[^[:space:]@]+$'),
 check(length(authority_note) between 1 and 1000)
);
alter table field_sales.confirmation_contacts enable row level security;
create index confirmation_contacts_scope on field_sales.confirmation_contacts(tenant_id,legal_entity_id,branch_id,customer_id);

-- No public API enables transport. A separately reviewed worker/provider rollout
-- must configure this private policy. Missing policy means unavailable.
create table field_sales.confirmation_transport (
 tenant_id uuid primary key references core.tenants(id), enabled boolean not null default false,
 version bigint not null default 1 check(version>0),
 acceptance_minutes integer not null default 1440 check(acceptance_minutes between 15 and 10080),
 verification_secret bytea not null default extensions.gen_random_bytes(32)
);
alter table field_sales.confirmation_transport enable row level security;
create function field_sales.confirmation_ready(t uuid) returns boolean
language sql stable security definer set search_path='' as $$
 select coalesce((select enabled from field_sales.confirmation_transport where tenant_id=t),false)
$$;
create function field_sales.confirmation_contact_entity(c field_sales.confirmation_contacts) returns jsonb
language sql stable set search_path='' as $$
 select field_sales.exact(to_jsonb(c))||jsonb_build_object('channel_state','unverified')
$$;
create table field_sales.confirmation_challenges (
 id uuid primary key, tenant_id uuid not null references core.tenants(id), legal_entity_id uuid not null, branch_id uuid not null,
 request_id uuid not null references field_sales.order_requests(id), request_version bigint not null, source_digest text not null,
 contact_id uuid not null references field_sales.confirmation_contacts(id), contact_version bigint not null,
 order_digest text not null, policy_version bigint not null, recipient_tag text not null,
 version bigint not null default 1, state text not null default 'queued_link'
  check(state in('queued_link','link_prepared','link_accepted','code_requested','code_prepared','code_accepted','verified','responded','revoked')),
 token_hash text unique, code_hash text, proof_hash text, offer_hash text, failures integer not null default 0 check(failures between 0 and 5),
 provider_link_reference text, provider_code_reference text,
 issued_by uuid not null references auth.users(id), issued_at timestamptz not null default clock_timestamp(),
 expires_at timestamptz not null, acceptance_valid_until timestamptz not null,
 check(expires_at>issued_at),check(acceptance_valid_until>=expires_at),check(version>0)
);
alter table field_sales.confirmation_challenges enable row level security;
create index confirmation_recipient_rate on field_sales.confirmation_challenges(tenant_id,recipient_tag,issued_at);
create index confirmation_request on field_sales.confirmation_challenges(request_id,issued_at);

create function field_sales.confirmation_source(request uuid,revalidate boolean default true) returns jsonb
language plpgsql security definer set search_path='' as $$
declare r field_sales.order_requests; o sales.sales_orders; reviewed jsonb; lines jsonb; begin
 select * into r from field_sales.order_requests where id=request for share;
 if r.id is null or r.state<>'approved' or r.canonical_order_id is null
  or not exists(select 1 from core.tenants t join core.legal_entities e on e.tenant_id=t.id
   join core.branches b on b.tenant_id=t.id and b.legal_entity_id=e.id
   where t.id=r.tenant_id and e.id=r.legal_entity_id and b.id=r.branch_id
    and t.status in('active','trial') and e.status='active' and b.status='active') then
  raise exception using errcode='55000',message='CONFIRMATION_SOURCE_UNAVAILABLE'; end if;
 if revalidate then
  reviewed:=field_sales.prepare(r.tenant_id,r.legal_entity_id,r.branch_id,r.rep_id,r.input);
  if reviewed->>'source_digest' is distinct from r.source_digest then
   raise exception using errcode='40001',message='SOURCE_CHANGED'; end if;
 else
  perform field_sales.assignment(r.tenant_id,r.legal_entity_id,r.branch_id,r.customer_id,r.rep_id);
  if not exists(select 1 from crm.parties where tenant_id=r.tenant_id and id=r.customer_id and status='active') then
   raise exception using errcode='55000',message='CONFIRMATION_SOURCE_UNAVAILABLE'; end if;
 end if;
 select * into o from sales.sales_orders where id=r.canonical_order_id for share;
 if o.status<>'draft' or o.customer_id<>r.customer_id or o.tenant_id<>r.tenant_id
  or o.legal_entity_id<>r.legal_entity_id or o.branch_id<>r.branch_id then
  raise exception using errcode='55000',message='CONFIRMATION_SOURCE_UNAVAILABLE'; end if;
 select coalesce(jsonb_agg(to_jsonb(l) order by l.id),'[]') into lines from sales.sales_order_lines l where l.sales_order_id=o.id;
 return jsonb_build_object('request',to_jsonb(r),'order_version',o.version::text,
  'order_digest',encode(extensions.digest((to_jsonb(o)||jsonb_build_object('lines',lines))::text,'sha256'),'hex'));
end $$;
create function field_sales.confirmation_issue_context(t uuid,e uuid,b uuid,payload jsonb) returns jsonb
language plpgsql security definer set search_path='' as $$
declare c field_sales.confirmation_contacts; source jsonb; policy field_sales.confirmation_transport; issued_at timestamptz; begin
 if not field_sales.confirmation_ready(t) then
  raise exception using errcode='55000',message='CONFIRMATION_PROVIDER_UNAVAILABLE'; end if;
 if exists(select 1 from jsonb_object_keys(payload) k where k not in('id','request_id','contact_id','request_version','source_digest')) then
  raise exception using errcode='22023',message='CONFIRMATION_FIELDS_INVALID'; end if;
 if not exists(select 1 from field_sales.order_requests where id=(payload->>'request_id')::uuid
  and tenant_id=t and legal_entity_id=e and branch_id=b) then
  raise exception using errcode='42501',message='CONFIRMATION_SCOPE_INVALID'; end if;
 source:=field_sales.confirmation_source((payload->>'request_id')::uuid);
 if source->'request'->>'version' is distinct from payload->>'request_version'
  or source->'request'->>'source_digest' is distinct from payload->>'source_digest' then
  raise exception using errcode='40001',message='SOURCE_CHANGED'; end if;
 select * into c from field_sales.confirmation_contacts where id=(payload->>'contact_id')::uuid for share;
 if c.id is null or c.tenant_id<>t or c.legal_entity_id<>e or c.branch_id<>b
  or c.customer_id<>(source->'request'->>'customer_id')::uuid or not c.active
  or c.valid_until<=clock_timestamp()+interval '15 minutes' then
  raise exception using errcode='42501',message='CONTACT_NOT_AUTHORIZED'; end if;
 select * into policy from field_sales.confirmation_transport where tenant_id=t for share;
 issued_at:=clock_timestamp();
 return source||jsonb_build_object('contact_version',c.version::text,'policy_version',policy.version::text,
  'recipient_tag',encode(extensions.hmac(c.email,encode(policy.verification_secret,'hex'),'sha256'),'hex'),
  'issued_at',issued_at,'acceptance_valid_until',least(c.valid_until,issued_at+make_interval(mins=>policy.acceptance_minutes)));
end $$;
create function field_sales.confirmation_challenge_entity(c field_sales.confirmation_challenges) returns jsonb
language sql stable set search_path='' as $$
 select jsonb_build_object('id',c.id,'tenant_id',c.tenant_id,'legal_entity_id',c.legal_entity_id,'branch_id',c.branch_id,
  'request_id',c.request_id,'request_version',c.request_version::text,'contact_id',c.contact_id,'contact_version',c.contact_version::text,
  'source_digest',c.source_digest,'version',c.version::text,'state',c.state,'expires_at',c.expires_at,
  'acceptance_valid_until',c.acceptance_valid_until)
$$;

create function api.field_sales_confirmation_contacts(p_tenant_id uuid,p_legal_entity_id uuid,p_branch_id uuid,p_customer_id uuid,
 p_after uuid default null,p_limit integer default 50)
returns jsonb language plpgsql security definer set search_path='' as $$declare items jsonb; begin
 perform field_sales.require_company(p_tenant_id,p_legal_entity_id,p_branch_id,'sales.field.confirmations.manage');
 if p_limit is null or p_limit not between 1 and 200 then raise exception using errcode='22023',message='PAGE_INVALID'; end if;
 select coalesce(jsonb_agg(x.item order by x.id),'[]') into items from (
  select c.id,field_sales.confirmation_contact_entity(c) item from field_sales.confirmation_contacts c
  where c.tenant_id=p_tenant_id and c.legal_entity_id=p_legal_entity_id and c.branch_id=p_branch_id
   and c.customer_id=p_customer_id and c.active and c.valid_until>clock_timestamp() and (p_after is null or c.id>p_after)
  order by c.id limit p_limit+1) x;
 return jsonb_build_object('provider_state',case when field_sales.confirmation_ready(p_tenant_id) then 'configured' else 'unavailable' end,
  'items',(select coalesce(jsonb_agg(value order by ordinality),'[]') from jsonb_array_elements(items) with ordinality where ordinality<=p_limit),
  'next_cursor',case when jsonb_array_length(items)>p_limit then items->(p_limit-1)->>'id' end);
end $$;

create function api.field_sales_confirmation_command(p_tenant_id uuid,p_legal_entity_id uuid,p_branch_id uuid,
 p_command_id uuid,p_idempotency_key uuid,p_client_timestamp timestamptz,p_action text,p_payload jsonb,
 p_expected_entity_version bigint default null) returns jsonb
language plpgsql security definer set search_path='' as $$
declare c field_sales.confirmation_contacts; ch field_sales.confirmation_challenges; context jsonb;
 hash text; replay jsonb; before jsonb; entity jsonb; name text; begin
 perform field_sales.require_company(p_tenant_id,p_legal_entity_id,p_branch_id,'sales.field.confirmations.manage');
 if p_client_timestamp is null or coalesce(p_action,'') not in('authorize_contact','revoke_contact','issue_order','revoke_challenge')
  or jsonb_typeof(p_payload) is distinct from 'object' or p_command_id is null or p_idempotency_key is null then
  raise exception using errcode='22023',message='CONFIRMATION_COMMAND_INVALID'; end if;
 name:='sales.field.confirmation.'||p_action;
 if p_action='issue_order' then
  if p_expected_entity_version is not null then raise exception using errcode='22023',message='CONFIRMATION_COMMAND_INVALID'; end if;
  context:=field_sales.confirmation_issue_context(p_tenant_id,p_legal_entity_id,p_branch_id,p_payload);
 end if;
 hash:=core.wave3_request_hash(name,p_command_id,p_tenant_id,p_legal_entity_id,p_branch_id,p_payload,p_expected_entity_version);
 replay:=core.wave3_replay(p_tenant_id,name,p_command_id,p_idempotency_key,hash);
 if replay is not null then return replay; end if;
 if p_action='revoke_challenge' then
  if exists(select 1 from jsonb_object_keys(p_payload) k where k not in('id','reason'))
   or length(trim(coalesce(p_payload->>'reason',''))) not between 1 and 500 then
   raise exception using errcode='22023',message='REVOCATION_REASON_REQUIRED'; end if;
  select * into ch from field_sales.confirmation_challenges where id=(p_payload->>'id')::uuid
   and tenant_id=p_tenant_id and legal_entity_id=p_legal_entity_id and branch_id=p_branch_id for update;
  if ch.id is null then raise exception using errcode='42501',message='CONFIRMATION_SCOPE_INVALID'; end if;
  before:=field_sales.confirmation_challenge_entity(ch);
  perform core.wave3_assert_expected_version(ch.version,p_expected_entity_version,before);
  update field_sales.confirmation_challenges set state='revoked',version=version+1 where id=ch.id returning * into ch;
  return core.wave3_finish_command(p_tenant_id,name,p_command_id,'field_confirmation_challenge',ch.id,p_idempotency_key,hash,before,
   field_sales.confirmation_challenge_entity(ch),p_legal_entity_id,p_branch_id);
 end if;
 if p_action='issue_order' then
  perform pg_advisory_xact_lock(hashtextextended(p_tenant_id::text||(context->>'recipient_tag'),0));
  if (select count(*) from field_sales.confirmation_challenges where tenant_id=p_tenant_id
   and recipient_tag=context->>'recipient_tag' and issued_at>clock_timestamp()-interval '1 hour')>=5 then
   raise exception using errcode='54000',message='CONFIRMATION_RATE_LIMITED'; end if;
  update field_sales.confirmation_challenges set state='revoked',version=version+1
   where request_id=(p_payload->>'request_id')::uuid and state<>'revoked';
  insert into field_sales.confirmation_challenges(id,tenant_id,legal_entity_id,branch_id,request_id,request_version,source_digest,
   contact_id,contact_version,order_digest,policy_version,recipient_tag,issued_by,issued_at,expires_at,acceptance_valid_until)
   values((p_payload->>'id')::uuid,p_tenant_id,p_legal_entity_id,p_branch_id,(p_payload->>'request_id')::uuid,
    (p_payload->>'request_version')::bigint,p_payload->>'source_digest',(p_payload->>'contact_id')::uuid,
    (context->>'contact_version')::bigint,context->>'order_digest',(context->>'policy_version')::bigint,
    context->>'recipient_tag',auth.uid(),(context->>'issued_at')::timestamptz,
    (context->>'issued_at')::timestamptz+interval '15 minutes',(context->>'acceptance_valid_until')::timestamptz)
   returning * into ch;
  return core.wave3_finish_command(p_tenant_id,name,p_command_id,'field_confirmation_challenge',ch.id,p_idempotency_key,hash,null,
   field_sales.confirmation_challenge_entity(ch),p_legal_entity_id,p_branch_id);
 end if;
 if exists(select 1 from jsonb_object_keys(p_payload) k where k not in
  ('id','customer_id','name','email','authority_note','valid_until')) then
  raise exception using errcode='22023',message='CONTACT_FIELDS_INVALID'; end if;
 select * into c from field_sales.confirmation_contacts where id=(p_payload->>'id')::uuid for update;
 if c.id is not null then
  if c.tenant_id<>p_tenant_id or c.legal_entity_id<>p_legal_entity_id or c.branch_id<>p_branch_id then
   raise exception using errcode='42501',message='CONTACT_SCOPE_INVALID'; end if;
  before:=field_sales.confirmation_contact_entity(c);
  perform core.wave3_assert_expected_version(c.version,p_expected_entity_version,before);
 elsif p_expected_entity_version is not null or p_action='revoke_contact' then
  raise exception using errcode='40001',message='VERSION_CONFLICT'; end if;
 if p_action='revoke_contact' then
  update field_sales.confirmation_contacts set active=false,version=version+1
   where id=c.id returning * into c;
 else
  if not exists(select 1 from crm.parties where tenant_id=p_tenant_id and id=(p_payload->>'customer_id')::uuid
   and status='active' and kind in('customer','both'))
   or (p_payload->>'valid_until')::timestamptz<=clock_timestamp()
   or (p_payload->>'valid_until')::timestamptz>clock_timestamp()+interval '366 days' then
   raise exception using errcode='22023',message='CONTACT_INVALID'; end if;
  insert into field_sales.confirmation_contacts(id,tenant_id,legal_entity_id,branch_id,customer_id,name,email,authority_note,valid_until,authorized_by)
   values((p_payload->>'id')::uuid,p_tenant_id,p_legal_entity_id,p_branch_id,(p_payload->>'customer_id')::uuid,
    trim(p_payload->>'name'),lower(trim(p_payload->>'email')),trim(p_payload->>'authority_note'),(p_payload->>'valid_until')::timestamptz,auth.uid())
   on conflict(id) do update set customer_id=excluded.customer_id,name=excluded.name,email=excluded.email,
    authority_note=excluded.authority_note,valid_until=excluded.valid_until,active=true,
    authorized_by=auth.uid(),authorized_at=clock_timestamp(),version=field_sales.confirmation_contacts.version+1
   where field_sales.confirmation_contacts.tenant_id=p_tenant_id
    and field_sales.confirmation_contacts.legal_entity_id=p_legal_entity_id and field_sales.confirmation_contacts.branch_id=p_branch_id
    and field_sales.confirmation_contacts.version=p_expected_entity_version
   returning * into c;
  if c.id is null then raise exception using errcode='40001',message='VERSION_CONFLICT'; end if;
 end if;
 entity:=field_sales.confirmation_contact_entity(c);
 return core.wave3_finish_command(p_tenant_id,name,p_command_id,'field_confirmation_contact',c.id,
  p_idempotency_key,hash,before,entity,p_legal_entity_id,p_branch_id);
end $$;
revoke all on function api.field_sales_confirmation_contacts(uuid,uuid,uuid,uuid,uuid,integer),
 api.field_sales_confirmation_command(uuid,uuid,uuid,uuid,uuid,timestamptz,text,jsonb,bigint) from public,anon;
grant execute on function api.field_sales_confirmation_contacts(uuid,uuid,uuid,uuid,uuid,integer),
 api.field_sales_confirmation_command(uuid,uuid,uuid,uuid,uuid,timestamptz,text,jsonb,bigint) to authenticated;

create function field_sales.confirmation_current(ch field_sales.confirmation_challenges,check_expiry boolean default true)
returns boolean language plpgsql security definer set search_path='' as $$
declare c field_sales.confirmation_contacts; policy field_sales.confirmation_transport; source jsonb; begin
 if ch.id is null or ch.state='revoked' or ch.failures>=5
  or (check_expiry and ch.expires_at<=clock_timestamp()) or ch.acceptance_valid_until<=clock_timestamp() then return false; end if;
 select * into policy from field_sales.confirmation_transport where tenant_id=ch.tenant_id for share;
 if check_expiry and (policy.tenant_id is null or not policy.enabled or policy.version<>ch.policy_version) then return false; end if;
 select * into c from field_sales.confirmation_contacts where id=ch.contact_id for share;
 if c.id is null or not c.active or c.valid_until<=clock_timestamp() or c.version<>ch.contact_version then return false; end if;
 source:=field_sales.confirmation_source(ch.request_id,check_expiry);
 return (source->'request'->>'version')::bigint=ch.request_version
  and source->'request'->>'source_digest'=ch.source_digest and source->>'order_digest'=ch.order_digest
  and c.tenant_id=ch.tenant_id and c.legal_entity_id=ch.legal_entity_id and c.branch_id=ch.branch_id
  and c.customer_id=(source->'request'->>'customer_id')::uuid;
 exception when others then return false;
end $$;
create function field_sales.confirmation_code_hash(ch field_sales.confirmation_challenges,code text) returns text
language sql stable security definer set search_path='' as $$
 select encode(extensions.hmac(ch.id::text||':'||code,encode(p.verification_secret,'hex'),'sha256'),'hex')
 from field_sales.confirmation_transport p where p.tenant_id=ch.tenant_id
$$;
-- Service-only preparation/acknowledgement seam. There is deliberately no
-- network sender or background job. Secrets arrive ephemerally from a future
-- reviewed worker and only hashes are retained. Acknowledgements are not proof
-- of email delivery or legal authority.
create function field_sales.confirmation_dispatch(p_id uuid,p_step text,p_secret text,p_provider_reference text default null)
returns jsonb language plpgsql security definer set search_path='' as $$
declare ch field_sales.confirmation_challenges; secret_hash text; begin
 select * into ch from field_sales.confirmation_challenges where id=p_id for update;
 if not field_sales.confirmation_current(ch) then
  raise exception using errcode='55000',message='CONFIRMATION_UNAVAILABLE'; end if;
 if p_step in('prepare_link','ack_link') then
  if coalesce(p_secret,'') !~ '^[0-9a-f]{64}$' then raise exception using errcode='22023',message='DISPATCH_INVALID'; end if;
  secret_hash:=encode(extensions.digest(p_secret,'sha256'),'hex');
  if p_step='prepare_link' and ch.state in('queued_link','link_prepared') then
   if ch.token_hash is not null and ch.token_hash<>secret_hash then raise exception using errcode='22023',message='DISPATCH_IMMUTABLE'; end if;
   update field_sales.confirmation_challenges set token_hash=secret_hash,state='link_prepared' where id=p_id;
  elsif p_step='ack_link' and ch.state in('link_prepared','link_accepted') and ch.token_hash=secret_hash
   and length(coalesce(p_provider_reference,'')) between 1 and 200 then
   if ch.provider_link_reference is not null and ch.provider_link_reference<>p_provider_reference then
    raise exception using errcode='22023',message='DISPATCH_IMMUTABLE'; end if;
   update field_sales.confirmation_challenges set state='link_accepted',provider_link_reference=p_provider_reference where id=p_id;
  else raise exception using errcode='55000',message='DISPATCH_STATE_INVALID'; end if;
 elsif p_step in('prepare_code','ack_code') then
  if coalesce(p_secret,'') !~ '^[0-9]{6}$' then raise exception using errcode='22023',message='DISPATCH_INVALID'; end if;
  secret_hash:=field_sales.confirmation_code_hash(ch,p_secret);
  if p_step='prepare_code' and ch.state in('code_requested','code_prepared') then
   if ch.code_hash is not null and ch.code_hash<>secret_hash then raise exception using errcode='22023',message='DISPATCH_IMMUTABLE'; end if;
   update field_sales.confirmation_challenges set code_hash=secret_hash,state='code_prepared' where id=p_id;
  elsif p_step='ack_code' and ch.state in('code_prepared','code_accepted') and ch.code_hash=secret_hash
   and length(coalesce(p_provider_reference,'')) between 1 and 200 then
   if ch.provider_code_reference is not null and ch.provider_code_reference<>p_provider_reference then
    raise exception using errcode='22023',message='DISPATCH_IMMUTABLE'; end if;
   update field_sales.confirmation_challenges set state='code_accepted',provider_code_reference=p_provider_reference where id=p_id;
  else raise exception using errcode='55000',message='DISPATCH_STATE_INVALID'; end if;
 else raise exception using errcode='22023',message='DISPATCH_INVALID'; end if;
 return jsonb_build_object('id',p_id,'kind',case when p_step in('prepare_link','ack_link') then 'order_link' else 'verification_code' end,
  'recipient',(select email from field_sales.confirmation_contacts where id=ch.contact_id),'expires_at',ch.expires_at);
end $$;
grant usage on schema field_sales to service_role;
revoke all on function field_sales.confirmation_dispatch(uuid,text,text,text) from public,anon,authenticated;
grant execute on function field_sales.confirmation_dispatch(uuid,text,text,text) to service_role;

-- Public RPCs are POST-only, anonymous, non-cacheable and intentionally reveal
-- no contact address or offer until the separately delivered code is verified.
create function field_sales.confirmation_public_request() returns boolean
language plpgsql set search_path='' as $$begin
 perform set_config('response.headers','[{"Cache-Control":"no-store"},{"Referrer-Policy":"no-referrer"}]',true);
 return auth.uid() is null and coalesce(current_setting('request.method',true),'')='POST';
end $$;
create function field_sales.confirmation_offer(ch field_sales.confirmation_challenges) returns jsonb
language sql stable security definer set search_path='' as $$
 select jsonb_build_object('request_id',r.id,'request_version',r.version::text,'source_digest',r.source_digest,
  'company',(select name from core.legal_entities where tenant_id=r.tenant_id and id=r.legal_entity_id),
  'customer',(select display_name from crm.parties where tenant_id=r.tenant_id and id=r.customer_id),
  'reference',r.input->>'reference','currency_code',r.preview->>'currency_code','discount_percent',r.preview->>'discount_percent',
  'terms',r.preview->'terms','valid_until',ch.acceptance_valid_until,
  'totals',(r.preview->'pricing')-'lines','lines',(select jsonb_agg(jsonb_build_object(
   'description',line->>'description','quantity',line->>'quantity','unit_price',line->>'unit_price',
   'unit',(select symbol from inventory.units where tenant_id=r.tenant_id and id=(line->>'unit_id')::uuid),
   'line_discount_amount',line->>'line_discount_amount','header_discount_amount',line->>'header_discount_amount',
   'tax_amount',line->>'tax_amount','tax_name',line->>'tax_name','tax_rate',line->>'tax_rate',
   'tax_inclusive',line->'tax_inclusive','line_total',line->>'line_total') order by n)
   from jsonb_array_elements(r.preview->'pricing'->'lines') with ordinality p(line,n)))
 from field_sales.order_requests r where r.id=ch.request_id
$$;
create function api.field_sales_confirmation_request_code(p_token text) returns jsonb
language plpgsql volatile security definer set search_path='' as $$
declare ch field_sales.confirmation_challenges; begin
 if not field_sales.confirmation_public_request() or coalesce(p_token,'') !~ '^[0-9a-f]{64}$' then
  return jsonb_build_object('state','unavailable'); end if;
 select * into ch from field_sales.confirmation_challenges where token_hash=encode(extensions.digest(p_token,'sha256'),'hex') for update;
 if not field_sales.confirmation_current(ch) or ch.state not in('link_accepted','code_requested','code_prepared','code_accepted','verified') then
  return jsonb_build_object('state','unavailable'); end if;
 if ch.state='link_accepted' then
  update field_sales.confirmation_challenges set state='code_requested' where id=ch.id;
 end if;
 return jsonb_build_object('state','check_email');
end $$;
create function api.field_sales_confirmation_verify(p_token text,p_code text) returns jsonb
language plpgsql volatile security definer set search_path='' as $$
declare ch field_sales.confirmation_challenges; proof text; secret bytea; offer jsonb; review_hash text; begin
 if not field_sales.confirmation_public_request() or coalesce(p_token,'') !~ '^[0-9a-f]{64}$' then
  return jsonb_build_object('state','unavailable'); end if;
 select * into ch from field_sales.confirmation_challenges where token_hash=encode(extensions.digest(p_token,'sha256'),'hex') for update;
 if not field_sales.confirmation_current(ch) or ch.state not in('code_accepted','verified','responded') then
  return jsonb_build_object('state','unavailable'); end if;
 if ch.code_hash is distinct from field_sales.confirmation_code_hash(ch,coalesce(p_code,'')) then
  if ch.state<>'responded' then
   update field_sales.confirmation_challenges set failures=failures+1,
    state=case when failures+1>=5 then 'revoked' else state end where id=ch.id;
  end if;
  return jsonb_build_object('state','unavailable'); end if;
 if ch.state='responded' then return jsonb_build_object('state','already_recorded'); end if;
 select verification_secret into secret from field_sales.confirmation_transport where tenant_id=ch.tenant_id;
 offer:=field_sales.confirmation_offer(ch);review_hash:=encode(extensions.digest(offer::text,'sha256'),'hex');
 proof:=encode(extensions.hmac(ch.id::text||':'||ch.token_hash||':'||ch.code_hash||':'||review_hash,encode(secret,'hex'),'sha256'),'hex');
 update field_sales.confirmation_challenges set state='verified',proof_hash=encode(extensions.digest(proof,'sha256'),'hex'),
  offer_hash=review_hash where id=ch.id;
 return jsonb_build_object('state','review','proof',proof,'offer',offer);
end $$;
grant usage on schema api to anon;
revoke all on function api.field_sales_confirmation_request_code(text),api.field_sales_confirmation_verify(text,text) from public,authenticated;
grant execute on function api.field_sales_confirmation_request_code(text),api.field_sales_confirmation_verify(text,text) to anon;

create table field_sales.order_responses (
 id uuid primary key default gen_random_uuid(), challenge_id uuid not null unique references field_sales.confirmation_challenges(id),
 request_id uuid not null references field_sales.order_requests(id), request_version bigint not null, source_digest text not null,
 order_digest text not null, contact_id uuid not null references field_sales.confirmation_contacts(id), contact_version bigint not null,
 contact_snapshot jsonb not null, offer_snapshot jsonb not null,
 response text not null check(response in('accepted','rejected')), reason text not null check(length(reason)<=500),
 authority_attested boolean not null check(authority_attested), method text not null check(method='email_link_and_code'),
 responded_at timestamptz not null default clock_timestamp(), valid_until timestamptz not null
);
alter table field_sales.order_responses enable row level security;
create index confirmation_response_request on field_sales.order_responses(request_id,responded_at);
create function field_sales.confirmation_response_receipt(r field_sales.order_responses) returns jsonb
language sql stable set search_path='' as $$
 select jsonb_build_object('state','recorded','id',r.id,'request_id',r.request_id,'request_version',r.request_version::text,
  'source_digest',r.source_digest,'response',r.response,'responded_at',r.responded_at,'valid_until',r.valid_until,'method',r.method)
$$;
create function api.field_sales_confirmation_respond(p_token text,p_proof text,p_response text,p_reason text,p_authorized boolean)
returns jsonb language plpgsql volatile security definer set search_path='' as $$
declare ch field_sales.confirmation_challenges; response field_sales.order_responses; c field_sales.confirmation_contacts; reviewed_offer jsonb; begin
 if not field_sales.confirmation_public_request() or coalesce(p_token,'') !~ '^[0-9a-f]{64}$'
  or coalesce(p_proof,'') !~ '^[0-9a-f]{64}$' or coalesce(p_response,'') not in('accept','reject')
  or p_authorized is distinct from true or length(coalesce(p_reason,''))>500 then
  return jsonb_build_object('state','unavailable'); end if;
 select * into ch from field_sales.confirmation_challenges where token_hash=encode(extensions.digest(p_token,'sha256'),'hex') for update;
 if not field_sales.confirmation_current(ch) or ch.state not in('verified','responded') then
  return jsonb_build_object('state','unavailable'); end if;
 if ch.proof_hash is distinct from encode(extensions.digest(p_proof,'sha256'),'hex') then
  if ch.state<>'responded' then
   update field_sales.confirmation_challenges set failures=failures+1,
    state=case when failures+1>=5 then 'revoked' else state end where id=ch.id;
  end if;
  return jsonb_build_object('state','unavailable'); end if;
 select * into response from field_sales.order_responses where challenge_id=ch.id;
 if response.id is not null then
  if response.response=(case when p_response='accept' then 'accepted' else 'rejected' end)
   and response.reason=trim(coalesce(p_reason,'')) then return field_sales.confirmation_response_receipt(response); end if;
  return jsonb_build_object('state','conflict');
 end if;
 reviewed_offer:=field_sales.confirmation_offer(ch);
 if ch.offer_hash is distinct from encode(extensions.digest(reviewed_offer::text,'sha256'),'hex') then
  return jsonb_build_object('state','unavailable'); end if;
 select * into c from field_sales.confirmation_contacts where id=ch.contact_id;
 insert into field_sales.order_responses(challenge_id,request_id,request_version,source_digest,order_digest,
  contact_id,contact_version,contact_snapshot,offer_snapshot,response,reason,authority_attested,method,valid_until)
  values(ch.id,ch.request_id,ch.request_version,ch.source_digest,ch.order_digest,ch.contact_id,ch.contact_version,
   field_sales.confirmation_contact_entity(c),reviewed_offer,
   case when p_response='accept' then 'accepted' else 'rejected' end,trim(coalesce(p_reason,'')),true,'email_link_and_code',ch.acceptance_valid_until)
  returning * into response;
 update field_sales.confirmation_challenges set state='responded' where id=ch.id;
 return field_sales.confirmation_response_receipt(response);
end $$;
revoke all on function api.field_sales_confirmation_respond(text,text,text,text,boolean) from public,authenticated;
grant execute on function api.field_sales_confirmation_respond(text,text,text,text,boolean) to anon;

create function api.field_sales_confirmation_receipt(p_tenant_id uuid,p_legal_entity_id uuid,p_branch_id uuid,p_idempotency_key uuid)
returns jsonb language plpgsql security definer set search_path='' as $$declare receipt core.command_receipts; entity jsonb; begin
 perform field_sales.require_company(p_tenant_id,p_legal_entity_id,p_branch_id,'sales.field.confirmations.manage');
 select * into receipt from core.command_receipts where tenant_id=p_tenant_id and actor_id=auth.uid()
  and idempotency_key=p_idempotency_key and command_name in('sales.field.confirmation.authorize_contact',
   'sales.field.confirmation.revoke_contact','sales.field.confirmation.issue_order','sales.field.confirmation.revoke_challenge');
 if receipt.id is null then return jsonb_build_object('state','not_found'); end if;
 entity:=receipt.response->'entity';
 if entity->>'tenant_id' is distinct from p_tenant_id::text or entity->>'legal_entity_id' is distinct from p_legal_entity_id::text
  or entity->>'branch_id' is distinct from p_branch_id::text then
  raise exception using errcode='42501',message='RECEIPT_SCOPE_INVALID'; end if;
 return jsonb_build_object('state','committed','receipt',receipt.response);
end $$;
revoke all on function api.field_sales_confirmation_receipt(uuid,uuid,uuid,uuid) from public,anon;
grant execute on function api.field_sales_confirmation_receipt(uuid,uuid,uuid,uuid) to authenticated;

create function field_sales.confirmation_status(r field_sales.order_requests) returns jsonb
language plpgsql security definer set search_path='' as $$
declare response field_sales.order_responses; ch field_sales.confirmation_challenges; state text; begin
 select * into response from field_sales.order_responses where request_id=r.id order by responded_at desc,id desc limit 1;
 if response.id is null then return jsonb_build_object('state','email_link_pending'); end if;
 select * into ch from field_sales.confirmation_challenges where id=response.challenge_id;
 state:=case when response.valid_until<=clock_timestamp() then 'expired'
  when not field_sales.confirmation_current(ch,false) then 'superseded' else response.response end;
 return jsonb_build_object('state',state,'responded_at',response.responded_at,'valid_until',response.valid_until,'method',response.method);
end $$;
create or replace function field_sales.entity(r field_sales.order_requests) returns jsonb
language sql stable set search_path='' as $$
 select jsonb_build_object('id',r.id,'version',r.version::text,'tenant_id',r.tenant_id,
  'legal_entity_id',r.legal_entity_id,'branch_id',r.branch_id,'customer_id',r.customer_id,'rep_id',r.rep_id,
  'input',r.input,'source_digest',r.source_digest,'preview',r.preview-'canonical','company_state',r.state,
  'canonical_order_id',r.canonical_order_id,'canonical_state',case when r.canonical_order_id is not null then 'draft' end,
  'customer_state',c.status->>'state','customer_response',c.status,'delivery_state','not_requested','decision_by',r.decision_by,
  'decision_reason',r.decision_reason,'decided_at',r.decided_at,'created_at',r.created_at)
 from (select field_sales.confirmation_status(r) status) c
$$;
-- Customer evidence never advances or edits canonical commerce. The separately
-- reviewed company progression/credit/stock slice remains unavailable.
create or replace function field_sales.guard_order() returns trigger
language plpgsql security definer set search_path='' as $$declare order_id uuid; r field_sales.order_requests; begin
 if tg_table_name='sales_orders' then order_id:=old.id;
 else order_id:=case when tg_op='INSERT' then new.sales_order_id else old.sales_order_id end; end if;
 select * into r from field_sales.order_requests where canonical_order_id=order_id;
 if r.id is not null then
  if field_sales.confirmation_status(r)->>'state'='accepted' then
   raise exception using errcode='55000',message='COMPANY_PROGRESSION_UNAVAILABLE'; end if;
  raise exception using errcode='55000',message='CUSTOMER_ACCEPTANCE_REQUIRED';
 end if;
 if tg_op='DELETE' then return old; end if; return new;
end $$;

-- Close explicit ACLs as well as the prerequisite's default privileges, so a
-- different reviewed migration creator cannot expose private helper execution.
do $$declare f record; begin
 for f in select p.oid from pg_proc p join pg_namespace n on n.oid=p.pronamespace
  where n.nspname='field_sales' and left(p.proname,13)='confirmation_' loop
  execute format('revoke all on function %s from public,anon,authenticated,service_role',f.oid::regprocedure);
 end loop;
end $$;
revoke all on field_sales.confirmation_contacts,field_sales.confirmation_transport,
 field_sales.confirmation_challenges,field_sales.order_responses from public,anon,authenticated,service_role;
revoke all on function api.field_sales_confirmation_request_code(text),api.field_sales_confirmation_verify(text,text),
 api.field_sales_confirmation_respond(text,text,text,text,boolean) from public,authenticated,service_role;
grant execute on function field_sales.confirmation_dispatch(uuid,text,text,text) to service_role;


-- Source: supabase/candidates/20261102120000_field_confirmation_company_workspace.sql
-- CANDIDATE ONLY. Compose after governance and order-email candidates inside the
-- rollback harness. No sender, migration installation or progression activation.
-- At most one active challenge, including races between different recipients.
create unique index confirmation_one_current_request on field_sales.confirmation_challenges(request_id) where state<>'revoked';
create function api.field_sales_confirmation_subjects(p_tenant_id uuid,p_legal_entity_id uuid,p_branch_id uuid,
 p_after uuid default null,p_limit integer default 50) returns jsonb
language plpgsql security definer set search_path='' as $$declare items jsonb; begin
 perform field_sales.require_company(p_tenant_id,p_legal_entity_id,p_branch_id,'sales.field.confirmations.manage');
 if p_limit is null or p_limit not between 1 and 200 then raise exception using errcode='22023',message='PAGE_INVALID'; end if;
 select coalesce(jsonb_agg(x.item order by x.id),'[]') into items from (
  select r.id,field_sales.entity(r)||jsonb_build_object('customer_name',c.display_name) item
  from field_sales.order_requests r join crm.parties c on c.tenant_id=r.tenant_id and c.id=r.customer_id
  where r.tenant_id=p_tenant_id and r.legal_entity_id=p_legal_entity_id and r.branch_id=p_branch_id
   and r.state='approved' and (p_after is null or r.id>p_after) order by r.id limit p_limit+1) x;
 return jsonb_build_object('provider_state',case when field_sales.confirmation_ready(p_tenant_id) then 'configured' else 'unavailable' end,
  'items',(select coalesce(jsonb_agg(value order by ordinality),'[]') from jsonb_array_elements(items) with ordinality where ordinality<=p_limit),
  'next_cursor',case when jsonb_array_length(items)>p_limit then items->(p_limit-1)->>'id' end);
end $$;

create function api.field_sales_confirmation_challenges(p_tenant_id uuid,p_legal_entity_id uuid,p_branch_id uuid,p_request_id uuid,
 p_after uuid default null,p_limit integer default 50) returns jsonb
language plpgsql security definer set search_path='' as $$declare items jsonb; begin
 perform field_sales.require_company(p_tenant_id,p_legal_entity_id,p_branch_id,'sales.field.confirmations.manage');
 if p_limit is null or p_limit not between 1 and 200 then raise exception using errcode='22023',message='PAGE_INVALID'; end if;
 if not exists(select 1 from field_sales.order_requests where id=p_request_id and tenant_id=p_tenant_id
  and legal_entity_id=p_legal_entity_id and branch_id=p_branch_id) then
  raise exception using errcode='42501',message='CONFIRMATION_SCOPE_INVALID'; end if;
 select coalesce(jsonb_agg(x.item order by x.id),'[]') into items from (
  select ch.id,field_sales.confirmation_challenge_entity(ch)||jsonb_build_object(
   'effective_state',case when ch.state='revoked' then 'revoked'
    when ch.state='responded' then field_sales.confirmation_status(r)->>'state'
    when ch.expires_at<=clock_timestamp() then 'expired'
    when not field_sales.confirmation_current(ch) then 'superseded' else ch.state end,
   'recipient_name',c.name) item
  from field_sales.confirmation_challenges ch join field_sales.order_requests r on r.id=ch.request_id
   join field_sales.confirmation_contacts c on c.id=ch.contact_id
  where ch.request_id=p_request_id and ch.tenant_id=p_tenant_id and ch.legal_entity_id=p_legal_entity_id and ch.branch_id=p_branch_id
   and (p_after is null or ch.id>p_after) order by ch.id limit p_limit+1) x;
 return jsonb_build_object('items',(select coalesce(jsonb_agg(value order by ordinality),'[]')
  from jsonb_array_elements(items) with ordinality where ordinality<=p_limit),
  'next_cursor',case when jsonb_array_length(items)>p_limit then items->(p_limit-1)->>'id' end);
end $$;

-- Staff UI additionally binds the exact contact revision it reviewed. This
-- wrapper delegates to the original audited command using the caller's JWT.
-- Exact receipt recovery remains available without requiring stale source data.
create function api.field_sales_confirmation_company_command(p_tenant_id uuid,p_legal_entity_id uuid,p_branch_id uuid,
 p_command_id uuid,p_idempotency_key uuid,p_client_timestamp timestamptz,p_action text,p_payload jsonb,
 p_expected_entity_version bigint default null) returns jsonb
language plpgsql security definer set search_path='' as $$declare c field_sales.confirmation_contacts; r field_sales.order_requests; replay jsonb; hash text; result jsonb; begin
 perform field_sales.require_company(p_tenant_id,p_legal_entity_id,p_branch_id,'sales.field.confirmations.manage');
 if p_action='issue_order' then
  select * into c from field_sales.confirmation_contacts where id=(p_payload->>'contact_id')::uuid
   and tenant_id=p_tenant_id and legal_entity_id=p_legal_entity_id and branch_id=p_branch_id for share;
  if c.id is null then raise exception using errcode='42501',message='CONTACT_NOT_AUTHORIZED'; end if;
  if c.version::text is distinct from p_payload->>'contact_version' then
   raise exception using errcode='40001',message='CONTACT_CHANGED'; end if;
  hash:=core.wave3_request_hash('sales.field.confirmation.issue_order',p_command_id,p_tenant_id,p_legal_entity_id,p_branch_id,
   p_payload-'contact_version',p_expected_entity_version);
  replay:=core.wave3_replay(p_tenant_id,'sales.field.confirmation.issue_order',p_command_id,p_idempotency_key,hash);
  if replay is not null then
   if replay->'entity'->>'contact_version' is distinct from p_payload->>'contact_version' then
    raise exception using errcode='22023',message='IDEMPOTENCY_PAYLOAD_CHANGED'; end if;
   return replay;
  end if;
  perform pg_advisory_xact_lock(hashtextextended('field-confirmation:'||(p_payload->>'request_id'),0));
  select * into r from field_sales.order_requests where id=(p_payload->>'request_id')::uuid
   and tenant_id=p_tenant_id and legal_entity_id=p_legal_entity_id and branch_id=p_branch_id for share;
  if r.id is null then raise exception using errcode='42501',message='CONFIRMATION_SCOPE_INVALID'; end if;
  if field_sales.confirmation_status(r)->>'state'='accepted' then
   raise exception using errcode='55000',message='RESPONSE_ALREADY_CURRENT'; end if;
 elsif p_payload ? 'contact_version' then raise exception using errcode='22023',message='CONFIRMATION_FIELDS_INVALID'; end if;
 result:=api.field_sales_confirmation_command(p_tenant_id,p_legal_entity_id,p_branch_id,p_command_id,p_idempotency_key,
  p_client_timestamp,p_action,p_payload-'contact_version',p_expected_entity_version);
 if p_action='issue_order' and result->'entity'->>'contact_version' is distinct from p_payload->>'contact_version' then
  raise exception using errcode='22023',message='IDEMPOTENCY_PAYLOAD_CHANGED'; end if;
 return result;
end $$;
revoke all on function api.field_sales_confirmation_subjects(uuid,uuid,uuid,uuid,integer),
 api.field_sales_confirmation_challenges(uuid,uuid,uuid,uuid,uuid,integer),
 api.field_sales_confirmation_company_command(uuid,uuid,uuid,uuid,uuid,timestamptz,text,jsonb,bigint) from public,anon,service_role;
grant execute on function api.field_sales_confirmation_subjects(uuid,uuid,uuid,uuid,integer),
 api.field_sales_confirmation_challenges(uuid,uuid,uuid,uuid,uuid,integer),
 api.field_sales_confirmation_company_command(uuid,uuid,uuid,uuid,uuid,timestamptz,text,jsonb,bigint) to authenticated;
-- Only the reviewed staff wrapper remains callable by clients. Its owner calls
-- the original command internally; no role is impersonated or granted authority.
revoke all on function api.field_sales_confirmation_command(uuid,uuid,uuid,uuid,uuid,timestamptz,text,jsonb,bigint) from public,anon,authenticated,service_role;


-- Assertions run on the actual complete hosted schema; no Auth identities are invented.
do $checks$ begin
 if (select count(*) from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='api' and p.proname like 'field_sales_confirmation_%' and has_function_privilege('anon',p.oid,'execute'))<>3 then raise exception 'ANONYMOUS_SURFACE_INVALID'; end if;
 if has_function_privilege('authenticated','api.field_sales_confirmation_command(uuid,uuid,uuid,uuid,uuid,timestamptz,text,jsonb,bigint)','execute') then raise exception 'LEGACY_COMMAND_BYPASS'; end if;
 if exists(select 1 from field_sales.confirmation_transport where enabled) then raise exception 'TRANSPORT_MUST_REMAIN_OFF'; end if;
 if to_regclass('field_sales.confirmation_one_current_request') is null then raise exception 'CURRENT_CHALLENGE_CONSTRAINT_MISSING'; end if;
end $checks$;
rollback to savepoint field_rehearsal_candidate;
do $restored$ begin
 if to_regnamespace('field_sales') is not null then raise exception 'CANDIDATE_NOT_ROLLED_BACK'; end if;
 if (select value from field_rehearsal_before) is distinct from jsonb_build_object('definitions',(select coalesce(jsonb_agg(jsonb_build_object('signature',p.oid::regprocedure::text,'definition',pg_get_functiondef(p.oid),'acl',p.proacl::text) order by p.oid),'[]') from pg_proc p where p.oid=any(array['core.has_permission(uuid,text,uuid,uuid)','core.list_capabilities(uuid)','core.wave2_replay(uuid,text,uuid,text)','core.wave3_replay(uuid,text,uuid,uuid,text)','core.bootstrap_tenant_impl(text,text,text,text,text,text,text,text,uuid)','people.require_access(uuid,uuid,uuid,text)']::regprocedure[])),'permissions',(select md5(coalesce(jsonb_agg(to_jsonb(p) order by p.code)::text,'')) from core.permissions p),'entitlements',(select md5(coalesce(jsonb_agg(to_jsonb(p) order by p.plan_code,p.entitlement_code)::text,'')) from billing.plan_entitlements p),'schema_acls',(select jsonb_agg(jsonb_build_object('schema',nspname,'acl',nspacl::text) order by nspname) from pg_namespace where nspname in('api','core','people','storage')),'policies',(select md5(coalesce(jsonb_agg(to_jsonb(p) order by schemaname,tablename,policyname)::text,'')) from pg_policies p)) then raise exception 'ORIGINAL_STATE_NOT_RESTORED'; end if;
end $restored$;
rollback;
select jsonb_build_object('project','xpdoufauvrbdmxgngetv','server_version',current_setting('server_version'),'schema_compatibility','three_candidates_composed_on_full_hosted_schema','anonymous_surface',3,'original_functions_acls_permissions_entitlements_policies_restored',true,'candidate_removed',to_regnamespace('field_sales') is null,'migration_count',(select count(*) from supabase_migrations.schema_migrations),'migration_versions_md5',(select md5(string_agg(version,',' order by version)) from supabase_migrations.schema_migrations),'migration_installed',false,'transport_enabled',false,'genuine_auth_flow_tested',false,'observed_at',clock_timestamp()) as field_sales_rehearsal;
