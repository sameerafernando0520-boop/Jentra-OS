-- UNAPPLIED additive candidate. Existing immutable ledgers and posting engines.
create table finance.close_control_reviews (
 id uuid primary key,tenant_id uuid not null,legal_entity_id uuid not null,branch_id uuid not null,
 period_id uuid not null,as_of date not null,generated_at timestamptz not null,
 summary jsonb not null,evidence jsonb not null,created_by uuid not null references auth.users(id),
 unique(tenant_id,id),foreign key(tenant_id,legal_entity_id) references core.legal_entities(tenant_id,id),
 foreign key(tenant_id,branch_id) references core.branches(tenant_id,id),
 foreign key(period_id) references finance.fiscal_periods(id),
 check(octet_length(evidence::text)<=16777216)
);
alter table finance.close_control_reviews enable row level security;
alter table finance.close_control_reviews force row level security;
revoke all on finance.close_control_reviews from public,anon,authenticated;
create trigger immutable before update or delete on finance.close_control_reviews
 for each row execute function workflow.reject_history_mutation();
create index close_reviews_scope on finance.close_control_reviews(tenant_id,legal_entity_id,id);
create index close_reviews_branch on finance.close_control_reviews(tenant_id,branch_id);
create index close_reviews_period on finance.close_control_reviews(period_id);
create index close_reviews_actor on finance.close_control_reviews(created_by);

create function finance.require_close_review_scope(t uuid,e uuid,b uuid) returns void
language plpgsql stable security definer set search_path='' as $$declare r record;begin
 perform core.wave3_require_scope(t,'finance.view',e,null);
 perform core.wave3_require_scope(t,'finance.controls.reconcile',e,null);
 perform inventory.require_valuation_report_scope(t,e,b);
 for r in select id from core.branches where tenant_id=t and legal_entity_id=e order by id loop
  perform finance.require_control_scope(t,e,r.id);
 end loop;
end $$;

create function finance.close_inventory_accounts(t uuid,e uuid,d date) returns jsonb
language plpgsql stable security definer set search_path='' as $$declare ids jsonb;begin
 select coalesce(jsonb_agg(id order by id),'[]') into ids from (
  select inventory_account_id id from inventory.products where tenant_id=t and legal_entity_id=e
  union
  select l.account_id from finance.journal_lines l join finance.journal_entries j
   on j.tenant_id=l.tenant_id and j.id=l.journal_entry_id
  join finance.accounts a on a.tenant_id=l.tenant_id and a.id=l.account_id and a.account_type='asset'
  where l.tenant_id=t and l.legal_entity_id=e and j.status='posted' and l.posting_date<=d
   and exists(select 1 from inventory.stock_movements m where m.tenant_id=t and m.legal_entity_id=e
    and m.command_id=j.command_id and (j.source_type=m.source_type or j.source_type=m.source_type||'.stock'))
 )q where id is not null;
 if jsonb_array_length(ids)>50 then raise exception using errcode='54000',message='CLOSE_INVENTORY_ACCOUNT_LIMIT';end if;
 return ids;
end $$;

-- Cutoff match memberships are immutable; current claim indexes are not history.
create function finance.build_cash_controls(t uuid,e uuid,d date) returns jsonb
language plpgsql stable security definer set search_path='' as $$
declare bank record;statement finance.bank_statements%rowtype;gl jsonb;sl jsonb;rows jsonb:='[]';sources jsonb:='[]';
 book numeric;ug numeric;us numeric;sv numeric;bad integer;n integer:=0;status text;base text;begin
 select currency_code into base from core.legal_entities where tenant_id=t and id=e;
 for bank in select * from finance.cash_bank_accounts where tenant_id=t and legal_entity_id=e order by id loop
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

-- Preserve all previous close checks and add live inventory, GRNI and bank basis.
alter function finance.period_close_exceptions(uuid,uuid,finance.fiscal_periods) rename to period_close_exceptions_before_controls;
-- These helpers only read. Freeze the complete nested report graph to one MVCC
-- statement snapshot; the hard-close command still calls it after period locking.
alter function finance.period_close_exceptions_before_controls(uuid,uuid,finance.fiscal_periods) stable;
alter function finance.period_close_exceptions_before_tax(uuid,uuid,finance.fiscal_periods) stable;
alter function finance.period_close_exceptions_before_cash_flow(uuid,uuid,finance.fiscal_periods) stable;
create function finance.period_close_exceptions(t uuid,e uuid,p finance.fiscal_periods) returns jsonb
language plpgsql stable security definer set search_path='' as $$
declare issues jsonb;branch record;data jsonb;ids jsonb;row jsonb;b uuid;begin
 issues:=finance.period_close_exceptions_before_controls(t,e,p);
 for branch in select id from core.branches where tenant_id=t and legal_entity_id=e order by id loop
  begin
   data:=finance.build_control_report(t,e,branch.id,jsonb_build_object('kind','GRNI','as_of',p.end_date,'id',gen_random_uuid()));
   if (data#>>'{summary,difference_count}')::integer>0 then
    issues:=issues||jsonb_build_array(jsonb_build_object('code','GRNI_CONTROL_DIFFERENCE','branch_id',branch.id,
     'count',data#>'{summary,difference_count}','difference',data#>'{summary,difference}'));end if;
  exception when others then
   issues:=issues||jsonb_build_array(jsonb_build_object('code','GRNI_CONTROL_CHECK_FAILED','branch_id',branch.id,'sqlstate',sqlstate));
  end;
 end loop;
 begin
  ids:=finance.close_inventory_accounts(t,e,p.end_date);
  if jsonb_array_length(ids)>0 then
   select id into b from core.branches where tenant_id=t and legal_entity_id=e order by id limit 1;
   data:=inventory.build_valuation_report(t,e,b,jsonb_build_object('id',gen_random_uuid(),'as_of',p.end_date,'account_ids',ids));
   if (data#>>'{summary,difference_count}')::integer>0 or exists(select 1 from jsonb_array_elements(data->'stock')x where x->>'exception' is not null) then
    issues:=issues||jsonb_build_array(jsonb_build_object('code','INVENTORY_CONTROL_DIFFERENCE','difference',data#>'{summary,difference}',
     'count',data#>'{summary,difference_count}','accounts',data#>'{summary,accounts}'));end if;
  elsif exists(select 1 from inventory.stock_movements where tenant_id=t and legal_entity_id=e and posting_date<=p.end_date) then
   issues:=issues||jsonb_build_array(jsonb_build_object('code','INVENTORY_CONTROL_BASIS_REQUIRED'));
  end if;
 exception when others then issues:=issues||jsonb_build_array(jsonb_build_object('code','INVENTORY_CONTROL_CHECK_FAILED','sqlstate',sqlstate));end;
 begin
  data:=finance.build_cash_controls(t,e,p.end_date);
  for row in select value from jsonb_array_elements(data->'controls') loop
   if (row->>'difference_count')::integer>0 then
    issues:=issues||jsonb_build_array(jsonb_build_object('code','CASH_CONTROL_BLOCKED','component_key',row->>'id',
     'reason',row->>'status','difference',row->>'difference'));end if;
  end loop;
 exception when others then issues:=issues||jsonb_build_array(jsonb_build_object('code','CASH_CONTROL_CHECK_FAILED','sqlstate',sqlstate));end;
 if jsonb_array_length(issues)>50000 or octet_length(issues::text)>16777216 then
  raise exception using errcode='54000',message='CLOSE_REVIEW_OUTPUT_LIMIT';end if;
 return issues;
end $$;

create function finance.build_close_control_review(t uuid,e uuid,b uuid,p jsonb) returns jsonb
language plpgsql stable security definer set search_path='' as $$
declare period finance.fiscal_periods%rowtype;d date:=(p->>'as_of')::date;branch record;k text;key text;data jsonb;row jsonb;
 controls jsonb:='[]';diffs jsonb:='[]';sources jsonb:='[]';stock jsonb:='[]';transit jsonb:='[]';issues jsonb;ids jsonb;
 result jsonb;fxdiff jsonb;begin
 perform finance.require_close_review_scope(t,e,b);
 select * into period from finance.fiscal_periods where tenant_id=t and legal_entity_id=e and id=(p->>'period_id')::uuid and status='active';
 if period.id is null or d is null or d not between period.start_date and period.end_date
  or d>(statement_timestamp() at time zone 'UTC')::date then raise exception using errcode='22023',message='CLOSE_REVIEW_INPUT_INVALID';end if;
 -- Close exceptions use this review cutoff; no premature period-end evidence.
 period.end_date:=d;issues:=finance.period_close_exceptions(t,e,period);
 for branch in select id,name from core.branches where tenant_id=t and legal_entity_id=e order by id loop
  foreach k in array array['AR','AP','GRNI'] loop
   key:=k||':'||branch.id;
   begin
    data:=finance.build_control_report(t,e,branch.id,jsonb_build_object('id',gen_random_uuid(),'kind',k,'as_of',d));
    if k in('AR','AP') then
     select coalesce(jsonb_agg(x||jsonb_build_object('id',(x->>'evidence_key')||':'||coalesce(x->>'command_id','none'),
      'difference',x->'unexplained_difference') order by x->>'evidence_key',x->>'command_id'),'[]') into fxdiff
     from jsonb_array_elements(finance.period_control_fx_variance(t,e,branch.id,k,d,data))x;
    else fxdiff:=data->'differences';end if;
    row:=data->'summary'||jsonb_build_object('id',key,'component_key',key,'name',k||' · '||branch.name,
     'difference_count',jsonb_array_length(fxdiff),'status',case when jsonb_array_length(fxdiff)=0 then 'reconciled' else 'difference' end);
    controls:=controls||jsonb_build_array(row);
    select diffs||coalesce(jsonb_agg(x||jsonb_build_object('id',key||':'||(x->>'id'),'component_key',key) order by x->>'id'),'[]') into diffs from jsonb_array_elements(fxdiff)x;
    select sources||coalesce(jsonb_agg(x||jsonb_build_object('id',key||':source:'||(x->>'id'),'component_key',key,'origin','subledger') order by x->>'id'),'[]') into sources from jsonb_array_elements(data->'entries')x;
    select sources||coalesce(jsonb_agg(x||jsonb_build_object('id',key||':journal:'||(x->>'id'),'component_key',key,'origin','journal') order by x->>'id'),'[]') into sources from jsonb_array_elements(data->'journals')x;
   exception when sqlstate '22023' or sqlstate '55000' then
    controls:=controls||jsonb_build_array(jsonb_build_object('id',key,'component_key',key,'kind',k,'name',k||' · '||branch.name,
     'branch_id',branch.id,'currency_code',(select currency_code from core.legal_entities where tenant_id=t and id=e),
     'status','unavailable','reason',sqlerrm,'difference_count',1,'accounts','[]'::jsonb));
    issues:=issues||jsonb_build_array(jsonb_build_object('code',k||'_CONTROL_CHECK_FAILED','component_key',key,'sqlstate',sqlstate));
   end;
  end loop;
 end loop;
 ids:=finance.close_inventory_accounts(t,e,d);
 if jsonb_array_length(ids)>0 then
  data:=inventory.build_valuation_report(t,e,b,jsonb_build_object('id',gen_random_uuid(),'as_of',d,'account_ids',ids));
  row:=data->'summary'||jsonb_build_object('id','INVENTORY','component_key','INVENTORY','kind','INVENTORY','name','Entity inventory including transit',
   'subledger_value',data#>'{summary,inventory_value}','status',case when (data#>>'{summary,difference_count}')::integer=0 then 'reconciled' else 'difference' end);
  controls:=controls||jsonb_build_array(row);stock:=data->'stock';transit:=data->'transit';
  select diffs||coalesce(jsonb_agg(x||jsonb_build_object('id','INVENTORY:'||(x->>'id'),'component_key','INVENTORY',
   'subledger_value',x->'inventory_value') order by x->>'id'),'[]') into diffs from jsonb_array_elements(data->'differences')x;
  select sources||coalesce(jsonb_agg(x||jsonb_build_object('id','INVENTORY:stock:'||(x->>'id'),'component_key','INVENTORY','origin','stock') order by x->>'id'),'[]') into sources from jsonb_array_elements(data->'movements')x;
  select sources||coalesce(jsonb_agg(x||jsonb_build_object('id','INVENTORY:journal:'||(x->>'id'),'component_key','INVENTORY','origin','journal') order by x->>'id'),'[]') into sources from jsonb_array_elements(data->'journals')x;
 end if;
 data:=finance.build_cash_controls(t,e,d);controls:=controls||(data->'controls');sources:=sources||(data->'sources');
 for row in select value from jsonb_array_elements(data->'controls') loop
  if (row->>'difference_count')::integer>0 then diffs:=diffs||jsonb_build_array(row);end if;
 end loop;
 select coalesce(jsonb_agg(x||jsonb_build_object('id','issue:'||ord) order by ord),'[]') into issues from jsonb_array_elements(issues) with ordinality q(x,ord);
 if greatest(jsonb_array_length(controls),jsonb_array_length(diffs),jsonb_array_length(sources),jsonb_array_length(stock),jsonb_array_length(transit),jsonb_array_length(issues))>50000 then
  raise exception using errcode='54000',message='CLOSE_REVIEW_OUTPUT_LIMIT';end if;
 result:=jsonb_build_object('summary',jsonb_build_object('id',p->>'id','version',1,'tenant_id',t,'legal_entity_id',e,'branch_id',b,
  'entity_name',(select name from core.legal_entities where tenant_id=t and id=e),'currency_code',(select currency_code from core.legal_entities where tenant_id=t and id=e),
  'period_id',period.id,'period_name',period.name,'period_version',period.version,'period_state',period.state,'period_start',period.start_date,'as_of',d,
  'generated_at',statement_timestamp(),'scope','all_entity_branches','status',case when jsonb_array_length(issues)=0 and jsonb_array_length(diffs)=0 then 'ready' else 'blocked' end,
  'control_count',jsonb_array_length(controls),'difference_count',jsonb_array_length(diffs),'blocker_count',jsonb_array_length(issues),
  'branch_count',(select count(*) from core.branches where tenant_id=t and legal_entity_id=e),
  'branches',(select jsonb_agg(jsonb_build_object('id',id,'name',name,'status',status) order by id) from core.branches where tenant_id=t and legal_entity_id=e)),
  'controls',controls,'differences',diffs,'sources',sources,'stock',stock,'transit',transit,'blockers',issues);
 if octet_length(result::text)>16777216 then raise exception using errcode='54000',message='CLOSE_REVIEW_EVIDENCE_LIMIT';end if;
 return result;
end $$;

create function api.generate_close_control_review(p_tenant_id uuid,p_legal_entity_id uuid,p_branch_id uuid,
 p_command_id uuid,p_idempotency_key uuid,p_client_timestamp timestamptz,p_payload jsonb,p_expected_entity_version bigint default null) returns jsonb
language plpgsql security definer set search_path='' as $$declare h text;r jsonb;data jsonb;s jsonb;id uuid:=(p_payload->>'id')::uuid;req uuid:=gen_random_uuid();begin
 perform finance.require_close_review_scope(p_tenant_id,p_legal_entity_id,p_branch_id);
 if id is null or p_client_timestamp is null then raise exception using errcode='22023',message='CLOSE_REVIEW_INPUT_INVALID';end if;
 h:=core.wave3_request_hash('finance.close.review',p_command_id,p_tenant_id,p_legal_entity_id,p_branch_id,p_payload,p_expected_entity_version);
 r:=core.wave3_replay(p_tenant_id,'finance.close.review',p_command_id,p_idempotency_key,h);if r is not null then return r;end if;
 perform core.wave3_assert_expected_version(0,p_expected_entity_version,'{}');
 data:=finance.build_close_control_review(p_tenant_id,p_legal_entity_id,p_branch_id,p_payload);s:=data->'summary';
 insert into finance.close_control_reviews values(id,p_tenant_id,p_legal_entity_id,p_branch_id,(s->>'period_id')::uuid,
  (s->>'as_of')::date,(s->>'generated_at')::timestamptz,s,data,auth.uid());
 return core.wave3_finish_command(p_tenant_id,'finance.close.review',p_command_id,'close_control_review',id,p_idempotency_key,h,null,s,
  p_legal_entity_id,p_branch_id,'{}',jsonb_build_object('to_status',s->>'status'),
  jsonb_build_array(jsonb_build_object('topic','finance.close.reviewed','payload',s)),'[]',req,req);
end $$;
create function api.close_control_reviews(p_tenant_id uuid,p_legal_entity_id uuid,p_branch_id uuid,p_after uuid default null) returns jsonb
language plpgsql stable security definer set search_path='' as $$declare rows jsonb;cursor uuid;begin
 perform finance.require_close_review_scope(p_tenant_id,p_legal_entity_id,p_branch_id);
 select coalesce(jsonb_agg(summary order by id),'[]') into rows from(select id,summary from finance.close_control_reviews
  where tenant_id=p_tenant_id and legal_entity_id=p_legal_entity_id and(p_after is null or id>p_after) order by id limit 51)q;
 if jsonb_array_length(rows)>50 then cursor:=(rows->49->>'id')::uuid;rows:=rows-50;end if;
 return jsonb_build_object('items',rows,'next_cursor',cursor);
end $$;
create function api.close_control_review_page(p_tenant_id uuid,p_legal_entity_id uuid,p_branch_id uuid,p_id uuid,
 p_section text,p_after integer default 0,p_component_key text default null) returns jsonb
language plpgsql stable security definer set search_path='' as $$declare r finance.close_control_reviews%rowtype;rows jsonb;n integer;begin
 perform finance.require_close_review_scope(p_tenant_id,p_legal_entity_id,p_branch_id);
 if p_section not in('controls','differences','sources','stock','transit','blockers') or p_section is null
  or p_after is null or p_after<0 or p_after>50000 then raise exception using errcode='22023',message='CLOSE_REVIEW_PAGE_INVALID';end if;
 select * into r from finance.close_control_reviews where tenant_id=p_tenant_id and legal_entity_id=p_legal_entity_id and id=p_id;
 if not found then raise exception using errcode='42501',message='CLOSE_REVIEW_SCOPE_REQUIRED';end if;
 if p_component_key is not null and (p_section in('stock','transit') or not exists(select 1 from jsonb_array_elements(r.evidence->'controls')x where x->>'id'=p_component_key)) then
  raise exception using errcode='22023',message='CLOSE_REVIEW_COMPONENT_INVALID';end if;
 select count(*) into n from jsonb_array_elements(r.evidence->p_section)x where p_component_key is null or x->>'component_key'=p_component_key;
 select coalesce(jsonb_agg(x order by ord),'[]') into rows from(select x,ord from jsonb_array_elements(r.evidence->p_section) with ordinality q(x,ord)
  where p_component_key is null or x->>'component_key'=p_component_key order by ord offset p_after limit 50)q;
 return jsonb_build_object('summary',r.summary,'section',p_section,'component_key',p_component_key,'items',rows,
  'next_cursor',case when n>p_after+50 then (p_after+50)::text end);
end $$;
revoke all on function finance.require_close_review_scope(uuid,uuid,uuid),finance.close_inventory_accounts(uuid,uuid,date),
 finance.build_cash_controls(uuid,uuid,date),finance.period_close_exceptions_before_controls(uuid,uuid,finance.fiscal_periods),
 finance.period_close_exceptions(uuid,uuid,finance.fiscal_periods),finance.build_close_control_review(uuid,uuid,uuid,jsonb),
 api.generate_close_control_review(uuid,uuid,uuid,uuid,uuid,timestamptz,jsonb,bigint),api.close_control_reviews(uuid,uuid,uuid,uuid),
 api.close_control_review_page(uuid,uuid,uuid,uuid,text,integer,text) from public,anon,authenticated;
grant execute on function api.generate_close_control_review(uuid,uuid,uuid,uuid,uuid,timestamptz,jsonb,bigint),
 api.close_control_reviews(uuid,uuid,uuid,uuid),api.close_control_review_page(uuid,uuid,uuid,uuid,text,integer,text) to authenticated;
notify pgrst,'reload schema';
