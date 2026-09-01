-- Advisor-driven hardening for the greenfield foundation.

-- Global reference data is authenticated-readable but never client-writable.
alter table core.permissions enable row level security;
alter table billing.plans enable row level security;
alter table billing.plan_entitlements enable row level security;

create policy permissions_authenticated_read on core.permissions
  for select to authenticated using (true);
create policy plans_authenticated_read on billing.plans
  for select to authenticated using (true);
create policy plan_entitlements_authenticated_read on billing.plan_entitlements
  for select to authenticated using (true);

-- Make the intentional client denial visible to both humans and the advisor.
create policy outbox_client_deny on core.outbox_events
  as restrictive for all to authenticated
  using (false) with check (false);

-- Cache the permission helper once per statement in the invitation policy.
drop policy invitations_invitee_or_manager_read on core.invitations;
create policy invitations_invitee_or_manager_read on core.invitations
  for select to authenticated
  using (
    lower(email) = lower(coalesce((select auth.jwt()->>'email'), ''))
    or (select core.has_permission(tenant_id, 'core.members.invite'))
  );

-- Cover every foreign-key lookup path surfaced by the performance advisor.
create index tenants_created_by_idx on core.tenants (created_by);
create index legal_entities_created_by_idx on core.legal_entities (created_by);
create index branches_created_by_idx on core.branches (created_by);
create index warehouses_created_by_idx on core.warehouses (created_by);
create index warehouses_tenant_entity_idx
  on core.warehouses (tenant_id, legal_entity_id);
create index memberships_invited_by_idx on core.memberships (invited_by);

create index role_permissions_permission_idx
  on core.role_permissions (permission_code);
create index role_permissions_tenant_role_idx
  on core.role_permissions (tenant_id, role_id);

create index role_assignments_created_by_idx
  on core.role_assignments (created_by);
create index role_assignments_tenant_membership_idx
  on core.role_assignments (tenant_id, membership_id);
create index role_assignments_tenant_role_idx
  on core.role_assignments (tenant_id, role_id);
create index role_assignments_tenant_entity_idx
  on core.role_assignments (tenant_id, legal_entity_id);
create index role_assignments_tenant_branch_idx
  on core.role_assignments (tenant_id, branch_id);

create index invitations_invited_by_idx on core.invitations (invited_by);
create index invitations_accepted_by_idx on core.invitations (accepted_by);
create index invitations_tenant_role_idx
  on core.invitations (tenant_id, role_id);
create index invitations_tenant_entity_idx
  on core.invitations (tenant_id, legal_entity_id);
create index invitations_tenant_branch_idx
  on core.invitations (tenant_id, branch_id);

create index outbox_events_tenant_idx on core.outbox_events (tenant_id);
create index tenant_subscriptions_plan_idx
  on billing.tenant_subscriptions (plan_code);

create index approval_requests_submitted_by_idx
  on workflow.approval_requests (submitted_by);
create index approval_requests_assigned_to_idx
  on workflow.approval_requests (assigned_to);
create index approval_requests_decision_by_idx
  on workflow.approval_requests (decision_by);
create index approval_requests_tenant_entity_idx
  on workflow.approval_requests (tenant_id, legal_entity_id);
create index approval_requests_tenant_branch_idx
  on workflow.approval_requests (tenant_id, branch_id);

create index audit_events_actor_idx on audit.events (actor_id);
create index audit_events_tenant_entity_idx
  on audit.events (tenant_id, legal_entity_id);
create index audit_events_tenant_branch_idx
  on audit.events (tenant_id, branch_id);
