-- Tax-defined sales and returns through the real posted journal engine.
select set_config('request.jwt.claims',jsonb_build_object('sub',pg_temp.fid('actor'),
 'role','authenticated','aal','aal2')::text,true);
select set_config('request.jwt.claim.sub',pg_temp.fid('actor')::text,true);
insert into core.role_assignments(tenant_id,membership_id,role_id,legal_entity_id,
 branch_id,created_by) values(pg_temp.fid('tenant'),pg_temp.fid('actor.membership'),
 pg_temp.fid('actor.role'),pg_temp.fid('entity'),null,pg_temp.fid('actor'));
insert into finance.tax_definitions(id,tenant_id,legal_entity_id,code,name,rate,kind,
 inclusive,valid_from,created_by,updated_by)
values(pg_temp.fid('tax.output'),pg_temp.fid('tenant'),pg_temp.fid('entity'),
 'OUTPUT15','Output 15 percent',15,'output',false,'2026-01-01',
 pg_temp.fid('actor'),pg_temp.fid('actor')),
(pg_temp.fid('tax.exempt'),pg_temp.fid('tenant'),pg_temp.fid('entity'),
 'EXEMPT0','Exempt services',0,'exempt',false,'2026-01-01',
 pg_temp.fid('actor'),pg_temp.fid('actor'));
create function pg_temp.tax_approve_post(n text) returns void language plpgsql as $$begin
 perform set_config('request.jwt.claims',jsonb_build_object('sub',pg_temp.fid('approver'),
  'role','authenticated','aal','aal2')::text,true);
 perform set_config('request.jwt.claim.sub',pg_temp.fid('approver')::text,true);
 perform pg_temp.call('decide_operational_approval',jsonb_build_object(
  'document_type','sales_invoice','document_id',pg_temp.fid(n),'decision','approved'),
  (select version from sales.sales_invoices where id=pg_temp.fid(n)));
 perform set_config('request.jwt.claims',jsonb_build_object('sub',pg_temp.fid('actor'),
  'role','authenticated','aal','aal2')::text,true);
 perform set_config('request.jwt.claim.sub',pg_temp.fid('actor')::text,true);
 perform pg_temp.call('post_sales_invoice',jsonb_build_object('document_id',pg_temp.fid(n)),
  (select version from sales.sales_invoices where id=pg_temp.fid(n)));
end$$;
select pg_temp.save_submit('sales_invoice','tax.invoice',pg_temp.header('tax.invoice')
 ||jsonb_build_object('lines',jsonb_build_array(pg_temp.line('tax.invoice.line',
 'service','1','100',jsonb_build_object('tax_definition_id',pg_temp.fid('tax.output'))))));
select pg_temp.tax_approve_post('tax.invoice');
select pg_temp.save_submit('sales_invoice','tax.exempt.invoice',
 pg_temp.header('tax.exempt.invoice')||jsonb_build_object('lines',jsonb_build_array(
 pg_temp.line('tax.exempt.line','service','1','50',
 jsonb_build_object('tax_definition_id',pg_temp.fid('tax.exempt'))))));
select pg_temp.tax_approve_post('tax.exempt.invoice');
create function pg_temp.sales_tax_call(n text,d date) returns jsonb language sql as $$
 select api.generate_tax_summary(pg_temp.fid('tenant'),pg_temp.fid('entity'),
 pg_temp.fid('branch'),pg_temp.fid(n||'.command'),pg_temp.fid(n||'.key'),
 '2026-09-26T00:00:00Z',jsonb_build_object('id',pg_temp.fid(n),
 'period_id',pg_temp.fid('period'),'as_of',d,'branch_filter_id',pg_temp.fid('branch')),0)$$;
create temporary table tax_sales_responses(name text primary key,response jsonb);
insert into tax_sales_responses values('before',pg_temp.sales_tax_call('tax.before','2026-09-02'));
select is((select response#>>'{entity,status}' from tax_sales_responses where name='before'),
 'generated','posted sales tax lines have complete version and journal provenance');
select is((select response#>>'{entity,output_tax_base}' from tax_sales_responses
 where name='before'),'15.000000','output tax agrees with posted liability credit');
select is((select response#>>'{entity,exempt_taxable_base}' from tax_sales_responses
 where name='before'),'50.000000','exempt treatment preserves posted taxable basis without tax credit');
select is((select jsonb_array_length(api.tax_summary_page(pg_temp.fid('tenant'),
 pg_temp.fid('entity'),pg_temp.fid('branch'),pg_temp.fid('tax.before'),0,
 pg_temp.fid('tax.invoice.line'))->'items')),1,
 'tax line drill selects one posted source and its journal');
select is((select (value->>'tax_base')::numeric from jsonb_array_elements(
 api.tax_summary_page(pg_temp.fid('tenant'),pg_temp.fid('entity'),pg_temp.fid('branch'),
 pg_temp.fid('tax.before'),0,pg_temp.fid('tax.invoice.line'))->'items') value),
 15::numeric,'output tax drill uses journal base credit');
select pg_temp.save_submit('sales_return','tax.return',
 pg_temp.header('tax.return','2026-09-06')||jsonb_build_object('reason','Taxed service return',
 'lines',jsonb_build_array(jsonb_build_object('line_id',pg_temp.fid('tax.return.line'),
 'sales_invoice_line_id',pg_temp.fid('tax.invoice.line'),'base_quantity','1',
 'disposition','no_restock'))));
select pg_temp.post('sales_return','tax.return');
insert into tax_sales_responses values('after',pg_temp.sales_tax_call('tax.after','2026-09-07'));
select is((select response#>>'{entity,output_tax_base}' from tax_sales_responses
 where name='after'),'0.000000','posted return reverses output tax in report period');
select is((select response#>>'{entity,status}' from tax_sales_responses
 where name='after'),'generated','return tax journal and snapshot reconcile');
select is((select response#>>'{entity,output_tax_base}' from tax_sales_responses
 where name='before'),'15.000000','later return does not rewrite frozen prior tax report');
update finance.tax_definitions set rate=16 where id=pg_temp.fid('tax.output');
select is((select rate from finance.tax_definition_versions where definition_id=pg_temp.fid('tax.output')
 and version=1),15::numeric,'later Wave 2 edit retains posted tax definition version');
select is((select response#>>'{entity,status}' from tax_sales_responses
 where name='before'),'generated','later tax definition edit cannot rewrite saved report');
select throws_ok($$select api.generate_tax_summary(pg_temp.fid('tenant'),pg_temp.fid('entity'),
 pg_temp.fid('branch'),pg_temp.fid('tax.bad.branch.command'),pg_temp.fid('tax.bad.branch.key'),
 '2026-09-26T00:00:00Z',jsonb_build_object('id',pg_temp.fid('tax.bad.branch'),
 'period_id',pg_temp.fid('period'),'as_of','2026-09-02',
 'branch_filter_id',pg_temp.fid('foreign.branch')),0)$$,
 '22023','TAX_REPORT_BRANCH_INVALID','tax filter cannot cross the requesting branch');
