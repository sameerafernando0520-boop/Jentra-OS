# Wave 4 remaining development and acceptance matrix

Updated 2026-10-06. This is a living implementation checkpoint, not acceptance.
Owner instruction: complete remaining synthetic Wave 4 development and reviews,
with additional agents explicitly authorized on October 1 and 2;
preserve concurrent work and continue independent slices while gates are pending.

## Fresh preflight

The [final October 6 requirement review](../verification/wave4/requirement-review-final-20261006.json)
retains all 86 approved IDs and supersedes pending client/build claims in the
dated table below. Current 994-file integration is source-matched: domain 340,
platform 1,062, whole analysis and isolated Windows release build pass. Required
Wave 4 widget files have two payroll pixel comparisons awaiting visual decision;
all other required Wave 4 files pass. Fresh strict 15-candidate composition passes
14 preservation/security assertions across 111 protected tables. Expense handlers
14 and runtime validator 20 pass. Installation/deployment, absent stock/procurement
providers and real authenticated/load/contention/restart/owner acceptance remain
open. See [the concrete install review](../verification/wave4/install-review-final-20261006.md).

Source refreshed October 5: HEAD `d7a2022faf2631e15b9ba2bc181c8b6fa9d83acc`.
The owner committed earlier work externally; this continuation made no Git writes.
Concurrent Wave 3 source/candidates/evidence remain protected. Active Wave 4
changes are module-owned and unstaged. Read-only live evidence is saved in
`docs/verification/wave4/live-refresh-20261005.json`.
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
| FR-417–422 | Unapplied payroll and off-cycle corrections; project/billed corrections pass 201 actual rollback assertions and service corrections/private costs pass 186. Correction domain 12/platform 16/native 14 pass with inspected current previews | Current integrated source/build, installation/authentication/contention/load and AC-407–409 remain open |
| FR-423–428 | Projects pass 55 SQL, 11 domain, 18 gateway and 36 native; eight updated previews inspected. Later project acknowledgement fix passes five platform regressions and all 36 native. Finance/protected expense evidence integration passes current 180 SQL; earlier finance 11/17/28 client counts are historical after integration changes. Milestones pass 144 SQL and 4 domain/5 gateway/20 native, with later maximum-term boundary verification pending | Final current client/recovery reviews, integrated build, installation and AC-410–412 acceptance remain open |
| FR-429–434 | Service/SLA/dispatch/work orders/labor/equipment/maintenance pass 48 SQL, 186 combined payroll/private-cost assertions and 48 current native checks. Private service costs are integrated into dated project margin. Internal fixed-asset equipment has a real scoped adapter and first actual 169 rollback assertions; later envelope guards and their final regression are pending | Stock parts provider, final current internal-link client/review/build, installation and AC-413–415 acceptance remain open |
| FR-435–438 | Governed opening capitalization/books/depreciation/disposal previously passed 88 SQL, 13 domain and 20 gateway. Current recovery passes 27 native and five exact-envelope confirmation tests in a verified source-bound gate; original eight goldens unchanged | Specific installation approval; verified procurement/stock providers, internal equipment integration, current build and AC-416–418 acceptance remain open |
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
| AC-407–409 | Exact payroll plus linked off-cycle corrections, actual billed source/current-credit proof and immutable reversal have automated candidate evidence. Project suite passes 201 and service/private-cost suite 186; current integrated/installed/authenticated/contention/load evidence remain open |
| AC-410–412 | Planning, dated task owners/common time, expenses/billing and dated margin have candidate/client evidence. Protected finance/evidence SQL passes 180; milestone client/recovery passes 4/5/20. Final current reviews/boundary tests/build and installed/native acceptance remain open |
| AC-413–415 | Service/SLA/work orders/equipment/maintenance have candidate/native evidence; current combined correction/cost passes 186 and service recovery native 48. First internal asset link SQL passes 169, with two later envelope regressions pending. Parts provider, final link client/review/build and installed acceptance remain open |
| AC-416–418 | Governed opening capitalization/depreciation/transfer/impairment/revaluation/disposal and original reversal have candidate/client evidence; current exact-request recovery checks pass. Procurement/stock providers, equipment integration, current build and installed acceptance remain open |
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
4. W4-04/W4-05 corrections: latest actual billed-project suite passes 201;
   original payroll and receipt/audit effects remain immutable. Three fixture/error-
   path failures were retained and repaired before this pass. Correction current
   native 14 update/no-update checks and both previews pass. Service combined
   correction/private-cost verification passes 186.
5. W4-05: finish current milestones and protected expense evidence tests/reviews.
   Final protected finance/evidence SQL passes 180; its changed clients need
   current checks. Milestones pass 144 SQL and 4/5/20 client/recovery checks; the
   subsequent payment-term maximum boundary is being verified. Project native 36
   and eight owner-label previews pass; its acknowledgement fix passes five
   platform checks and all 36 native regressions.
6. W4-07: late confirmation and current authority recovery checks pass; continue
   actual scoped source adapter paths. No text reference establishes stock or
   procurement source eligibility. Missing providers cannot produce success.
7. W4-08: stronger new source-bound checks retain historical harness evidence;
   the previous 120-source gate is historical after the project acknowledgement
   fix. The observation validator passes 20 tests, including rejection of reused
   proof across the matrix, without claiming real observations. Final isolated
   build, real contention/load/native/restart/owner gates stay distinct.

Only the specifically approved private HR migration/functions were installed. Continue
independent implementation while the real synthetic workspace is reconciled.
