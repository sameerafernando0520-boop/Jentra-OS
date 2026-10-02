# Attendance/leave and People verification checkpoint

2026-09-30, Asia/Colombo. Work continues solo under
[the remaining-development instruction](../../development/remaining-wave4-development-prompt.md).
Wave 4 is not complete. No migration, Storage policy, Edge deployment, Auth,
subscription or acceptance-owned data was changed.

## Current source and database

W4-03 now has common UTC work ownership, immutable attendance/raw source history,
independent attendance decisions, versioned leave policies, deterministic exact
grant/effect accounting, accrual/adjustment/carry, private leave decisions and
original-only cancellation. Its scoped named APIs include bounded policy history,
minimal own-receipt reconciliation, current actor authorization and recovery of
the policy identity from an immutable version. Native `/people/workforce` is
wired through the real Supabase gateway. It provides named employee/policy/raw
event pickers, published-zone resolution including explicit fold choices, UTC
breaks, dated policy and grant sources, immutable history, corrections/decisions,
encrypted exact retries and explicit conflict comparison. Leave draft text
expires in memory and encrypted storage after 24 hours; expiry is checked before
editing, saving or submitting as well as by the access monitor.

The shared rollback fixture now uses the actual fixture weekday. A Monday-only
calendar had prevented leave tests from running truthfully on Wednesday; no
installed calendar data was modified. The strict time parser rejects impossible
civil dates and overflow instead of normalizing them silently.

| Unapplied candidate | SHA-256 | Rollback assertions |
|---|---|---:|
| `20260928082234_wave4_attendance_intervals.sql` | `21CB1745977492F343F2992CCC915400F9320A82957F342D943E36A50DB60AD6` | 36 |
| `20260928083449_wave4_leave_ledger.sql` | `1FBDD603A68F1962291C85A90739F599EE629FEF27E5714EE6C00E8A0E37D4B3` | 59 |
| `20260926185432_wave4_private_hr.sql` | `37E14C5A789B9D73BC7B5738CC087C4E5A59D4BF74F2E075CD2BAF70CF87C6C3` | 82 |

The attendance builder includes unapplied resolver/organization prerequisites;
the leave builder adds attendance and leave in the same rollback transaction.
Every builder ends with `rollback;`; assertion failure raises before rollback
completion. A transient leave rerun lock timeout was followed by a successful
59-assertion rerun. This is environment contention during candidate setup, not a
claim of measured application concurrency. Installed employee/calendar checks
passed 49/65 assertions; the organization candidate passed 53 after the fixture
date change.

A final read of `xpdoufauvrbdmxgngetv` still shows 36 migrations through
`20260926082441`, zero employees/calendars, absent attendance/leave/private-contact
tables and zero `w4-employee-synthetic` tenants. Organization/resolution approval
and signed-in workspace reconciliation remain pending. Existing plans and roles
receive no implicit permissions or entitlement changes.

## Client checks and build

The combined People suites passed **45 domain**, **64 gateway/recovery** and
**82 native** tests. W4-03 contributes 13 domain, 16 gateway/recovery and 17
native checks. Tests cover exact interval/leave arithmetic, strict response scope
and identity, bounded histories, source grants, access loss, uncertain replay,
reviewed conflict replacement, optional read failure, unavailable employee
directory during replay, late response discard and private expiry before a
periodic access check. Mock HTTP/JWT and rollback role fixtures are synthetic
test harnesses; they are not signed-in acceptance evidence.

Private HR's search-label goldens were refreshed. Six workforce light/dark,
compact/comfortable and editor previews use actual Manrope/Material fonts at
200% text scaling; wide desktop checks use 1920×1080. Light workforce, dark
workspace/editor and the refreshed private HR light workspace were inspected.
The date label and native command titles were corrected after inspection.
Rendered previews do not establish native authenticated workflows.

An isolated release build passed at
`C:\jw4-client-20260930-a\apps\jentra_desktop\build\windows\x64\runner\Release`.
The first build took 312.5 seconds; a refreshed build containing the final
recovery additions passed in 161.6 seconds. The source copy excludes Git,
generated caches/builds, environment/secret files and local database stores.
Shared checkout binaries and installed apps were not replaced or launched.
The verified source manifest is [client-source-hashes-20260930.json](client-source-hashes-20260930.json)
and the runner/AOT hashes are [client-windows-build-20260930.json](client-windows-build-20260930.json).
A subsequent brace/interpolation-only lint cleanup changes source formatting
without changing its logic. Final focused domain, gateway and integrated native
analyzers returned **No issues found**. Eleven injected Edge handler tests also
passed again. The prior private-HR build auto-review account-limit
rejection is historical; today's isolated builds executed successfully.

## Remaining work

W4-03 is a tested development vertical, with payroll input seals and linked
later-period correction integrated during W4-04 still open. The native import
currently submits one immutable source event per atomic command; a provider
batch/file adapter remains open. Real two-connection contention, p95/load,
installed-schema verification and signed-in native acceptance remain required.

W4-04 provider inspection has begun. The installed journal/open-period functions
and schema constraints were read, and the new
[synthetic payroll contract](../../blueprint/53_WAVE4_SYNTHETIC_PAYROLL_CONTRACT.md)
sets exact calculation, seal, obligation, posting, reversal and settlement rules.
Seven initial exact payroll calculation tests pass; they cover reproducible
earning/deduction/employer totals, rational proration, signed tie rounding,
configured caps, zero paid work, missing basis, coverage and journal precision.
This is the domain calculation start, not a payroll database/native vertical.
Payroll, projects/time/expenses, service/maintenance, fixed assets and integrated
verification must continue. No owner signoff or Wave 4 completion is asserted.
