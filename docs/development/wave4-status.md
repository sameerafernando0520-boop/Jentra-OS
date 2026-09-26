# Wave 4 kickoff and delivery status

Updated: 2026-09-26. User instruction: **start wave 4**, then **continue**.

## Current checkpoint

Wave 4 specification and the first employee development slice are prepared:

- [Wave 4 specification](../blueprint/40_WAVE4_WORKFORCE_AND_DELIVERY_SPEC.md)
- [W4-01 employee contract](../blueprint/41_WAVE4_EMPLOYEE_FOUNDATION_CONTRACT.md)
- [W4-02 private HR and organization/calendar contract](../blueprint/42_WAVE4_PRIVATE_HR_ORGANIZATION_CALENDAR_CONTRACT.md)
- [W4-02A calendar candidate verification](../verification/wave4/calendar-candidate-20260926.md)
- [W4-02A calendar client and installation review](../verification/wave4/calendar-client-20260926.md)
- [W4-01 development installation review](../verification/wave4/employee-install-review-20260925.md)
- [W4-01 native acceptance checklist](../verification/wave4/employee-native-acceptance-20260926.md)

The owner instructed continuation on 2026-09-24 after the concrete contract review
request; the contracts are approved for synthetic development. W4-01 has a
source-complete development slice. The owner authorized development installation
on 2026-09-25. Its migration is installed and the installed-schema test passed;
authenticated native acceptance remains separate.

Fresh development refresh: project `xpdoufauvrbdmxgngetv` is ACTIVE_HEALTHY;
36 migrations through `20260926082441_wave4_calendar_versions`. Seven People
tables and ten scoped API functions exist. All three original plans have
`module.people` disabled. A separate `w4_employee_synthetic` test plan now has
People enabled and zero subscribers. Shared permission/command helper definitions were read.
Advisors report the pre-existing leaked-password-protection warning, seven
intentional no-policy People base tables, ten pre-existing employee foreign keys without covering indexes and
unused-index informational notices. No auth configuration was changed.

On 2026-09-26, after the owner reported creating the synthetic workspace, a fresh
read of this development project still found no `w4-employee-synthetic` tenant or
subscription. The project has one account without an active tenant membership;
the signed-in bootstrap result and app target remain to be reconciled. No plan
switch or owner/account record was fabricated.

## Fresh source audit

Observed branch `main`, HEAD `4e0a244` (`feat(finance): implement AC-317 AR/AP
control reconciliation`). The checkout was initially clean. During the audit,
`supabase/migrations/20260923225202_bank_reconciliation.sql` and
`docs/blueprint/34_WAVE3_BANK_RECONCILIATION_CONTRACT.md` appeared as concurrent
untracked work. Leave these and subsequent concurrent files untouched. Wave 4 uses
document numbers 40–42 to avoid the active Wave 3 contract numbering.

- `docs/blueprint/05_TEST_AND_DELIVERY.md` defines Wave 4's domains but had no detailed
  Wave 4 requirements/acceptance contract.
- `apps/jentra_desktop/lib/src/router.dart` maps People, Projects and Service to
  module placeholders; those are not working domain features.
- `20260831193714_create_greenfield_foundation.sql` creates people/projects/service
  schemas and module-view permissions; these are foundation scaffolding.
- Shared command/context types, operational helpers, scoped reads, native workspace
  and encrypted-draft patterns exist; reuse them after verifying installed contracts.
- `remaining-wave3-status.md` records open Wave 3 finance/integration/acceptance.
  Its commit/uncommitted wording is historical: AC-317 now appears at the observed
  HEAD. No older database count is presented here as fresh verification.

The kickoff source audit preceded the fresh database refresh recorded above.

## Specification verification

Fresh checks on 2026-09-24: 40 functional requirements, 10 non-functional requirements,
20 acceptance criteria and 16 edge cases have unique contiguous identifiers. All
50 requirements map to acceptance criteria; 31 local links across the new documents
and updated dossier index resolve. Reviewed scope, privacy, temporal correction,
finance dependencies and approval language. These are documentation checks, not
application/database test results. Markdown's intentional two-space hard breaks are
retained in document metadata.

## Delivery matrix

| Slice | Status | Dependency / next action |
|---|---|---|
| W4-01 employees and employment | Entitlement-gated development installation; installed-schema assertions pass | Signed-in synthetic tenant bootstrap, test-plan subscription, two-session contention, authenticated native walkthrough and owner acceptance |
| W4-02 private HR, organization/calendars | [Calendar source verified and installed in development](../verification/wave4/calendar-client-20260926.md): typed gateway, native workspace and encrypted recovery; 65 installed-schema checks passed | Calendar authenticated acceptance/contention; W4-01; dated organization assignments, then private HR/reviews/link with separate document authorization and retention |
| W4-03 attendance/leave | Specified; not implemented | Effective calendars, overlap and leave-ledger contracts |
| W4-04 synthetic payroll | Specified; not implemented | Approved inputs, exact rule contract and verified finance/settlement adapters |
| W4-05 projects/time/expenses | Specified; not implemented | W4-01–02, common work-time ownership and billing/AP integration |
| W4-06 service/equipment/maintenance | Specified; not implemented | Employee eligibility, common time, SLA and stock/billing providers |
| W4-07 fixed assets | Specified; not implemented | Capitalization/schedule contracts and verified finance providers |
| W4-08 integrated verification | Not started | All slices; security, contention/load, visual, restart and owner evidence |

## Preservation and evidence

### W4-01 implementation and verification

- Installed migration `20260925181927_wave4_employee_foundation.sql` defines scoped employee
  identity, half-open spells/assignments, immutable redacted events, four read RPCs
  and one idempotent command RPC. A transfer appears in both authorized branch
  histories without exposing the destination in the source projection. The register
  defaults its date using the legal entity time zone. The installed SQL has the
  same SHA-256 as the reviewed rollback candidate.
- `build_employee_candidate.ps1` ran the candidate and 49 pgTAP assertions against
  development project `xpdoufauvrbdmxgngetv` inside a transaction ending in
  `ROLLBACK`. The assertions cover scoped reads, permission/MFA denial, future
  assignment/correction/end/rehire, command replay, destination permission loss,
  default-disabled People entitlements, expired/suspended subscriptions, entitlement
  revocation before replay, private-field rejection and immutable history. The
  original rollback test preceded installation. After installation, the same
  49 assertions passed against the installed schema inside a fresh rollback
  transaction. A post-test read showed zero persistent People employees, spells,
  assignments or events, 35 migrations and no enabled People plans. These
  single-session tests do not prove concurrent behavior.
- Domain validation, the Supabase gateway, encrypted SQLite draft/retry recovery,
  People navigation, register, scoped history and employee editor are implemented.
  Focused tests passed: 4 domain, 1 encrypted restart, and 9 desktop/controller/UI.
  The integrated desktop/domain/platform analyzer reported no issues. Light/dark
  register and light editor render previews were observed at 200% text; clipped
  inputs were corrected before the final preview. The plan-denial view was also
  [rendered and inspected](../../apps/jentra_desktop/test/goldens/employee_plan_denied_light_200.png)
  at 200% text in the light theme; its message/retry control stayed readable and
  the loaded employee was absent.
- The Windows release build passed from a short isolated source copy:
  `build/windows/x64/runner/Release/jentra_desktop.exe`. An initial build from a
  longer Temp path failed in native-plugin output at Windows' path limit; the
  successful short-path build resolved that environmental failure. The isolated
  build was repeated after the entitlement-denial client changes on 2026-09-25
  and returned exit code 0. The isolated copy was removed. No active checkout
  binary was launched or overwritten.
- The candidate seeds `module.people` disabled on current plans and checks its
  subscription state on every scoped read, command and replay. The desktop reports
  plan denial, removes loaded employee data and preserves an uncertain encrypted
  request for retry after restoration. The migration was installed in development
  with all three original plans disabled. On 2026-09-26 the owner selected a
  separate synthetic W4 tenant and plan; the `w4_employee_synthetic` plan was
  provisioned after a rollback preflight, with People enabled and zero
  subscribers. The owner must create its tenant through the signed-in setup
  flow before its subscription can be attached to this plan.
- A read-only dual-query probe reached distinct PostgreSQL backends, but its query
  intervals did not overlap. The available Supabase connector did not prove true
  employee contention. The exact post-install scenarios and pass criteria are in
  [the contention protocol](../verification/wave4/employee-contention-20260925.md).
  A downstream-consumption/correction race remains a later integrated gate:
  no governed downstream consumer exists yet, and historical correction remains
  disabled until that race passes.
- The installed API is security-definer, contains the entitlement check, and gives
  `authenticated` no base-table SELECT. Authenticated native RPC/UI behavior has
  not been evidenced. Two-session contention and owner acceptance remain open.

### W4-02 contract and first domain check

- The [W4-02 contract](../blueprint/42_WAVE4_PRIVATE_HR_ORGANIZATION_CALENDAR_CONTRACT.md)
  defines dated organization and calendar versions, restricted private HR and
  reviews, exact-user account-link confirmation, and retention gates. A live
  development read confirmed that the current `jentra-attachments` Storage
  policies allow tenant-wide `core.files.view/manage`; private HR documents
  therefore require a separately authorized path.
- The framework-free `WorkCalendarPattern` validator checks local intervals,
  overnight/week-wrap overlap, malformed duration and duplicate exception
  dates, pattern limits and working overrides without regular hours. The focused
  calendar and existing employee tests passed together (10 tests);
  `dart analyze packages/jentra_domain` found no issues, and the
  three touched Dart files passed `dart format --set-exit-if-changed`.
  This does not validate IANA/DST resolution or W4-02 server behavior.
- The additive calendar-version candidate passed 65 pgTAP rollback assertions;
  the installed employee regression passed 49 separately. Post-test reads
  confirmed no persisted calendar objects or fixtures and an unchanged ledger.
  The [verification record](../verification/wave4/calendar-candidate-20260926.md)
  identifies the reviewed SQL hash, limits and open client/DST/contention gates.
- The owner explicitly approved the calendar development installation. It
  succeeded as `20260926082441_wave4_calendar_versions`, with the reviewed SQL
  hash unchanged and local filename/builder aligned to the ledger. The installed
  calendar and employee rollback suites passed 65 and 49 assertions. Three new
  forced-RLS base tables deny direct authenticated access; five APIs grant scoped
  authenticated EXECUTE and deny anon EXECUTE. No calendar role grants, plan
  activation, authenticated native walkthrough or owner acceptance was performed.
- The calendar-version client now has typed scoped response validation,
  `/people/calendars` capability-gated navigation, directory/detail/version/history
  reads, create/publish/rename editors and encrypted exact-request retry. Stale
  drafts require explicit comparison; access loss clears visible data. Confirmed
  writes survive optional read failures without retaining another calendar's
  version/history. Final focused client checks passed: 13 domain, 14 platform and
  26 desktop tests, including employee regressions; integrated analysis and
  targeted formatting are clean. Light/dark workspace/editor and plan-denial
  renders were inspected at 200% text, plus a wide desktop render. The
  [client verification and concrete installation review](../verification/wave4/calendar-client-20260926.md)
  records the evidence and remaining authenticated gates.
- The calendar-enabled Windows release build passed in 191.8 seconds from an
  isolated short source copy, with all 11 calendar/integration source files
  matching the workspace. No application launch or authenticated walkthrough
  is claimed.

Work solo. Preserve concurrent source and applied migrations. Do not stage, commit,
push, reset, clean or stash. Keep production and real employee/payroll data outside
development. Preserve the stock-opening acceptance session, setup, authentication,
data, binaries and evidence. Build in isolation.

Source checks, automated tests, rollback candidate validation, installation, Windows
compilation, rendered previews and native owner acceptance remain distinct. Wave 4
kickoff does not close any Wave 3 gate.
