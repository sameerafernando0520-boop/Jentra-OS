# Wave 3 GRNI control reconciliation

Status: additive development candidate; installation and native acceptance are separate gates.

AC-317 / AC-326 extension: a branch operator with `finance.view` and
`finance.controls.reconcile`, under the existing privileged-command MFA policy,
can generate and read an immutable `kind: GRNI`, `version: 1` control report.
The existing command envelope, private `finance.control_reports`, audited atomic
generation, replay checks and 50-row evidence-page RPCs remain the public surface.
AR/AP reports and allocation corrections retain their contracts.

GRNI is credit-positive in the entity base currency. At the posting cutoff,
expected value is receipt accrual less matched-bill accrual, unbilled receipt
returns and linked receipt reversals. Bill-linked returns affect AP rather than
GRNI. Every amount comes from the immutable operational source, independently of
the GL amounts being compared. Matched bills use frozen `accrual_amount`,
`accrual_base_amount` and `grni_account_id`, including cumulative rounding and FX.
Receipt returns use their independently calculated `total` / `base_total`.
New receipts freeze the original GRNI account at insertion. Legacy receipts
require a unique original credit line equal to both original transaction and base values; ambiguous
legacy history fails with `GRNI_CONTROL_BASIS_REQUIRED`. Rejected-only legacy
receipts with zero value contribute no monetary movement.
The journal engine's minimum base precision guard remains unchanged.

`items` contains receipts with original, settled and open transaction/base values,
supplier identity, original account, source / journal / command links and date.
Settled here means matched, returned or reversed, not payment. `entries` contains
dated receipt, matched bill-line, unbilled return and reversal movements, with
`receipt_id`, source identity, original account, exact `value` and
`transaction_value`. `journals` contains every posted line on original, current
and historical GRNI accounts within the branch and cutoff. `differences` groups
by account and source type / source ID; unrelated commands cannot cancel merely
because their net account difference is zero. The existing account filter applies
to every section. `allocations` is empty for GRNI; allocation reversal is AR/AP only.

Report totals and every decimal are JSON strings, using the existing six-place
exact-decimal contract. Receipt residuals equal original minus settled. One STABLE
MVCC read freezes all sections. Bounds: 10,000 receipts, 10,000 matched bill lines,
10,000 returns, 10,000 reversals, 10,000 GL lines, 50 accounts, 50,000 output rows
and 16 MiB evidence. Exceeding a bound aborts the whole command. No partial report.

The desktop workspace adds a GRNI choice, receipt and source labels, scoped
account drill-down, and no allocation correction action for GRNI. Its encrypted
recovery preserves the exact sealed generation on uncertain transport or local
write failure. Confirmation atomically replaces that pending request with the
confirmed report identity, including when a view closes or goes offline during
the response. Evidence clears on disconnect, permission denial or disposal;
responses from an earlier access epoch cannot restore it. Reconnection requires
a fresh permission-scoped read. Coordinated client/candidate installation is
required because older clients only recognize AR/AP report kinds.

Verification must cover dated receipts/bills/returns/reversals, original account
changes, FX and rounding, missing/extra GL sources, net-zero differences, branch
and permission/MFA isolation, exact replay, frozen backdated evidence, atomic late
failure, strict rollback, encrypted retry/reopen and light/dark 200% rendering.
Candidate SQL, mock clients, widget previews and a Windows compilation do not
prove installed schemas, native Credential Manager recovery, authenticated
acceptance, real contention/load or owner signoff.
