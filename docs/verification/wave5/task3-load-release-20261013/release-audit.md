# Jentra OS release audit, 13 October 2026

**Verdict: production release is not ready.** This is the requested release-check result, not a deployment or a waiver of missing evidence. Delegating technical acceptance does not create a database credential, a signed Windows package, a backup restore result or a complete genuine-session load trace.

The project is Flutter/Dart for Windows, PostgreSQL/Supabase for authoritative commands, and Node/Deno workers and verification tools. The blueprint assigns staging/production separation, migration rehearsal, restore, monitoring, performance/accessibility certification, signed MSIX and a controlled pilot to Wave 6 (`docs/blueprint/05_TEST_AND_DELIVERY.md:53`). Those gates are broader than Wave 5 local checks.

| Release check | Observed outcome | Required completion evidence |
| --- | --- | --- |
| Development installed ledger | 114 migrations / 363 API functions in root read-only live preflight, observed 2026-10-13 17:59:55 UTC | Current contract/grant/RLS fingerprints and preserved original ledger, bound to the exact release |
| Separate staging / production | Current project is explicitly synthetic development; project branch listing returned no branches | Separately authorized projects, configuration separation and a successful staging rehearsal |
| Backup and restore | No actual isolated restore drill is established by the reviewed runtime/status artifacts | Backup availability plus restoration to an isolated target with consistency and recovery verification |
| Concurrency / performance | Full protocol remains unrun; current total server Auth session rows are 21, not the required 2,000 verified independent eligible sessions | Exact seven committed races, online sessions, 60s warmup + 300s measurement and P95 thresholds, complete no-egress observation |
| Accessibility / keyboard | Native acceptance is owned by the separate Windows subagent and remains an independent gate | Actual authenticated native keyboard and focus observations on the exact package, plus accessibility criteria |
| Windows release signing | CurrentUser code-signing certificate inventory returned zero; CI explicitly builds an unsigned Windows release | Signed MSIX, valid signature/timestamp, clean-account installation/upgrade/rollback proof |
| Monitoring / alerting | Repository contains operational event/telemetry contracts and CI source; this does not prove a configured alert destination or a delivered incident alert | Actual monitoring configuration, scoped failure/alert receipt and operational ownership |
| Workers | Another chat currently owns deployment/routing and private/live writes; earlier NOT_FOUND evidence is preserved | Its current reviewed deployment, actual scheduled worker/receiver and recovery outcomes |
| Controlled pilot | No executed pilot is established in the reviewed runtime/status artifacts | Pilot criteria, actual observations, unresolved issue handling and explicit release decision |

Read-only Supabase advisor checks at 17:58:35 UTC returned no ERROR-level findings. Security had 215 informational RLS/no-policy findings and one leaked-password-protection warning. These private RPC-only tables are intentionally inaccessible directly; missing policies do not by themselves establish an exposed route. Verify exact grants/exposed schemas before treating a finding as an access-control defect. The leaked-password setting was not changed. [Official password security guidance](https://supabase.com/docs/guides/auth/password-security#password-strength-and-leaked-password-protection).

Performance advisors reported 289 informational unindexed foreign keys, 784 unused indexes, one informational missing primary key on `inventory.receipt_provenance_pools`, and one duplicate-index warning on `finance.bank_match_claims`. These are investigation inputs, not a measured P95 failure or permission to drop indexes. [Foreign-key guidance](https://supabase.com/docs/guides/database/database-linter?lint=0001_unindexed_foreign_keys), [duplicate-index guidance](https://supabase.com/docs/guides/database/database-linter?lint=0009_duplicate_index).

The complete public runtime provider already exists at `tools/wave5/supabase_runtime_provider.mjs`. Remaining live prerequisites include its private configuration and independent preparation binding, a verified PostgreSQL transport/credential, genuine session population, actual complete external transport capture and continuous job quiescence. The additive transport and observer in this folder implement missing connection/capture adapters; controlled tests do not prove these live prerequisites. Model credentials are not required for the load workload because model/webhook dispatches are excluded.

At the private-input inventory, `database-password.dpapi`, `openai-key.dpapi` and the runtime-input-ready report were absent. No credential was read, no global Auth policy changed, no session created, no live fixture mutated and no production action performed. The other chat's live ownership is respected.

This first audit is accompanied by an additive detailed source-check report, transport/helper verification record, runtime-protocol result and a final hash manifest. Unsupported or missing operational evidence stays open rather than becoming a source-scan pass.
