-- Nonempty realized-provider fixtures only; composed inside strict ROLLBACK.
-- Uses the installed quotation snapshot/header/line schema. These records are
-- synthetic projections, not real posted-command/MFA acceptance evidence.
select pg_temp.actor('owner');
insert into core.role_permissions values(pg_temp.fid('t'),pg_temp.fid('owner.role'),'sales.quotations.view') on conflict do nothing;
insert into core.warehouses(id,tenant_id,legal_entity_id,branch_id,name,code,created_by)
 values(pg_temp.fid('realized.warehouse'),pg_temp.fid('t'),pg_temp.fid('e'),pg_temp.fid('b'),'Synthetic realized warehouse','SYN-REAL',auth.uid());
insert into crm.opportunities(id,tenant_id,legal_entity_id,branch_id,code,prospect_name,owner_id,currency_code,created_by,updated_by,
 expected_close_date,request_id,command_id,correlation_id,client_timestamp)
 values(pg_temp.fid('realized.other.opportunity'),pg_temp.fid('t'),pg_temp.fid('e'),pg_temp.fid('b'),'SYN-OTHER-REAL','Synthetic other cohort',auth.uid(),'LKR',auth.uid(),auth.uid(),
 current_date-1,pg_temp.fid('realized.other.opportunity'),pg_temp.fid('realized.other.opportunity'),pg_temp.fid('realized.other.opportunity'),statement_timestamp());
insert into sales.quotations(id,tenant_id,legal_entity_id,branch_id,document_number,customer_id,opportunity_id,quotation_date,valid_until,
 currency_code,base_currency_code,exchange_rate,rate_date,salesperson_id,request_id,command_id,correlation_id,client_timestamp,created_by,updated_by)
 select pg_temp.fid('realized.quote.'||x),pg_temp.fid('t'),pg_temp.fid('e'),pg_temp.fid('b'),'SYN-REAL-'||x,pg_temp.fid('cash.party'),
 case x when 'cohort' then pg_temp.fid('o') else pg_temp.fid('realized.other.opportunity') end,current_date-5,current_date+5,
 'LKR','LKR',1,current_date-5,auth.uid(),pg_temp.fid('realized.quote.'||x),pg_temp.fid('realized.quote.'||x),pg_temp.fid('realized.quote.'||x),current_date-5,auth.uid(),auth.uid()
 from unnest(array['cohort','other']) x;
-- This is the same top-level quotation projection captured by the installed
-- submit/convert producers. Do not invent a mutable current-CRM mapping.
insert into sales.sales_orders(id,tenant_id,legal_entity_id,branch_id,source_quotation_id,source_quotation_revision,source_snapshot,
 customer_id,order_date,promised_date,warehouse_id,currency_code,base_currency_code,exchange_rate,rate_date,salesperson_id,
 request_id,command_id,correlation_id,client_timestamp,created_by,updated_by)
 select pg_temp.fid('realized.order.'||x),pg_temp.fid('t'),pg_temp.fid('e'),pg_temp.fid('b'),pg_temp.fid('realized.quote.'||x),1,
 sales.quotation_entity(pg_temp.fid('realized.quote.'||x)),pg_temp.fid('cash.party'),current_date-4,current_date-1,pg_temp.fid('realized.warehouse'),
 'LKR','LKR',1,current_date-4,auth.uid(),pg_temp.fid('realized.order.'||x),pg_temp.fid('realized.order.'||x),pg_temp.fid('realized.order.'||x),current_date-4,auth.uid(),auth.uid()
 from unnest(array['cohort','other']) x;
create function pg_temp.realized_header(n text,k text,o uuid,d date,amount numeric,p timestamptz default null) returns void
 language plpgsql as $$declare rel text:=case k when 'invoice' then 'sales_invoices' else 'sales_returns' end;begin
 execute format('insert into sales.%I(id,tenant_id,legal_entity_id,branch_id,customer_id,document_date,due_date,currency_code,base_currency_code,exchange_rate,rate_date,
 rounding_scale,sales_order_id,grand_total,base_total,request_id,command_id,correlation_id,client_timestamp,created_by,updated_by,created_at)
 values($1,$2,$3,$4,$5,$6,$6,''LKR'',''LKR'',1,$6,6,$7,$8,$8,$1,$1,$1,$9,$10,$10,$9)',rel)
 using pg_temp.fid('realized.'||n),pg_temp.fid('t'),pg_temp.fid('e'),pg_temp.fid('b'),pg_temp.fid('cash.party'),d,o,amount,
 coalesce(p,current_date-1)-interval '1 minute',auth.uid();
 if n='invoice' then
  insert into sales.sales_invoice_lines(id,tenant_id,legal_entity_id,branch_id,document_id,line_number,description,quantity,base_quantity,line_total,snapshot,created_by)
   values(pg_temp.fid('realized.invoice.line'),pg_temp.fid('t'),pg_temp.fid('e'),pg_temp.fid('b'),pg_temp.fid('realized.invoice'),1,'Synthetic realized source',1,1,amount,'{}',auth.uid());
 elsif k='return' then
  insert into sales.sales_return_lines(id,tenant_id,legal_entity_id,branch_id,document_id,line_number,description,quantity,base_quantity,line_total,sales_invoice_line_id,snapshot,created_by)
   values(pg_temp.fid('realized.'||n||'.line'),pg_temp.fid('t'),pg_temp.fid('e'),pg_temp.fid('b'),pg_temp.fid('realized.'||n),1,'Synthetic realized credit',1,1,amount,pg_temp.fid('realized.invoice.line'),'{}',auth.uid());
 end if;
 if p is not null then execute format('update sales.%I set status=''posted'',posted_at=$2,posted_by=$3 where id=$1',rel)
  using pg_temp.fid('realized.'||n),p,auth.uid();end if;
end $$;
select pg_temp.realized_header('invoice','invoice',pg_temp.fid('realized.order.cohort'),current_date-1,12.000003,(current_date-1)::timestamptz+interval '10 hours');
select pg_temp.realized_header('credit','return',pg_temp.fid('realized.order.cohort'),current_date-1,2.000001,(current_date-1)::timestamptz+interval '11 hours');
select pg_temp.realized_header('draft','invoice',pg_temp.fid('realized.order.cohort'),current_date-1,99.000000);
select pg_temp.realized_header('before_horizon','invoice',pg_temp.fid('realized.order.cohort'),current_date-31,99.000000,(current_date-1)::timestamptz);
select pg_temp.realized_header('at_horizon_end','invoice',pg_temp.fid('realized.order.cohort'),current_date,99.000000,current_date::timestamptz);
select pg_temp.realized_header('other_cohort','invoice',pg_temp.fid('realized.order.other'),current_date-1,99.000000,(current_date-1)::timestamptz);
select pg_temp.realized_header('late_record','invoice',pg_temp.fid('realized.order.cohort'),current_date-1,99.000000,statement_timestamp()-interval '1 second');
create temporary table w5_realized_cutoff as select statement_timestamp()-interval '2 seconds' value;
create temporary table w5_realized_documents as select api.wave5_pipeline_realized(pg_temp.fid('t'),pg_temp.fid('e'),pg_temp.fid('b'),
 pg_temp.fid('realized'),(select value from w5_realized_cutoff)) result;
select is(jsonb_array_length((select result->'documents' from w5_realized_documents)),2,
 'Realized mapping includes exactly the posted frozen-cohort invoice and order-linked credit');
select is((select sum((d->>'amount')::numeric)::text from jsonb_array_elements((select result->'documents' from w5_realized_documents)) d),'10.000002',
 'Nonempty SQL realized gross is exact invoice minus credit with no duplicate line counting');
select ok((select bool_and(d->>'opportunityId'=pg_temp.fid('o')::text and d->>'currency'='LKR' and d->>'version'='2')
 from jsonb_array_elements((select result->'documents' from w5_realized_documents)) d),
 'Nonempty realized documents preserve original frozen opportunity, currency and immutable posted versions');
select is(api.wave5_pipeline_realized(pg_temp.fid('t'),pg_temp.fid('e'),pg_temp.fid('b'),pg_temp.fid('realized'),(select value from w5_realized_cutoff)),
 (select result from w5_realized_documents),'Identical realization cutoff retains the complete original document result');
select is((select sum((d->>'amount')::numeric) filter(where d->>'kind'='credit_return')::text
 from jsonb_array_elements((select result->'documents' from w5_realized_documents)) d),'-2.000001',
 'Credit-return gross retains its explicit negative sign');
delete from core.role_permissions where tenant_id=pg_temp.fid('t') and role_id=pg_temp.fid('owner.role') and permission_code='sales.returns.view';
select throws_ok($$select api.wave5_pipeline_realized(pg_temp.fid('t'),pg_temp.fid('e'),pg_temp.fid('b'),pg_temp.fid('realized'),statement_timestamp())$$,
 '42501','Permission denied or multi-factor authentication required.','Realized results recheck revoked source-return authority');
insert into core.role_permissions values(pg_temp.fid('t'),pg_temp.fid('owner.role'),'sales.returns.view');
select throws_ok($$select api.wave5_pipeline_realized(pg_temp.fid('t'),pg_temp.fid('e'),pg_temp.fid('b'),pg_temp.fid('realized'),(current_date-1)::timestamptz)$$,
 '55000','REALIZED_HORIZON_OPEN','Realization cannot publish while its half-open horizon remains open');
select pg_temp.realized_header('line_only_credit','return',null,current_date-1,1.000001,(current_date-1)::timestamptz+interval '12 hours');
select throws_ok($$select api.wave5_pipeline_realized(pg_temp.fid('t'),pg_temp.fid('e'),pg_temp.fid('b'),pg_temp.fid('realized'),statement_timestamp())$$,
 '55000','REALIZED_MAPPING_INCOMPLETE','Invoice-line-linked credit without an order header rejects partial realized totals');
