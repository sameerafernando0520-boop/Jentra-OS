# Corporate Audit & Assurance — installation / rollback runbook

**Not authorised.** Installation requires explicit owner approval naming this
candidate and its SHA-256.

## Preconditions
1. Refresh live ledger read-only: migration count/latest version, `api` function count, confirm no `assurance` schema and no `assurance.%` permissions.
2. Confirm candidate hash still matches the reviewed one (A1: `ecce6d8a…6a86`; re-record if A2 changes it).
3. Fresh rollback suite passes against the same live state, within the same day.
4. No concurrent migration work in progress; existing 115 migrations untouched.

## Install (only after approval)
1. Copy the candidate into `supabase/migrations/` under its timestamp; do not edit any applied migration.
2. Apply through the normal migration path (one migration, one transaction).
3. Post-check: 12 tables with forced RLS; zero table grants to `anon`/`authenticated`/`service_role`; two `api.assurance_*` functions executable by `authenticated` only; 15 permissions; no role granted any `assurance.%` capability.
4. Run the installed variant of the pgTAP suite (still inside `begin … rollback`) and record evidence.

## Roll back an installation
Only if no business data has been written (holds and history must never be destroyed):
1. Verify `select count(*) from assurance.engagements` = 0.
2. In one transaction: drop `api.assurance_command`, `api.assurance_engagement`, `drop schema assurance cascade`, `delete from core.permissions where code like 'assurance.%'` (after confirming no `core.role_permissions` reference them).
3. Record a compensating migration rather than deleting the ledger row.

If engagements exist, do not drop: revoke `execute` on the two API functions to freeze access, and escalate.
