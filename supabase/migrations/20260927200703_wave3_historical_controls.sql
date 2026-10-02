-- UNAPPLIED additive historical AR/AP control coverage. Source builder SHA-256 9de77b0e06887469a682292311d9cd161d598dcb6f871a34a712dbc38aaa5e26.
-- GRNI wrapper source SHA-256 b1864d4ac1612ebfc54439873ef5c8afab790051cf399869f55bc8ba4ff67f02; only bounded preflight is added.
-- No arbitrary same-type GL account is inferred as an AR/AP control.
create table finance.control_account_basis(
 id uuid primary key default gen_random_uuid(), tenant_id uuid not null,legal_entity_id uuid not null,
 kind text not null check(kind in('AR','AP')),account_id uuid not null,
 source_type text not null check(source_type in('current_mapping','audit_before','audit_after','future_mapping_old','future_mapping_new')),
 source_id uuid not null,source_version bigint not null default 0,observed_at timestamptz not null,
 actor_id uuid references auth.users(id),created_at timestamptz not null default now(),
 unique(tenant_id,kind,source_type,source_id,source_version,account_id),
 foreign key(tenant_id,legal_entity_id) references core.legal_entities(tenant_id,id),
 foreign key(tenant_id,legal_entity_id,account_id) references finance.accounts(tenant_id,legal_entity_id,id)
);
alter table finance.control_account_basis enable row level security;
alter table finance.control_account_basis force row level security;
revoke all on finance.control_account_basis from public,anon,authenticated;
create index control_account_basis_scope on finance.control_account_basis(tenant_id,legal_entity_id,kind,account_id,observed_at);
create index control_account_basis_actor on finance.control_account_basis(actor_id);
create trigger immutable before update or delete on finance.control_account_basis
 for each row execute function workflow.reject_history_mutation();

-- Only audited, attributable before/after snapshots enter the historical set.
insert into finance.control_account_basis(tenant_id,legal_entity_id,kind,account_id,source_type,source_id,source_version,observed_at,actor_id)
select pm.tenant_id,pm.legal_entity_id,'AR',pm.account_id,'current_mapping',pm.id,pm.version,pm.updated_at,pm.updated_by
from finance.posting_mappings pm join finance.accounts a on a.tenant_id=pm.tenant_id and a.legal_entity_id=pm.legal_entity_id
 and a.id=pm.account_id and a.account_type='asset' where pm.purpose='receivable_control';
insert into finance.control_account_basis(tenant_id,legal_entity_id,kind,account_id,source_type,source_id,source_version,observed_at,actor_id)
select c.tenant_id,c.legal_entity_id,'AP',c.payable_account_id,'current_mapping',c.legal_entity_id,c.version,c.updated_at,c.updated_by
from procurement.supplier_bill_controls c join finance.accounts a on a.tenant_id=c.tenant_id and a.legal_entity_id=c.legal_entity_id
 and a.id=c.payable_account_id and a.account_type='liability';
with snapshots as (
 select ev.*,side.source_type,side.body from audit.events ev
 cross join lateral(values('audit_before'::text,ev.before_context),('audit_after'::text,ev.after_context))side(source_type,body)
 where ev.aggregate_type in('posting_mappings','supplier_bill_controls') and ev.legal_entity_id is not null
), candidates as (
 select s.tenant_id,s.legal_entity_id,case when s.aggregate_type='posting_mappings' then 'AR' else 'AP' end kind,
  case when s.aggregate_type='posting_mappings' then s.body->>'account_id' else s.body->>'payable_account_id' end account_text,
  s.source_type,s.id source_id,s.occurred_at,s.actor_id
 from snapshots s where s.body is not null and
  (s.aggregate_type='supplier_bill_controls' or s.body->>'purpose'='receivable_control')
)
insert into finance.control_account_basis(tenant_id,legal_entity_id,kind,account_id,source_type,source_id,source_version,observed_at,actor_id)
select c.tenant_id,c.legal_entity_id,c.kind,a.id,c.source_type,c.source_id,0,c.occurred_at,c.actor_id
from candidates c join finance.accounts a on a.tenant_id=c.tenant_id and a.legal_entity_id=c.legal_entity_id
 and a.id::text=c.account_text and a.account_type=case c.kind when 'AR' then 'asset' else 'liability' end
on conflict do nothing;

create function finance.record_control_mapping_basis() returns trigger
language plpgsql security definer set search_path='' as $$
declare k text;old_account uuid;new_account uuid;source uuid;v bigint;tenant uuid;entity uuid;actor uuid;typ text;begin
 if TG_TABLE_SCHEMA='finance' then
  if new.purpose<>'receivable_control' then return new;end if;
  k:='AR';new_account:=new.account_id;source:=new.id;v:=new.version;
  tenant:=new.tenant_id;entity:=new.legal_entity_id;actor:=new.updated_by;
  if TG_OP='UPDATE' then old_account:=old.account_id;end if;
 else
  k:='AP';new_account:=new.payable_account_id;source:=new.legal_entity_id;v:=new.version;
  tenant:=new.tenant_id;entity:=new.legal_entity_id;actor:=new.updated_by;
  if TG_OP='UPDATE' then old_account:=old.payable_account_id;end if;
 end if;
 typ:=case k when 'AR' then 'asset' else 'liability' end;
 if not exists(select 1 from finance.accounts a where a.tenant_id=tenant and a.legal_entity_id=entity
  and a.id=new_account and a.account_type=typ) then
  raise exception using errcode='22023',message='CONTROL_ACCOUNT_TYPE_INVALID';end if;
 if old_account is not null and old_account is distinct from new_account then
  insert into finance.control_account_basis(tenant_id,legal_entity_id,kind,account_id,source_type,source_id,source_version,observed_at,actor_id)
  values(tenant,entity,k,old_account,'future_mapping_old',source,v,statement_timestamp(),actor) on conflict do nothing;
 end if;
 insert into finance.control_account_basis(tenant_id,legal_entity_id,kind,account_id,source_type,source_id,source_version,observed_at,actor_id)
 values(tenant,entity,k,new_account,'future_mapping_new',source,v,statement_timestamp(),actor) on conflict do nothing;
 return new;
end $$;
revoke all on function finance.record_control_mapping_basis() from public,anon,authenticated;
create trigger control_mapping_basis after insert or update of account_id,status on finance.posting_mappings
 for each row execute function finance.record_control_mapping_basis();
create trigger supplier_mapping_basis after insert or update of payable_account_id on procurement.supplier_bill_controls
 for each row execute function finance.record_control_mapping_basis();

create or replace function finance.build_ar_ap_control_report_v1(t uuid,e uuid,b uuid,p jsonb) returns jsonb
language plpgsql stable security definer set search_path='' as $$
declare d date:=(p->>'as_of')::date;k text:=p->>'kind';sgn integer;
 items jsonb;allocations jsonb;entries jsonb;journals jsonb;accounts jsonb;differences jsonb;result jsonb;
 ids uuid[];sv numeric;gv numeric;unsupported bigint;begin
 perform finance.require_control_scope(t,e,b);
 if k is null or k not in('AR','AP') or d is null or d>(statement_timestamp() at time zone 'UTC')::date then
 raise exception using errcode='22023',message='CONTROL_REPORT_INPUT_INVALID';end if;
 sgn:=case k when 'AR' then 1 else -1 end;
 select coalesce(jsonb_agg(to_jsonb(q) order by id),'[]') into items from (
  select o.id,o.party_id,party.display_name party_name,o.source_type,o.source_id,o.document_number,o.journal_entry_id,o.command_id,
  o.posting_date,o.due_date,o.currency_code,o.base_currency_code,finance.open_item_control(t,o.id)::text evidence_key,
  o.original_amount::text original_amount,o.original_base_amount::text original_base_amount,
  r->>'amount' open_amount,r->>'base_amount' open_base_amount,
  (o.original_amount-(r->>'amount')::numeric)::text settled_amount,
  (o.original_base_amount-(r->>'base_amount')::numeric)::text settled_base_amount
  from finance.open_items o join crm.parties party on party.id=o.party_id
  cross join lateral (select finance.flow_residual(t,o.id,d) r) residual
  where o.tenant_id=t and o.legal_entity_id=e and o.branch_id=b and o.kind=k and o.posting_date<=d order by o.id limit 10001)q;
 if jsonb_array_length(items)>10000 then raise exception using errcode='54000',message='CONTROL_REPORT_INPUT_LIMIT';end if;
 select coalesce(jsonb_agg(to_jsonb(q) order by id),'[]') into allocations from (
  select a.id,a.command_id,a.source_open_item_id,a.target_open_item_id,s.document_number source_document_number,z.document_number target_document_number,
  a.posting_date,a.journal_entry_id,a.source_amount::text,a.transaction_amount::text,a.source_base_amount::text,a.target_base_amount::text,
  a.write_off::text,a.discount_amount::text,a.adjustment_base_amount::text,a.exchange_difference::text,a.reason,
  finance.open_item_control(t,s.id)::text source_control,finance.open_item_control(t,z.id)::text evidence_key,
  case when r.id is not null then sales.flow_exact_json(to_jsonb(r)) end reversal
  from finance.open_item_allocations a join finance.open_items s on s.id=a.source_open_item_id join finance.open_items z on z.id=a.target_open_item_id
  left join finance.allocation_reversals r on r.allocation_id=a.id and r.posting_date<=d
  where a.tenant_id=t and a.legal_entity_id=e and a.branch_id=b and s.kind=k and a.posting_date<=d order by a.id limit 10001)q;
 if jsonb_array_length(allocations)>10000 then raise exception using errcode='54000',message='CONTROL_REPORT_INPUT_LIMIT';end if;
 select array_agg(distinct id order by id) into ids from (
  select (x->>'evidence_key')::uuid id from jsonb_array_elements(items)x
  union select account_id from finance.posting_mappings where tenant_id=t and legal_entity_id=e and purpose='receivable_control' and k='AR'
  union select payable_account_id from procurement.supplier_bill_controls where tenant_id=t and legal_entity_id=e and k='AP'
  union select account_id from finance.control_account_basis where tenant_id=t and legal_entity_id=e and kind=k
   and observed_at < (d + 1)::timestamptz)a where id is not null;
 if coalesce(cardinality(ids),0) not between 1 and 50 then raise exception using errcode='55000',message='CONTROL_ACCOUNT_SETUP_REQUIRED';end if;
 -- Dated subledger movements retain original command lineage, including exact reversal effects.
 with movements as (
  select 'item:'||(x->>'id') id,x->>'evidence_key' evidence_key,x->>'command_id' command_id,x->>'source_type' source_type,x->>'source_id' source_id,
   x->>'posting_date' posting_date,(x->>'original_base_amount')::numeric value from jsonb_array_elements(items)x
  union all select 'allocation-source:'||(x->>'id'),x->>'source_control',x->>'command_id','allocation',x->>'id',x->>'posting_date',(x->>'source_base_amount')::numeric from jsonb_array_elements(allocations)x
  union all select 'allocation-target:'||(x->>'id'),x->>'evidence_key',x->>'command_id','allocation',x->>'id',x->>'posting_date',-(x->>'target_base_amount')::numeric-(x->>'adjustment_base_amount')::numeric from jsonb_array_elements(allocations)x
  union all select 'reversal-source:'||(x#>>'{reversal,id}'),x->>'source_control',x#>>'{reversal,command_id}','allocation_reversal',x#>>'{reversal,id}',x#>>'{reversal,posting_date}',-(x->>'source_base_amount')::numeric from jsonb_array_elements(allocations)x where x->'reversal'<>'null'::jsonb
  union all select 'reversal-target:'||(x#>>'{reversal,id}'),x->>'evidence_key',x#>>'{reversal,command_id}','allocation_reversal',x#>>'{reversal,id}',x#>>'{reversal,posting_date}',(x->>'target_base_amount')::numeric+(x->>'adjustment_base_amount')::numeric from jsonb_array_elements(allocations)x where x->'reversal'<>'null'::jsonb)
 select coalesce(jsonb_agg(jsonb_build_object('id',id,'evidence_key',evidence_key,'command_id',command_id,'source_type',source_type,'source_id',source_id,'posting_date',posting_date,'value',value::text) order by id),'[]') into entries from movements;
 select coalesce(jsonb_agg(to_jsonb(q) order by id),'[]') into journals from (
  select l.id,l.account_id::text evidence_key,a.code account_code,j.command_id,j.id journal_id,j.document_number,j.source_type,j.source_id,l.source_line_id,l.posting_date,
   (sgn*(l.base_debit-l.base_credit))::text value,l.base_debit::text,l.base_credit::text
  from finance.journal_lines l join finance.journal_entries j on j.id=l.journal_entry_id join finance.accounts a on a.id=l.account_id
  where l.tenant_id=t and l.legal_entity_id=e and l.branch_id=b and l.account_id=any(ids) and j.status='posted' and l.posting_date<=d order by l.id limit 10001)q;
 if jsonb_array_length(journals)>10000 then raise exception using errcode='54000',message='CONTROL_REPORT_INPUT_LIMIT';end if;
 select jsonb_agg(jsonb_build_object('id',a.id,'evidence_key',a.id,'code',a.code,'name',a.name,'subledger_value',v::text,'gl_value',g::text,'difference',(v-g)::text) order by a.id)
 into accounts from finance.accounts a
 cross join lateral(select coalesce(sum((x->>'open_base_amount')::numeric),0) v from jsonb_array_elements(items)x where x->>'evidence_key'=a.id::text)s
 cross join lateral(select coalesce(sum((x->>'value')::numeric),0) g from jsonb_array_elements(journals)x where x->>'evidence_key'=a.id::text)j where a.id=any(ids);
 with effects as (
  select x->>'evidence_key' a,x->>'command_id' c,(x->>'value')::numeric v,0::numeric g from jsonb_array_elements(entries)x
  union all select x->>'evidence_key',x->>'command_id',0,(x->>'value')::numeric from jsonb_array_elements(journals)x), totals as(select a,c,sum(v)v,sum(g)g from effects group by a,c)
 select coalesce(jsonb_agg(jsonb_build_object('id',a||':'||c,'evidence_key',a,'command_id',c,'subledger_value',v::text,'gl_value',g::text,'difference',(v-g)::text) order by a,c),'[]') into differences from totals where v<>g;
 if greatest(jsonb_array_length(entries),jsonb_array_length(differences))>50000 then raise exception using errcode='54000',message='CONTROL_REPORT_OUTPUT_LIMIT';end if;
 select coalesce(sum((x->>'subledger_value')::numeric),0),coalesce(sum((x->>'gl_value')::numeric),0) into sv,gv from jsonb_array_elements(accounts)x;
 if sv<>(select coalesce(sum((x->>'value')::numeric),0) from jsonb_array_elements(entries)x) then raise exception using errcode='23514',message='CONTROL_RESIDUAL_DIVERGENCE';end if;
 select coalesce(jsonb_agg(x||jsonb_build_object('basis',coalesce((
  select jsonb_agg(jsonb_build_object('source',basis.source_type,'source_id',basis.source_id,
   'observed_at',basis.observed_at) order by basis.observed_at,basis.id)
  from finance.control_account_basis basis where basis.tenant_id=t and basis.legal_entity_id=e
   and basis.kind=k and basis.account_id=(x->>'id')::uuid and basis.observed_at<(d+1)::timestamptz),'[]'::jsonb)) order by x->>'id'),'[]')
 into accounts from jsonb_array_elements(accounts)x;
 select count(*) into unsupported from audit.events ev cross join lateral
 (values(ev.before_context),(ev.after_context)) snapshot(body)
 where ev.tenant_id=t and ev.legal_entity_id=e and ev.aggregate_type in('posting_mappings','supplier_bill_controls')
  and ev.occurred_at<(d+1)::timestamptz
  and ((k='AR' and ev.aggregate_type='posting_mappings' and snapshot.body->>'purpose'='receivable_control'
    and snapshot.body ? 'account_id' and not exists(select 1 from finance.control_account_basis basis
     where basis.tenant_id=t and basis.kind=k and basis.source_id=ev.id and basis.account_id::text=snapshot.body->>'account_id'))
   or (k='AP' and ev.aggregate_type='supplier_bill_controls' and snapshot.body ? 'payable_account_id'
    and not exists(select 1 from finance.control_account_basis basis
     where basis.tenant_id=t and basis.kind=k and basis.source_id=ev.id and basis.account_id::text=snapshot.body->>'payable_account_id')));
 result:=jsonb_build_object('summary',jsonb_build_object('id',p->>'id','version',1,'status','generated','kind',k,'as_of',d,'tenant_id',t,'legal_entity_id',e,'branch_id',b,
 'entity_name',(select name from core.legal_entities where id=e),'branch_name',(select name from core.branches where id=b),
 'currency_code',(select currency_code from core.legal_entities where id=e),'generated_at',statement_timestamp(),
 'accounts',accounts,'subledger_value',sv::text,'gl_value',gv::text,'difference',(sv-gv)::text,'item_count',jsonb_array_length(items),'difference_count',jsonb_array_length(differences),
 'basis_coverage',jsonb_build_object('registry_accounts',(
  select count(distinct account_id) from finance.control_account_basis
  where tenant_id=t and legal_entity_id=e and kind=k and observed_at<(d+1)::timestamptz),
  'source_accounts',(
   select count(distinct x->>'evidence_key') from jsonb_array_elements(items)x),
  'unsupported_legacy_audit_snapshots',unsupported)),
 'items',items,'allocations',allocations,'entries',entries,'journals',journals,'accounts',accounts,'differences',differences);
 if octet_length(result::text)>16777216 then raise exception using errcode='54000',message='CONTROL_REPORT_EVIDENCE_LIMIT';end if;
 return result;
end $$;

revoke all on function finance.build_ar_ap_control_report_v1(uuid,uuid,uuid,jsonb) from public,anon,authenticated;
create or replace function finance.build_control_report(t uuid,e uuid,b uuid,p jsonb) returns jsonb
language plpgsql stable security definer set search_path='' as $$
declare d date:=(p->>'as_of')::date;receipts jsonb;matches jsonb;returns jsonb;reversals jsonb;
 items jsonb;entries jsonb;journals jsonb;accounts jsonb;differences jsonb;result jsonb;
 ids uuid[];sv numeric;gv numeric;receipt_count integer;begin
 if p->>'kind' is distinct from 'GRNI' then return finance.build_ar_ap_control_report_v1(t,e,b,p);end if;
 perform finance.require_control_scope(t,e,b);
 if d is null or d>(statement_timestamp() at time zone 'UTC')::date then raise exception using errcode='22023',message='CONTROL_REPORT_INPUT_INVALID';end if;
 select count(*) into receipt_count from (
  select id from procurement.goods_receipts where tenant_id=t and legal_entity_id=e
   and branch_id=b and document_date<=d limit 10001) bounded;
 if receipt_count>10000 then raise exception using errcode='54000',message='CONTROL_REPORT_INPUT_LIMIT';end if;
 select coalesce(jsonb_agg(to_jsonb(q) order by id),'[]') into receipts from (
  select r.id,r.id receipt_id,'goods_receipt'::text source_type,r.id source_id,r.command_id,r.journal_entry_id,
   r.document_number,r.document_date posting_date,r.currency_code,r.base_currency_code,
   r.source_snapshot->>'supplier_id' party_id,coalesce(r.source_snapshot->>'supplier_name',party.display_name,'Supplier') party_name,
   finance.receipt_grni_control(t,r.id)::text evidence_key,r.net_amount::text original_amount,r.base_amount::text original_base_amount
  from procurement.goods_receipts r left join crm.parties party on party.id=(r.source_snapshot->>'supplier_id')::uuid and party.tenant_id=r.tenant_id
  where r.tenant_id=t and r.legal_entity_id=e and r.branch_id=b and r.document_date<=d order by r.id limit 10001)q;
 select coalesce(jsonb_agg(to_jsonb(q) order by id),'[]') into matches from (
  select l.id,r.id receipt_id,'supplier_bill'::text source_type,h.id source_id,h.document_date posting_date,h.document_number,
   h.journal_entry_id,j.command_id,l.detail->>'grni_account_id' evidence_key,
   l.detail->>'accrual_amount' amount,l.detail->>'accrual_base_amount' base_amount
  from procurement.supplier_bill_lines l join procurement.supplier_bills h on h.id=l.bill_id and h.tenant_id=l.tenant_id
  join procurement.goods_receipt_lines rl on rl.id=l.receipt_line_id and rl.tenant_id=l.tenant_id
  join procurement.goods_receipts r on r.id=rl.receipt_id and r.tenant_id=l.tenant_id
  left join finance.journal_entries j on j.id=h.journal_entry_id and j.tenant_id=h.tenant_id
  where h.tenant_id=t and h.legal_entity_id=e and h.branch_id=b and h.status='posted' and h.document_date<=d
   and r.document_date<=d order by l.id limit 10001)q;
 if exists(select 1 from jsonb_array_elements(matches)x where x->>'evidence_key' is null or x->>'amount' is null or x->>'base_amount' is null)
 then raise exception using errcode='55000',message='GRNI_CONTROL_BASIS_REQUIRED';end if;
 select coalesce(jsonb_agg(to_jsonb(q) order by id),'[]') into returns from (
  select h.id,r.id receipt_id,'purchase_return'::text source_type,h.id source_id,h.document_date posting_date,h.document_number,
   h.journal_entry_id,h.command_id,finance.receipt_grni_control(t,r.id)::text evidence_key,h.total::text amount,h.base_total::text base_amount
  from procurement.purchase_returns h join procurement.goods_receipts r on r.id=h.source_id and r.tenant_id=h.tenant_id
  where h.tenant_id=t and h.legal_entity_id=e and h.branch_id=b and h.source_kind='receipt' and h.document_date<=d and r.document_date<=d order by h.id limit 10001)q;
 select coalesce(jsonb_agg(to_jsonb(q) order by id),'[]') into reversals from (
  select h.id,r.id receipt_id,'goods_receipt_reversal'::text source_type,h.id source_id,h.document_date posting_date,
   h.journal_entry_id,h.command_id,finance.receipt_grni_control(t,r.id)::text evidence_key,r.net_amount::text amount,r.base_amount::text base_amount
  from procurement.goods_receipt_reversals h join procurement.goods_receipts r on r.id=h.receipt_id and r.tenant_id=h.tenant_id
  where h.tenant_id=t and h.legal_entity_id=e and h.branch_id=b and h.document_date<=d and r.document_date<=d order by h.id limit 10001)q;
 if greatest(jsonb_array_length(receipts),jsonb_array_length(matches),jsonb_array_length(returns),jsonb_array_length(reversals))>10000
 then raise exception using errcode='54000',message='CONTROL_REPORT_INPUT_LIMIT';end if;
 with movements as (
  select x,1 sgn,x->>'original_amount' amount,x->>'original_base_amount' base from jsonb_array_elements(receipts)x
  union all select x,-1,x->>'amount',x->>'base_amount' from jsonb_array_elements(matches)x
  union all select x,-1,x->>'amount',x->>'base_amount' from jsonb_array_elements(returns)x
  union all select x,-1,x->>'amount',x->>'base_amount' from jsonb_array_elements(reversals)x)
 select coalesce(jsonb_agg(x||jsonb_build_object('id',(x->>'source_type')||':'||(x->>'id'),
  'transaction_value',(sgn*amount::numeric)::text,'value',(sgn*base::numeric)::text) order by x->>'source_type',x->>'id'),'[]') into entries
 from movements where x->>'evidence_key' is not null;
 with residuals as (
  select z->>'receipt_id' id,sum((z->>'transaction_value')::numeric)a,sum((z->>'value')::numeric)v
  from jsonb_array_elements(entries)z group by z->>'receipt_id')
 select coalesce(jsonb_agg(x||jsonb_build_object('settled_amount',((x->>'original_amount')::numeric-coalesce(a,0))::text,
  'settled_base_amount',((x->>'original_base_amount')::numeric-coalesce(v,0))::text,
  'open_amount',coalesce(a,0)::text,'open_base_amount',coalesce(v,0)::text) order by x->>'id'),'[]') into items
 from jsonb_array_elements(receipts)x left join residuals tot on tot.id=x->>'id';
 select array_agg(distinct id order by id) into ids from (
  select (x->>'evidence_key')::uuid id from jsonb_array_elements(entries)x
  union select grni_account_id from procurement.receipt_controls where tenant_id=t and legal_entity_id=e
  union select (snapshot->>'grni_account_id')::uuid from procurement.receipt_control_history where tenant_id=t and legal_entity_id=e)a where id is not null;
 if coalesce(cardinality(ids),0) not between 1 and 50 then raise exception using errcode='55000',message='CONTROL_ACCOUNT_SETUP_REQUIRED';end if;
 select coalesce(jsonb_agg(to_jsonb(q) order by id),'[]') into journals from (
  select l.id,l.account_id::text evidence_key,a.code account_code,j.command_id,j.id journal_id,j.document_number,j.source_type,j.source_id,l.source_line_id,l.posting_date,
   (l.base_credit-l.base_debit)::text value,l.base_debit::text,l.base_credit::text
  from finance.journal_lines l join finance.journal_entries j on j.id=l.journal_entry_id and j.tenant_id=l.tenant_id
  join finance.accounts a on a.id=l.account_id and a.tenant_id=l.tenant_id
  where l.tenant_id=t and l.legal_entity_id=e and l.branch_id=b and l.account_id=any(ids) and j.status='posted' and l.posting_date<=d order by l.id limit 10001)q;
 if jsonb_array_length(journals)>10000 then raise exception using errcode='54000',message='CONTROL_REPORT_INPUT_LIMIT';end if;
 select jsonb_agg(jsonb_build_object('id',a.id,'evidence_key',a.id,'code',a.code,'name',a.name,
  'subledger_value',v::text,'gl_value',g::text,'difference',(v-g)::text) order by a.id) into accounts from finance.accounts a
 cross join lateral(select coalesce(sum((x->>'value')::numeric),0)v from jsonb_array_elements(entries)x where x->>'evidence_key'=a.id::text)s
 cross join lateral(select coalesce(sum((x->>'value')::numeric),0)g from jsonb_array_elements(journals)x where x->>'evidence_key'=a.id::text)j
 where a.tenant_id=t and a.legal_entity_id=e and a.id=any(ids);
 if jsonb_array_length(accounts)<>cardinality(ids) then raise exception using errcode='55000',message='GRNI_CONTROL_BASIS_REQUIRED';end if;
 with effects as (
  select x->>'evidence_key' a,x->>'source_type' st,x->>'source_id' si,(x->>'value')::numeric v,0::numeric g from jsonb_array_elements(entries)x
  union all select x->>'evidence_key',x->>'source_type',x->>'source_id',0,(x->>'value')::numeric from jsonb_array_elements(journals)x),
 totals as(select a,st,si,sum(v)v,sum(g)g from effects group by a,st,si)
 select coalesce(jsonb_agg(jsonb_build_object('id',a||':'||st||':'||si,'evidence_key',a,'source_type',st,'source_id',si,
  'subledger_value',v::text,'gl_value',g::text,'difference',(v-g)::text) order by a,st,si),'[]') into differences from totals where v<>g;
 if greatest(jsonb_array_length(entries),jsonb_array_length(differences))>50000 then raise exception using errcode='54000',message='CONTROL_REPORT_OUTPUT_LIMIT';end if;
 select coalesce(sum((x->>'subledger_value')::numeric),0),coalesce(sum((x->>'gl_value')::numeric),0) into sv,gv from jsonb_array_elements(accounts)x;
 if sv<>(select coalesce(sum((x->>'open_base_amount')::numeric),0) from jsonb_array_elements(items)x)
 then raise exception using errcode='23514',message='CONTROL_RESIDUAL_DIVERGENCE';end if;
 result:=jsonb_build_object('summary',jsonb_build_object('id',p->>'id','version',1,'status','generated','kind','GRNI','as_of',d,'tenant_id',t,'legal_entity_id',e,'branch_id',b,
  'entity_name',(select name from core.legal_entities where id=e),'branch_name',(select name from core.branches where id=b),
  'currency_code',(select currency_code from core.legal_entities where id=e),'generated_at',statement_timestamp(),'accounts',accounts,
  'subledger_value',sv::text,'gl_value',gv::text,'difference',(sv-gv)::text,'item_count',jsonb_array_length(items),'difference_count',jsonb_array_length(differences)),
  'items',items,'allocations','[]'::jsonb,'entries',entries,'journals',journals,'accounts',accounts,'differences',differences);
 if octet_length(result::text)>16777216 then raise exception using errcode='54000',message='CONTROL_REPORT_EVIDENCE_LIMIT';end if;
 return result;end $$;

revoke all on function finance.build_control_report(uuid,uuid,uuid,jsonb) from public,anon,authenticated;
notify pgrst,'reload schema';
