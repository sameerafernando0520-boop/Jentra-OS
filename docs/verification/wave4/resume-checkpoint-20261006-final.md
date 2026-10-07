# Wave 4 current verification checkpoint — 2026-10-06

Wave 4 remains incomplete. Current source integration, whole-app analysis and isolated release compilation are verified; installation, dependent providers and real acceptance remain separate gates. No Git writes, persistent installation, deployment, authentication, application launch or acceptance-store change occurred.

## Verified current work

- [All 86 requirements](requirement-review-final-20261006.json): 40 FR, 10 NFR, 20 AC and 16 EC, preserving approved wording and explicit missing evidence.
- [Actual combined SQL rollback](install-composition-result-20261006.json): 15 current candidates, 111 protected tables, 14 strict security/preservation assertions. Current hashes and exact order are [captured](install-composition-prepared-hashes-20261006.json). Existing grants, plans, subscriptions, finance providers and ledger are preserved.
- [Current integrated client evidence](integrated-current-evidence-20261006.json): 994 workspace/copy source files match actual executions/build. Domain full serial 340 passes; platform full 1,062 passes. Every required vertical file appears in the logs. Analyzer passes. Isolated Windows release build passes with exact binary hash, without launch.
- Full desktop: 1,775 passed and 83 pixel comparisons. Within the required Wave 4 test files, only payroll's light/dark previews fail; both include the new Linked corrections button missing from the old approved baseline. All baseline PNGs are preserved. No functional/overflow test failure was reported. No visual approval is inferred.
- Fresh expense Edge handler 14 passes and runtime observation validator 20 passes. Validators are synthetic checks, not real sessions/load. Earlier exact-source SQL business suites, source reviews and Edge entry checks retain their original dates.
- Plugin Management confirms Supabase is installed and enabled. Both exposed Supabase links list the same Jentra development project. Fresh read-only refresh retains 37 migrations/latest `20260929224939`; payroll/projects/service/assets tables and the synthetic tenant are absent.

## Remaining work

The [concrete installation review](install-review-final-20261006.md) is ready for owner approval of the exact 15 SQL candidates and, separately, two expense Edge deployments. Installed employee/calendar/private HR are excluded. Fixture/workspace authority and restore ownership need binding before persistent acceptance writes.

Dependent generic service stock parts and asset stock/procurement conversion providers are absent. Do not substitute fake sales orders, text source references or a second stock posting engine. Other implemented paths, including governed opening assets and internal asset links, remain independently reviewable.

Real overlapping authenticated actors, populated counts and raw p95/load, trusted private workers, authenticated cold launch/recovery/Windows Credential Manager restart, owner visual decisions and signoff remain open. Existing Wave 3 acceptance, concurrent source, local stores and binaries remain protected.
