# Jentra OS HR error audit — 13 October 2026

Nine reproducible desktop HR defects were corrected in source, with sixteen new regression cases. The final affected suites passed **300 tests**. The existing employee mobile app and concurrent Wave 5 work were preserved.

## Errors fixed

| ID | Trigger and previous behavior | Corrected behavior | New cases |
| --- | --- | --- | --- |
| HR-01 | Publishing the next dated payroll rule reset an existing percentage to 1/1, proration to none, rounding to half-away, precision to two places, and cap to none. The default start could overlap the existing version. | Retains the existing rate, amount, proration, rounding, precision, cap and account mapping; defaults the next period to the prior exclusive end with a fresh rule identity. Edits and publication remain explicit. | 2 |
| HR-02 | An employee switch followed by an attendance load failure could leave the first employee's attendance/leave records visible under the second employee; inactive views also retained old rows. | Clears employee-specific records, details, history, balances, clock lineage and cursors before loading the new context. Date changes also clear the previous dated assignment/calendar and policy context. | 2 |
| HR-03 | Opening another leave request followed by a balance failure retained the previous policy's balance. | Clears balance and grants before loading the selected request's policy balance. | 1 |
| HR-04 | Switching payroll employees followed by a read failure retained the previous employee's payslips or component assignments. | Clears employee records, cursors, editor state and prepared export references before the switch; loads assignments for the new employee when the rules view is active. | 2 |
| HR-05 | An employee detail response could restore visible records after its controller was disposed when the selected scope changed. | Disposal clears visible records and editor state. Async reads and local draft loads check disposal before publishing results. | 1 |
| HR-06 | An employee command confirmed after scope disposal could delete the original encrypted retry receipt before the new scope reconciled it. | Retains the exact sealed request after a late confirmation; a fresh controller retries/reconciles that original request before cleanup. | 1 |
| HR-07 | Permission, plan or session loss during the optional refresh after employee confirmation was swallowed as a normal read failure, leaving the confirmed employee visible. | Clears visible HR data and marks access denied while preserving the already-confirmed outcome and preventing a duplicate command. Ordinary network refresh failures still preserve confirmation. | 3 |
| HR-08 | A pending private-HR read could restore private content after disconnect, including a quick reconnect. An export dialog could also resume using its earlier authorization context. | Each operation is tied to a connection/access generation. Disconnect invalidates that generation and clears private content; reconnect requires a fresh operation. Late reads and dialogs cannot restore content or write an export. Async draft restoration checks the same generation. | 3 |
| HR-09 | Any periodic payroll-correction authorization exception, including a temporary network error, permanently denied and cleared the workspace. | Known authorization, session, plan and MFA failures still revoke access. Temporary connection errors remain retryable; offline checks avoid a remote authorization call. | 1 |

The changes are in [employee_controller.dart](../../../apps/jentra_desktop/lib/src/features/people/employee_controller.dart), [workforce_controller.dart](../../../apps/jentra_desktop/lib/src/features/people/workforce_controller.dart), [private_hr_controller.dart](../../../apps/jentra_desktop/lib/src/features/people/private_hr_controller.dart), [payroll_controller.dart](../../../apps/jentra_desktop/lib/src/features/people/payroll_controller.dart), and [payroll_correction_controller.dart](../../../apps/jentra_desktop/lib/src/features/people/payroll_correction_controller.dart). Regression cases are in their corresponding desktop workspace tests.

## Verification

| Check | Result | Evidence |
| --- | --- | --- |
| Original five desktop HR suites | 86 passed before changes | [desktop-baseline.log](desktop-baseline.log) |
| First reproductions against unchanged source | 11 failed, with test fixtures compiling | [regressions-before-fix-verified.log](regressions-before-fix-verified.log) |
| Payroll rule renewal reproductions | 2 failed against the previous renewal implementation | [payroll-renewal-before-fix-verified.log](payroll-renewal-before-fix-verified.log) |
| Post-confirmation revocation reproductions | 3 failed against the previous employee refresh handler | [employee-revocation-before-fix.log](employee-revocation-before-fix.log) |
| Final desktop HR, calendar and organization suites | **139 passed**, including all 16 new cases and existing UI/golden checks | [desktop-final-v2.log](desktop-final-v2.log) |
| Domain HR, payroll arithmetic, calendars and organization | **62 passed** | [domain-final.log](domain-final.log) |
| HR gateway, encrypted draft and exact retry suites | **99 passed** | [platform-final.log](platform-final.log) |
| Whole desktop analyzer before the final revocation handler adjustment | No issues found | [desktop-analyze.log](desktop-analyze.log) |
| Final HR feature and changed regression test analyzer | **No issues found** | [hr-final-analyze-v2.log](hr-final-analyze-v2.log) |

The SDK used was Flutter **3.47.5** / Dart **3.13.4**. Tests ran serially with concurrency one; Flutter tests used `--no-pub`. Test logs record exact case names. Earlier fixture compilation attempts are retained separately and are not counted as reproduced product defects. The final static check is clean after adding required braces to an existing test fixture statement; this formatting change does not alter test behavior. [Source hashes](source-hashes.json) record the five repaired controllers and five regression test files.

## Installed contract checks

Read-only catalog inspection of Jentra's `xpdoufauvrbdmxgngetv` project at **2026-10-13 15:53:28 UTC** found 114 installed migrations and 84 HR-related API functions, including 79 callable by authenticated users. All **78 API names referenced by the seven inspected HR gateway files** are present. See [live-contract-metadata.json](live-contract-metadata.json) and [gateway-api-presence.json](gateway-api-presence.json).

This refresh confirmed installed attendance, leave, synthetic payroll, clock batch and payroll correction APIs. Older notes that described these staff APIs as uninstalled are no longer the current catalog state. Function presence is distinct from authenticated behavioral acceptance. The detailed payslip API still requires staff payslip-view permission; employee self access remains a separate summary contract. No employee permissions were broadened.

## Scope and acceptance boundary

This is a source repair with local unit, controller, gateway and widget/golden evidence. It does not certify the entire HR/payroll system or statutory payroll. No real employee/payroll rows were queried, no business commands or migrations were executed against the installed database, and no application binary was installed or deployed. Signed-in native acceptance with the intended employee/staff permissions and MFA remains separate from these checks.

No Git files were staged, committed or pushed. Existing concurrent work and the mobile profile-photo implementation were preserved.
