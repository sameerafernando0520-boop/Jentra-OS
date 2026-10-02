# Report recovery and cancellation review — 2026-09-30

Contract [54](../../blueprint/54_WAVE3_REPORT_RECOVERY_AND_CANCELLATION_CONTRACT.md)
was written before the behavior changes. Inventory valuation previously retained
server cost evidence offline, accepted late options/pages after access changes,
and cleared the sealed generation before saving confirmation. Budget variance and
budget actions had similar late-response/confirmation windows. These are confirmed
development gaps corrected in this continuation, rather than new requirements.

Inventory valuation now discards legacy cached summaries, recovers only inputs and
report identity, clears current cost/source evidence on offline or access denial,
and rejects obsolete responses. Budget readers bind the current access epoch;
budget version and variance confirmation are persisted against their original
sealed commands before optional list/page reads. Report amounts are freshly read
under current scope rather than trusted from recovery metadata.

Control reconciliation, close review, statements, tax, valuation, variance and
operational/dated party/bank report presentation expose progress and cancellation.
Cancellation clears presentation and stops subsequent optional reads. A dispatched
command still saves an authoritative receipt; transport uncertainty retains exact
identity/payload. A cancelled wait permits navigation without resealing the request.
This does not claim to abort a PostgreSQL transaction or cancel a budget approval.

## Executed client checks

- [First focused run](../../../build/remaining-wave3/report-recovery-cancellation-first-20260930.log):
  14 passed, including before-dispatch, response, optional-page, uncertainty,
  disposal, encrypted restart and keyboard/semantics at 200%.
- [Broader corrected run](../../../build/remaining-wave3/report-recovery-cancellation-corrected-20260930.log):
  56 passed across report edges, budgets, operational lists and diagnostic previews;
  [focused analyzer](../../../build/remaining-wave3/report-recovery-analyze-20260930.log) was clean.
- [Final focused additions](../../../build/remaining-wave3/report-cancellation-final2-20260930.log):
  16 passed, adding dated statement cancellation and valuation confirmation/restart.
- [Whole desktop](../../../build/remaining-wave3/desktop-report-full-final-20260930.log):
  658 passed, 81 approved-golden failures retained. A subsequent style-only fix
  addresses its one analyzer finding. The subsequent 34 focused read/report edge
  checks and their analyzer passed; current full-suite/coverage refresh follows
  contracts 55–56.

Contracts [55](../../blueprint/55_WAVE3_RECEIVABLE_READ_ACCESS_CONTRACT.md) and
[56](../../blueprint/56_WAVE3_PROCUREMENT_REFERENCE_ACCESS_CONTRACT.md) were written
before correcting the next confirmed access gaps. Receivable register, document,
statement and root dialogs now clear obsolete evidence; command confirmation
while disconnected still resolves original encrypted recovery before presentation.
Procurement selectors bind seven originating controllers and cannot revive after
disconnect/disposal. Read adapters normalize known access failures and suppress
raw diagnostics. A focused test exposed PostgREST Dart 2.9.1 `maybeSingle()` masking
the document denial; a bounded two-row lookup preserves classification and rejects
ambiguous evidence.

- [Adapter checks](../../../build/remaining-wave3/read-access-platform-20260930.log):
  60 passed, including every receivable read and 17 procurement read entry points.
- [Desktop checks](../../../build/remaining-wave3/read-access-desktop-20260930.log):
  42 passed, including all seven selector controllers, disposal/denial/offline,
  paging/search, exact statement history and immutable confirmation recovery.
- [Form/comparison checks](../../../build/remaining-wave3/procurement-interaction-20260930.log):
  four passed, including exact bill controls, supplier/FX/expense/tax choices,
  immutable match exception evidence and incomplete supplier selection denial.

The fixed authentication read states follow the official
[PostgREST error catalogue](https://postgrest.org/en/latest/references/errors.html).
The tests use a mocked transport and do not exercise or alter real authentication.

An intermediate root-workspace invocation used a nonexistent operational test path
and lacked the desktop fonts/SQLite native asset bundle. It was interrupted, then
rerun successfully from `apps/jentra_desktop` with the correct test path. Its
[failure log](../../../build/remaining-wave3/report-recovery-cancellation-final-20260930.log)
is preserved; those environment/command failures are not presented as product
verification. No approved golden was replaced to obtain passing results.

## Evidence boundary

These checks use synthetic gateways, an in-memory SQLite database and fake key
storage. They do not exercise installed candidate RPCs, Windows Credential Manager,
real authentication, cold launch, target-scale p95, native file dialogs or process
restart. The isolated binary will be compiled after final source review and will
not be launched under this prompt. Native acceptance and owner signoff remain open.
