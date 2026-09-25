# Wave 4 kickoff and delivery status

Date: 2026-09-25. User instruction: **start wave 4**, then **continue**.

## Current checkpoint

Wave 4 specification and the first employee development slice are prepared:

- [Wave 4 specification](../blueprint/40_WAVE4_WORKFORCE_AND_DELIVERY_SPEC.md)
- [W4-01 employee contract](../blueprint/41_WAVE4_EMPLOYEE_FOUNDATION_CONTRACT.md)
- [W4-01 development installation review](../verification/wave4/employee-install-review-20260925.md)

The owner instructed continuation on 2026-09-24 after the concrete contract review
request; the contracts are approved for synthetic development. W4-01 has a
source-complete development candidate with rollback database evidence. Its migration
is not installed; authenticated native acceptance remains separate.

Fresh development refresh: project `xpdoufauvrbdmxgngetv` is ACTIVE_HEALTHY; 34
migrations through `20260911130900_stock_opening_approver_setup`; no workforce tables.
Shared permission/command helper definitions were read. Advisors report the existing
leaked-password-protection warning and unused-index informational notices. No auth
configuration was changed.

## Fresh source audit

Observed branch `main`, HEAD `4e0a244` (`feat(finance): implement AC-317 AR/AP
control reconciliation`). The checkout was initially clean. During the audit,
`supabase/migrations/20260923225202_bank_reconciliation.sql` and
`docs/blueprint/34_WAVE3_BANK_RECONCILIATION_CONTRACT.md` appeared as concurrent
untracked work. Leave these and subsequent concurrent files untouched. Wave 4 uses
document numbers 40–41 to avoid the active Wave 3 contract numbering.

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
| W4-01 employees and employment | Entitlement-gated development candidate; migration unapplied | Plan enablement decision, coordinated installation, two-session contention, authenticated native walkthrough and owner acceptance |
| W4-02 private HR, organization/calendars | Specified; not implemented | W4-01; privacy/retention and self-service contracts |
| W4-03 attendance/leave | Specified; not implemented | Effective calendars, overlap and leave-ledger contracts |
| W4-04 synthetic payroll | Specified; not implemented | Approved inputs, exact rule contract and verified finance/settlement adapters |
| W4-05 projects/time/expenses | Specified; not implemented | W4-01–02, common work-time ownership and billing/AP integration |
| W4-06 service/equipment/maintenance | Specified; not implemented | Employee eligibility, common time, SLA and stock/billing providers |
| W4-07 fixed assets | Specified; not implemented | Capitalization/schedule contracts and verified finance providers |
| W4-08 integrated verification | Not started | All slices; security, contention/load, visual, restart and owner evidence |

## Preservation and evidence

### W4-01 implementation and verification

- Candidate `20260925001000_wave4_employee_foundation.sql` defines scoped employee
  identity, half-open spells/assignments, immutable redacted events, four read RPCs
  and one idempotent command RPC. A transfer appears in both authorized branch
  histories without exposing the destination in the source projection. The register
  defaults its date using the legal entity time zone. The candidate remains unapplied.
- `build_employee_candidate.ps1` ran the candidate and 49 pgTAP assertions against
  development project `xpdoufauvrbdmxgngetv` inside a transaction ending in
  `ROLLBACK`. The assertions cover scoped reads, permission/MFA denial, future
  assignment/correction/end/rehire, command replay, destination permission loss,
  default-disabled People entitlements, expired/suspended subscriptions, entitlement
  revocation before replay, private-field rejection and immutable history. They do not constitute two real
  concurrent sessions or persistent installation evidence. A post-test read still
  showed 34 installed migrations through `20260911130900`; the employee table and
  command RPC were absent.
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
  request for retry after restoration. An owner must choose which plans to enable;
  no plan enablement or migration installation was performed.
- A read-only dual-query probe reached distinct PostgreSQL backends, but its query
  intervals did not overlap. The available Supabase connector did not prove true
  employee contention. The exact post-install scenarios and pass criteria are in
  [the contention protocol](../verification/wave4/employee-contention-20260925.md).
  A downstream-consumption/correction race remains a later integrated gate:
  no governed downstream consumer exists yet, and historical correction remains
  disabled until that race passes.
- Authenticated live RPC/UI behavior has not been evidenced because the candidate
  is not installed. Two-session contention and owner acceptance remain open.

Work solo. Preserve concurrent source and applied migrations. Do not stage, commit,
push, reset, clean or stash. Keep production and real employee/payroll data outside
development. Preserve the stock-opening acceptance session, setup, authentication,
data, binaries and evidence. Build in isolation.

Source checks, automated tests, rollback candidate validation, installation, Windows
compilation, rendered previews and native owner acceptance remain distinct. Wave 4
kickoff does not close any Wave 3 gate.
