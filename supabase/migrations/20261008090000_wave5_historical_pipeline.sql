-- Additive UNAPPLIED candidate. Uses the installed immutable CRM history.
-- No source history, entitlements, role assignments or acceptance fixtures seeded.
create function api.wave5_pipeline_history(p_tenant_id uuid,p_legal_entity_id uuid,p_branch_id uuid,
 p_as_of timestamptz,p_recorded_through timestamptz) returns jsonb
language plpgsql stable security definer set search_path='' as $$
declare rows jsonb;n integer;result jsonb;begin
 perform analytics.pipeline_access(p_tenant_id,p_legal_entity_id,p_branch_id);
 if p_as_of is null or p_recorded_through is null or not isfinite(p_as_of) or not isfinite(p_recorded_through)
  or p_as_of>p_recorded_through or p_recorded_through>statement_timestamp() then
  raise exception using errcode='22023',message='VALIDATION_ERROR';end if;
 if exists(select 1 from crm.opportunities o where o.tenant_id=p_tenant_id and o.legal_entity_id=p_legal_entity_id
  and (p_branch_id is null or o.branch_id=p_branch_id) and o.created_at<=p_as_of
  and not exists(select 1 from crm.pipeline_history h where h.tenant_id=o.tenant_id and h.entity_type='opportunity'
   and h.entity_id=o.id and h.recorded_at<=p_as_of and h.recorded_at<=p_recorded_through)) then
  raise exception using errcode='55000',message='HISTORY_COHORT_INCOMPLETE';end if;
 -- Retain all revisions up to the cutoff: a last-known row alone cannot certify
 -- stage entry. Recheck each historical branch, including a later scope move.
 select coalesce(jsonb_agg(jsonb_build_object('id',h.entity_id,'revisionId',h.id,'version',h.version::text,
  'tenantId',h.tenant_id,'legalEntityId',h.legal_entity_id,'branchId',h.branch_id,
  'recordedAt',analytics.process_utc(h.recorded_at),'createdAt',analytics.process_utc((h.snapshot->>'created_at')::timestamptz),
  'stage',h.snapshot->>'stage','status',h.snapshot->>'status','ownerId',h.snapshot->>'owner_id',
  'amount',h.snapshot->>'expected_value','probability',h.snapshot->>'probability',
  'currency',h.snapshot->>'currency_code') order by h.entity_id,h.version),'[]'),count(*) into rows,n
 from (select h.* from crm.pipeline_history h where h.tenant_id=p_tenant_id and h.legal_entity_id=p_legal_entity_id
  and h.entity_type='opportunity' and h.recorded_at<=p_as_of and h.recorded_at<=p_recorded_through
  and exists(select 1 from crm.pipeline_history selected where selected.tenant_id=h.tenant_id
   and selected.entity_type=h.entity_type and selected.entity_id=h.entity_id and selected.recorded_at<=p_as_of
   and selected.recorded_at<=p_recorded_through and (p_branch_id is null or selected.branch_id=p_branch_id))
  order by h.entity_id,h.version limit 10001) h;
 if n>10000 then raise exception using errcode='54000',message='LIMIT_EXCEEDED';end if;
 if exists(select 1 from jsonb_array_elements(rows) r group by r->>'id'
  having min((r->>'version')::bigint)<>1 or count(*)<>max((r->>'version')::bigint)) then
  raise exception using errcode='55000',message='HISTORY_REVISION_GAP';end if;
 if exists(select 1 from jsonb_array_elements(rows) r where
  not (core.has_permission(p_tenant_id,'crm.opportunities.view',p_legal_entity_id,(r->>'branchId')::uuid)
   or core.has_permission(p_tenant_id,'crm.opportunities.manage',p_legal_entity_id,(r->>'branchId')::uuid))) then
  raise exception using errcode='42501',message='PERMISSION_DENIED';end if;
 result:=jsonb_build_object('contractRevision',1,'sourceContract','crm.pipeline_history.v1',
  'scope',jsonb_build_object('tenantId',p_tenant_id,'legalEntityId',p_legal_entity_id,'branchId',p_branch_id),
  'asOf',analytics.process_utc(p_as_of),'recordedThrough',analytics.process_utc(p_recorded_through),
  'complete',true,'revisions',rows);
 if octet_length(result::text)>8388608 then raise exception using errcode='54000',message='LIMIT_EXCEEDED';end if;
 return jsonb_build_object('canonicalText',result::text,'sourceHash',encode(extensions.digest(result::text,'sha256'),'hex'));
end $$;
revoke all on function api.wave5_pipeline_history(uuid,uuid,uuid,timestamptz,timestamptz) from public,anon,authenticated;
grant execute on function api.wave5_pipeline_history(uuid,uuid,uuid,timestamptz,timestamptz) to authenticated;

-- Realized result is explicitly posted invoice gross less posted credit-return
-- gross, grouped in original transaction currency. It is not ledger revenue.
create function api.wave5_pipeline_realized(p_tenant_id uuid,p_legal_entity_id uuid,p_branch_id uuid,
 p_forecast_id uuid,p_as_of timestamptz) returns jsonb
language plpgsql stable security definer set search_path='' as $$
declare f jsonb;rows jsonb;n integer;begin
 f:=api.get_pipeline_forecast(p_tenant_id,p_legal_entity_id,p_branch_id,p_forecast_id);
 perform core.wave3_require_scope(p_tenant_id,'finance.receivables.view',p_legal_entity_id,p_branch_id);
 perform core.wave3_require_scope(p_tenant_id,'sales.returns.view',p_legal_entity_id,p_branch_id);
 if p_as_of is null or not isfinite(p_as_of) or p_as_of>statement_timestamp()
  or p_as_of<(f#>>'{evidence,asOf}')::timestamptz then raise exception using errcode='22023',message='VALIDATION_ERROR';end if;
 if p_as_of<(f#>>'{evidence,horizonEnd}')::date::timestamptz then
  raise exception using errcode='55000',message='REALIZED_HORIZON_OPEN';end if;
 if (f#>>'{evidence,asOf}')::timestamptz>=(f#>>'{evidence,horizonEnd}')::date::timestamptz then
  raise exception using errcode='55000',message='FORECAST_NOT_PROSPECTIVE';end if;
 with cohort as (select (x->>'id')::uuid id from jsonb_array_elements(f#>'{evidence,observations}') x),
 documents as (
  select i.id,(o.source_snapshot->>'opportunity_id')::uuid opportunity_id,i.branch_id,i.currency_code,i.grand_total amount,i.version,'invoice' kind,i.posted_at
  from sales.sales_invoices i join sales.sales_orders o on o.tenant_id=i.tenant_id and o.id=i.sales_order_id
  join cohort c on c.id=(o.source_snapshot->>'opportunity_id')::uuid
  where i.tenant_id=p_tenant_id and i.legal_entity_id=p_legal_entity_id and (p_branch_id is null or i.branch_id=p_branch_id)
   and i.status='posted' and i.posted_at<=p_as_of and i.document_date>=(f#>>'{evidence,horizonStart}')::date
   and i.document_date<(f#>>'{evidence,horizonEnd}')::date
  union all
  select r.id,(o.source_snapshot->>'opportunity_id')::uuid,r.branch_id,r.currency_code,-r.grand_total,r.version,'credit_return',r.posted_at
  from sales.sales_returns r join sales.sales_orders o on o.tenant_id=r.tenant_id and o.id=r.sales_order_id
  join cohort c on c.id=(o.source_snapshot->>'opportunity_id')::uuid
  where r.tenant_id=p_tenant_id and r.legal_entity_id=p_legal_entity_id and (p_branch_id is null or r.branch_id=p_branch_id)
   and r.status='posted' and r.posted_at<=p_as_of and r.document_date>=(f#>>'{evidence,horizonStart}')::date
   and r.document_date<(f#>>'{evidence,horizonEnd}')::date
 ) select coalesce(jsonb_agg(jsonb_build_object('id',id,'opportunityId',opportunity_id,'branchId',branch_id,
  'currency',currency_code,'amount',amount::text,'version',version::text,'kind',kind,'postedAt',analytics.process_utc(posted_at)) order by id),'[]'),count(*)
 into rows,n from (select * from documents order by id limit 10001) d;
 if n>10000 then raise exception using errcode='54000',message='LIMIT_EXCEEDED';end if;
 -- A line-linked return without an order header can affect the frozen cohort.
 -- Until an exact header/line apportionment exists, do not report a partial zero.
 if exists(select 1 from sales.sales_returns r join sales.sales_return_lines l on l.tenant_id=r.tenant_id and l.document_id=r.id
  join sales.sales_invoice_lines il on il.tenant_id=l.tenant_id and il.id=l.sales_invoice_line_id
  join sales.sales_invoices i on i.tenant_id=il.tenant_id and i.id=il.document_id
  join sales.sales_orders o on o.tenant_id=i.tenant_id and o.id=i.sales_order_id
  where r.tenant_id=p_tenant_id and r.legal_entity_id=p_legal_entity_id and (p_branch_id is null or r.branch_id=p_branch_id)
   and r.sales_order_id is null and r.status='posted' and r.posted_at<=p_as_of
   and r.document_date>=(f#>>'{evidence,horizonStart}')::date and r.document_date<(f#>>'{evidence,horizonEnd}')::date
   and exists(select 1 from jsonb_array_elements(f#>'{evidence,observations}') x where x->>'id'=o.source_snapshot->>'opportunity_id')) then
  raise exception using errcode='55000',message='REALIZED_MAPPING_INCOMPLETE';end if;
 if exists(select 1 from jsonb_array_elements(rows) r where
  not core.has_permission(p_tenant_id,'finance.receivables.view',p_legal_entity_id,(r->>'branchId')::uuid)
  or not core.has_permission(p_tenant_id,'sales.returns.view',p_legal_entity_id,(r->>'branchId')::uuid)) then
  raise exception using errcode='42501',message='PERMISSION_DENIED';end if;
 return jsonb_build_object('contractRevision',1,'forecastId',p_forecast_id,'sourceHash',f->>'sourceHash',
  'definition','posted_invoice_less_order_linked_credit_gross.v1','asOf',analytics.process_utc(p_as_of),'complete',true,'documents',rows);
end $$;
revoke all on function api.wave5_pipeline_realized(uuid,uuid,uuid,uuid,timestamptz) from public,anon,authenticated;
grant execute on function api.wave5_pipeline_realized(uuid,uuid,uuid,uuid,timestamptz) to authenticated;
