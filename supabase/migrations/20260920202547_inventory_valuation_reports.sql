-- Candidate only. Saved evidence from existing immutable ledgers, no new postings.
create table inventory.valuation_reports (
 id uuid primary key,tenant_id uuid not null,legal_entity_id uuid not null,branch_id uuid not null,
 as_of date not null,generated_at timestamptz not null,summary jsonb not null,evidence jsonb not null,
 created_by uuid not null references auth.users(id),unique(tenant_id,id),
 foreign key(tenant_id,legal_entity_id) references core.legal_entities(tenant_id,id),
 foreign key(tenant_id,branch_id) references core.branches(tenant_id,id),
 check(octet_length(evidence::text)<=16777216)
);
alter table inventory.valuation_reports enable row level security;
alter table inventory.valuation_reports force row level security;
revoke all on inventory.valuation_reports from public,anon,authenticated;
create trigger immutable before update or delete on inventory.valuation_reports for each row execute function workflow.reject_history_mutation();
create index valuation_reports_scope on inventory.valuation_reports(tenant_id,legal_entity_id,branch_id,id);
create index valuation_reports_branch on inventory.valuation_reports(tenant_id,branch_id);
create index valuation_reports_actor on inventory.valuation_reports(created_by);
create index stock_lines_valuation_date on inventory.stock_movement_lines(tenant_id,legal_entity_id,posting_date,id);
create index journal_lines_valuation_date on finance.journal_lines(tenant_id,legal_entity_id,account_id,posting_date,id);

create function inventory.require_valuation_report_scope(t uuid,e uuid,b uuid) returns void
language plpgsql stable security definer set search_path='' as $$declare r record;p text;begin
 if e is null or b is null then raise exception using errcode='42501',message='OPERATIONAL_SCOPE_REQUIRED';end if;
 perform core.wave3_require_scope(t,'inventory.stock.view',e,b);
 if (select count(*) from core.branches where tenant_id=t and legal_entity_id=e)>500 then raise exception using errcode='54000',message='VALUATION_BRANCH_LIMIT';end if;
 for r in select id from core.branches where tenant_id=t and legal_entity_id=e loop
  foreach p in array array['inventory.stock.view','inventory.cost.view','finance.view'] loop
   perform core.require_permission(t,p,e,r.id);
  end loop;
 end loop;
end $$;
revoke all on function inventory.require_valuation_report_scope(uuid,uuid,uuid) from public,anon,authenticated;

-- STABLE deliberately fixes one database snapshot for all ledger reads below.
create function inventory.build_valuation_report(t uuid,e uuid,b uuid,p jsonb) returns jsonb
language plpgsql stable security definer set search_path='' as $$
declare d date:=(p->>'as_of')::date; v_accounts uuid[]; account_rows jsonb; movements jsonb;journals jsonb;transit jsonb;stock jsonb;lots jsonb;diffs jsonb;
 sv numeric;tv numeric;gv numeric;result jsonb;begin
 perform inventory.require_valuation_report_scope(t,e,b);
 if d is null or d>(statement_timestamp() at time zone 'UTC')::date or jsonb_typeof(p->'account_ids') is distinct from 'array'
  or jsonb_array_length(p->'account_ids') not between 1 and 50 then raise exception using errcode='22023',message='VALUATION_INPUT_INVALID';end if;
 select array_agg(x::uuid order by x) into v_accounts from jsonb_array_elements_text(p->'account_ids') x;
 if (select count(distinct x) from unnest(v_accounts)x)<>cardinality(v_accounts) then raise exception using errcode='22023',message='VALUATION_ACCOUNT_DUPLICATE';end if;
 select jsonb_agg(jsonb_build_object('id',id,'code',code,'name',name) order by id) into account_rows from finance.accounts
  where tenant_id=t and legal_entity_id=e and account_type='asset' and id=any(v_accounts);
 if coalesce(jsonb_array_length(account_rows),0)<>cardinality(v_accounts) then raise exception using errcode='22023',message='VALUATION_ACCOUNT_INVALID';end if;
 select coalesce(jsonb_agg(to_jsonb(q) order by id),'[]') into movements from (
  select l.id,m.command_id,case when m.source_type like 'transfer.%' then 'transfer:'||m.source_id else 'command:'||m.command_id end evidence_key,
   m.source_type,m.source_id,l.source_line_id,l.stock_movement_id,l.warehouse_id,w.name warehouse_name,l.product_id,pr.name product_name,pr.sku,l.lot_id,lot.code lot_code,
   l.serial_ids,l.posting_date,l.base_quantity::text quantity,l.base_value::text value
  from inventory.stock_movement_lines l join inventory.stock_movements m on m.id=l.stock_movement_id
  join core.warehouses w on w.id=l.warehouse_id join inventory.products pr on pr.id=l.product_id left join inventory.lots lot on lot.id=l.lot_id
  where l.tenant_id=t and l.legal_entity_id=e and l.posting_date<=d order by l.id limit 10001)q;
 select coalesce(jsonb_agg(to_jsonb(q) order by id),'[]') into journals from (
  select l.id,j.command_id,'command:'||j.command_id evidence_key,j.id journal_id,j.document_number,j.source_type,j.source_id,l.source_line_id,l.account_id,a.code account_code,
   l.posting_date,(l.base_debit-l.base_credit)::text value
  from finance.journal_lines l join finance.journal_entries j on j.id=l.journal_entry_id join finance.accounts a on a.id=l.account_id
  where l.tenant_id=t and l.legal_entity_id=e and l.account_id=any(v_accounts) and j.status='posted' and l.posting_date<=d order by l.id limit 10001)q;
 select coalesce(jsonb_agg(to_jsonb(q) order by id),'[]') into transit from (
  select l.id,'transfer:'||tr.id evidence_key,tr.id transfer_id,tr.reference,tr.source_warehouse_id,tr.destination_warehouse_id,
   sw.name source_warehouse_name,dw.name destination_warehouse_name,l.product_id,pr.name product_name,l.lot_id,l.serial_ids,
   l.base_quantity::text quantity,l.carrying_value::text value
  from inventory.transfers tr join inventory.transfer_lines l on l.transfer_id=tr.id join inventory.products pr on pr.id=l.product_id
   join core.warehouses sw on sw.id=tr.source_warehouse_id join core.warehouses dw on dw.id=tr.destination_warehouse_id
  where tr.tenant_id=t and tr.legal_entity_id=e
   and exists(select 1 from inventory.transfer_events te where te.transfer_id=tr.id and te.operation='dispatch' and te.posting_date<=d)
   and not exists(select 1 from inventory.transfer_events te where te.transfer_id=tr.id and te.operation in('receive','reverse') and te.posting_date<=d)
  order by l.id limit 10001)q;
 if greatest(jsonb_array_length(movements),jsonb_array_length(journals),jsonb_array_length(transit))>10000 then raise exception using errcode='54000',message='VALUATION_INPUT_LIMIT';end if;
 with totals as (select x->>'warehouse_id' warehouse_id,x->>'warehouse_name' warehouse_name,x->>'product_id' product_id,x->>'product_name' product_name,x->>'sku' sku,
  sum((x->>'quantity')::numeric) q,sum((x->>'value')::numeric) v from jsonb_array_elements(movements)x group by 1,2,3,4,5)
 select coalesce(jsonb_agg(jsonb_build_object('id',warehouse_id||':'||product_id,'warehouse_id',warehouse_id,'warehouse_name',warehouse_name,'product_id',product_id,
  'product_name',product_name,'sku',sku,'quantity',q::text,'value',v::text,'average_cost',case when q<>0 then round(v/q,12)::text end,
  'exception',case when q<0 then 'NEGATIVE_QUANTITY' when q=0 and v<>0 then 'VALUE_WITHOUT_QUANTITY' end) order by warehouse_id,product_id),'[]') into stock from totals;
 if jsonb_array_length(stock)>2000 then raise exception using errcode='54000',message='VALUATION_ROW_LIMIT';end if;
 with quantities as (select x->>'warehouse_id' w,x->>'product_id' pr,x->>'lot_id' lot,x->>'lot_code' code,sum((x->>'quantity')::numeric) q
  from jsonb_array_elements(movements)x group by 1,2,3,4), shares as (
  select q.*,s->>'warehouse_name' warehouse_name,s->>'product_name' product_name,(s->>'quantity')::numeric total_q,(s->>'value')::numeric total_v,
   sum(q.q) over(partition by w,pr order by lot nulls first rows unbounded preceding) running_q
  from quantities q join jsonb_array_elements(stock)s on s->>'warehouse_id'=w and s->>'product_id'=pr where q.q<>0)
 select coalesce(jsonb_agg(jsonb_build_object('id',w||':'||pr||':'||coalesce(lot,'untracked'),'warehouse_name',warehouse_name,'product_name',product_name,
  'lot_id',lot,'lot_code',code,'quantity',q::text,'value',case when total_q<>0 then (round(total_v*running_q/total_q,6)-round(total_v*(running_q-q)/total_q,6))::text end)
  order by w,pr,lot nulls first),'[]') into lots from shares;
 with entries as (
  select x->>'evidence_key' k,(x->>'value')::numeric v,0::numeric g from jsonb_array_elements(movements)x
  union all select x->>'evidence_key',(x->>'value')::numeric,0 from jsonb_array_elements(transit)x
  union all select x->>'evidence_key',0,(x->>'value')::numeric from jsonb_array_elements(journals)x), totals as(select k,sum(v)v,sum(g)g from entries group by k)
 select coalesce(jsonb_agg(jsonb_build_object('id',k,'evidence_key',k,'inventory_value',v::text,'gl_value',g::text,'difference',(v-g)::text) order by k),'[]') into diffs from totals where v<>g;
 select coalesce(sum((x->>'value')::numeric),0) into sv from jsonb_array_elements(stock)x;
 select coalesce(sum((x->>'value')::numeric),0) into tv from jsonb_array_elements(transit)x;
 select coalesce(sum((x->>'value')::numeric),0) into gv from jsonb_array_elements(journals)x;
 result:=jsonb_build_object('summary',jsonb_build_object('id',p->>'id','version',1,'status','generated','as_of',d,'tenant_id',t,'legal_entity_id',e,'branch_id',b,
  'entity_name',(select name from core.legal_entities where id=e),'currency_code',(select currency_code from core.legal_entities where id=e),'generated_at',statement_timestamp(),
  'accounts',account_rows,'warehouse_value',sv::text,'transit_value',tv::text,'inventory_value',(sv+tv)::text,'gl_value',gv::text,'difference',(sv+tv-gv)::text,
  'stock_count',jsonb_array_length(stock),'difference_count',jsonb_array_length(diffs)),
  'stock',stock,'lots',lots,'transit',transit,'differences',diffs,'movements',movements,'journals',journals);
 if octet_length(result::text)>16777216 then raise exception using errcode='54000',message='VALUATION_EVIDENCE_LIMIT';end if;
 return result;
end $$;
revoke all on function inventory.build_valuation_report(uuid,uuid,uuid,jsonb) from public,anon,authenticated;

create function api.generate_inventory_valuation_report(p_tenant_id uuid,p_legal_entity_id uuid,p_branch_id uuid,p_command_id uuid,p_idempotency_key uuid,
 p_client_timestamp timestamptz,p_payload jsonb,p_expected_entity_version bigint default null) returns jsonb
language plpgsql security definer set search_path='' as $$declare h text;r jsonb;data jsonb;summary jsonb;id uuid:=(p_payload->>'id')::uuid;req uuid:=gen_random_uuid();begin
 perform inventory.require_valuation_report_scope(p_tenant_id,p_legal_entity_id,p_branch_id);
 if id is null or p_client_timestamp is null then raise exception using errcode='22023',message='VALUATION_INPUT_INVALID';end if;
 h:=core.wave3_request_hash('inventory.valuation.report',p_command_id,p_tenant_id,p_legal_entity_id,p_branch_id,p_payload,p_expected_entity_version);
 r:=core.wave3_replay(p_tenant_id,'inventory.valuation.report',p_command_id,p_idempotency_key,h);if r is not null then return r;end if;
 perform core.wave3_assert_expected_version(0,p_expected_entity_version,'{}');
 data:=inventory.build_valuation_report(p_tenant_id,p_legal_entity_id,p_branch_id,p_payload);summary:=data->'summary';
 insert into inventory.valuation_reports values(id,p_tenant_id,p_legal_entity_id,p_branch_id,(summary->>'as_of')::date,(summary->>'generated_at')::timestamptz,summary,data,auth.uid());
 return core.wave3_finish_command(p_tenant_id,'inventory.valuation.report',p_command_id,'inventory_valuation_report',id,p_idempotency_key,h,null,summary,
  p_legal_entity_id,p_branch_id,'{}',jsonb_build_object('to_status','generated'),jsonb_build_array(jsonb_build_object('topic','inventory.valuation.report','payload',summary)),'[]',req,req);
end $$;
create function api.inventory_valuation_reports(p_tenant_id uuid,p_legal_entity_id uuid,p_branch_id uuid,p_resource text,p_after uuid default null) returns jsonb
language plpgsql stable security definer set search_path='' as $$declare rows jsonb;cursor uuid;begin
 perform inventory.require_valuation_report_scope(p_tenant_id,p_legal_entity_id,p_branch_id);
 if p_resource='accounts' then
  select coalesce(jsonb_agg(to_jsonb(q) order by id),'[]') into rows from(select a.id,a.code,a.name,a.status from finance.accounts a
   where a.tenant_id=p_tenant_id and a.legal_entity_id=p_legal_entity_id and a.account_type='asset' and(p_after is null or a.id>p_after) order by id limit 51)q;
 elsif p_resource='reports' then
  select coalesce(jsonb_agg(summary order by id),'[]') into rows from(select id,summary from inventory.valuation_reports
   where tenant_id=p_tenant_id and legal_entity_id=p_legal_entity_id and branch_id=p_branch_id and(p_after is null or id>p_after) order by id limit 51)q;
 else raise exception using errcode='22023',message='VALUATION_RESOURCE_INVALID';end if;
 if jsonb_array_length(rows)>50 then cursor:=(rows->49->>'id')::uuid;rows:=rows-50;end if;
 return jsonb_build_object('items',rows,'next_cursor',cursor);
end $$;
create function api.inventory_valuation_report_page(p_tenant_id uuid,p_legal_entity_id uuid,p_branch_id uuid,p_id uuid,p_section text,p_after integer default 0,p_evidence_key text default null) returns jsonb
language plpgsql stable security definer set search_path='' as $$declare r inventory.valuation_reports%rowtype;rows jsonb;n integer;begin
 perform inventory.require_valuation_report_scope(p_tenant_id,p_legal_entity_id,p_branch_id);
 if p_section is null or p_section not in('stock','lots','transit','differences','movements','journals') or p_after is null or p_after<0 or p_after>30000 then raise exception using errcode='22023',message='VALUATION_PAGE_INVALID';end if;
 select * into r from inventory.valuation_reports where tenant_id=p_tenant_id and legal_entity_id=p_legal_entity_id and branch_id=p_branch_id and id=p_id;
 if not found then raise exception using errcode='42501',message='VALUATION_REPORT_SCOPE_REQUIRED';end if;
 select coalesce(jsonb_agg(value order by ord),'[]') into rows from(select value,ord from jsonb_array_elements(r.evidence->p_section) with ordinality x(value,ord)
  where p_evidence_key is null or value->>'evidence_key'=p_evidence_key order by ord offset p_after limit 51)q;
 n:=jsonb_array_length(rows);if n>50 then rows:=rows-50;end if;
 return jsonb_build_object('summary',r.summary,'section',p_section,'evidence_key',p_evidence_key,'items',rows,'next_cursor',case when n>50 then (p_after+50)::text end);
end $$;
revoke all on function api.generate_inventory_valuation_report(uuid,uuid,uuid,uuid,uuid,timestamptz,jsonb,bigint),api.inventory_valuation_reports(uuid,uuid,uuid,text,uuid),api.inventory_valuation_report_page(uuid,uuid,uuid,uuid,text,integer,text) from public,anon,authenticated;
grant execute on function api.generate_inventory_valuation_report(uuid,uuid,uuid,uuid,uuid,timestamptz,jsonb,bigint),api.inventory_valuation_reports(uuid,uuid,uuid,text,uuid),api.inventory_valuation_report_page(uuid,uuid,uuid,uuid,text,integer,text) to authenticated;
notify pgrst,'reload schema';
