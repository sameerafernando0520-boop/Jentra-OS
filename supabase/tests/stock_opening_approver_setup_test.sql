begin;
create temporary table access_checks(name text);
create function pg_temp.aid(v text) returns uuid language sql immutable as $$select md5('opening-access-test:'||v)::uuid$$;
create function pg_temp.actor(v text,aal text default 'aal2') returns void language plpgsql as $$begin
  perform set_config('request.jwt.claims',jsonb_build_object('sub',pg_temp.aid(v),'email',v||'@opening-access.jentra.test','role','authenticated','aal',aal)::text,true);
  perform set_config('request.jwt.claim.sub',pg_temp.aid(v)::text,true);
end$$;
create function pg_temp.check(v boolean,n text) returns void language plpgsql as $$begin
  if v is distinct from true then raise exception 'Assertion failed: %',n; end if;
  insert into access_checks values(n);
end$$;
create function pg_temp.err(q text,c text,n text) returns void language plpgsql as $$begin
  begin execute q; exception when others then
    if sqlstate=c then insert into access_checks values(n);return;end if;raise;
  end; raise exception 'Expected error: %',n;
end$$;
create function pg_temp.inv(email text default 'approver@opening-access.jentra.test',b text default 'branch',k text default 'invite') returns jsonb language sql as $$
  select api.invite_stock_opening_approver(pg_temp.aid('tenant'),pg_temp.aid('entity'),pg_temp.aid(b),email,pg_temp.aid(k))$$;
insert into auth.users(id,instance_id,aud,role,email,encrypted_password,email_confirmed_at,created_at,updated_at)
select pg_temp.aid(x),'00000000-0000-0000-0000-000000000000','authenticated','authenticated',x||'@opening-access.jentra.test','',now(),now(),now()
from unnest(array['owner','approver','outsider','second']) x;
insert into core.tenants(id,name,slug,created_by) values(pg_temp.aid('tenant'),'Opening Access Test','opening-access-fixture',pg_temp.aid('owner'));
insert into core.legal_entities(id,tenant_id,name,code,currency_code,created_by)
select pg_temp.aid(x),pg_temp.aid('tenant'),x,upper(x),'LKR',pg_temp.aid('owner') from unnest(array['entity','other']) x;
insert into core.branches(id,tenant_id,legal_entity_id,name,code,created_by)
select pg_temp.aid(x),pg_temp.aid('tenant'),pg_temp.aid(case when x='foreign' then 'other' else 'entity' end),x,upper(x),pg_temp.aid('owner') from unnest(array['branch','branch2','foreign']) x;
insert into core.memberships(id,tenant_id,user_id,status) values(pg_temp.aid('membership'),pg_temp.aid('tenant'),pg_temp.aid('owner'),'active');
insert into core.roles(id,tenant_id,code,name,requires_mfa) values(pg_temp.aid('ownerrole'),pg_temp.aid('tenant'),'access_manager','Access manager',false);
insert into core.role_permissions(tenant_id,role_id,permission_code) select pg_temp.aid('tenant'),pg_temp.aid('ownerrole'),x from unnest(array['core.members.invite','core.roles.manage']) x;
insert into core.role_assignments(tenant_id,membership_id,role_id,created_by) values(pg_temp.aid('tenant'),pg_temp.aid('membership'),pg_temp.aid('ownerrole'),pg_temp.aid('owner'));
select pg_temp.check(not has_function_privilege('anon','api.invite_stock_opening_approver(uuid,uuid,uuid,text,uuid)','execute'),'anon invite denied');
select pg_temp.check(not has_function_privilege('authenticated','core.invite_stock_opening_approver_impl(uuid,uuid,uuid,text,uuid)','execute'),'private invite denied');
select pg_temp.check(not has_function_privilege('authenticated','core.accept_stock_opening_invitation_impl(uuid,uuid)','execute'),'private accept denied');
select pg_temp.actor('outsider');
select pg_temp.err($$select pg_temp.inv()$$,'42501','outsider cannot invite');
select pg_temp.actor('owner','aal1');
select pg_temp.err($$select pg_temp.inv()$$,'42501','explicit MFA even when manager role lacks MFA flag');
select pg_temp.actor('owner');
select pg_temp.err($$select pg_temp.inv('owner@opening-access.jentra.test')$$,'22023','self invitation denied');
select pg_temp.err($$select pg_temp.inv('bad')$$,'22023','invalid email denied');
select pg_temp.err($$select pg_temp.inv('approver@opening-access.jentra.test','foreign')$$,'22023','cross entity branch denied');
update core.branches set status='inactive' where id=pg_temp.aid('branch');
select pg_temp.err($$select pg_temp.inv()$$,'22023','inactive scope denied');
update core.branches set status='active' where id=pg_temp.aid('branch');
create temporary table invitation_result as select pg_temp.inv() body;
select pg_temp.check((select body=pg_temp.inv() from invitation_result),'identical invite replay');
select pg_temp.check((select count(*)=1 from core.invitations where tenant_id=pg_temp.aid('tenant')),'one invitation after replay');
select pg_temp.check((select body::text not like '%token%' from invitation_result),'receipt contains no bearer token');
select pg_temp.check((select core.stock_opening_approver_role_valid(pg_temp.aid('tenant'),(body#>>'{entity,role_id}')::uuid) from invitation_result),'minimal MFA role created');
select pg_temp.err($$select pg_temp.inv('second@opening-access.jentra.test')$$,'22023','mismatched retry denied');
select pg_temp.err($$select pg_temp.inv('approver@opening-access.jentra.test','branch','duplicate')$$,'23505','duplicate pending invite denied');
select pg_temp.actor('outsider');
select pg_temp.check((select count(*)=0 from api.list_my_stock_opening_invitations()),'inbox email isolation');
select pg_temp.err($$select api.accept_stock_opening_invitation((select (body#>>'{entity,id}')::uuid from invitation_result),pg_temp.aid('accept'))$$,'42501','wrong recipient denied');
select pg_temp.actor('approver','aal1');
select pg_temp.check((select count(*)=1 from api.list_my_stock_opening_invitations()),'recipient sees invitation before membership');
update auth.users set email_confirmed_at=null where id=pg_temp.aid('approver');
select pg_temp.check((select count(*)=0 from api.list_my_stock_opening_invitations()),'unconfirmed email inbox denied');
select pg_temp.err($$select api.accept_stock_opening_invitation((select (body#>>'{entity,id}')::uuid from invitation_result),pg_temp.aid('accept'))$$,'42501','unconfirmed email cannot accept');
update auth.users set email_confirmed_at=now() where id=pg_temp.aid('approver');
update core.invitations set expires_at=now()-interval '1 second' where tenant_id=pg_temp.aid('tenant');
select pg_temp.err($$select api.accept_stock_opening_invitation((select (body#>>'{entity,id}')::uuid from invitation_result),pg_temp.aid('accept'))$$,'22023','expired invitation denied');
update core.invitations set expires_at=now()+interval '1 day' where tenant_id=pg_temp.aid('tenant');
insert into core.role_permissions(tenant_id,role_id,permission_code) select pg_temp.aid('tenant'),(body#>>'{entity,role_id}')::uuid,'inventory.adjustments.post' from invitation_result;
select pg_temp.err($$select api.accept_stock_opening_invitation((select (body#>>'{entity,id}')::uuid from invitation_result),pg_temp.aid('accept'))$$,'42501','broadened role rejected on accept');
delete from core.role_permissions where tenant_id=pg_temp.aid('tenant') and permission_code='inventory.adjustments.post';
create temporary table acceptance_result as select api.accept_stock_opening_invitation((select (body#>>'{entity,id}')::uuid from invitation_result),pg_temp.aid('accept')) body;
select pg_temp.check((select body=api.accept_stock_opening_invitation((select (body#>>'{entity,id}')::uuid from invitation_result),pg_temp.aid('accept')) from acceptance_result),'identical accept replay');
select pg_temp.check((select count(*)=1 from core.memberships where tenant_id=pg_temp.aid('tenant') and user_id=pg_temp.aid('approver')),'one membership');
select pg_temp.check(not core.has_permission(pg_temp.aid('tenant'),'workflow.approvals.decide',pg_temp.aid('entity'),pg_temp.aid('branch')),'AAL1 cannot approve');
select pg_temp.actor('approver');
select pg_temp.check(core.has_permission(pg_temp.aid('tenant'),'workflow.approvals.decide',pg_temp.aid('entity'),pg_temp.aid('branch')),'AAL2 scoped approval granted');
select pg_temp.check(core.has_permission(pg_temp.aid('tenant'),'inventory.cost.view',pg_temp.aid('entity'),pg_temp.aid('branch')),'scoped cost visibility granted');
select pg_temp.check(not core.has_permission(pg_temp.aid('tenant'),'workflow.approvals.decide',pg_temp.aid('entity'),pg_temp.aid('branch2')),'other branch approval denied');
select pg_temp.check(not core.has_permission(pg_temp.aid('tenant'),'inventory.adjustments.post',pg_temp.aid('entity'),pg_temp.aid('branch')),'posting denied');
select pg_temp.check(not core.has_permission(pg_temp.aid('tenant'),'core.roles.manage'),'role management denied');
select pg_temp.check((select count(*)=0 from api.list_my_stock_opening_invitations()),'accepted invitation removed from inbox');
select pg_temp.check((select count(*)=2 from core.command_receipts where tenant_id=pg_temp.aid('tenant')),'exactly two command receipts');
select pg_temp.check((select count(*)=2 from audit.events where tenant_id=pg_temp.aid('tenant') and event_type in ('invite_stock_opening_approver','accept_stock_opening_invitation')),'both commands audited');
select pg_temp.check((select count(*)=2 from core.outbox_events where tenant_id=pg_temp.aid('tenant') and topic in ('invite_stock_opening_approver','accept_stock_opening_invitation')),'both commands emit outbox');
select pg_temp.actor('owner');
select pg_temp.err($$select pg_temp.inv('approver@opening-access.jentra.test','branch','again')$$,'22023','existing member is not reinvited');
update core.memberships set status='suspended' where tenant_id=pg_temp.aid('tenant') and user_id=pg_temp.aid('approver');
select pg_temp.err($$select pg_temp.inv('approver@opening-access.jentra.test','branch','suspended')$$,'22023','suspended member is not reactivated');
update core.memberships set status='active' where tenant_id=pg_temp.aid('tenant') and user_id=pg_temp.aid('approver');
delete from core.role_permissions where role_id=pg_temp.aid('ownerrole') and permission_code='core.roles.manage';
select pg_temp.err($$select pg_temp.inv('second@opening-access.jentra.test','branch','withoutrole')$$,'42501','invitation permission alone cannot create role');
insert into core.role_permissions(tenant_id,role_id,permission_code) values(pg_temp.aid('tenant'),pg_temp.aid('ownerrole'),'core.roles.manage');
grant select,insert on access_checks to authenticated;
set local role authenticated;
select pg_temp.actor('approver');
select pg_temp.check(core.has_permission(pg_temp.aid('tenant'),'workflow.approvals.decide',pg_temp.aid('entity'),pg_temp.aid('branch')),'authenticated database role has scoped decision permission');
select pg_temp.check((select count(*)=0 from api.list_my_stock_opening_invitations()),'authenticated inbox executes with explicit grant');
select pg_temp.err($$select api.invite_stock_opening_approver(pg_temp.aid('tenant'),pg_temp.aid('entity'),pg_temp.aid('branch'),'second@opening-access.jentra.test',pg_temp.aid('authdenied'))$$,'42501','authenticated approver cannot issue access');
reset role;
set constraints all immediate;
-- pg_prove needs TAP: each check above raises on failure, so every recorded name passed.
reset role;
create extension if not exists pgtap with schema extensions;
set local search_path=extensions,public,pg_catalog;
select no_plan();
select pass(name) from access_checks;
select * from finish();
select jsonb_build_object('passed',count(*),'checks',jsonb_agg(name),'fixtures','rollback_only') result from access_checks;
rollback;
