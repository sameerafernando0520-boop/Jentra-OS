# Wave 5 installation result - October 8, 2026

**The six owner-approved migrations are installed in `xpdoufauvrbdmxgngetv`. Wave 5 remains incomplete.**

The ledger changed from 37 to 43 migrations and API functions from 85 to 107. The exact approved byte hashes still match. All 98 existing API/command provider fingerprints remain unchanged. See the [authorization](installation-authorization-20261008.json), [preflight](installation-preflight-20261008.json), [final catalog](installed-catalog-final-20261008.json) and [machine-readable result](installation-result-20261008.json).

## Applied ledger mapping

The connector assigns installation-time ledger versions. The original approved source filenames and hashes are retained below. These six files are applied despite their earlier filename timestamps. Use this mapping before any future CLI migration reconciliation; do not replay them or bulk-push the remaining W3/W4 candidates.

| Order | Approved source | Installed ledger version |
|---|---|---|
| 1 | [20261006140000_wave5_process_metrics.sql](../../../supabase/migrations/20261006140000_wave5_process_metrics.sql) | `20261007195453_wave5_process_metrics` |
| 2 | [20261006143000_wave5_pipeline_forecasts.sql](../../../supabase/migrations/20261006143000_wave5_pipeline_forecasts.sql) | `20261007200707_wave5_pipeline_forecasts` |
| 3 | [20261006150000_wave5_trusted_metering.sql](../../../supabase/migrations/20261006150000_wave5_trusted_metering.sql) | `20261007201325_wave5_trusted_metering` |
| 4 | [20261006153000_wave5_operator_isolation.sql](../../../supabase/migrations/20261006153000_wave5_operator_isolation.sql) | `20261007201500_wave5_operator_isolation` |
| 5 | [20261006160000_wave5_human_proposals.sql](../../../supabase/migrations/20261006160000_wave5_human_proposals.sql) | `20261007201517_wave5_human_proposals` |
| 6 | [20261006170000_wave5_synthetic_subscriptions.sql](../../../supabase/migrations/20261006170000_wave5_synthetic_subscriptions.sql) | `20261007201524_wave5_synthetic_subscriptions` |

## Installed verification

- All 32 introduced function signatures match the review: 22 API functions and 10 private helpers. Public/anonymous execute is denied. Seventeen API functions require authenticated access; five worker RPCs require service role. Private helper access is unavailable to the desktop.
- All 15 new tables enable and force RLS; direct anonymous/authenticated table reads and writes are denied. Immutable evidence tables retain their triggers. Only quota counters, operator authority and the synthetic allowlist are intentionally mutable through reviewed server authority.
- The nullable trial-start column, process cohort index and synthetic membership seat trigger are present.
- [All 126 strict installed SQL checks passed](installed-strict-checks-result-20261008.json), with `finish(true)` and `rollback;`. The composition contained fixture SQL only, not migration reinstallation.
- Before/after catalogs, disabled entitlements and empty state counters match. The [additional residue check](installation-fixture-residue-check-20261008.json) found zero fixture auth accounts and tenants. No synthetic operator/grant/proposal/usage/trial data persisted, no role permission was assigned, and no new entitlement was enabled.
- PostgREST schema reload was requested. A real authenticated API/native request remains an acceptance gate; notification alone does not prove cached endpoint behavior.

## Remaining Wave 5 work

Runtime needs named synthetic tenant/entity/two branches and proposer, distinct MFA approver, executor, billing administrator, separate operator and foreign-tenant account labels. Synthetic plan/role/operator/grant bootstrap and entitlement activation were excluded from this approval. Historical CRM/realized providers, financial/cash/scenario/export adapters, persistent integration/model providers, real authenticated native/MFA/restart/keyboard, contention/load and owner signoff remain open. Installed rollback SQL is not a real signed-in or independent-session acceptance run.

No production, real billing, keys, model provisioning, external sends or worker deployment occurred. The [current development status](../../development/wave5-status.md) and [requirement matrix](requirement-matrix-20261008.md) distinguish these gates.
