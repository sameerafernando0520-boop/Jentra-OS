# W4-02B private HR installed development evidence

2026-09-30 Asia/Colombo. The owner explicitly approved the migration and both
reviewed Edge deployments. Target: development `xpdoufauvrbdmxgngetv` only.
Reviewed source hashes matched before installation. Project was ACTIVE_HEALTHY,
PostgreSQL 17.6.1.166, with 36 migrations through `20260926082441`.

## Installed scope

The ledger now contains 37 migrations, latest
`20260929224939_wave4_private_hr`. The reviewed candidate was renamed to that
ledger-aligned filename without changing its SQL; SHA-256 remains
`37E14C5A789B9D73BC7B5738CC087C4E5A59D4BF74F2E075CD2BAF70CF87C6C3`.
The original review names the pre-install filename `20260926185432`.
Employee/calendar applied SQL and existing subscriptions/roles were preserved.
Organization/resolution and attendance/leave remain unapplied.

All 15 `people_private` tables have enabled and forced RLS. Authenticated direct
SELECT is denied on every table. The 21 named APIs have empty search paths and
deny anonymous execution; five worker/service APIs are service-only and the
remaining 16 are authenticated-only. `jentra-hr-private` is private, with a
10 MiB object limit and an ALL restrictive policy excluding direct anonymous and
authenticated Storage access. Installed-schema rollback checks passed **82
assertions** using `build_private_hr_candidate.ps1 -Installed`; no test fixtures
were retained.

Both reviewed functions are ACTIVE at version 1:

| Function | Bundle SHA-256 | Authentication |
|---|---|---|
| `people-private-documents` | `013bc0f0544765f1f55534b300eb9ff9db1287baa8fd3aaa51a56de44d6f90a8` | pinned wrapper `auth: user`, then scoped ticket/current permission checks |
| `people-private-purge` | `11090fac763e7a81a1fc0a7e607edc6389b2888230e82c2c307d533e89119010` | pinned wrapper `auth: secret`, then service-only APIs |

The platform JWT precheck is disabled because these reviewed entries implement
their own authentication through `npm:@supabase/server@1.8.0`. Fresh live POST
requests without Authorization or apikey both returned **401 MISSING_CREDENTIALS**
from that wrapper, before handler execution. This proves unauthenticated denial,
not successful authenticated byte access. The first purge deployment omitted its
relative shared hashing dependency and failed bundling; the successful retry
included the unchanged reviewed document handler. No source change was needed.
Retrieved deployed files match the reviewed entries/handlers (line-ending
normalization only where the platform normalizes text).

## Remaining gates and advisors

Fresh database reads after the rollback suite show zero employees, calendars,
private profiles, documents and purge jobs. Worker readiness has **zero rows**.
No synthetic `w4-employee-synthetic` tenant exists. The nonsecret artifact config,
authorized storage probe, secret-key provisioning and schedule activation remain
owner/provider gates. Private content writes remain unavailable until verified
worker readiness; no credentials were extracted and no schedule was activated.

Security advisors show 22 informational no-policy notices for deliberately
API-only People/private tables and the existing leaked-password-protection
warning. Direct grants/RLS were checked separately; no permissive table policies
were added to silence those notices. References:
[RLS advisory](https://supabase.com/docs/guides/database/database-linter?lint=0008_rls_enabled_no_policy),
[Auth advisory](https://supabase.com/docs/guides/auth/password-security#password-strength-and-leaked-password-protection).
No Auth configuration changed.

Successful authenticated storage retries, probe/jobs, HR/subject/reviewer
separation, native acceptance, Credential Manager restart, real contention/load
and owner signoff remain required. Installation does not complete Wave 4.
