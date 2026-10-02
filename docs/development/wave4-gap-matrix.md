# Wave 4 remaining development and acceptance matrix

Updated 2026-10-02. This is a living implementation checkpoint, not acceptance.
Owner instruction: complete remaining synthetic Wave 4 development and reviews,
with additional agents explicitly authorized on October 1 and 2;
preserve concurrent work and continue independent slices while gates are pending.

## Fresh preflight

Source refreshed September 30: `main`, `f9cc342`; concurrent Wave 3 finance,
inventory, operational, notification/dashboard source/candidates/evidence and
commits are present and protected. Wave 4 changes remain unstaged.
Development `xpdoufauvrbdmxgngetv`: ACTIVE_HEALTHY, PostgreSQL 17, 37 migrations
through `20260929224939_wave4_private_hr`, installed after specific owner approval.
Employee/calendar and private APIs retain empty search paths; all 22 base tables
are forced-RLS API-only. Private Edge functions are ACTIVE v1 and reject anonymous
requests with 401; private installed rollback checks pass 82 assertions. Worker
readiness and authenticated runtime evidence remain open.
Starter/growth/scale People entitlements are disabled. `w4_employee_synthetic`
is enabled with zero subscribers. No `w4-employee-synthetic` tenant exists;
signed-in workspace bootstrap/target reconciliation remains an external gate.
Security: 22 expected API-only no-policy notices and the pre-existing
leaked-password warning. Performance: ten employee foreign-key index notices and
unused-index notices; no broad auth/config changes are authorized.

## Requirement ownership

| Requirements | Owner / current state | Required evidence |
|---|---|---|
| FR-401–405 | Employee/calendar baseline implemented; extend for every new aggregate | Cross-scope/private/replay/recovery/bounds checks per slice; AC-401/419 |
| FR-406–408 | W4-01 installed; native/real contention and downstream correction open | AC-402/403; compatibility with organization and consumed work |
| FR-409–411 | Organization reviewed and approval-pending; private HR/reviews/links candidate, trusted handler, client/native recovery implemented and rollback-tested | AC-403/404; installed/deployed worker, actual two-user authentication; no implicit account/role changes |
| FR-412 | Calendar versions installed; instant/assignment candidates verified, unapplied | 25 resolver / 53 organization SQL assertions; native/installation/contention open; AC-405 |
| FR-413–416 | W4-03 attendance/leave and clock CSV candidate/native/recovery implemented; 65 attendance/batch and 59 leave rollback assertions; workforce counts now 16 domain/22 platform/24 native | Installed/native authenticated, actual contention/load, sealed correction integration; AC-405/406 |
| FR-417–422 | W4-04 unapplied exact payroll vertical: 72 SQL, 13 domain, 19 platform/recovery, 20 native checks; isolated Windows build and rendered previews pass | Linked off-cycle differences and project/service adapters; installed/authenticated/real contention/load; AC-407–409 |
| FR-423–428 | W4-05 core planning/time candidate passed 49 SQL, 10 domain, 18 gateway and 26 native checks; eight updated previews inspected; finance native ten checks pass, final provider SQL/source review active | Linked project payroll first combined rollback diagnostic passed 138 assertion calls; final direct-source/credit/lock changes, integrated build and installed/native acceptance remain; AC-410–412 |
| FR-429–434 | W4-06 development and review active in service agent; no integrated acceptance yet | SLA/dispatch/work orders/parts/equipment/maintenance; AC-413–415 |
| FR-435–438 | W4-07 active: eight-table candidate, 88 rollback assertions, 13 domain, 20 gateway and 20 native; eight inspected previews and isolated Windows build pass | Specific installation approval; procurement/stock/equipment adapters and AC-416–418 acceptance remain open |
| FR-439–440 | Baseline employee/calendar UI verified; all new verticals and integrated evidence open | AC-419/420; no fabricated provider success |
| NFR-401–403 | Baseline security/exact arithmetic; new-module coverage open | RLS/grants/private leakage/conservation |
| NFR-404 | Real contention open | Separate overlapping sessions; sequential SQL is insufficient |
| NFR-405–406 | New-module limits/load evidence open | 50 default/200 maximum pages; bounded jobs; read/command p95 |
| NFR-407–410 | Baseline previews/build; integrated visuals/native restart/runtime open | Light/dark, both densities, 200%, restart, analysis/build |

## Acceptance criteria

| Criteria | State / next work |
|---|---|
| AC-401 | Employee/calendar automated baseline; extend every endpoint/file/export |
| AC-402 | Installed employee assertions; signed-in native and contention open |
| AC-403 | Organization rollback guards/cycles/consumption/end/withdrawal and native recovery verified; installation/contention/authenticated acceptance open |
| AC-404 | Candidate/client and installed 82 assertions pass; both reviewed Edge functions deployed v1 and anonymous denial verified. Worker probe, authenticated byte access, actual two-user authentication and owner acceptance remain open |
| AC-405 | Attendance/common-work candidate, exact UTC/break/domain and native correction/recovery checks pass; installation/authentication/real contention remain open |
| AC-406 | Leave policy/grant/expiry/carry, independent decisions, overlap/unpaid/cancellation/revoked replay pass rollback checks; seal corrections and actual contention remain open |
| AC-407–409 | Exact payroll, approval/posting, immutable payslips, original reversal, export and settlement automated evidence passes; linked off-cycle differences and installed/authenticated/contention/load evidence remain open |
| AC-410–412 | Project planning/common time/expense/billing/margin missing |
| AC-413–415 | Service/SLA/work order/equipment/maintenance missing |
| AC-416–418 | Asset capitalization/depreciation/disposal missing |
| AC-419 | Employee/calendar encrypted test restart and previews; new modules and actual Credential Manager restart open |
| AC-420 | Integrated performance/security/native/owner decision open |

## Edge-case traceability

| Cases | Required implementation/verification |
|---|---|
| EC-401–402 | Employee create/replay baseline; repeat for all new commands |
| EC-403–404 | Consumed employment correction, branch transfer and private boundaries |
| EC-405–406 | Frozen calendar evidence, overnight/fold/gap resolution |
| EC-407–410 | Leave/payroll late correction, caps/proration, uncertain posting |
| EC-411–412 | Expense/parts/time/billing source ownership and atomic failure |
| EC-413–414 | Maintenance occurrence identity and disposal/depreciation races |
| EC-415–416 | Old-context response rejection and actionable provider denial |

## Active work

1. W4-02A organization and UTC/calendar resolution: unapplied reviewed candidates
   with SQL 25/53, installed employee/calendar regression 49/65, People desktop 46,
   isolated Windows build and rendered review passing. Specific installation
   approval, installed/native authenticated and contention evidence remain open.
2. W4-02B private HR, documents, reviews/account links: installed development passed
   82 rollback assertions; separate bucket and trusted handlers exist, pinned Deno
   check passed, injected Edge tests 11, domain 6, platform 17 and native 19 passed
   in earlier focused runs. Current combined analysis/goldens/build pass, and
   11 injected handler tests pass again. The owner approved installation/deployment;
   ledger `20260929224939`, both Edge functions ACTIVE v1 and live anonymous denial
   are recorded in the [installed evidence](../verification/wave4/private-hr-installed-20260930.md).
   Worker configuration/probe and authenticated acceptance remain open.
3. W4-03: attendance/leave and clock CSV verticals with encrypted native recovery
   tested; complete seal/difference integration in W4-04. Earlier People totals:
   45 domain, 64 platform, 82 native; refreshed isolated Windows build passes.
   See [September 30 evidence](../verification/wave4/workforce-checkpoint-20260930.md).
4. W4-04: exact synthetic payroll database/domain/gateway/native/recovery vertical
   is implemented and rollback/client/build verified. Complete linked off-cycle
   differences and project/service adapters. W4-05–07 remain required.
5. W4-08: integrate and verify throughout; final native/owner gates stay distinct.

Only the specifically approved private HR migration/functions were installed. Continue
independent implementation while the real synthetic workspace is reconciled.
