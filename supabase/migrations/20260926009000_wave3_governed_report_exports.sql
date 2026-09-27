-- UNAPPLIED. Private saved evidence only; never arbitrary tables or client rows.
insert into core.permissions(code,module,description,privileged) values
 ('finance.reports.export','finance','Export scoped frozen financial and inventory evidence.',false) on conflict(code) do nothing;

create function finance.report_export_document(t uuid,e uuid,b uuid,resource text,i uuid,section text,filters jsonb) returns jsonb
language plpgsql stable security definer set search_path='' as $$
declare probe jsonb;data jsonb;rows jsonb;meta jsonb;allowed text[];k text;v jsonb;result jsonb;begin
 perform core.wave3_require_scope(t,'finance.reports.export',e,null);
 perform core.wave3_require_scope(t,'finance.reports.export',e,b);
 if i is null or jsonb_typeof(filters) is distinct from 'object' then raise exception using errcode='22023',message='REPORT_EXPORT_INPUT_INVALID';end if;
 allowed:=case resource when 'statement' then array['account_id'] when 'control' then array['evidence_key']
  when 'inventory' then array['evidence_key'] when 'tax' then array['account_id','evidence_key','source_line_id']
  when 'budget' then array['budget_line_id'] when 'close' then array['component_key'] else null end;
 if allowed is null then raise exception using errcode='22023',message='REPORT_EXPORT_SOURCE_INVALID';end if;
 for k,v in select * from jsonb_each(filters) loop
  if not k=any(allowed) or (v<>'null'::jsonb and (jsonb_typeof(v)<>'string' or length(v#>>'{}')>220)) then
   raise exception using errcode='22023',message='REPORT_EXPORT_FILTER_INVALID';end if;
 end loop;
 case resource
 when 'statement' then
  probe:=api.financial_statement_page(t,e,b,i,section,0,(filters->>'account_id')::uuid);
  select evidence into data from finance.financial_reports where tenant_id=t and legal_entity_id=e and id=i;
 when 'control' then
  probe:=api.control_reconciliation_report_page(t,e,b,i,section,0,filters->>'evidence_key');
  select evidence into data from finance.control_reports where tenant_id=t and legal_entity_id=e and branch_id=b and id=i;
 when 'inventory' then
  probe:=api.inventory_valuation_report_page(t,e,b,i,section,0,filters->>'evidence_key');
  select evidence into data from inventory.valuation_reports where tenant_id=t and legal_entity_id=e and branch_id=b and id=i;
 when 'tax' then
  if section='lines' then
   if filters->>'account_id' is not null or filters->>'evidence_key' is not null then raise exception using errcode='22023',message='REPORT_EXPORT_FILTER_INVALID';end if;
   probe:=api.tax_summary_page(t,e,b,i,0,(filters->>'source_line_id')::uuid);
  else
   if filters->>'source_line_id' is not null then raise exception using errcode='22023',message='REPORT_EXPORT_FILTER_INVALID';end if;
   probe:=api.tax_control_page(t,e,b,i,section,0,(filters->>'account_id')::uuid,filters->>'evidence_key');
  end if;
  select evidence into data from finance.tax_reports where tenant_id=t and legal_entity_id=e and requested_branch_id=b and id=i;
 when 'budget' then
  probe:=api.budget_variance_page(t,e,b,i,section,0,(filters->>'budget_line_id')::uuid);
  select evidence into data from finance.budget_variance_reports where tenant_id=t and legal_entity_id=e and requested_branch_id=b and id=i;
 when 'close' then
  probe:=api.close_control_review_page(t,e,b,i,section,0,filters->>'component_key');
  select evidence into data from finance.close_control_reviews where tenant_id=t and legal_entity_id=e and id=i;
 end case;
 if data is null or jsonb_typeof(data->section) is distinct from 'array' then raise exception using errcode='42501',message='REPORT_EXPORT_SCOPE_REQUIRED';end if;
 select coalesce(jsonb_agg(x order by ord),'[]') into rows from jsonb_array_elements(data->section) with ordinality q(x,ord)
 where (filters->>'account_id' is null or x->>'account_id'=filters->>'account_id')
  and (filters->>'evidence_key' is null or x->>'evidence_key'=filters->>'evidence_key')
  and (filters->>'source_line_id' is null or x->>'source_line_id'=filters->>'source_line_id')
  and (filters->>'component_key' is null or x->>'component_key'=filters->>'component_key')
  and (filters->>'budget_line_id' is null or (section='lines' and x->>'id'=filters->>'budget_line_id')
   or (section='journals' and x->>'budget_line_id'=filters->>'budget_line_id'));
 if jsonb_array_length(rows)>10000 then raise exception using errcode='54000',message='REPORT_EXPORT_ROW_LIMIT';end if;
 select coalesce(jsonb_object_agg(key,value),'{}') into meta from jsonb_each(data->'summary')
  where key in('id','version','tenant_id','legal_entity_id','branch_id','requested_branch_id','scope','entity_name','branch_name','kind','status',
   'currency_code','base_currency_code','as_of','generated_at','period_id','period_name','period_start','period_end','period_version','period_state',
   'comparative_period_id','budget_id','budget_version','budget_name','branch_filter_id','cost_centre_filter_id','project_filter_id','notice');
 result:=jsonb_build_object('version',1,'metadata',meta||jsonb_build_object('actor_id',auth.uid(),'working_branch_id',b,
  'source_type',resource,'source_id',i,'section',section,'filters',filters,'row_count',jsonb_array_length(rows)), 'rows',rows);
 if octet_length(result::text)>8388608 then raise exception using errcode='54000',message='REPORT_EXPORT_EVIDENCE_LIMIT';end if;
 return result;
end $$;
create function api.report_export_preview(p_tenant_id uuid,p_legal_entity_id uuid,p_branch_id uuid,
 p_source_type text,p_source_id uuid,p_section text,p_filters jsonb) returns jsonb
language plpgsql stable security definer set search_path='' as $$declare data jsonb;begin
 data:=finance.report_export_document(p_tenant_id,p_legal_entity_id,p_branch_id,p_source_type,p_source_id,p_section,p_filters);
 return jsonb_build_object('canonical_text',data::text,'source_hash',encode(extensions.digest(data::text,'sha256'),'hex'));
end $$;
create function api.record_report_export(p_tenant_id uuid,p_legal_entity_id uuid,p_branch_id uuid,
 p_command_id uuid,p_idempotency_key uuid,p_client_timestamp timestamptz,p_payload jsonb,p_expected_entity_version bigint default null) returns jsonb
language plpgsql security definer set search_path='' as $$
declare p jsonb:=p_payload;data jsonb;h text;r jsonb;id uuid:=(p->>'id')::uuid;req uuid:=gen_random_uuid();
 source_hash text;columns jsonb;filters jsonb;result jsonb;expected_columns jsonb;begin
 -- Current source permission and export permission precede every replay.
 data:=finance.report_export_document(p_tenant_id,p_legal_entity_id,p_branch_id,p->>'source_type',(p->>'source_id')::uuid,p->>'section',p->'filters');
 source_hash:=encode(extensions.digest(data::text,'sha256'),'hex');
 select jsonb_build_array('record_type')||
  (select jsonb_agg('report.'||key order by key) from (select jsonb_object_keys(data->'metadata') key
   union select unnest(array['export_id','export_prepared_at','source_hash','file_format']))q)||
  coalesce((select jsonb_agg('data.'||key order by key) from (select distinct key
   from jsonb_array_elements(data->'rows')x cross join lateral jsonb_object_keys(x)key)q),'[]'::jsonb)
 into expected_columns;
 if id is null or p_client_timestamp is null or p->>'source_hash' is distinct from source_hash
  or p->>'file_format' not in('csv','xlsx') or p->>'file_format' is null
  or coalesce(p->>'file_name','')!~ '^[a-zA-Z0-9][a-zA-Z0-9._-]{1,180}$'
  or right(p->>'file_name',length(p->>'file_format')+1)<>'.'||(p->>'file_format')
  or coalesce(p->>'file_sha256','')!~ '^[a-f0-9]{64}$' or (p->>'file_size')::bigint not between 1 and 10485760
  or p->>'file_size' is null or jsonb_typeof(p->'columns') is distinct from 'array'
  or jsonb_array_length(p->'columns') not between 1 and 256 or p->>'prepared_at' is null
  or p->'columns' is distinct from expected_columns then
  raise exception using errcode='22023',message='REPORT_EXPORT_METADATA_INVALID';end if;
 if exists(select 1 from jsonb_array_elements(p->'columns')x where jsonb_typeof(x)<>'string' or length(x#>>'{}') not between 1 and 100)
  or (select count(distinct x) from jsonb_array_elements_text(p->'columns')x)<>jsonb_array_length(p->'columns') then
  raise exception using errcode='22023',message='REPORT_EXPORT_METADATA_INVALID';end if;
 perform (p->>'prepared_at')::timestamptz;
 h:=core.wave3_request_hash('finance.report.export',p_command_id,p_tenant_id,p_legal_entity_id,p_branch_id,p,p_expected_entity_version);
 r:=core.wave3_replay(p_tenant_id,'finance.report.export',p_command_id,p_idempotency_key,h);if r is not null then return r;end if;
 perform core.wave3_assert_expected_version(0,p_expected_entity_version,'{}');
 filters:=data->'metadata'||jsonb_build_object('source_hash',source_hash,'file_sha256',p->>'file_sha256','prepared_at',p->>'prepared_at',
  'artifact_state','generated_local_delivery_unconfirmed');columns:=p->'columns';
 insert into core.export_jobs(id,tenant_id,actor_id,resource,file_format,filters,columns_json,status,row_count,file_name,file_size,request_id)
  values(id,p_tenant_id,auth.uid(),'wave3.'||(p->>'source_type'),p->>'file_format',filters,columns,'completed',
   jsonb_array_length(data->'rows'),p->>'file_name',(p->>'file_size')::bigint,req);
 result:=jsonb_build_object('id',id,'version',1,'tenant_id',p_tenant_id,'legal_entity_id',p_legal_entity_id,'branch_id',p_branch_id,
  'actor_id',auth.uid(),'status','registered','source_type',p->>'source_type','source_id',p->>'source_id',
  'section',p->>'section','filters',p->'filters','source_hash',source_hash,'file_sha256',p->>'file_sha256',
  'file_format',p->>'file_format','file_name',p->>'file_name','file_size',(p->>'file_size')::bigint,'row_count',jsonb_array_length(data->'rows'));
 return core.wave3_finish_command(p_tenant_id,'finance.report.export',p_command_id,'report_export',id,p_idempotency_key,h,null,result,
  p_legal_entity_id,p_branch_id,'{}',jsonb_build_object('to_status','registered'),
  jsonb_build_array(jsonb_build_object('topic','finance.report.exported','payload',result)),'[]',req,req);
end $$;
revoke all on function finance.report_export_document(uuid,uuid,uuid,text,uuid,text,jsonb),
 api.report_export_preview(uuid,uuid,uuid,text,uuid,text,jsonb),
 api.record_report_export(uuid,uuid,uuid,uuid,uuid,timestamptz,jsonb,bigint) from public,anon,authenticated;
grant execute on function api.report_export_preview(uuid,uuid,uuid,text,uuid,text,jsonb),
 api.record_report_export(uuid,uuid,uuid,uuid,uuid,timestamptz,jsonb,bigint) to authenticated;
notify pgrst,'reload schema';
