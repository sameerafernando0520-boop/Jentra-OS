-- Candidate only. Not installed on any hosted database.
-- Monthly EPF, ETF and APIT schedules from posted Sri Lanka statutory payroll
-- runs. Requires 20261120090000_lk_statutory_payroll.sql. Contract:
-- docs/blueprint/70_LK_STATUTORY_PAYROLL_CONTRACT.md (part C).
--
-- A schedule lists the posted, approved revisions of runs that start in the
-- month. Reversed and cancelled runs are left out. It returns employee
-- identifiers, so it needs the payroll export permission across the whole
-- entity and MFA.

create function api.people_payroll_statutory_return(p_tenant_id uuid,p_legal_entity_id uuid,p_branch_id uuid,
 p_month date,p_kind text)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare employer people_payroll.employer_registrations%rowtype;tin text;v_rows jsonb;v_totals jsonb;begin
 perform people_payroll.require_access(p_tenant_id,p_legal_entity_id,p_branch_id,'people.payroll.export',true);
 perform core.require_permission(p_tenant_id,'people.payroll.export',p_legal_entity_id,null);
 if p_month is null or extract(day from p_month)<>1 or p_kind is null or p_kind not in('epf','etf','apit') then
  raise exception using errcode='22023',message='PAYROLL_STATUTORY_RETURN_INVALID';end if;
 select * into employer from people_payroll.employer_registrations where tenant_id=p_tenant_id and legal_entity_id=p_legal_entity_id
  order by version desc limit 1;
 select le.tax_identifier into tin from core.legal_entities le where le.tenant_id=p_tenant_id and le.id=p_legal_entity_id;
 with calcs as (
  select c.employee_id,c.calculation from people_payroll.employee_calculations c join people_payroll.runs r
   on r.tenant_id=c.tenant_id and r.legal_entity_id=c.legal_entity_id and r.id=c.run_id and r.approved_revision_id=c.revision_id
  where c.tenant_id=p_tenant_id and c.legal_entity_id=p_legal_entity_id and r.status='posted'
   and r.start_date>=p_month and r.start_date<(p_month+interval '1 month')::date and c.calculation ? 'statutory'),
 amounts as (
  select employee_id,
   (calculation->'statutory'->>'epf_base')::numeric epf_base,(calculation->'statutory'->>'etf_base')::numeric etf_base,
   (calculation->'statutory'->>'apit_base')::numeric apit_base,
   (select coalesce(sum((l->>'amount')::numeric) filter(where l->>'code'='EPF_EE'),0) from jsonb_array_elements(calculation->'lines') l where l->>'basis'='statutory') epf_employee,
   (select coalesce(sum((l->>'amount')::numeric) filter(where l->>'code'='EPF_ER'),0) from jsonb_array_elements(calculation->'lines') l where l->>'basis'='statutory') epf_employer,
   (select coalesce(sum((l->>'amount')::numeric) filter(where l->>'code'='ETF_ER'),0) from jsonb_array_elements(calculation->'lines') l where l->>'basis'='statutory') etf_employer,
   (select coalesce(sum((l->>'amount')::numeric) filter(where l->>'code'='APIT'),0) from jsonb_array_elements(calculation->'lines') l where l->>'basis'='statutory') apit
  from calcs),
 per as (
  select employee_id,sum(epf_base) epf_base,sum(etf_base) etf_base,sum(apit_base) apit_base,sum(epf_employee) epf_employee,
   sum(epf_employer) epf_employer,sum(etf_employer) etf_employer,sum(apit) apit
  from amounts group by employee_id),
 listed as (
  select p.*,e.code,e.display_name,s.nic,s.epf_member_number from per p
  join people.employees e on e.tenant_id=p_tenant_id and e.legal_entity_id=p_legal_entity_id and e.id=p.employee_id
  left join lateral(select x.nic,x.epf_member_number from people_payroll.employee_statutory x where x.tenant_id=p_tenant_id
   and x.legal_entity_id=p_legal_entity_id and x.employee_id=p.employee_id order by x.version desc limit 1) s on true
  where case p_kind when 'epf' then p.epf_base>0 when 'etf' then p.etf_base>0 else p.apit_base>0 end)
 select coalesce(jsonb_agg(jsonb_build_object('employee_id',employee_id,'employee_code',code,'name',display_name,
   'nic',nic,'epf_member_number',epf_member_number,'epf_base',round(epf_base,6)::text,'etf_base',round(etf_base,6)::text,
   'apit_base',round(apit_base,6)::text,'epf_employee',round(epf_employee,6)::text,'epf_employer',round(epf_employer,6)::text,
   'etf_employer',round(etf_employer,6)::text,'apit',round(apit,6)::text) order by code),'[]'::jsonb),
  jsonb_build_object('employees',count(*),'epf_base',round(coalesce(sum(epf_base),0),6)::text,
   'etf_base',round(coalesce(sum(etf_base),0),6)::text,'apit_base',round(coalesce(sum(apit_base),0),6)::text,
   'epf_employee',round(coalesce(sum(epf_employee),0),6)::text,'epf_employer',round(coalesce(sum(epf_employer),0),6)::text,
   'etf_employer',round(coalesce(sum(etf_employer),0),6)::text,'apit',round(coalesce(sum(apit),0),6)::text)
 into v_rows,v_totals from listed;
 return jsonb_build_object('kind',p_kind,'month',p_month,'employer_epf_number',employer.epf_employer_number,
  'employer_etf_number',employer.etf_employer_number,'employer_tin',tin,'rows',v_rows,'totals',v_totals);
end $$;
revoke all on function api.people_payroll_statutory_return(uuid,uuid,uuid,date,text) from public,anon;
grant execute on function api.people_payroll_statutory_return(uuid,uuid,uuid,date,text) to authenticated;

notify pgrst,'reload schema';
