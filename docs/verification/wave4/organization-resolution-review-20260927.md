# W4-02A organization and instant-resolution installation review

Prepared 2026-09-27 against development `xpdoufauvrbdmxgngetv`. Source HEAD
`b51eec0dce3a73236f3460325394a4dc19e7a2ce` plus explicit dirty Wave 4 paths;
concurrent Wave 3 source is preserved. **Not installed; owner approval pending.**

## Exact installation scope

1. `20260926160000_wave4_calendar_resolution.sql`, SHA-256
   `6ABD4DCEDDBB3124B4BFA01EFD97ECAFABD59F03EE1F85F48B5BC2A2F5685053`:
   two trusted local/UTC helpers and one scoped calendar-resolution API. No new
   table, role grant or entitlement change.
2. `20260926161000_wave4_organization.sql`, SHA-256
   `6F682652564A030E8A3A6960999AA9C51AA96486AB0F7219D4347F5445E31C45`:
   five protected organization tables, five scoped APIs, two permission
   definitions and internal hierarchy/coverage/consumption guards. No existing
   role or plan receives a grant. No existing employee or calendar fact changes.

The principal behavioral risk is that later employee transfers/end commands now
fail atomically when existing organization dates would become incompatible. The
operator must explicitly end/replace compatible organization first. Hierarchy and
employee locking can serialize competing operations; actual overlapping-session
contention remains a release gate. The resolver checks representative IANA edge
cases using round trips; exhaustive all-zone historical proof is not claimed.

This approval excludes private HR storage/worker, attendance/payroll, all Wave 3
candidates, production, real data and role/subscription changes.

## Automated and rendered evidence

- Rollback-only candidates: 25 instant-resolution and 53 organization assertions.
  Original installed-schema regressions with both new candidates injected:
  49 employee and 65 calendar assertions. Diagnostic wrappers fail on any `not ok`.
- Domain: 7 organization and 6 resolution checks. Platform: 14 organization
  gateway/recovery checks; existing calendar gateway/draft suite 16. Native People
  regression suite: 46 checks, including 15 organization and 5 resolution.
- Focused domain/platform/desktop analysis passed. SQLite restart proves encrypted
  exact request recovery using test keys; it does not prove Windows Credential
  Manager restart with a signed-in account.
- Light/dark organization workspace in both densities and both editors inspected
  at 1024×720/200% text; tests scroll to lazily built controls, check keyboard focus,
  and exercise 1920×1080. Resolver light/dark previews also inspected. Rendered
  tests are independent of authenticated native acceptance.
- Isolated release Windows build passed in `C:\jw4org-20260927` in 166.1 seconds.
  It uses current source, excludes generated Windows plugin/build directories,
  authentication databases and `.env*`/secret configuration; no app was launched.
  See `organization-build-source-hashes-20260927.json`,
  `organization-isolated-pubget-20260927.log` and
  `organization-isolated-windows-build-retry-20260927.log`.
- Machine record: `organization-resolution-automated-20260927.json`.

Fresh ledger has 36 migrations, latest `20260926082441`. Post-rollback queries
confirm the candidate objects are absent, employee/calendar tables have zero rows,
and the synthetic bootstrap tenant is still absent. The test lab and existing plans
remain unchanged. Before installation refresh ledger, hashes and advisors; after
approval apply only these candidates, align returned ledger filenames without
altering applied SQL, rerun `-Installed` checks and record grants/RLS/health.

## Remaining acceptance

Signed-in W4 tenant bootstrap reconciliation, exact capability setup, native
workflow, real OS-keystore restart, hierarchy/timeline overlap, load p95 and owner
walkthrough are pending. This review does not close Wave 4 or prior Wave 3 gates.
