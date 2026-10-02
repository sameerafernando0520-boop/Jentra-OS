# Bounded clock CSV development checkpoint

2026-09-30. Development `xpdoufauvrbdmxgngetv`. Work remains solo and unstaged.

The unapplied candidate `20260930070500_wave4_clock_batches.sql` adds two immutable
forced-RLS API-only tables and three scoped APIs: atomic import, batch history and
bounded original-event lineage. It uses the existing attendance import/view
capabilities and grants no existing roles/plans. SQL SHA-256:
`6775123B8EF94C61572EBE2C321557A5B0AB3EB976189115DA14A374145BAFFD`.
The contract is the batch extension of blueprint 52. This adapter records raw
evidence only; it creates no payable time, leave or payroll effect.

The native employee-scoped CSV chooser validates UTF-8, the exact header, 64 KiB,
200 records, quoted fields, canonical UTC times and source identity. A preview
precedes explicit submission. Server checks recompute row/manifest hashes, reuse
only exact same-scope original evidence and reject changed duplicates atomically.
The encrypted operational store retains the same request/event IDs across unknown
outcomes. Editing source system invalidates the preview; access loss or a late
chosen file cannot repopulate an old context. Paths and whole file content are
excluded from drafts, generic receipts and telemetry.

Verification:

- `build_attendance_candidate.ps1 -IncludeClockBatches` passes **65 rollback
  assertions**: 36 attendance baseline plus 29 batch checks. These cover RLS/grants,
  scope/MFA/revoked replay, changed request keys, exact reuse, bad checksums,
  bounds, original lineage, an actual 200-record synthetic job, 50-row history
  pages and injected late outbox failure with no partial rows. This is neither
  installation, real contention nor a measured p95 workload.
- Three new CSV domain tests and six adapter/gateway tests pass. The checksum has
  exact parity with a PostgreSQL UTF-8 SHA-256 oracle. The focused run with existing
  workforce contracts passed eight domain and fifteen platform tests before the
  two additional history/snapshot tests; those two passed in the final six-test
  adapter run. No duplicate aggregate totals are claimed.
- Isolated native checks pass **44**: 20 payroll and 24 workforce. New checks cover
  encrypted stable batch retries, invalidation, late context loss and four
  light/dark compact/comfortable previews at 1024/1920 widths and 200% text.
  All four import previews were inspected. Tab traversal reaches the chooser and
  scrolling reaches confirmation. Domain/platform/native analysis is clean.
- The current isolated source manifest includes the clock/workforce vertical.
  The refreshed release build passed in **91.3 seconds** in
  `C:\jw4-payroll-20260930-c`. AOT SHA-256:
  `79231DD66508DB7D37B016BA2ACC506D2A06F7BB00A8FD178F2ECC6594DB131D`.
  EXE SHA-256: `F424CE412FDC786F867D0B0E797700E57A52982C029EE0F554AC94805FFEB26A`.
  The later correction calculation engine is not in this binary. No app was
  installed or launched.

The development ledger remains 37 migrations through installed private HR.
Attendance/leave, organization/resolution, payroll and this batch candidate remain
unapplied. Their specific installation, authenticated Windows workflows,
Credential Manager restart, actual overlapping sessions/load and owner acceptance
are separate gates. Linked post-seal corrections remain development work.
