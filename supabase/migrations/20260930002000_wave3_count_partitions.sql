-- Additive count partition candidate. Capture is bounded to 10,000 identities;
-- approval and posting remain independent existing stock-count transactions.
create table inventory.stock_count_partition_groups (
 id uuid primary key, tenant_id uuid not null references core.tenants(id), legal_entity_id uuid not null,
 branch_id uuid not null, warehouse_id uuid not null, product_id uuid not null,
 cutoff_at timestamptz not null, identity_count integer not null check(identity_count between 1 and 10000),
 partition_count integer not null check(partition_count between 1 and 20),
 baseline_quantity numeric(20,6) not null check(baseline_quantity>=0),
 created_by uuid not null references auth.users(id), created_at timestamptz not null default now(),
 unique(tenant_id,id),
 foreign key(tenant_id,legal_entity_id) references core.legal_entities(tenant_id,id),
 foreign key(tenant_id,branch_id) references core.branches(tenant_id,id),
 foreign key(tenant_id,warehouse_id) references core.warehouses(tenant_id,id),
 foreign key(tenant_id,legal_entity_id,product_id) references inventory.products(tenant_id,legal_entity_id,id),
 check(partition_count=(identity_count+499)/500)
);
create table inventory.stock_count_partitions (
 tenant_id uuid not null, group_id uuid not null, count_id uuid not null,
 ordinal integer not null check(ordinal between 1 and 20), identity_count integer not null check(identity_count between 1 and 500),
 baseline_quantity numeric(20,6) not null check(baseline_quantity>=0),
 primary key(tenant_id,group_id,ordinal), unique(tenant_id,count_id), unique(tenant_id,group_id,count_id),
 foreign key(tenant_id,group_id) references inventory.stock_count_partition_groups(tenant_id,id),
 foreign key(tenant_id,count_id) references inventory.stock_counts(tenant_id,id)
);
create table inventory.stock_count_partition_identities (
 tenant_id uuid not null, group_id uuid not null, identity_id uuid not null, count_id uuid not null,
 baseline jsonb not null check(jsonb_typeof(baseline)='object'),
 primary key(tenant_id,group_id,identity_id),
 foreign key(tenant_id,group_id) references inventory.stock_count_partition_groups(tenant_id,id),
 foreign key(tenant_id,group_id,count_id) references inventory.stock_count_partitions(tenant_id,group_id,count_id)
);
create index stock_count_partition_identities_count_idx on inventory.stock_count_partition_identities(tenant_id,count_id,identity_id);
create index stock_count_partition_group_scope_idx on inventory.stock_count_partition_groups(tenant_id,legal_entity_id,branch_id,id);
-- Tenant-leading indexes also cover every referencing foreign key.
do $$declare t text; f record;begin
 foreach t in array array['stock_count_partition_groups','stock_count_partitions','stock_count_partition_identities'] loop
  for f in select c.conname,(select string_agg(quote_ident(a.attname),',' order by k.n)
   from unnest(c.conkey) with ordinality k(num,n) join pg_attribute a on a.attrelid=c.conrelid and a.attnum=k.num) cols
   from pg_constraint c where c.conrelid=('inventory.'||t)::regclass and c.contype='f' loop
   execute format('create index %I on inventory.%I(%s)',t||'_fk_'||substr(md5(f.conname),1,12)||'_idx',t,f.cols);
  end loop;
 end loop;
end $$;
create function inventory.count_partition_immutable() returns trigger language plpgsql set search_path='' as $$begin
 raise exception using errcode='55000',message='COUNT_PARTITION_BASELINE_IMMUTABLE';
end $$;
revoke all on function inventory.count_partition_immutable() from public,anon,authenticated;
do $$declare t text;begin
 foreach t in array array['stock_count_partition_groups','stock_count_partitions','stock_count_partition_identities'] loop
  execute format('alter table inventory.%I enable row level security',t);
  execute format('alter table inventory.%I force row level security',t);
  execute format('revoke all on inventory.%I from public,anon,authenticated',t);
  execute format('grant select on inventory.%I to authenticated',t);
  execute format('create trigger count_partition_immutable before update or delete on inventory.%I for each row execute function inventory.count_partition_immutable()',t);
 end loop;
end $$;
create policy count_partition_group_read on inventory.stock_count_partition_groups for select to authenticated using (
 core.is_tenant_member(tenant_id) and core.has_permission(tenant_id,'inventory.cost.view',legal_entity_id,branch_id)
 and (core.has_permission(tenant_id,'inventory.adjustments.post',legal_entity_id,branch_id)
 or core.has_permission(tenant_id,'workflow.approvals.decide',legal_entity_id,branch_id))
);
create policy count_partition_read on inventory.stock_count_partitions for select to authenticated using (
 exists(select 1 from inventory.stock_count_partition_groups g where g.tenant_id=stock_count_partitions.tenant_id and g.id=group_id)
);
create policy count_partition_identity_read on inventory.stock_count_partition_identities for select to authenticated using (
 exists(select 1 from inventory.stock_count_partition_groups g where g.tenant_id=stock_count_partition_identities.tenant_id and g.id=group_id)
);

-- Retain the original exact engine. A partition uses its own frozen baseline,
-- never a caller-supplied slice masquerading as the whole product baseline.
alter function inventory.count_normalize(uuid,uuid,uuid,jsonb,jsonb) rename to count_normalize_unpartitioned;
create function inventory.count_normalize(p_tenant uuid,p_entity uuid,p_branch uuid,p_payload jsonb,p_old jsonb default null)
returns jsonb language plpgsql security definer set search_path='' as $$
declare part inventory.stock_count_partitions%rowtype; g inventory.stock_count_partition_groups%rowtype; baseline_rows jsonb;
begin
 select * into part from inventory.stock_count_partitions where tenant_id=p_tenant and count_id=(p_old->>'id')::uuid;
 if part.count_id is null then
  if p_payload ?| array['partition_group_id','partition_ordinal','partition_identity_count','partition_count','partition_baseline_quantity'] then
   raise exception using errcode='22023',message='COUNT_PARTITION_METADATA_SERVER_ONLY';end if;
 else
  select * into g from inventory.stock_count_partition_groups where tenant_id=p_tenant and id=part.group_id;
  if g.legal_entity_id<>p_entity or g.branch_id<>p_branch or g.warehouse_id<>(p_old->>'warehouse_id')::uuid
   or g.cutoff_at<>(p_old->>'cutoff_at')::timestamptz or jsonb_array_length(p_old->'lines')<>1
   or (p_old#>>'{lines,0,product_id}')::uuid<>g.product_id
   or (p_old#>>'{lines,0,baseline_quantity}')::numeric<>part.baseline_quantity then
   raise exception using errcode='55000',message='COUNT_PARTITION_BASELINE_IMMUTABLE';end if;
  if (p_payload ? 'partition_group_id' and p_payload->>'partition_group_id' is distinct from part.group_id::text)
   or (p_payload ? 'partition_ordinal' and (p_payload->>'partition_ordinal')::integer is distinct from part.ordinal)
   or (p_payload ? 'partition_identity_count' and (p_payload->>'partition_identity_count')::integer is distinct from part.identity_count)
   or (p_payload ? 'partition_count' and (p_payload->>'partition_count')::integer is distinct from g.partition_count)
   or (p_payload ? 'partition_baseline_quantity' and (p_payload->>'partition_baseline_quantity')::numeric is distinct from part.baseline_quantity)
   or (p_payload ? 'cutoff_at' and (p_payload->>'cutoff_at')::timestamptz is distinct from g.cutoff_at) then
   raise exception using errcode='22023',message='COUNT_PARTITION_BASELINE_IMMUTABLE';end if;
  select jsonb_agg(baseline order by identity_id) into baseline_rows from inventory.stock_count_partition_identities
   where tenant_id=p_tenant and group_id=part.group_id and count_id=part.count_id;
  if coalesce(jsonb_array_length(baseline_rows),0)<>part.identity_count
   or coalesce(jsonb_array_length(p_old#>'{lines,0,identities}'),0)<>part.identity_count or exists (
   select 1 from jsonb_array_elements(baseline_rows) b where not exists (
    select 1 from jsonb_array_elements(p_old#>'{lines,0,identities}') x where x->>'id'=b->>'id'
     and x->>'baseline_version'=b->>'baseline_version'
     and x-'counted_quantity'-'variance_quantity'-'variance_value'-'baseline_version'
       =b-'counted_quantity'-'variance_quantity'-'variance_value'-'baseline_version')) then
   raise exception using errcode='55000',message='COUNT_PARTITION_BASELINE_IMMUTABLE';end if;
 end if;
 return inventory.count_normalize_unpartitioned(p_tenant,p_entity,p_branch,p_payload,p_old);
end $$;
revoke all on function inventory.count_normalize(uuid,uuid,uuid,jsonb,jsonb) from public,anon,authenticated;
alter function inventory.count_document(text,uuid,uuid,boolean) rename to count_document_unpartitioned;
create function inventory.count_document(p_kind text,p_tenant uuid,p_id uuid,p_lock boolean default false)
returns jsonb language plpgsql security definer set search_path='' as $$
declare d jsonb; m jsonb;begin
 d:=inventory.count_document_unpartitioned(p_kind,p_tenant,p_id,p_lock);
 if d->'workflow_snapshot'='null'::jsonb then d:=d-'workflow_snapshot';end if;
 select jsonb_build_object('partition_group_id',p.group_id,'partition_ordinal',p.ordinal,
  'partition_count',g.partition_count,'partition_identity_count',p.identity_count,'partition_baseline_quantity',p.baseline_quantity::text)
 into m from inventory.stock_count_partitions p join inventory.stock_count_partition_groups g on g.tenant_id=p.tenant_id and g.id=p.group_id
 where p.tenant_id=p_tenant and p.count_id=p_id;
 return d||coalesce(m,'{}');
end $$;
revoke all on function inventory.count_document(text,uuid,uuid,boolean) from public,anon,authenticated;

create function api.stock_count_partitions_page(p_tenant_id uuid,p_legal_entity_id uuid,p_branch_id uuid,p_group_id uuid,
 p_after integer default 0,p_limit integer default 50)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare g inventory.stock_count_partition_groups%rowtype; rows jsonb; captured integer; posted integer; cancelled integer;
 member_count integer; declared_count integer; baseline numeric; counted numeric; total numeric; missing jsonb; next_ordinal integer;
begin
 perform core.wave3_require_scope(p_tenant_id,'inventory.cost.view',p_legal_entity_id,p_branch_id);
 if not core.has_permission(p_tenant_id,'inventory.adjustments.post',p_legal_entity_id,p_branch_id)
  and not core.has_permission(p_tenant_id,'workflow.approvals.decide',p_legal_entity_id,p_branch_id) then
  raise exception using errcode='42501',message='PERMISSION_DENIED';end if;
 if p_after is null or p_after<0 or p_limit is null or p_limit not between 1 and 50 then
  raise exception using errcode='22023',message='COUNT_PARTITION_PAGE_INVALID';end if;
 select * into g from inventory.stock_count_partition_groups where tenant_id=p_tenant_id and legal_entity_id=p_legal_entity_id
  and branch_id=p_branch_id and id=p_group_id;
 if not found then raise exception using errcode='P0002',message='DOCUMENT_NOT_FOUND';end if;
 select count(*)::integer,count(*) filter(where c.status='posted')::integer,count(*) filter(where c.status='cancelled')::integer,
  coalesce(sum(p.identity_count),0)::integer,coalesce(sum(p.baseline_quantity),0),coalesce(sum((c.lines#>>'{0,counted_quantity}')::numeric),0),coalesce(sum(c.grand_total),0)
 into captured,posted,cancelled,declared_count,baseline,counted,total
 from inventory.stock_count_partitions p join inventory.stock_counts c on c.tenant_id=p.tenant_id and c.id=p.count_id
 where p.tenant_id=p_tenant_id and p.group_id=p_group_id;
 select count(*)::integer into member_count from inventory.stock_count_partition_identities where tenant_id=p_tenant_id and group_id=p_group_id;
 select coalesce(jsonb_agg(n order by n),'[]') into missing from generate_series(1,g.partition_count)n where not exists(
  select 1 from inventory.stock_count_partitions p join inventory.stock_counts c on c.tenant_id=p.tenant_id and c.id=p.count_id
   where p.tenant_id=p_tenant_id and p.group_id=p_group_id and p.ordinal=n);
 select coalesce(jsonb_agg(jsonb_build_object('id',q.count_id,'partition_ordinal',q.ordinal,'identity_count',q.identity_count,
  'baseline_quantity',q.baseline_quantity::text,'counted_quantity',q.lines#>>'{0,counted_quantity}',
  'variance_quantity',q.lines#>>'{0,variance_quantity}','grand_total',q.grand_total::text,'status',q.status,'version',q.version) order by q.ordinal),'[]')
 into rows from (select p.*,c.lines,c.grand_total,c.status,c.version from inventory.stock_count_partitions p
  join inventory.stock_counts c on c.tenant_id=p.tenant_id and c.id=p.count_id
  where p.tenant_id=p_tenant_id and p.group_id=p_group_id and p.ordinal>p_after order by p.ordinal limit p_limit+1)q;
 if jsonb_array_length(rows)>p_limit then next_ordinal:=(rows->(p_limit-1)->>'partition_ordinal')::integer;rows:=rows-p_limit;end if;
 return jsonb_build_object('id',g.id,'version','1','warehouse_id',g.warehouse_id,'product_id',g.product_id,'cutoff_at',g.cutoff_at,
  'expected_identity_count',g.identity_count,'captured_identity_count',member_count,'expected_partition_count',g.partition_count,
  'captured_partition_count',captured,'posted_partition_count',posted,'cancelled_partition_count',cancelled,
  'missing_partition_ordinals',missing,'baseline_quantity',g.baseline_quantity::text,'counted_quantity',counted::text,
  'variance_quantity',(counted-g.baseline_quantity)::text,'grand_total',total::text,
  'capture_complete',captured=g.partition_count and declared_count=member_count and member_count=g.identity_count and baseline=g.baseline_quantity and missing='[]'::jsonb,
  'posting_complete',posted=g.partition_count and cancelled=0 and declared_count=member_count and member_count=g.identity_count
   and baseline=g.baseline_quantity and missing='[]'::jsonb,'items',rows,'next_cursor',next_ordinal);
end $$;

create function api.capture_stock_count_partitions(p_tenant_id uuid,p_legal_entity_id uuid,p_branch_id uuid,p_command_id uuid,
 p_idempotency_key uuid,p_client_timestamp timestamptz,p_payload jsonb,p_expected_entity_version bigint default null)
returns jsonb language plpgsql security definer set search_path='' as $$
declare gid uuid:=(p_payload->>'id')::uuid;wh uuid:=(p_payload->>'warehouse_id')::uuid;pid uuid:=(p_payload->>'product_id')::uuid;
 req uuid:=gen_random_uuid();h text;replay jsonb;product inventory.products%rowtype;b inventory.stock_balances%rowtype;
 identities jsonb;page jsonb;row jsonb;seed jsonb;normalized jsonb;summary jsonb;cutoff timestamptz;n integer;ordinal integer;
 cid uuid;line_id uuid;baseline numeric;group_baseline numeric;currency text;
begin
 perform core.wave3_require_scope(p_tenant_id,'inventory.adjustments.post',p_legal_entity_id,p_branch_id);
 perform core.require_permission(p_tenant_id,'inventory.cost.view',p_legal_entity_id,p_branch_id);
 if gid is null or wh is null or pid is null or p_branch_id is null or p_legal_entity_id is null or p_client_timestamp is null
  or (p_payload ? 'partition_size' and p_payload->>'partition_size' is distinct from '500')
  or p_payload ?| array['lines','cutoff_at','partition_group_id','partition_ordinal','corrects_count_id'] then
  raise exception using errcode='22023',message='COUNT_PARTITION_INPUT_INVALID';end if;
 h:=core.wave3_request_hash('inventory.stock_count_partitions.capture',p_command_id,p_tenant_id,p_legal_entity_id,p_branch_id,p_payload,p_expected_entity_version);
 replay:=core.wave3_replay(p_tenant_id,'inventory.stock_count_partitions.capture',p_command_id,p_idempotency_key,h);
 if replay is not null then return replay;end if;
 perform pg_advisory_xact_lock(hashtextextended(p_tenant_id::text||':count-partition-group:'||gid::text,0));
 if p_expected_entity_version is not null or exists(select 1 from inventory.stock_count_partition_groups where id=gid) then
  raise exception using errcode='40001',message='VERSION_CONFLICT';end if;
 if not exists(select 1 from core.warehouses where tenant_id=p_tenant_id and legal_entity_id=p_legal_entity_id and branch_id=p_branch_id and id=wh and status='active') then
  raise exception using errcode='22023',message='COUNT_INPUT_INVALID';end if;
 perform pg_advisory_xact_lock(hashtextextended(p_tenant_id::text||':'||wh::text||':'||pid::text,0));
 select * into product from inventory.products where tenant_id=p_tenant_id and legal_entity_id=p_legal_entity_id and id=pid and kind='stocked' and status='active' for share;
 if not found or product.tracking_mode not in ('lot','serial') then raise exception using errcode='22023',message='COUNT_PRODUCT_INVALID';end if;
 select * into b from inventory.stock_balances where tenant_id=p_tenant_id and warehouse_id=wh and product_id=pid for update;
 if not found then raise exception using errcode='55000',message='COUNT_BALANCE_REQUIRED';end if;
 -- All captured rows are frozen under the same warehouse/product lock. The extra
 -- row detects overflow explicitly; no prefix is ever accepted as completeness.
 if product.tracking_mode='lot' then
  select coalesce(jsonb_agg(jsonb_build_object('id',x.lot_id,'code',x.code,'baseline_quantity',x.on_hand_quantity::text,
   'counted_quantity',x.on_hand_quantity::text,'baseline_version',x.version,'disposition',x.status) order by x.lot_id),'[]') into identities
  from (select lb.*,l.code,l.status from inventory.lot_balances lb join inventory.lots l on l.tenant_id=lb.tenant_id and l.id=lb.lot_id
   where lb.tenant_id=p_tenant_id and lb.warehouse_id=wh and lb.product_id=pid order by lb.lot_id limit 10001 for update of lb,l)x;
 else
  select coalesce(jsonb_agg(jsonb_build_object('id',x.id,'code',x.code,'baseline_quantity',case when x.status='count_missing' then '0' else '1' end,
   'counted_quantity',case when x.status='count_missing' then '0' else '1' end,'baseline_version',x.version,'disposition',x.status,
   'restore_status',coalesce(x.count_previous_status,x.status),'lot_id',x.lot_id) order by x.id),'[]') into identities
  from (select * from inventory.serials where tenant_id=p_tenant_id and warehouse_id=wh and product_id=pid
   and status in ('available','quarantine','count_missing') order by id limit 10001 for update)x;
 end if;
 n:=jsonb_array_length(identities);
 if n>10000 then raise exception using errcode='22023',message='LIMIT_EXCEEDED';end if;
 if n=0 then raise exception using errcode='22023',message='COUNT_IDENTITIES_REQUIRED';end if;
 select sum((value->>'baseline_quantity')::numeric) into group_baseline from jsonb_array_elements(identities);
 if group_baseline<>b.on_hand_quantity then raise exception using errcode='55000',message='COUNT_TRACKING_BALANCE_MISMATCH';end if;
 cutoff:=clock_timestamp();
 insert into inventory.stock_count_partition_groups(id,tenant_id,legal_entity_id,branch_id,warehouse_id,product_id,cutoff_at,identity_count,partition_count,baseline_quantity,created_by)
 values(gid,p_tenant_id,p_legal_entity_id,p_branch_id,wh,pid,cutoff,n,(n+499)/500,group_baseline,auth.uid());
 for ordinal in 1..((n+499)/500) loop
  cid:=md5(gid::text||':count-partition:'||ordinal)::uuid;line_id:=md5(cid::text||':line')::uuid;
  select jsonb_agg(value order by idx),sum((value->>'baseline_quantity')::numeric) into page,baseline
   from jsonb_array_elements(identities) with ordinality x(value,idx) where idx>(ordinal-1)*500 and idx<=ordinal*500;
  seed:=p_payload||jsonb_build_object('id',cid,'corrects_count_id',null,'cutoff_at',cutoff,'warehouse_id',wh,
   'lines',jsonb_build_array(jsonb_build_object('line_id',line_id,'product_id',pid,'base_unit_id',product.base_unit_id,
    'tracking_mode',product.tracking_mode,'baseline_quantity',baseline::text,'baseline_version',b.version,
    'counted_quantity',baseline::text,'empty_unit_cost','0','identities',page)));
  normalized:=inventory.count_normalize_unpartitioned(p_tenant_id,p_legal_entity_id,p_branch_id,seed,seed);
  insert into inventory.stock_counts(id,tenant_id,legal_entity_id,branch_id,warehouse_id,cutoff_at,document_date,reason,currency_code,offset_account_id,lines,grand_total,
   request_id,command_id,correlation_id,client_timestamp,prepared_by,created_by,updated_by)
  values(cid,p_tenant_id,p_legal_entity_id,p_branch_id,wh,cutoff,(normalized->>'document_date')::date,normalized->>'reason',normalized->>'currency_code',
   (normalized->>'offset_account_id')::uuid,normalized->'lines',(normalized->>'grand_total')::numeric,req,p_command_id,req,p_client_timestamp,auth.uid(),auth.uid(),auth.uid());
  insert into inventory.stock_count_partitions(tenant_id,group_id,count_id,ordinal,identity_count,baseline_quantity)
   values(p_tenant_id,gid,cid,ordinal,jsonb_array_length(page),baseline);
  insert into inventory.stock_count_partition_identities(tenant_id,group_id,identity_id,count_id,baseline)
   select p_tenant_id,gid,(value->>'id')::uuid,cid,value from jsonb_array_elements(page);
 end loop;
 summary:=api.stock_count_partitions_page(p_tenant_id,p_legal_entity_id,p_branch_id,gid)-'items'-'next_cursor';
 return core.wave3_finish_command(p_tenant_id,'inventory.stock_count_partitions.capture',p_command_id,'stock_count_partition_group',gid,
  p_idempotency_key,h,null,summary,p_legal_entity_id,p_branch_id,'{}',null,
  jsonb_build_array(jsonb_build_object('topic','inventory.stock_count_partitions.capture','payload',jsonb_build_object('id',gid,'partition_count',(n+499)/500))),'[]',req,req);
end $$;
revoke all on function api.capture_stock_count_partitions(uuid,uuid,uuid,uuid,uuid,timestamptz,jsonb,bigint),
 api.stock_count_partitions_page(uuid,uuid,uuid,uuid,integer,integer) from public,anon,authenticated;
grant execute on function api.capture_stock_count_partitions(uuid,uuid,uuid,uuid,uuid,timestamptz,jsonb,bigint),
 api.stock_count_partitions_page(uuid,uuid,uuid,uuid,integer,integer) to authenticated;
