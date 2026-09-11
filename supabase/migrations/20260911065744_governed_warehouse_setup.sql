-- Add the missing warehouse setup command; existing read policy is preserved.
create function core.upsert_warehouse_impl(
  p_tenant_id uuid, p_legal_entity_id uuid, p_payload jsonb,
  p_expected_version bigint, p_idempotency_key uuid
) returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  v_actor uuid := (select auth.uid());
  v_branch uuid;
  v_id uuid;
  v_code text;
  v_name text;
  v_status text;
  v_hash text;
  v_replay jsonb;
  v_before jsonb;
  v_row core.warehouses%rowtype;
begin
  if v_actor is null then
    raise exception using errcode='42501', message='Authentication required.';
  end if;
  if p_payload is null or jsonb_typeof(p_payload) <> 'object' then
    raise exception using errcode='22023', message='Warehouse payload must be an object.';
  end if;
  v_branch := nullif(p_payload->>'branch_id','')::uuid;
  if p_legal_entity_id is null or v_branch is null then
    raise exception using errcode='22023', message='Warehouse legal entity and branch are required.';
  end if;
  perform core.require_permission(p_tenant_id,'core.setup.manage',p_legal_entity_id,v_branch);
  v_hash := core.wave2_request_hash('upsert_warehouse',p_tenant_id,p_legal_entity_id,p_payload,p_expected_version);
  v_replay := core.wave2_replay(p_tenant_id,'upsert_warehouse',p_idempotency_key,v_hash);
  if v_replay is not null then return v_replay; end if;

  perform 1 from core.branches b join core.legal_entities le
    on le.tenant_id=b.tenant_id and le.id=b.legal_entity_id
    where b.tenant_id=p_tenant_id and b.id=v_branch
      and b.legal_entity_id=p_legal_entity_id and b.status='active' and le.status='active'
    for share of b,le;
  if not found then
    raise exception using errcode='22023', message='Warehouse branch must be active in the selected legal entity.';
  end if;
  v_code := upper(trim(p_payload->>'code'));
  v_name := trim(p_payload->>'name');
  v_status := coalesce(nullif(p_payload->>'status',''),'active');
  if coalesce(v_code,'') !~ '^[A-Z0-9][A-Z0-9_-]{1,19}$'
     or coalesce(length(v_name),0) not between 2 and 160
     or v_status not in ('active','inactive') then
    raise exception using errcode='22023', message='Warehouse code, name or status is invalid.';
  end if;
  v_id := nullif(p_payload->>'id','')::uuid;
  if v_id is null then
    if p_expected_version is not null then
      raise exception using errcode='22023', message='Expected version is only valid for an existing warehouse.';
    end if;
    insert into core.warehouses(tenant_id,legal_entity_id,branch_id,code,name,status,created_by)
      values(p_tenant_id,p_legal_entity_id,v_branch,v_code,v_name,v_status,v_actor)
      returning * into v_row;
  else
    select * into v_row from core.warehouses
      where tenant_id=p_tenant_id and id=v_id and legal_entity_id=p_legal_entity_id and branch_id=v_branch
      for update;
    if not found then
      raise exception using errcode='P0002', message='Warehouse was not found in this scope.';
    end if;
    perform core.wave2_assert_expected_version(v_row.version,p_expected_version);
    v_before := to_jsonb(v_row);
    update core.warehouses set code=v_code,name=v_name,status=v_status
      where tenant_id=p_tenant_id and id=v_id returning * into v_row;
  end if;
  return core.wave2_finish_command(p_tenant_id,'upsert_warehouse','warehouse',v_row.id,
    p_idempotency_key,v_hash,v_before,to_jsonb(v_row),p_legal_entity_id,v_branch);
end;
$$;
revoke execute on function core.upsert_warehouse_impl(uuid,uuid,jsonb,bigint,uuid) from public,anon,authenticated;

create function api.upsert_warehouse(
  p_tenant_id uuid, p_legal_entity_id uuid, p_payload jsonb,
  p_expected_version bigint default null, p_idempotency_key uuid default gen_random_uuid()
) returns jsonb language sql security definer set search_path = '' as $$
  select core.upsert_warehouse_impl(p_tenant_id,p_legal_entity_id,p_payload,p_expected_version,p_idempotency_key);
$$;
revoke execute on function api.upsert_warehouse(uuid,uuid,jsonb,bigint,uuid) from public,anon;
grant execute on function api.upsert_warehouse(uuid,uuid,jsonb,bigint,uuid) to authenticated;
