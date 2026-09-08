-- Governed posting prerequisites; no client has direct table writes.
create function api.upsert_receivables_setup(p_tenant_id uuid,p_legal_entity_id uuid,p_branch_id uuid,p_command_id uuid,
 p_idempotency_key uuid,p_client_timestamp timestamptz,p_payload jsonb,p_expected_entity_version bigint default null)
returns jsonb language plpgsql security definer set search_path='' as $$
declare v_resource text:=p_payload->>'resource';v_id uuid:=coalesce((p_payload->>'id')::uuid,gen_random_uuid());
 v_command text:='finance.receivables_setup.upsert';v_request uuid:=gen_random_uuid();v_hash text;v_replay jsonb;
 v_before jsonb;v_after jsonb;v_mapping finance.posting_mappings%rowtype;v_bank finance.cash_bank_accounts%rowtype;
 v_purpose text:=p_payload->>'purpose';v_account uuid:=(p_payload->>'account_id')::uuid;
begin
 perform core.wave3_require_scope(p_tenant_id,'finance.setup.manage',p_legal_entity_id,p_branch_id);
 if p_legal_entity_id is null or p_branch_id is null or p_client_timestamp is null or v_resource not in ('posting_mapping','cash_bank_account') then
 raise exception using errcode='22023',message='SETUP_PAYLOAD_INVALID';end if;
 v_hash:=core.wave3_request_hash(v_command,p_command_id,p_tenant_id,p_legal_entity_id,p_branch_id,p_payload,p_expected_entity_version);
 v_replay:=core.wave3_replay(p_tenant_id,v_command,p_command_id,p_idempotency_key,v_hash);if v_replay is not null then return v_replay;end if;
 perform pg_advisory_xact_lock(hashtextextended(p_tenant_id::text||':'||p_legal_entity_id::text||':receivables_setup',0));
 if v_resource='posting_mapping' then
 select * into v_mapping from finance.posting_mappings where tenant_id=p_tenant_id and legal_entity_id=p_legal_entity_id and purpose=v_purpose for update;
 if found then v_id:=v_mapping.id;v_before:=sales.flow_exact_json(to_jsonb(v_mapping));
 perform core.wave3_assert_expected_version(v_mapping.version,p_expected_entity_version,v_before);
 if (v_mapping.account_id<>v_account or coalesce(p_payload->>'status','active')<>v_mapping.status)
 and exists(select 1 from finance.journal_entries where tenant_id=p_tenant_id and legal_entity_id=p_legal_entity_id) then
 raise exception using errcode='55000',message='POSTING_MAPPING_IN_USE';end if;
 elsif p_expected_entity_version is not null then raise exception using errcode='40001',message='VERSION_CONFLICT';end if;
 perform finance.flow_account(p_tenant_id,p_legal_entity_id,v_account,
 case v_purpose when 'receivable_control' then 'asset' when 'output_tax' then 'liability' when 'exchange_gain' then 'revenue' else 'expense' end,
 (select currency_code from core.legal_entities where id=p_legal_entity_id));
 insert into finance.posting_mappings(id,tenant_id,legal_entity_id,purpose,account_id,status,created_by,updated_by)
 values(v_id,p_tenant_id,p_legal_entity_id,v_purpose,v_account,coalesce(p_payload->>'status','active'),auth.uid(),auth.uid())
 on conflict(tenant_id,legal_entity_id,purpose) do update set account_id=excluded.account_id,status=excluded.status,updated_by=auth.uid();
 select sales.flow_exact_json(to_jsonb(m)) into v_after from finance.posting_mappings m where id=v_id;
 else
 select * into v_bank from finance.cash_bank_accounts where tenant_id=p_tenant_id and id=v_id for update;
 if found then
 if v_bank.legal_entity_id<>p_legal_entity_id or v_bank.branch_id<>p_branch_id then raise exception using errcode='42501',message='DOCUMENT_SCOPE_INVALID';end if;
 v_before:=sales.flow_exact_json(to_jsonb(v_bank));perform core.wave3_assert_expected_version(v_bank.version,p_expected_entity_version,v_before);
 if (v_bank.account_id<>v_account or v_bank.currency_code<>p_payload->>'currency_code')
 and exists(select 1 from sales.customer_receipts where tenant_id=p_tenant_id and cash_bank_account_id=v_id and status='posted') then
 raise exception using errcode='55000',message='CASH_BANK_ACCOUNT_IN_USE';end if;
 elsif p_expected_entity_version is not null then raise exception using errcode='40001',message='VERSION_CONFLICT';end if;
 perform finance.flow_account(p_tenant_id,p_legal_entity_id,v_account,'asset',p_payload->>'currency_code');
 if not exists(select 1 from core.currencies where code=p_payload->>'currency_code' and active) then raise exception using errcode='22023',message='CURRENCY_INVALID';end if;
 insert into finance.cash_bank_accounts(id,tenant_id,legal_entity_id,branch_id,code,name,account_kind,account_id,currency_code,status,created_by,updated_by)
 values(v_id,p_tenant_id,p_legal_entity_id,p_branch_id,p_payload->>'code',p_payload->>'name',p_payload->>'account_kind',v_account,
 p_payload->>'currency_code',coalesce(p_payload->>'status','active'),auth.uid(),auth.uid())
 on conflict(id) do update set code=excluded.code,name=excluded.name,account_kind=excluded.account_kind,
 account_id=excluded.account_id,currency_code=excluded.currency_code,status=excluded.status,updated_by=auth.uid();
 select sales.flow_exact_json(to_jsonb(b)) into v_after from finance.cash_bank_accounts b where id=v_id;
 end if;
 return core.wave3_finish_command(p_tenant_id,v_command,p_command_id,v_resource,v_id,p_idempotency_key,v_hash,v_before,v_after,
 p_legal_entity_id,p_branch_id,'{}',null,jsonb_build_array(jsonb_build_object('topic',v_command,'payload',jsonb_build_object('resource',v_resource))),'[]',v_request,v_request);
end $$;
revoke all on function api.upsert_receivables_setup(uuid,uuid,uuid,uuid,uuid,timestamptz,jsonb,bigint) from public,anon,authenticated;
grant execute on function api.upsert_receivables_setup(uuid,uuid,uuid,uuid,uuid,timestamptz,jsonb,bigint) to authenticated;
create policy setup_or_receipt_reference on finance.cash_bank_accounts for select to authenticated using(
 core.is_tenant_member(tenant_id) and (core.has_permission(tenant_id,'finance.receipts.manage',legal_entity_id,branch_id)
 or core.has_permission(tenant_id,'finance.setup.view',legal_entity_id,branch_id)
 or core.has_permission(tenant_id,'finance.setup.manage',legal_entity_id,branch_id)));
notify pgrst,'reload schema';
