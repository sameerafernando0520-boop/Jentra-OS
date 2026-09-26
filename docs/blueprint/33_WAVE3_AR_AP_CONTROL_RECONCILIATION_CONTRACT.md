# AC-317 — AR/AP control reconciliation and allocation corrections

Development contract, 2026-09-24. Candidate
`20260922001000_ar_ap_control_reconciliation.sql` is **UNAPPLIED** and depends on
the existing nineteen Wave 3 candidates, including allocation reversals. No
authentication, stock-opening setup, production data or acceptance runtime changes.

The additive [GRNI extension](39_WAVE3_GRNI_CONTROL_RECONCILIATION_CONTRACT.md)
adds `kind: GRNI` to the same report APIs and encrypted workspace. AR/AP allocation
commands remain unchanged. Its candidate is unapplied and requires coordinated
client/schema installation.

## Public commands and reads

All calls require the authenticated actor and explicit tenant, legal entity and
branch. No null branch broadens a report. A report covers **one branch**, not an
entity-wide total. `finance.view` and the new privileged
`finance.controls.reconcile` permission authorize both AR and AP evidence in that
branch. Grants are not installed automatically; existing role/MFA rules apply.
Generation replay, registers and every saved evidence page recheck access.

| API | Input and result |
|---|---|
| `api.generate_control_reconciliation_report` | Standard command envelope; expected version `0`; payload `{id, kind: AR or AP, as_of: YYYY-MM-DD}`. Returns the existing command receipt with immutable report summary. |
| `api.control_reconciliation_reports` | Standard scope, `p_resource: reports`, optional UUID `p_after`; 50 summaries and `next_cursor`. |
| `api.control_reconciliation_report_page` | Standard scope, `p_id`, `p_section`, integer `p_after` default 0, optional `p_evidence_key` account UUID text. Returns summary, section, filter identity, up to 50 rows and decimal-text offset cursor. |
| `api.reverse_customer_allocation` | Standard command envelope; expected version null; payload `{allocation_id, posting_date, reason}`. Requires new privileged `finance.receipts.reverse`. Returns correction ID, original allocation ID, date/reason, optional journal ID and both exact residuals. |
| `api.reverse_supplier_allocation` | Existing permission `finance.payments.reverse`, envelope and payload retained. The new workspace reuses this command. |

Report sections are `accounts`, `items`, `allocations`, `entries`, `journals` and
`differences`. Account filtering includes both sides of a cross-control allocation.
Amounts, base values, FX, write-offs and discounts are decimal strings. Client
validation uses `ExactDecimal`/`BigInt`; integers are only versions, counts and
bounded pagination offsets. Summaries validate scope, requested ID/kind/date,
account totals and `subledger_value - gl_value = difference` before confirmation.
Malformed command responses retain the sealed uncertain request.

## Exact accounting basis

The existing immutable `finance.open_items`, allocations, linked reversals,
`finance.flow_residual` and `finance.flow_post_journal` remain authoritative.
No second posting engine, mutable balance cache or invented balancing entry exists.

AR uses debit-positive control values; AP uses credit-positive values. Each item's
original source journal identifies its control: exactly one account of the relevant
asset/liability type must sum to its signed original base amount. Missing or ambiguous
basis fails explicitly with `OPEN_ITEM_CONTROL_BASIS_REQUIRED`; the application does
not guess using today's mapping. This supported-source rule requires review before
installing against other historical posting conventions. Account metadata remains
governed setup; changing historical account types can cause an explicit basis failure.

The control set is the union of source-derived accounts and the current AR/AP
mapping, at most 50. Dated residuals and **all** posted GL lines in that branch and
control set are compared. Original postings, allocations, write-offs/discounts and
reversals retain command/source lineage. Differences are exposed per account and
command, including GL commands without an open item; offsetting differences are
not hidden by an aggregate zero. This does not discover retired mappings that have
neither an open-item source nor a current mapping. Historical mapping registries and
entity-wide consolidation are separate extensions.

The stable builder reads one MVCC snapshot. Its as-of date is a posting cutoff;
`generated_at` records when that evidence was captured. Later backdated postings
appear only in newly generated reports. Saved report evidence is immutable, private
and never directly readable by authenticated clients. Generation, receipt, audit and
outbox are atomic. Each input stream is limited to 10,000 items, allocations or
control journal lines; evidence is limited to 16 MiB. Oversized input fails without
truncating totals. At most 50,000 subledger entries can result from these bounds.

## Governed corrections

AR allocation now apportions from **remaining** transaction and carrying amounts,
including the final residual, so reallocating a restored rounding share cannot
leave stranded base cents. AP retains its existing remaining-value calculation.
Both use source-journal controls; settlement between different controls posts the
exact transfer between those accounts, plus any realized FX and authorized AR
adjustment. Original item and journal rows are never rewritten.

AR reversal locks the customer, open period and items in the same ordering as
allocation, requires a 1–1000 character reason and a nonfuture date no earlier than
the relevant allocation/reversal history. It appends one unique reversal, negates
the original adjustment journal with original account/amount values and refreshes
the existing AR credit exposure. Discounts and write-offs reverse alongside FX.
Reversal, journal, exposure, audit and receipt all roll back on late failure.
Backdating a subsequent AR allocation ahead of a reversal is rejected. Replay uses
the original command ID, key, payload and timestamp. Changed-body reuse and a
second independent reversal fail. Existing AP proposal-claim protection remains.

Reversals reopen exact balances, allowing existing customer/supplier allocation
workspaces to apply corrected allocations. Cash/bank account setup and recorded
payment evidence are reused. Allocation correction never marks a bank transaction
reconciled or executes an external payment.

## Desktop and recovery

`/finance/controls` provides AR/AP cutoff selection, saved reports, account/source
evidence, exact differences and permission-aware AR/AP reversal preparation.
Reversals have an explicit confirmation dialog. A saved report remains unchanged
after a correction; the user generates a new report to see reopened balances.

Encrypted, actor/entity/branch-scoped slots `control-reconciliation-report` and
`control-allocation-correction` use the existing draft repository. Uncertain results
lock inputs and preserve byte-identical retry across controller restart. Confirmed
commands are cleared before optional evidence refresh. A failed refresh cannot
resend a confirmed command. Offline restart shows inputs but hides restored source
evidence until a fresh access check. Explicit revocation clears visible evidence;
sealed recovery remains encrypted. Permission controls are revalidated on the server.

## Verification boundary

See `docs/verification/remaining-wave3/control-reconciliation-review-20260924.md`.
Synthetic rollback assertions, client tests and rendered widget evidence establish
candidate development behavior only. Installation, authenticated native use, actual
Credential Manager restart, real multi-session contention, load/p95 and owner signoff
remain separate gates. Wave 3 is not complete.
