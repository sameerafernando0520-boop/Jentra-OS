-- CANDIDATE ONLY. Not installed anywhere. Needs only the tracked People
-- migrations; install after 20261114090000_organization_creation_control.sql.
--
-- 1. Reading payroll needs an MFA session. people.payroll.view returns
--    per-employee gross, deductions, net and calculation inputs, while
--    payslips and payroll corrections already require MFA for the same data.
-- 2. Nobody decides their own leave or attendance record. The existing rules
--    compare the decider with whoever created or submitted the record, not
--    with the employee the record is about.

-- 1. Payroll reads ---------------------------------------------------------

create or replace function people_payroll.require_access(t uuid,e uuid,b uuid,cap text,p_write boolean default false)
returns void language plpgsql security definer set search_path='' as $$begin
 if cap is null or cap not in('people.payroll.view','people.payroll.configure','people.payroll.prepare',
  'people.payroll.approve','people.payroll.post','people.payroll.reverse','people.payroll.payslip.view',
  'people.payroll.export','people.payroll.settle','people.payroll.payslip.self') then
  raise exception using errcode='42501',message='PAYROLL_SCOPE_DENIED';end if;
 perform people.require_access(t,e,b,cap);
 if (p_write or cap='people.payroll.view') and coalesce(auth.jwt()->>'aal','aal1')<>'aal2' then
  raise exception using errcode='42501',message='PAYROLL_MFA_REQUIRED';end if;
end $$;

-- 2. Decisions about your own record ---------------------------------------

-- The decider is the subject when an accepted account link ties the deciding
-- user to the employee on the record. Fires only when a decision is recorded,
-- so drafting, submitting and withdrawing are unaffected.
create function people_private.refuse_self_decision()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  if new.decided_by is not null and new.status is distinct from old.status
    and new.status = any (tg_argv[1:array_length(tg_argv, 1)])
    and exists (
      select 1 from people_private.account_links l
      where l.tenant_id = new.tenant_id and l.legal_entity_id = new.legal_entity_id
        and l.employee_id = new.employee_id and l.user_id = new.decided_by and l.status = 'accepted'
    ) then
    raise exception using errcode = '55000', message = tg_argv[0];
  end if;
  return new;
end;
$$;
revoke all on function people_private.refuse_self_decision() from public, anon, authenticated;

create trigger leave_refuse_self_decision before update of status on people.leave_requests
  for each row execute function people_private.refuse_self_decision('LEAVE_SELF_DECISION_DENIED', 'approved', 'rejected');

create trigger attendance_refuse_self_decision before update of status on people.attendance_entries
  for each row execute function people_private.refuse_self_decision(
    'ATTENDANCE_SELF_DECISION_DENIED', 'approved', 'rejected', 'cancelled');
