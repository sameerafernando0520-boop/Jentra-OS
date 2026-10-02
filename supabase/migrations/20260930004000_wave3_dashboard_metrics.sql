-- UNAPPLIED: contract49. Stable scoped metrics, never a second posting engine.
create index wave3_dashboard_budget_review on finance.budget_variance_reports
 (tenant_id,legal_entity_id,requested_branch_id,budget_id,generated_at desc,id desc);
create index wave3_dashboard_close_review on finance.close_control_reviews
 (tenant_id,legal_entity_id,branch_id,generated_at desc,id desc);
create function finance.wave3_dashboard_aging(t uuid,e uuid,b uuid,k text,d date) returns jsonb
language plpgsql stable security definer set search_path='' as $$
declare n int;rows jsonb;begin
 perform core.wave3_require_scope(t,case k when 'AR' then 'finance.receivables.view'
  when 'AP' then 'finance.payments.manage' end,e,b);
 if k is null or k not in('AR','AP') or d is null then
  raise exception using errcode='22023',message='DASHBOARD_AGING_INVALID';end if;
 select count(*) into n from(select id from finance.open_items where tenant_id=t
  and legal_entity_id=e and branch_id=b and kind=k and posting_date<=d limit 10001)q;
 if n>10000 then raise exception using errcode='54000',message='LIMIT_EXCEEDED';end if;
 with residuals as materialized(select o.currency_code,o.original_amount,o.due_date,
  (finance.flow_residual(t,o.id,d)->>'amount')::numeric amount from finance.open_items o
  where o.tenant_id=t and o.legal_entity_id=e and o.branch_id=b and o.kind=k and o.posting_date<=d),
 grouped as(select currency_code,case when original_amount<0 then 'credit'
  when due_date>=d then 'current' when d-due_date<=30 then '1–30'
  when d-due_date<=60 then '31–60' when d-due_date<=90 then '61–90' else '90+' end bucket,
  sum(amount)::text amount,count(*)::text item_count from residuals where amount<>0 group by 1,2)
 select coalesce(jsonb_agg(to_jsonb(grouped) order by currency_code,bucket),'[]') into rows from grouped;
 return jsonb_build_object('kind',k,'as_of',d,'item_count',n::text,'buckets',rows);
end $$;
revoke all on function finance.wave3_dashboard_aging(uuid,uuid,uuid,text,date) from public,anon,authenticated;

alter function api.wave3_dashboard(uuid,uuid,uuid) rename to wave3_dashboard_queues;
revoke all on function api.wave3_dashboard_queues(uuid,uuid,uuid) from public,anon,authenticated;
create function api.wave3_dashboard(p_tenant_id uuid,p_legal_entity_id uuid,p_branch_id uuid) returns jsonb
language plpgsql stable security definer set search_path='' as $$
declare t uuid:=p_tenant_id;e uuid:=p_legal_entity_id;b uuid:=p_branch_id;
 d date:=(statement_timestamp() at time zone 'UTC')::date;result jsonb;metrics jsonb:='[]';
 data jsonb;rows jsonb;kind text;perm text;common jsonb;n int;
begin
 result:=api.wave3_dashboard_queues(t,e,b);
 if not exists(select 1 from core.branches where tenant_id=t and legal_entity_id=e and id=b and status='active')
  or not exists(select 1 from core.legal_entities where tenant_id=t and id=e and status='active') then
  raise exception using errcode='42501',message='SOURCE_UNAVAILABLE';end if;
 common:=jsonb_build_object('tenant_id',t,'legal_entity_id',e,'branch_id',b,
  'generated_at',statement_timestamp(),'as_of',d);
 if core.has_permission(t,'crm.opportunities.view',e,b) and core.has_permission(t,'crm.leads.view',e,b) then
  perform core.wave3_require_scope(t,'crm.opportunities.view',e,b);
  perform core.wave3_require_scope(t,'crm.leads.view',e,b);
  data:=api.get_crm_pipeline_summary(t,e,b,d);
  metrics:=metrics||jsonb_build_array(common||jsonb_build_object('kind','pipeline','basis','dated_pipeline',
   'destination','/crm','data',data));
 end if;
 for kind,perm in select * from(values('AR','finance.receivables.view'),('AP','finance.payments.manage'))x loop
  if core.has_permission(t,perm,e,b) then
   data:=finance.wave3_dashboard_aging(t,e,b,kind,d);
   metrics:=metrics||jsonb_build_array(common||jsonb_build_object('kind',lower(kind)||'_aging','basis','dated_open_items',
    'destination',case kind when 'AR' then '/receivables' else '/procurement/payments' end,'data',data));
  end if;
 end loop;
 if core.has_permission(t,'finance.view',e,b) then
  perform core.wave3_require_scope(t,'finance.view',e,b);
  data:=finance.build_branch_cash_controls(t,e,b,d);
  metrics:=metrics||jsonb_build_array(common||jsonb_build_object('kind','cash_bank','basis','dated_posted_controls',
   'destination','/finance/bank','data',data->'controls'));
  if core.has_permission(t,'finance.view',e,null) then
  perform core.wave3_require_scope(t,'finance.view',e,null);
  select count(*) into n from(select id from finance.fiscal_periods where tenant_id=t and legal_entity_id=e limit 10001)q;
  if n>10000 then raise exception using errcode='54000',message='LIMIT_EXCEEDED';end if;
  select coalesce(jsonb_agg(jsonb_build_object('id',id,'name',name,'state',state,
   'start_date',start_date,'end_date',end_date) order by start_date,id),'[]') into rows
   from finance.fiscal_periods where tenant_id=t and legal_entity_id=e;
  metrics:=metrics||jsonb_build_array(common||jsonb_build_object('kind','periods','basis','current_period_state',
   'destination','/finance/periods','data',rows));
  end if;
  select count(*) into n from(select id from procurement.supplier_bills where tenant_id=t and legal_entity_id=e
   and branch_id=b and status='draft' limit 10001)q;
  if core.has_permission(t,'procurement.bills.view',e,b) then
   perform core.wave3_require_scope(t,'procurement.bills.view',e,b);
   if n>10000 then raise exception using errcode='54000',message='LIMIT_EXCEEDED';end if;
   select count(*) into n from procurement.supplier_bills where tenant_id=t and legal_entity_id=e and branch_id=b
    and status='draft' and (coalesce((match_result->>'blocked')::boolean,false)
     or jsonb_array_length(coalesce(match_result->'exceptions','[]'))>0);
   metrics:=metrics||jsonb_build_array(common||jsonb_build_object('kind','bill_exceptions','basis','current_match_exceptions',
    'destination','/procurement/bills','data',jsonb_build_object('exception_count',n::text)));
  end if;
 end if;
 if core.has_permission(t,'finance.view',e,null) and core.has_permission(t,'finance.view',e,b) then
  perform core.wave3_require_scope(t,'finance.view',e,null);
  select count(*) into n from(select id from finance.budget_versions where tenant_id=t and legal_entity_id=e
   and (branch_id=b or branch_id is null) limit 10001)q;
  if n>10000 then raise exception using errcode='54000',message='LIMIT_EXCEEDED';end if;
  select coalesce(jsonb_agg(jsonb_build_object('id',v.id,'year',v.budget_year,'revision',v.revision,
   'status',v.status,'currency_code',v.currency_code,'review',r.summary) order by v.budget_year,v.root_id,v.revision),'[]')
   into rows from finance.budget_versions v left join lateral(select summary from finance.budget_variance_reports
    where tenant_id=t and legal_entity_id=e and requested_branch_id=b and budget_id=v.id
    order by generated_at desc,id desc limit 1)r on true
   where v.tenant_id=t and v.legal_entity_id=e and(v.branch_id=b or v.branch_id is null);
  metrics:=metrics||jsonb_build_array(common||jsonb_build_object('kind','budgets','basis','current_state_and_saved_review',
   'destination','/finance/budgets','data',rows));
  if core.has_permission(t,'finance.controls.reconcile',e,null)
   and core.has_permission(t,'inventory.cost.view',e,null) and core.has_permission(t,'inventory.stock.view',e,null)
   and not exists(select 1 from core.branches br where br.tenant_id=t and br.legal_entity_id=e
    and(not core.has_permission(t,'finance.view',e,br.id) or not core.has_permission(t,'finance.controls.reconcile',e,br.id)
     or not core.has_permission(t,'inventory.cost.view',e,br.id) or not core.has_permission(t,'inventory.stock.view',e,br.id))) then
   perform finance.require_close_review_scope(t,e,b);
   select summary into data from finance.close_control_reviews where tenant_id=t and legal_entity_id=e and branch_id=b
    order by generated_at desc,id desc limit 1;
   metrics:=metrics||jsonb_build_array(common||jsonb_build_object('kind','close_review','basis','latest_saved_review',
    'destination','/finance/close-review','data',data));
  end if;
 end if;
 result:=result||jsonb_build_object('metrics',metrics,'as_of',d);
 if octet_length(result::text)>1048576 then raise exception using errcode='54000',message='DASHBOARD_EVIDENCE_LIMIT';end if;
 return result;
end $$;
revoke all on function api.wave3_dashboard(uuid,uuid,uuid) from public,anon,authenticated;
grant execute on function api.wave3_dashboard(uuid,uuid,uuid) to authenticated;
notify pgrst,'reload schema';
