-- Cover every foreign-key lookup introduced by the Wave 3 foundation.
-- Actor indexes deliberately lead with actor_id because auth.users is the
-- referenced table; tenant-leading indexes alone do not cover FK maintenance.

create index command_receipts_legal_entity_fk_idx
  on core.command_receipts (tenant_id, legal_entity_id);
create index command_receipts_branch_fk_idx
  on core.command_receipts (tenant_id, branch_id);
create index outbox_events_actor_fk_idx
  on core.outbox_events (actor_id, tenant_id);

create index approval_requests_currency_fk_idx
  on workflow.approval_requests (currency_code);

create index approval_decisions_actor_fk_idx
  on workflow.approval_decisions (actor_id, tenant_id);
create index approval_decisions_currency_fk_idx
  on workflow.approval_decisions (currency_code);
create index approval_decisions_request_workflow_fk_idx
  on workflow.approval_decisions (
    tenant_id, approval_request_id, workflow_definition_id, workflow_revision
  );
create index approval_decisions_workflow_fk_idx
  on workflow.approval_decisions (
    tenant_id, workflow_definition_id, workflow_revision
  );
create index approval_decisions_matrix_step_fk_idx
  on workflow.approval_decisions (
    tenant_id, approval_matrix_step_id, workflow_definition_id, step_order
  );

create index notifications_actor_fk_idx
  on workflow.notifications (actor_id, tenant_id);
create index notifications_legal_entity_fk_idx
  on workflow.notifications (tenant_id, legal_entity_id);
create index notifications_branch_fk_idx
  on workflow.notifications (tenant_id, branch_id);

create index process_events_actor_fk_idx
  on workflow.process_events (actor_id, tenant_id);
create index process_events_owner_fk_idx
  on workflow.process_events (owner_id, tenant_id);
create index process_events_legal_entity_fk_idx
  on workflow.process_events (tenant_id, legal_entity_id);
create index process_events_branch_fk_idx
  on workflow.process_events (tenant_id, branch_id);
create index process_events_workflow_fk_idx
  on workflow.process_events (
    tenant_id, workflow_definition_id, workflow_revision
  );
