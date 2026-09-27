-- UNAPPLIED additive read contract; no posting engine or historical writes.
create function api.posted_journal_evidence(p_tenant_id uuid,p_legal_entity_id uuid,p_branch_id uuid,
 p_journal_id uuid,p_after_line integer default 0) returns jsonb
language plpgsql stable security definer set search_path='' as $$
declare j finance.journal_entries%rowtype;header jsonb;rows jsonb;result jsonb;n integer;
 debit numeric;credit numeric;tx_debit numeric;tx_credit numeric;next_line integer;stock_branch uuid;branches uuid[];
begin
 perform core.wave3_require_scope(p_tenant_id,'finance.view',p_legal_entity_id,p_branch_id);
 if p_legal_entity_id is null or p_branch_id is null then
  raise exception using errcode='42501',message='JOURNAL_UNAVAILABLE';end if;
 select * into j from finance.journal_entries where tenant_id=p_tenant_id
  and legal_entity_id=p_legal_entity_id and id=p_journal_id and status='posted';
 if not found then raise exception using errcode='42501',message='JOURNAL_UNAVAILABLE';end if;
 -- Historical source branches may be retired. Authorization is still current.
 perform core.require_permission(p_tenant_id,'finance.view',p_legal_entity_id,j.branch_id);
 if not exists(select 1 from core.branches where tenant_id=p_tenant_id
  and legal_entity_id=p_legal_entity_id and id=j.branch_id) then
  raise exception using errcode='42501',message='JOURNAL_UNAVAILABLE';end if;
 select array_agg(branch_id) into branches from(select distinct branch_id from inventory.stock_movements
  where tenant_id=p_tenant_id and legal_entity_id=p_legal_entity_id and command_id=j.command_id limit 501)q;
 if cardinality(branches)>500 then raise exception using errcode='54000',message='JOURNAL_BRANCH_LIMIT';end if;
 if cardinality(branches)>0 then
  branches:=branches||array[p_branch_id,j.branch_id];
  for stock_branch in select distinct unnest(branches) loop
   perform core.require_permission(p_tenant_id,'inventory.stock.view',p_legal_entity_id,stock_branch);
   perform core.require_permission(p_tenant_id,'inventory.cost.view',p_legal_entity_id,stock_branch);
  end loop;
 end if;
 if p_after_line is null or p_after_line<0 or p_after_line>10000 or (p_after_line>0 and not exists(
  select 1 from finance.journal_lines where tenant_id=p_tenant_id and journal_entry_id=j.id and line_number=p_after_line)) then
  raise exception using errcode='22023',message='JOURNAL_CURSOR_INVALID';end if;
 select count(*),sum(base_debit),sum(base_credit),sum(transaction_debit),sum(transaction_credit)
  into n,debit,credit,tx_debit,tx_credit from finance.journal_lines where tenant_id=p_tenant_id and journal_entry_id=j.id;
 if n>10000 then raise exception using errcode='54000',message='JOURNAL_LINE_LIMIT';end if;
 if n<2 or debit<>credit then raise exception using errcode='55000',message='JOURNAL_BALANCE_INVALID';end if;
 header:=sales.flow_exact_json(jsonb_build_object('id',j.id,'tenant_id',j.tenant_id,'legal_entity_id',j.legal_entity_id,
  'branch_id',j.branch_id,'branch_name',(select name from core.branches where tenant_id=j.tenant_id and id=j.branch_id),
  'branch_status',(select status from core.branches where tenant_id=j.tenant_id and id=j.branch_id),
  'document_number',j.document_number,'posting_date',j.posting_date,'status',j.status,'fiscal_period_id',j.fiscal_period_id,
  'currency_code',j.currency_code,'base_currency_code',j.base_currency_code,'exchange_rate',j.exchange_rate,
  'source_type',j.source_type,'source_id',j.source_id,'command_id',j.command_id,'request_id',j.request_id,
  'correlation_id',j.correlation_id,'rule_version',j.rule_version,'created_at',j.created_at,'created_by',j.created_by,
  'transaction_debit',tx_debit,'transaction_credit',tx_credit,'base_debit',debit,'base_credit',credit))
  ||jsonb_build_object('line_count',n,'label_basis','current_catalogue','stock_cost_access_required',coalesce(cardinality(branches)>0,false));
 select coalesce(jsonb_agg(sales.flow_exact_json(to_jsonb(q)) order by line_number),'[]') into rows from(
  select l.id,l.tenant_id,l.legal_entity_id,l.branch_id,l.journal_entry_id,l.line_number,l.account_id,
   a.code account_code,a.name account_name,a.status account_status,l.party_id,l.source_line_id,l.currency_code,
   l.transaction_debit,l.transaction_credit,l.base_debit,l.base_credit,l.posting_date,
   l.cost_centre_id,l.project_id,l.dimension_snapshot
  from finance.journal_lines l join finance.accounts a on a.tenant_id=l.tenant_id and a.legal_entity_id=l.legal_entity_id and a.id=l.account_id
  where l.tenant_id=p_tenant_id and l.journal_entry_id=j.id and l.line_number>p_after_line order by l.line_number limit 51)q;
 if jsonb_array_length(rows)=51 then rows:=rows-50;next_line:=(rows->49->>'line_number')::integer;end if;
 result:=jsonb_build_object('tenant_id',p_tenant_id,'legal_entity_id',p_legal_entity_id,'branch_id',p_branch_id,
  'journal_id',j.id,'after_line',p_after_line,'journal',header,'items',rows,'next_cursor',next_line);
 if octet_length(result::text)>1048576 then raise exception using errcode='54000',message='JOURNAL_RESPONSE_LIMIT';end if;
 return result;
end$$;
revoke all on function api.posted_journal_evidence(uuid,uuid,uuid,uuid,integer) from public,anon,authenticated;
grant execute on function api.posted_journal_evidence(uuid,uuid,uuid,uuid,integer) to authenticated;
notify pgrst,'reload schema';
