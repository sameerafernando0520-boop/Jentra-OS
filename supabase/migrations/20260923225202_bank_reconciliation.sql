-- UNAPPLIED AC-318 candidate; all verification runs end in ROLLBACK.
create table finance.bank_statements (
 id uuid primary key, tenant_id uuid not null, legal_entity_id uuid not null, branch_id uuid not null,
 bank_id uuid not null, account_id uuid not null, currency_code text not null,
 identity text not null check(length(identity) between 1 and 140), start_date date not null, end_date date not null,
 opening numeric(20,6) not null, closing numeric(20,6) not null, total numeric(20,6) not null,
 row_count integer not null check(row_count between 1 and 2000), created_by uuid not null references auth.users(id),
 created_at timestamptz not null default now(), unique(tenant_id,id), unique(tenant_id,bank_id,identity),
 foreign key(tenant_id,bank_id) references finance.cash_bank_accounts(tenant_id,id),
 foreign key(tenant_id,legal_entity_id,account_id) references finance.accounts(tenant_id,legal_entity_id,id),
 foreign key(tenant_id,branch_id) references core.branches(tenant_id,id),
 check(start_date<=end_date), check(opening+total=closing)
);
create table finance.bank_statement_lines (
 id uuid primary key, tenant_id uuid not null, statement_id uuid not null, bank_id uuid not null,
 line_number integer not null, posting_date date not null, reference text not null, description text not null,
 amount numeric(20,6) not null check(amount<>0), unique(tenant_id,id), unique(tenant_id,bank_id,reference),
 unique(tenant_id,statement_id,line_number),
 foreign key(tenant_id,statement_id) references finance.bank_statements(tenant_id,id),
 foreign key(tenant_id,bank_id) references finance.cash_bank_accounts(tenant_id,id)
);
create table finance.bank_matches (
 id uuid primary key, tenant_id uuid not null, legal_entity_id uuid not null, branch_id uuid not null,
 bank_id uuid not null, posting_date date not null, statement_total numeric(20,6) not null,
 journal_total numeric(20,6) not null, difference numeric(20,6) not null, currency_code text not null,
 reason text not null, statement_line_ids uuid[] not null, journal_line_ids uuid[] not null,
 adjustment_journal_id uuid, created_by uuid not null references auth.users(id), created_at timestamptz not null default now(),
 unique(tenant_id,id), foreign key(tenant_id,bank_id) references finance.cash_bank_accounts(tenant_id,id),
 foreign key(tenant_id,branch_id) references core.branches(tenant_id,id),
 foreign key(tenant_id,adjustment_journal_id) references finance.journal_entries(tenant_id,id),
 check(statement_total-journal_total=difference)
);
create table finance.bank_match_reversals (
 id uuid primary key, tenant_id uuid not null, match_id uuid not null, posting_date date not null,
 reason text not null, journal_entry_id uuid, created_by uuid not null references auth.users(id), created_at timestamptz not null default now(),
 unique(tenant_id,match_id), foreign key(tenant_id,match_id) references finance.bank_matches(tenant_id,id),
 foreign key(tenant_id,journal_entry_id) references finance.journal_entries(tenant_id,id)
);
-- Private, rebuildable active claim indexes. Original memberships remain in bank_matches.
create table finance.bank_match_claims (
 tenant_id uuid not null, kind text not null check(kind in('statement','journal')), source_id uuid not null, match_id uuid not null,
 primary key(tenant_id,kind,source_id), foreign key(tenant_id,match_id) references finance.bank_matches(tenant_id,id)
);
create index bank_statements_scope on finance.bank_statements(tenant_id,legal_entity_id,branch_id,bank_id,id);
create unique index bank_statements_identity_ci on finance.bank_statements(tenant_id,bank_id,lower(btrim(identity)));
create index bank_matches_scope on finance.bank_matches(tenant_id,legal_entity_id,branch_id,bank_id,id);
create index bank_claim_match on finance.bank_match_claims(tenant_id,match_id);
do $$declare t text;f record;begin
 foreach t in array array['bank_statements','bank_statement_lines','bank_matches','bank_match_reversals','bank_match_claims'] loop
  execute format('alter table finance.%I enable row level security',t);
  execute format('alter table finance.%I force row level security',t);
  execute format('revoke all on finance.%I from public,anon,authenticated',t);
  if t<>'bank_match_claims' then execute format('create trigger immutable before update or delete on finance.%I for each row execute function workflow.reject_history_mutation()',t);end if;
  for f in select c.conname,(select string_agg(quote_ident(a.attname),',' order by k.n) from unnest(c.conkey) with ordinality k(num,n)
   join pg_attribute a on a.attrelid=c.conrelid and a.attnum=k.num) cols from pg_constraint c where c.conrelid=('finance.'||t)::regclass and c.contype='f' loop
   execute format('create index %I on finance.%I(%s)',f.conname||'_idx',t,f.cols);end loop;
 end loop;
end$$;

create function finance.bank_protect_basis() returns trigger language plpgsql set search_path='' as $$begin
 if (new.account_id,new.currency_code,new.legal_entity_id,new.branch_id) is distinct from (old.account_id,old.currency_code,old.legal_entity_id,old.branch_id)
 and (exists(select 1 from finance.bank_statements where tenant_id=old.tenant_id and bank_id=old.id)
  or exists(select 1 from finance.journal_lines where tenant_id=old.tenant_id and legal_entity_id=old.legal_entity_id and branch_id=old.branch_id and account_id=old.account_id))
 then raise exception using errcode='55000',message='BANK_BASIS_IN_USE';end if;
 return new;
end$$;
create trigger bank_protect_basis before update on finance.cash_bank_accounts for each row execute function finance.bank_protect_basis();

create function finance.bank_scope(t uuid,e uuid,b uuid) returns void language plpgsql security definer set search_path='' as $$begin
 if e is null or b is null then raise exception using errcode='42501',message='BRANCH_SCOPE_REQUIRED';end if;
 perform core.wave3_require_scope(t,'finance.view',e,b);
end$$;
create function finance.bank_json(j jsonb) returns jsonb language sql immutable set search_path='' as $$
 select j||case when j ? 'opening' then jsonb_build_object('opening',j->>'opening','closing',j->>'closing','total',j->>'total') else '{}'::jsonb end
 ||case when j ? 'amount' then jsonb_build_object('amount',j->>'amount') else '{}'::jsonb end
 ||case when j ? 'difference' then jsonb_build_object('statement_total',j->>'statement_total','journal_total',j->>'journal_total','difference',j->>'difference') else '{}'::jsonb end
$$;

create function finance.bank_amount(v jsonb,f text) returns numeric language plpgsql immutable set search_path='' as $$
declare s text:=v#>>'{}';begin
 if jsonb_typeof(v) is distinct from 'string' or s !~ '^-?[0-9]{1,14}([.][0-9]{1,6})?$' then
  raise exception using errcode='22023',message='BANK_EXACT_AMOUNT_REQUIRED';end if;
 return (case when left(s,1)='-' then -1 else 1 end)*sales.wave3_decimal_string(to_jsonb(ltrim(s,'-')),f,6,true,0,null);
end$$;

create function api.bank_reconciliation_command(p_tenant_id uuid,p_legal_entity_id uuid,p_branch_id uuid,p_command_id uuid,p_idempotency_key uuid,
 p_client_timestamp timestamptz,p_payload jsonb,p_expected_entity_version bigint default null) returns jsonb
language plpgsql security definer set search_path='' as $$
declare t uuid:=p_tenant_id;e uuid:=p_legal_entity_id;b uuid:=p_branch_id;p jsonb:=p_payload;act text:=p_payload->>'action';
 v_id uuid:=(p_payload->>'id')::uuid;bank finance.cash_bank_accounts%rowtype;m finance.bank_matches%rowtype;
 h text;r jsonb;result jsonb;req uuid:=gen_random_uuid();cmd text;d date;startd date;endd date;
 x jsonb;amount numeric;opening numeric;closing numeric;st numeric:=0;jt numeric:=0;diff numeric;tol numeric;
 sids uuid[];jids uuid[];n integer;cnt integer;newj uuid;fx jsonb;doc jsonb;lines jsonb;rev finance.journal_entries%rowtype;
begin
 perform finance.bank_scope(t,e,b);
 if act is null or act not in('import','match','reverse','rules') or v_id is null or p_client_timestamp is null then raise exception using errcode='22023',message='BANK_INPUT_INVALID';end if;
 perform core.wave3_require_scope(t,case when act='import' then 'finance.bank.import' when act='rules' then 'finance.bank.manage' else 'finance.bank.reconcile' end,e,b);
 cmd:='finance.bank.'||act;
 h:=core.wave3_request_hash(cmd,p_command_id,t,e,b,p,p_expected_entity_version);
 -- Current access is checked before replay, including the adjustment capability.
 if act='match' and p->>'adjustment_account_id' is not null then perform core.require_permission(t,'finance.bank.adjust',e,b);end if;
 if act='reverse' then
  select * into m from finance.bank_matches where tenant_id=t and legal_entity_id=e and branch_id=b and id=(p->>'match_id')::uuid;
  if not found then raise exception using errcode='42501',message='BANK_MATCH_SCOPE_REQUIRED';end if;
  if m.adjustment_journal_id is not null then perform core.require_permission(t,'finance.bank.adjust',e,b);end if;
 end if;
 r:=core.wave3_replay(t,cmd,p_command_id,p_idempotency_key,h);if r is not null then return r;end if;
 select * into bank from finance.cash_bank_accounts where tenant_id=t and legal_entity_id=e and branch_id=b
 and id=case when act='reverse' then m.bank_id else (p->>'bank_id')::uuid end for update;
 if not found or bank.account_kind<>'bank' or (bank.status<>'active' and act<>'reverse') then raise exception using errcode='42501',message='BANK_SCOPE_REQUIRED';end if;
 if exists(select 1 from finance.cash_bank_accounts where tenant_id=t and legal_entity_id=e and branch_id=b and account_id=bank.account_id and currency_code=bank.currency_code and id<>bank.id and status='active') then
  raise exception using errcode='55000',message='BANK_GL_BASIS_AMBIGUOUS';end if;
 if act='rules' then
  perform core.wave3_assert_expected_version(bank.version,p_expected_entity_version,'{}');
  tol:=sales.wave3_decimal_string(p->'tolerance','tolerance',6,true,0,null)::numeric;
  if length(coalesce(trim(p->>'reason'),'')) not between 3 and 1000 then raise exception using errcode='22023',message='BANK_REASON_DATE_REQUIRED';end if;
  update finance.cash_bank_accounts set reconciliation_rules=jsonb_build_object('tolerance',tol::text),updated_by=auth.uid() where finance.cash_bank_accounts.id=bank.id;
  select jsonb_build_object('id',v_id,'tenant_id',t,'legal_entity_id',e,'branch_id',b,'bank_id',bank.id,'version',1,'bank_version',a.version,'status','configured','tolerance',tol::text,'reason',trim(p->>'reason')) into result from finance.cash_bank_accounts a where a.id=bank.id;
 elsif act='import' then
  perform core.wave3_assert_expected_version(0,p_expected_entity_version,'{}');
  startd:=(p->>'start_date')::date;endd:=(p->>'end_date')::date;
  if startd is null or endd is null or startd>endd or endd>(clock_timestamp() at time zone 'UTC')::date
   or length(coalesce(trim(p->>'identity'),'')) not between 1 and 140
   or jsonb_typeof(p->'lines') is distinct from 'array' or jsonb_array_length(p->'lines') not between 1 and 2000
   or octet_length(p::text)>2097152 then raise exception using errcode='22023',message='BANK_STATEMENT_INVALID';end if;
  if exists(select 1 from finance.bank_statements where tenant_id=t and bank_id=bank.id and lower(btrim(identity))=lower(trim(p->>'identity'))) then
   raise exception using errcode='23505',message='BANK_STATEMENT_DUPLICATE';end if;
  opening:=finance.bank_amount(p->'opening','opening');
  closing:=finance.bank_amount(p->'closing','closing');
  for x in select value from jsonb_array_elements(p->'lines') loop
   amount:=finance.bank_amount(x->'amount','amount');d:=(x->>'date')::date;
   if amount=0 or d is null or d not between startd and endd or length(coalesce(trim(x->>'reference'),'')) not between 1 and 140
    or length(coalesce(x->>'description',''))>500 then raise exception using errcode='22023',message='BANK_LINE_INVALID';end if;
   st:=st+amount;
  end loop;
  if opening+st<>closing then raise exception using errcode='23514',message='BANK_BALANCE_MISMATCH';end if;
  insert into finance.bank_statements values(v_id,t,e,b,bank.id,bank.account_id,bank.currency_code,trim(p->>'identity'),startd,endd,opening,closing,st,jsonb_array_length(p->'lines'),auth.uid(),now());
  insert into finance.bank_statement_lines select gen_random_uuid(),t,v_id,bank.id,ord,(a.x->>'date')::date,trim(a.x->>'reference'),coalesce(a.x->>'description',''),(a.x->>'amount')::numeric
   from jsonb_array_elements(p->'lines') with ordinality a(x,ord);
  select finance.bank_json(to_jsonb(s))||jsonb_build_object('version',1,'status','imported') into result from finance.bank_statements s where s.id=v_id;
 else
  d:=(p->>'posting_date')::date;
  if d is null or d>(clock_timestamp() at time zone 'UTC')::date or length(coalesce(trim(p->>'reason'),'')) not between 3 and 1000 then raise exception using errcode='22023',message='BANK_REASON_DATE_REQUIRED';end if;
  perform finance.wave3_lock_open_period(t,e,d);
  if act='match' then
   perform core.wave3_assert_expected_version(0,p_expected_entity_version,'{}');
   if jsonb_typeof(p->'statement_line_ids') is distinct from 'array' or jsonb_typeof(p->'journal_line_ids') is distinct from 'array'
    or jsonb_array_length(p->'statement_line_ids') not between 1 and 100 or jsonb_array_length(p->'journal_line_ids') not between 1 and 100
    or least(jsonb_array_length(p->'statement_line_ids'),jsonb_array_length(p->'journal_line_ids'))<>1 then raise exception using errcode='22023',message='BANK_MATCH_SHAPE_INVALID';end if;
   select array_agg(v::uuid order by v) into sids from jsonb_array_elements_text(p->'statement_line_ids')a(v);
   select array_agg(v::uuid order by v) into jids from jsonb_array_elements_text(p->'journal_line_ids')a(v);
   if (select count(distinct v) from unnest(sids)v)<>cardinality(sids) or (select count(distinct v) from unnest(jids)v)<>cardinality(jids) then raise exception using errcode='22023',message='BANK_MATCH_DUPLICATE_MEMBER';end if;
   perform 1 from finance.bank_statement_lines where tenant_id=t and bank_id=bank.id and finance.bank_statement_lines.id=any(sids) order by finance.bank_statement_lines.id for update;
   select count(*),sum(l.amount) into cnt,st from finance.bank_statement_lines l join finance.bank_statements s on s.id=l.statement_id
    where l.tenant_id=t and l.bank_id=bank.id and l.id=any(sids) and l.posting_date<=d and s.account_id=bank.account_id and s.currency_code=bank.currency_code;
   if cnt<>cardinality(sids) then raise exception using errcode='42501',message='BANK_LINE_SCOPE_REQUIRED';end if;
   perform 1 from finance.journal_lines l where l.tenant_id=t and l.id=any(jids) order by l.id for update;
   select count(*),sum(l.transaction_debit-l.transaction_credit) into cnt,jt from finance.journal_lines l join finance.journal_entries j on j.id=l.journal_entry_id
    where l.tenant_id=t and l.legal_entity_id=e and l.branch_id=b and l.id=any(jids) and l.account_id=bank.account_id
    and l.currency_code=bank.currency_code and l.posting_date<=d and j.status='posted'
    and j.source_type not in('bank_adjustment','bank_adjustment_reversal');
   if cnt<>cardinality(jids) then raise exception using errcode='42501',message='BANK_JOURNAL_SCOPE_REQUIRED';end if;
   if st=0 or jt=0 or sign(st)<>sign(jt) then raise exception using errcode='22023',message='BANK_MATCH_SIGN_INVALID';end if;
   if exists(select 1 from finance.bank_match_claims c where c.tenant_id=t and ((c.kind='statement' and c.source_id=any(sids)) or(c.kind='journal' and c.source_id=any(jids)))) then raise exception using errcode='40001',message='BANK_LINE_ALREADY_MATCHED';end if;
   -- A rematch cannot predate the reversal that released any selected source.
   if exists(select 1 from finance.bank_match_reversals rr join finance.bank_matches mm on mm.id=rr.match_id where rr.tenant_id=t and rr.posting_date>d
    and (mm.statement_line_ids&&sids or mm.journal_line_ids&&jids)) then raise exception using errcode='22023',message='BANK_MATCH_DATE_BEFORE_HISTORY';end if;
   diff:=st-jt;
   tol:=sales.wave3_decimal_string(coalesce(bank.reconciliation_rules->'tolerance','"0"'),'tolerance',6,true,0,null)::numeric;
   if abs(diff)>tol then raise exception using errcode='22023',message='BANK_TOLERANCE_EXCEEDED';end if;
   if diff<>0 then
    perform core.require_permission(t,'finance.bank.adjust',e,b);
    if not exists(select 1 from finance.accounts a where a.tenant_id=t and a.legal_entity_id=e and a.id=(p->>'adjustment_account_id')::uuid and a.status='active' and a.is_posting and a.account_type in('expense','revenue')
      and not exists(select 1 from finance.posting_mappings pm where pm.tenant_id=t and pm.account_id=a.id and pm.purpose in('receivable_control','payable_control'))
      and not exists(select 1 from finance.cash_bank_accounts cb where cb.tenant_id=t and cb.account_id=a.id)) then raise exception using errcode='22023',message='BANK_ADJUSTMENT_ACCOUNT_INVALID';end if;
    fx:=finance.flow_rate(t,e,bank.currency_code,d,(p->>'exchange_rate_id')::uuid);
    doc:=fx||jsonb_build_object('tenant_id',t,'legal_entity_id',e,'branch_id',b,'document_date',d,'currency_code',bank.currency_code);
    amount:=round(diff*(fx->>'exchange_rate')::numeric,6);
    if amount=0 then raise exception using errcode='22023',message='AMOUNT_BELOW_BASE_PRECISION';end if;
    newj:=finance.flow_post_journal(doc,jsonb_build_array(finance.flow_jline(bank.account_id,diff,amount),finance.flow_jline((p->>'adjustment_account_id')::uuid,-diff,-amount)),'bank_adjustment',v_id,req,p_command_id);
   end if;
   insert into finance.bank_matches values(v_id,t,e,b,bank.id,d,st,jt,diff,bank.currency_code,trim(p->>'reason'),sids,jids,newj,auth.uid(),now());
   insert into finance.bank_match_claims select t,'statement',v,v_id from unnest(sids)v union all select t,'journal',v,v_id from unnest(jids)v;
   select finance.bank_json(to_jsonb(mm))||jsonb_build_object('version',1,'status','matched') into result from finance.bank_matches mm where mm.id=v_id;
  else
   perform core.wave3_assert_expected_version(1,p_expected_entity_version,'{}');
   if d<m.posting_date then raise exception using errcode='22023',message='BANK_REVERSAL_DATE_INVALID';end if;
   if exists(select 1 from finance.bank_match_reversals where tenant_id=t and match_id=m.id) then raise exception using errcode='55000',message='BANK_MATCH_ALREADY_REVERSED';end if;
   if m.adjustment_journal_id is not null then
    select * into rev from finance.journal_entries where tenant_id=t and finance.journal_entries.id=m.adjustment_journal_id;
    doc:=jsonb_build_object('tenant_id',t,'legal_entity_id',e,'branch_id',b,'document_date',d,'currency_code',rev.currency_code,'base_currency_code',rev.base_currency_code,'exchange_rate',rev.exchange_rate::text);
    select jsonb_agg(finance.flow_jline(l.account_id,l.transaction_credit-l.transaction_debit,l.base_credit-l.base_debit) order by l.line_number) into lines from finance.journal_lines l where l.journal_entry_id=rev.id;
    newj:=finance.flow_post_journal(doc,lines,'bank_adjustment_reversal',v_id,req,p_command_id);
   end if;
   insert into finance.bank_match_reversals values(v_id,t,m.id,d,trim(p->>'reason'),newj,auth.uid(),now());
   delete from finance.bank_match_claims where tenant_id=t and match_id=m.id;
   result:=jsonb_build_object('id',v_id,'tenant_id',t,'legal_entity_id',e,'branch_id',b,'bank_id',bank.id,'match_id',m.id,'version',1,'status','reversed','journal_entry_id',newj);
  end if;
 end if;
 return core.wave3_finish_command(t,cmd,p_command_id,'bank_'||act,v_id,p_idempotency_key,h,null,result,e,b,'{}',jsonb_build_object('to_status',result->>'status'),jsonb_build_array(jsonb_build_object('topic',cmd,'payload',jsonb_build_object('id',v_id))),'[]',req,req);
end$$;

create function api.bank_reconciliation_options(p_tenant_id uuid,p_legal_entity_id uuid,p_branch_id uuid,p_resource text,p_bank_id uuid default null,p_after uuid default null)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare t uuid:=p_tenant_id;e uuid:=p_legal_entity_id;b uuid:=p_branch_id;bank finance.cash_bank_accounts%rowtype;rows jsonb;cursor uuid;begin
 perform finance.bank_scope(t,e,b);
 if p_resource not in('accounts','statements','statement_lines','journal_lines','matches','offset_accounts','rates') or p_resource is null then raise exception using errcode='22023',message='BANK_RESOURCE_INVALID';end if;
 if p_resource not in('accounts','offset_accounts','rates') then
  select * into bank from finance.cash_bank_accounts where tenant_id=t and legal_entity_id=e and branch_id=b and id=p_bank_id;
  if not found then raise exception using errcode='42501',message='BANK_SCOPE_REQUIRED';end if;
 end if;
 if p_resource='accounts' then
  select coalesce(jsonb_agg(to_jsonb(q) order by id),'[]') into rows from(select id,code,name,currency_code,version,status,reconciliation_rules from finance.cash_bank_accounts where tenant_id=t and legal_entity_id=e and branch_id=b and account_kind='bank' and (p_after is null or id>p_after) order by id limit 51)q;
 elsif p_resource='offset_accounts' then
  select coalesce(jsonb_agg(to_jsonb(q) order by id),'[]') into rows from(select id,code,name from finance.accounts where tenant_id=t and legal_entity_id=e and is_posting and status='active' and account_type in('expense','revenue') and (p_after is null or id>p_after) order by id limit 51)q;
 elsif p_resource='rates' then
  select coalesce(jsonb_agg(to_jsonb(q) order by id),'[]') into rows from(select id,source_currency_code,target_currency_code,rate::text,effective_date from finance.exchange_rates where tenant_id=t and legal_entity_id=e and status='active' and (p_after is null or id>p_after) order by id limit 51)q;
 elsif p_resource='statements' then
  select coalesce(jsonb_agg(finance.bank_json(to_jsonb(q)) order by id),'[]') into rows from(select * from finance.bank_statements where tenant_id=t and legal_entity_id=e and branch_id=b and bank_id=bank.id and (p_after is null or id>p_after) order by id limit 51)q;
 elsif p_resource='statement_lines' then
  select coalesce(jsonb_agg(finance.bank_json(to_jsonb(q)) order by id),'[]') into rows from(select l.*,c.match_id from finance.bank_statement_lines l left join finance.bank_match_claims c on c.tenant_id=l.tenant_id and c.kind='statement' and c.source_id=l.id where l.tenant_id=t and l.bank_id=bank.id and (p_after is null or l.id>p_after) order by l.id limit 51)q;
 elsif p_resource='journal_lines' then
  select coalesce(jsonb_agg(to_jsonb(q) order by id),'[]') into rows from(select l.id,j.document_number,j.source_type,j.source_id,l.posting_date,(l.transaction_debit-l.transaction_credit)::text amount,(l.base_debit-l.base_credit)::text base_amount,c.match_id from finance.journal_lines l join finance.journal_entries j on j.id=l.journal_entry_id left join finance.bank_match_claims c on c.tenant_id=l.tenant_id and c.kind='journal' and c.source_id=l.id
   where l.tenant_id=t and l.legal_entity_id=e and l.branch_id=b and l.account_id=bank.account_id and l.currency_code=bank.currency_code and j.status='posted' and j.source_type not in('bank_adjustment','bank_adjustment_reversal') and(p_after is null or l.id>p_after) order by l.id limit 51)q;
 else
  select coalesce(jsonb_agg(finance.bank_json(to_jsonb(q)) order by id),'[]') into rows from(select m.*,to_jsonb(rr) reversal from finance.bank_matches m left join finance.bank_match_reversals rr on rr.tenant_id=m.tenant_id and rr.match_id=m.id where m.tenant_id=t and m.legal_entity_id=e and m.branch_id=b and m.bank_id=bank.id and (p_after is null or m.id>p_after) order by m.id limit 51)q;
 end if;
 if jsonb_array_length(rows)>50 then cursor:=(rows->49->>'id')::uuid;rows:=rows-50;end if;
 return jsonb_build_object('items',rows,'next_cursor',cursor,'tenant_id',t,'legal_entity_id',e,'branch_id',b,'resource',p_resource,'bank_id',p_bank_id);
end$$;
revoke all on function finance.bank_protect_basis(),finance.bank_scope(uuid,uuid,uuid),finance.bank_json(jsonb),finance.bank_amount(jsonb,text),api.bank_reconciliation_command(uuid,uuid,uuid,uuid,uuid,timestamptz,jsonb,bigint),api.bank_reconciliation_options(uuid,uuid,uuid,text,uuid,uuid) from public,anon,authenticated;
grant execute on function api.bank_reconciliation_command(uuid,uuid,uuid,uuid,uuid,timestamptz,jsonb,bigint),api.bank_reconciliation_options(uuid,uuid,uuid,text,uuid,uuid) to authenticated;
notify pgrst,'reload schema';
