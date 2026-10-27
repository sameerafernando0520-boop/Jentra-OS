-- Candidate only. Depends on employee push, self-service, and cases/documents
-- candidates (20261023/20261025). No installation, backfill, or sender activation.
-- Source-owned HR transitions use the existing recipient gate, event receipt,
-- generic people.employee.* inbox message, and recipient-bound push mirror.

-- Immutable attendance events are appended after the canonical entry/revision
-- changes, including sealed payroll corrections with approved -> approved state.
-- Draft edits and submissions are not employee outcomes. Reopening an approved
-- entry for correction is an outcome even before it is approved again.
create function employee_self.notify_attendance_event() returns trigger
language plpgsql security definer set search_path='' as $$
declare a people.attendance_entries%rowtype;begin
 if not ((new.action='approve' and new.after_status='approved')
  or (new.action='reject' and new.after_status='rejected')
  or (new.action='cancel' and new.after_status='cancelled')
  or (new.action='correct' and new.before_status='approved' and new.after_status in ('draft','approved'))) then
  return new;
 end if;
 select * into a from people.attendance_entries e
 where e.tenant_id=new.tenant_id and e.legal_entity_id=new.legal_entity_id
  and e.branch_id=new.branch_id and e.employee_id=new.employee_id and e.id=new.entry_id
  and e.current_revision_id=new.revision_id and e.status=new.after_status;
 if a.id is not null then
  perform employee_self.notify_employee(a.tenant_id,a.legal_entity_id,a.branch_id,a.employee_id,
   'attendance',a.id,a.version);
 end if;
 return new;
end $$;
create trigger employee_attendance_event_notice after insert on people.attendance_events
 for each row execute function employee_self.notify_attendance_event();

-- The correction owner issues its immutable correction payslip before posting
-- the correction. Its ID, rather than the original payslip ID, prevents collisions
-- with normal payroll notices or another correction at the same version.
create function employee_self.notify_payroll_correction() returns trigger
language plpgsql security definer set search_path='' as $$
declare p people_payroll.correction_payslips%rowtype;begin
 if new.status in ('posted','reversed') and old.status is distinct from new.status then
  select * into p from people_payroll.correction_payslips s
  where s.tenant_id=new.tenant_id and s.legal_entity_id=new.legal_entity_id
   and s.branch_id=new.branch_id and s.employee_id=new.employee_id and s.correction_id=new.id;
  if p.id is not null then
   perform employee_self.notify_employee(p.tenant_id,p.legal_entity_id,p.branch_id,p.employee_id,
    'pay',p.id,new.version);
  end if;
 end if;
 return new;
end $$;
create trigger employee_payroll_correction_notice after update on people_payroll.corrections
 for each row execute function employee_self.notify_payroll_correction();

-- Resolution rows are immutable, so their own ID at version 1 identifies the
-- decision independently of the canonical attendance outcome. A resolved leave
-- cancellation already has a canonical leave notice; do not send a second wake.
-- A declined cancellation leaves the ledger unchanged and needs its own notice.
create function employee_self.notify_request_resolution() returns trigger
language plpgsql security definer set search_path='' as $$begin
 if new.kind='attendance' or (new.kind='leave_cancel' and new.decision='declined') then
  perform employee_self.notify_employee(new.tenant_id,new.legal_entity_id,new.branch_id,new.employee_id,
   case when new.kind='attendance' then 'attendance' else 'leave' end,new.id,1);
 end if;
 return new;
end $$;
create trigger employee_request_resolution_notice after insert on employee_self.request_resolutions
 for each row execute function employee_self.notify_request_resolution();

-- Trigger-only authority. No public RPC, capability, role, plan, or direct
-- notification/outbox grant is added. This slice edits no prerequisite candidate.
revoke all on function employee_self.notify_attendance_event(),
 employee_self.notify_payroll_correction(),employee_self.notify_request_resolution()
 from public,anon,authenticated,service_role;
