import {writeFile} from 'node:fs/promises';
const completeApp=process.argv.includes('--complete-app');
const {accounts,assignments,id,plans,roles,scopes,workerConfig}=await import(completeApp?'./complete_app_runtime_plan.mjs':'./runtime_plan.mjs');
const outputSuffix=completeApp?'complete-app-20261009':'20261008';
const quoted=s=>`'${s.replaceAll("'","''")}'`;
const uuid=s=>`${quoted(s)}::uuid`;
const main=scopes[0],sql=[`-- PREPARED ONLY. No synthetic account or business bootstrap is authorized yet.
-- Execute only after the final bound review SHA and explicit owner approval.
-- Auth users must be created through Auth Admin first, with random private
-- passwords, email_confirm=true and no email delivery. Never INSERT auth.users.
-- Resolve only the six reviewed labels; any collision/preexisting user aborts
-- in the Auth provisioning preflight and requires a refreshed owner review.
begin;
${completeApp?`-- Inject only the six real IDs returned by the reviewed Auth Admin creates.
-- This non-secret label-to-ID binding is required again on each SQL connection.
create temporary table w5_runtime_created_auth(label text primary key,user_id uuid not null unique);
insert into w5_runtime_created_auth select key,value::uuid from jsonb_each_text(current_setting('jentra.w5.created_auth_ids',true)::jsonb);
do $$begin if (select count(*) from w5_runtime_created_auth)<>6
 or exists(select 1 from w5_runtime_created_auth where label not in('proposer','approver','executor','billing-admin','operator','foreign-member')) then
 raise exception 'EXACT_RETURNED_AUTH_IDS_REQUIRED';end if;end$$;`:''}
create temporary table w5_runtime_accounts(label text primary key,user_id uuid not null unique,email text not null unique);
insert into w5_runtime_accounts
 select labels.label,u.id,u.email from(values
 ${accounts.map(a=>`(${quoted(a.label)},${quoted(a.email)})`).join(',\n ')}) labels(label,email)
 join auth.users u on lower(u.email)=labels.email and u.deleted_at is null
 ${completeApp?'join w5_runtime_created_auth created on created.label=labels.label and created.user_id=u.id':''};
do $$begin if (select count(*) from w5_runtime_accounts)<>6 then raise exception 'EXACT_SIX_AUTH_ACCOUNTS_REQUIRED';end if;end$$;
create temporary table w5_runtime_scopes(key text primary key,tenant_id uuid not null,entity_id uuid not null,branch_id uuid not null,second_branch_id uuid,slug text not null,plan_code text not null);
insert into w5_runtime_scopes values
 ${scopes.map(s=>`(${quoted(s.key)},${uuid(s.tenantId)},${uuid(s.entityId)},${uuid(s.branchId)},${s.secondBranchId?uuid(s.secondBranchId):'null'},${quoted(s.slug)},${quoted(s.planCode)})`).join(',\n ')};
do $$begin
 if exists(select 1 from core.tenants t join w5_runtime_scopes s on t.id=s.tenant_id or t.slug=s.slug) then raise exception 'RUNTIME_TENANT_COLLISION';end if;
 if exists(select 1 from billing.plans where code in(${plans.map(p=>quoted(p.code)).join(',')})) then raise exception 'RUNTIME_PLAN_COLLISION';end if;
 if exists(select 1 from intelligence_control.operators o join w5_runtime_accounts a on a.user_id=o.actor_id) then raise exception 'RUNTIME_OPERATOR_COLLISION';end if;
end$$;`];
sql.push(`insert into billing.plans(code,name,trial_days) values ${plans.map(p=>`(${quoted(p.code)},${quoted(p.name)},${p.trialDays})`).join(',')};`);
for(const p of plans){sql.push(`insert into billing.plan_entitlements(plan_code,entitlement_code,enabled,numeric_limit) values
 ${Object.entries(p.entitlements).map(([code,value])=>`(${quoted(p.code)},${quoted(code)},true,${typeof value==='string'?quoted(value)+'::numeric':'null'})`).join(',\n ')};`);}
sql.push(`insert into core.tenants(id,name,slug,status,timezone,default_currency_code,created_by)
 select tenant_id,'Synthetic Wave 5 '||key,slug,'trial','Asia/Colombo','LKR',(select user_id from w5_runtime_accounts where label='billing-admin') from w5_runtime_scopes;
insert into core.legal_entities(id,tenant_id,name,code,currency_code,timezone,rounding_scale,created_by)
 select entity_id,tenant_id,'Synthetic '||key,case key when 'runtime' then 'W5RT' when 'foreign' then 'W5FX' else 'W5LOAD' end,'LKR','Asia/Colombo',6,
 (select user_id from w5_runtime_accounts where label='billing-admin') from w5_runtime_scopes;
insert into core.branches(id,tenant_id,legal_entity_id,name,code,created_by)
 select branch_id,tenant_id,entity_id,'Synthetic RT1','RT1',(select user_id from w5_runtime_accounts where label='billing-admin') from w5_runtime_scopes
 union all select second_branch_id,tenant_id,entity_id,'Synthetic RT2 denial branch','RT2',(select user_id from w5_runtime_accounts where label='billing-admin') from w5_runtime_scopes where second_branch_id is not null;
insert into billing.tenant_subscriptions(id,tenant_id,plan_code,status,seats,trial_started_at,trial_ends_at,current_period_ends_at)
 select md5(tenant_id::text||':subscription')::uuid,tenant_id,plan_code,'trialing',case key when 'runtime' then 5 when 'foreign' then 1 else 4 end,
 statement_timestamp(),statement_timestamp()+interval '7 days',null from w5_runtime_scopes;
insert into core.memberships(id,tenant_id,user_id,status,joined_at)
 select md5(s.tenant_id::text||':'||a.label||':member')::uuid,s.tenant_id,a.user_id,'active',statement_timestamp()
 from w5_runtime_scopes s cross join w5_runtime_accounts a
 where (s.key='foreign' and a.label='foreign-member') or (s.key<>'foreign' and a.label in('proposer','approver','executor','billing-admin'));
create temporary table w5_runtime_roles(tenant_id uuid,role_key text,role_id uuid,permissions jsonb,requires_mfa boolean,primary key(tenant_id,role_key));`);
if(completeApp){sql.push(`insert into w5_runtime_roles
 select s.tenant_id,r.key,format('%s-%s-4%s-8%s-%s',substr(h.value,1,8),substr(h.value,9,4),substr(h.value,14,3),substr(h.value,18,3),substr(h.value,21,12))::uuid,
 r.value->'permissions',(r.value->>'requiresMfa')::boolean
 from w5_runtime_scopes s cross join jsonb_each(${quoted(JSON.stringify(roles))}::jsonb) r
 cross join lateral(select encode(extensions.digest('jentra-w5-runtime-review-20261008:'||s.key||'.role.'||r.key,'sha256'),'hex') value) h
 where r.key=any(case s.key when 'runtime' then array['reader','financeAnchor','proposer','approver','executor','billing']
 when 'foreign' then array['foreignReader'] else array['loadReader',case s.key when 'load-001' then 'billing' else 'loadBilling' end] end);`);
}else for(const s of scopes){const keys=s.key==='runtime'?['reader','financeAnchor','proposer','approver','executor','billing']:s.key==='foreign'?['foreignReader']:['loadReader',s.key==='load-001'?'billing':'loadBilling'];
 for(const key of keys){const r=roles[key];sql.push(`insert into w5_runtime_roles values(${uuid(s.tenantId)},${quoted(key)},${uuid(id(s.key+'.role.'+key))},${quoted(JSON.stringify(r.permissions))}::jsonb,${r.requiresMfa});`);}}
sql.push(`do $$begin if exists(select 1 from w5_runtime_roles r cross join lateral jsonb_array_elements_text(r.permissions) p where not exists(select 1 from core.permissions c where c.code=p.value)) then
 raise exception 'REVIEWED_PERMISSION_MISSING';end if;end$$;
insert into core.roles(id,tenant_id,code,name,requires_mfa)
 select role_id,tenant_id,'w5_'||lower(role_key),'Synthetic Wave 5 '||role_key,requires_mfa from w5_runtime_roles;
insert into core.role_permissions(tenant_id,role_id,permission_code)
 select tenant_id,role_id,p.value from w5_runtime_roles cross join lateral jsonb_array_elements_text(permissions) p;
create temporary table w5_runtime_assignment_keys(tenant_id uuid,label text,role_key text);
insert into w5_runtime_assignment_keys values
 ${Object.entries(assignments).filter(([label])=>label!=='foreign-member').flatMap(([label,keys])=>keys.map(key=>`(${uuid(main.tenantId)},${quoted(label)},${quoted(key)})`)).join(',\n ')};
insert into w5_runtime_assignment_keys select tenant_id,'foreign-member','foreignReader' from w5_runtime_scopes where key='foreign';
insert into w5_runtime_assignment_keys select s.tenant_id,a.label,case when a.label='billing-admin' then case when s.key='load-001' then 'billing' else 'loadBilling' end else 'loadReader' end
 from w5_runtime_scopes s cross join w5_runtime_accounts a where s.key like 'load-%' and a.label in('proposer','approver','executor','billing-admin');
insert into core.role_assignments(id,tenant_id,membership_id,role_id,legal_entity_id,branch_id,created_by)
 select md5(s.tenant_id::text||':'||k.label||':'||k.role_key)::uuid,s.tenant_id,md5(s.tenant_id::text||':'||k.label||':member')::uuid,r.role_id,
 case when k.role_key in('billing','loadBilling') then null else s.entity_id end,
 case when k.role_key in('billing','loadBilling','financeAnchor') then null else s.branch_id end,
 (select user_id from w5_runtime_accounts where label='billing-admin')
 from w5_runtime_assignment_keys k join w5_runtime_scopes s on s.tenant_id=k.tenant_id join w5_runtime_roles r on r.tenant_id=k.tenant_id and r.role_key=k.role_key;
insert into intelligence_control.synthetic_tenants(tenant_id,allowed)
 select tenant_id,true from w5_runtime_scopes where key in('runtime','load-001');
insert into intelligence_control.runtime_worker_scopes(runtime_id,tenant_id,legal_entity_id,branch_id,enabled,expires_at)
 values(${uuid(workerConfig.runtimeId)},${uuid(main.tenantId)},${uuid(main.entityId)},${uuid(main.branchId)},true,statement_timestamp()+interval '24 hours');
-- Operator registration is separate from tenant membership. Fixed authority is
-- inserted immediately before the operator phase, using the separate script.
insert into intelligence_control.operators(actor_id,active,health_read,grant_manage)
 select user_id,true,true,true from w5_runtime_accounts where label='operator';
-- No integration destination, credential, HMAC key or operator grant is created
-- here. Bind exact receiver/host before review approval, register integrations
-- through real MFA, then issue the bounded operator grant through its MFA API.
select jsonb_build_object('tenants',(select count(*) from w5_runtime_scopes),'accounts',(select count(*) from w5_runtime_accounts),
 'memberships',(select count(*) from core.memberships where tenant_id in(select tenant_id from w5_runtime_scopes)),
 'roles',(select count(*) from w5_runtime_roles),'assignments',(select count(*) from w5_runtime_assignment_keys)) reviewed_counts;
commit;
`);
await writeFile(new URL('../../docs/verification/wave5/runtime-bootstrap-'+outputSuffix+'.sql',import.meta.url),sql.join('\n'));
await writeFile(new URL('../../docs/verification/wave5/runtime-operator-authority-'+outputSuffix+'.sql',import.meta.url),`-- PREPARED ONLY; after approval, immediately before the real operator MFA phase.
begin;
insert into intelligence_control.runtime_operator_authorities(operator_id,tenant_id,reason,expires_at)
 select id,${uuid(main.tenantId)},${quoted(workerConfig.operator.reason)},statement_timestamp()+interval '45 minutes'
 from auth.users where lower(email)='w5-operator@jentra.invalid' and deleted_at is null
 ${completeApp?"and id=(current_setting('jentra.w5.created_auth_ids',true)::jsonb->>'operator')::uuid":''};
do $$begin if not exists(select 1 from intelligence_control.runtime_operator_authorities a join auth.users u on u.id=a.operator_id
 where lower(u.email)='w5-operator@jentra.invalid' and a.tenant_id=${uuid(main.tenantId)}) then raise exception 'EXACT_OPERATOR_REQUIRED';end if;end$$;
commit;
-- Real installed issue_operator_tenant_grant: selected tenant only, reason above,
-- recipient is this separate operator, deadline +30 minutes within authority.
-- Capture actual receipt/grant ID; do not insert or invent an authenticated grant.
`);
process.stdout.write(JSON.stringify({preparedOnly:true,accounts:6,tenants:500,memberships:1997,branches:501}));
