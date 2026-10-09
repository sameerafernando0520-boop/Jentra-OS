-- UNAPPLIED extension. Requires the existing reviewed Wave 3 governed-export
-- candidate 20260926009000 first. Reuses its command, jobs, audit and file codec.
alter function finance.report_export_document(uuid,uuid,uuid,text,uuid,text,jsonb) rename to wave3_report_export_document;
create function finance.report_export_document(t uuid,e uuid,b uuid,resource text,i uuid,section text,filters jsonb) returns jsonb
language plpgsql stable security definer set search_path='' as $$
declare f jsonb;s jsonb;data jsonb;rows jsonb;meta jsonb;start_date date;end_date date;n integer;begin
 if resource is null then raise exception using errcode='22023',message='REPORT_EXPORT_SOURCE_INVALID';end if;
 if resource not in('w5_pipeline','w5_cash') then return finance.wave3_report_export_document(t,e,b,resource,i,section,filters);end if;
 perform core.wave3_require_scope(t,'finance.reports.export',e,b);
 if i is null or filters is null or jsonb_typeof(filters)<>'object' or (filters-'currency')<>'{}'
  or (filters ? 'currency' and (jsonb_typeof(filters->'currency')<>'string' or coalesce(filters->>'currency','')!~ '^[A-Z]{3}$')) then
  raise exception using errcode='22023',message='REPORT_EXPORT_FILTER_INVALID';end if;
 if resource='w5_pipeline' then
  if section is distinct from 'currencies' then raise exception using errcode='22023',message='REPORT_EXPORT_SOURCE_INVALID';end if;
  f:=api.get_pipeline_forecast(t,e,b,i);data:=f->'evidence';
  select coalesce(jsonb_agg(x order by x->>'currency'),'[]') into rows from jsonb_array_elements(data->'currencies') x
   where filters->>'currency' is null or x->>'currency'=filters->>'currency';
  meta:=jsonb_build_object('as_of',data->>'asOf','generated_at',data->>'generatedAt','horizon_start',data->>'horizonStart','horizon_end',data->>'horizonEnd',
   'calculation','pipeline.current_weighted.v1','source_basis_hash',f->>'sourceHash');
 else
  if section is distinct from 'buckets' then raise exception using errcode='22023',message='REPORT_EXPORT_SOURCE_INVALID';end if;
  s:=api.wave5_cash_get(t,e,b,i);data:=(s->>'canonicalText')::jsonb;start_date:=(data->>'horizonStart')::date;end_date:=(data->>'horizonEnd')::date;
  if exists(select 1 from jsonb_array_elements(data->'obligations') o where not exists(select 1 from jsonb_array_elements(data->'controls') c where c->>'currency'=o->>'currency')) then
   raise exception using errcode='55000',message='CASH_CURRENCY_MAPPING_REQUIRED';end if;
  with opening as(select x->>'currency' currency,sum((x->>'amount')::numeric) balance from jsonb_array_elements(data->'controls') x group by x->>'currency'),
   flows as(select o->>'currency' currency,coalesce((s#>>array['parameters','overrides',o->>'id','dueDate'])::date,(o->>'dueDate')::date) due_date,
    case when o->>'provider'='receivables' then coalesce((s#>>array['parameters','overrides',o->>'id','remainingUnits'])::numeric/1000000,(o->>'amount')::numeric) else 0 end inflow,
    case when o->>'provider'='payables' then coalesce((s#>>array['parameters','overrides',o->>'id','remainingUnits'])::numeric/1000000,(o->>'amount')::numeric) else 0 end outflow
    from jsonb_array_elements(data->'obligations') o),
   days as(select c.currency,c.balance,d::date bucket_date from opening c cross join generate_series(start_date,end_date-1,interval '1 day') d
    where filters->>'currency' is null or c.currency=filters->>'currency'),
   buckets as(select d.currency,d.bucket_date,d.balance,coalesce(sum(f.inflow),0) inflow,coalesce(sum(f.outflow),0) outflow
    from days d left join flows f on f.currency=d.currency and f.due_date=d.bucket_date group by d.currency,d.bucket_date,d.balance)
  select coalesce(jsonb_agg(jsonb_build_object('date',bucket_date::text,'currency',currency,'inflow',inflow::text,'outflow',outflow::text,'balance',total::text) order by currency,bucket_date),'[]'),count(*) into rows,n
  from(select currency,bucket_date,inflow,outflow,balance+sum(inflow-outflow) over(partition by currency order by bucket_date) total from buckets order by currency,bucket_date limit 10001) projected;
  if n>10000 then raise exception using errcode='54000',message='REPORT_EXPORT_ROW_LIMIT';end if;
  meta:=jsonb_build_object('as_of',data->>'horizonStart','generated_at',data->>'recordedThrough','horizon_start',data->>'horizonStart','horizon_end',data->>'horizonEnd',
   'calculation','dated_transaction_cash_ar_and_ap.v2','source_basis_hash',s->>'sourceHash','scenario_parameters',s->'parameters','exclusions',data->'exclusions');
 end if;
 meta:=meta||jsonb_build_object('id',i,'version',1,'tenant_id',t,'legal_entity_id',e,'branch_id',b,'actor_id',auth.uid(),'working_branch_id',b,
  'source_type',resource,'source_id',i,'section',section,'filters',filters,'row_count',jsonb_array_length(rows));
 f:=jsonb_build_object('version',1,'metadata',meta,'rows',rows);
 if octet_length(f::text)>8388608 then raise exception using errcode='54000',message='REPORT_EXPORT_EVIDENCE_LIMIT';end if;return f;
end $$;
revoke all on function finance.report_export_document(uuid,uuid,uuid,text,uuid,text,jsonb) from public,anon,authenticated;
create function api.wave5_export_reopen(p_tenant_id uuid,p_legal_entity_id uuid,p_branch_id uuid,p_export_id uuid) returns jsonb
language plpgsql stable security definer set search_path='' as $$declare job core.export_jobs%rowtype;data jsonb;begin
 select * into job from core.export_jobs where tenant_id=p_tenant_id and id=p_export_id and actor_id=auth.uid();
 if not found or job.filters->>'legal_entity_id' is distinct from p_legal_entity_id::text or job.filters->>'working_branch_id' is distinct from p_branch_id::text
  or job.filters->>'source_type' not in('w5_pipeline','w5_cash') then raise exception using errcode='42501',message='PERMISSION_DENIED';end if;
 data:=finance.report_export_document(p_tenant_id,p_legal_entity_id,p_branch_id,job.filters->>'source_type',(job.filters->>'source_id')::uuid,job.filters->>'section',job.filters->'filters');
 if encode(extensions.digest(data::text,'sha256'),'hex')<>job.filters->>'source_hash' then raise exception using errcode='55000',message='EXPORT_BASIS_CHANGED';end if;
 return jsonb_build_object('id',job.id,'canonicalText',data::text,'sourceHash',job.filters->>'source_hash','fileHash',job.filters->>'file_sha256',
  'preparedAt',job.filters->>'prepared_at','format',job.file_format,'fileName',job.file_name);end $$;
revoke all on function api.wave5_export_reopen(uuid,uuid,uuid,uuid) from public,anon,authenticated;
grant execute on function api.wave5_export_reopen(uuid,uuid,uuid,uuid) to authenticated;
