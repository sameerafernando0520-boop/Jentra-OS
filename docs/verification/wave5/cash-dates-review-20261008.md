# Cash payment-date contract review - October 8, 2026

The implemented candidate gives issued payroll, signed payroll recoveries and approved project reimbursements authoritative payment dates through an immutable, independently MFA-reviewed Wave 5 registry. It reads Wave 4 balances and journals without changing their stores, functions or source files. **No new migration is installed or authorized by this review.**

The new file is [20261008120000_wave5_cash_payment_dates.sql](../../../supabase/migrations/20261008120000_wave5_cash_payment_dates.sql), SHA-256 `1463953b0fa76269740a732a59485ff3d160681fb2a6655eedbd8c0aeda42c8a`. The [contract](../../blueprint/wave5/W5_CASH_PAYMENT_DATES_CONTRACT.md) defines source authority, signed residuals, approval, recovery and full-provider semantics.

## Concrete installation effects

The candidate adds two immutable forced-RLS tables with direct client access revoked, two privileged permission definitions and four authenticated date APIs: authorize, bounded source list, proposal read and command. It wraps cash basis/save/get and governed export calculation with revision 3, revoking callable legacy aliases. Role permissions and plan entitlements are not assigned. A source-scoped proposer and a distinct current MFA approver must bind the original source fingerprint, exact proposal digest and expected approved version; serialized approvals reject stale versions.

Revision 3 requires bank cash, receivables, payables, payroll and project reimbursements. Missing dates withhold the entire family; absent source contracts remain source_not_installed. Negative payroll corrections become exact recovery inflows. Revision 2 frozen scenarios retain their historical, partial bank/AR/AP scope. Current source access is rechecked for frozen reopen and governed export. Encrypted recovery preserves the original command identity and timestamp in separate actor/scope/source-kind slots.

## Dependency and ownership boundary

The 14-file table below describes the rollback verification composition, not an installation request. The five Wave 3/5 prerequisites are uninstalled. Wave 4 is optional at installation but required for live payroll, correction and reimbursement coverage; its eight source hashes and original synthetic fixture are unchanged. The original six installed Wave 5 migrations are excluded and must never be replayed. Any later installation plan needs a fresh ledger/dependency review with the relevant Wave 3/4 owners.

| Source | Relationship | SHA-256 |
|---|---|---|
| [20260925002000_wave3_financial_statements.sql](../../../supabase/migrations/20260925002000_wave3_financial_statements.sql) | Uninstalled Wave 3/5 prerequisite | `7596ec3e5b1ac2b348e4b23371ff6c54818a5336d276fa3a03f14f1ecd5f17b6` |
| [20260926009000_wave3_governed_report_exports.sql](../../../supabase/migrations/20260926009000_wave3_governed_report_exports.sql) | Uninstalled Wave 3/5 prerequisite | `85238e684c967e8377221e55f911fcb9dfa64e7696110ee28eacffe8b6586386` |
| [20261008090000_wave5_historical_pipeline.sql](../../../supabase/migrations/20261008090000_wave5_historical_pipeline.sql) | Uninstalled Wave 3/5 prerequisite | `183a8688dd2c78a9e13032a165d2e1787b3d8f9dd4a15aee9b201eddf4767768` |
| [20261008103000_wave5_dated_cash.sql](../../../supabase/migrations/20261008103000_wave5_dated_cash.sql) | Uninstalled Wave 3/5 prerequisite | `24b5ab44250ec5239ab2b942277cb104867d8e67288666c6297d4fa694e4b391` |
| [20261008110000_wave5_governed_export_adapter.sql](../../../supabase/migrations/20261008110000_wave5_governed_export_adapter.sql) | Uninstalled Wave 3/5 prerequisite | `fbe68cc451f5044c03be7b68803ff2afbb858004109a5ee2319960d495e193ed` |
| [20261008120000_wave5_cash_payment_dates.sql](../../../supabase/migrations/20261008120000_wave5_cash_payment_dates.sql) | New Wave 5 candidate | `1463953b0fa76269740a732a59485ff3d160681fb2a6655eedbd8c0aeda42c8a` |
| [20260926160000_wave4_calendar_resolution.sql](../../../supabase/migrations/20260926160000_wave4_calendar_resolution.sql) | Optional, separately owned Wave 4 source | `6abd4dceddbb3124b4bfa01efd97ecafabd59f03ee1f85f48b5bc2a2f5685053` |
| [20260926161000_wave4_organization.sql](../../../supabase/migrations/20260926161000_wave4_organization.sql) | Optional, separately owned Wave 4 source | `6f682652564a030e8a3a6960999aa9c51aa96486ab0f7219d4347f5445e31c45` |
| [20260928082234_wave4_attendance_intervals.sql](../../../supabase/migrations/20260928082234_wave4_attendance_intervals.sql) | Optional, separately owned Wave 4 source | `21cb1745977492f343f2992ccc915400f9320a82957f342d943e36a50db60ad6` |
| [20260928083449_wave4_leave_ledger.sql](../../../supabase/migrations/20260928083449_wave4_leave_ledger.sql) | Optional, separately owned Wave 4 source | `1fbdd603a68f1962291c85a90739f599ee629fef27e5714ee6c00e8a0e37d4b3` |
| [20260930070000_wave4_synthetic_payroll.sql](../../../supabase/migrations/20260930070000_wave4_synthetic_payroll.sql) | Optional, separately owned Wave 4 source | `5517cc4559c3f91901525b38ec8fbf03633da49c587a0d034a885405a43465b2` |
| [20261001080000_wave4_projects_time.sql](../../../supabase/migrations/20261001080000_wave4_projects_time.sql) | Optional, separately owned Wave 4 source | `52ca0ba293d0a621304e01135db1424e69ebff579f14712b6b6c29d8c031e740` |
| [20261001100000_wave4_project_expenses_billing.sql](../../../supabase/migrations/20261001100000_wave4_project_expenses_billing.sql) | Optional, separately owned Wave 4 source | `0430f55698a28ee7c26a609bc982a96cbc20319d204c3d5546f9a6ae4272efef` |
| [20261001110000_wave4_payroll_corrections.sql](../../../supabase/migrations/20261001110000_wave4_payroll_corrections.sql) | Optional, separately owned Wave 4 source | `709170a703a5fd6808ba15de27a4b6cfcb33470da977203b960e2d04e67437cf` |

All 35 new strict checks passed with finish(true), followed by rollback. Query SHA-256 is `a511e68bacf3db62646713c1780555a16ea1cb720a44a2596ec2943112fe3c6a`. The test uses the actual Wave 4 schemas and no Wave 4 shape shims. It covers signed residuals and effective reversal dates, undated-family rejection, five-provider freeze/export parity, exact retries, independent-actor policy, MFA/revocation and immutable decisions. AR/AP are empty in this fixture; the earlier unchanged 116-check composition retains its separate nonempty allocation/reversal evidence and test-only reversal shape shim. Injected claims and sequential competing proposals do not prove real MFA or overlapping sessions.

The [before](cash-dates-catalog-before-20261008.json) and [after](cash-dates-catalog-after-20261008.json) live reads show 43 migrations and 107 API functions with unchanged ledger/provider hashes, 87 role permissions, one role assignment, 28 entitlements and one membership. The new date/scenario tables and Wave 4 payroll/reimbursement sources remain absent; fixture tenant/account counts are zero. The original 126 installed SQL checks are historical installation evidence and were not rerun here.

The [final read-only refresh](cash-dates-live-final-20261008.json) at 2026-10-08 12:10:36.484966+00 confirms the same ledger/API/access counts and absent date/scenario/payroll/reimbursement stores after final SDK verification.

## Current development verification

Current-source scoped Dart analysis is clean; 72 domain, 48 platform and 96 desktop/controller/render tests pass. The Windows release matches all 1,050 selected source files and 34 release files. Twelve cash variants cover 1024x720, 1440x900 and 1920x1080, both themes/densities and 200% text. Sixty fresh top/provider/lower/date/approval frames were captured; 16 were visually inspected, including approval in all twelve variants. Initial Tab focus was checked. These are controlled development renders and tests; authenticated native acceptance and complete keyboard navigation remain open.

[Current SDK/build/render evidence](cash-dates-verification-20261008.md) and [strict SQL result](cash-dates-candidate-result-20261008.json). The earlier platform fixture failure and pre-final native logs are preserved. The 13 shared dashboard/setup golden failures remain open; no approved golden was regenerated.

## Separate remaining approvals and evidence

Before installation, review the exact new file and its dependency closure; this does not enlarge the previous six-file approval or reverse the decision to keep the earlier eight candidates uninstalled. Synthetic identity/role/entitlement setup, secrets, worker deployment and external delivery each need their own concrete review. Real authenticated proposer/approver sessions, native restart/revocation/export/keyboard, actual worker/model delivery, independent contention, target-scale load and owner acceptance remain open. Real billing and production remain excluded. Wave 5 remains incomplete.

[Machine-readable review](cash-dates-review-20261008.json).
