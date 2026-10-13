// Declarative source mapping only. No client, secret access, SQL executor,
// fixture mutation, private provider, session factory, or live evidence.
const freeze = value => {
  if (value && typeof value === 'object' && !Object.isFrozen(value)) {
    Object.values(value).forEach(freeze);
    Object.freeze(value);
  }
  return value;
};

export const RUNTIME_FIXTURE_BINDING = freeze({
  projectId: 'xpdoufauvrbdmxgngetv',
  projectUrl: 'https://xpdoufauvrbdmxgngetv.supabase.co',
  reviewPath: 'docs/verification/wave5/complete-app-runtime-review-20261010-r5.json',
  reviewFileSha256: 'b1b0cb94a8aa705b5cc6ff674ed215a8487a960ff0a594f7abffadfbc4e57cc3',
  runtimeBundleSha256: 'db525758554036fa99ec02d00c85bd8401ef7ebce787e2a983db1c69a08baf7b',
  operationScopeSha256: 'fcdab89d242dc578793eba1d520ea0251699b70b7730c02aea94232805286e63',
  status: 'source-mapped; private implementation and actual observations absent',
  authorizesOperations: false, setsRuntimeGates: false,
  production: false, realBilling: false, installOriginalSix: false,
});

export const FIXTURE_CAPS = freeze({
  perTenant: { opportunities: 200, processEvents: 800, postedJournals: 100,
    journalLines: 200, openItems: 120 },
  runtimeOnly: { payrollObligations: 10, payrollCorrections: 4,
    projectReimbursements: 10, financialPublications: 3,
    classificationReviews: 1, cashScenarios: 4, governedExports: 8 },
  invitations: { scopeKey: 'load-001', actorLabels: ['approver', 'executor'], emailDelivery: false },
  syntheticActivationScopes: ['runtime', 'load-001'],
  runtimeId: '778237e3-3d4e-4871-8cc9-e08b07b989c7',
  totalScopes: 500, totalGenuineSessions: 2000,
});

export const SQL_CONTRACTS = freeze({
  indexedForecastRead: {
    signature: 'api.get_pipeline_forecast(uuid,uuid,uuid,uuid)', grant: 'authenticated',
    parameters: ['p_tenant_id', 'p_legal_entity_id', 'p_branch_id', 'p_forecast_id'],
    source: 'supabase/migrations/20261006143000_wave5_pipeline_forecasts.sql', lines: [102, 118, 120, 121],
    capability: ['analytics.view', 'crm.opportunities.view OR crm.opportunities.manage', 'active analytics entitlement'],
  },
  indexedBillingRead: {
    signature: 'api.get_wave5_subscription(uuid)', grant: 'authenticated',
    parameters: ['p_tenant_id'],
    source: 'supabase/migrations/20261006170000_wave5_synthetic_subscriptions.sql', lines: [111, 119],
    capability: ['billing.read', 'genuine AAL2 for runtime AND load-001 billing roles'],
  },
  forecast: {
    signature: 'api.freeze_pipeline_forecast(uuid,uuid,uuid,uuid,uuid,timestamptz,date,date)', grant: 'authenticated',
    parameters: ['p_tenant_id', 'p_legal_entity_id', 'p_branch_id', 'p_command_id',
      'p_idempotency_key', 'p_client_timestamp', 'p_horizon_start', 'p_horizon_end'],
    source: 'supabase/migrations/20261006143000_wave5_pipeline_forecasts.sql', lines: [47, 100, 118, 120, 121],
    capability: ['analytics.view', 'crm.opportunities.view OR crm.opportunities.manage', 'active analytics entitlement'],
    identity: 'Same original actor/command/key/timestamp/horizon for duplicates; all load commands fresh.',
  },
  analytics: {
    signature: 'api.analytics_process_snapshot(uuid,uuid,uuid,timestamptz,timestamptz,timestamptz,timestamptz)', grant: 'authenticated',
    parameters: ['p_tenant_id', 'p_legal_entity_id', 'p_branch_id', 'p_window_start',
      'p_window_end', 'p_as_of', 'p_recorded_through'],
    source: 'supabase/migrations/20261006140000_wave5_process_metrics.sql', lines: [31, 89],
    capability: ['analytics.view', 'workflow.process.view', 'crm.opportunities.view OR crm.opportunities.manage', 'active analytics entitlement'],
    identity: 'Read only; no caller command or idempotency input.',
  },
  acceptInvitation: {
    signature: 'api.accept_invitation(text)', grant: 'authenticated', parameters: ['p_token'],
    source: 'supabase/migrations/20260831193714_create_greenfield_foundation.sql', lines: [856, 1068, 1120],
    capability: ['genuine authenticated subject/email matching exact reviewed invitation'],
    identity: 'Private token only. Public attemptId is correlation, never an invented server commandId.',
  },
  reserveOne: {
    signature: 'api.wave5_reserve_usage(uuid,uuid,text,timestamptz,timestamptz,text)', grant: 'service_role',
    parameters: ['p_tenant_id', 'p_invocation_id', 'p_metric_code', 'p_period_start', 'p_period_end', 'p_quantity'],
    source: 'supabase/migrations/20261006150000_wave5_trusted_metering.sql', lines: [60, 98, 152, 154, 156],
    capability: ['actual service-role transport', 'exact active subscription period', 'actual hard cap'],
    identity: 'Returned invocationId is the original invocation UUID, not a fabricated command parameter.',
  },
  activate: {
    signature: 'api.apply_synthetic_subscription(uuid,uuid)', grant: 'service_role',
    parameters: ['p_tenant_id', 'p_revision_id'],
    source: 'supabase/migrations/20261006170000_wave5_synthetic_subscriptions.sql', lines: [57, 91, 103, 105],
    capability: ['actual service-role transport', 'runtime or load-001 synthetic allowlist',
      'current billing actor authority and real verified MFA', 'effective revision and expected subscription version',
      'no quota period ending after revision start'],
    identity: 'Read original revision.execution_id from the actual scheduled revision; RPC accepts no caller command/key.',
  },
  executeProposal: {
    signature: 'api.wave5_proposal_command(uuid,uuid,uuid,uuid,uuid,timestamptz,text,jsonb)', grant: 'authenticated',
    parameters: ['p_tenant_id', 'p_legal_entity_id', 'p_branch_id', 'p_command_id',
      'p_idempotency_key', 'p_client_timestamp', 'p_action', 'p_payload'],
    source: 'supabase/migrations/20261006160000_wave5_human_proposals.sql', lines: [68, 155, 170, 172, 173],
    capability: ['actual AAL2 executor with ai.proposals.execute', 'module.ai entitlement',
      'distinct current MFA approver', 'immutable matching parameters/source hash and exact source revisions'],
    fixedAction: 'execute', fixedPayloadKeys: ['proposalId'],
  },
  claimLease: {
    signature: 'api.wave5_runtime_delivery_worker(uuid,text,jsonb)', grant: 'service_role',
    parameters: ['p_runtime_id', 'p_action', 'p_payload'],
    source: 'supabase/migrations/20261008123000_wave5_runtime_scope.sql', lines: [59, 113, 150, 151],
    fixedAction: 'claim', fixedPayload: {},
    capability: ['actual service-role transport', 'exact unexpired RT1 worker scope',
      'one available delivery and current delegated integration authority'],
    identity: 'claim returns actual delivery/lease/invocation identities; it does not reserve usage or send HTTP.',
  },
});

export const SQL_PREPARATION_CONTRACTS = freeze({
  scheduleRevision: { signature: 'api.schedule_synthetic_subscription(uuid,uuid,uuid,timestamptz,bigint,text,integer,timestamptz,timestamptz)',
    grant: 'authenticated', source: 'supabase/migrations/20261006170000_wave5_synthetic_subscriptions.sql', lines: [31, 54, 104],
    actor: 'genuine AAL2 billing-admin in runtime or load-001',
    constraints: ['Exact approved existing plan code/seats/period and expected subscription version.',
      'Read actual returned revision ID and execution ID; never fabricate revisions or MFA rows.'] },
  createInvitation: { signature: 'api.create_invitation(uuid,text,uuid,uuid,uuid,integer)',
    grant: 'authenticated', source: 'supabase/migrations/20260831193714_create_greenfield_foundation.sql', lines: [779, 1045, 1117],
    actor: 'genuine AAL2 load-001 billing-admin with core.members.invite',
    constraints: ['Only exact approved approver/executor emails and original loadReader role/entity/RT1.',
      'Keep returned token private; audit and outbox creation are baseline preparation effects, not contention deltas.',
      'No invitation email delivery or invited-membership insertion.'] },
  createAndApproveProposal: { signature: 'api.wave5_proposal_command(uuid,uuid,uuid,uuid,uuid,timestamptz,text,jsonb)',
    grant: 'authenticated', source: 'supabase/migrations/20261006160000_wave5_human_proposals.sql', lines: [68, 74, 80, 120, 126, 172],
    actors: ['proposer creates', 'distinct genuine AAL2 approver decides'],
    actions: ['create', 'decide'], constraints: ['Fresh original preparation commands; actual source forecast ID/hash and bounded expiry.',
      'Read actual proposal ID/parametersHash/execution_id; count preparation receipts/audits/outbox before the race.'] },
  registerLeaseSubscription: { signature: 'api.wave5_integration_manage(uuid,uuid,uuid,text,uuid,bigint,jsonb)',
    grant: 'authenticated', source: 'supabase/migrations/20261008093000_wave5_persistent_delivery.sql', lines: [62, 68, 80, 90],
    grantSource: 'supabase/migrations/20261008123000_wave5_runtime_scope.sql', grantLine: 148,
    actor: 'genuine AAL2 proposer with integrations.manage and pipeline access', action: 'register',
    constraints: ['Only the exact reviewed accept subscription ID/url/key reference in RT1; no send.',
      'Register after earlier forecast races, freeze one fresh event, and register other3 receiver paths only after lease contention.',
      'All4 enabled subscriptions can create4 heads. Revoke has no public re-enable operation; do not promise unsupported restoration.'] },
});

// Execute these fixed SELECTs only in a separately reviewed private database
// transport. This module cannot execute them. Parameter values and scope lists
// must be independently validated against the frozen review and returned IDs.
export const COMMITTED_READS = freeze({
  transaction: { isolation: 'repeatable-read', readOnly: true, commit: true,
    freshConnection: true, rollbackFixtureEvidenceAllowed: false },
  bindingRules: [
    'Single-tenant reads accept only the actual tenantId for the case scope in the frozen review.',
    'Load tenant UUID array must equal all 500 frozen tenant IDs, without omission, duplication, or extra target.',
    'Every invitation, proposal, revision, invocation, actor, job, and resource identity comes from genuine returned/read state.',
    'Record exact query bytes, typed bindings, transaction identity, observation time and result hash before deriving deltas.',
    'Read-only service access does not establish genuine user Auth/MFA or actual transport overlap.',
  ],
  numericRule: 'Preserve exact integer text; validate nonnegative BigInt and safe-integer bounds before converting. Never round quota units or subscription versions.',
  installedSignaturesAndGrants: {
    parameters: [],
    semantics: 'Actual installed metadata only. Missing signatures, anon/public execute, or missing required grant must stop preparation; source signatures alone are not installed proof.',
    sql: `WITH expected(signature,required_role) AS (VALUES
  ('api.get_pipeline_forecast(uuid,uuid,uuid,uuid)','authenticated'),
  ('api.get_wave5_subscription(uuid)','authenticated'),
  ('api.freeze_pipeline_forecast(uuid,uuid,uuid,uuid,uuid,timestamptz,date,date)','authenticated'),
  ('api.analytics_process_snapshot(uuid,uuid,uuid,timestamptz,timestamptz,timestamptz,timestamptz)','authenticated'),
  ('api.accept_invitation(text)','authenticated'),
  ('api.wave5_reserve_usage(uuid,uuid,text,timestamptz,timestamptz,text)','service_role'),
  ('api.apply_synthetic_subscription(uuid,uuid)','service_role'),
  ('api.wave5_proposal_command(uuid,uuid,uuid,uuid,uuid,timestamptz,text,jsonb)','authenticated'),
  ('api.wave5_runtime_delivery_worker(uuid,text,jsonb)','service_role'),
  ('api.schedule_synthetic_subscription(uuid,uuid,uuid,timestamptz,bigint,text,integer,timestamptz,timestamptz)','authenticated'),
  ('api.create_invitation(uuid,text,uuid,uuid,uuid,integer)','authenticated'),
  ('api.wave5_integration_manage(uuid,uuid,uuid,text,uuid,bigint,jsonb)','authenticated')
)
SELECT e.signature,e.required_role,p.oid IS NOT NULL AS installed,p.prosecdef,p.provolatile,p.proconfig,
  has_function_privilege(e.required_role,p.oid,'EXECUTE') AS required_role_execute,
  has_function_privilege('anon',p.oid,'EXECUTE') AS anon_execute,
  has_function_privilege('authenticated',p.oid,'EXECUTE') AS authenticated_execute,
  EXISTS(SELECT 1 FROM aclexplode(coalesce(p.proacl,acldefault('f',p.proowner))) a
    WHERE a.grantee = 0 AND a.privilege_type = 'EXECUTE') AS public_execute
FROM expected e LEFT JOIN pg_proc p ON p.oid = to_regprocedure(e.signature)
ORDER BY e.signature`,
  },
  scopeSnapshot: {
    parameters: [{ name: 'tenantId', type: 'uuid', scope: 'exact case scope' }],
    semantics: 'business counts forecast rows + proposal execution rows + immutable subscription activation ledger rows; subscriptionVersion separately proves the update. It is not a physical DML-history counter.',
    prerequisites: ['No concurrent fixture preparation or worker sends in this synthetic tenant.', 'Exactly one subscription row.'],
    sql: `WITH scoped_subscription AS (
  SELECT * FROM billing.tenant_subscriptions WHERE tenant_id = $1::uuid
)
SELECT statement_timestamp() AS observed_at,
  (SELECT count(*) FROM scoped_subscription) AS subscription_rows,
  (SELECT count(*) FROM analytics.pipeline_forecasts WHERE tenant_id = $1::uuid)
    + (SELECT count(*) FROM intelligence_control.proposal_executions WHERE tenant_id = $1::uuid)
    + (SELECT count(*) FROM intelligence_control.subscription_activations WHERE tenant_id = $1::uuid) AS business,
  (SELECT count(*) FROM core.memberships WHERE tenant_id = $1::uuid AND status IN ('active','invited')) AS membership,
  (SELECT count(*) FROM core.command_receipts WHERE tenant_id = $1::uuid) AS receipt,
  (SELECT count(*) FROM intelligence_control.usage_reservations WHERE tenant_id = $1::uuid) AS usage,
  (SELECT count(*) FROM audit.events WHERE tenant_id = $1::uuid) AS audit,
  (SELECT count(*) FROM core.outbox_events WHERE tenant_id = $1::uuid) AS outbox,
  (SELECT count(*) FROM intelligence_control.delivery_attempts WHERE tenant_id = $1::uuid) AS lease,
  (SELECT count(*) FROM intelligence_control.subscription_activations WHERE tenant_id = $1::uuid) AS activation,
  s.seats AS seat_limit,
  (SELECT count(*) FROM core.memberships WHERE tenant_id = $1::uuid AND status IN ('active','invited')) AS active_and_invited,
  s.version::text AS subscription_version_text,
  coalesce(q.reserved_units,0)::text AS reserved_units_text,
  coalesce(q.settled_units,0)::text AS settled_units_text
FROM scoped_subscription s
LEFT JOIN intelligence_control.quota_periods q ON q.tenant_id = s.tenant_id
  AND q.metric_code = 'webhook.deliveries'
  AND q.period_start = coalesce(s.trial_started_at,s.created_at)
  AND q.period_end = s.trial_ends_at`,
  },
  invitationProvenance: {
    parameters: [{ name: 'tenantId', type: 'uuid', scope: 'load-001' },
      { name: 'returnedInvitationsAndActors', type: 'jsonb', columns: ['invitation_id uuid', 'actor_id uuid'] }],
    semantics: 'Read before AND after. A losing invitation keeps its candidate inactive and adds zero joined audit/receipt/outbox deltas. No token/email is returned.',
    sql: `WITH cohort AS (
  SELECT * FROM jsonb_to_recordset($2::jsonb) AS x(invitation_id uuid,actor_id uuid)
)
SELECT x.invitation_id,x.actor_id,i.status AS invitation_status,i.accepted_by,
  m.id AS membership_id,m.status AS membership_status,
  (SELECT count(*) FROM core.memberships m0 WHERE m0.tenant_id = $1::uuid AND m0.user_id = x.actor_id AND m0.status IN ('active','invited')) AS active_membership_rows,
  (SELECT count(*) FROM audit.events a WHERE a.tenant_id = $1::uuid
    AND ((a.aggregate_type = 'invitation' AND a.aggregate_id = x.invitation_id)
      OR a.after_context->>'invitation_id' = x.invitation_id::text)) AS audit_rows,
  (SELECT count(*) FROM core.command_receipts r WHERE r.tenant_id = $1::uuid AND r.aggregate_type = 'invitation' AND r.aggregate_id = x.invitation_id) AS receipt_rows,
  (SELECT count(*) FROM core.outbox_events o WHERE o.tenant_id = $1::uuid AND o.aggregate_type = 'invitation' AND o.aggregate_id = x.invitation_id) AS outbox_rows
FROM cohort x
JOIN core.invitations i ON i.tenant_id = $1::uuid AND i.id = x.invitation_id
LEFT JOIN core.memberships m ON m.tenant_id = $1::uuid AND m.user_id = x.actor_id
ORDER BY x.invitation_id`,
  },
  invocationProvenance: {
    parameters: [{ name: 'tenantId', type: 'uuid', scope: 'load-001' }, { name: 'originalInvocationIds', type: 'uuid[]' }],
    semantics: 'Each denied original invocation must remain absent from reservations/events/receipts/audit/outbox; other effect categories additionally use unchanged whole-scope counters and actual atomic-denial evidence.',
    sql: `SELECT x.invocation_id,
  (SELECT count(*) FROM intelligence_control.usage_reservations r WHERE r.tenant_id = $1::uuid AND r.invocation_id = x.invocation_id) AS reservation_rows,
  (SELECT count(*) FROM intelligence_control.usage_events e WHERE e.tenant_id = $1::uuid AND e.invocation_id = x.invocation_id) AS usage_event_rows,
  (SELECT count(*) FROM core.command_receipts r WHERE r.tenant_id = $1::uuid AND r.command_id = x.invocation_id) AS receipt_rows,
  (SELECT count(*) FROM audit.events a WHERE a.tenant_id = $1::uuid AND a.command_id = x.invocation_id) AS audit_rows,
  (SELECT count(*) FROM core.outbox_events o WHERE o.tenant_id = $1::uuid AND o.command_id = x.invocation_id) AS outbox_rows
FROM unnest($2::uuid[]) AS x(invocation_id) ORDER BY x.invocation_id`,
  },
  activationPrerequisites: {
    parameters: [{ name: 'tenantId', type: 'uuid', scope: 'runtime OR load-001' }, { name: 'returnedRevisionId', type: 'uuid' }],
    semantics: 'Preparation and post-case provenance. Any busy quota period blocks activation; no quota/history deletion is permitted.',
    sql: `SELECT r.id AS revision_id,r.actor_id,r.request_id,r.execution_id,r.expected_version::text,
  r.plan_code,r.seats,r.trial_starts_at,r.trial_ends_at,s.version::text AS subscription_version,
  (SELECT count(*) FROM intelligence_control.quota_periods q WHERE q.tenant_id = r.tenant_id AND q.period_end > r.trial_starts_at) AS busy_quota_periods,
  (SELECT count(*) FROM intelligence_control.subscription_activations a WHERE a.tenant_id = r.tenant_id AND a.revision_id = r.id) AS activation_rows,
  (SELECT count(*) FROM core.command_receipts c WHERE c.tenant_id = r.tenant_id AND c.command_name = 'billing.synthetic.activate' AND c.request_id = r.execution_id) AS receipt_rows,
  (SELECT count(*) FROM audit.events a WHERE a.tenant_id = r.tenant_id AND a.event_type = 'billing.synthetic.activate' AND a.request_id = r.execution_id) AS audit_rows,
  (SELECT count(*) FROM core.outbox_events o WHERE o.tenant_id = r.tenant_id AND o.topic = 'billing.synthetic.activated' AND o.payload->>'revisionId' = r.id::text) AS outbox_rows
FROM intelligence_control.subscription_revisions r
JOIN billing.tenant_subscriptions s ON s.tenant_id = r.tenant_id
WHERE r.tenant_id = $1::uuid AND r.id = $2::uuid`,
  },
  proposalPrerequisites: {
    parameters: [{ name: 'tenantId', type: 'uuid', scope: 'runtime' }, { name: 'returnedProposalId', type: 'uuid' }],
    semantics: 'Stored AAL2 decision is required but cannot substitute for real independent session/MFA evidence or current installed capability checks.',
    sql: `SELECT p.id,p.proposer_id,p.execution_id,p.source_forecast_id,p.source_hash,p.parameters_hash,p.created_at,p.expires_at,
  d.approver_id,d.decision,d.assurance,d.parameters_hash AS decision_parameters_hash,
  (SELECT count(*) FROM jsonb_each_text(p.targets)) AS target_count,
  NOT EXISTS (SELECT 1 FROM jsonb_each_text(p.targets) target WHERE NOT EXISTS (
    SELECT 1 FROM crm.opportunities o WHERE o.tenant_id = p.tenant_id AND o.legal_entity_id = p.legal_entity_id
      AND (p.branch_id IS NULL OR o.branch_id = p.branch_id) AND o.id = target.key::uuid AND o.version::text = target.value
  )) AS target_revisions_unchanged,
  (SELECT count(*) FROM intelligence_control.proposal_executions e WHERE e.tenant_id = p.tenant_id AND e.proposal_id = p.id) AS execution_rows
FROM intelligence_control.proposals p
LEFT JOIN intelligence_control.proposal_decisions d ON d.tenant_id = p.tenant_id AND d.proposal_id = p.id
WHERE p.tenant_id = $1::uuid AND p.id = $2::uuid`,
  },
  sourcePopulation: {
    parameters: [{ name: 'tenantId', type: 'uuid', scope: 'one exact reviewed tenant' }],
    semantics: 'Actual total seed rows, not just filtered rows; cap checks cannot hide pre-existing fixtures. Active currency codes are reference data and cannot be added by this plan.',
    sql: `SELECT
  (SELECT count(*) FROM crm.opportunities WHERE tenant_id = $1::uuid) AS opportunity_rows,
  (SELECT count(*) FROM workflow.process_events WHERE tenant_id = $1::uuid) AS process_event_rows,
  (SELECT count(*) FROM core.currencies WHERE active) AS active_currency_codes`,
  },
  restorationBaseline: {
    parameters: [{ name: 'tenantId', type: 'uuid', scope: 'load-001 only' },
      { name: 'returnedApproverAndExecutorIds', type: 'uuid[]', exactLength: 2 }],
    semantics: 'Bind the two exact new memberships and their exact original assignments before modifying state. Membership/subscription versions are recorded and retained, not rewound. No account deletion or new actor adoption.',
    sql: `SELECT s.id AS subscription_id,s.plan_code,s.status,s.seats,s.version::text AS subscription_version,
  s.trial_started_at,s.trial_ends_at,s.current_period_ends_at,
  (SELECT coalesce(jsonb_agg(jsonb_build_object('id',m.id,'userId',m.user_id,'status',m.status,
    'invitedBy',m.invited_by,'joinedAt',m.joined_at,'version',m.version::text,'updatedAt',m.updated_at) ORDER BY m.id),'[]'::jsonb)
    FROM core.memberships m WHERE m.tenant_id = $1::uuid AND m.user_id = ANY($2::uuid[])) AS original_memberships,
  (SELECT coalesce(jsonb_agg(jsonb_build_object('id',a.id,'membershipId',a.membership_id,'roleId',a.role_id,
    'entityId',a.legal_entity_id,'branchId',a.branch_id,'createdBy',a.created_by) ORDER BY a.id),'[]'::jsonb)
    FROM core.role_assignments a JOIN core.memberships m ON m.tenant_id = a.tenant_id AND m.id = a.membership_id
    WHERE m.tenant_id = $1::uuid AND m.user_id = ANY($2::uuid[])) AS original_assignments
FROM billing.tenant_subscriptions s WHERE s.tenant_id = $1::uuid`,
  },
  loadLedgers: {
    parameters: [{ name: 'tenantIds', type: 'uuid[]', scope: 'exact complete 500-tenant set' },
      { name: 'runtimeId', type: 'uuid', scope: 'exact reviewed RT1 runtime' }],
    semantics: 'These are committed database row counts. model_invocation_rows and delivery_attempt_rows are NOT actual HTTP call/send counts.',
    sql: `SELECT statement_timestamp() AS observed_at,
  (SELECT count(*) FROM analytics.pipeline_forecasts WHERE tenant_id = ANY($1::uuid[])) AS forecasts,
  (SELECT count(*) FROM core.command_receipts WHERE tenant_id = ANY($1::uuid[])) AS receipts,
  (SELECT count(*) FROM audit.events WHERE tenant_id = ANY($1::uuid[])) AS audit,
  (SELECT count(*) FROM core.outbox_events WHERE tenant_id = ANY($1::uuid[])) AS outbox,
  (SELECT count(*) FROM intelligence_control.model_invocations WHERE tenant_id = ANY($1::uuid[])) AS model_invocation_rows,
  (SELECT count(*) FROM intelligence_control.model_outcomes o JOIN intelligence_control.model_invocations i USING(invocation_id) WHERE i.tenant_id = ANY($1::uuid[])) AS model_outcome_rows,
  (SELECT count(*) FROM intelligence_control.delivery_attempts WHERE tenant_id = ANY($1::uuid[])) AS delivery_attempt_rows,
  (SELECT count(*) FROM intelligence_control.delivery_outcomes WHERE tenant_id = ANY($1::uuid[])) AS delivery_outcome_rows,
  (SELECT count(*) FROM intelligence_control.edge_receiver_receipts WHERE runtime_id = $2::uuid) AS receiver_receipt_rows,
  (SELECT count(*) FROM intelligence_control.edge_ticks WHERE runtime_id = $2::uuid) AS worker_tick_rows`,
  },
  loadQuiescence: {
    parameters: [{ name: 'runtimeId', type: 'uuid', scope: 'exact reviewed RT1 runtime' }],
    semantics: 'Counts and IDs only; never select Vault values, cron command text, keys, passwords, or Auth tokens. Absence of a running tick alone does not prove no in-flight network request.',
    sql: `SELECT
  (SELECT count(*) FROM intelligence_control.edge_ticks WHERE runtime_id = $1::uuid AND state = 'running') AS running_tick_rows,
  (SELECT coalesce(jsonb_agg(jsonb_build_object('id',jobid,'name',jobname,'active',active) ORDER BY jobid),'[]'::jsonb)
    FROM cron.job WHERE jobname IN ('jentra-w5-20261009-delivery','jentra-w5-20261009-subscription','jentra-w5-20261009-health')) AS reviewed_jobs`,
  },
});

export const RACE_FIXTURES = freeze({
  duplicates: { scopeKey: 'runtime', participants: 100, operation: 'forecast', actors: ['proposer'],
    requires: ['100 genuine distinct sessions for the same actual proposer, independently verified connections.',
      'Exactly one stable original command/key/timestamp/horizon; source fixtures remain unchanged.'],
    expectedDelta: { business: 1, membership: 0, receipt: 1, usage: 0, audit: 1, outbox: 1, lease: 0, activation: 0 },
    provenance: 'command_id + actor_id + returned forecast aggregate ID; cached replies need not identify the winner.', restoration: 'preserveImmutableEvidence' },
  seats: { scopeKey: 'load-001', participants: 2, operation: 'acceptInvitation', actors: ['approver', 'executor'],
    requires: ['Suspend those two exact new memberships; keep proposer/billing active. Set seats3 only after active-plus-invited count2.',
      'Create separate invitations to the same exact two emails/actors using original loadReader role/entity/RT1; never email.',
      'A pending core.invitations row is not an invited core.memberships row.'],
    expectedDelta: { business: 0, membership: 1, receipt: 0, usage: 0, audit: 1, outbox: 0, lease: 0, activation: 0 },
    deniedCode: 'SEAT_QUOTA_EXCEEDED', provenance: 'invitationProvenance before/after + committed whole-scope deltas + actual denial transaction.',
    restoration: 'restoreLoadMembershipsAndSeats' },
  admissions: { scopeKey: 'load-001', participants: 2, operations: ['acceptInvitation', 'activate'], actors: ['approver', 'trusted'],
    requires: ['Fresh approved-target invitation; active-plus-invited2 and seats3.',
      'Actual genuine-MFA scheduled revision to seats2 with matching subscription version; original returned execution ID.',
      'Zero busy quota periods, before the quota reservation case.'],
    branches: ['membership+audit commit and activation is denied with zero effects, cap remains3.',
      'activation+subscription version+receipt+audit+outbox commit, acceptance is denied with zero effects, cap becomes2.'],
    deniedCode: 'SEAT_QUOTA_EXCEEDED', provenance: ['invitationProvenance', 'activationPrerequisites', 'scopeSnapshot'],
    restoration: 'restoreLoadMembershipsAndSeats' },
  activation: { scopeKey: 'runtime', participants: 2, operation: 'activate', actors: ['trusted'],
    requires: ['Two actual independent service-role connections, one real scheduled revision/execution ID.',
      'Existing four runtime actors fit seats5; verified current billing actor authority and real MFA.',
      'Run before model, external, or delivery usage creates a busy runtime quota period.'],
    expectedDelta: { business: 1, membership: 0, receipt: 1, usage: 0, audit: 1, outbox: 1, lease: 0, activation: 1 },
    subscriptionVersionDelta: 1, provenance: ['activationPrerequisites', 'scopeSnapshot'], restoration: 'preserveImmutableEvidence' },
  execution: { scopeKey: 'runtime', participants: 2, operation: 'executeProposal', actors: ['executor'],
    requires: ['Two distinct genuine AAL2 executor sessions, one immutable source-bound proposal.',
      'Created by proposer and genuinely approved by the distinct current MFA approver; unchanged source revisions.',
      'Same original parent command/key/client timestamp; child identity is actual proposal.execution_id.'],
    expectedDelta: { business: 2, membership: 0, receipt: 2, usage: 0, audit: 2, outbox: 2, lease: 0, activation: 0 },
    provenance: 'Parent command + proposal ID and actual child execution ID; one forecast plus one proposal_executions row.',
    restoration: 'preserveImmutableEvidence' },
  outboxLeases: { scopeKey: 'runtime', participants: 2, operation: 'claimLease', actors: ['trusted'],
    requires: ['Exact RT1 runtime UUID, two actual independent service-role connections, all schedules quiesced.',
      'Exactly one current authorized available pending delivery; no other eligible forecast/outbox pair can be materialized by claim.',
      'Register only exact accept subscription after earlier forecast races; freeze one event; register other3 reviewed subscriptions after this case.',
      'Registration uses the real MFA proposer. Existing4 enabled subscriptions require a separately reviewed precise fixture/restoration plan.'],
    sourceDeltaForClaimOnly: { business: 0, membership: 0, receipt: 0, usage: 0, audit: 0, outbox: 0, lease: 1, activation: 0 },
    limitation: 'claim and delivery_authorize do NOT reserve usage; worker_runtime.mjs separately reserves only after claim. A claim-only assertion cannot require usage1.',
    provenance: 'Actual delivery_attempt/lease and returned delivery ID; null second claim is empty, not a denial.',
    restoration: 'retainLeaseAndReservationEvidence' },
  quota: { scopeKey: 'load-001', participants: 20, operation: 'reserveOne', actors: ['trusted'],
    requires: ['20 actual independent service-role connections; actual quota10 plan/cap and current trial period.',
      '20 fresh distinct original invocation IDs, metric webhook.deliveries, quantity string1.',
      'Initial reserved0/settled0; run after seat/admission activations.'],
    expectedDelta: { business: 0, membership: 0, receipt: 0, usage: 10, audit: 0, outbox: 0, lease: 0, activation: 0 },
    deniedCode: 'QUOTA_EXCEEDED', provenance: ['invocationProvenance before/after for all20', 'scopeSnapshot exact units0→10'],
    restoration: 'retainLeaseAndReservationEvidence' },
});

export const INVALID_BOUNDARIES = freeze({
  '10001Rows': { scopeKey: 'runtime', status: 'unavailable-with-reviewed-caps', expectedCode: 'LIMIT_EXCEEDED',
    operations: ['forecast', 'analytics'], requiredPersistentPopulation: '10001 selected opportunities or joined process events in one tenant/entity scope.',
    sourceChecks: ['pipeline_forecasts.sql SELECT limit10001 then n>10000', 'process_metrics.sql SELECT limit10001 then count_rows>10000'],
    reason: 'RPCs accept no source array/count parameter. Caps200 opportunities/800 events cannot reach10001; no cross-tenant aggregation or extra source seeding.' },
  '101Groups': { scopeKey: 'runtime', status: 'requires-existing-authorized-reference-catalog-proof', expectedCode: 'LIMIT_EXCEEDED',
    operation: 'forecast', requiredPersistentPopulation: '101 in-window open opportunities with101 distinct valid existing currency codes; total≤200.',
    sourceChecks: ['pipeline_forecasts.sql groups by row currency, then g>100'],
    reason: 'Current migration reference seeds11 currency codes. Fresh catalog proof is required; adding global currency rows is outside this fixture specification.' },
  '367DayWindow': { scopeKey: 'runtime', status: 'source-supported-without-extra-seeding', expectedCode: 'LIMIT_EXCEEDED',
    operations: ['forecast', 'analytics'], fixture: 'Finite, ordered timestamps/dates with exactly367 days; process end≤asOf≤recordedThrough≤actual server time.',
    sourceChecks: ['pipeline_forecasts.sql horizon_end-horizon_start>366 before replay/select', 'process_metrics.sql window_end-window_start>366days before contract/select'],
    committedProof: 'scopeSnapshot before/after: all eight counter deltas0; actual authenticated permission/entitlement and server54000/LIMIT_EXCEEDED response.' },
  '8MiBPlus1Byte': { scopeKey: 'runtime', status: 'unavailable-with-reviewed-caps', expectedCode: 'LIMIT_EXCEEDED',
    operations: ['forecast', 'analytics'], requiredOutputBytes: 8388609,
    sourceChecks: ['pipeline_forecasts.sql octet_length(generated canonical)>8388608', 'process_metrics.sql generated result byte length>8388608'],
    reason: 'No arbitrary payload/string-size input is projected. UUID/numeric/currency/time projections over capped200/800 rows cannot manufacture an8MiB output; do not pad evidence or widen seed caps.' },
});

export const LOAD_FIXTURES = freeze({
  indexedReads: { percentage: 70, p95StrictlyUnderMs: 500,
    actorOperations: { 'billing-admin': 'indexedBillingRead', proposer: 'indexedForecastRead', approver: 'indexedForecastRead',
      executor: 'indexedForecastRead', 'foreign-member': 'indexedForecastRead' },
    requires: ['Actual nonempty readable forecast for runtime, all498 load scopes AND foreign scope.',
      'Runtime and load-001 billing-admin sessions genuinely AAL2; load-002..498 billing roles do not require MFA.'] },
  ordinaryForecastCommands: { percentage: 20, p95StrictlyUnderMs: 1500, operation: 'forecast',
    actors: ['proposer', 'approver', 'executor'], excludes: ['billing-admin', 'foreign-member', 'operator'],
    requires: ['Fresh command/key per dispatch, stable reviewed horizon/timestamp mapping.',
      'Source-based read capability is sufficient for freeze; no invented manage grant.',
      'Every fresh command including warmup adds one forecast/receipt/audit/outbox; preserve all immutable rows.'] },
  boundedAnalytics: { percentage: 10, p95StrictlyUnderMs: 3000, operation: 'analytics',
    actors: ['proposer', 'approver', 'executor', 'foreign-member'], excludes: ['billing-admin', 'operator'],
    requires: ['Existing nonempty joined CRM process sources in every500 scope, within200/800 caps.',
      'Finite valid fixed window/asOf/recordedThrough; responses are actual scoped reads.'] },
  bounds: { warmupMs: 60000, measuredMs: 300000, maxRunMs: 900000,
    maximumTimedRequests: 100000, maxInflightRequests: 2000, measuredSessionIds: 2000, measuredScopes: 500 },
  noExternalSendProof: ['loadLedgers before/after proves no new model invocation or delivery attempt/outcome/receiver receipt/worker tick rows.',
    'Exact own cron jobs inactive, zero in-flight worker ticks AND separately verified drained transport work.',
    'Hash-bound actual transport journal dispatches only permitted RPCs; actual HTTP model/send counters require separate transport evidence, not renamed database row counts.'],
});

export const RESTORATION_POLICY = freeze({
  preserveImmutableEvidence: ['Keep forecasts, proposals/decisions/executions, revisions/activations, receipts/audits/outbox and usage evidence.',
    'Do not rewind subscription versions, replace immutable evidence, delete source rows, or call restoration a rollback test.'],
  restoreLoadMembershipsAndSeats: ['Bind exact original new membership/assignment IDs/statuses and subscription state before preparation.',
    'After seats/admissions, raise cap to original4 before reactivating both exact original approver/executor memberships; seat trigger otherwise rejects restoration.',
    'Restore only exact reviewed role assignments; use original non-null loadReader entity/branch so accept_invitation does not create a duplicate nullable assignment.',
    'Preserve accepted invitation rows; revoke only exact unused reviewed pending invitations before a later fresh invitation to avoid pending-email collision.',
    'Retain real activation evidence/version increments; any plan/period restoration needs its own exact reviewed source-supported operation.'],
  retainLeaseAndReservationEvidence: ['No external send from contention; never retry/release/delete an unknown lease or reservation.',
    'A known claim-only lease may be retained until expiry/review; do not fabricate an HTTP outcome to clear it.',
    'Quota reservations and periods remain durable. Do not delete/shorten a bucket to bypass BILLING_PERIOD_BUSY or reset the cap.',
    'Restoration attestation must say precisely which membership/seat state was restored and which durable evidence was retained.'],
  unknownOutcome: ['Preserve original IDs, append-only journal and effects; skip automatic restoration and resubmission pending owner review.'],
  privateBoundary: ['No credential/token/password/MFA secret or raw business response in public evidence.',
    'Never touch existing accounts, acceptance stores, concurrent Wave3/4/Employee sources or sessions.',
    'This module neither supplies genuine sessions nor authorizes installation, SQL mutation, provider import or gate completion.'],
});
