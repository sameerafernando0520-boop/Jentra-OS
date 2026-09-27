# Wave 4 remaining development and acceptance matrix

Updated 2026-09-27. This is a living implementation checkpoint, not acceptance.
Owner instruction: complete remaining synthetic Wave 4 development, work solo,
preserve concurrent work and continue independent slices while gates are pending.

## Fresh preflight

Source: `main`, `b51eec0`; concurrent Wave 3 close-review/report-export source,
contracts 43/44, candidates, tests and evidence are present and protected.
Development `xpdoufauvrbdmxgngetv`: ACTIVE_HEALTHY, PostgreSQL 17, 36 migrations
through `20260926082441`. Employee and calendar APIs retain empty search paths,
authenticated-only execution and seven forced-RLS API-only tables.
Starter/growth/scale People entitlements are disabled. `w4_employee_synthetic`
is enabled with zero subscribers. No `w4-employee-synthetic` tenant exists;
signed-in workspace bootstrap/target reconciliation remains an external gate.
Security: seven expected API-only no-policy notices and the pre-existing
leaked-password warning. Performance: ten employee foreign-key index notices and
unused-index notices; no broad auth/config changes are authorized.

## Requirement ownership

| Requirements | Owner / current state | Required evidence |
|---|---|---|
| FR-401–405 | Employee/calendar baseline implemented; extend for every new aggregate | Cross-scope/private/replay/recovery/bounds checks per slice; AC-401/419 |
| FR-406–408 | W4-01 installed; native/real contention and downstream correction open | AC-402/403; compatibility with organization and consumed work |
| FR-409–411 | Organization candidate/native recovery implemented; private HR/reviews/link pending | AC-403/404; two users; no implicit account/role changes |
| FR-412 | Calendar versions installed; instant/assignment candidates verified, unapplied | 25 resolver / 53 organization SQL assertions; native/installation/contention open; AC-405 |
| FR-413–416 | W4-03 missing | Attendance, leave ledger/decision/cancellation, sealed inputs; AC-405/406 |
| FR-417–422 | W4-04 missing | Exact synthetic payroll, obligations/journals/reversal/settlement; AC-407–409 |
| FR-423–428 | W4-05 missing | Projects/dependencies/common time/expenses/billing/margin; AC-410–412 |
| FR-429–434 | W4-06 missing | SLA/dispatch/work orders/parts/equipment/maintenance; AC-413–415 |
| FR-435–438 | W4-07 missing | Capitalization, exact schedules/posting/disposal; AC-416–418 |
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
| AC-404 | Private HR/reviews/link missing |
| AC-405 | Civil pattern baseline and UTC gap/fold/overnight candidate/client checks pass; installation and attendance pending |
| AC-406 | Leave and contention missing |
| AC-407–409 | Payroll, posting/reversal/export/settlement missing |
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

1. W4-02A organization and UTC/calendar resolution: unapplied candidates and
   working domain/gateway/native/recovery. SQL 25/53, organization client 7/14/15,
   calendar preview 5. Final analyzer/render/build/review and acceptance gates open.
2. W4-02B private HR, documents, reviews/account links: pending.
3. W4-03–07: detailed contracts and complete verticals pending, in dependency order.
4. W4-08: integrate and verify throughout; final native/owner gates stay distinct.

No new Wave 4 candidate has been installed during this continuation. Continue
independent implementation while the real synthetic workspace is reconciled.
