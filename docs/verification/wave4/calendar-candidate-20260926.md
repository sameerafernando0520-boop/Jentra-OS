# W4-02A calendar-version candidate verification

**Date:** 2026-09-26  
**Outcome:** Rollback candidate verified; subsequently installed in development
after owner approval as `20260926082441`. The
[gateway/native/recovery increment is now source verified](calendar-client-20260926.md).
Instant/DST resolution, organization assignment and authenticated acceptance remain pending.

The [contract](../../blueprint/42_WAVE4_PRIVATE_HR_ORGANIZATION_CALENDAR_CONTRACT.md)
now has a first database increment for calendar identity, immutable bounded
versions, explicit coverage gaps and attributable command history. It does not
change plans, role grants, employee timelines or private attachment policies.

## Candidate identity and development preflight

- File: [20260926082441_wave4_calendar_versions.sql](../../../supabase/migrations/20260926082441_wave4_calendar_versions.sql)
- SHA-256: `857B26043339D3802A0D9421D134B70F1A114428E3232E73B47E509D295A1244`
- Development project: `xpdoufauvrbdmxgngetv`, ACTIVE_HEALTHY, PostgreSQL 17.
- Ledger: 35 migrations, latest `20260925181927_wave4_employee_foundation`.
- Installed helper definitions for People access, expected versions, hashes,
  receipts and command finishing were read. `btree_gist` exists in `extensions`.
- The security advisor still reports the intentional API-only People RLS tables
  and the pre-existing [leaked-password protection warning](https://supabase.com/docs/guides/auth/password-security#password-strength-and-leaked-password-protection).
  No auth settings were changed.

## Verification evidence

1. A rollback pgTAP baseline failed both expected missing-table assertions for
   calendar identities/versions before implementation.
2. [build_calendar_candidate.ps1](../../../supabase/tests/build_calendar_candidate.ps1)
   combined the additive migration and
   [wave4_calendar_test.sql](../../../supabase/tests/wave4_calendar_test.sql)
   in a transaction with a 3-second lock timeout, 60-second statement timeout and
   final `ROLLBACK`. Its diagnostic raises on any failed assertion. The final
   run returned `1..65`, with no failed assertion.
3. The assertions cover immutable version/event/code history, date exclusion,
   Sunday-to-Monday overlap, invalid/oversized inputs, explicit missing coverage,
   literal search, bounded UUID paging, cross-tenant/entity/branch denial,
   foreign-version substitution, entity-wide management, MFA, role/membership/
   entitlement revocation before replay, receipts/audit/outbox and late-failure
   rollback. Base tables force RLS and give desktop roles no direct access.
4. The installed W4-01 regression returned `1..49` in a separate rollback-only
   transaction. Its default-entitlement assertion now checks the three original
   commercial plans; the intentionally enabled synthetic W4 plan is not treated
   as a disabled commercial plan.
5. The calendar domain validator now enforces the same pattern bounds and refuses
   a working override without regular hours. Employee/calendar domain tests passed
   together (10 tests). Domain analysis reported no issues; targeted Dart
   formatting completed successfully.
6. Post-candidate reads found no calendar tables/API permissions, no fixture
   tenants/plan, an unchanged 35-entry ledger, original People plans still
   disabled, and Jentra Acceptance Lab still subscribed to starter. The dedicated
   owner W4 workspace remained absent; no subscription switch was performed.

## Remaining gates

The reviewed SQL is now installed in development, with 65 installed-schema
assertions passed; the local immutable filename matches the generated ledger
version. The typed authenticated gateway, native calendar
workspace and encrypted draft/retry recovery are now implemented and verified;
see the [client record and installation review](calendar-client-20260926.md).
Departments, manager relationships and employee calendar assignment remain open.
Local pattern validation is not instant/DST resolution or attendance evidence.
The single-session pgTAP suite does not establish real contention or load results.
Rendered calendar UI evidence and Windows build status are recorded separately
in the client record. Signed-in runtime, owner acceptance and production change
are not claimed by this rollback verification.
