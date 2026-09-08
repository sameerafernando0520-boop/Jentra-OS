create function finance.flow_allocate(p_source uuid,p_target uuid,p_tenant uuid,p_entity uuid,p_branch uuid,
 p_payload jsonb,p_date date,p_request uuid,p_command uuid)
returns jsonb language plpgsql security definer set search_path='' as $$
declare v_s finance.open_items%rowtype;v_t finance.open_items%rowtype;v_sr jsonb;v_tr jsonb;
 v_source numeric;v_target numeric;v_write numeric;v_discount numeric;v_sb numeric;v_tb numeric;v_ab numeric;
 v_fx numeric;v_rate finance.exchange_rates%rowtype;v_scale integer;v_conversion numeric:=1;v_id uuid:=gen_random_uuid();
 v_journal uuid;v_lines jsonb:='[]';v_doc jsonb;v_control uuid;v_prior numeric;v_adjust numeric;
begin
 perform 1 from finance.open_items where tenant_id=p_tenant and id in (p_source,p_target) order by id for update;
 select * into v_s from finance.open_items where tenant_id=p_tenant and legal_entity_id=p_entity and branch_id=p_branch and id=p_source;
 select * into v_t from finance.open_items where tenant_id=p_tenant and legal_entity_id=p_entity and branch_id=p_branch and id=p_target;
 if v_s.id is null or v_t.id is null or v_s.party_id<>v_t.party_id or v_s.original_amount>=0 or v_t.original_amount<=0
 or v_s.kind<>'AR' or v_t.kind<>'AR' or v_s.base_currency_code<>v_t.base_currency_code
 or p_date<greatest(v_s.posting_date,v_t.posting_date) then raise exception using errcode='22023',message='ALLOCATION_SOURCE_INVALID';end if;
 if exists(select 1 from finance.open_item_allocations where tenant_id=p_tenant and
 (source_open_item_id in (p_source,p_target) or target_open_item_id in (p_source,p_target)) and posting_date>p_date) then
 raise exception using errcode='22023',message='ALLOCATION_DATE_BEFORE_LATEST';end if;
 select rounding_scale into v_scale from core.legal_entities where id=p_entity and tenant_id=p_tenant;
 v_source:=sales.wave3_decimal_string(p_payload->'source_amount','Source amount',6,true,0,null)::numeric;
 v_target:=sales.wave3_decimal_string(p_payload->'transaction_amount','Target amount',6,true,0,null)::numeric;
 v_write:=sales.wave3_decimal_string(coalesce(p_payload->'write_off','"0"'),'Write-off',6,true,0,null)::numeric;
 v_discount:=sales.wave3_decimal_string(coalesce(p_payload->'discount_amount','"0"'),'Discount',6,true,0,null)::numeric;
 if v_source<=0 or v_target<=0 or v_source<>round(v_source,v_scale) or v_target<>round(v_target,v_scale)
 or v_write<>round(v_write,v_scale) or v_discount<>round(v_discount,v_scale) then raise exception using errcode='22023',message='ALLOCATION_AMOUNT_INVALID';end if;
 if v_write+v_discount>0 then
 perform core.wave3_require_scope(p_tenant,'finance.receipts.adjust',p_entity,p_branch);
 if nullif(trim(p_payload->>'reason'),'') is null then raise exception using errcode='22023',message='REASON_REQUIRED';end if;end if;
 if v_s.currency_code<>v_t.currency_code then
 select * into v_rate from finance.exchange_rates where tenant_id=p_tenant and legal_entity_id=p_entity and status='active'
 and id=(p_payload->>'exchange_rate_id')::uuid and source_currency_code=v_s.currency_code and target_currency_code=v_t.currency_code and effective_date<=p_date;
 if not found then raise exception using errcode='22023',message='ALLOCATION_EXCHANGE_RATE_REQUIRED';end if;v_conversion:=v_rate.rate;
 end if;
 if round(v_source*v_conversion,v_scale)<>v_target then raise exception using errcode='22023',message='ALLOCATION_CURRENCY_MISMATCH';end if;
 v_sr:=finance.flow_residual(p_tenant,p_source);v_tr:=finance.flow_residual(p_tenant,p_target);
 if v_source>-(v_sr->>'amount')::numeric or v_target+v_write+v_discount>(v_tr->>'amount')::numeric then
 raise exception using errcode='22023',message='ALLOCATION_EXCEEDED';end if;
 v_prior:=v_s.original_amount-(v_sr->>'amount')::numeric;
 v_sb:=round((-v_s.original_base_amount)*(-v_prior+v_source)/(-v_s.original_amount),v_scale)-round((-v_s.original_base_amount)*(-v_prior)/(-v_s.original_amount),v_scale);
 v_prior:=v_t.original_amount-(v_tr->>'amount')::numeric;
 v_tb:=round(v_t.original_base_amount*(v_prior+v_target)/v_t.original_amount,v_scale)-round(v_t.original_base_amount*v_prior/v_t.original_amount,v_scale);
 v_ab:=round(v_t.original_base_amount*(v_prior+v_target+v_write+v_discount)/v_t.original_amount,v_scale)-round(v_t.original_base_amount*(v_prior+v_target)/v_t.original_amount,v_scale);
 if v_sb<=0 or v_tb<=0 then raise exception using errcode='22023',message='AMOUNT_BELOW_BASE_PRECISION';end if;
 v_fx:=v_sb-v_tb;
 v_doc:=jsonb_build_object('tenant_id',p_tenant,'legal_entity_id',p_entity,'branch_id',p_branch,'document_date',p_date,
 'customer_id',v_s.party_id,'currency_code',v_s.base_currency_code,'base_currency_code',v_s.base_currency_code,'exchange_rate','1');
 if v_fx<>0 or v_ab<>0 then
 v_control:=finance.flow_mapping(p_tenant,p_entity,'receivable_control',v_s.base_currency_code);
 if v_fx<>0 then
 v_lines:=v_lines||jsonb_build_array(finance.flow_jline(v_control,v_fx,v_fx),finance.flow_jline(
 finance.flow_mapping(p_tenant,p_entity,case when v_fx>0 then 'exchange_gain' else 'exchange_loss' end,v_s.base_currency_code),-v_fx,-v_fx));end if;
 if v_ab>0 then
 v_lines:=v_lines||jsonb_build_array(finance.flow_jline(v_control,-v_ab,-v_ab));
 v_adjust:=round(v_ab*v_write/(v_write+v_discount),v_scale);
 if v_adjust>0 then v_lines:=v_lines||jsonb_build_array(finance.flow_jline(finance.flow_mapping(p_tenant,p_entity,'write_off',v_s.base_currency_code),v_adjust,v_adjust));end if;
 if v_ab-v_adjust>0 then v_lines:=v_lines||jsonb_build_array(finance.flow_jline(finance.flow_mapping(p_tenant,p_entity,'settlement_discount',v_s.base_currency_code),v_ab-v_adjust,v_ab-v_adjust));end if;
 end if;
 v_journal:=finance.flow_post_journal(v_doc,v_lines,'customer_allocation',v_id,p_request,p_command);end if;
 insert into finance.open_item_allocations(id,tenant_id,legal_entity_id,branch_id,source_open_item_id,target_open_item_id,
 source_amount,transaction_amount,source_base_amount,target_base_amount,exchange_difference,write_off,discount_amount,
 adjustment_base_amount,exchange_rate_id,conversion_rate,posting_date,reason,journal_entry_id,request_id,command_id,correlation_id,created_by)
 values(v_id,p_tenant,p_entity,p_branch,p_source,p_target,v_source,v_target,v_sb,v_tb,v_fx,v_write,v_discount,v_ab,v_rate.id,v_conversion,
 p_date,p_payload->>'reason',v_journal,p_request,p_command,p_request,auth.uid());
 return jsonb_build_object('allocation_id',v_id,'journal_entry_id',v_journal,'source_open_item_id',p_source,'target_open_item_id',p_target,
 'source_amount',v_source::text,'transaction_amount',v_target::text,'exchange_difference',v_fx::text,
 'source_residual',finance.flow_residual(p_tenant,p_source),'target_residual',finance.flow_residual(p_tenant,p_target));end $$;

create function api.allocate_customer_receipt(p_tenant_id uuid,p_legal_entity_id uuid,p_branch_id uuid,p_command_id uuid,
 p_idempotency_key uuid,p_client_timestamp timestamptz,p_payload jsonb,p_expected_entity_version bigint default null)
returns jsonb language plpgsql security definer set search_path='' as $$
declare v_command text:='finance.customer_receipt.allocate';v_hash text;v_replay jsonb;v_source finance.open_items%rowtype;
 v_item jsonb;v_result jsonb;v_results jsonb:='[]';v_request uuid:=gen_random_uuid();v_date date:=(p_payload->>'posting_date')::date;v_id uuid;
begin
 perform core.wave3_require_scope(p_tenant_id,'finance.receipts.allocate',p_legal_entity_id,p_branch_id);
 if p_legal_entity_id is null or p_branch_id is null or p_client_timestamp is null or v_date is null
 or jsonb_typeof(p_payload->'allocations') is distinct from 'array' or jsonb_array_length(p_payload->'allocations') not between 1 and 500 then
 raise exception using errcode='22023',message='ALLOCATION_PAYLOAD_INVALID';end if;
 v_hash:=core.wave3_request_hash(v_command,p_command_id,p_tenant_id,p_legal_entity_id,p_branch_id,p_payload,p_expected_entity_version);
 v_replay:=core.wave3_replay(p_tenant_id,v_command,p_command_id,p_idempotency_key,v_hash);if v_replay is not null then return v_replay;end if;
 select * into v_source from finance.open_items where tenant_id=p_tenant_id and legal_entity_id=p_legal_entity_id and branch_id=p_branch_id and id=(p_payload->>'source_open_item_id')::uuid;
 if not found or v_source.original_amount>=0 then raise exception using errcode='22023',message='ALLOCATION_SOURCE_INVALID';end if;
 perform 1 from crm.parties where tenant_id=p_tenant_id and id=v_source.party_id and status='active' for update;
 if not found then raise exception using errcode='22023',message='CUSTOMER_INACTIVE';end if;
 perform finance.wave3_lock_open_period(p_tenant_id,p_legal_entity_id,v_date);
 if v_date>(clock_timestamp() at time zone 'UTC')::date then raise exception using errcode='22023',message='FUTURE_POSTING_DATE';end if;
 for v_id in select id from finance.open_items where tenant_id=p_tenant_id and (id=v_source.id or id in
 (select (x->>'target_open_item_id')::uuid from jsonb_array_elements(p_payload->'allocations') x)) order by id loop
 perform 1 from finance.open_items where id=v_id for update;end loop;
 for v_item in select value from jsonb_array_elements(p_payload->'allocations') loop
 v_result:=finance.flow_allocate(v_source.id,(v_item->>'target_open_item_id')::uuid,p_tenant_id,p_legal_entity_id,p_branch_id,v_item,v_date,v_request,p_command_id);
 v_results:=v_results||jsonb_build_array(v_result);end loop;
 perform finance.flow_refresh_credit(jsonb_build_object('tenant_id',p_tenant_id,'legal_entity_id',p_legal_entity_id,'branch_id',p_branch_id,'customer_id',v_source.party_id));
 return core.wave3_finish_command(p_tenant_id,v_command,p_command_id,'customer_allocation',p_command_id,p_idempotency_key,v_hash,null,
 jsonb_build_object('id',p_command_id,'source_open_item_id',v_source.id,'allocations',v_results,'source_residual',finance.flow_residual(p_tenant_id,v_source.id)),
 p_legal_entity_id,p_branch_id,coalesce(p_payload->'source_context','{}'),
 jsonb_build_object('from_status','open','to_status','allocated'),
 jsonb_build_array(jsonb_build_object('topic',v_command,'payload',jsonb_build_object('source_open_item_id',v_source.id))),'[]',v_request,v_request);end $$;

-- Bounded exact report: no aggregate ever silently drops rows.
create function api.customer_statement(p_tenant_id uuid,p_legal_entity_id uuid,p_branch_id uuid,p_customer_id uuid,
 p_currency_code text,p_as_of date,p_buckets integer[] default array[30,60,90])
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare v_rows jsonb;v_amount numeric;v_base numeric;v_bucket jsonb;v_count integer;begin
 perform core.wave3_require_scope(p_tenant_id,'finance.receivables.view',p_legal_entity_id,p_branch_id);
 if p_branch_id is null or p_customer_id is null or p_as_of is null or p_as_of>(now() at time zone 'UTC')::date
 or p_currency_code is null or p_currency_code!~'^[A-Z]{3}$'
 or p_buckets is null or cardinality(p_buckets) not between 1 and 12 or exists(select 1 from unnest(p_buckets) x where x is null or x<=0)
 or p_buckets<>(select array_agg(distinct x order by x) from unnest(p_buckets) x) then
 raise exception using errcode='22023',message='STATEMENT_FILTER_INVALID';end if;
 select count(*) into v_count from (select id from finance.open_items where tenant_id=p_tenant_id and legal_entity_id=p_legal_entity_id
 and branch_id=p_branch_id and party_id=p_customer_id and kind='AR' and currency_code=p_currency_code and posting_date<=p_as_of limit 10001) bounded;
 if v_count>10000 then raise exception using errcode='54000',message='LIMIT_EXCEEDED';end if;
 with items as (select o.*,finance.flow_residual(p_tenant_id,o.id,p_as_of) residual from finance.open_items o
 where o.tenant_id=p_tenant_id and o.legal_entity_id=p_legal_entity_id and o.branch_id=p_branch_id and o.party_id=p_customer_id
 and o.kind='AR' and o.currency_code=p_currency_code and o.posting_date<=p_as_of), rows as (
 select id,source_type,source_id,document_number,currency_code,posting_date,due_date,original_amount::text,original_base_amount::text,
 residual->>'amount' as open_amount,residual->>'base_amount' as open_base_amount,
 case when original_amount<0 then -1 when due_date>=p_as_of then 0 else
 1+(select count(*) from unnest(p_buckets) b where p_as_of-due_date>b) end bucket from items)
 select coalesce(jsonb_agg(to_jsonb(rows) order by posting_date,id),'[]'),coalesce(sum(open_amount::numeric),0),coalesce(sum(open_base_amount::numeric),0)
 into v_rows,v_amount,v_base from rows;
 select coalesce(jsonb_agg(jsonb_build_object('bucket',bucket,'amount',amount::text,'base_amount',base_amount::text) order by bucket),'[]') into v_bucket
 from (select (x->>'bucket')::integer bucket,sum((x->>'open_amount')::numeric) amount,sum((x->>'open_base_amount')::numeric) base_amount
 from jsonb_array_elements(v_rows) x group by (x->>'bucket')::integer) b;
 return jsonb_build_object('customer_id',p_customer_id,'currency_code',p_currency_code,'as_of',p_as_of,
 'rows',v_rows,'aging',v_bucket,'bucket_days',p_buckets,'open_amount',v_amount::text,'open_base_amount',v_base::text,
 'basis','posting_date','unapplied_credits_separate',true);end $$;

-- Private RLS-compliant residual views for current item and receipt detail.
create function finance.flow_visible_residual(p_tenant uuid,p_id uuid) returns jsonb
language plpgsql stable security definer set search_path='' as $$
declare v_o finance.open_items%rowtype;begin select * into v_o from finance.open_items where tenant_id=p_tenant and id=p_id;
 if not found or not core.is_tenant_member(p_tenant) or not core.has_permission(p_tenant,'finance.receivables.view',v_o.legal_entity_id,v_o.branch_id) then return null;end if;
 return finance.flow_residual(p_tenant,p_id);end $$;
create view api.receivable_balances with(security_invoker=true) as
select o.id,o.tenant_id,o.legal_entity_id,o.branch_id,o.party_id,o.currency_code,o.source_type,o.source_id,o.posting_date,o.due_date,
 sales.flow_exact_json(to_jsonb(o))||finance.flow_visible_residual(o.tenant_id,o.id) as detail from finance.open_items o;

revoke all on function finance.flow_allocate(uuid,uuid,uuid,uuid,uuid,jsonb,date,uuid,uuid),
 api.allocate_customer_receipt(uuid,uuid,uuid,uuid,uuid,timestamptz,jsonb,bigint),
 api.customer_statement(uuid,uuid,uuid,uuid,text,date,integer[]),finance.flow_visible_residual(uuid,uuid) from public,anon,authenticated;
grant execute on function api.allocate_customer_receipt(uuid,uuid,uuid,uuid,uuid,timestamptz,jsonb,bigint),
 api.customer_statement(uuid,uuid,uuid,uuid,text,date,integer[]),finance.flow_visible_residual(uuid,uuid) to authenticated;
revoke all on api.receivable_balances from public,anon,authenticated;
grant select on api.receivable_balances to authenticated;
notify pgrst,'reload schema';
