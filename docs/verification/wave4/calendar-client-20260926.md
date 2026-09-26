# W4-02A calendar client and installation review

**Date:** 2026-09-26  
**Outcome:** Calendar source verified and installed in development after explicit
owner approval. Installed-schema regression passed; authenticated native
acceptance remains open.

## Implemented behavior

The native **Work calendars** destination at `/people/calendars` requires
`people.view` and `people.calendars.view`. It has scoped loading, error, empty,
populated and plan-denial states, literal search, a civil-date filter and UUID
keyset paging. Wide windows display the register beside version details; larger
text uses a stacked layout. Users can browse immutable versions, local weekly
hours, explicit overnight intervals, dated exceptions and attributable history.
Missing coverage is displayed explicitly.

Calendar managers can create an identity with its initial version, publish a
separate future version or rename the identity. Codes and published rules are
immutable. The editor supports multiple intervals, same/next-day endings and
working/nonworking dated exceptions. Validation feedback and confirmation controls
remain visible outside the scrolling editor content. The server checks IANA zones,
current entity dates, overlap, MFA and entity-wide authority.

The typed [gateway](../../../packages/jentra_platform/lib/src/supabase_calendar_gateway.dart)
uses only the five scoped `api.people_calendar_*` functions. It validates allowed
fields, scope, date correspondence, bounded and ordered pages, version ancestry,
event lineage, actors and command confirmations. A response arriving after
sign-out is rejected. A malformed or substituted command response remains an
uncertain write rather than clearing the saved request.

The actor/tenant/entity/branch/editor-specific
[draft store](../../../packages/jentra_platform/lib/src/calendar_draft_store.dart)
encrypts the editor and the exact command envelope. Pending commands cannot be
edited or discarded. Reopening SQLite preserves command ID, idempotency key,
client timestamp, expected version and payload. Preparation serializes competing
local saves. A version conflict requires explicit comparison and replacement
before a new command is prepared. Revocation clears all visible calendar and
draft state while retaining an uncertain request encrypted for later authorized
recovery. A verified write survives optional refresh failures; old version/history
details are cleared so they cannot be shown under the newly confirmed identity.

## Verification

| Check | Result |
|---|---|
| Calendar rollback pgTAP candidate | 65 assertions passed (`1..65`), final rollback |
| Installed calendar schema regression | 65 assertions passed (`1..65`), final rollback after installation |
| Installed employee rollback regression | 49 assertions passed (`1..49`), final rollback |
| Calendar/employee domain tests | 13 passed: 9 calendar, 4 employee |
| Platform gateway/recovery tests | 14 passed: 11 calendar gateway, 2 calendar encrypted recovery, 1 employee restart |
| Desktop controller/widget regression | 26 passed: 17 calendar, 9 employee |
| Integrated desktop/domain/platform source and new-test analysis | No issues |
| Focused Dart formatting | 12 files checked; 0 changes |
| Windows release compilation | Passed, 191.8 seconds; isolated source copy; no application launch |

The focused tests cover response scope/identity substitution, filter date drift,
missing coverage, page order/bounds, immutable version ancestry, overnight/exception
validation, event lineage, malformed command confirmations, sign-out during a
request, missing installation, entitlement/MFA/overlap/historical denial, encrypted
SQLite restart, competing local prepares and actor/entity/branch/tenant isolation.
Controller checks cover exact replay, locked pending requests, conflict comparison,
offline draft editing, access revocation and confirmed-write refresh failures.

The Flutter tests ran from their package roots so SQLite native assets were
resolved. Root-level Flutter execution initially lacked those native assets;
package-root execution passed. The previews below are widget renders, not a
signed-in Windows walkthrough or Credential Manager persistence test.

The Windows release build used the short isolated source directory
`C:\jw4c-0f715811`; configuration/authentication stores were excluded. All 11
calendar/integration source files matched the workspace by SHA-256 before the
successful build. An initial copied generated plugin directory prevented Flutter
from creating its symlinks (`PathExistsException`). Removing only that generated
directory inside the verified isolated copy let Flutter regenerate it; compilation
then produced `build/windows/x64/runner/Release/jentra_desktop.exe` with exit 0.
The running acceptance application and its binaries were not overwritten or
launched.
The release bundle was retained under the ignored workspace path
`build/wave4-calendar-20260926/windows`, executable SHA-256
`526C66D5B418F2AF672B17703C8BA1604A6050A1F9381DDDC3BBF2A8EACCC8CC`. This compilation bundle contains no environment configuration;
authenticated acceptance requires a separately configured development build.
The temporary source files were cleaned after preserving the bundle; an empty
directory held by a build process was left rather than interrupting other work.

Observed previews:

- [Wide desktop register and detail](../../../apps/jentra_desktop/test/goldens/calendar_wide_light.png), 1440 × 1100, 100% text.
- [Light workspace](../../../apps/jentra_desktop/test/goldens/calendar_light_200.png) and [dark workspace](../../../apps/jentra_desktop/test/goldens/calendar_dark_200.png), 1024 × 1500, 200% text.
- [Light editor](../../../apps/jentra_desktop/test/goldens/calendar_editor_light_200.png) and [dark editor](../../../apps/jentra_desktop/test/goldens/calendar_editor_dark_200.png), 1024 × 720, 200% text.
- [Plan denial](../../../apps/jentra_desktop/test/goldens/calendar_plan_denied_light_200.png), 1024 × 720, 200% text.

The search label was shortened after inspection showed truncation at 200% text.
Editor feedback was moved beside the fixed confirmation controls. Version/history
and editor rows are reachable by scrolling; a scrollbar makes the editor's
additional content visible. Final render comparisons and employee goldens passed
without modifying the employee baselines.

## Concrete development installation review

The owner explicitly approved installing only
[20260926082441_wave4_calendar_versions.sql](../../../supabase/migrations/20260926082441_wave4_calendar_versions.sql)
in development project `xpdoufauvrbdmxgngetv`. Installation succeeded as ledger
version `20260926082441`, name `wave4_calendar_versions`. The originally reviewed
filename was `20260926004000_wave4_calendar_versions.sql`; the local file and
builder were aligned to the generated ledger version without changing the SQL.
Reviewed and installed source SHA-256:
`857B26043339D3802A0D9421D134B70F1A114428E3232E73B47E509D295A1244`.
The [candidate verification](calendar-candidate-20260926.md) records the SQL
contract and rollback assertions.

The migration adds three forced-RLS calendar base tables, supporting constraints,
indexes/immutable-history guards, two permission definitions and five
authenticated scoped API functions. Commands use the existing People access and
atomic receipt/audit/outbox helpers. Desktop roles receive no direct base-table
access. Existing plans and roles receive no calendar grants or entitlement change;
employee timelines and attachment policies are unaffected. Installation makes
these new objects persistent in the shared development database and adds a ledger
entry. It has no destructive data rewrite. A later rollback of installed objects
would need a reviewed compensating migration; do not edit an applied migration.

Pre-installation pre/post-rollback reads: healthy development project; 35 ledger entries,
latest `20260925181927`; no `people.work_calendars`; zero employees; zero rollback
tenants; zero `w4-employee-synthetic` tenants and zero subscribers to
`w4_employee_synthetic`. The owner-reported workspace result remains to be
reconciled. No owner/account audit was fabricated and no subscription was switched.

Post-installation, the 65-assertion calendar suite and 49-assertion installed
employee regression both passed with `-Installed`, in rollback transactions.
The ledger has 36 entries through `20260926082441`. All three new base tables have
RLS enabled/forced and authenticated SELECT/INSERT denied. All five calendar
APIs grant authenticated EXECUTE and deny anon EXECUTE; no calendar role grants
were added. PostgREST was notified to reload its schema. Calendar identity,
version and event counts are zero; employee and rollback-tenant counts are zero.
The original three plans still have People disabled, and the dedicated test plan
still has zero subscribers. No concurrent Wave 3 candidate was installed.

The security advisor reports seven intentional
[API-only People tables without read policies](https://supabase.com/docs/guides/database/database-linter?lint=0008_rls_enabled_no_policy)
and the pre-existing
[leaked-password-protection warning](https://supabase.com/docs/guides/auth/password-security#password-strength-and-leaked-password-protection).
The performance advisor reports ten pre-existing employee foreign keys without
covering indexes and unused-index informational findings. It reports no calendar
foreign key without a covering index. No auth setting or historical employee
migration was changed.

## Authenticated native acceptance and remaining scope

1. Reconcile the separate owner-created W4 workspace with this development
   project. Verify its tenant/entity/branch and truthful owner audit before
   attaching the synthetic test plan. Use only synthetic fixtures.
2. Give the synthetic operator the explicit People/calendar view capabilities
   and entity-wide calendar management authority through the authorized role
   workflow. Test branch-only management denial and MFA denial; do not widen the
   acceptance lab's existing roles.
3. In a fresh Windows build configured for development, browse/filter the
   calendar register, create a synthetic calendar, publish adjacent future
   versions, show a coverage gap, open older versions, rename and read actor/time/
   reason history. Prove overlapping versions and current/past publication fail.
4. Interrupt a save response, restart Windows with the actual secure key store,
   then retry the original sealed request. Verify one receipt/audit/event, the
   same IDs/body and no plaintext draft. Revoke permission/membership/entitlement
   and confirm visible state is removed and replay is denied.
5. Submit competing expected-version commands from two real authenticated
   sessions. Record the single winner, conflict result and receipt/audit/outbox
   counts. Single-session pgTAP and serialized connector calls are not contention
   proof. Obtain owner acceptance separately.

This is the calendar-version vertical within W4-02A. Departments, dated manager
relationships and employee calendar assignments remain open. Local schedules
do not yet resolve ambiguous/nonexistent civil times to UTC instants; that adapter
must pass DST tests before attendance consumes these versions. Private HR,
reviews/account linking, W4-01 native/contention acceptance and production release
remain separate gates. No production change, application launch or sign-in was
performed for this verification.
