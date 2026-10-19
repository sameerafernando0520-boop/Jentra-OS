# Corporate Audit & Assurance — installation / rollback runbook

**Development project: installed 2026-10-18** with the owner's approval in the development session, as ledger versions
`20261018153931` (A1), `20261018154123` (A2), `20261018154309` (A4), `20261018154450` (A4b),
`20261018155008` (A3) and `20261018155041` (A5). Repository copies are in `supabase/migrations/`;
evidence: [installation record](../verification/assurance/installation-dev-20261018.json).
The installed statements differ from the repository files only in SQL comments.

**Production: not authorised.** Any other project needs its own explicit approval naming the
migrations and their SHA-256.

## Preconditions
1. Refresh live ledger read-only: migration count/latest version, `api` function count, confirm no `assurance` schema and no `assurance.%` permissions.
2. Confirm candidate hashes still match the reviewed ones (A1 `ecce6d8a…6a86`, A2 `f3b8b6ee…0071`, A4 `c0edcbdc…555a`, A4b `f822183c…f251`, A3 `a4857ca8…0db2`, A5 `2dfa9979…3e25`); install A1, A2, A4, A4b, A3, A5 in order.
3. Fresh rollback suite passes against the same live state, within the same day.
4. No concurrent migration work in progress; existing 115 migrations untouched.

## Install (only after approval)
1. Copy the candidate into `supabase/migrations/` under its timestamp; do not edit any applied migration.
2. Apply through the normal migration path (one migration, one transaction).
3. Post-check (after A1 + A2 + A4 + A4b + A3 + A5): 24 tables with forced RLS; zero table grants to `anon`/`authenticated`/`service_role`; twelve `api.assurance*` functions executable by `authenticated` only; 15 permissions; no role granted any `assurance.%` capability.
4. Run the installed variant of the pgTAP suite (`build_assurance_candidate.ps1 -Slice A5 -Installed`, still inside `begin … rollback`) and record evidence.

## Roll back an installation
Only if no business data has been written (holds and history must never be destroyed):
1. Verify `assurance.engagements`, `assurance.universe_items`, `assurance.plans` and `assurance.templates` are all empty.
2. In one transaction: drop `api.assurance_command`, `api.assurance_engagement`, `api.assurance_test_command`, `api.assurance_tests`, `api.assurance_evidence_command`, `api.assurance_verify_evidence`, `api.assurance_export_manifest`, `api.assurance_plan_command`, `api.assurance_universe`, `api.assurance_plan`, `api.assurance_engagements`, `api.assurance_overview`, then `drop schema assurance cascade`, `delete from core.permissions where code like 'assurance.%'` (after confirming no `core.role_permissions` reference them).
3. Record a compensating migration rather than deleting the ledger row.

If any of those rows exist, do not drop: revoke `execute` on every `api.assurance*` function to freeze access, and escalate.
