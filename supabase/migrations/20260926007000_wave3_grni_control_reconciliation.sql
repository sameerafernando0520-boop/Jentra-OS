-- Unapplied additive candidate. No replacement of immutable posting history.
alter table procurement.goods_receipts add column grni_account_id uuid;
alter table procurement.goods_receipts add constraint goods_receipts_grni_basis_fk
 foreign key(tenant_id,legal_entity_id,grni_account_id) references finance.accounts(tenant_id,legal_entity_id,id);
create index goods_receipts_grni_basis_idx on procurement.goods_receipts(tenant_id,legal_entity_id,grni_account_id);
create function procurement.freeze_receipt_grni_basis() returns trigger
language plpgsql security definer set search_path='' as $$declare ids uuid[];begin
 if new.base_amount<>0 or new.net_amount<>0 then
  select array_agg(q.account_id) into ids from (
   select l.account_id from finance.journal_lines l where l.tenant_id=new.tenant_id
    and l.journal_entry_id=new.journal_entry_id and l.source_line_id is null
   group by l.account_id having sum(l.base_credit-l.base_debit)=new.base_amount
    and sum(l.transaction_credit-l.transaction_debit)=new.net_amount)q;
  if coalesce(cardinality(ids),0)<>1 then raise exception using errcode='55000',message='GRNI_CONTROL_BASIS_REQUIRED';end if;
  new.grni_account_id:=ids[1];
 else
  select grni_account_id into new.grni_account_id from procurement.receipt_controls
  where tenant_id=new.tenant_id and legal_entity_id=new.legal_entity_id;
 end if;
 if new.grni_account_id is null then raise exception using errcode='55000',message='GRNI_CONTROL_BASIS_REQUIRED';end if;
 return new;end $$;
revoke all on function procurement.freeze_receipt_grni_basis() from public,anon,authenticated;
create trigger freeze_grni_basis before insert on procurement.goods_receipts
 for each row execute function procurement.freeze_receipt_grni_basis();

create function finance.receipt_grni_control(t uuid,i uuid) returns uuid
language plpgsql stable security definer set search_path='' as $$
declare r procurement.goods_receipts%rowtype;ids uuid[];begin
 select * into r from procurement.goods_receipts where tenant_id=t and id=i;
 if r.grni_account_id is not null then return r.grni_account_id;end if;
 if r.base_amount=0 and r.net_amount=0 then return null;end if;
 select array_agg(q.account_id) into ids from (
  select l.account_id from finance.journal_lines l
  where l.tenant_id=t and l.journal_entry_id=r.journal_entry_id and l.source_line_id is null
  group by l.account_id having sum(l.base_credit-l.base_debit)=r.base_amount
   and sum(l.transaction_credit-l.transaction_debit)=r.net_amount
 )q;
 if coalesce(cardinality(ids),0)<>1 then raise exception using errcode='55000',message='GRNI_CONTROL_BASIS_REQUIRED';end if;
 return ids[1];end $$;
revoke all on function finance.receipt_grni_control(uuid,uuid) from public,anon,authenticated;

alter function finance.build_control_report(uuid,uuid,uuid,jsonb) rename to build_ar_ap_control_report_v1;
create function finance.build_control_report(t uuid,e uuid,b uuid,p jsonb) returns jsonb
language plpgsql stable security definer set search_path='' as $$
declare d date:=(p->>'as_of')::date;receipts jsonb;matches jsonb;returns jsonb;reversals jsonb;
 items jsonb;entries jsonb;journals jsonb;accounts jsonb;differences jsonb;result jsonb;
 ids uuid[];sv numeric;gv numeric;begin
 if p->>'kind' is distinct from 'GRNI' then return finance.build_ar_ap_control_report_v1(t,e,b,p);end if;
 perform finance.require_control_scope(t,e,b);
 if d is null or d>(statement_timestamp() at time zone 'UTC')::date then raise exception using errcode='22023',message='CONTROL_REPORT_INPUT_INVALID';end if;
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
revoke all on function finance.build_control_report(uuid,uuid,uuid,jsonb),finance.build_ar_ap_control_report_v1(uuid,uuid,uuid,jsonb) from public,anon,authenticated;
notify pgrst,'reload schema';
