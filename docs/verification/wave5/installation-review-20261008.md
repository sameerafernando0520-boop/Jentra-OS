# Wave 5 candidate installation review - October 8, 2026

**Installation update:** The owner approved this exact list and all six files are now installed. See the [installation result](installation-result-20261008.md) for ledger mappings, catalog checks and 126 passing installed assertions. The original pre-installation review below is retained for audit; its JSON and reviewed hashes are unchanged.

**Status: unapplied; owner authorization pending.**

Proposed target: synthetic development project `xpdoufauvrbdmxgngetv`. The read-only [baseline](live-baseline-20261008.json) remains at 37 migrations through `20260929224939` and 85 API functions. The `analytics` and `intelligence_control` schemas are absent. The six files below introduce 22 API functions plus private helpers; the predicted API count after only this list is 107, subject to a fresh installed check.

The approved [parent specification](../../blueprint/wave5/WAVE5_INTELLIGENCE_AND_CONTROL_SPEC.md#native-delivery-and-concurrency), FR-534, requires:

> installation/deployment MUST have a separately recorded owner-authorized target and migration/function list.

The October 6 request authorizes additive development. It has not separately recorded approval to persist this exact target/list. This review makes that installation scope concrete; it does not approve it.

## Exact migration order and byte hashes

| Order | Migration | SHA-256 of file bytes |
|---|---|---|
| 1 | [20261006140000_wave5_process_metrics.sql](../../../supabase/migrations/20261006140000_wave5_process_metrics.sql) | `be586326b7d8ec380a5524a5d8232e67639d677eb192b9fe29da135ee9ffe997` |
| 2 | [20261006143000_wave5_pipeline_forecasts.sql](../../../supabase/migrations/20261006143000_wave5_pipeline_forecasts.sql) | `1ea4ab076cb3deaa9d0f7f92b56c47effc1a0ad45e14839156a2fd6a2d1bd8ed` |
| 3 | [20261006150000_wave5_trusted_metering.sql](../../../supabase/migrations/20261006150000_wave5_trusted_metering.sql) | `632d768e736e35c40ff33ed8aeb7de30c4a421cdce813751b69e67c128c39c1e` |
| 4 | [20261006153000_wave5_operator_isolation.sql](../../../supabase/migrations/20261006153000_wave5_operator_isolation.sql) | `29ce2ed18e40fb3fbf916e11b9ae82742eb75a52f252085eed48da9af9d88e8b` |
| 5 | [20261006160000_wave5_human_proposals.sql](../../../supabase/migrations/20261006160000_wave5_human_proposals.sql) | `b75e9cf94107fd9a959ced43f9e643b163ed579f95fb68c8de7b9e739b10d02e` |
| 6 | [20261006170000_wave5_synthetic_subscriptions.sql](../../../supabase/migrations/20261006170000_wave5_synthetic_subscriptions.sql) | `339e9e86074887d164dd339eb17ac54943c39fca0caf50db575c48529456a9f5` |

The [machine-readable review](installation-review-20261008.json) also records normalized UTF-8 SQL hashes, function signatures and table names. Windows CRLF file-byte hashes differ from the normalized SQL hashes used by the strict composition. Both are retained; no newline normalization is treated as a new migration version.

## Persistent effects in this list

- Add nullable `billing.tenant_subscriptions.trial_started_at` and the process cohort index.
- Add private forced-RLS forecast, usage, operator, proposal and synthetic subscription evidence tables, indexes and RPCs.
- Add four AI permission definitions and `billing.synthetic.manage`; assign them to no roles.
- Insert disabled `quota.ai.tokens`, `quota.webhook.deliveries` and `module.ai` definitions for existing plans if missing; enable none.
- Add the membership seat trigger. Enforcement is restricted to rows explicitly allowlisted in the initially empty synthetic-target table.

## Excluded and required follow-up scopes

No W3/W4 candidate, SQL fixture, tenant/account/operator/grant bootstrap, role assignment, subscription activation, secret/key/model provisioning, worker deployment, receiver request or real billing is included. Installing these six files alone leaves entitlement-gated and synthetic/operator paths unavailable.

A later bootstrap review must name the synthetic tenant/entity/two branches and proposer, distinct MFA approver, executor, billing administrator, separate operator and foreign-tenant account labels. Use a private synthetic plan or an equivalently reviewed tenant-specific arrangement. Enabling analytics/AI/quota entitlements on the shared `starter` plan would affect other tenants and is outside this list.

## Verification and installation procedure

The [strict rollback result](subscription-native-development-result-20261006.json) has 126 passing assertions. The [source hashes](subscription-native-development-20261006.hashes.json) and all six fixture inputs still match on October 8. The [current command dependency fingerprints](command-dependencies-20261008.json) retain the existing command/scope/optimistic-version authority. Sequential duplicate loops do not establish contention safety.

After owner authorization, refresh the live ledger, all file hashes, provider column signatures and command fingerprints. Stop for any unreviewed drift or candidate collision. Apply only this ordered list through the migration connector, verify each ledger entry and installed function signature/grant/forced-RLS state, and refresh the API schema. Perform authenticated allowed/denied checks after the separately reviewed synthetic bootstrap. Record installation separately from runtime/worker/load/owner acceptance. Any function-list or byte change requires an updated review.

## API function list

These signatures are introduced by the six reviewed files; the JSON review also lists their private helper functions.

- `api.analytics_process_snapshot(p_tenant_id uuid,p_legal_entity_id uuid,p_branch_id uuid, p_window_start timestamptz,p_window_end timestamptz,p_as_of timestamptz,p_recorded_through timestamptz)`
- `api.analytics_process_event(p_tenant_id uuid,p_legal_entity_id uuid,p_branch_id uuid,p_event_id uuid)`
- `api.analytics_process_authorize(p_tenant_id uuid,p_legal_entity_id uuid,p_branch_id uuid)`
- `api.analytics_pipeline_authorize(p_tenant_id uuid,p_legal_entity_id uuid,p_branch_id uuid)`
- `api.freeze_pipeline_forecast(p_tenant_id uuid,p_legal_entity_id uuid,p_branch_id uuid, p_command_id uuid,p_idempotency_key uuid,p_client_timestamp timestamptz,p_horizon_start date,p_horizon_end date)`
- `api.get_pipeline_forecast(p_tenant_id uuid,p_legal_entity_id uuid,p_branch_id uuid,p_forecast_id uuid)`
- `api.wave5_reserve_usage(p_tenant_id uuid,p_invocation_id uuid,p_metric_code text, p_period_start timestamptz,p_period_end timestamptz,p_quantity text)`
- `api.wave5_settle_usage(p_tenant_id uuid,p_invocation_id uuid,p_event_id uuid,p_quantity text)`
- `api.wave5_correct_usage(p_tenant_id uuid,p_event_id uuid,p_original_event_id uuid,p_quantity text,p_reason_code text)`
- `api.get_wave5_usage_allowance(p_tenant_id uuid,p_metric_code text,p_period_start timestamptz)`
- `api.issue_operator_tenant_grant(p_tenant_id uuid,p_operator_id uuid,p_reason text,p_expires_at timestamptz,p_idempotency_key uuid)`
- `api.get_operator_health()`
- `api.get_operator_tenant_health(p_tenant_id uuid,p_grant_id uuid)`
- `api.record_wave5_health_probe(p_id uuid,p_tenant_id uuid,p_code text,p_value text,p_observed_at timestamptz)`
- `api.wave5_proposal_authorize(p_tenant_id uuid,p_legal_entity_id uuid,p_branch_id uuid)`
- `api.get_ai_forecast_evidence(p_tenant_id uuid,p_legal_entity_id uuid,p_branch_id uuid,p_forecast_id uuid)`
- `api.wave5_proposal_command(p_tenant_id uuid,p_legal_entity_id uuid,p_branch_id uuid,p_command_id uuid, p_idempotency_key uuid,p_client_timestamp timestamptz,p_action text,p_payload jsonb)`
- `api.get_wave5_proposal(p_tenant_id uuid,p_legal_entity_id uuid,p_branch_id uuid,p_proposal_id uuid)`
- `api.schedule_synthetic_subscription(p_tenant_id uuid,p_command_id uuid,p_idempotency_key uuid,p_client_timestamp timestamptz, p_expected_version bigint,p_plan_code text,p_seats integer,p_trial_starts_at timestamptz,p_trial_ends_at timestamptz)`
- `api.apply_synthetic_subscription(p_tenant_id uuid,p_revision_id uuid)`
- `api.wave5_subscription_authorize(p_tenant_id uuid)`
- `api.get_wave5_subscription(p_tenant_id uuid)`
