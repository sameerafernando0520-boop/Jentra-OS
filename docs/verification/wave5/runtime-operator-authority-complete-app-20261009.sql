-- PREPARED ONLY; after approval, immediately before the real operator MFA phase.
begin;
insert into intelligence_control.runtime_operator_authorities(operator_id,tenant_id,reason,expires_at)
 select id,'babe6c86-a764-4d3a-80a3-952a7c096c2c'::uuid,'Owner-reviewed Wave 5 synthetic runtime health acceptance; isolated runtime tenant only',statement_timestamp()+interval '45 minutes'
 from auth.users where lower(email)='w5-operator@jentra.invalid' and deleted_at is null
 and id=(current_setting('jentra.w5.created_auth_ids',true)::jsonb->>'operator')::uuid;
do $$begin if not exists(select 1 from intelligence_control.runtime_operator_authorities a join auth.users u on u.id=a.operator_id
 where lower(u.email)='w5-operator@jentra.invalid' and a.tenant_id='babe6c86-a764-4d3a-80a3-952a7c096c2c'::uuid) then raise exception 'EXACT_OPERATOR_REQUIRED';end if;end$$;
commit;
-- Real installed issue_operator_tenant_grant: selected tenant only, reason above,
-- recipient is this separate operator, deadline +30 minutes within authority.
-- Capture actual receipt/grant ID; do not insert or invent an authenticated grant.
