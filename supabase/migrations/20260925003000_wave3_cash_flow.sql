-- UNAPPLIED AC-320 indirect cash-flow candidate. Exercise only inside ROLLBACK.
-- Mappings are dated, versioned, immutable decisions. A report freezes the
-- mapping selected at its cutoff alongside posted journal evidence.
insert into core.permissions(code,module,description,privileged) values
 ('finance.cash_flow.configure','finance','Configure indirect cash-flow account classifications.',true)
on conflict(code) do nothing;
insert into core.role_permissions(tenant_id,role_id,permission_code)
select r.tenant_id,r.id,'finance.cash_flow.configure' from core.roles r
where r.code='tenant_owner' on conflict(role_id,permission_code) do nothing;

create table finance.cash_flow_mapping_events (
 id uuid primary key,tenant_id uuid not null,legal_entity_id uuid not null,
 account_id uuid not null,effective_date date not null,
 category text not null check(category in
  ('cash','noncash_adjustment','working_capital','investing','financing')),
 version bigint not null check(version>0),reason text not null
  check(length(trim(reason)) between 3 and 1000),
 created_by uuid not null references auth.users(id),created_at timestamptz not null default now(),
 unique(tenant_id,id),unique(tenant_id,legal_entity_id,account_id,version),
 unique(tenant_id,legal_entity_id,account_id,effective_date),
 foreign key(tenant_id,legal_entity_id,account_id)
  references finance.accounts(tenant_id,legal_entity_id,id)
);
create index cash_flow_mapping_lookup on finance.cash_flow_mapping_events
 (tenant_id,legal_entity_id,account_id,effective_date desc,version desc);
create index cash_flow_mapping_actor on finance.cash_flow_mapping_events(created_by);
alter table finance.cash_flow_mapping_events enable row level security;
alter table finance.cash_flow_mapping_events force row level security;
revoke all on finance.cash_flow_mapping_events from public,anon,authenticated;
create trigger immutable before update or delete on finance.cash_flow_mapping_events
 for each row execute function workflow.reject_history_mutation();

alter table finance.financial_reports drop constraint financial_reports_kind_check;
alter table finance.financial_reports add constraint financial_reports_kind_check
 check(kind in('trial_balance','profit_loss','balance_sheet','cash_flow'));

create function api.cash_flow_mapping_options(p_tenant_id uuid,p_legal_entity_id uuid,
 p_branch_id uuid,p_as_of date,p_after uuid default null) returns jsonb
language plpgsql stable security definer set search_path='' as $$
declare rows jsonb;cursor uuid;begin
 perform core.wave3_require_scope(p_tenant_id,'finance.view',p_legal_entity_id,null);
 perform core.wave3_require_scope(p_tenant_id,'finance.view',p_legal_entity_id,p_branch_id);
 if p_as_of is null or p_as_of>(clock_timestamp() at time zone 'UTC')::date then
  raise exception using errcode='22023',message='CASH_FLOW_DATE_INVALID';end if;
 select coalesce(jsonb_agg(to_jsonb(q) order by id),'[]') into rows from (
  select a.id,a.id account_id,a.code,a.name,a.account_type,a.status,
   m.id mapping_id,m.category,m.effective_date,m.version
  from finance.accounts a left join lateral (
   select id,category,effective_date,version from finance.cash_flow_mapping_events
   where tenant_id=p_tenant_id and legal_entity_id=p_legal_entity_id
    and account_id=a.id and effective_date<=p_as_of
   order by effective_date desc,version desc limit 1) m on true
  where a.tenant_id=p_tenant_id and a.legal_entity_id=p_legal_entity_id
   and a.is_posting and a.account_type in('asset','liability','equity')
   and (p_after is null or a.id>p_after)
  order by a.id limit 51)q;
 if jsonb_array_length(rows)>50 then cursor:=(rows->49->>'id')::uuid;rows:=rows-50;end if;
 return jsonb_build_object('tenant_id',p_tenant_id,'legal_entity_id',p_legal_entity_id,
  'branch_id',p_branch_id,'as_of',p_as_of,'items',rows,'next_cursor',cursor);
end$$;

create function api.configure_cash_flow_mapping(p_tenant_id uuid,p_legal_entity_id uuid,
 p_branch_id uuid,p_command_id uuid,p_idempotency_key uuid,p_client_timestamp timestamptz,
 p_payload jsonb,p_expected_entity_version bigint default null) returns jsonb
language plpgsql security definer set search_path='' as $$
declare v_id uuid:=(p_payload->>'id')::uuid;v_account uuid:=(p_payload->>'account_id')::uuid;
 v_date date:=(p_payload->>'effective_date')::date;v_category text:=p_payload->>'category';
 v_reason text:=trim(p_payload->>'reason');a finance.accounts%rowtype;
 v_version bigint;v_before jsonb;h text;r jsonb;result jsonb;req uuid:=gen_random_uuid();begin
 perform core.wave3_require_scope(p_tenant_id,'finance.cash_flow.configure',p_legal_entity_id,null);
 perform core.wave3_require_scope(p_tenant_id,'finance.cash_flow.configure',p_legal_entity_id,p_branch_id);
 if v_id is null or v_account is null or p_client_timestamp is null or v_date is null
  or v_date<date '2000-01-01' or v_date>(clock_timestamp() at time zone 'UTC')::date+365
  or v_category not in('cash','noncash_adjustment','working_capital','investing','financing')
  or v_category is null or length(v_reason) not between 3 and 1000 then
  raise exception using errcode='22023',message='CASH_FLOW_MAPPING_INPUT_INVALID';end if;
 h:=core.wave3_request_hash('finance.cashflow.mapping.configure',p_command_id,p_tenant_id,
  p_legal_entity_id,p_branch_id,p_payload,p_expected_entity_version);
 r:=core.wave3_replay(p_tenant_id,'finance.cashflow.mapping.configure',p_command_id,p_idempotency_key,h);
 if r is not null then return r;end if;
 select * into a from finance.accounts where tenant_id=p_tenant_id
  and legal_entity_id=p_legal_entity_id and id=v_account and status='active'
  and is_posting and account_type in('asset','liability','equity') for update;
 if not found then raise exception using errcode='22023',message='CASH_FLOW_ACCOUNT_INVALID';end if;
 if v_category='cash' and (a.account_type<>'asset' or not exists(
  select 1 from finance.cash_bank_accounts cb where cb.tenant_id=p_tenant_id
   and cb.legal_entity_id=p_legal_entity_id and cb.account_id=v_account)) then
  raise exception using errcode='22023',message='CASH_FLOW_CASH_ACCOUNT_INVALID';end if;
 select coalesce(max(version),0) into v_version from finance.cash_flow_mapping_events
  where tenant_id=p_tenant_id and legal_entity_id=p_legal_entity_id and account_id=v_account;
 perform core.wave3_assert_expected_version(v_version,p_expected_entity_version,'{}');
 select to_jsonb(m) into v_before from finance.cash_flow_mapping_events m
  where m.tenant_id=p_tenant_id and m.legal_entity_id=p_legal_entity_id
   and m.account_id=v_account order by m.version desc limit 1;
 if exists(select 1 from finance.cash_flow_mapping_events where tenant_id=p_tenant_id
  and legal_entity_id=p_legal_entity_id and account_id=v_account and effective_date=v_date) then
  raise exception using errcode='23505',message='CASH_FLOW_EFFECTIVE_DATE_EXISTS';end if;
 insert into finance.cash_flow_mapping_events(id,tenant_id,legal_entity_id,account_id,
  effective_date,category,version,reason,created_by)
 values(v_id,p_tenant_id,p_legal_entity_id,v_account,v_date,v_category,v_version+1,v_reason,auth.uid());
 result:=jsonb_build_object('id',v_id,'tenant_id',p_tenant_id,'legal_entity_id',p_legal_entity_id,
  'branch_id',p_branch_id,'account_id',v_account,'effective_date',v_date,
  'category',v_category,'version',v_version+1,'status','configured','reason',v_reason);
 return core.wave3_finish_command(p_tenant_id,'finance.cashflow.mapping.configure',p_command_id,
  'cash_flow_mapping',v_id,p_idempotency_key,h,v_before,result,p_legal_entity_id,p_branch_id,
  jsonb_build_object('account_id',v_account,'effective_date',v_date),
  jsonb_build_object('to_status','configured','account_id',v_account),
  jsonb_build_array(jsonb_build_object('topic','finance.cashflow.mapping.configured','payload',result)),
  '[]',req,req);
end$$;

-- Derive every cash-flow category from exact period movement. Revenue and
-- expense movement contributes profit; all other moving accounts need a
-- dated mapping. With complete mappings, accounting balance proves cash.
create function finance.cash_flow_totals(t uuid,e uuid,d date,account_rows jsonb)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare x jsonb;rows jsonb:='[]';unmapped jsonb:='[]';cat text;kind text;
 movement numeric;amount numeric;opening_cash numeric:=0;closing_cash numeric:=0;
 profit numeric:=0;adjustments numeric:=0;working numeric:=0;
 investing numeric:=0;financing numeric:=0;cash_delta numeric:=0;cash_count integer:=0;
 missing_count integer:=0;net numeric;difference numeric;summary jsonb;begin
 for x in select value from jsonb_array_elements(account_rows) loop
  kind:=x->>'account_type';
  movement:=(x->>'period_debit')::numeric-(x->>'period_credit')::numeric;
  if kind in('revenue','expense') then
   cat:='profit';amount:=-movement;profit:=profit+amount;
  else
   select m.category into cat from finance.cash_flow_mapping_events m
    where m.tenant_id=t and m.legal_entity_id=e and m.account_id=(x->>'account_id')::uuid
     and m.effective_date<=d order by m.effective_date desc,m.version desc limit 1;
   if cat='cash' then
    amount:=movement;cash_count:=cash_count+1;
    opening_cash:=opening_cash+(x->>'opening_balance')::numeric;
    closing_cash:=closing_cash+(x->>'closing_balance')::numeric;
    cash_delta:=cash_delta+movement;
   else
    amount:=-movement;
    case cat
     when 'noncash_adjustment' then adjustments:=adjustments+amount;
     when 'working_capital' then working:=working+amount;
     when 'investing' then investing:=investing+amount;
     when 'financing' then financing:=financing+amount;
     else
      if movement<>0 then
       missing_count:=missing_count+1;
       if jsonb_array_length(unmapped)<50 then unmapped:=unmapped||
        jsonb_build_array(jsonb_build_object('id',x->>'account_id','code',x->>'code',
         'name',x->>'name','unclassified_movement',amount::text));end if;
      end if;
    end case;
   end if;
  end if;
  rows:=rows||jsonb_build_array(x||jsonb_build_object(
   'cash_flow_category',coalesce(cat,'unmapped'),'amount',amount::text));
 end loop;
 net:=profit+adjustments+working+investing+financing;
 difference:=net-cash_delta;
 summary:=jsonb_build_object('period_profit',profit::text,'noncash_adjustments',adjustments::text,
  'working_capital_change',working::text,'operating_cash',(profit+adjustments+working)::text,
  'investing_cash',investing::text,'financing_cash',financing::text,
  'net_cash_change',net::text,'opening_cash',opening_cash::text,'closing_cash',closing_cash::text,
  'cash_delta',cash_delta::text,'difference',difference::text,'mapped_cash_count',cash_count,
  'unmapped_count',missing_count,'unmapped_accounts',unmapped,
  'no_mapped_cash',cash_count=0,
  'status',case when cash_count=0 or missing_count>0 or difference<>0 then 'blocked' else 'generated' end);
 return jsonb_build_object('summary',summary,'accounts',rows);
end$$;

create function finance.build_cash_flow_statement(t uuid,e uuid,b uuid,p jsonb)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare data jsonb;prior jsonb;current_totals jsonb;prior_totals jsonb;
 summary jsonb;accounts jsonb:='[]';x jsonb;comp_row jsonb;comp_accounts jsonb;result jsonb;
 compare_id text;compare_end text;begin
 perform core.wave3_require_scope(t,'finance.view',e,null);
 perform core.wave3_require_scope(t,'finance.view',e,b);
 data:=finance.build_financial_statement(t,e,b,p||jsonb_build_object('kind','trial_balance'));
 summary:=data->'summary';compare_id:=summary->>'comparative_period_id';
 compare_end:=summary->>'comparative_end';
 current_totals:=finance.cash_flow_totals(t,e,(summary->>'as_of')::date,data->'accounts');
 if compare_id is not null then
  prior:=finance.build_financial_statement(t,e,b,p||jsonb_build_object(
   'kind','trial_balance','period_id',compare_id,'as_of',compare_end,
   'comparative_period_id',null));
  prior_totals:=finance.cash_flow_totals(t,e,compare_end::date,prior->'accounts');
  comp_accounts:=prior_totals->'accounts';
 end if;
 for x in select value from jsonb_array_elements(current_totals->'accounts') loop
  if comp_accounts is not null then
   select value into comp_row from jsonb_array_elements(comp_accounts)
    where value->>'account_id'=x->>'account_id' limit 1;
  end if;
  accounts:=accounts||jsonb_build_array(x||jsonb_build_object(
   'comparative_amount',comp_row->>'amount',
   'comparative_category',comp_row->>'cash_flow_category'));
  comp_row:=null;
 end loop;
 summary:=summary||jsonb_build_object('kind','cash_flow',
  'status',case when current_totals#>>'{summary,status}'='blocked'
    or prior_totals#>>'{summary,status}'='blocked' then 'blocked' else 'generated' end,
  'cash_flow',current_totals->'summary',
  'comparative',prior_totals->'summary');
 result:=jsonb_build_object('summary',summary,'accounts',accounts,'journals',data->'journals');
 if octet_length(result::text)>16777216 then
  raise exception using errcode='54000',message='FINANCIAL_REPORT_EVIDENCE_LIMIT';end if;
 return result;
end$$;

create or replace function api.generate_financial_statement(p_tenant_id uuid,p_legal_entity_id uuid,p_branch_id uuid,
 p_command_id uuid,p_idempotency_key uuid,p_client_timestamp timestamptz,p_payload jsonb,
 p_expected_entity_version bigint default null) returns jsonb
language plpgsql security definer set search_path='' as $$
declare id uuid:=(p_payload->>'id')::uuid;h text;r jsonb;data jsonb;summary jsonb;req uuid:=gen_random_uuid();begin
 perform core.wave3_require_scope(p_tenant_id,'finance.view',p_legal_entity_id,null);
 perform core.wave3_require_scope(p_tenant_id,'finance.view',p_legal_entity_id,p_branch_id);
 if id is null or p_client_timestamp is null then
  raise exception using errcode='22023',message='FINANCIAL_REPORT_INPUT_INVALID';end if;
 h:=core.wave3_request_hash('finance.statements.generate',p_command_id,p_tenant_id,
  p_legal_entity_id,p_branch_id,p_payload,p_expected_entity_version);
 r:=core.wave3_replay(p_tenant_id,'finance.statements.generate',p_command_id,p_idempotency_key,h);
 if r is not null then return r;end if;
 perform core.wave3_assert_expected_version(0,p_expected_entity_version,'{}');
 if p_payload->>'kind'='cash_flow' then
  data:=finance.build_cash_flow_statement(p_tenant_id,p_legal_entity_id,p_branch_id,p_payload);
 else
  data:=finance.build_financial_statement(p_tenant_id,p_legal_entity_id,p_branch_id,p_payload);
 end if;
 summary:=data->'summary';
 insert into finance.financial_reports values(id,p_tenant_id,p_legal_entity_id,p_branch_id,
  summary->>'kind',(summary->>'period_id')::uuid,(summary->>'comparative_period_id')::uuid,
  (summary->>'as_of')::date,(summary->>'generated_at')::timestamptz,summary,data,auth.uid());
 return core.wave3_finish_command(p_tenant_id,'finance.statements.generate',p_command_id,
  'financial_statement_report',id,p_idempotency_key,h,null,summary,p_legal_entity_id,p_branch_id,
  '{}',jsonb_build_object('to_status',summary->>'status'),
  jsonb_build_array(jsonb_build_object('topic','finance.statements.generated','payload',summary)),
  '[]',req,req);
end$$;

revoke all on function finance.cash_flow_totals(uuid,uuid,date,jsonb),
 finance.build_cash_flow_statement(uuid,uuid,uuid,jsonb),
 api.cash_flow_mapping_options(uuid,uuid,uuid,date,uuid),
 api.configure_cash_flow_mapping(uuid,uuid,uuid,uuid,uuid,timestamptz,jsonb,bigint)
 from public,anon,authenticated;
grant execute on function api.cash_flow_mapping_options(uuid,uuid,uuid,date,uuid),
 api.configure_cash_flow_mapping(uuid,uuid,uuid,uuid,uuid,timestamptz,jsonb,bigint)
 to authenticated;
notify pgrst,'reload schema';
