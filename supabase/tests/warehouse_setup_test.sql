begin;
create temporary table warehouse_checks(name text);
create function pg_temp.wid(v text) returns uuid language sql immutable as $$select md5('warehouse-setup-test:'||v)::uuid$$;
create function pg_temp.wactor(v text, aal text default 'aal2') returns void language plpgsql as $$begin
  perform set_config('request.jwt.claims',jsonb_build_object('sub',pg_temp.wid(v),'role','authenticated','aal',aal)::text,true);
  perform set_config('request.jwt.claim.sub',pg_temp.wid(v)::text,true);
end$$;
create function pg_temp.wcheck(v boolean,n text) returns void language plpgsql as $$begin
  if v is distinct from true then raise exception 'Assertion failed: %',n;end if;
  insert into warehouse_checks values(n);
end$$;
create function pg_temp.werror(q text,code text,n text) returns void language plpgsql as $$begin
  begin execute q; exception when others then
    if sqlstate=code then insert into warehouse_checks values(n);return;end if;raise;
  end;
  raise exception 'Expected error: %',n;
end$$;
create function pg_temp.wpayload(extra jsonb default '{}') returns jsonb language sql as $$
select jsonb_build_object('branch_id',pg_temp.wid('branch'),'code','ACPT-WH','name','Acceptance warehouse','status','active')||extra$$;
create function pg_temp.wcall(extra jsonb default '{}',ver bigint default null,k text default null) returns jsonb language sql as $$
select api.upsert_warehouse(pg_temp.wid('tenant'),pg_temp.wid('entity'),pg_temp.wpayload(extra),ver,case when k is null then gen_random_uuid() else pg_temp.wid(k) end)$$;

insert into auth.users(id,instance_id,aud,role,email,encrypted_password,email_confirmed_at,created_at,updated_at)
select pg_temp.wid(x),'00000000-0000-0000-0000-000000000000','authenticated','authenticated',x||'@warehouse.jentra.test','',now(),now(),now() from unnest(array['owner','viewer','outsider']) x;
insert into core.tenants(id,name,slug,created_by) values(pg_temp.wid('tenant'),'Warehouse Test','warehouse-setup-fixture',pg_temp.wid('owner'));
insert into core.legal_entities(id,tenant_id,name,code,currency_code,created_by)
select pg_temp.wid(x),pg_temp.wid('tenant'),x,upper(x),'LKR',pg_temp.wid('owner') from unnest(array['entity','other']) x;
insert into core.branches(id,tenant_id,legal_entity_id,name,code,created_by)
select pg_temp.wid(x),pg_temp.wid('tenant'),pg_temp.wid(case when x='foreign' then 'other' else 'entity' end),x,upper(x),pg_temp.wid('owner') from unnest(array['branch','branch2','foreign']) x;
insert into core.memberships(id,tenant_id,user_id,status) select pg_temp.wid(x||'.membership'),pg_temp.wid('tenant'),pg_temp.wid(x),'active' from unnest(array['owner','viewer']) x;
insert into core.roles(id,tenant_id,code,name,requires_mfa) values(pg_temp.wid('role'),pg_temp.wid('tenant'),'warehouse_manager','Warehouse manager',true);
insert into core.role_permissions(tenant_id,role_id,permission_code) values(pg_temp.wid('tenant'),pg_temp.wid('role'),'core.setup.manage');
insert into core.role_assignments(tenant_id,membership_id,role_id,legal_entity_id,branch_id,created_by)
values(pg_temp.wid('tenant'),pg_temp.wid('owner.membership'),pg_temp.wid('role'),pg_temp.wid('entity'),null,pg_temp.wid('owner'));

select pg_temp.wcheck(not has_function_privilege('anon','api.upsert_warehouse(uuid,uuid,jsonb,bigint,uuid)','execute'),'anonymous command denied');
select pg_temp.wcheck(not has_function_privilege('authenticated','core.upsert_warehouse_impl(uuid,uuid,jsonb,bigint,uuid)','execute'),'private implementation denied');
select pg_temp.wactor('viewer');
select pg_temp.werror($$select pg_temp.wcall()$$,'42501','viewer cannot create');
select pg_temp.wactor('outsider');
select pg_temp.werror($$select pg_temp.wcall()$$,'42501','outsider cannot create');
select pg_temp.wactor('owner','aal1');
select pg_temp.werror($$select pg_temp.wcall()$$,'42501','MFA required');
select pg_temp.wactor('owner');
select pg_temp.werror($$select pg_temp.wcall('{"branch_id":null}')$$,'22023','branch required');
select pg_temp.werror($$select pg_temp.wcall(jsonb_build_object('branch_id',pg_temp.wid('foreign')))$$,'22023','foreign entity branch rejected');
select pg_temp.werror($$select pg_temp.wcall('{"code":"!"}')$$,'22023','invalid code rejected');
select pg_temp.werror($$select pg_temp.wcall('{"name":"A"}')$$,'22023','short name rejected');
select pg_temp.werror($$select pg_temp.wcall('{"status":"deleted"}')$$,'22023','invalid status rejected');
select pg_temp.werror($$select pg_temp.wcall('{}',1)$$,'22023','create does not accept expected version');
update core.branches set status='inactive' where id=pg_temp.wid('branch');
select pg_temp.werror($$select pg_temp.wcall()$$,'22023','inactive branch rejected');
update core.branches set status='active' where id=pg_temp.wid('branch');
create temporary table warehouse_response as select pg_temp.wcall('{}',null,'create') as body;
select pg_temp.wcheck((select body#>>'{entity,version}'='1' from warehouse_response),'create returns version one');
select pg_temp.wcheck((select body=pg_temp.wcall('{}',null,'create') from warehouse_response),'matching retry returns original receipt');
select pg_temp.wcheck((select count(*)=1 from core.warehouses where tenant_id=pg_temp.wid('tenant')),'retry creates no duplicate warehouse');
select pg_temp.wcheck((select count(*)=1 from audit.events where tenant_id=pg_temp.wid('tenant') and event_type='upsert_warehouse'),'one audited create');
select pg_temp.wcheck((select count(*)=1 from core.outbox_events where tenant_id=pg_temp.wid('tenant') and topic='upsert_warehouse'),'one outbox event');
select pg_temp.werror($$select pg_temp.wcall('{"name":"Changed"}',null,'create')$$,'22023','mismatched replay denied');
select pg_temp.werror($$select pg_temp.wcall()$$,'23505','duplicate code denied');
select pg_temp.werror($$select pg_temp.wcall(jsonb_build_object('id',(select body#>>'{entity,id}' from warehouse_response)),99)$$,'40001','stale update denied');
select pg_temp.werror($$select pg_temp.wcall(jsonb_build_object('id',(select body#>>'{entity,id}' from warehouse_response),'branch_id',pg_temp.wid('branch2')),1)$$,'P0002','warehouse cannot be reparented');
select pg_temp.wcheck((select pg_temp.wcall(jsonb_build_object('id',body#>>'{entity,id}','name','Updated warehouse'),1,'update')#>>'{entity,version}'='2' from warehouse_response),'update increments version');
select pg_temp.wcheck((select count(*)=2 from core.command_receipts where tenant_id=pg_temp.wid('tenant') and command_name='upsert_warehouse'),'only accepted commands have receipts');
select pg_temp.wactor('viewer');
select pg_temp.werror($$select pg_temp.wcall(jsonb_build_object('id',(select body#>>'{entity,id}' from warehouse_response)),2)$$,'42501','viewer cannot update');
select jsonb_build_object('passed',count(*),'checks',jsonb_agg(name),'fixtures','rollback_only') as result from warehouse_checks;
rollback;
