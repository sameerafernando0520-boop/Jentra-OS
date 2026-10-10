# Complete live database preflight — October 10, 2026, r2

Read at **2026-10-10 03:06:52.392446+00** on `xpdoufauvrbdmxgngetv`: **43 migrations /107 API functions**, with **120/120 protected function fingerprints unchanged** from 2026-10-09 18:59:33.305239+00. The original six installed Wave5 migrations retain their exact connector ledger versions and were not reinstalled.

| Read-only gate | Fresh result |
|---|---|
| Role permissions /assignments /entitlements /memberships | 87/1/28/1; counts unchanged |
| Wave5 tables | 15 with enabled and forced RLS; flags unchanged |
| Proposed six Auth labels | All six collision counts are zero; no Auth writes or credentials read |
| Exact proposed resources | 500 tenant/entity scopes,501 branches,4 plans and1,003 roles checked; all related collision counts zero |
| Runtime authority /scope /cron /net | Relevant runtime authority, worker-scope, cron-job and net-queue relations remain absent |
| Edge deployments | Only people-private-documents and people-private-purge; no Wave5 runtime/receiver deployment |
| Separate desktop trial | Confirmed; membership count 0; last sign-in 2026-10-09T18:30:22.512847+00:00 |
| Exact Windows target | Package/profile paths absent; account existence unverified after both readonly account APIs failed |

The database metadata and exact SQL-resource collision checks are clear. This does **not** complete the full runtime preflight. The first Windows account method failed with an internal null-reference, and the exact-name CIM fallback reported that client access to the resource was unavailable. No account absence is inferred from those errors.

The four new ordered access-row hashes and15 policy/grant hashes establish fresh metadata baselines. The prior read contains access counts and RLS flags, so historical row/policy/hash equality is not claimed. All120 function definitions are directly hash-compared.

The saved runtime bundle `92a68a58d70a1f9061776be1b6416b8124112577b0a0859ed6f389becc2533d4` remains unapproved and historical for current native source. A final-source paired Preview/Connected package, truthful current native report, independent exact new bundle review and direct owner runtime approval remain required. Image promotion or calculation acceptance provides no runtime authority. Genuine MFA, native keyboard/authentication, delivery, independent contention/load and all109 owner decisions remain separate open gates.

[Summary](complete-live-preflight-20261010-r2-summary.json) · [Raw connected results](complete-live-preflight-20261010-r2-raw.json) · [Exact SQL and SHA binding](complete-live-preflight-20261010-r2-query-hashes.json) · [Fingerprint comparison](complete-live-preflight-20261010-r2-fingerprint-comparison.json) · [Native metadata errors](complete-live-preflight-20261010-r2-native.json).

No migration, bootstrap, Auth/account, secret, deployment, business RPC/probe, delivery, SDK job, approved PNG or living document was changed. Recheck collisions and all exact hashes immediately before any separately approved operation. Production and real billing remain excluded.
