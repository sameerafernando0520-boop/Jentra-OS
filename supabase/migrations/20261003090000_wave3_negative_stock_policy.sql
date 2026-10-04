-- Candidate only. Approved FR-353 / EC-323 interim policy, 2026-10-03.
-- Supersedes public paths additively; prior migration files are untouched.
insert into core.permissions(code,module,description,privileged) values
 ('inventory.stock.policy.manage','inventory','Version the legal-entity negative-stock policy.',true)
on conflict(code) do nothing;
insert into core.role_permissions(tenant_id,role_id,permission_code)
select tenant_id,id,'inventory.stock.policy.manage' from core.roles where code='tenant_owner'
on conflict(role_id,permission_code) do nothing;

create table inventory.negative_stock_policy_versions (
 id uuid primary key,tenant_id uuid not null,legal_entity_id uuid not null,branch_id uuid not null,
 version bigint not null check(version>0),active boolean not null,reason text not null check(length(trim(reason)) between 1 and 1000),
 basis text not null default 'last_authoritative_positive_average' check(basis='last_authoritative_positive_average'),
 cover_order text not null default 'issue_ledger_fifo' check(cover_order='issue_ledger_fifo'),
 tracking_scope text not null default 'untracked' check(tracking_scope='untracked'),
 command_id uuid not null,request_id uuid not null,created_by uuid not null references auth.users(id),created_at timestamptz not null default clock_timestamp(),
 unique(tenant_id,id),unique(tenant_id,legal_entity_id,version),
 foreign key(tenant_id,legal_entity_id) references core.legal_entities(tenant_id,id),
 foreign key(tenant_id,branch_id) references core.branches(tenant_id,id)
);
create table inventory.negative_stock_cost_bases (
 id bigint generated always as identity primary key,tenant_id uuid not null,legal_entity_id uuid not null,branch_id uuid not null,
 warehouse_id uuid not null,product_id uuid not null,balance_id uuid not null,balance_version bigint not null,valuation_version bigint not null,
 positive_quantity numeric(20,6) not null check(positive_quantity>0),carrying_value numeric(20,6) not null check(carrying_value>=0),
 source_context jsonb not null,created_by uuid not null references auth.users(id),created_at timestamptz not null default clock_timestamp(),
 unique(tenant_id,id),unique(tenant_id,balance_id,balance_version,valuation_version),
 foreign key(tenant_id,balance_id) references inventory.stock_balances(tenant_id,id),
 foreign key(tenant_id,warehouse_id) references core.warehouses(tenant_id,id),
 foreign key(tenant_id,legal_entity_id,product_id) references inventory.products(tenant_id,legal_entity_id,id)
);
create table inventory.negative_stock_overrides (
 id bigint generated always as identity primary key,tenant_id uuid not null,legal_entity_id uuid not null,branch_id uuid not null,
 warehouse_id uuid not null,product_id uuid not null,balance_id uuid not null,policy_id uuid,
 effect text not null check(effect in('reserve','issue','receipt_cover','customer_return')),
 source_id uuid not null,source_line_id uuid not null,command_id uuid not null,request_id uuid not null,
 quantity numeric(20,6) not null check(quantity>0),reason text not null check(length(trim(reason)) between 1 and 1000),
 old_quantity numeric(20,6) not null,new_quantity numeric(20,6) not null,old_allocated numeric(20,6) not null,new_allocated numeric(20,6) not null,
 old_value numeric(20,6) not null,new_value numeric(20,6) not null,transaction_id bigint not null default txid_current(),
 created_by uuid not null references auth.users(id),created_at timestamptz not null default clock_timestamp(),
 unique(tenant_id,id),
 foreign key(tenant_id,policy_id) references inventory.negative_stock_policy_versions(tenant_id,id),
 foreign key(tenant_id,balance_id) references inventory.stock_balances(tenant_id,id),
 foreign key(tenant_id,warehouse_id) references core.warehouses(tenant_id,id),
 foreign key(tenant_id,legal_entity_id,product_id) references inventory.products(tenant_id,legal_entity_id,id)
);
create index negative_stock_override_projection on inventory.negative_stock_overrides(transaction_id,balance_id,created_by);
create table inventory.negative_stock_deficits (
 id bigint generated always as identity primary key,tenant_id uuid not null,legal_entity_id uuid not null,branch_id uuid not null,
 warehouse_id uuid not null,product_id uuid not null,issue_movement_line_id uuid not null,policy_id uuid not null,basis_id bigint not null,
 override_id bigint not null,quantity numeric(20,6) not null check(quantity>0),provisional_value numeric(20,6) not null check(provisional_value>=0),
 inventory_account_id uuid not null,cogs_account_id uuid not null,posting_date date not null,
 command_id uuid not null,created_by uuid not null references auth.users(id),created_at timestamptz not null default clock_timestamp(),
 unique(tenant_id,id),unique(tenant_id,issue_movement_line_id),
 foreign key(tenant_id,issue_movement_line_id) references inventory.stock_movement_lines(tenant_id,id) deferrable initially deferred,
 foreign key(tenant_id,policy_id) references inventory.negative_stock_policy_versions(tenant_id,id),
 foreign key(tenant_id,basis_id) references inventory.negative_stock_cost_bases(tenant_id,id),
 foreign key(tenant_id,override_id) references inventory.negative_stock_overrides(tenant_id,id),
 foreign key(tenant_id,legal_entity_id,inventory_account_id) references finance.accounts(tenant_id,legal_entity_id,id),
 foreign key(tenant_id,legal_entity_id,cogs_account_id) references finance.accounts(tenant_id,legal_entity_id,id),
 foreign key(tenant_id,warehouse_id) references core.warehouses(tenant_id,id),
 foreign key(tenant_id,legal_entity_id,product_id) references inventory.products(tenant_id,legal_entity_id,id)
);
create index negative_stock_deficit_stream on inventory.negative_stock_deficits(tenant_id,warehouse_id,product_id,id);
create table inventory.negative_stock_covers (
 id bigint generated always as identity primary key,tenant_id uuid not null,legal_entity_id uuid not null,branch_id uuid not null,
 deficit_id bigint not null,movement_line_id uuid not null,kind text not null check(kind in('receipt','customer_return')),
 quantity numeric(20,6) not null check(quantity>0),provisional_value numeric(20,6) not null check(provisional_value>=0),
 actual_value numeric(20,6) not null check(actual_value>=0),variance numeric(20,6) not null,
 journal_entry_id uuid,posting_date date not null,command_id uuid not null,request_id uuid not null,
 created_by uuid not null references auth.users(id),created_at timestamptz not null default clock_timestamp(),
 unique(tenant_id,id),unique(tenant_id,deficit_id,movement_line_id),
 foreign key(tenant_id,deficit_id) references inventory.negative_stock_deficits(tenant_id,id),
 foreign key(tenant_id,movement_line_id) references inventory.stock_movement_lines(tenant_id,id) deferrable initially deferred,
 foreign key(tenant_id,journal_entry_id) references finance.journal_entries(tenant_id,id),
 check(variance=actual_value-provisional_value),check((variance=0)=(journal_entry_id is null))
);
create index negative_stock_cover_deficit on inventory.negative_stock_covers(tenant_id,deficit_id,id);
create index negative_stock_cover_movement on inventory.negative_stock_covers(tenant_id,movement_line_id,id);
create table inventory.negative_stock_return_allocations (
 id bigint generated always as identity primary key,tenant_id uuid not null,legal_entity_id uuid not null,branch_id uuid not null,
 original_movement_line_id uuid not null,return_movement_line_id uuid not null,segment_key text not null,
 deficit_id bigint,cover_id bigint,quantity numeric(20,6) not null check(quantity>0),value numeric(20,6) not null check(value>=0),
 command_id uuid not null,created_by uuid not null references auth.users(id),created_at timestamptz not null default clock_timestamp(),
 unique(tenant_id,id),unique(tenant_id,return_movement_line_id,segment_key),
 foreign key(tenant_id,original_movement_line_id) references inventory.stock_movement_lines(tenant_id,id),
 foreign key(tenant_id,return_movement_line_id) references inventory.stock_movement_lines(tenant_id,id) deferrable initially deferred,
 foreign key(tenant_id,deficit_id) references inventory.negative_stock_deficits(tenant_id,id),
 foreign key(tenant_id,cover_id) references inventory.negative_stock_covers(tenant_id,id)
);

do $$declare tbl text;fk record;begin
 foreach tbl in array array['negative_stock_policy_versions','negative_stock_cost_bases','negative_stock_overrides','negative_stock_deficits','negative_stock_covers','negative_stock_return_allocations'] loop
  execute format('alter table inventory.%I enable row level security',tbl);
  execute format('alter table inventory.%I force row level security',tbl);
  execute format('revoke all on inventory.%I from public,anon,authenticated',tbl);
  execute format('create trigger immutable before update or delete on inventory.%I for each row execute function workflow.reject_history_mutation()',tbl);
  for fk in select conname,(select string_agg(quote_ident(a.attname),',' order by k.n) from unnest(c.conkey) with ordinality k(num,n)
   join pg_attribute a on a.attrelid=c.conrelid and a.attnum=k.num) cols from pg_constraint c where c.conrelid=format('inventory.%I',tbl)::regclass and c.contype='f' loop
   execute format('create index %I on inventory.%I(%s)',left(tbl,20)||'_'||md5(fk.conname),tbl,fk.cols);
  end loop;
 end loop;
end $$;

create function inventory.negative_stock_policy_entity(p inventory.negative_stock_policy_versions) returns jsonb
language sql stable set search_path='' as $$select jsonb_build_object('id',p.id,'tenant_id',p.tenant_id,'legal_entity_id',p.legal_entity_id,'policy_version',coalesce(p.version,0)::text,'active',coalesce(p.active,false),
 'basis',coalesce(p.basis,'last_authoritative_positive_average'),'cover_order',coalesce(p.cover_order,'issue_ledger_fifo'),
 'tracking_scope',coalesce(p.tracking_scope,'untracked'),'reason',p.reason,'created_by',p.created_by,'created_at',p.created_at)$$;
create function api.negative_stock_policy(p_tenant_id uuid,p_legal_entity_id uuid,p_branch_id uuid) returns jsonb
language plpgsql stable security definer set search_path='' as $$declare p inventory.negative_stock_policy_versions%rowtype;begin
 perform core.wave3_require_scope(p_tenant_id,'inventory.stock.view',p_legal_entity_id,p_branch_id);
 if p_legal_entity_id is null or p_branch_id is null then raise exception using errcode='42501',message='OPERATIONAL_SCOPE_REQUIRED';end if;
 select * into p from inventory.negative_stock_policy_versions where tenant_id=p_tenant_id and legal_entity_id=p_legal_entity_id order by version desc limit 1;
 return inventory.negative_stock_policy_entity(p)||jsonb_build_object('tenant_id',p_tenant_id,'legal_entity_id',p_legal_entity_id);
end $$;
create function api.configure_negative_stock_policy(p_tenant_id uuid,p_legal_entity_id uuid,p_branch_id uuid,p_command_id uuid,
 p_idempotency_key uuid,p_client_timestamp timestamptz,p_payload jsonb,p_expected_entity_version bigint default null) returns jsonb
language plpgsql security definer set search_path='' as $$
declare h text;r jsonb;p inventory.negative_stock_policy_versions%rowtype;before_doc jsonb;after_doc jsonb;req uuid:=gen_random_uuid();v bigint;begin
 perform core.wave3_require_scope(p_tenant_id,'inventory.stock.policy.manage',p_legal_entity_id,p_branch_id);
 -- A branch-only assignment cannot change the policy of every entity branch.
 perform core.require_permission(p_tenant_id,'inventory.stock.policy.manage',p_legal_entity_id,null);
 if p_legal_entity_id is null or p_branch_id is null then raise exception using errcode='42501',message='OPERATIONAL_SCOPE_REQUIRED';end if;
 if p_client_timestamp is null or jsonb_typeof(p_payload->'active') is distinct from 'boolean' or coalesce(length(trim(p_payload->>'reason')),0) not between 1 and 1000 then
  raise exception using errcode='22023',message='NEGATIVE_STOCK_POLICY_INPUT_INVALID';end if;
 h:=core.wave3_request_hash('inventory.stock.policy.configure',p_command_id,p_tenant_id,p_legal_entity_id,p_branch_id,p_payload,p_expected_entity_version);
 r:=core.wave3_replay(p_tenant_id,'inventory.stock.policy.configure',p_command_id,p_idempotency_key,h);if r is not null then return r;end if;
 perform pg_advisory_xact_lock(hashtextextended('negative-policy:'||p_tenant_id::text||':'||p_legal_entity_id::text,0));
 select * into p from inventory.negative_stock_policy_versions where tenant_id=p_tenant_id and legal_entity_id=p_legal_entity_id order by version desc limit 1;
 v:=coalesce(p.version,0);before_doc:=inventory.negative_stock_policy_entity(p)||jsonb_build_object('tenant_id',p_tenant_id,'legal_entity_id',p_legal_entity_id);
 perform core.wave3_assert_expected_version(v,p_expected_entity_version,before_doc);
 if v=9223372036854775807 then raise exception using errcode='55000',message='NEGATIVE_STOCK_POLICY_VERSION_EXHAUSTED';end if;
 insert into inventory.negative_stock_policy_versions(id,tenant_id,legal_entity_id,branch_id,version,active,reason,command_id,request_id,created_by)
 values(p_command_id,p_tenant_id,p_legal_entity_id,p_branch_id,v+1,(p_payload->>'active')::boolean,trim(p_payload->>'reason'),p_command_id,req,auth.uid()) returning * into p;
 after_doc:=inventory.negative_stock_policy_entity(p);
 return core.wave3_finish_command(p_tenant_id,'inventory.stock.policy.configure',p_command_id,'negative_stock_policy',p.id,p_idempotency_key,h,before_doc,after_doc,
  p_legal_entity_id,p_branch_id,'{}',jsonb_build_object(
   'from_status',case when before_doc->>'active'=after_doc->>'active' then null when (before_doc->>'active')::boolean then 'active' else 'inactive' end,
   'to_status',case when p.active then 'active' else 'inactive' end,'reason',p.reason,'owner_id',auth.uid()),
  jsonb_build_array(jsonb_build_object('topic','inventory.stock.policy.configured','payload',after_doc)),'[]',req,req);
end $$;
create function inventory.require_negative_stock_policy(t uuid,e uuid,b uuid,p jsonb) returns inventory.negative_stock_policy_versions
language plpgsql security definer set search_path='' as $$declare policy inventory.negative_stock_policy_versions%rowtype;begin
 perform core.wave3_require_scope(t,'inventory.stock.override',e,b);
 if jsonb_typeof(p) is distinct from 'object' or jsonb_typeof(p->'policy_version') is distinct from 'string'
  or (p->>'policy_version')!~'^[1-9][0-9]{0,18}$' or coalesce(length(trim(p->>'reason')),0) not between 1 and 1000 then
  raise exception using errcode='22023',message='NEGATIVE_STOCK_OVERRIDE_INPUT_INVALID';end if;
 if (p->>'policy_version')::numeric>9223372036854775807 then raise exception using errcode='22023',message='NEGATIVE_STOCK_OVERRIDE_INPUT_INVALID';end if;
 perform pg_advisory_xact_lock(hashtextextended('negative-policy:'||t::text||':'||e::text,0));
 select * into policy from inventory.negative_stock_policy_versions where tenant_id=t and legal_entity_id=e order by version desc limit 1;
 if not found or not policy.active then raise exception using errcode='55000',message='NEGATIVE_STOCK_POLICY_INACTIVE';end if;
 if policy.version<>(p->>'policy_version')::bigint then raise exception using errcode='40001',message='NEGATIVE_STOCK_POLICY_VERSION_CONFLICT';end if;
 return policy;
end $$;
create function inventory.capture_negative_stock_basis(t uuid,e uuid,b uuid,w uuid,pr uuid,p_source jsonb) returns inventory.negative_stock_cost_bases
language plpgsql security definer set search_path='' as $$
declare bal inventory.stock_balances%rowtype;val inventory.stock_valuations%rowtype;basis inventory.negative_stock_cost_bases%rowtype;begin
 perform pg_advisory_xact_lock(hashtextextended(t::text||':'||w::text||':'||pr::text,0));
 select * into bal from inventory.stock_balances where tenant_id=t and legal_entity_id=e and branch_id=b and warehouse_id=w and product_id=pr for update;
 if not found then raise exception using errcode='55000',message='STOCK_BALANCE_UNAVAILABLE';end if;
 select * into val from inventory.stock_valuations where tenant_id=t and stock_balance_id=bal.id for update;
 if not found then raise exception using errcode='55000',message='INVENTORY_COST_UNAVAILABLE';end if;
 if bal.on_hand_quantity>0 and val.carrying_value>=0 then
  insert into inventory.negative_stock_cost_bases(tenant_id,legal_entity_id,branch_id,warehouse_id,product_id,balance_id,balance_version,valuation_version,
   positive_quantity,carrying_value,source_context,created_by)
  values(t,e,b,w,pr,bal.id,bal.version,val.version,bal.on_hand_quantity,val.carrying_value,p_source,auth.uid())
  on conflict(tenant_id,balance_id,balance_version,valuation_version) do nothing;
 end if;
 select * into basis from inventory.negative_stock_cost_bases where tenant_id=t and legal_entity_id=e and branch_id=b and warehouse_id=w and product_id=pr order by id desc limit 1;
 if not found then raise exception using errcode='55000',message='NEGATIVE_STOCK_COST_BASIS_UNKNOWN';end if;
 return basis;
end $$;
create function inventory.authorize_negative_stock_projection(bal inventory.stock_balances,val inventory.stock_valuations,policy uuid,effect text,
 source uuid,line_id uuid,cmd uuid,req uuid,q numeric,reason text,new_q numeric,new_alloc numeric,new_val numeric) returns bigint
language plpgsql security definer set search_path='' as $$declare result bigint;begin
 insert into inventory.negative_stock_overrides(tenant_id,legal_entity_id,branch_id,warehouse_id,product_id,balance_id,policy_id,effect,source_id,source_line_id,
  command_id,request_id,quantity,reason,old_quantity,new_quantity,old_allocated,new_allocated,old_value,new_value,created_by)
 values(bal.tenant_id,bal.legal_entity_id,bal.branch_id,bal.warehouse_id,bal.product_id,bal.id,policy,effect,source,line_id,cmd,req,q,reason,
  bal.on_hand_quantity,new_q,bal.allocated_quantity,new_alloc,val.carrying_value,new_val,auth.uid()) returning id into result;
 return result;
end $$;

-- Signed projections are accepted only for explicit server authorization or an
-- existing deficit whose quantity/allocation improves. Direct API writes stay revoked.
alter table inventory.stock_balances drop constraint stock_balances_on_hand_quantity_check;
alter table inventory.stock_balances drop constraint stock_balances_check;
alter table inventory.stock_valuations drop constraint stock_valuations_carrying_value_check;
create function inventory.guard_negative_stock_balance() returns trigger language plpgsql security definer set search_path='' as $$
declare val inventory.stock_valuations%rowtype;begin
 -- Existing posting paths lock the stock stream and decrease quantity before
 -- valuation. Retain the OLD aligned positive snapshot before either changes.
 if tg_op='UPDATE' and old.on_hand_quantity>0 and new.on_hand_quantity<old.on_hand_quantity and auth.uid() is not null
  and exists(select 1 from inventory.products p where p.tenant_id=old.tenant_id and p.id=old.product_id and p.tracking_mode='none') then
  perform pg_advisory_xact_lock(hashtextextended(old.tenant_id::text||':'||old.warehouse_id::text||':'||old.product_id::text,0));
  select * into val from inventory.stock_valuations where tenant_id=old.tenant_id and stock_balance_id=old.id for update;
  if found and val.carrying_value>=0 then
   insert into inventory.negative_stock_cost_bases(tenant_id,legal_entity_id,branch_id,warehouse_id,product_id,balance_id,balance_version,valuation_version,
    positive_quantity,carrying_value,source_context,created_by)
   values(old.tenant_id,old.legal_entity_id,old.branch_id,old.warehouse_id,old.product_id,old.id,old.version,val.version,old.on_hand_quantity,val.carrying_value,
    jsonb_build_object('snapshot_stage','before_positive_quantity_decrease','balance_source_context',old.source_context),auth.uid())
   on conflict(tenant_id,balance_id,balance_version,valuation_version) do nothing;
  end if;
 end if;
 if new.on_hand_quantity<0 or new.allocated_quantity>new.on_hand_quantity then
  if tg_op='UPDATE' and new.on_hand_quantity>=old.on_hand_quantity and new.allocated_quantity<=old.allocated_quantity
   and (old.on_hand_quantity<0 or old.allocated_quantity>old.on_hand_quantity) then return new;end if;
  if tg_op='UPDATE' and old.on_hand_quantity>=0 and new.on_hand_quantity>=0 and old.allocated_quantity>old.on_hand_quantity
   and new.on_hand_quantity-old.on_hand_quantity=new.allocated_quantity-old.allocated_quantity and new.on_hand_quantity<=old.on_hand_quantity then return new;end if;
  if not exists(select 1 from inventory.negative_stock_overrides a where a.transaction_id=txid_current() and a.balance_id=new.id and a.created_by=auth.uid()
   and a.old_quantity=case when tg_op='UPDATE' then old.on_hand_quantity else 0 end and a.new_quantity=new.on_hand_quantity
   and a.old_allocated=case when tg_op='UPDATE' then old.allocated_quantity else 0 end and a.new_allocated=new.allocated_quantity) then
   raise exception using errcode='23514',message='NEGATIVE_STOCK_AUTHORIZATION_REQUIRED';end if;
 end if;return new;
end $$;
create trigger negative_stock_balance_guard before insert or update on inventory.stock_balances for each row execute function inventory.guard_negative_stock_balance();
create function inventory.guard_negative_stock_value() returns trigger language plpgsql security definer set search_path='' as $$begin
 if new.carrying_value<0 then
  if tg_op='UPDATE' and old.carrying_value<0 and new.carrying_value>=old.carrying_value then return new;end if;
  if not exists(select 1 from inventory.negative_stock_overrides a where a.transaction_id=txid_current() and a.balance_id=new.stock_balance_id and a.created_by=auth.uid()
   and a.old_value=case when tg_op='UPDATE' then old.carrying_value else 0 end and a.new_value=new.carrying_value) then
   raise exception using errcode='23514',message='NEGATIVE_STOCK_AUTHORIZATION_REQUIRED';end if;
 end if;return new;
end $$;
create trigger negative_stock_value_guard before insert or update on inventory.stock_valuations for each row execute function inventory.guard_negative_stock_value();

create function inventory.negative_stock_open_quantity(t uuid,d bigint) returns numeric language sql stable security definer set search_path='' as $$
 select x.quantity-coalesce((select sum(c.quantity) from inventory.negative_stock_covers c where c.tenant_id=t and c.deficit_id=x.id),0)
 from inventory.negative_stock_deficits x where x.tenant_id=t and x.id=d
$$;

-- Source-linked returns consume uncovered, covered, then original positive
-- portions. Each segment keeps its exact original numerator/denominator.
create function inventory.negative_stock_return_cost(original inventory.stock_movement_lines,return_id uuid,q numeric,mdate date,cmd uuid,req uuid) returns numeric
language plpgsql security definer set search_path='' as $$
declare d inventory.negative_stock_deficits%rowtype;c inventory.negative_stock_covers%rowtype;remaining numeric:=q;take numeric;prior numeric;amount numeric;
 result numeric:=0;open_q numeric;segment_q numeric;segment_v numeric;key text;begin
 select * into d from inventory.negative_stock_deficits where tenant_id=original.tenant_id and issue_movement_line_id=original.id;
 if not found then raise exception using errcode='55000',message='NEGATIVE_STOCK_RETURN_SOURCE_REQUIRED';end if;
 open_q:=inventory.negative_stock_open_quantity(d.tenant_id,d.id);take:=least(remaining,open_q);
 if take>0 then
  prior:=d.quantity-open_q;amount:=round(d.provisional_value*(prior+take)/d.quantity,6)-round(d.provisional_value*prior/d.quantity,6);
  insert into inventory.negative_stock_covers(tenant_id,legal_entity_id,branch_id,deficit_id,movement_line_id,kind,quantity,provisional_value,actual_value,variance,
   posting_date,command_id,request_id,created_by)
  values(d.tenant_id,d.legal_entity_id,d.branch_id,d.id,return_id,'customer_return',take,amount,amount,0,mdate,cmd,req,auth.uid());
  insert into inventory.negative_stock_return_allocations(tenant_id,legal_entity_id,branch_id,original_movement_line_id,return_movement_line_id,segment_key,
   deficit_id,quantity,value,command_id,created_by)
  values(d.tenant_id,d.legal_entity_id,d.branch_id,original.id,return_id,'uncovered:'||d.id,d.id,take,amount,cmd,auth.uid());
  result:=result+amount;remaining:=remaining-take;
 end if;
 for c in select * from inventory.negative_stock_covers where tenant_id=d.tenant_id and deficit_id=d.id and kind='receipt' order by id loop
  exit when remaining=0;
  select coalesce(sum(quantity),0) into prior from inventory.negative_stock_return_allocations where tenant_id=d.tenant_id and cover_id=c.id;
  take:=least(remaining,c.quantity-prior);if take<=0 then continue;end if;
  amount:=round(c.actual_value*(prior+take)/c.quantity,6)-round(c.actual_value*prior/c.quantity,6);
  insert into inventory.negative_stock_return_allocations(tenant_id,legal_entity_id,branch_id,original_movement_line_id,return_movement_line_id,segment_key,
   deficit_id,cover_id,quantity,value,command_id,created_by)
  values(d.tenant_id,d.legal_entity_id,d.branch_id,original.id,return_id,'covered:'||c.id,d.id,c.id,take,amount,cmd,auth.uid());
  result:=result+amount;remaining:=remaining-take;
 end loop;
 if remaining>0 then
  segment_q:=-original.base_quantity-d.quantity;segment_v:=-original.base_value-d.provisional_value;key:='positive:'||original.id;
  select coalesce(sum(quantity),0) into prior from inventory.negative_stock_return_allocations where tenant_id=d.tenant_id and original_movement_line_id=original.id and segment_key=key;
  take:=least(remaining,segment_q-prior);
  if take<=0 then raise exception using errcode='22023',message='SOURCE_QUANTITY_EXCEEDED';end if;
  amount:=round(segment_v*(prior+take)/segment_q,6)-round(segment_v*prior/segment_q,6);
  insert into inventory.negative_stock_return_allocations(tenant_id,legal_entity_id,branch_id,original_movement_line_id,return_movement_line_id,segment_key,
   quantity,value,command_id,created_by)
  values(d.tenant_id,d.legal_entity_id,d.branch_id,original.id,return_id,key,take,amount,cmd,auth.uid());
  result:=result+amount;remaining:=remaining-take;
 end if;
 if remaining<>0 then raise exception using errcode='22023',message='SOURCE_QUANTITY_EXCEEDED';end if;
 return result;
end $$;

create function inventory.negative_stock_provenance(line inventory.stock_movement_lines) returns boolean
language plpgsql security definer set search_path='' as $$
declare m inventory.stock_movements%rowtype;bal inventory.stock_balances%rowtype;val inventory.stock_valuations%rowtype;
 d inventory.negative_stock_deficits%rowtype;pos record;allocation record;entry record;basis inventory.negative_stock_cost_bases%rowtype;
 remaining numeric;prior numeric;take numeric;eid bigint;def_entry bigint;covered numeric:=0;actual numeric;provisional numeric;variance numeric;
 jid uuid;correction_id uuid;currency text;steps integer:=0;open_q numeric;all_open numeric;origin uuid;begin
 if line.lot_id is not null or cardinality(line.serial_ids)>0 then return false;end if;
 select * into m from inventory.stock_movements where tenant_id=line.tenant_id and id=line.stock_movement_id;
 select * into d from inventory.negative_stock_deficits where tenant_id=line.tenant_id and issue_movement_line_id=line.id;
 select coalesce(sum(inventory.negative_stock_open_quantity(x.tenant_id,x.id)),0) into all_open from inventory.negative_stock_deficits x
  where x.tenant_id=line.tenant_id and x.warehouse_id=line.warehouse_id and x.product_id=line.product_id;
 if d.id is null and all_open=0 and not exists(select 1 from inventory.negative_stock_return_allocations a where a.tenant_id=line.tenant_id and a.return_movement_line_id=line.id) then return false;end if;
 if m.source_type not in('delivery','goods_receipt','sales_return') then raise exception using errcode='55000',message='NEGATIVE_STOCK_OPERATION_REQUIRES_REVIEW';end if;
 perform pg_advisory_xact_lock(hashtextextended(line.tenant_id::text||':'||line.warehouse_id::text||':'||line.product_id::text,0));
 select * into bal from inventory.stock_balances where tenant_id=line.tenant_id and legal_entity_id=line.legal_entity_id and branch_id=line.branch_id
  and warehouse_id=line.warehouse_id and product_id=line.product_id for update;
 select * into val from inventory.stock_valuations where tenant_id=line.tenant_id and stock_balance_id=bal.id for update;
 if not exists(select 1 from inventory.receipt_provenance_pools p where p.tenant_id=line.tenant_id and p.warehouse_id=line.warehouse_id and p.product_id=line.product_id and p.lot_id is null and p.serial_id is null) then
  prior:=bal.on_hand_quantity-line.base_quantity;
  if prior<0 then raise exception using errcode='55000',message='PROVENANCE_BASELINE_INVALID';end if;
  insert into inventory.receipt_provenance_pools(tenant_id,warehouse_id,product_id,baseline_quantity) values(line.tenant_id,line.warehouse_id,line.product_id,prior);
  if prior>0 then insert into inventory.receipt_provenance_positions(tenant_id,warehouse_id,product_id,quantity) values(line.tenant_id,line.warehouse_id,line.product_id,prior);end if;
 end if;
 remaining:=abs(line.base_quantity);
 if line.base_quantity<0 then
  for pos in select * from inventory.receipt_provenance_positions p where p.tenant_id=line.tenant_id and p.warehouse_id=line.warehouse_id and p.product_id=line.product_id
   and p.lot_id is null and p.serial_id is null and p.quantity>0 order by p.id for update loop
   take:=least(remaining,pos.quantity);steps:=steps+1;if steps>1000 then raise exception using errcode='54000',message='PROVENANCE_MOVEMENT_LIMIT';end if;
   insert into inventory.receipt_provenance_entries(tenant_id,legal_entity_id,branch_id,movement_line_id,origin_line_id,warehouse_id,product_id,quantity)
   values(line.tenant_id,line.legal_entity_id,line.branch_id,line.id,pos.origin_line_id,line.warehouse_id,line.product_id,-take);
   update inventory.receipt_provenance_positions set quantity=quantity-take where id=pos.id;
   remaining:=remaining-take;exit when remaining=0;
  end loop;
  if remaining<>coalesce(d.quantity,0) then raise exception using errcode='55000',message='PROVENANCE_STOCK_MISMATCH';end if;
  if remaining>0 then
   insert into inventory.receipt_provenance_entries(tenant_id,legal_entity_id,branch_id,movement_line_id,warehouse_id,product_id,quantity)
   values(line.tenant_id,line.legal_entity_id,line.branch_id,line.id,line.warehouse_id,line.product_id,-remaining);
  end if;
 elsif m.source_type='goods_receipt' then
  select currency_code into currency from core.legal_entities where tenant_id=line.tenant_id and id=line.legal_entity_id;
  for d in select * from inventory.negative_stock_deficits x where x.tenant_id=line.tenant_id and x.warehouse_id=line.warehouse_id and x.product_id=line.product_id
   and inventory.negative_stock_open_quantity(x.tenant_id,x.id)>0 order by x.id loop
   if remaining=0 then exit;end if;steps:=steps+1;if steps>1000 then raise exception using errcode='54000',message='NEGATIVE_STOCK_COVER_LIMIT';end if;
   open_q:=inventory.negative_stock_open_quantity(d.tenant_id,d.id);take:=least(remaining,open_q);prior:=d.quantity-open_q;
   provisional:=round(d.provisional_value*(prior+take)/d.quantity,6)-round(d.provisional_value*prior/d.quantity,6);
   actual:=round(line.base_value*(covered+take)/line.base_quantity,6)-round(line.base_value*covered/line.base_quantity,6);
   variance:=actual-provisional;jid:=null;
   if variance<>0 then
    correction_id:=md5('negative-cover:'||line.id::text||':'||d.id::text)::uuid;
    jid:=finance.flow_post_journal(jsonb_build_object('tenant_id',line.tenant_id,'legal_entity_id',line.legal_entity_id,'branch_id',line.branch_id,
     'document_date',line.posting_date,'currency_code',currency,'base_currency_code',currency,'exchange_rate','1'),
     jsonb_build_array(finance.flow_jline(d.inventory_account_id,-variance,-variance,d.issue_movement_line_id),finance.flow_jline(d.cogs_account_id,variance,variance,d.issue_movement_line_id)),
     'negative_stock.cover',correction_id,m.request_id,m.command_id);
    perform inventory.authorize_negative_stock_projection(bal,val,d.policy_id,'receipt_cover',m.source_id,line.id,m.command_id,m.request_id,take,
     'Linked later-receipt variance',bal.on_hand_quantity,bal.allocated_quantity,val.carrying_value-variance);
    update inventory.stock_valuations set carrying_value=carrying_value-variance,updated_by=auth.uid() where id=val.id returning * into val;
   end if;
   insert into inventory.negative_stock_covers(tenant_id,legal_entity_id,branch_id,deficit_id,movement_line_id,kind,quantity,provisional_value,actual_value,variance,
    journal_entry_id,posting_date,command_id,request_id,created_by)
   values(line.tenant_id,line.legal_entity_id,line.branch_id,d.id,line.id,'receipt',take,provisional,actual,variance,jid,line.posting_date,m.command_id,m.request_id,auth.uid());
   select id into def_entry from inventory.receipt_provenance_entries where tenant_id=line.tenant_id and movement_line_id=d.issue_movement_line_id and origin_line_id is null order by id desc limit 1;
   if def_entry is null then raise exception using errcode='55000',message='NEGATIVE_STOCK_PROVENANCE_SOURCE_REQUIRED';end if;
   insert into inventory.receipt_provenance_entries(tenant_id,legal_entity_id,branch_id,movement_line_id,origin_line_id,restores_entry_id,warehouse_id,product_id,quantity)
   values(line.tenant_id,line.legal_entity_id,line.branch_id,line.id,line.id,def_entry,line.warehouse_id,line.product_id,take);
   covered:=covered+take;remaining:=remaining-take;
  end loop;
  if remaining>0 then
   insert into inventory.receipt_provenance_entries(tenant_id,legal_entity_id,branch_id,movement_line_id,origin_line_id,warehouse_id,product_id,quantity)
   values(line.tenant_id,line.legal_entity_id,line.branch_id,line.id,line.id,line.warehouse_id,line.product_id,remaining) returning id into eid;
   insert into inventory.receipt_provenance_positions(tenant_id,warehouse_id,product_id,origin_line_id,entry_id,quantity)
   values(line.tenant_id,line.warehouse_id,line.product_id,line.id,eid,remaining);
  end if;
 else
  for allocation in select * from inventory.negative_stock_return_allocations where tenant_id=line.tenant_id and return_movement_line_id=line.id order by id loop
   take:=allocation.quantity;origin:=null;def_entry:=null;
   if allocation.segment_key like 'uncovered:%' then
    select id into def_entry from inventory.receipt_provenance_entries where tenant_id=line.tenant_id and movement_line_id=allocation.original_movement_line_id and origin_line_id is null order by id desc limit 1;
   elsif allocation.cover_id is not null then
    select movement_line_id into origin from inventory.negative_stock_covers where tenant_id=line.tenant_id and id=allocation.cover_id;
   else
    -- The positive original portion uses its exact recorded cohort attribution.
    for entry in select e.*,-e.quantity-coalesce((select sum(r.quantity) from inventory.receipt_provenance_entries r where r.restores_entry_id=e.id),0) restorable
     from inventory.receipt_provenance_entries e where e.tenant_id=line.tenant_id and e.movement_line_id=allocation.original_movement_line_id and e.quantity<0
     and e.id<>(select id from inventory.receipt_provenance_entries where tenant_id=line.tenant_id and movement_line_id=allocation.original_movement_line_id and origin_line_id is null order by id desc limit 1)
     order by e.id loop
     prior:=least(take,entry.restorable);if prior<=0 then continue;end if;
     insert into inventory.receipt_provenance_entries(tenant_id,legal_entity_id,branch_id,movement_line_id,origin_line_id,restores_entry_id,warehouse_id,product_id,quantity)
     values(line.tenant_id,line.legal_entity_id,line.branch_id,line.id,entry.origin_line_id,entry.id,line.warehouse_id,line.product_id,prior) returning id into eid;
     insert into inventory.receipt_provenance_positions(tenant_id,warehouse_id,product_id,origin_line_id,entry_id,quantity)
     values(line.tenant_id,line.warehouse_id,line.product_id,entry.origin_line_id,eid,prior);
     take:=take-prior;exit when take=0;
    end loop;
    if take<>0 then raise exception using errcode='55000',message='PROVENANCE_RESTORE_EXCEEDS_SOURCE';end if;
    remaining:=remaining-allocation.quantity;continue;
   end if;
   insert into inventory.receipt_provenance_entries(tenant_id,legal_entity_id,branch_id,movement_line_id,origin_line_id,restores_entry_id,warehouse_id,product_id,quantity)
   values(line.tenant_id,line.legal_entity_id,line.branch_id,line.id,origin,def_entry,line.warehouse_id,line.product_id,take) returning id into eid;
   if allocation.cover_id is not null then
    insert into inventory.receipt_provenance_positions(tenant_id,warehouse_id,product_id,origin_line_id,entry_id,quantity)
    values(line.tenant_id,line.warehouse_id,line.product_id,origin,eid,take);
   end if;
   remaining:=remaining-allocation.quantity;
  end loop;
  if remaining<>0 then raise exception using errcode='55000',message='PROVENANCE_RESTORE_EXCEEDS_SOURCE';end if;
 end if;
 select coalesce(sum(p.quantity),0) into prior from inventory.receipt_provenance_positions p where p.tenant_id=line.tenant_id and p.warehouse_id=line.warehouse_id and p.product_id=line.product_id and p.lot_id is null and p.serial_id is null;
 select coalesce(sum(inventory.negative_stock_open_quantity(x.tenant_id,x.id)),0) into all_open from inventory.negative_stock_deficits x where x.tenant_id=line.tenant_id and x.warehouse_id=line.warehouse_id and x.product_id=line.product_id;
 if prior-all_open<>bal.on_hand_quantity then raise exception using errcode='55000',message='PROVENANCE_STOCK_MISMATCH';end if;
 if bal.on_hand_quantity>0 then perform inventory.capture_negative_stock_basis(line.tenant_id,line.legal_entity_id,line.branch_id,line.warehouse_id,line.product_id,jsonb_build_object('movement_line_id',line.id));end if;
 return true;
end $$;

-- GENERATED ADDITIVE SUPERSESSIONS: source boundaries asserted by dated composer.
-- Original helpers remain available internally with their original bodies.
alter function api.reserve_sales_order_stock(uuid,uuid,uuid,uuid,uuid,timestamptz,jsonb,bigint) rename to reserve_sales_order_stock_without_negative_policy;
revoke all on function api.reserve_sales_order_stock_without_negative_policy(uuid,uuid,uuid,uuid,uuid,timestamptz,jsonb,bigint) from public,anon,authenticated;
create function api.reserve_sales_order_stock(
  p_tenant_id uuid,
  p_legal_entity_id uuid,
  p_branch_id uuid,
  p_command_id uuid,
  p_idempotency_key uuid,
  p_client_timestamp timestamptz,
  p_payload jsonb,
  p_expected_entity_version bigint default null
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_actor uuid := (select auth.uid());
  v_command_name constant text := 'inventory.sales_order.reserve';
  v_request_hash text;
  v_replay jsonb;
  v_order_id uuid := (p_payload->>'sales_order_id')::uuid;
  v_order sales.sales_orders%rowtype;
  v_line sales.sales_order_lines%rowtype;
  v_balance inventory.stock_balances%rowtype;
  v_reservation inventory.stock_reservations%rowtype;
  v_item jsonb;
  v_ordinal integer;
  v_requested numeric(20, 6);
  v_remaining numeric(20, 6);
  v_available numeric(20, 6);
  v_allocate numeric(20, 6);
  v_shortfall boolean := false;
  v_before jsonb;
  v_entity jsonb;
  v_request_id uuid := gen_random_uuid();
  v_source_context jsonb := coalesce(p_payload->'source_context', '{}'::jsonb);
  v_to_status text;
  v_policy inventory.negative_stock_policy_versions%rowtype;
  v_basis inventory.negative_stock_cost_bases%rowtype;
  v_val inventory.stock_valuations%rowtype;
  v_tracking text;
  v_has_override boolean := coalesce(p_payload ? 'negative_stock_override',false);
  v_used_override boolean := false;
  v_warnings jsonb := '[]'::jsonb;
begin
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
  perform core.wave3_require_scope(
    p_tenant_id, 'inventory.reservations.manage', p_legal_entity_id, p_branch_id
  );
  if p_branch_id is null or p_client_timestamp is null
     or jsonb_typeof(p_payload->'lines') <> 'array'
     or jsonb_array_length(p_payload->'lines') not between 1 and 500
     or (p_payload->>'expires_at')::timestamptz <= greatest(clock_timestamp(), p_client_timestamp)
     or jsonb_typeof(v_source_context) <> 'object' then
    raise exception using errcode = '22023', message = 'Stock reservation payload is invalid.';
  end if;
  v_request_hash := core.wave3_request_hash(
    v_command_name, p_command_id, p_tenant_id, p_legal_entity_id,
    p_branch_id, p_payload, p_expected_entity_version
  );
  v_replay := core.wave3_replay(
    p_tenant_id, v_command_name, p_command_id, p_idempotency_key, v_request_hash
  );
  if v_replay is not null then return v_replay; end if;
  select o.* into v_order
  from sales.sales_orders as o
  where o.tenant_id = p_tenant_id and o.legal_entity_id = p_legal_entity_id
    and o.branch_id = p_branch_id and o.id = v_order_id
  for update;
  if not found then
    raise exception using errcode = 'P0002', message = 'Sales order was not found.';
  end if;
  v_before := sales.order_entity(v_order_id);
  perform core.wave3_assert_expected_version(
    v_order.version, p_expected_entity_version, v_before
  );
  if v_order.status not in ('confirmed', 'partially_reserved', 'reserved') then
    raise exception using errcode = '55000', message = 'SALES_ORDER_NOT_RESERVABLE';
  end if;

  if not exists (
    select 1 from core.warehouses w
    where w.tenant_id = p_tenant_id and w.legal_entity_id = p_legal_entity_id
      and w.branch_id = p_branch_id and w.id = v_order.warehouse_id
      and w.status = 'active'
  ) then
    raise exception using errcode = '55000', message = 'WAREHOUSE_INACTIVE';
  end if;

  -- Deterministic product locks serialize competing reservations without
  -- creating an inventory movement or changing on-hand quantity.
  for v_line in
    select distinct on (l.product_id) l.*
    from jsonb_array_elements(p_payload->'lines') as item
    join sales.sales_order_lines as l
      on l.id = (item->>'sales_order_line_id')::uuid
    where l.tenant_id = p_tenant_id and l.sales_order_id = v_order_id
    order by l.product_id, l.id
  loop
    perform pg_catalog.pg_advisory_xact_lock(
      pg_catalog.hashtextextended(
        p_tenant_id::text || ':' || v_order.warehouse_id::text || ':' || v_line.product_id::text,
        0
      )
    );
  end loop;

  for v_item, v_ordinal in
    select value, ordinality::integer
    from jsonb_array_elements(p_payload->'lines') with ordinality
  loop
    select l.* into v_line
    from sales.sales_order_lines as l
    where l.tenant_id = p_tenant_id and l.sales_order_id = v_order_id
      and l.id = (v_item->>'sales_order_line_id')::uuid
    for update;
    if not found then
      raise exception using errcode = '22023', message = 'Sales-order line is outside scope.';
    end if;
    if v_line.product_kind <> 'stocked' then
      raise exception using errcode = '22023', message = 'Only stocked products can be reserved.';
    end if;
    if not exists (
      select 1 from inventory.products p
      where p.tenant_id = p_tenant_id and p.legal_entity_id = p_legal_entity_id
        and p.id = v_line.product_id and p.kind = 'stocked' and p.status = 'active'
    ) then
      raise exception using errcode = '55000', message = 'PRODUCT_NOT_RESERVABLE';
    end if;
    v_requested := sales.wave3_decimal_string(
      v_item->'requested_base_quantity', 'Requested base quantity', 6, true, 0, null
    )::numeric(20, 6);
    if v_requested <= 0 then
      raise exception using errcode = '22023', message = 'Requested quantity must be positive.';
    end if;
    select b.* into v_balance
    from inventory.stock_balances as b
    where b.tenant_id = p_tenant_id and b.legal_entity_id = p_legal_entity_id
      and b.branch_id = p_branch_id and b.warehouse_id = v_order.warehouse_id
      and b.product_id = v_line.product_id
    for update;
    v_remaining := greatest(
      v_line.base_ordered_quantity - v_line.cancelled_quantity
        - v_line.allocated_quantity - v_line.delivered_quantity,
      0
    )::numeric(20, 6);
    v_available := case when v_balance.id is null then 0
      else greatest(v_balance.available_quantity, 0) end::numeric(20, 6);
    if v_has_override and least(v_requested,v_remaining)>v_available then
      select tracking_mode into v_tracking from inventory.products where tenant_id=p_tenant_id and legal_entity_id=p_legal_entity_id and id=v_line.product_id;
      if v_tracking<>'none' then raise exception using errcode='55000',message='NEGATIVE_STOCK_TRACKING_REQUIRED';end if;
      v_basis := inventory.capture_negative_stock_basis(p_tenant_id,p_legal_entity_id,p_branch_id,v_order.warehouse_id,v_line.product_id,
        jsonb_build_object('sales_order_id',v_order_id,'sales_order_line_id',v_line.id,'command_id',p_command_id));
      v_available := v_remaining;
    end if;
    v_allocate := least(v_requested, v_remaining, v_available)::numeric(20, 6);
    if v_allocate < v_requested then v_shortfall := true; end if;
    if v_allocate > 0 then
      select r.* into v_reservation
      from inventory.stock_reservations as r
      where r.tenant_id = p_tenant_id and r.warehouse_id = v_order.warehouse_id
        and r.sales_order_line_id = v_line.id and r.status = 'active'
      for update;
      if found then
        update inventory.stock_reservations set
          base_quantity = base_quantity + v_allocate,
          expires_at = greatest(expires_at, (p_payload->>'expires_at')::timestamptz),
          request_id = v_request_id, command_id = p_command_id,
          correlation_id = v_request_id, source_context = v_source_context,
          updated_by = v_actor
        where id = v_reservation.id;
      else
        insert into inventory.stock_reservations (
          id, tenant_id, legal_entity_id, branch_id, warehouse_id, product_id,
          sales_order_id, sales_order_line_id, base_quantity, status,
          expires_at, request_id, command_id, correlation_id, source_context,
          created_by, updated_by
        ) values (
          core.wave2_derived_uuid(p_command_id, v_ordinal),
          p_tenant_id, p_legal_entity_id, p_branch_id, v_order.warehouse_id,
          v_line.product_id, v_order_id, v_line.id, v_allocate, 'active',
          (p_payload->>'expires_at')::timestamptz,
          v_request_id, p_command_id, v_request_id, v_source_context,
          v_actor, v_actor
        );
      end if;
      if v_balance.allocated_quantity+v_allocate>v_balance.on_hand_quantity then
        select * into v_val from inventory.stock_valuations where tenant_id=p_tenant_id and stock_balance_id=v_balance.id for update;
        perform inventory.authorize_negative_stock_projection(v_balance,v_val,v_policy.id,'reserve',v_order_id,v_line.id,p_command_id,v_request_id,
          v_allocate,trim(p_payload#>>'{negative_stock_override,reason}'),v_balance.on_hand_quantity,v_balance.allocated_quantity+v_allocate,v_val.carrying_value);
        v_used_override := true;
      end if;
      update inventory.stock_balances set
        allocated_quantity = allocated_quantity + v_allocate,
        updated_by = v_actor, source_context = v_source_context
      where id = v_balance.id;
      update sales.sales_order_lines set
        allocated_quantity = allocated_quantity + v_allocate,
        request_id = v_request_id, command_id = p_command_id,
        correlation_id = v_request_id, source_context = v_source_context,
        updated_by = v_actor
      where id = v_line.id;
    end if;
  end loop;
  if exists (
    select 1 from sales.sales_order_lines as l
    where l.tenant_id = p_tenant_id and l.sales_order_id = v_order_id
      and l.product_kind = 'stocked'
      and l.base_ordered_quantity - l.cancelled_quantity - l.allocated_quantity - l.delivered_quantity > 0
  ) then
    v_to_status := 'partially_reserved';
  else
    v_to_status := 'reserved';
  end if;
  if v_shortfall then
    v_warnings := jsonb_build_array('PARTIAL_STOCK_RESERVATION');
  end if;
  if v_used_override then v_warnings := v_warnings || jsonb_build_array('NEGATIVE_STOCK_OVERRIDDEN'); end if;
  update sales.sales_orders set
    status = v_to_status, request_id = v_request_id, command_id = p_command_id,
    correlation_id = v_request_id, source_context = v_source_context,
    client_timestamp = p_client_timestamp, updated_by = v_actor
  where id = v_order_id;
  v_entity := sales.order_entity(v_order_id);
  return core.wave3_finish_command(
    p_tenant_id, v_command_name, p_command_id, 'sales_order', v_order_id,
    p_idempotency_key, v_request_hash, v_before, v_entity,
    p_legal_entity_id, p_branch_id, v_source_context,
    jsonb_build_object(
      'from_status', case when v_order.status=v_to_status then null else v_order.status end, 'to_status', v_to_status,
      'owner_id', v_order.salesperson_id
    ),
    jsonb_build_array(jsonb_build_object(
      'topic', v_command_name,
      'payload', jsonb_build_object('status', v_to_status)
    )), v_warnings, v_request_id, v_request_id
  );
end;
$$;
alter function sales.flow_post_stock(text,jsonb,uuid,uuid) rename to flow_post_stock_without_negative_policy;
revoke all on function sales.flow_post_stock_without_negative_policy(text,jsonb,uuid,uuid) from public,anon,authenticated;
create function sales.flow_post_stock(p_kind text,p_doc jsonb,p_request uuid,p_command uuid)
returns jsonb language plpgsql security definer set search_path='' as $$
declare v_t uuid:=(p_doc->>'tenant_id')::uuid;v_e uuid:=(p_doc->>'legal_entity_id')::uuid;
 v_b uuid:=(p_doc->>'branch_id')::uuid;v_date date:=(p_doc->>'document_date')::date;v_id uuid:=(p_doc->>'id')::uuid;
 v_movement uuid;v_line jsonb;v_snapshot jsonb;v_product inventory.products%rowtype;v_order sales.sales_orders%rowtype;
 v_ol sales.sales_order_lines%rowtype;v_balance inventory.stock_balances%rowtype;v_value inventory.stock_valuations%rowtype;
 v_res inventory.stock_reservations%rowtype;v_original inventory.stock_movement_lines%rowtype;
 v_lot inventory.lots%rowtype;v_lb inventory.lot_balances%rowtype;v_serial inventory.serials%rowtype;
 v_serial_ids uuid[];v_serial_id uuid;v_warehouse uuid;v_lot_id uuid;v_q numeric;v_cost numeric;v_prior numeric;
 v_negative_policy inventory.negative_stock_policy_versions%rowtype;v_basis inventory.negative_stock_cost_bases%rowtype;
 v_deficit_quantity numeric;v_provisional numeric;v_override bigint;v_mline uuid;v_def inventory.negative_stock_deficits%rowtype;
 v_inventory uuid;v_cogs uuid;v_jlines jsonb:='[]';v_sign integer:=case when p_kind='delivery' then -1 else 1 end;
begin
 if p_kind='delivery' then perform pg_advisory_xact_lock(hashtextextended('negative-policy:'||v_t::text||':'||v_e::text,0));end if;
 -- Lock stock products with exactly the same advisory identity as reservations.
 for v_warehouse,v_serial_id in select distinct
 case when p_kind='delivery' then (p_doc->>'warehouse_id')::uuid else d.warehouse_id end, (x->>'product_id')::uuid
 from jsonb_array_elements(p_doc->'lines') x
 left join sales.delivery_lines dl on dl.tenant_id=v_t and dl.id=(x->>'delivery_line_id')::uuid
 left join sales.deliveries d on d.tenant_id=v_t and d.id=dl.document_id
 where x#>>'{snapshot,product_kind}'='stocked' order by 1,2 loop
 perform pg_advisory_xact_lock(hashtextextended(v_t::text||':'||v_warehouse::text||':'||v_serial_id::text,0));end loop;
 for v_line in select value from jsonb_array_elements(p_doc->'lines') loop
 v_snapshot:=v_line->'snapshot';v_q:=(v_line->>'base_quantity')::numeric;v_mline:=gen_random_uuid();v_deficit_quantity:=0;v_provisional:=0;
 if v_snapshot->>'product_kind'<>'stocked' then
 if p_kind='delivery' then update sales.sales_order_lines set delivered_quantity=delivered_quantity+v_q,updated_by=auth.uid()
 where tenant_id=v_t and id=(v_line->>'sales_order_line_id')::uuid;end if;continue;end if;
 if p_kind='sales_return' and v_snapshot->>'disposition'='no_restock' then continue;end if;
 select * into v_product from inventory.products where tenant_id=v_t and legal_entity_id=v_e and id=(v_line->>'product_id')::uuid;
 v_original:=null;v_lot:=null;v_lb:=null;v_def:=null;
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
 if v_balance.allocated_quantity<v_q then raise exception using errcode='55000',message='INSUFFICIENT_STOCK';end if;
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
 end if;
 if v_res.base_quantity=v_q then update inventory.stock_reservations set status='fulfilled',released_at=clock_timestamp(),release_reason='Delivery posted',updated_by=auth.uid() where id=v_res.id;
 else update inventory.stock_reservations set base_quantity=base_quantity-v_q,updated_by=auth.uid() where id=v_res.id;end if;
 update inventory.stock_balances set on_hand_quantity=on_hand_quantity-v_q,allocated_quantity=allocated_quantity-v_q,updated_by=auth.uid() where id=v_balance.id;
 update sales.sales_order_lines set allocated_quantity=allocated_quantity-v_q,delivered_quantity=delivered_quantity+v_q,updated_by=auth.uid() where id=v_ol.id;
 else
  select * into v_def from inventory.negative_stock_deficits where tenant_id=v_t and issue_movement_line_id=v_original.id;
  if found then
   v_cost:=inventory.negative_stock_return_cost(v_original,v_mline,v_q,v_date,p_command,p_request);
   perform inventory.authorize_negative_stock_projection(v_balance,v_value,v_def.policy_id,'customer_return',v_id,(v_line->>'id')::uuid,p_command,p_request,
    v_q,'Source-linked customer return',v_balance.on_hand_quantity+v_q,v_balance.allocated_quantity,v_value.carrying_value+v_cost);
  end if;
  update inventory.stock_balances set on_hand_quantity=on_hand_quantity+v_q,updated_by=auth.uid() where id=v_balance.id;end if;
 update inventory.stock_valuations set carrying_value=carrying_value+v_sign*v_cost,updated_by=auth.uid() where id=v_value.id;
 if v_lb.id is not null then update inventory.lot_balances set on_hand_quantity=on_hand_quantity+v_sign*v_q,updated_by=auth.uid() where id=v_lb.id;end if;
 if v_movement is null then
 v_movement:=gen_random_uuid();
 insert into inventory.stock_movements(id,tenant_id,legal_entity_id,branch_id,source_type,source_id,warehouse_id,posting_date,movement_kind,request_id,command_id,correlation_id,created_by)
 values(v_movement,v_t,v_e,v_b,p_kind,v_id,v_warehouse,v_date,p_kind,p_request,p_command,p_request,auth.uid());end if;
 insert into inventory.stock_movement_lines(id,tenant_id,legal_entity_id,branch_id,stock_movement_id,warehouse_id,product_id,
 source_line_id,original_movement_line_id,base_quantity,base_value,lot_id,serial_ids,posting_date,created_by)
 values(v_mline,v_t,v_e,v_b,v_movement,v_warehouse,v_product.id,(v_line->>'id')::uuid,v_original.id,v_sign*v_q,v_sign*v_cost,v_lot_id,v_serial_ids,v_date,auth.uid());
 if v_cost>0 then
 v_inventory:=v_product.inventory_account_id;
 v_cogs:=v_product.cogs_account_id;
 if p_kind='sales_return' then
 if v_def.id is not null then v_inventory:=v_def.inventory_account_id;v_cogs:=v_def.cogs_account_id;
 else
 select jl.account_id into v_inventory from finance.journal_lines jl join finance.journal_entries j on j.id=jl.journal_entry_id
 join finance.accounts a on a.id=jl.account_id where jl.tenant_id=v_t and jl.source_line_id=v_original.source_line_id
 and j.source_type='delivery.stock' and a.account_type='asset';
 select jl.account_id into v_cogs from finance.journal_lines jl join finance.journal_entries j on j.id=jl.journal_entry_id
 join finance.accounts a on a.id=jl.account_id where jl.tenant_id=v_t and jl.source_line_id=v_original.source_line_id
 and j.source_type='delivery.stock' and a.account_type='expense';
 end if;end if;
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
-- Trigger bindings resolve by OID. Reattach it to the additive dispatcher;
-- the renamed original trigger helper retains its byte-identical body.
alter function inventory.record_receipt_provenance() rename to record_receipt_provenance_without_negative_policy;
create function inventory.record_receipt_provenance() returns trigger language plpgsql security definer set search_path='' as $$
declare m inventory.stock_movements%rowtype; related uuid; sid uuid; ids uuid[]; q numeric; prior numeric; available numeric;
 remaining numeric; take numeric; eid bigint; origin uuid; pos record; entry record; v_source_type text; steps integer:=0;
begin
 if inventory.negative_stock_provenance(new) then return new;end if;
 if new.base_quantity=0 then return new;end if;
 perform pg_advisory_xact_lock(hashtextextended(new.tenant_id::text||':'||new.warehouse_id::text||':'||new.product_id::text,0));
 select * into strict m from inventory.stock_movements where tenant_id=new.tenant_id and id=new.stock_movement_id;
 related:=new.original_movement_line_id;
 if m.source_type in('transfer.receive','transfer.reverse.receipt','transfer.reverse.issue') then
  v_source_type:=case when m.source_type='transfer.receive' then 'transfer.dispatch'
   when m.source_type='transfer.reverse.issue' then 'transfer.receive'
   when exists(select 1 from inventory.stock_movements x where x.tenant_id=new.tenant_id and x.source_id=m.source_id and x.source_type='transfer.reverse.issue') then 'transfer.reverse.issue'
   else 'transfer.dispatch' end;
  select l.id into related from inventory.stock_movement_lines l join inventory.stock_movements x on x.id=l.stock_movement_id
   where x.tenant_id=new.tenant_id and x.source_id=m.source_id and x.source_type=v_source_type and l.source_line_id=new.source_line_id;
  if related is null then raise exception using errcode='55000',message='PROVENANCE_TRANSFER_SOURCE_MISSING';end if;
 end if;
 ids:=case when cardinality(new.serial_ids)>0 then new.serial_ids else array[null::uuid] end;
 if cardinality(new.serial_ids)>0 and abs(new.base_quantity)<>cardinality(new.serial_ids) then raise exception using errcode='55000',message='PROVENANCE_SERIAL_QUANTITY_MISMATCH';end if;
 foreach sid in array ids loop
  q:=case when sid is null then new.base_quantity else sign(new.base_quantity) end;
  if sid is not null and q>0 and m.source_type='stock_count' then
   -- A governed recount restores the same missing serial, not an invented receipt.
   select e.movement_line_id into related from inventory.receipt_provenance_entries e
    join inventory.stock_movement_lines ml on ml.id=e.movement_line_id join inventory.stock_movements sm on sm.id=ml.stock_movement_id
    where e.tenant_id=new.tenant_id and e.serial_id=sid and e.warehouse_id=new.warehouse_id and e.quantity<0 and sm.source_type='stock_count'
    and not exists(select 1 from inventory.receipt_provenance_entries r where r.restores_entry_id=e.id) order by e.id desc limit 1;
  end if;
  -- Transfer validates serial disposition after its ledger leg; preserve that public error.
  if sid is not null and m.source_type='transfer.dispatch' and not exists(select 1 from inventory.serials s
   where s.tenant_id=new.tenant_id and s.id=sid and s.warehouse_id=new.warehouse_id and s.status='available') then
   raise exception using errcode='55000',message='TRANSFER_SERIAL_UNAVAILABLE';end if;
  if not exists(select 1 from inventory.receipt_provenance_pools p where p.tenant_id=new.tenant_id and p.warehouse_id=new.warehouse_id and p.product_id=new.product_id
   and p.lot_id is not distinct from new.lot_id and p.serial_id is not distinct from sid) then
   if sid is not null then prior:=case when q<0 then 1 else 0 end;
   elsif new.lot_id is not null then
    select on_hand_quantity-q into prior from inventory.lot_balances where tenant_id=new.tenant_id and warehouse_id=new.warehouse_id and lot_id=new.lot_id;
   else
    select on_hand_quantity-q into prior from inventory.stock_balances where tenant_id=new.tenant_id and warehouse_id=new.warehouse_id and product_id=new.product_id;
    -- Untracked pool excludes independently tracked pools if legacy synthetic data mixed tracking modes.
    prior:=prior-coalesce((select sum(quantity) from inventory.receipt_provenance_positions p where p.tenant_id=new.tenant_id and p.warehouse_id=new.warehouse_id and p.product_id=new.product_id and (p.lot_id is not null or p.serial_id is not null)),0);
   end if;
   if prior is null or prior<0 then raise exception using errcode='55000',message='PROVENANCE_BASELINE_INVALID';end if;
   insert into inventory.receipt_provenance_pools(tenant_id,warehouse_id,product_id,lot_id,serial_id,baseline_quantity)
    values(new.tenant_id,new.warehouse_id,new.product_id,new.lot_id,sid,prior);
   if prior>0 then insert into inventory.receipt_provenance_positions(tenant_id,warehouse_id,product_id,lot_id,serial_id,quantity)
    values(new.tenant_id,new.warehouse_id,new.product_id,new.lot_id,sid,prior);end if;
  end if;
  remaining:=abs(q);
  if sid is not null then
   select coalesce(sum(p.quantity),0)+q into available from inventory.receipt_provenance_positions p
    where p.tenant_id=new.tenant_id and p.warehouse_id=new.warehouse_id and p.product_id=new.product_id and p.serial_id=sid;
   if available not in(0,1) then raise exception using errcode='55000',message='PROVENANCE_SERIAL_QUANTITY_MISMATCH';end if;
  end if;
  if sid is null then
   select coalesce(sum(p.quantity),0)+q into available from inventory.receipt_provenance_positions p
    where p.tenant_id=new.tenant_id and p.warehouse_id=new.warehouse_id and p.product_id=new.product_id
    and p.lot_id is not distinct from new.lot_id and p.serial_id is null;
   if new.lot_id is not null then
    select on_hand_quantity into prior from inventory.lot_balances where tenant_id=new.tenant_id and warehouse_id=new.warehouse_id and lot_id=new.lot_id;
   else
    select on_hand_quantity-coalesce((select sum(p.quantity) from inventory.receipt_provenance_positions p where p.tenant_id=new.tenant_id and p.warehouse_id=new.warehouse_id and p.product_id=new.product_id and (p.lot_id is not null or p.serial_id is not null)),0)
     into prior from inventory.stock_balances where tenant_id=new.tenant_id and warehouse_id=new.warehouse_id and product_id=new.product_id;
   end if;
   if available is distinct from prior then raise exception using errcode='55000',message='PROVENANCE_STOCK_MISMATCH';end if;
  end if;
  if q<0 then
   for pos in select * from inventory.receipt_provenance_positions p where p.tenant_id=new.tenant_id and p.warehouse_id=new.warehouse_id and p.product_id=new.product_id
    and p.lot_id is not distinct from new.lot_id and p.serial_id is not distinct from sid and p.quantity>0
    order by case when related is not null and (p.origin_line_id=related or p.entry_id in(select e.id from inventory.receipt_provenance_entries e where e.movement_line_id=related)) then 0 else 1 end,p.id for update loop
    take:=least(remaining,pos.quantity);
    steps:=steps+1;if steps>1000 then raise exception using errcode='54000',message='PROVENANCE_MOVEMENT_LIMIT';end if;
    insert into inventory.receipt_provenance_entries(tenant_id,legal_entity_id,branch_id,movement_line_id,origin_line_id,warehouse_id,product_id,lot_id,serial_id,quantity)
     values(new.tenant_id,new.legal_entity_id,new.branch_id,new.id,pos.origin_line_id,new.warehouse_id,new.product_id,new.lot_id,sid,-take);
    update inventory.receipt_provenance_positions set quantity=quantity-take where id=pos.id;
    remaining:=remaining-take;exit when remaining=0;
   end loop;
   if remaining<>0 then raise exception using errcode='55000',message='PROVENANCE_STOCK_MISMATCH';end if;
  else
   -- Returns and transfer receipts restore the exact recorded negative attribution.
   if related is not null then
    for entry in select e.*, -e.quantity-coalesce((select sum(r.quantity) from inventory.receipt_provenance_entries r where r.restores_entry_id=e.id),0) restorable
     from inventory.receipt_provenance_entries e where e.tenant_id=new.tenant_id and e.movement_line_id=related and e.quantity<0 and e.serial_id is not distinct from sid order by e.id loop
     take:=least(remaining,entry.restorable);if take<=0 then continue;end if;
     steps:=steps+1;if steps>1000 then raise exception using errcode='54000',message='PROVENANCE_MOVEMENT_LIMIT';end if;
     insert into inventory.receipt_provenance_entries(tenant_id,legal_entity_id,branch_id,movement_line_id,origin_line_id,restores_entry_id,warehouse_id,product_id,lot_id,serial_id,quantity)
      values(new.tenant_id,new.legal_entity_id,new.branch_id,new.id,entry.origin_line_id,entry.id,new.warehouse_id,new.product_id,new.lot_id,sid,take) returning id into eid;
     insert into inventory.receipt_provenance_positions(tenant_id,warehouse_id,product_id,lot_id,serial_id,origin_line_id,entry_id,quantity)
      values(new.tenant_id,new.warehouse_id,new.product_id,new.lot_id,sid,entry.origin_line_id,eid,take);
     remaining:=remaining-take;exit when remaining=0;
    end loop;
    if remaining<>0 and exists(select 1 from inventory.receipt_provenance_entries e where e.tenant_id=new.tenant_id and e.movement_line_id=related) then
     raise exception using errcode='55000',message='PROVENANCE_RESTORE_EXCEEDS_SOURCE';end if;
   end if;
   if remaining>0 then
    origin:=case when m.source_type='goods_receipt' then new.id end;
    insert into inventory.receipt_provenance_entries(tenant_id,legal_entity_id,branch_id,movement_line_id,origin_line_id,warehouse_id,product_id,lot_id,serial_id,quantity)
     values(new.tenant_id,new.legal_entity_id,new.branch_id,new.id,origin,new.warehouse_id,new.product_id,new.lot_id,sid,remaining) returning id into eid;
    insert into inventory.receipt_provenance_positions(tenant_id,warehouse_id,product_id,lot_id,serial_id,origin_line_id,entry_id,quantity)
     values(new.tenant_id,new.warehouse_id,new.product_id,new.lot_id,sid,origin,eid,remaining);
   end if;
  end if;
 end loop;
 -- All legacy projection changes precede the movement insert. Capture only the
 -- aligned final positive quantity/value after normal provenance succeeds.
 if new.lot_id is null and cardinality(new.serial_ids)=0
  and exists(select 1 from inventory.products p where p.tenant_id=new.tenant_id and p.id=new.product_id and p.tracking_mode='none')
  and exists(select 1 from inventory.stock_balances b join inventory.stock_valuations v on v.tenant_id=b.tenant_id and v.stock_balance_id=b.id
   where b.tenant_id=new.tenant_id and b.warehouse_id=new.warehouse_id and b.product_id=new.product_id and b.on_hand_quantity>0 and v.carrying_value>=0) then
  perform inventory.capture_negative_stock_basis(new.tenant_id,new.legal_entity_id,new.branch_id,new.warehouse_id,new.product_id,jsonb_build_object('movement_line_id',new.id,'snapshot_stage','after_aligned_movement'));
 end if;
 return new;
end $$;
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
-- END GENERATED ADDITIVE SUPERSESSIONS.






create function inventory.guard_negative_stock_operation() returns trigger language plpgsql security definer set search_path='' as $$
declare m inventory.stock_movements%rowtype;bal inventory.stock_balances%rowtype;begin
 select * into m from inventory.stock_movements where tenant_id=new.tenant_id and id=new.stock_movement_id;
 select * into bal from inventory.stock_balances where tenant_id=new.tenant_id and warehouse_id=new.warehouse_id and product_id=new.product_id;
 if m.source_type not in('delivery','goods_receipt','sales_return') and (
  bal.on_hand_quantity<0 or bal.on_hand_quantity-new.base_quantity<0 or bal.on_hand_quantity-bal.allocated_quantity<0
  or bal.on_hand_quantity-new.base_quantity-bal.allocated_quantity<0
  or exists(select 1 from inventory.negative_stock_deficits x where x.tenant_id=new.tenant_id and x.warehouse_id=new.warehouse_id and x.product_id=new.product_id
   and inventory.negative_stock_open_quantity(x.tenant_id,x.id)>0)) then
  raise exception using errcode='55000',message='NEGATIVE_STOCK_OPERATION_REQUIRES_REVIEW';end if;
 if m.source_type='sales_return' and exists(select 1 from inventory.negative_stock_deficits x where x.tenant_id=new.tenant_id and x.warehouse_id=new.warehouse_id
  and x.product_id=new.product_id and inventory.negative_stock_open_quantity(x.tenant_id,x.id)>0)
  and not exists(select 1 from inventory.negative_stock_return_allocations a where a.tenant_id=new.tenant_id and a.return_movement_line_id=new.id) then
  raise exception using errcode='55000',message='NEGATIVE_STOCK_RETURN_REQUIRES_CORRECTION';end if;
 return new;
end $$;
create trigger negative_stock_operation_guard before insert on inventory.stock_movement_lines for each row execute function inventory.guard_negative_stock_operation();

alter function api.upsert_stock_count(uuid,uuid,uuid,uuid,uuid,timestamptz,jsonb,bigint) rename to upsert_stock_count_without_negative_policy;
create function api.upsert_stock_count(p_tenant_id uuid,p_legal_entity_id uuid,p_branch_id uuid,p_command_id uuid,p_idempotency_key uuid,
 p_client_timestamp timestamptz,p_payload jsonb,p_expected_entity_version bigint default null) returns jsonb
language plpgsql security definer set search_path='' as $$begin
 perform core.wave3_require_scope(p_tenant_id,'inventory.adjustments.post',p_legal_entity_id,p_branch_id);
 -- Delegate saved retries to the unchanged routine so it checks current cost
 -- permission and the complete request hash before returning the receipt.
 if exists(select 1 from core.command_receipts r where r.actor_id=auth.uid() and r.idempotency_key=p_idempotency_key and r.response is not null) then
  return api.upsert_stock_count_without_negative_policy(p_tenant_id,p_legal_entity_id,p_branch_id,p_command_id,p_idempotency_key,p_client_timestamp,p_payload,p_expected_entity_version);
 end if;
 if exists(select 1 from inventory.stock_balances bal join jsonb_array_elements(p_payload->'lines')x on bal.product_id=(x->>'product_id')::uuid
  where bal.tenant_id=p_tenant_id and bal.legal_entity_id=p_legal_entity_id and bal.branch_id=p_branch_id and bal.warehouse_id=(p_payload->>'warehouse_id')::uuid
  and (bal.on_hand_quantity<0 or bal.allocated_quantity>bal.on_hand_quantity
   or exists(select 1 from inventory.negative_stock_deficits d where d.tenant_id=bal.tenant_id and d.warehouse_id=bal.warehouse_id and d.product_id=bal.product_id
    and inventory.negative_stock_open_quantity(d.tenant_id,d.id)>0))) then
  raise exception using errcode='55000',message='NEGATIVE_STOCK_OPERATION_REQUIRES_REVIEW';end if;
 return api.upsert_stock_count_without_negative_policy(p_tenant_id,p_legal_entity_id,p_branch_id,p_command_id,p_idempotency_key,p_client_timestamp,p_payload,p_expected_entity_version);
end $$;
alter function api.transfer_stock(uuid,uuid,uuid,uuid,uuid,timestamptz,jsonb,bigint) rename to transfer_stock_without_negative_policy;
create function api.transfer_stock(p_tenant_id uuid,p_legal_entity_id uuid,p_branch_id uuid,p_command_id uuid,p_idempotency_key uuid,
 p_client_timestamp timestamptz,p_payload jsonb,p_expected_entity_version bigint default null) returns jsonb
language plpgsql security definer set search_path='' as $$begin
 perform core.wave3_require_scope(p_tenant_id,'inventory.transfers.post',p_legal_entity_id,p_branch_id);
 -- The original routine rechecks both affected branch scopes and the hash.
 if exists(select 1 from core.command_receipts r where r.actor_id=auth.uid() and r.idempotency_key=p_idempotency_key and r.response is not null) then
  return api.transfer_stock_without_negative_policy(p_tenant_id,p_legal_entity_id,p_branch_id,p_command_id,p_idempotency_key,p_client_timestamp,p_payload,p_expected_entity_version);
 end if;
 if exists(select 1 from inventory.stock_balances bal join jsonb_array_elements(coalesce(p_payload->'lines','[]'))x on bal.product_id=(x->>'product_id')::uuid
  where bal.tenant_id=p_tenant_id and bal.legal_entity_id=p_legal_entity_id and bal.warehouse_id in((p_payload->>'source_warehouse_id')::uuid,(p_payload->>'destination_warehouse_id')::uuid)
  and (bal.on_hand_quantity<0 or bal.allocated_quantity>bal.on_hand_quantity
   or exists(select 1 from inventory.negative_stock_deficits d where d.tenant_id=bal.tenant_id and d.warehouse_id=bal.warehouse_id and d.product_id=bal.product_id
    and inventory.negative_stock_open_quantity(d.tenant_id,d.id)>0))) then
  raise exception using errcode='55000',message='NEGATIVE_STOCK_OPERATION_REQUIRES_REVIEW';end if;
 return api.transfer_stock_without_negative_policy(p_tenant_id,p_legal_entity_id,p_branch_id,p_command_id,p_idempotency_key,p_client_timestamp,p_payload,p_expected_entity_version);
end $$;

alter function api.reverse_goods_receipt(uuid,uuid,uuid,uuid,uuid,timestamptz,jsonb,bigint) rename to reverse_goods_receipt_without_negative_policy;
create function api.reverse_goods_receipt(p_tenant_id uuid,p_legal_entity_id uuid,p_branch_id uuid,p_command_id uuid,
 p_idempotency_key uuid,p_client_timestamp timestamptz,p_payload jsonb,p_expected_entity_version bigint default null) returns jsonb
language plpgsql security definer set search_path='' as $$begin
 perform core.wave3_require_scope(p_tenant_id,'procurement.receipts.post',p_legal_entity_id,p_branch_id);
 if exists(select 1 from procurement.goods_receipts r join inventory.stock_movement_lines ml on ml.stock_movement_id=r.stock_movement_id
  join inventory.negative_stock_covers c on c.tenant_id=ml.tenant_id and c.movement_line_id=ml.id and c.kind='receipt'
  where r.tenant_id=p_tenant_id and r.legal_entity_id=p_legal_entity_id and r.branch_id=p_branch_id and r.id=(p_payload->>'document_id')::uuid) then
  raise exception using errcode='55000',message='NEGATIVE_STOCK_RECEIPT_REVERSAL_REQUIRES_CORRECTION';end if;
 return api.reverse_goods_receipt_without_negative_policy(p_tenant_id,p_legal_entity_id,p_branch_id,p_command_id,p_idempotency_key,p_client_timestamp,p_payload,p_expected_entity_version);
end $$;

alter function inventory.build_valuation_report(uuid,uuid,uuid,jsonb) rename to negative_stock_original_valuation_report;
create function inventory.build_valuation_report(t uuid,e uuid,b uuid,p jsonb) returns jsonb
language plpgsql stable security definer set search_path='' as $$
declare result jsonb;extra jsonb;movements jsonb;diffs jsonb;stock jsonb;lots jsonb;deficits jsonb;sv numeric;tv numeric;gv numeric;d date:=(p->>'as_of')::date;begin
 result:=inventory.negative_stock_original_valuation_report(t,e,b,p);
 select coalesce(jsonb_agg(jsonb_build_object('id','negative-cover:'||c.id,'evidence_key','command:'||c.command_id,'command_id',c.command_id,
  'source_type','negative_stock.cover','source_id',c.id::text,'receipt_movement_line_id',c.movement_line_id,'issue_movement_line_id',x.issue_movement_line_id,
  'policy_id',x.policy_id,'warehouse_id',x.warehouse_id,'product_id',x.product_id,'quantity','0','value',(-c.variance)::text,'posting_date',c.posting_date,
  'covered_quantity',c.quantity::text,'actual_value',c.actual_value::text,'provisional_value',c.provisional_value::text,'variance',c.variance::text,'journal_entry_id',c.journal_entry_id) order by c.id),'[]') into extra
 from inventory.negative_stock_covers c join inventory.negative_stock_deficits x on x.tenant_id=c.tenant_id and x.id=c.deficit_id
 where c.tenant_id=t and c.legal_entity_id=e and c.kind='receipt' and c.posting_date<=d;
 movements:=(result->'movements')||extra;
 if jsonb_array_length(movements)>10000 then raise exception using errcode='54000',message='VALUATION_INPUT_LIMIT';end if;
 select coalesce(jsonb_agg(jsonb_build_object('id',x.id::text,'issue_movement_line_id',x.issue_movement_line_id,'policy_id',x.policy_id,
  'warehouse_id',x.warehouse_id,'product_id',x.product_id,'posting_date',x.posting_date,'quantity',x.quantity::text,'provisional_value',x.provisional_value::text,
  'open_quantity',(x.quantity-coalesce(c.covered,0))::text,
  'open_provisional_value',(x.provisional_value-round(x.provisional_value*coalesce(c.covered,0)/x.quantity,6))::text) order by x.id),'[]') into deficits
 from inventory.negative_stock_deficits x left join lateral(select sum(quantity) covered from inventory.negative_stock_covers z where z.tenant_id=x.tenant_id and z.deficit_id=x.id and z.posting_date<=d)c on true
 where x.tenant_id=t and x.legal_entity_id=e and x.posting_date<=d;
 if jsonb_array_length(deficits)>2000 then raise exception using errcode='54000',message='NEGATIVE_STOCK_EVIDENCE_LIMIT';end if;
 with rows as(select s,coalesce((select sum((c->>'value')::numeric) from jsonb_array_elements(extra)c where c->>'warehouse_id'=s->>'warehouse_id' and c->>'product_id'=s->>'product_id'),0) correction,
  coalesce((select sum((x->>'open_quantity')::numeric) from jsonb_array_elements(deficits)x where x->>'warehouse_id'=s->>'warehouse_id' and x->>'product_id'=s->>'product_id'),0) open_q,
  coalesce((select sum((x->>'open_provisional_value')::numeric) from jsonb_array_elements(deficits)x where x->>'warehouse_id'=s->>'warehouse_id' and x->>'product_id'=s->>'product_id'),0) open_v
  from jsonb_array_elements(result->'stock')s)
 select coalesce(jsonb_agg(s||jsonb_build_object('value',((s->>'value')::numeric+correction)::text,
  'average_cost',case when (s->>'quantity')::numeric>0 then round(((s->>'value')::numeric+correction)/(s->>'quantity')::numeric,12)::text end,
  'provisional_quantity',open_q::text,'provisional_value',open_v::text,'valuation_status',case when open_q>0 then 'provisional_deficit' else 'authoritative' end) order by s->>'id'),'[]') into stock from rows;
 select coalesce(jsonb_agg(case when x->>'lot_id' is null and exists(select 1 from jsonb_array_elements(deficits)nd
   where nd->>'warehouse_id'=s->>'warehouse_id' and nd->>'product_id'=s->>'product_id')
   then x||jsonb_build_object('value',s->>'value') else x end order by x->>'id'),'[]') into lots
 from jsonb_array_elements(result->'lots')x left join jsonb_array_elements(stock)s on s->>'id'=split_part(x->>'id',':',1)||':'||split_part(x->>'id',':',2);
 with entries as(select x->>'evidence_key' k,(x->>'value')::numeric v,0::numeric g from jsonb_array_elements(movements)x
  union all select x->>'evidence_key',(x->>'value')::numeric,0 from jsonb_array_elements(result->'transit')x
  union all select x->>'evidence_key',0,(x->>'value')::numeric from jsonb_array_elements(result->'journals')x),totals as(select k,sum(v)v,sum(g)g from entries group by k)
 select coalesce(jsonb_agg(jsonb_build_object('id',k,'evidence_key',k,'inventory_value',v::text,'gl_value',g::text,'difference',(v-g)::text) order by k),'[]') into diffs from totals where v<>g;
 select coalesce(sum((x->>'value')::numeric),0) into sv from jsonb_array_elements(stock)x;
 tv:=(result#>>'{summary,transit_value}')::numeric;gv:=(result#>>'{summary,gl_value}')::numeric;
 result:=result||jsonb_build_object('movements',movements,'stock',stock,'lots',lots,'differences',diffs,'negative_stock_deficits',deficits,
  'summary',(result->'summary')||jsonb_build_object('warehouse_value',sv::text,'inventory_value',(sv+tv)::text,'difference',(sv+tv-gv)::text,'difference_count',jsonb_array_length(diffs)));
 if octet_length(result::text)>16777216 then raise exception using errcode='54000',message='VALUATION_EVIDENCE_LIMIT';end if;
 return result;
end $$;

create function api.negative_stock_evidence(p_tenant_id uuid,p_legal_entity_id uuid,p_branch_id uuid,p_resource text,p_after bigint default null) returns jsonb
language plpgsql stable security definer set search_path='' as $$declare rows jsonb;cursor bigint;begin
 perform core.wave3_require_scope(p_tenant_id,'inventory.stock.view',p_legal_entity_id,p_branch_id);
 perform core.wave3_require_scope(p_tenant_id,'inventory.cost.view',p_legal_entity_id,p_branch_id);
 if p_legal_entity_id is null or p_branch_id is null then raise exception using errcode='42501',message='OPERATIONAL_SCOPE_REQUIRED';end if;
 if p_resource='deficits' then
  select coalesce(jsonb_agg(to_jsonb(q) order by q.sequence),'[]') into rows from(
   select x.id::text id,x.id sequence,x.issue_movement_line_id,x.policy_id,pol.version::text policy_version,x.basis_id::text basis_id,x.warehouse_id,x.product_id,
    x.quantity::text quantity,x.provisional_value::text provisional_value,inventory.negative_stock_open_quantity(x.tenant_id,x.id)::text open_quantity,
    x.posting_date,x.command_id,x.created_at,x.created_by
   from inventory.negative_stock_deficits x join inventory.negative_stock_policy_versions pol on pol.tenant_id=x.tenant_id and pol.id=x.policy_id
   where x.tenant_id=p_tenant_id and x.legal_entity_id=p_legal_entity_id and x.branch_id=p_branch_id and(p_after is null or x.id>p_after) order by x.id limit 51)q;
 elsif p_resource='covers' then
  select coalesce(jsonb_agg(to_jsonb(q) order by q.sequence),'[]') into rows from(
   select x.id::text id,x.id sequence,x.deficit_id::text deficit_id,x.movement_line_id,x.kind,x.quantity::text quantity,x.provisional_value::text provisional_value,
    x.actual_value::text actual_value,x.variance::text variance,x.journal_entry_id,x.posting_date,x.command_id,x.request_id,x.created_at,x.created_by
   from inventory.negative_stock_covers x where x.tenant_id=p_tenant_id and x.legal_entity_id=p_legal_entity_id and x.branch_id=p_branch_id
    and(p_after is null or x.id>p_after) order by x.id limit 51)q;
 else raise exception using errcode='22023',message='NEGATIVE_STOCK_EVIDENCE_RESOURCE_INVALID';end if;
 -- Sequence participates in server sorting only and never crosses as JSON number.
 if jsonb_array_length(rows)>50 then cursor:=(rows->49->>'sequence')::bigint;rows:=rows-50;end if;
 select coalesce(jsonb_agg(x-'sequence' order by (x->>'sequence')::bigint),'[]') into rows from jsonb_array_elements(rows)x;
 return jsonb_build_object('items',rows,'next_cursor',cursor::text);
end $$;

-- No alternate API name or internal helper exposes an unchecked write path.
revoke all on function api.reverse_goods_receipt_without_negative_policy(uuid,uuid,uuid,uuid,uuid,timestamptz,jsonb,bigint) from public,anon,authenticated;
revoke all on function api.upsert_stock_count_without_negative_policy(uuid,uuid,uuid,uuid,uuid,timestamptz,jsonb,bigint),api.transfer_stock_without_negative_policy(uuid,uuid,uuid,uuid,uuid,timestamptz,jsonb,bigint) from public,anon,authenticated;
revoke all on function sales.flow_post_without_negative_policy(text,uuid,uuid,uuid,uuid,uuid,timestamptz,jsonb,bigint),sales.flow_post(text,uuid,uuid,uuid,uuid,uuid,timestamptz,jsonb,bigint),
 sales.flow_post_stock(text,jsonb,uuid,uuid),inventory.record_receipt_provenance(),inventory.record_receipt_provenance_without_negative_policy(),
 inventory.negative_stock_original_valuation_report(uuid,uuid,uuid,jsonb),inventory.build_valuation_report(uuid,uuid,uuid,jsonb),
 inventory.negative_stock_policy_entity(inventory.negative_stock_policy_versions),inventory.require_negative_stock_policy(uuid,uuid,uuid,jsonb),
 inventory.capture_negative_stock_basis(uuid,uuid,uuid,uuid,uuid,jsonb),inventory.authorize_negative_stock_projection(inventory.stock_balances,inventory.stock_valuations,uuid,text,uuid,uuid,uuid,uuid,numeric,text,numeric,numeric,numeric),
 inventory.guard_negative_stock_balance(),inventory.guard_negative_stock_value(),inventory.guard_negative_stock_operation(),inventory.negative_stock_open_quantity(uuid,bigint),
 inventory.negative_stock_return_cost(inventory.stock_movement_lines,uuid,numeric,date,uuid,uuid),inventory.negative_stock_provenance(inventory.stock_movement_lines) from public,anon,authenticated;
revoke all on function api.negative_stock_policy(uuid,uuid,uuid),api.configure_negative_stock_policy(uuid,uuid,uuid,uuid,uuid,timestamptz,jsonb,bigint),
 api.negative_stock_evidence(uuid,uuid,uuid,text,bigint),api.reserve_sales_order_stock(uuid,uuid,uuid,uuid,uuid,timestamptz,jsonb,bigint),
 api.reverse_goods_receipt(uuid,uuid,uuid,uuid,uuid,timestamptz,jsonb,bigint) from public,anon,authenticated;
revoke all on function api.upsert_stock_count(uuid,uuid,uuid,uuid,uuid,timestamptz,jsonb,bigint),api.transfer_stock(uuid,uuid,uuid,uuid,uuid,timestamptz,jsonb,bigint) from public,anon,authenticated;
grant execute on function api.negative_stock_policy(uuid,uuid,uuid),api.configure_negative_stock_policy(uuid,uuid,uuid,uuid,uuid,timestamptz,jsonb,bigint),
 api.negative_stock_evidence(uuid,uuid,uuid,text,bigint),api.reserve_sales_order_stock(uuid,uuid,uuid,uuid,uuid,timestamptz,jsonb,bigint),
 api.reverse_goods_receipt(uuid,uuid,uuid,uuid,uuid,timestamptz,jsonb,bigint) to authenticated;
grant execute on function api.upsert_stock_count(uuid,uuid,uuid,uuid,uuid,timestamptz,jsonb,bigint),api.transfer_stock(uuid,uuid,uuid,uuid,uuid,timestamptz,jsonb,bigint) to authenticated;
notify pgrst,'reload schema';
