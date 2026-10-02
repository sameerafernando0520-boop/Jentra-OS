begin;
set local lock_timeout='3s';
set local statement_timeout='90s';
-- W4-07 UNAPPLIED synthetic candidate. Installed journal/period provider only.
-- Procurement, stock and equipment providers are explicitly unavailable here.
-- No subscriptions, existing plan entitlements, roles or grants are changed.
create schema assets;
revoke all on schema assets from public,anon,authenticated;
insert into core.permissions(code,module,description,privileged) values
 ('assets.view','assets','Read scoped asset register and immutable books',false),
 ('assets.configure','assets','Configure named scoped asset locations with MFA',true),
 ('assets.prepare','assets','Prepare governed synthetic asset changes with MFA',true),
 ('assets.approve','assets','Independently approve exact asset proposal with MFA',true),
 ('assets.post','assets','Post approved asset effects with MFA',true),
 ('assets.depreciate','assets','Post exact immutable asset schedule periods with MFA',true),
 ('assets.reverse','assets','Reverse original asset effects with MFA',true),
 ('assets.transfer','assets','Authorize asset transfers in both branches with MFA',true)
on conflict(code) do nothing;
create table assets.locations(
 id uuid primary key,tenant_id uuid not null,legal_entity_id uuid not null,branch_id uuid not null,
 code text not null check(code ~ '^[A-Z0-9][A-Z0-9_-]{0,31}$'),name text not null check(length(btrim(name)) between 1 and 160),
 created_by uuid not null references auth.users(id),created_at timestamptz not null default clock_timestamp(),
 unique(tenant_id,legal_entity_id,branch_id,id),unique(tenant_id,legal_entity_id,branch_id,code),
 foreign key(tenant_id,legal_entity_id,branch_id) references core.branches(tenant_id,legal_entity_id,id)
);
create table assets.register(
 id uuid primary key,tenant_id uuid not null,legal_entity_id uuid not null,original_branch_id uuid not null,branch_id uuid not null,
 code text not null check(code ~ '^[A-Z0-9][A-Z0-9_-]{0,31}$'),name text not null check(length(btrim(name)) between 1 and 160),
 ownership text not null check(length(btrim(ownership)) between 1 and 160),currency_code text not null references core.currencies(code),
 in_service date not null,location_id uuid not null,custodian_id uuid,
 status text not null default 'draft' check(status in('draft','active','disposed','reversed')),
 version bigint not null default 1 check(version between 1 and 9007199254740991),
 cost numeric(20,6) not null default 0 check(cost>=0),accumulated numeric(20,6) not null default 0 check(accumulated>=0),
 impairment numeric(20,6) not null default 0 check(impairment>=0),
 cost_account_id uuid not null,accumulated_account_id uuid not null,impairment_account_id uuid not null,
 current_book_id uuid,posted_periods integer not null default 0 check(posted_periods between 0 and 1200),
 current_proposal_id uuid,last_effect_id uuid,
 created_by uuid not null references auth.users(id),created_at timestamptz not null default clock_timestamp(),
 check(in_service between '0001-01-01'::date and '9999-12-31'::date and accumulated+impairment<=cost),
 check(status<>'active' or cost>0),check(cost_account_id<>accumulated_account_id and cost_account_id<>impairment_account_id
  and accumulated_account_id<>impairment_account_id),
 unique(tenant_id,legal_entity_id,id),unique(tenant_id,legal_entity_id,code),
 foreign key(tenant_id,legal_entity_id,original_branch_id) references core.branches(tenant_id,legal_entity_id,id),
 foreign key(tenant_id,legal_entity_id,branch_id) references core.branches(tenant_id,legal_entity_id,id),
 foreign key(tenant_id,legal_entity_id,branch_id,location_id) references assets.locations(tenant_id,legal_entity_id,branch_id,id),
 foreign key(tenant_id,legal_entity_id,custodian_id) references people.employees(tenant_id,legal_entity_id,id),
 foreign key(tenant_id,legal_entity_id,cost_account_id) references finance.accounts(tenant_id,legal_entity_id,id),
 foreign key(tenant_id,legal_entity_id,accumulated_account_id) references finance.accounts(tenant_id,legal_entity_id,id),
 foreign key(tenant_id,legal_entity_id,impairment_account_id) references finance.accounts(tenant_id,legal_entity_id,id)
);
create table assets.opening_sources(
 id uuid primary key,tenant_id uuid not null,legal_entity_id uuid not null,asset_id uuid not null,
 source_reference text not null check(length(source_reference) between 1 and 160 and source_reference=upper(btrim(source_reference))),
 cost numeric(20,6) not null check(cost>0),opening_accumulated numeric(20,6) not null check(opening_accumulated between 0 and cost),
 components jsonb not null check(jsonb_typeof(components)='array' and jsonb_array_length(components) between 1 and 50),
 reason text not null check(length(btrim(reason)) between 1 and 1000),recorded_by uuid not null references auth.users(id),
 recorded_at timestamptz not null default clock_timestamp(),unique(tenant_id,legal_entity_id,asset_id),
 unique(tenant_id,legal_entity_id,source_reference),
 foreign key(tenant_id,legal_entity_id,asset_id) references assets.register(tenant_id,legal_entity_id,id)
);
create table assets.books(
 id uuid primary key,tenant_id uuid not null,legal_entity_id uuid not null,asset_id uuid not null,version bigint not null,
 basis jsonb not null check(jsonb_typeof(basis)='object'),reason text not null check(length(btrim(reason)) between 1 and 1000),
 created_by uuid not null references auth.users(id),created_at timestamptz not null default clock_timestamp(),
 unique(tenant_id,legal_entity_id,asset_id,id),unique(tenant_id,legal_entity_id,asset_id,version),
 foreign key(tenant_id,legal_entity_id,asset_id) references assets.register(tenant_id,legal_entity_id,id)
);
create table assets.schedules(
 tenant_id uuid not null,legal_entity_id uuid not null,asset_id uuid not null,book_id uuid not null,
 period_index integer not null check(period_index between 1 and 1200),facts jsonb not null check(jsonb_typeof(facts)='object'),
 primary key(book_id,period_index),
 foreign key(tenant_id,legal_entity_id,asset_id,book_id) references assets.books(tenant_id,legal_entity_id,asset_id,id)
);
create table assets.proposals(
 id uuid primary key,tenant_id uuid not null,legal_entity_id uuid not null,asset_id uuid not null,branch_id uuid not null,
 kind text not null check(kind in('capitalize','book_revision','transfer','impair','revalue','dispose')),
 data jsonb not null check(jsonb_typeof(data)='object'),digest text not null check(digest ~ '^[a-f0-9]{64}$'),
 posting_date date not null,reason text not null check(length(btrim(reason)) between 1 and 1000),
 prepared_by uuid not null references auth.users(id),prepared_at timestamptz not null default clock_timestamp(),
 unique(tenant_id,legal_entity_id,asset_id,id),
 foreign key(tenant_id,legal_entity_id,asset_id) references assets.register(tenant_id,legal_entity_id,id),
 foreign key(tenant_id,legal_entity_id,branch_id) references core.branches(tenant_id,legal_entity_id,id)
);
create table assets.approvals(
 proposal_id uuid primary key,tenant_id uuid not null,legal_entity_id uuid not null,asset_id uuid not null,
 digest text not null check(digest ~ '^[a-f0-9]{64}$'),approved_by uuid not null references auth.users(id),
 reason text not null check(length(btrim(reason)) between 1 and 1000),approved_at timestamptz not null default clock_timestamp(),
 foreign key(tenant_id,legal_entity_id,asset_id,proposal_id) references assets.proposals(tenant_id,legal_entity_id,asset_id,id)
);
create table assets.effects(
 id uuid primary key,tenant_id uuid not null,legal_entity_id uuid not null,asset_id uuid not null,branch_id uuid not null,
 kind text not null check(kind in('capitalize','book_revision','transfer','impair','revalue','dispose','depreciate','reverse')),
 proposal_id uuid unique,book_id uuid,period_index integer,posting_date date not null,
 original_effect_id uuid unique,prior_effect_id uuid,journal_id uuid,
 before_context jsonb not null,after_context jsonb not null,reason text not null check(length(btrim(reason)) between 1 and 1000),
 recorded_by uuid not null references auth.users(id),recorded_at timestamptz not null default clock_timestamp(),
 unique(tenant_id,legal_entity_id,asset_id,id),unique(book_id,period_index),
 check((kind='reverse')=(original_effect_id is not null)),
 check((kind='depreciate')=(period_index is not null)),
 foreign key(tenant_id,legal_entity_id,asset_id) references assets.register(tenant_id,legal_entity_id,id),
 foreign key(tenant_id,legal_entity_id,branch_id) references core.branches(tenant_id,legal_entity_id,id),
 foreign key(tenant_id,legal_entity_id,asset_id,proposal_id) references assets.proposals(tenant_id,legal_entity_id,asset_id,id),
 foreign key(tenant_id,legal_entity_id,asset_id,book_id) references assets.books(tenant_id,legal_entity_id,asset_id,id),
 foreign key(tenant_id,legal_entity_id,asset_id,original_effect_id) references assets.effects(tenant_id,legal_entity_id,asset_id,id),
 foreign key(tenant_id,legal_entity_id,asset_id,prior_effect_id) references assets.effects(tenant_id,legal_entity_id,asset_id,id),
 foreign key(tenant_id,journal_id) references finance.journal_entries(tenant_id,id)
);
alter table assets.register add foreign key(tenant_id,legal_entity_id,id,current_book_id)
 references assets.books(tenant_id,legal_entity_id,asset_id,id) deferrable initially deferred;
alter table assets.register add foreign key(tenant_id,legal_entity_id,id,current_proposal_id)
 references assets.proposals(tenant_id,legal_entity_id,asset_id,id) deferrable initially deferred;
alter table assets.register add foreign key(tenant_id,legal_entity_id,id,last_effect_id)
 references assets.effects(tenant_id,legal_entity_id,asset_id,id) deferrable initially deferred;
create function assets.immutable() returns trigger language plpgsql set search_path='' as $$begin
 raise exception using errcode='55000',message='ASSET_HISTORY_IMMUTABLE';end $$;
do $$declare n text;begin
 foreach n in array array['locations','register','opening_sources','books','schedules','proposals','approvals','effects'] loop
  execute format('alter table assets.%I enable row level security',n);
  execute format('alter table assets.%I force row level security',n);
  execute format('revoke all on assets.%I from public,anon,authenticated',n);
  if n<>'register' then execute format('create trigger immutable before update or delete on assets.%I for each row execute function assets.immutable()',n);end if;
 end loop;
end $$;
create index asset_locations_scope_idx on assets.locations(tenant_id,legal_entity_id,branch_id,id);
create index asset_register_scope_idx on assets.register(tenant_id,legal_entity_id,branch_id,id);
create index asset_register_custodian_idx on assets.register(tenant_id,legal_entity_id,custodian_id);
create index asset_register_original_branch_idx on assets.register(tenant_id,legal_entity_id,original_branch_id);
create index asset_register_location_idx on assets.register(tenant_id,legal_entity_id,branch_id,location_id);
create index asset_register_cost_account_idx on assets.register(tenant_id,legal_entity_id,cost_account_id);
create index asset_register_accumulated_account_idx on assets.register(tenant_id,legal_entity_id,accumulated_account_id);
create index asset_register_impairment_account_idx on assets.register(tenant_id,legal_entity_id,impairment_account_id);
create index asset_register_creator_idx on assets.register(created_by);
create index asset_location_creator_idx on assets.locations(created_by);
create index asset_opening_actor_idx on assets.opening_sources(recorded_by);
create index asset_book_actor_idx on assets.books(created_by);
create index asset_proposal_actor_idx on assets.proposals(prepared_by);
create index asset_proposal_branch_idx on assets.proposals(tenant_id,legal_entity_id,branch_id);
create index asset_approval_actor_idx on assets.approvals(approved_by);
create index asset_effect_actor_idx on assets.effects(recorded_by);
create index asset_effect_journal_idx on assets.effects(tenant_id,journal_id);
create index asset_effect_branch_idx on assets.effects(tenant_id,legal_entity_id,branch_id);
create index asset_effects_scope_idx on assets.effects(tenant_id,legal_entity_id,asset_id,id);
create index asset_proposals_scope_idx on assets.proposals(tenant_id,legal_entity_id,asset_id,id);
create function assets.require_access(t uuid,e uuid,b uuid,cap text,p_write boolean default false)
returns void language plpgsql security definer set search_path='' as $$begin
 if t is null or e is null or b is null or cap is null or cap not in('assets.view','assets.configure','assets.prepare',
  'assets.approve','assets.post','assets.depreciate','assets.reverse','assets.transfer') then
  raise exception using errcode='42501',message='ASSET_SCOPE_DENIED';end if;
 perform core.wave3_require_scope(t,'assets.view',e,b);perform core.wave3_require_scope(t,cap,e,b);
 if not exists(select 1 from billing.tenant_subscriptions s join billing.plan_entitlements p on p.plan_code=s.plan_code
  where s.tenant_id=t and p.entitlement_code='module.assets' and p.enabled and
  ((s.status='trialing' and s.trial_ends_at>now()) or(s.status='active' and
    (s.current_period_ends_at is null or s.current_period_ends_at>now())))) then
  raise exception using errcode='42501',message='ASSET_ENTITLEMENT_REQUIRED';end if;
 if p_write and coalesce(auth.jwt()->>'aal','aal1')<>'aal2' then
  raise exception using errcode='42501',message='ASSET_MFA_REQUIRED';end if;
end $$;
create function assets.amount(p jsonb) returns numeric language plpgsql immutable set search_path='' as $$begin
 if p is null or jsonb_typeof(p)<>'string' or p#>>'{}' !~ '^(0|[1-9][0-9]{0,13})(\.[0-9]{1,6})?$' then
  raise exception using errcode='22023',message='ASSET_AMOUNT_INVALID';end if;return (p#>>'{}')::numeric;end $$;
create function assets.ratio(n numeric,d numeric,p integer) returns numeric language plpgsql immutable set search_path='' as $$
declare q numeric;r numeric;divisor numeric;begin
 if n is null or d is null or p is null or n<0 or d<=0 or p not between 0 and 6 or n<>trunc(n) or d<>trunc(d) then
  raise exception using errcode='22023',message='ASSET_ROUNDING_INVALID';end if;
 divisor:=d*power(10::numeric,6-p);q:=div(n,divisor);r:=mod(n,divisor);
 if r*2>divisor or(r*2=divisor and mod(q,2)=1) then q:=q+1;end if;return q*power(10::numeric,6-p);
end $$;
create function assets.round_even(n numeric,p integer) returns numeric language sql immutable set search_path='' as $$
 select assets.ratio(n*1000000,1,p)/1000000 $$;
create function assets.schedule(cost text,accum text,impair text,residual text,months integer,method text,
 n bigint,d bigint,p_precision integer,first_date date) returns jsonb language plpgsql immutable set search_path='' as $$
declare c numeric:=assets.amount(to_jsonb(cost));a numeric:=assets.amount(to_jsonb(accum));
 m numeric:=assets.amount(to_jsonb(impair));r numeric:=assets.amount(to_jsonb(residual));
 carrying numeric;depreciable numeric;last_target numeric:=0;target numeric;dep numeric;i integer;s date;ed date;rows jsonb:='[]';begin
 -- Exact validation is separate from all date/amount computations.
 if months is null or months not between 1 and 1200 or method is null or method not in('straight_line','reducing_balance')
  or n is null or d is null or n not between 1 and 9007199254740991 or d not between 1 and 9007199254740991 or n>d
  or p_precision is null or p_precision not between 0 and 6 or first_date is null
  or first_date<>date_trunc('month',first_date)::date or first_date<'0001-01-01'::date
  or (first_date+make_interval(months=>months))::date>'9999-12-31'::date
  or c<=0 or a+m>c or r>c-a-m or c<>round(c,p_precision) or a<>round(a,p_precision)
  or m<>round(m,p_precision) or r<>round(r,p_precision) then
  raise exception using errcode='22023',message='ASSET_BOOK_INVALID';end if;
 carrying:=c-a-m;depreciable:=carrying-r;
 for i in 1..months loop
  s:=(first_date+make_interval(months=>i-1))::date;ed:=(first_date+make_interval(months=>i))::date;
  if i=months then dep:=carrying-r;
  elsif method='straight_line' then target:=assets.ratio(depreciable*1000000*i,months,p_precision)/1000000;
   dep:=target-last_target;last_target:=target;
  else dep:=least(carrying-r,assets.ratio(carrying*1000000*n,d,p_precision)/1000000);end if;
  if dep<0 or dep>carrying-r then raise exception using errcode='22023',message='ASSET_SCHEDULE_INVALID';end if;
  rows:=rows||jsonb_build_array(jsonb_build_object('period_index',i,'start_date',s,'end_date_exclusive',ed,'posting_date',ed-1,
   'opening_carrying',round(carrying,6)::text,'depreciation',round(dep,6)::text,'closing_carrying',round(carrying-dep,6)::text,
   'accumulated_closing',round(a+dep,6)::text));carrying:=carrying-dep;a:=a+dep;
 end loop;return rows;
end $$;
create function assets.account(t uuid,e uuid,p_id uuid,kind text,currency text) returns void
language plpgsql security definer set search_path='' as $$declare ap boolean:=false;begin
 perform 1 from finance.accounts where tenant_id=t and legal_entity_id=e and id=p_id for share;
 perform finance.flow_account(t,e,p_id,kind,currency);
 if exists(select 1 from finance.posting_mappings where tenant_id=t and legal_entity_id=e and account_id=p_id
  and purpose in('receivable_control','payable_control')) then
  raise exception using errcode='55000',message='ASSET_SEPARATE_CONTROL_REQUIRED';end if;
 if to_regclass('procurement.supplier_bill_controls') is not null then
  execute 'select exists(select 1 from procurement.supplier_bill_controls where tenant_id=$1 and legal_entity_id=$2 and payable_account_id=$3)'
   into ap using t,e,p_id;
 end if;if ap then raise exception using errcode='55000',message='ASSET_SEPARATE_CONTROL_REQUIRED';end if;
end $$;
create function assets.place(t uuid,e uuid,b uuid,location uuid,custodian uuid,on_date date) returns void
language plpgsql security definer set search_path='' as $$begin
 if not exists(select 1 from assets.locations where tenant_id=t and legal_entity_id=e and branch_id=b and id=location) then
  raise exception using errcode='55000',message='ASSET_LOCATION_INVALID';end if;
 if custodian is not null and not exists(select 1 from people.employees x join people.employment_assignments a
  on a.employee_id=x.id and a.tenant_id=x.tenant_id and a.legal_entity_id=x.legal_entity_id
  join people.employment_spells s on s.id=a.spell_id and s.tenant_id=a.tenant_id and s.legal_entity_id=a.legal_entity_id and s.employee_id=a.employee_id
  where x.tenant_id=t and x.legal_entity_id=e and x.id=custodian and a.branch_id=b
  and a.start_date<=on_date and(a.end_date_exclusive is null or a.end_date_exclusive>on_date)
  and s.start_date<=on_date and(s.end_date_exclusive is null or s.end_date_exclusive>on_date)) then
  raise exception using errcode='55000',message='ASSET_CUSTODIAN_INVALID';end if;
end $$;
create function assets.snapshot(p_id uuid) returns jsonb language sql stable security definer set search_path='' as $$
 select jsonb_build_object('branch_id',branch_id,'location_id',location_id,'custodian_id',custodian_id,'status',status,
  'cost',cost::text,'accumulated',accumulated::text,'impairment',impairment::text,'book_id',current_book_id,
  'posted_periods',posted_periods,'last_effect_id',last_effect_id) from assets.register where id=p_id $$;
create function assets.summary(p_id uuid) returns jsonb language sql stable security definer set search_path='' as $$
 select jsonb_build_object('id',id,'tenant_id',tenant_id,'legal_entity_id',legal_entity_id,'branch_id',branch_id,
  'original_branch_id',original_branch_id,'code',code,'name',name,'ownership',ownership,'currency_code',currency_code,
  'in_service',in_service,'location_id',location_id,'custodian_id',custodian_id,'status',status,'version',version,
  'cost',cost::text,'accumulated',accumulated::text,'impairment',impairment::text,'carrying',(cost-accumulated-impairment)::text,
  'cost_account_id',cost_account_id,'accumulated_account_id',accumulated_account_id,'impairment_account_id',impairment_account_id,
  'book_id',current_book_id,'posted_periods',posted_periods,'proposal_id',current_proposal_id,'last_effect_id',last_effect_id)
 from assets.register where id=p_id $$;
create function assets.book_validate(data jsonb,cost numeric,accum numeric,impair numeric,start_date date,in_service date,
 currency text,t uuid,e uuid) returns jsonb language plpgsql security definer set search_path='' as $$
declare result jsonb;begin
 if coalesce(jsonb_typeof(data),'null')<>'object' or exists(select 1 from jsonb_object_keys(data) k where k<>all(
  array['residual','remaining_months','method','convention','rate_numerator','rate_denominator','precision','expense_account_id']))
 or data->>'convention' is null or data->>'convention' not in('in_service_month','next_month')
  or start_date<(date_trunc('month',in_service)+case when data->>'convention'='next_month' then interval '1 month' else interval '0' end)::date
  or coalesce(data->>'remaining_months','') !~ '^[0-9]{1,4}$' or coalesce(data->>'precision','') !~ '^[0-6]$'
  or coalesce(data->>'rate_numerator','') !~ '^[0-9]{1,16}$' or coalesce(data->>'rate_denominator','') !~ '^[0-9]{1,16}$'
  or jsonb_typeof(data->'remaining_months') is distinct from 'number' or jsonb_typeof(data->'precision') is distinct from 'number'
  or jsonb_typeof(data->'rate_numerator') is distinct from 'number' or jsonb_typeof(data->'rate_denominator') is distinct from 'number'
  then raise exception using errcode='22023',message='ASSET_BOOK_INVALID';end if;
 perform assets.schedule(cost::text,accum::text,impair::text,assets.amount(data->'residual')::text,(data->>'remaining_months')::integer,
  data->>'method',(data->>'rate_numerator')::bigint,(data->>'rate_denominator')::bigint,(data->>'precision')::integer,start_date);
 perform assets.account(t,e,(data->>'expense_account_id')::uuid,'expense',currency);
 result:=data||jsonb_build_object('cost',cost::text,'opening_accumulated',accum::text,'opening_impairment',impair::text,
  'start_date',start_date,'in_service',in_service,'currency_code',currency,'residual',round(assets.amount(data->'residual'),6)::text);
 return result;
end $$;
create function assets.materialize_book(t uuid,e uuid,asset uuid,proposal uuid,basis jsonb,reason text) returns void
language plpgsql security definer set search_path='' as $$declare v bigint;begin
 select coalesce(max(version),0)+1 into v from assets.books where tenant_id=t and legal_entity_id=e and asset_id=asset;
 insert into assets.books(id,tenant_id,legal_entity_id,asset_id,version,basis,reason,created_by)
  values(proposal,t,e,asset,v,basis,reason,auth.uid());
 insert into assets.schedules(tenant_id,legal_entity_id,asset_id,book_id,period_index,facts)
  select t,e,asset,proposal,(x->>'period_index')::integer,x from jsonb_array_elements(assets.schedule(
   basis->>'cost',basis->>'opening_accumulated',basis->>'opening_impairment',basis->>'residual',
   (basis->>'remaining_months')::integer,basis->>'method',(basis->>'rate_numerator')::bigint,
   (basis->>'rate_denominator')::bigint,(basis->>'precision')::integer,(basis->>'start_date')::date)) x;
end $$;
create function api.assets_authorize(p_tenant_id uuid,p_legal_entity_id uuid,p_branch_id uuid,p_capability text)
returns jsonb language plpgsql stable security definer set search_path='' as $$begin
 perform assets.require_access(p_tenant_id,p_legal_entity_id,p_branch_id,p_capability,p_capability<>'assets.view');
 return jsonb_build_object('actor_id',auth.uid(),'tenant_id',p_tenant_id,'legal_entity_id',p_legal_entity_id,'branch_id',p_branch_id,
  'capability',p_capability,'authorized',true,'procurement_provider',false,'stock_provider',false,'equipment_provider',false,
  'currency_code',(select currency_code from core.legal_entities where tenant_id=p_tenant_id and id=p_legal_entity_id),
  'currency_precision',(select rounding_scale from core.legal_entities where tenant_id=p_tenant_id and id=p_legal_entity_id),
  'business_date',(select (now() at time zone timezone)::date from core.legal_entities where tenant_id=p_tenant_id and id=p_legal_entity_id));
end $$;
create function api.assets_command(p_tenant_id uuid,p_legal_entity_id uuid,p_branch_id uuid,p_command_id uuid,
 p_idempotency_key uuid,p_issued_at timestamptz,p_payload jsonb,p_expected_version bigint)
returns jsonb language plpgsql security definer set search_path='' as $$
#variable_conflict use_variable
<<asset_work>>
declare act text:=p_payload->>'action';cap text;id uuid;prop uuid;reason text;hash text;replay jsonb;request uuid:=gen_random_uuid();
 r assets.register%rowtype;p assets.proposals%rowtype;original assets.effects%rowtype;book jsonb;data jsonb;basis jsonb;
 before_state jsonb;after_state jsonb;cost numeric;accum numeric;impair numeric;amount numeric;proceeds numeric;delta numeric;
 start_date date;posting date;today date;rows jsonb;lines jsonb:='[]';journal uuid;effect uuid:=gen_random_uuid();
 next_branch uuid;location uuid;custodian uuid;offset_id uuid;gain_id uuid;loss_id uuid;proceeds_id uuid;current_period jsonb;
 component jsonb;total numeric:=0;source_reference text;allowed text[];transfer_branch uuid;begin
 if coalesce(jsonb_typeof(p_payload),'null')<>'object' or act is null or act not in('location','opening','propose','approve','post','depreciate','reverse','cancel')
  or p_command_id is null or p_idempotency_key is null or p_issued_at is null or p_issued_at>clock_timestamp()+interval '5 minutes'
  or p_expected_version is null or p_expected_version not between 0 and 9007199254740990 or octet_length(p_payload::text)>65536
  or jsonb_typeof(p_payload->'reason') is distinct from 'string'
  or coalesce(p_payload->>'id','') !~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
  or length(btrim(coalesce(p_payload->>'reason',''))) not between 1 and 1000 then
  raise exception using errcode='22023',message='ASSET_COMMAND_INVALID';end if;
 allowed:=case act when 'location' then array['action','id','code','name','reason']
  when 'opening' then array['action','id','proposal_id','source_id','source_reference','code','name','ownership','in_service','location_id','custodian_id',
   'cost','opening_accumulated','cost_components','cost_account_id','accumulated_account_id','impairment_account_id','offset_account_id','book','posting_date','currency_code','reason']
  when 'propose' then array['action','id','proposal_id','kind','book','destination_branch_id','location_id','custodian_id','amount','cost',
   'surplus_account_id','loss_account_id','proceeds','proceeds_account_id','gain_account_id','posting_date','reason']
  when 'depreciate' then array['action','id','book_id','period_index','reason']
  when 'reverse' then array['action','id','effect_id','reason'] else array['action','id','proposal_id','digest','reason'] end;
 if exists(select 1 from jsonb_object_keys(p_payload) k where k<>all(allowed)) then
  raise exception using errcode='22023',message='ASSET_COMMAND_FIELDS_INVALID';end if;
 cap:=case act when 'location' then 'assets.configure' when 'approve' then 'assets.approve' when 'post' then 'assets.post'
  when 'depreciate' then 'assets.depreciate' when 'reverse' then 'assets.reverse' else 'assets.prepare' end;
 perform assets.require_access(p_tenant_id,p_legal_entity_id,p_branch_id,cap,true);
 id:=(p_payload->>'id')::uuid;reason:=btrim(p_payload->>'reason');
 -- All original transfer authorities are rechecked before actor-bound replay.
 if act='propose' and p_payload->>'kind'='transfer' then transfer_branch:=(p_payload->>'destination_branch_id')::uuid;
 elsif act in('approve','post','cancel') then
  select (q.data->>'branch_id')::uuid into transfer_branch from assets.proposals q
   where q.tenant_id=p_tenant_id and q.legal_entity_id=p_legal_entity_id and q.branch_id=p_branch_id
    and q.asset_id=id and q.id=(p_payload->>'proposal_id')::uuid and q.kind='transfer';
 elsif act='reverse' then
  select (q.before_context->>'branch_id')::uuid into transfer_branch from assets.effects q
   where q.tenant_id=p_tenant_id and q.legal_entity_id=p_legal_entity_id and q.asset_id=id
    and q.id=(p_payload->>'effect_id')::uuid and q.kind='transfer';
 end if;
 if transfer_branch is not null then
  perform assets.require_access(p_tenant_id,p_legal_entity_id,p_branch_id,'assets.transfer',true);
  perform assets.require_access(p_tenant_id,p_legal_entity_id,transfer_branch,'assets.transfer',true);
 end if;
 hash:=core.wave3_request_hash('assets.'||act,p_command_id,p_tenant_id,p_legal_entity_id,p_branch_id,p_payload,p_expected_version);
 replay:=core.wave3_replay(p_tenant_id,'assets.'||act,p_command_id,p_idempotency_key,hash);
 if replay is not null then return replay;end if;
 select (now() at time zone timezone)::date into today from core.legal_entities where tenant_id=p_tenant_id and legal_entities.id=p_legal_entity_id;
 if act in('location','opening') then
  if p_expected_version<>0 or jsonb_typeof(p_payload->'code') is distinct from 'string' or jsonb_typeof(p_payload->'name') is distinct from 'string'
   or coalesce(p_payload->>'code','') !~ '^[A-Z0-9][A-Z0-9_-]{0,31}$'
   or length(btrim(coalesce(p_payload->>'name',''))) not between 1 and 160 then
   raise exception using errcode='22023',message='ASSET_CREATE_INVALID';end if;
  if act='location' then
   insert into assets.locations(id,tenant_id,legal_entity_id,branch_id,code,name,created_by)
    values(id,p_tenant_id,p_legal_entity_id,p_branch_id,p_payload->>'code',btrim(p_payload->>'name'),auth.uid());
   return core.wave3_finish_command(p_tenant_id,'assets.location',p_command_id,'assets.location',id,p_idempotency_key,hash,null,
    jsonb_build_object('id',id,'tenant_id',p_tenant_id,'legal_entity_id',p_legal_entity_id,'branch_id',p_branch_id,'version',1),
    p_legal_entity_id,p_branch_id,p_request_id=>request);
  end if;
  prop:=(p_payload->>'proposal_id')::uuid;cost:=assets.amount(p_payload->'cost');accum:=assets.amount(p_payload->'opening_accumulated');
  if p_payload->>'currency_code' is distinct from(select currency_code from core.legal_entities where tenant_id=p_tenant_id and legal_entities.id=p_legal_entity_id) then
   raise exception using errcode='55000',message='ASSET_BASE_CURRENCY_CHANGED';end if;
  posting:=(p_payload->>'posting_date')::date;source_reference:=upper(btrim(p_payload->>'source_reference'));
  if prop is null or (p_payload->>'source_id')::uuid is null or cost<=0 or accum>cost
   or length(btrim(coalesce(p_payload->>'ownership',''))) not between 1 and 160
   or jsonb_typeof(p_payload->'ownership') is distinct from 'string' or jsonb_typeof(p_payload->'source_reference') is distinct from 'string'
   or length(coalesce(source_reference,'')) not between 1 and 160 or source_reference ~ '[[:cntrl:]]'
   or posting is null or posting>today or (p_payload->>'in_service')::date is null or posting<(p_payload->>'in_service')::date
   or coalesce(jsonb_typeof(p_payload->'cost_components'),'null')<>'array'
   or jsonb_array_length(p_payload->'cost_components') not between 1 and 50 then
   raise exception using errcode='22023',message='ASSET_OPENING_INVALID';end if;
  for component in select value from jsonb_array_elements(p_payload->'cost_components') loop
   if coalesce(jsonb_typeof(component),'null')<>'object' or exists(select 1 from jsonb_object_keys(component) k where k<>all(array['code','name','amount']))
    or jsonb_typeof(component->'code') is distinct from 'string' or jsonb_typeof(component->'name') is distinct from 'string'
    or coalesce(component->>'code','') !~ '^[A-Z0-9][A-Z0-9_-]{0,31}$' or length(btrim(coalesce(component->>'name',''))) not between 1 and 160 then
    raise exception using errcode='22023',message='ASSET_COMPONENT_INVALID';end if;
   total:=total+assets.amount(component->'amount');
  end loop;
  if total<>cost or(select count(distinct x->>'code') from jsonb_array_elements(p_payload->'cost_components') x)<>jsonb_array_length(p_payload->'cost_components') then
   raise exception using errcode='22023',message='ASSET_COMPONENT_INVALID';end if;
  perform pg_advisory_xact_lock(hashtextextended('assets.opening:'||p_tenant_id||':'||p_legal_entity_id||':'||source_reference,0));
  if exists(select 1 from assets.opening_sources where tenant_id=p_tenant_id and legal_entity_id=p_legal_entity_id and opening_sources.source_reference=asset_work.source_reference) then
   raise exception using errcode='55000',message='ASSET_SOURCE_ALREADY_OWNED';end if;
  perform assets.place(p_tenant_id,p_legal_entity_id,p_branch_id,(p_payload->>'location_id')::uuid,(p_payload->>'custodian_id')::uuid,posting);
  -- The register holds no authoritative cost until independent approval/posting.
  insert into assets.register(id,tenant_id,legal_entity_id,original_branch_id,branch_id,code,name,ownership,currency_code,in_service,location_id,custodian_id,
   cost_account_id,accumulated_account_id,impairment_account_id,current_proposal_id,created_by)
   select id,p_tenant_id,p_legal_entity_id,p_branch_id,p_branch_id,p_payload->>'code',btrim(p_payload->>'name'),btrim(p_payload->>'ownership'),currency_code,
    (p_payload->>'in_service')::date,(p_payload->>'location_id')::uuid,(p_payload->>'custodian_id')::uuid,
    (p_payload->>'cost_account_id')::uuid,(p_payload->>'accumulated_account_id')::uuid,(p_payload->>'impairment_account_id')::uuid,prop,auth.uid()
   from core.legal_entities where tenant_id=p_tenant_id and legal_entities.id=p_legal_entity_id;
  select * into r from assets.register where register.id=id;
  perform assets.account(p_tenant_id,p_legal_entity_id,r.cost_account_id,'asset',r.currency_code);
  perform assets.account(p_tenant_id,p_legal_entity_id,r.accumulated_account_id,'asset',r.currency_code);
  perform assets.account(p_tenant_id,p_legal_entity_id,r.impairment_account_id,'asset',r.currency_code);
  offset_id:=(p_payload->>'offset_account_id')::uuid;perform assets.account(p_tenant_id,p_legal_entity_id,offset_id,'equity',r.currency_code);
  start_date:=(date_trunc('month',r.in_service)+case when p_payload->'book'->>'convention'='next_month' then interval '1 month' else interval '0' end)::date;
  basis:=assets.book_validate(p_payload->'book',cost,accum,0,start_date,r.in_service,r.currency_code,p_tenant_id,p_legal_entity_id);
  insert into assets.opening_sources(id,tenant_id,legal_entity_id,asset_id,source_reference,cost,opening_accumulated,components,reason,recorded_by)
   values((p_payload->>'source_id')::uuid,p_tenant_id,p_legal_entity_id,id,source_reference,cost,accum,p_payload->'cost_components',reason,auth.uid());
  data:=jsonb_build_object('book',basis,'offset_account_id',offset_id,'source_id',p_payload->>'source_id');
  insert into assets.proposals(id,tenant_id,legal_entity_id,asset_id,branch_id,kind,data,digest,posting_date,reason,prepared_by)
   values(prop,p_tenant_id,p_legal_entity_id,id,p_branch_id,'capitalize',data,encode(extensions.digest(convert_to(data::text,'UTF8'),'sha256'),'hex'),posting,reason,auth.uid());
 else
  select * into r from assets.register where tenant_id=p_tenant_id and legal_entity_id=p_legal_entity_id and branch_id=p_branch_id and register.id=id for update;
  if r.id is null then raise exception using errcode='P0002',message='ASSET_NOT_FOUND';end if;
  if r.version<>p_expected_version then raise exception using errcode='40001',message='VERSION_CONFLICT';end if;
  if r.currency_code is distinct from(select currency_code from core.legal_entities where tenant_id=p_tenant_id and legal_entities.id=p_legal_entity_id) then
   raise exception using errcode='55000',message='ASSET_BASE_CURRENCY_CHANGED';end if;
  before_state:=assets.snapshot(id);
  if act='propose' then
   if r.status<>'active' or r.current_proposal_id is not null then raise exception using errcode='55000',message='ASSET_STATE_INVALID';end if;
   prop:=(p_payload->>'proposal_id')::uuid;posting:=(p_payload->>'posting_date')::date;
   if prop is null or posting is null or posting>today or p_payload->>'kind' is null
    or p_payload->>'kind' not in('book_revision','transfer','impair','revalue','dispose') then
    raise exception using errcode='22023',message='ASSET_PROPOSAL_INVALID';end if;
   allowed:=array['action','id','proposal_id','kind','posting_date','reason']||case p_payload->>'kind'
    when 'book_revision' then array['book'] when 'transfer' then array['destination_branch_id','location_id','custodian_id']
    when 'impair' then array['amount','loss_account_id'] when 'revalue' then array['cost','surplus_account_id','loss_account_id']
    else array['proceeds','proceeds_account_id','gain_account_id','loss_account_id'] end;
   if exists(select 1 from jsonb_object_keys(p_payload) k where k<>all(allowed)) then
    raise exception using errcode='22023',message='ASSET_COMMAND_FIELDS_INVALID';end if;
   if exists(select 1 from assets.effects where effects.id=r.last_effect_id and posting_date>posting) then
    raise exception using errcode='55000',message='ASSET_EFFECT_DATE_INVALID';end if;
   select b.basis into book from assets.books b where b.id=r.current_book_id;
   if p_payload->>'kind'='transfer' then
    next_branch:=(p_payload->>'destination_branch_id')::uuid;location:=(p_payload->>'location_id')::uuid;custodian:=(p_payload->>'custodian_id')::uuid;
    perform assets.require_access(p_tenant_id,p_legal_entity_id,p_branch_id,'assets.transfer',true);
    perform assets.require_access(p_tenant_id,p_legal_entity_id,next_branch,'assets.transfer',true);
    perform assets.place(p_tenant_id,p_legal_entity_id,next_branch,location,custodian,posting);
    data:=jsonb_build_object('branch_id',next_branch,'location_id',location,'custodian_id',custodian);
   elsif p_payload->>'kind'='dispose' then
    proceeds:=assets.amount(p_payload->'proceeds');proceeds_id:=(p_payload->>'proceeds_account_id')::uuid;
    gain_id:=(p_payload->>'gain_account_id')::uuid;loss_id:=(p_payload->>'loss_account_id')::uuid;
    perform assets.account(p_tenant_id,p_legal_entity_id,proceeds_id,'asset',r.currency_code);
    perform assets.account(p_tenant_id,p_legal_entity_id,gain_id,'revenue',r.currency_code);
    perform assets.account(p_tenant_id,p_legal_entity_id,loss_id,'expense',r.currency_code);
    if proceeds_id in(r.cost_account_id,r.accumulated_account_id,r.impairment_account_id) or proceeds<>round(proceeds,(book->>'precision')::integer) then
     raise exception using errcode='22023',message='ASSET_DISPOSAL_INVALID';end if;
    data:=jsonb_build_object('proceeds',round(proceeds,6)::text,'proceeds_account_id',proceeds_id,'gain_account_id',gain_id,'loss_account_id',loss_id,
     'cost',r.cost::text,'accumulated',r.accumulated::text,'impairment',r.impairment::text,'carrying',(r.cost-r.accumulated-r.impairment)::text,
     'gain_loss',round(proceeds-r.cost+r.accumulated+r.impairment,6)::text);
   else
    select (s.facts->>'start_date')::date into start_date from assets.schedules s where s.book_id=r.current_book_id and s.period_index=r.posted_periods+1;
    if start_date is null then raise exception using errcode='55000',message='ASSET_UNPOSTED_PERIOD_REQUIRED';end if;
    cost:=r.cost;impair:=r.impairment;
    if p_payload->>'kind'='book_revision' then basis:=p_payload->'book';
    else
     basis:=book-array['cost','opening_accumulated','opening_impairment','start_date','in_service','currency_code'];
     basis:=basis||jsonb_build_object('remaining_months',(book->>'remaining_months')::integer-r.posted_periods);
     if p_payload->>'kind'='impair' then
      amount:=assets.amount(p_payload->'amount');if amount<=0 then raise exception using errcode='22023',message='ASSET_IMPAIRMENT_INVALID';end if;
      impair:=impair+amount;loss_id:=(p_payload->>'loss_account_id')::uuid;
      perform assets.account(p_tenant_id,p_legal_entity_id,loss_id,'expense',r.currency_code);
      data:=jsonb_build_object('amount',round(amount,6)::text,'loss_account_id',loss_id);
     else
      cost:=assets.amount(p_payload->'cost');if cost=r.cost then raise exception using errcode='22023',message='ASSET_REVALUATION_INVALID';end if;
      offset_id:=(p_payload->>'surplus_account_id')::uuid;loss_id:=(p_payload->>'loss_account_id')::uuid;
      perform assets.account(p_tenant_id,p_legal_entity_id,offset_id,'equity',r.currency_code);
      perform assets.account(p_tenant_id,p_legal_entity_id,loss_id,'expense',r.currency_code);
      data:=jsonb_build_object('cost',round(cost,6)::text,'surplus_account_id',offset_id,'loss_account_id',loss_id);
     end if;
    end if;
    basis:=assets.book_validate(basis,cost,r.accumulated,impair,start_date,r.in_service,r.currency_code,p_tenant_id,p_legal_entity_id);
    data:=coalesce(data,'{}')||jsonb_build_object('book',basis);
   end if;
   data:=data||jsonb_build_object('before',before_state);
   insert into assets.proposals(id,tenant_id,legal_entity_id,asset_id,branch_id,kind,data,digest,posting_date,reason,prepared_by)
    values(prop,p_tenant_id,p_legal_entity_id,id,p_branch_id,p_payload->>'kind',data,encode(extensions.digest(convert_to(data::text,'UTF8'),'sha256'),'hex'),posting,reason,auth.uid());
   update assets.register set current_proposal_id=prop,version=version+1 where register.id=id;
  elsif act in('approve','post','cancel') then
   prop:=(p_payload->>'proposal_id')::uuid;
   select * into p from assets.proposals where proposals.id=prop and tenant_id=p_tenant_id and legal_entity_id=p_legal_entity_id and asset_id=id;
   if p.id is null or r.current_proposal_id is distinct from prop or p.digest is distinct from p_payload->>'digest' then
    raise exception using errcode='55000',message='ASSET_PROPOSAL_STALE';end if;
   if p.kind='transfer' then
    perform assets.require_access(p_tenant_id,p_legal_entity_id,p_branch_id,'assets.transfer',true);
    perform assets.require_access(p_tenant_id,p_legal_entity_id,(p.data->>'branch_id')::uuid,'assets.transfer',true);
   end if;
   if act='approve' then
    if auth.uid()=p.prepared_by or exists(select 1 from assets.approvals where proposal_id=prop) then
     raise exception using errcode='42501',message='ASSET_INDEPENDENT_APPROVAL_REQUIRED';end if;
    insert into assets.approvals(proposal_id,tenant_id,legal_entity_id,asset_id,digest,approved_by,reason)
     values(prop,p_tenant_id,p_legal_entity_id,id,p.digest,auth.uid(),reason);
    update assets.register set version=version+1 where register.id=id;
   elsif act='cancel' then update assets.register set current_proposal_id=null,version=version+1 where register.id=id;
   else
    if not exists(select 1 from assets.approvals where proposal_id=prop and digest=p.digest and approved_by<>p.prepared_by) then
     raise exception using errcode='55000',message='ASSET_APPROVAL_REQUIRED';end if;
    if p.posting_date>today or(p.kind<>'capitalize' and p.data->'before' is distinct from before_state) then
     raise exception using errcode='55000',message='ASSET_PROPOSAL_STALE';end if;
    perform assets.account(p_tenant_id,p_legal_entity_id,r.cost_account_id,'asset',r.currency_code);
    perform assets.account(p_tenant_id,p_legal_entity_id,r.accumulated_account_id,'asset',r.currency_code);
    perform assets.account(p_tenant_id,p_legal_entity_id,r.impairment_account_id,'asset',r.currency_code);
    if p.kind in('capitalize','book_revision','impair','revalue') then
     basis:=p.data->'book';perform assets.account(p_tenant_id,p_legal_entity_id,(basis->>'expense_account_id')::uuid,'expense',r.currency_code);
    end if;
    if p.kind='capitalize' then
     if r.status<>'draft' or exists(select 1 from assets.effects where asset_id=id and kind='capitalize') then
      raise exception using errcode='55000',message='ASSET_SOURCE_ALREADY_OWNED';end if;
     cost:=(basis->>'cost')::numeric;accum:=(basis->>'opening_accumulated')::numeric;offset_id:=(p.data->>'offset_account_id')::uuid;
     perform assets.account(p_tenant_id,p_legal_entity_id,offset_id,'equity',r.currency_code);
     lines:=jsonb_build_array(jsonb_build_object('account_id',r.cost_account_id,'amount',cost::text,'base_amount',cost::text,'source_line_id',p.data->>'source_id'),
      jsonb_build_object('account_id',r.accumulated_account_id,'amount',(-accum)::text,'base_amount',(-accum)::text,'source_line_id',p.data->>'source_id'),
      jsonb_build_object('account_id',offset_id,'amount',(-(cost-accum))::text,'base_amount',(-(cost-accum))::text,'source_line_id',p.data->>'source_id'));
     update assets.register set cost=asset_work.cost,accumulated=accum,status='active' where register.id=id;
    elsif p.kind='transfer' then
     next_branch:=(p.data->>'branch_id')::uuid;location:=(p.data->>'location_id')::uuid;custodian:=(p.data->>'custodian_id')::uuid;
     perform assets.place(p_tenant_id,p_legal_entity_id,next_branch,location,custodian,p.posting_date);
     update assets.register set branch_id=next_branch,location_id=location,custodian_id=custodian where register.id=id;
    elsif p.kind='impair' then
     amount:=(p.data->>'amount')::numeric;loss_id:=(p.data->>'loss_account_id')::uuid;
     perform assets.account(p_tenant_id,p_legal_entity_id,loss_id,'expense',r.currency_code);
     lines:=jsonb_build_array(jsonb_build_object('account_id',loss_id,'amount',amount::text,'base_amount',amount::text,'source_line_id',prop),
      jsonb_build_object('account_id',r.impairment_account_id,'amount',(-amount)::text,'base_amount',(-amount)::text,'source_line_id',prop));
     update assets.register set impairment=impairment+amount where register.id=id;
    elsif p.kind='revalue' then
     cost:=(p.data->>'cost')::numeric;delta:=cost-r.cost;
     offset_id:=case when delta>0 then (p.data->>'surplus_account_id')::uuid else(p.data->>'loss_account_id')::uuid end;
     perform assets.account(p_tenant_id,p_legal_entity_id,offset_id,case when delta>0 then 'equity' else 'expense' end,r.currency_code);
     lines:=jsonb_build_array(jsonb_build_object('account_id',r.cost_account_id,'amount',delta::text,'base_amount',delta::text,'source_line_id',prop),
      jsonb_build_object('account_id',offset_id,'amount',(-delta)::text,'base_amount',(-delta)::text,'source_line_id',prop));
     update assets.register set cost=asset_work.cost where register.id=id;
    elsif p.kind='dispose' then
     proceeds:=(p.data->>'proceeds')::numeric;delta:=(p.data->>'gain_loss')::numeric;
     proceeds_id:=(p.data->>'proceeds_account_id')::uuid;gain_id:=(p.data->>'gain_account_id')::uuid;loss_id:=(p.data->>'loss_account_id')::uuid;
     perform assets.account(p_tenant_id,p_legal_entity_id,proceeds_id,'asset',r.currency_code);
     perform assets.account(p_tenant_id,p_legal_entity_id,gain_id,'revenue',r.currency_code);
     perform assets.account(p_tenant_id,p_legal_entity_id,loss_id,'expense',r.currency_code);
     lines:=jsonb_build_array(jsonb_build_object('account_id',r.cost_account_id,'amount',(-r.cost)::text,'base_amount',(-r.cost)::text,'source_line_id',prop),
      jsonb_build_object('account_id',r.accumulated_account_id,'amount',r.accumulated::text,'base_amount',r.accumulated::text,'source_line_id',prop),
      jsonb_build_object('account_id',r.impairment_account_id,'amount',r.impairment::text,'base_amount',r.impairment::text,'source_line_id',prop),
      jsonb_build_object('account_id',proceeds_id,'amount',proceeds::text,'base_amount',proceeds::text,'source_line_id',prop),
      jsonb_build_object('account_id',case when delta>0 then gain_id else loss_id end,'amount',(-delta)::text,'base_amount',(-delta)::text,'source_line_id',prop));
     update assets.register set status='disposed' where register.id=id;
    end if;
    if jsonb_array_length(lines)>0 then
     journal:=finance.flow_post_journal(jsonb_build_object('tenant_id',p_tenant_id,'legal_entity_id',p_legal_entity_id,'branch_id',p_branch_id,
      'document_date',p.posting_date,'currency_code',r.currency_code,'base_currency_code',r.currency_code,'exchange_rate','1.000000'),
      lines,'asset_'||p.kind,effect,request,p_command_id);
    end if;
    if p.kind in('capitalize','book_revision','impair','revalue') then
     perform assets.materialize_book(p_tenant_id,p_legal_entity_id,id,prop,basis,p.reason);
     update assets.register set current_book_id=prop,posted_periods=0 where register.id=id;
    end if;
    update assets.register set current_proposal_id=null,last_effect_id=effect,version=version+1 where register.id=id;
    after_state:=assets.snapshot(id);
    insert into assets.effects(id,tenant_id,legal_entity_id,asset_id,branch_id,kind,proposal_id,book_id,posting_date,prior_effect_id,journal_id,before_context,after_context,reason,recorded_by)
     values(effect,p_tenant_id,p_legal_entity_id,id,p_branch_id,p.kind,prop,case when p.kind in('capitalize','book_revision','impair','revalue') then prop else r.current_book_id end,
      p.posting_date,r.last_effect_id,journal,before_state,after_state,reason,auth.uid());
   end if;
  elsif act='depreciate' then
   if r.status<>'active' or r.current_proposal_id is not null or r.current_book_id is distinct from(p_payload->>'book_id')::uuid
    or jsonb_typeof(p_payload->'period_index') is distinct from 'number'
    or coalesce(p_payload->>'period_index','') !~ '^[0-9]{1,4}$' or(p_payload->>'period_index')::integer<>r.posted_periods+1 then
    raise exception using errcode='55000',message='ASSET_SCHEDULE_STALE';end if;
   select s.facts into current_period from assets.schedules s where s.book_id=r.current_book_id and s.period_index=r.posted_periods+1;
   select b.basis into book from assets.books b where b.id=r.current_book_id;
   if current_period is null or(current_period->>'posting_date')::date>today
    or(current_period->>'opening_carrying')::numeric<>r.cost-r.accumulated-r.impairment then
    raise exception using errcode='55000',message='ASSET_SCHEDULE_STALE';end if;
   if exists(select 1 from assets.effects where book_id=r.current_book_id and period_index=r.posted_periods+1) then
    raise exception using errcode='55000',message='ASSET_REBOOK_AFTER_REVERSAL_REQUIRED';end if;
   perform finance.wave3_lock_open_period(p_tenant_id,p_legal_entity_id,(current_period->>'posting_date')::date);
   perform assets.account(p_tenant_id,p_legal_entity_id,(book->>'expense_account_id')::uuid,'expense',r.currency_code);
   perform assets.account(p_tenant_id,p_legal_entity_id,r.accumulated_account_id,'asset',r.currency_code);
   amount:=(current_period->>'depreciation')::numeric;
   if amount>0 then
    lines:=jsonb_build_array(jsonb_build_object('account_id',book->>'expense_account_id','amount',amount::text,'base_amount',amount::text,'source_line_id',effect),
     jsonb_build_object('account_id',r.accumulated_account_id,'amount',(-amount)::text,'base_amount',(-amount)::text,'source_line_id',effect));
    journal:=finance.flow_post_journal(jsonb_build_object('tenant_id',p_tenant_id,'legal_entity_id',p_legal_entity_id,'branch_id',p_branch_id,
     'document_date',current_period->>'posting_date','currency_code',r.currency_code,'base_currency_code',r.currency_code,'exchange_rate','1.000000'),
     lines,'asset_depreciate',effect,request,p_command_id);
   end if;
   update assets.register set accumulated=accumulated+amount,posted_periods=posted_periods+1,last_effect_id=effect,version=version+1 where register.id=id;
   insert into assets.effects(id,tenant_id,legal_entity_id,asset_id,branch_id,kind,book_id,period_index,posting_date,prior_effect_id,journal_id,before_context,after_context,reason,recorded_by)
    values(effect,p_tenant_id,p_legal_entity_id,id,p_branch_id,'depreciate',r.current_book_id,r.posted_periods+1,(current_period->>'posting_date')::date,
     r.last_effect_id,journal,before_state,assets.snapshot(id),reason,auth.uid());
  else
   if r.current_proposal_id is not null then raise exception using errcode='55000',message='ASSET_STATE_INVALID';end if;
   select * into original from assets.effects where effects.id=(p_payload->>'effect_id')::uuid and tenant_id=p_tenant_id and legal_entity_id=p_legal_entity_id and asset_id=id;
   if original.id is null or original.kind='reverse' or r.last_effect_id is distinct from original.id
    or exists(select 1 from assets.effects where original_effect_id=original.id) then
    raise exception using errcode='55000',message='ASSET_DEPENDENT_EFFECT_BLOCKS_REVERSAL';end if;
   next_branch:=(original.before_context->>'branch_id')::uuid;
   if original.kind='transfer' then
    perform assets.require_access(p_tenant_id,p_legal_entity_id,p_branch_id,'assets.transfer',true);
    perform assets.require_access(p_tenant_id,p_legal_entity_id,next_branch,'assets.transfer',true);
   end if;
   if original.journal_id is not null then
    select jsonb_agg(jsonb_build_object('account_id',account_id,'source_line_id',source_line_id,
     'amount',(transaction_credit-transaction_debit)::text,'base_amount',(base_credit-base_debit)::text) order by line_number) into lines
     from finance.journal_lines where tenant_id=p_tenant_id and legal_entity_id=p_legal_entity_id and journal_entry_id=original.journal_id;
    journal:=finance.flow_post_journal(jsonb_build_object('tenant_id',p_tenant_id,'legal_entity_id',p_legal_entity_id,'branch_id',p_branch_id,
     'document_date',original.posting_date,'currency_code',r.currency_code,'base_currency_code',r.currency_code,'exchange_rate','1.000000'),
     lines,'asset_reverse',effect,request,p_command_id);
   else perform finance.wave3_lock_open_period(p_tenant_id,p_legal_entity_id,original.posting_date);end if;
   data:=original.before_context;
   update assets.register set branch_id=next_branch,location_id=(data->>'location_id')::uuid,custodian_id=(data->>'custodian_id')::uuid,
    status=case when original.kind='capitalize' then 'reversed' else data->>'status' end,cost=(data->>'cost')::numeric,
    accumulated=(data->>'accumulated')::numeric,impairment=(data->>'impairment')::numeric,current_book_id=(data->>'book_id')::uuid,
    posted_periods=(data->>'posted_periods')::integer,last_effect_id=original.prior_effect_id,version=version+1 where register.id=id;
   insert into assets.effects(id,tenant_id,legal_entity_id,asset_id,branch_id,kind,posting_date,original_effect_id,prior_effect_id,journal_id,before_context,after_context,reason,recorded_by)
    values(effect,p_tenant_id,p_legal_entity_id,id,p_branch_id,'reverse',original.posting_date,original.id,r.last_effect_id,journal,before_state,assets.snapshot(id),reason,auth.uid());
  end if;
 end if;
 select * into r from assets.register where register.id=id;
 -- Only IDs/version/state enter generic receipts/audit/outbox, never evidence or financial values.
 after_state:=jsonb_build_object('id',id,'tenant_id',p_tenant_id,'legal_entity_id',p_legal_entity_id,'branch_id',p_branch_id,'current_branch_id',r.branch_id,
  'version',r.version,'status',r.status,'proposal_id',r.current_proposal_id,'book_id',r.current_book_id,'last_effect_id',r.last_effect_id);
 return core.wave3_finish_command(p_tenant_id,'assets.'||act,p_command_id,'assets.asset',id,p_idempotency_key,hash,null,after_state,
  p_legal_entity_id,p_branch_id,p_source_context=>jsonb_build_object('action',act,'transfer_branch_id',transfer_branch),p_request_id=>request);
end $$;
create function api.assets_register(p_tenant_id uuid,p_legal_entity_id uuid,p_branch_id uuid,p_after uuid default null)
returns jsonb language plpgsql stable security definer set search_path='' as $$declare items jsonb;begin
 perform assets.require_access(p_tenant_id,p_legal_entity_id,p_branch_id,'assets.view');
 select coalesce(jsonb_agg(assets.summary(q.id) order by q.id),'[]'::jsonb) into items from(select id from assets.register
  where tenant_id=p_tenant_id and legal_entity_id=p_legal_entity_id and branch_id=p_branch_id and(p_after is null or id>p_after) order by id limit 51) q;
 return jsonb_build_object('tenant_id',p_tenant_id,'legal_entity_id',p_legal_entity_id,'branch_id',p_branch_id,'items',items-50,
  'next_cursor',case when jsonb_array_length(items)>50 then items->49->>'id' end);
end $$;
create function assets.label(t uuid,e uuid,kind text,p_id uuid) returns text language plpgsql stable set search_path='' as $$
declare label text;begin
 if kind='account' then select code||' · '||name into label from finance.accounts where tenant_id=t and legal_entity_id=e and id=p_id;
 elsif kind='location' then select code||' · '||name into label from assets.locations where tenant_id=t and legal_entity_id=e and id=p_id;
 elsif kind='custodian' then select code||' · '||display_name into label from people.employees where tenant_id=t and legal_entity_id=e and id=p_id;
 elsif kind='branch' then select code||' · '||name into label from core.branches where tenant_id=t and legal_entity_id=e and id=p_id;end if;
 return label;
end $$;
create function api.assets_detail(p_tenant_id uuid,p_legal_entity_id uuid,p_branch_id uuid,p_asset_id uuid,p_kind text,p_after uuid default null)
returns jsonb language plpgsql stable security definer set search_path='' as $$declare items jsonb;prop jsonb;opening jsonb;summary jsonb;labels jsonb;begin
 perform assets.require_access(p_tenant_id,p_legal_entity_id,p_branch_id,'assets.view');
 if p_kind is null or p_kind not in('books','effects','proposals') then raise exception using errcode='22023',message='ASSET_PAGE_INVALID';end if;
 if not exists(select 1 from assets.register where tenant_id=p_tenant_id and legal_entity_id=p_legal_entity_id and branch_id=p_branch_id and id=p_asset_id) then
  raise exception using errcode='P0002',message='ASSET_NOT_FOUND';end if;
 if p_kind='books' then select coalesce(jsonb_agg(to_jsonb(q) order by q.id),'[]') into items from(select * from assets.books
  where tenant_id=p_tenant_id and legal_entity_id=p_legal_entity_id and asset_id=p_asset_id and(p_after is null or id>p_after) order by id limit 51) q;
 elsif p_kind='effects' then select coalesce(jsonb_agg(to_jsonb(q) order by q.id),'[]') into items from(select * from assets.effects
  where tenant_id=p_tenant_id and legal_entity_id=p_legal_entity_id and asset_id=p_asset_id and(p_after is null or id>p_after) order by id limit 51) q;
 else select coalesce(jsonb_agg(to_jsonb(q)||jsonb_build_object('approval',(select to_jsonb(a) from assets.approvals a where a.proposal_id=q.id)) order by q.id),'[]') into items
  from(select * from assets.proposals where tenant_id=p_tenant_id and legal_entity_id=p_legal_entity_id and asset_id=p_asset_id
   and(p_after is null or id>p_after) order by id limit 51) q;end if;
 select to_jsonb(p)||jsonb_build_object('approval',(select to_jsonb(a) from assets.approvals a where a.proposal_id=p.id)) into prop
  from assets.proposals p join assets.register r on r.current_proposal_id=p.id where r.id=p_asset_id;
 select to_jsonb(s)||jsonb_build_object('cost',s.cost::text,'opening_accumulated',s.opening_accumulated::text)
  into opening from assets.opening_sources s where s.asset_id=p_asset_id;
 summary:=assets.summary(p_asset_id);
 labels:=jsonb_build_object(
  'cost_account_id',assets.label(p_tenant_id,p_legal_entity_id,'account',(summary->>'cost_account_id')::uuid),
  'accumulated_account_id',assets.label(p_tenant_id,p_legal_entity_id,'account',(summary->>'accumulated_account_id')::uuid),
  'impairment_account_id',assets.label(p_tenant_id,p_legal_entity_id,'account',(summary->>'impairment_account_id')::uuid),
  'location_id',assets.label(p_tenant_id,p_legal_entity_id,'location',(summary->>'location_id')::uuid),
  'custodian_id',assets.label(p_tenant_id,p_legal_entity_id,'custodian',(summary->>'custodian_id')::uuid),
  'branch_id',assets.label(p_tenant_id,p_legal_entity_id,'branch',(summary->>'branch_id')::uuid),
  'expense_account_id',assets.label(p_tenant_id,p_legal_entity_id,'account',(prop->'data'->'book'->>'expense_account_id')::uuid),
  'offset_account_id',assets.label(p_tenant_id,p_legal_entity_id,'account',(prop->'data'->>'offset_account_id')::uuid),
  'loss_account_id',assets.label(p_tenant_id,p_legal_entity_id,'account',(prop->'data'->>'loss_account_id')::uuid),
  'surplus_account_id',assets.label(p_tenant_id,p_legal_entity_id,'account',(prop->'data'->>'surplus_account_id')::uuid),
  'proceeds_account_id',assets.label(p_tenant_id,p_legal_entity_id,'account',(prop->'data'->>'proceeds_account_id')::uuid),
  'gain_account_id',assets.label(p_tenant_id,p_legal_entity_id,'account',(prop->'data'->>'gain_account_id')::uuid),
  'destination_branch_id',assets.label(p_tenant_id,p_legal_entity_id,'branch',(prop->'data'->>'branch_id')::uuid),
  'destination_location_id',assets.label(p_tenant_id,p_legal_entity_id,'location',(prop->'data'->>'location_id')::uuid),
  'destination_custodian_id',assets.label(p_tenant_id,p_legal_entity_id,'custodian',(prop->'data'->>'custodian_id')::uuid));
 return jsonb_build_object('tenant_id',p_tenant_id,'legal_entity_id',p_legal_entity_id,'branch_id',p_branch_id,'asset',summary,
  'kind',p_kind,'proposal',prop,'opening',opening,'labels',labels,'items',items-50,'next_cursor',case when jsonb_array_length(items)>50 then items->49->>'id' end);
end $$;
create function api.assets_schedule(p_tenant_id uuid,p_legal_entity_id uuid,p_branch_id uuid,p_asset_id uuid,p_book_id uuid,p_after integer default 0)
returns jsonb language plpgsql stable security definer set search_path='' as $$declare items jsonb;basis jsonb;begin
 perform assets.require_access(p_tenant_id,p_legal_entity_id,p_branch_id,'assets.view');
 if p_after is null or p_after not between 0 and 1200 then raise exception using errcode='22023',message='ASSET_PAGE_INVALID';end if;
 if not exists(select 1 from assets.register where tenant_id=p_tenant_id and legal_entity_id=p_legal_entity_id and branch_id=p_branch_id and id=p_asset_id) then
  raise exception using errcode='P0002',message='ASSET_NOT_FOUND';end if;
 select b.basis into basis from assets.books b where tenant_id=p_tenant_id and legal_entity_id=p_legal_entity_id and asset_id=p_asset_id and id=p_book_id;
 if basis is null then raise exception using errcode='P0002',message='ASSET_BOOK_NOT_FOUND';end if;
 select coalesce(jsonb_agg(q.facts order by q.period_index),'[]') into items from(select * from assets.schedules where book_id=p_book_id
  and period_index>p_after order by period_index limit 51) q;
 return jsonb_build_object('tenant_id',p_tenant_id,'legal_entity_id',p_legal_entity_id,'branch_id',p_branch_id,'asset_id',p_asset_id,'book_id',p_book_id,
  'basis',basis,'items',items-50,'next_cursor',case when jsonb_array_length(items)>50 then items->49->>'period_index' end);
end $$;
create function api.assets_pickers(p_tenant_id uuid,p_legal_entity_id uuid,p_branch_id uuid,p_kind text,p_after uuid default null)
returns jsonb language plpgsql stable security definer set search_path='' as $$declare items jsonb;today date;begin
 perform assets.require_access(p_tenant_id,p_legal_entity_id,p_branch_id,'assets.view');
 if p_kind='locations' then
  select coalesce(jsonb_agg(jsonb_build_object('id',q.id,'code',q.code,'name',q.name) order by q.id),'[]') into items from(select * from assets.locations
   where tenant_id=p_tenant_id and legal_entity_id=p_legal_entity_id and branch_id=p_branch_id and(p_after is null or id>p_after) order by id limit 51) q;
 elsif p_kind='custodians' then
  select (now() at time zone timezone)::date into today from core.legal_entities where tenant_id=p_tenant_id and id=p_legal_entity_id;
  select coalesce(jsonb_agg(jsonb_build_object('id',q.id,'code',q.code,'name',q.display_name) order by q.id),'[]') into items from(select * from people.employees e
   where tenant_id=p_tenant_id and legal_entity_id=p_legal_entity_id and(p_after is null or id>p_after) and exists(select 1 from people.employment_assignments a
    where a.employee_id=e.id and a.tenant_id=e.tenant_id and a.legal_entity_id=e.legal_entity_id and a.branch_id=p_branch_id
    and a.start_date<=today and(a.end_date_exclusive is null or a.end_date_exclusive>today)
    and exists(select 1 from people.employment_spells s where s.id=a.spell_id and s.tenant_id=a.tenant_id and s.legal_entity_id=a.legal_entity_id
     and s.employee_id=a.employee_id and s.start_date<=today and(s.end_date_exclusive is null or s.end_date_exclusive>today))) order by id limit 51) q;
 elsif p_kind in('asset','expense','equity','revenue') then
  select coalesce(jsonb_agg(jsonb_build_object('id',q.id,'code',q.code,'name',q.name,'kind',q.account_type,'currency_code',q.currency_code,'version',q.version) order by q.id),'[]') into items
   from(select * from finance.accounts a where tenant_id=p_tenant_id and legal_entity_id=p_legal_entity_id and status='active' and is_posting and account_type=p_kind
    and(currency_code is null or currency_code=(select e.currency_code from core.legal_entities e where e.tenant_id=p_tenant_id and e.id=p_legal_entity_id))
    and(p_after is null or id>p_after) and not exists(select 1 from finance.posting_mappings m where m.tenant_id=a.tenant_id and m.legal_entity_id=a.legal_entity_id
     and m.account_id=a.id and m.purpose in('receivable_control','payable_control')) order by id limit 51) q;
 else raise exception using errcode='22023',message='ASSET_PICKER_INVALID';end if;
 return jsonb_build_object('tenant_id',p_tenant_id,'legal_entity_id',p_legal_entity_id,'branch_id',p_branch_id,'kind',p_kind,'items',items-50,
  'next_cursor',case when jsonb_array_length(items)>50 then items->49->>'id' end);
end $$;
create function api.assets_own_receipt(p_tenant_id uuid,p_legal_entity_id uuid,p_branch_id uuid,p_idempotency_key uuid,p_action text)
returns jsonb language plpgsql stable security definer set search_path='' as $$declare r core.command_receipts%rowtype;cap text;begin
 cap:=case p_action when 'location' then 'assets.configure' when 'opening' then 'assets.prepare' when 'propose' then 'assets.prepare'
  when 'cancel' then 'assets.prepare' when 'approve' then 'assets.approve' when 'post' then 'assets.post'
  when 'depreciate' then 'assets.depreciate' when 'reverse' then 'assets.reverse' end;
 perform assets.require_access(p_tenant_id,p_legal_entity_id,p_branch_id,cap,true);
 select * into r from core.command_receipts where tenant_id=p_tenant_id and legal_entity_id=p_legal_entity_id and branch_id=p_branch_id
  and actor_id=auth.uid() and idempotency_key=p_idempotency_key and command_name='assets.'||p_action;
 if r.source_context->>'transfer_branch_id' is not null then
  perform assets.require_access(p_tenant_id,p_legal_entity_id,p_branch_id,'assets.transfer',true);
  perform assets.require_access(p_tenant_id,p_legal_entity_id,(r.source_context->>'transfer_branch_id')::uuid,'assets.transfer',true);
 end if;
 return case when r.id is null then null else jsonb_build_object('command_id',r.command_id,'idempotency_key',r.idempotency_key,
  'request_hash',r.request_hash,'response',r.response) end;
end $$;
revoke all on all functions in schema assets from public,anon,authenticated;
revoke all on function api.assets_authorize(uuid,uuid,uuid,text),api.assets_command(uuid,uuid,uuid,uuid,uuid,timestamptz,jsonb,bigint),
 api.assets_register(uuid,uuid,uuid,uuid),api.assets_detail(uuid,uuid,uuid,uuid,text,uuid),api.assets_schedule(uuid,uuid,uuid,uuid,uuid,integer),
 api.assets_pickers(uuid,uuid,uuid,text,uuid),api.assets_own_receipt(uuid,uuid,uuid,uuid,text) from public,anon,authenticated;
grant execute on function api.assets_authorize(uuid,uuid,uuid,text),api.assets_command(uuid,uuid,uuid,uuid,uuid,timestamptz,jsonb,bigint),
 api.assets_register(uuid,uuid,uuid,uuid),api.assets_detail(uuid,uuid,uuid,uuid,text,uuid),api.assets_schedule(uuid,uuid,uuid,uuid,uuid,integer),
 api.assets_pickers(uuid,uuid,uuid,text,uuid),api.assets_own_receipt(uuid,uuid,uuid,uuid,text) to authenticated;

create temporary table asset_assertions(message text);
grant insert on asset_assertions to authenticated,service_role;
-- Included only inside a caller-owned BEGIN ... ROLLBACK. Never an owner bootstrap.
create function pg_temp.wid(p text) returns uuid language sql immutable as
  $$select md5('wave4-integrated-rollback-20260926:'||p)::uuid$$;
create function pg_temp.wdate() returns date language sql stable as
  $$select (now() at time zone 'Asia/Colombo')::date$$;
create function pg_temp.wactor(p text,p_aal text default 'aal2') returns void language plpgsql as $$begin
  perform set_config('request.jwt.claims',jsonb_build_object('sub',pg_temp.wid(p),'role','authenticated','aal',p_aal)::text,true);
  perform set_config('request.jwt.claim.sub',pg_temp.wid(p)::text,true);
end $$;
insert into auth.users(id,instance_id,aud,role,email,encrypted_password,email_confirmed_at,created_at,updated_at)
select pg_temp.wid(x),'00000000-0000-0000-0000-000000000000','authenticated','authenticated',
  x||'@wave4.rollback.jentra.test','',now(),now(),now()
from unnest(array['creator','reviewer','reader','branch-manager','outsider']) x;
insert into core.tenants(id,name,slug,created_by) values
  (pg_temp.wid('tenant'),'Wave 4 Rollback','w4-integrated-rollback',pg_temp.wid('creator')),
  (pg_temp.wid('other-tenant'),'Other Rollback','w4-other-integrated-rollback',pg_temp.wid('outsider'));
insert into core.legal_entities(id,tenant_id,name,code,currency_code,timezone,rounding_scale,created_by) values
  (pg_temp.wid('entity'),pg_temp.wid('tenant'),'Synthetic Operations','W4OPS','LKR','Asia/Colombo',2,pg_temp.wid('creator')),
  (pg_temp.wid('entity2'),pg_temp.wid('tenant'),'Other Operations','W4OTHER','LKR','Asia/Colombo',2,pg_temp.wid('creator'));
insert into core.branches(id,tenant_id,legal_entity_id,name,code,created_by) values
  (pg_temp.wid('branch'),pg_temp.wid('tenant'),pg_temp.wid('entity'),'Head Office','HQ',pg_temp.wid('creator')),
  (pg_temp.wid('branch2'),pg_temp.wid('tenant'),pg_temp.wid('entity'),'Second Branch','B2',pg_temp.wid('creator')),
  (pg_temp.wid('entity2-branch'),pg_temp.wid('tenant'),pg_temp.wid('entity2'),'Other HQ','HQ',pg_temp.wid('creator'));
insert into billing.plans(code,name) values('w4_integrated_rollback','Wave 4 rollback');
insert into billing.plan_entitlements(plan_code,entitlement_code,enabled) values('w4_integrated_rollback','module.people',true);
insert into billing.tenant_subscriptions(tenant_id,plan_code,status,seats,trial_ends_at)
values(pg_temp.wid('tenant'),'w4_integrated_rollback','trialing',10,now()+interval '30 days');
insert into core.memberships(id,tenant_id,user_id,status)
select pg_temp.wid(x||'.membership'),pg_temp.wid('tenant'),pg_temp.wid(x),'active'
from unnest(array['creator','reviewer','reader','branch-manager']) x;
insert into core.roles(id,tenant_id,code,name,requires_mfa)
select pg_temp.wid(x||'.role'),pg_temp.wid('tenant'),x,x,true
from unnest(array['creator','reviewer','reader','branch-manager']) x;
insert into core.role_permissions(tenant_id,role_id,permission_code)
select pg_temp.wid('tenant'),pg_temp.wid(x||'.role'),p.code
from unnest(array['creator','reviewer','branch-manager']) x cross join core.permissions p
where p.module='people';
insert into core.role_permissions(tenant_id,role_id,permission_code)
select pg_temp.wid('tenant'),pg_temp.wid('reader.role'),p.code
from unnest(array['people.view','people.employees.view','people.employees.history.view',
  'people.calendars.view','people.organization.view']) p(code)
join core.permissions c on c.code=p.code;
insert into core.role_assignments(tenant_id,membership_id,role_id,legal_entity_id,branch_id,created_by)
select pg_temp.wid('tenant'),pg_temp.wid(x||'.membership'),pg_temp.wid(x||'.role'),pg_temp.wid('entity'),
  case when x in ('creator','reviewer') then null else pg_temp.wid('branch') end,pg_temp.wid('creator')
from unnest(array['creator','reviewer','reader','branch-manager']) x;
create function pg_temp.wemployee(p text) returns jsonb language sql as $$
  select api.people_employee_command(pg_temp.wid('tenant'),pg_temp.wid('entity'),pg_temp.wid('branch'),
    pg_temp.wid(p||'.create'),pg_temp.wid(p||'.create'),now(),jsonb_build_object('action','create',
      'id',pg_temp.wid(p),'code',upper(p),'display_name','Synthetic '||p,'work_email',null,
      'start_date',pg_temp.wdate()-10,'job_title','Synthetic role','employment_type','permanent'),0)
$$;
select pg_temp.wactor('creator');
select pg_temp.wemployee('employee');
select pg_temp.wemployee('manager');
select pg_temp.wemployee('third');
insert into people.work_calendars(id,tenant_id,legal_entity_id,code,name,created_by,updated_by)
values(pg_temp.wid('calendar'),pg_temp.wid('tenant'),pg_temp.wid('entity'),'W4CAL','Synthetic Calendar',pg_temp.wid('creator'),pg_temp.wid('creator'));
insert into people.work_calendar_versions(id,tenant_id,legal_entity_id,calendar_id,start_date,end_date_exclusive,
  timezone,weekly_intervals,date_overrides,published_by)
values(pg_temp.wid('calendar-version'),pg_temp.wid('tenant'),pg_temp.wid('entity'),pg_temp.wid('calendar'),
  pg_temp.wdate()-10,pg_temp.wdate()+400,'Asia/Colombo',
  jsonb_build_array(jsonb_build_object(
    'day_of_week',extract(isodow from pg_temp.wdate())::integer,
    'start_minute',540,'end_minute',1020,'end_day_offset',0)),
  '[]',pg_temp.wid('creator'));

-- Governed synthetic fixed-asset candidate. Included only in BEGIN/ROLLBACK.
create extension if not exists pgtap with schema extensions;
set local search_path=extensions,public,pg_catalog;
select no_plan();
create temporary table asset_client_samples(label text primary key,body jsonb not null);
create function pg_temp.asset_capture(label text,k text default 'a',b text default 'branch') returns void language plpgsql as $$
declare item jsonb; section text;begin
 foreach section in array array['books','effects','proposals'] loop
  item:=api.assets_detail(pg_temp.wid('tenant'),pg_temp.wid('entity'),pg_temp.wid(b),pg_temp.wid('asset.'||k),section,null);
  insert into asset_client_samples values(label||'.'||section,item);
 end loop;
end $$;
insert into asset_assertions select is((select count(*)::integer from pg_class c join pg_namespace n on n.oid=c.relnamespace
 where n.nspname='assets' and c.relkind='r' and c.relrowsecurity and c.relforcerowsecurity),8,
 'all eight asset tables are forced RLS');
insert into asset_assertions select is(assets.round_even(0.005,2),0::numeric,'asset exact even tie');
insert into asset_assertions select is(assets.round_even(0.015,2),0.02::numeric,'asset exact odd tie');
insert into asset_assertions select is(assets.ratio(99999999999999999999::numeric*9007199254740991-1,9007199254740991,6),99999999999999999999::numeric,
 'large rational quotient does not acquire a rounded division increment');
insert into asset_assertions select is((assets.schedule('0.03','0','0','0',5,'straight_line',1,1,2,'2026-01-01')->4->>'depreciation'),
 '0.010000','asset tiny final residue conserves exactly');
insert into asset_assertions select ok(not exists(select 1 from pg_class c join pg_namespace n on n.oid=c.relnamespace
 where n.nspname='assets' and c.relkind='r' and has_table_privilege('authenticated',c.oid,'SELECT')),'no direct asset table reads');
insert into asset_assertions select ok(not exists(select 1 from pg_proc p join pg_namespace n on n.oid=p.pronamespace
 where n.nspname='assets' and has_function_privilege('authenticated',p.oid,'EXECUTE')),'asset helpers denied to authenticated clients');
insert into asset_assertions select throws_ok($q$select assets.schedule('1','0','0','2',3,'straight_line',1,1,2,'2026-01-01')$q$,
 '22023','ASSET_BOOK_INVALID','residual exceeds carrying');
insert into asset_assertions select throws_ok($q$select assets.schedule('1.001','0','0','0',3,'straight_line',1,1,2,'2026-01-01')$q$,
 '22023','ASSET_BOOK_INVALID','unrepresentable currency precision rejected');
insert into asset_assertions select is(assets.schedule('1000','0','0','100',3,'reducing_balance',1,5,2,'2026-01-01')->2->>'depreciation',
 '540.000000','exact declining balance final residue');
insert into asset_assertions select is(assets.schedule('1000','200','300','100',2,'straight_line',1,1,2,'2026-01-01')->1->>'accumulated_closing',
 '600.000000','impairment stays separate from depreciation history');
insert into billing.plan_entitlements(plan_code,entitlement_code,enabled) values('w4_integrated_rollback','module.assets',true);
insert into core.role_permissions(tenant_id,role_id,permission_code)
 select pg_temp.wid('tenant'),pg_temp.wid(x||'.role'),p.code from unnest(array['creator','reviewer','branch-manager']) x
 cross join core.permissions p where p.module='assets';
insert into core.role_permissions(tenant_id,role_id,permission_code) values(pg_temp.wid('tenant'),pg_temp.wid('reader.role'),'assets.view');
insert into finance.accounts(id,tenant_id,legal_entity_id,code,name,account_type,normal_balance,created_by,updated_by)
 select pg_temp.wid('asset.account.'||x),pg_temp.wid('tenant'),pg_temp.wid('entity'),upper(x),'Synthetic asset '||x,
 case when x in('cost','accum','impair','bank') then 'asset' when x in('expense','loss') then 'expense' when x='gain' then 'revenue' else 'equity' end,
 case when x in('accum','impair','gain','offset','surplus') then 'credit' else 'debit' end,pg_temp.wid('creator'),pg_temp.wid('creator')
 from unnest(array['cost','accum','impair','bank','expense','loss','gain','offset','surplus']) x;
insert into finance.fiscal_periods(id,tenant_id,legal_entity_id,name,start_date,end_date,created_by,updated_by)
 values(pg_temp.wid('asset.period'),pg_temp.wid('tenant'),pg_temp.wid('entity'),'Synthetic asset period',pg_temp.wdate()-400,pg_temp.wdate()+400,
 pg_temp.wid('creator'),pg_temp.wid('creator'));
insert into core.document_sequences(tenant_id,legal_entity_id,branch_id,document_type,prefix,created_by,updated_by)
 select pg_temp.wid('tenant'),pg_temp.wid('entity'),pg_temp.wid(x),'journal_entry','SYNTHETIC-ASSET-'||x||'-',pg_temp.wid('creator'),pg_temp.wid('creator')
 from unnest(array['branch','branch2']) x;
create function pg_temp.acmd(payload jsonb,v bigint,k text,b text default 'branch') returns jsonb language sql as $$
 select api.assets_command(pg_temp.wid('tenant'),pg_temp.wid('entity'),pg_temp.wid(b),pg_temp.wid('asset.command.'||k),
  pg_temp.wid('asset.command.'||k),now(),payload,v) $$;
create function pg_temp.abook(resid text default '100',months integer default 3) returns jsonb language sql as $$
 select jsonb_build_object('residual',resid,'remaining_months',months,'method','straight_line','convention','in_service_month',
  'rate_numerator',1,'rate_denominator',1,'precision',2,'expense_account_id',pg_temp.wid('asset.account.expense')) $$;
create function pg_temp.aopening(k text default 'a') returns jsonb language sql as $$
 select jsonb_build_object('action','opening','id',pg_temp.wid('asset.'||k),'proposal_id',pg_temp.wid('asset.proposal.'||k),
 'source_id',pg_temp.wid('asset.source.'||k),'source_reference','SYNTHETIC-'||upper(k),'code',upper(k),'name','Synthetic asset '||k,
 'ownership','Synthetic owned','currency_code','LKR','in_service',(date_trunc('month',pg_temp.wdate())-interval '3 months')::date,
 'location_id',pg_temp.wid('asset.location.branch'),'custodian_id',null,'cost','1000','opening_accumulated','400',
 'cost_components',jsonb_build_array(jsonb_build_object('code','OPENING','name','Governed synthetic opening','amount','1000')),
 'cost_account_id',pg_temp.wid('asset.account.cost'),'accumulated_account_id',pg_temp.wid('asset.account.accum'),
 'impairment_account_id',pg_temp.wid('asset.account.impair'),'offset_account_id',pg_temp.wid('asset.account.offset'),
 'book',pg_temp.abook(),'posting_date',(date_trunc('month',pg_temp.wdate())-interval '3 months')::date,'reason','Synthetic governed opening') $$;
create function pg_temp.astate(k text default 'a') returns jsonb language sql as $$select assets.summary(pg_temp.wid('asset.'||k)) $$;
create function pg_temp.aproposal(action text,k text default 'a') returns jsonb language sql as $$
 select jsonb_build_object('action',action,'id',r.id,'proposal_id',p.id,'digest',p.digest,'reason','Synthetic exact proposal '||action)
 from assets.register r join assets.proposals p on p.id=r.current_proposal_id where r.id=pg_temp.wid('asset.'||k) $$;
create function pg_temp.adep(k text default 'a') returns jsonb language sql as $$
 select jsonb_build_object('action','depreciate','id',r.id,'book_id',r.current_book_id,'period_index',r.posted_periods+1,'reason','Synthetic exact period')
 from assets.register r where r.id=pg_temp.wid('asset.'||k) $$;
create function pg_temp.areverse(k text default 'a') returns jsonb language sql as $$
 select jsonb_build_object('action','reverse','id',r.id,'effect_id',r.last_effect_id,'reason','Synthetic original effect reversal')
 from assets.register r where r.id=pg_temp.wid('asset.'||k) $$;
create function pg_temp.aprop(kind text,extra jsonb,k text default 'a',proposal text default 'p') returns jsonb language sql as $$
 select jsonb_build_object('action','propose','id',pg_temp.wid('asset.'||k),'proposal_id',pg_temp.wid('asset.proposal.'||proposal),
  'kind',kind,'posting_date',pg_temp.wdate(),'reason','Synthetic governed '||kind)||extra $$;
select pg_temp.wactor('creator');
select pg_temp.acmd(jsonb_build_object('action','location','id',pg_temp.wid('asset.location.branch'),'code','LAB','name','Synthetic lab','reason','Synthetic location'),0,'location');
select pg_temp.acmd(jsonb_build_object('action','location','id',pg_temp.wid('asset.location.branch2'),'code','LAB','name','Synthetic second lab','reason','Synthetic location'),0,'location2','branch2');
insert into asset_assertions select is(pg_temp.acmd(pg_temp.aopening(),0,'opening')->'entity'->>'status','draft','opening creates no authoritative cost');
insert into asset_assertions select is(pg_temp.astate()->>'cost','0.000000','cost remains zero until independent approval');
select pg_temp.asset_capture('opening');
insert into asset_assertions select is(api.assets_detail(pg_temp.wid('tenant'),pg_temp.wid('entity'),pg_temp.wid('branch'),pg_temp.wid('asset.a'),'books',null)->'labels'->>'expense_account_id',
 'EXPENSE · Synthetic asset expense','approval review exposes the exact scoped named expense mapping');
insert into asset_assertions select is(assets.label(pg_temp.wid('other-tenant'),pg_temp.wid('entity'),'account',pg_temp.wid('asset.account.expense')),null::text,
 'named reference projection cannot read another tenant');
insert into asset_assertions select is(jsonb_typeof(api.assets_detail(pg_temp.wid('tenant'),pg_temp.wid('entity'),pg_temp.wid('branch'),pg_temp.wid('asset.a'),'books',null)->'opening'->'cost'),
 'string','opening wire amounts retain exact decimal strings');
insert into asset_assertions select throws_ok($q$select pg_temp.acmd(pg_temp.aopening('currency')||'{"currency_code":"USD"}',0,'currency-mismatch')$q$,
 '55000','ASSET_BASE_CURRENCY_CHANGED','opening cannot reinterpret a client-frozen currency');
insert into asset_assertions select is(pg_temp.acmd(pg_temp.aopening(),0,'opening')->'entity'->>'version','1','exact opening replay is stable');
insert into asset_assertions select throws_ok($q$select pg_temp.acmd(pg_temp.aopening()||'{"name":"Changed body"}',0,'opening')$q$,
 '22023','IDEMPOTENCY_MISMATCH','changed opening body cannot replay');
insert into asset_assertions select throws_ok($q$select pg_temp.acmd(pg_temp.aopening('b')||'{"source_reference":"synthetic-a"}',0,'duplicate')$q$,
 '55000','ASSET_SOURCE_ALREADY_OWNED','opening evidence cannot be owned twice even under a new source UUID');
insert into asset_assertions select throws_ok($q$select pg_temp.acmd(pg_temp.aproposal('post'),1,'unapproved')$q$,
 '55000','ASSET_APPROVAL_REQUIRED','capitalization requires exact approval');
insert into asset_assertions select throws_ok($q$select pg_temp.acmd(pg_temp.aproposal('approve'),1,'self-approve')$q$,
 '42501','ASSET_INDEPENDENT_APPROVAL_REQUIRED','preparer cannot approve own opening');
select pg_temp.wactor('creator','aal1');
insert into asset_assertions select throws_ok($q$select pg_temp.acmd(pg_temp.aopening(),0,'opening')$q$,'42501','Permission denied or multi-factor authentication required.','MFA rechecked before replay');
select pg_temp.wactor('reviewer');
insert into asset_assertions select is(pg_temp.acmd(pg_temp.aproposal('approve'),1,'approve')->'entity'->>'version','2','independent approval binds exact proposal');
select pg_temp.wactor('creator');
insert into asset_assertions select is(pg_temp.acmd(pg_temp.aproposal('post'),2,'capitalize')->'entity'->>'status','active','governed opening posts atomically');
insert into asset_assertions select is(pg_temp.astate()->>'carrying','600.000000','opening cost minus original accumulation');
insert into asset_assertions select is((select count(*)::integer from assets.schedules where book_id=pg_temp.wid('asset.proposal.a')),3,'original immutable schedule materialized');
insert into asset_assertions select is((select sum(base_debit-base_credit) from finance.journal_lines where journal_entry_id=(select journal_id from assets.effects where kind='capitalize')),0::numeric,'capitalization journal balanced');
insert into asset_assertions select is(pg_temp.acmd(pg_temp.adep(),3,'dep1')->'entity'->>'version','4','first period posts once');
insert into asset_assertions select is(pg_temp.astate()->>'accumulated','566.670000','exact cumulative allocation matches Dart');
select pg_temp.asset_capture('active');
insert into asset_assertions select throws_ok($q$select pg_temp.acmd(pg_temp.adep(),3,'stale-period')$q$,'40001','VERSION_CONFLICT','stale asset version cannot post');
insert into asset_assertions select throws_ok($q$select pg_temp.acmd(jsonb_build_object('action','reverse','id',pg_temp.wid('asset.a'),'effect_id',
 (select id from assets.effects where kind='capitalize'),'reason','Synthetic reversal'),4,'dependent-reverse')$q$,
 '55000','ASSET_DEPENDENT_EFFECT_BLOCKS_REVERSAL','later depreciation blocks capitalization reversal');
insert into asset_assertions select throws_ok($q$update assets.schedules set facts='{}' where book_id=pg_temp.wid('asset.proposal.a')$q$,
 '55000','ASSET_HISTORY_IMMUTABLE','schedule facts cannot be overwritten');
insert into asset_assertions select is(pg_temp.acmd(pg_temp.aprop('book_revision',jsonb_build_object('book',pg_temp.abook('100',2)),proposal=>'book2'),4,'book2-propose')->'entity'->>'version','5','prospective book proposed');
insert into asset_assertions select throws_ok($q$select pg_temp.acmd(pg_temp.adep(),5,'blocked-period')$q$,'55000','ASSET_SCHEDULE_STALE','pending book freezes competing depreciation');
select pg_temp.wactor('reviewer');select pg_temp.acmd(pg_temp.aproposal('approve'),5,'book2-approve');
select pg_temp.wactor('creator');select pg_temp.acmd(pg_temp.aproposal('post'),6,'book2-post');
insert into asset_assertions select is((select basis->>'opening_accumulated' from assets.books where id=pg_temp.wid('asset.proposal.book2')),'566.670000','prospective book retains posted accumulation');
insert into asset_assertions select is((select basis->>'start_date' from assets.books where id=pg_temp.wid('asset.proposal.book2')),
 ((date_trunc('month',pg_temp.wdate())-interval '2 months')::date)::text,'prospective book begins at first unposted month');
select pg_temp.acmd(pg_temp.adep(),7,'book2-dep');
insert into asset_assertions select is(pg_temp.astate()->>'accumulated','733.330000','prospective half-even amount preserves total');
select pg_temp.acmd(pg_temp.areverse(),8,'book2-dep-reverse');
insert into asset_assertions select is(pg_temp.astate()->>'accumulated','566.670000','original period reversal restores exact prior accumulation');
insert into asset_assertions select throws_ok($q$select pg_temp.acmd(pg_temp.adep(),9,'same-period-again')$q$,
 '55000','ASSET_REBOOK_AFTER_REVERSAL_REQUIRED','reversed period requires a new governed book');
select pg_temp.acmd(pg_temp.areverse(),9,'book2-reverse');
insert into asset_assertions select is(pg_temp.astate()->>'book_id',pg_temp.wid('asset.proposal.a')::text,'book reversal restores original schedule identity');
select pg_temp.acmd(pg_temp.aprop('impair',jsonb_build_object('amount','100','loss_account_id',pg_temp.wid('asset.account.loss')),proposal=>'impair'),10,'impair-propose');
select pg_temp.wactor('reviewer');select pg_temp.acmd(pg_temp.aproposal('approve'),11,'impair-approve');
select pg_temp.wactor('creator');select pg_temp.acmd(pg_temp.aproposal('post'),12,'impair-post');
select pg_temp.asset_capture('impaired');
insert into asset_assertions select is(pg_temp.astate()->>'impairment','100.000000','impairment reserve is explicit');
insert into asset_assertions select is(pg_temp.astate()->>'accumulated','566.670000','impairment does not rewrite depreciation history');
select pg_temp.acmd(pg_temp.areverse(),13,'impair-reverse');
insert into asset_assertions select is(pg_temp.astate()->>'impairment','0.000000','original impairment reversal restores reserve');
select pg_temp.acmd(pg_temp.aprop('revalue',jsonb_build_object('cost','1100','surplus_account_id',pg_temp.wid('asset.account.surplus'),
 'loss_account_id',pg_temp.wid('asset.account.loss')),proposal=>'revalue'),14,'revalue-propose');
select pg_temp.wactor('reviewer');select pg_temp.acmd(pg_temp.aproposal('approve'),15,'revalue-approve');
select pg_temp.wactor('creator');select pg_temp.acmd(pg_temp.aproposal('post'),16,'revalue-post');
insert into asset_assertions select is(pg_temp.astate()->>'cost','1100.000000','configured revaluation retains revised gross cost');
select pg_temp.acmd(pg_temp.areverse(),17,'revalue-reverse');
insert into asset_assertions select is(pg_temp.astate()->>'cost','1000.000000','original revaluation reversal restores cost');
select pg_temp.acmd(pg_temp.aprop('dispose',jsonb_build_object('proceeds','500','proceeds_account_id',pg_temp.wid('asset.account.bank'),
 'gain_account_id',pg_temp.wid('asset.account.gain'),'loss_account_id',pg_temp.wid('asset.account.loss')),proposal=>'dispose'),18,'dispose-propose');
select pg_temp.wactor('reviewer');select pg_temp.acmd(pg_temp.aproposal('approve'),19,'dispose-approve');
select pg_temp.wactor('creator');select pg_temp.acmd(pg_temp.aproposal('post'),20,'dispose-post');
select pg_temp.asset_capture('disposed');
insert into asset_assertions select is(pg_temp.astate()->>'status','disposed','disposal commits with original cost and accumulation');
insert into asset_assertions select is((select sum(base_credit-base_debit) from finance.journal_lines where account_id=pg_temp.wid('asset.account.gain')),66.67::numeric,'exact disposal gain matches original carrying');
insert into asset_assertions select throws_ok($q$select pg_temp.acmd(pg_temp.adep(),21,'disposed-dep')$q$,'55000','ASSET_SCHEDULE_STALE','disposed asset denies depreciation');
select pg_temp.acmd(pg_temp.areverse(),21,'dispose-reverse');
insert into asset_assertions select is(pg_temp.astate()->>'status','active','original disposal reversal restores active state');
insert into asset_assertions select is(pg_temp.astate()->>'carrying','433.330000','original disposal reversal restores exact carrying');
-- Both branch authorities are required on original command and replay.
select pg_temp.wactor('branch-manager');
insert into asset_assertions select throws_ok($q$select pg_temp.acmd(pg_temp.aprop('transfer',jsonb_build_object('destination_branch_id',pg_temp.wid('branch2'),
 'location_id',pg_temp.wid('asset.location.branch2'),'custodian_id',null),proposal=>'transfer'),22,'narrow-transfer')$q$,
 '42501','Permission denied or multi-factor authentication required.','source-only branch role cannot authorize destination');
select pg_temp.wactor('creator');
select pg_temp.acmd(pg_temp.aprop('transfer',jsonb_build_object('destination_branch_id',pg_temp.wid('branch2'),
 'location_id',pg_temp.wid('asset.location.branch2'),'custodian_id',null),proposal=>'transfer'),22,'transfer-propose');
select pg_temp.wactor('reviewer');select pg_temp.acmd(pg_temp.aproposal('approve'),23,'transfer-approve');
select pg_temp.wactor('creator');
create temporary table asset_saved_requests as select pg_temp.aproposal('post') as transfer_post;
grant select on asset_saved_requests to authenticated;
insert into asset_assertions select is(pg_temp.acmd((select transfer_post from asset_saved_requests),24,'transfer-post')->'entity'->>'current_branch_id',
 pg_temp.wid('branch2')::text,'transfer retains command branch and resulting accountable branch separately');
insert into asset_assertions select is((api.assets_register(pg_temp.wid('tenant'),pg_temp.wid('entity'),pg_temp.wid('branch2'))->'items'->0->>'original_branch_id'),
 pg_temp.wid('branch')::text,'original ownership branch survives transfer');
-- Narrow the creator to its source branch after completion; destination replay must deny.
update core.role_assignments set branch_id=pg_temp.wid('branch') where role_id=pg_temp.wid('creator.role');
insert into asset_assertions select throws_ok($q$select pg_temp.acmd((select transfer_post from asset_saved_requests),24,'transfer-post')$q$,
 '42501','Permission denied or multi-factor authentication required.','revoked destination authority denies completed transfer replay');
insert into asset_assertions select throws_ok($q$select api.assets_own_receipt(pg_temp.wid('tenant'),pg_temp.wid('entity'),pg_temp.wid('branch'),
 pg_temp.wid('asset.command.transfer-post'),'post')$q$,'42501','Permission denied or multi-factor authentication required.',
 'receipt lookup rechecks original destination transfer authority');
update core.role_assignments set branch_id=null where role_id=pg_temp.wid('creator.role');
select pg_temp.acmd(pg_temp.areverse(),25,'transfer-reverse','branch2');
insert into asset_assertions select is(pg_temp.astate()->>'branch_id',pg_temp.wid('branch')::text,'original transfer reversal restores branch and location');
insert into asset_assertions select is(pg_temp.astate()->>'location_id',pg_temp.wid('asset.location.branch')::text,'original location restored exactly');
update finance.fiscal_periods set state='soft_locked' where id=pg_temp.wid('asset.period');
insert into asset_assertions select throws_ok($q$select pg_temp.acmd(pg_temp.adep(),26,'closed-dep')$q$,'55000','PERIOD_CLOSED','closed period denies exact scheduled posting');
insert into asset_assertions select throws_ok($q$select pg_temp.acmd(pg_temp.areverse(),26,'closed-reverse')$q$,'55000','PERIOD_CLOSED','closed original period denies reversal');
insert into asset_assertions select is(pg_temp.astate()->>'accumulated','566.670000','closed-period failures preserve all balances');
update finance.fiscal_periods set state='open' where id=pg_temp.wid('asset.period');
select pg_temp.acmd(pg_temp.adep(),26,'a-dep2');
select pg_temp.acmd(pg_temp.adep(),27,'a-dep3');
insert into asset_assertions select is(pg_temp.astate()->>'carrying','100.000000','original full life preserves exact residual after correction chain');
-- A late failure must roll back journal numbering, books, asset state and effects.
select pg_temp.acmd(pg_temp.aopening('b'),0,'b-opening');
select pg_temp.wactor('reviewer');select pg_temp.acmd(pg_temp.aproposal('approve','b'),1,'b-approve');
select pg_temp.wactor('creator');
create temporary table asset_late_before as select to_jsonb(s) as sequence from core.document_sequences s
 where tenant_id=pg_temp.wid('tenant') and branch_id=pg_temp.wid('branch') and document_type='journal_entry';
create function pg_temp.asset_fail_outbox() returns trigger language plpgsql as $$begin
 if new.topic='assets.post' then raise exception using errcode='P0001',message='SYNTHETIC_ASSET_LATE_FAIL';end if;return new;end $$;
create trigger asset_synthetic_late_fail before insert on core.outbox_events for each row execute function pg_temp.asset_fail_outbox();
insert into asset_assertions select throws_ok($q$select pg_temp.acmd(pg_temp.aproposal('post','b'),2,'b-post')$q$,
 'P0001','SYNTHETIC_ASSET_LATE_FAIL','late outbox failure aborts entire capitalization');
insert into asset_assertions select is(pg_temp.astate('b')->>'cost','0.000000','late failure restores provisional zero cost');
insert into asset_assertions select is(pg_temp.astate('b')->>'version','2','late failure restores approved version');
insert into asset_assertions select is((select count(*)::integer from assets.books where asset_id=pg_temp.wid('asset.b')),0,'late failure leaves no materialized books');
insert into asset_assertions select is((select count(*)::integer from assets.effects where asset_id=pg_temp.wid('asset.b')),0,'late failure leaves no authoritative effects');
insert into asset_assertions select is((select to_jsonb(s) from core.document_sequences s where tenant_id=pg_temp.wid('tenant') and branch_id=pg_temp.wid('branch') and document_type='journal_entry'),
 (select sequence from asset_late_before),'late failure rolls back document numbering');
drop trigger asset_synthetic_late_fail on core.outbox_events;
select pg_temp.acmd(pg_temp.aproposal('post','b'),2,'b-post');
select pg_temp.acmd(pg_temp.areverse('b'),3,'b-reverse');
insert into asset_assertions select is(pg_temp.astate('b')->>'status','reversed','opening reversal retains terminal ownership history');
insert into asset_assertions select throws_ok($q$select pg_temp.acmd(pg_temp.aopening('c')||'{"source_reference":"SYNTHETIC-B"}',0,'b-source-again')$q$,
 '55000','ASSET_SOURCE_ALREADY_OWNED','reversal does not release the same opening evidence for another capitalization');
-- Final schedule conservation and explicit zero periods against the installed journal.
select pg_temp.acmd(pg_temp.aopening('tiny')||jsonb_build_object('cost','0.03','opening_accumulated','0',
 'cost_components',jsonb_build_array(jsonb_build_object('code','TINY','name','Synthetic tiny value','amount','0.03')),
 'book',pg_temp.abook('0',5),'in_service',(date_trunc('month',pg_temp.wdate())-interval '6 months')::date,
 'posting_date',(date_trunc('month',pg_temp.wdate())-interval '6 months')::date),0,'tiny-opening');
select pg_temp.wactor('reviewer');select pg_temp.acmd(pg_temp.aproposal('approve','tiny'),1,'tiny-approve');
select pg_temp.wactor('creator');select pg_temp.acmd(pg_temp.aproposal('post','tiny'),2,'tiny-post');
select pg_temp.acmd(pg_temp.adep('tiny'),3,'tiny-dep1');
select pg_temp.acmd(pg_temp.adep('tiny'),4,'tiny-dep2');
select pg_temp.acmd(pg_temp.adep('tiny'),5,'tiny-dep3');
select pg_temp.acmd(pg_temp.adep('tiny'),6,'tiny-dep4');
select pg_temp.acmd(pg_temp.adep('tiny'),7,'tiny-dep5');
insert into asset_assertions select is(pg_temp.astate('tiny')->>'carrying','0.000000','final period conserves exact depreciable value');
insert into asset_assertions select is((select count(*)::integer from assets.effects where asset_id=pg_temp.wid('asset.tiny') and kind='depreciate'),5,'zero periods are retained facts');
insert into asset_assertions select is((select count(*)::integer from assets.effects where asset_id=pg_temp.wid('asset.tiny') and kind='depreciate' and journal_id is null),2,'zero periods do not fabricate zero journals');
insert into asset_assertions select is((select sum(base_debit) from finance.journal_lines where account_id=pg_temp.wid('asset.account.expense') and source_line_id in
 (select id from assets.effects where asset_id=pg_temp.wid('asset.tiny') and kind='depreciate')),0.03::numeric,'tiny journals conserve original cost');
insert into asset_assertions select throws_ok($q$select pg_temp.acmd(pg_temp.adep('tiny'),8,'tiny-beyond-life')$q$,'55000','ASSET_SCHEDULE_STALE','posting beyond final life rejected');
select pg_temp.acmd(pg_temp.aopening('paged')||jsonb_build_object('book',pg_temp.abook('100',1200)),0,'paged-opening');
select pg_temp.wactor('reviewer');select pg_temp.acmd(pg_temp.aproposal('approve','paged'),1,'paged-approve');
select pg_temp.wactor('creator');select pg_temp.acmd(pg_temp.aproposal('post','paged'),2,'paged-post');
insert into asset_assertions select is(jsonb_array_length(api.assets_schedule(pg_temp.wid('tenant'),pg_temp.wid('entity'),pg_temp.wid('branch'),pg_temp.wid('asset.paged'),
 pg_temp.wid('asset.proposal.paged'))->'items'),50,'1200-month schedule response remains bounded at 50');
insert into asset_assertions select is(api.assets_schedule(pg_temp.wid('tenant'),pg_temp.wid('entity'),pg_temp.wid('branch'),pg_temp.wid('asset.paged'),
 pg_temp.wid('asset.proposal.paged'))->>'next_cursor','50','ordinal schedule cursor identifies the final returned period');
insert into asset_assertions select is(api.assets_schedule(pg_temp.wid('tenant'),pg_temp.wid('entity'),pg_temp.wid('branch'),pg_temp.wid('asset.paged'),
 pg_temp.wid('asset.proposal.paged'),1150)->'items'->49->>'closing_carrying','100.000000','last bounded page retains original final residual');
insert into asset_assertions select is(api.assets_schedule(pg_temp.wid('tenant'),pg_temp.wid('entity'),pg_temp.wid('branch'),pg_temp.wid('asset.paged'),
 pg_temp.wid('asset.proposal.paged'),1150)->>'next_cursor',null::text,'terminal schedule page has no false continuation');
insert into asset_assertions select throws_ok($q$select api.assets_schedule(pg_temp.wid('tenant'),pg_temp.wid('entity'),pg_temp.wid('branch'),pg_temp.wid('asset.paged'),
 pg_temp.wid('asset.proposal.paged'),1201)$q$,'22023','ASSET_PAGE_INVALID','unbounded schedule cursor rejected');
insert into asset_assertions select is(api.assets_authorize(pg_temp.wid('tenant'),pg_temp.wid('entity'),pg_temp.wid('branch'),'assets.view')->>'procurement_provider','false','unimplemented procurement provider explicit');
insert into asset_assertions select throws_ok($q$select pg_temp.acmd(pg_temp.aopening('x')||'{"action":"procurement"}',0,'fake-procurement')$q$,
 '22023','ASSET_COMMAND_INVALID','invented procurement metadata cannot capitalize');
select pg_temp.wactor('branch-manager');
set local role authenticated;
insert into asset_assertions select throws_ok($q$select api.assets_register(pg_temp.wid('tenant'),pg_temp.wid('entity'),pg_temp.wid('branch2'))$q$,
 '42501','Permission denied or multi-factor authentication required.','authenticated branch actor cannot read other branch register');
insert into asset_assertions select throws_ok($q$select api.assets_register(pg_temp.wid('other-tenant'),pg_temp.wid('entity'),pg_temp.wid('branch'))$q$,
 '42501','Permission denied or multi-factor authentication required.','cross-tenant scope denied before data');
insert into asset_assertions select throws_ok($q$select count(*) from assets.register$q$,'42501',null,'authenticated direct asset table access denied');
reset role;
select pg_temp.wactor('creator');
update billing.plan_entitlements set enabled=false where plan_code='w4_integrated_rollback' and entitlement_code='module.assets';
insert into asset_assertions select throws_ok($q$select pg_temp.acmd(pg_temp.aopening(),0,'opening')$q$,'42501','ASSET_ENTITLEMENT_REQUIRED','entitlement rechecked before replay');
update billing.plan_entitlements set enabled=true where plan_code='w4_integrated_rollback' and entitlement_code='module.assets';
insert into asset_assertions select ok(not exists(select 1 from core.command_receipts where tenant_id=pg_temp.wid('tenant') and command_name like 'assets.%'
 and(response::text like '%600.000000%' or response::text like '%Synthetic owned%' or response::text like '%SYNTHETIC-A%')),'generic receipts contain no source/financial evidence');
insert into asset_assertions select ok(not exists(select 1 from audit.events where tenant_id=pg_temp.wid('tenant') and event_type like 'assets.%'
 and(after_context::text like '%600.000000%' or after_context::text like '%Synthetic owned%')),'generic audit contains no financial/ownership evidence');

do $$declare failed text;begin
 select string_agg(message,chr(10)) into failed from asset_assertions where message like 'not ok%';
 if failed is not null then raise exception using errcode='P0001',message=failed;end if;
end $$;
set constraints all immediate;
select * from finish(true);
select jsonb_object_agg(label,body order by label) as asset_client_samples from asset_client_samples;
rollback;