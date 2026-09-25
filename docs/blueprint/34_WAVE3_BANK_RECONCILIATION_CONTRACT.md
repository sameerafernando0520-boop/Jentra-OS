# Bank statement import and reconciliation — AC-318

Candidate only. No installation or native acceptance is implied.

## Scope and exact inputs

One authenticated tenant/entity/branch and one existing operational bank account per
command. `finance.view` is required for reads; import, match/reverse and adjustment
add `finance.bank.import`, `finance.bank.reconcile` and `finance.bank.adjust` respectively.
Existing server MFA/scope policy remains authoritative. No authentication changes.

CSV/XLSX files use the existing bounded tabular codec. Required text columns:
`date` (ISO YYYY-MM-DD), `reference` (bank line identity), `description`, `amount`
(signed decimal string, positive inflow, negative outflow, at most six places).
At most 2,000 rows, no formulas, no numeric conversion through binary floating point.
The workspace previews normalized rows and exact total before import. A statement
has a bank-supplied identity, start/end dates, opening and closing balances;
opening plus line amounts must equal closing exactly. Dates must lie in the range.
The server repeats all validations. Duplicate statement identities or duplicate
line references within the bank are rejected atomically, including overlapping files.
Import creates immutable statement/line evidence, audit, outbox and command receipt;
it never creates a journal or changes an open item.

## Matching and correction

Match at most 100 statement lines to 100 posted journal lines, with at least one
side containing exactly one line. Lines must share bank scope/currency and cannot
belong to another active match. Matching uses transaction debit minus credit.
The bank account's GL basis is frozen on import; ambiguous shared GL mappings fail
closed. Import and match serialize on the bank, and journal claims are unique even
across bank accounts. Frozen mapping updates are rejected once used.

Selected source dates must not exceed the matching date. The date must be in an
open period. Exact matching creates no accounting effect. A difference requires
the bank's configured exact tolerance, adjustment permission, a reason, a permitted
expense/revenue account, and a persisted FX rate for foreign currency. The existing
journal engine posts the balanced difference atomically with the match. No control
account or another operational bank account may be used as the offset.

Reversal retains original match and membership evidence, records an immutable linked
reversal, releases active claims and reverses the original adjustment at its original
transaction/base values in an open period. Duplicate reversal fails; exact command
replay returns the same receipt. An uncertain outcome retries the sealed command.

## Public API and desktop

`api.bank_reconciliation_command` uses the existing command envelope; payload action
is `import`, `match`, `reverse` or `rules`. Creation expects version 0; reverse
expects 1; a rule change expects the bank account's current version and requires
`finance.bank.manage`. A rule change records the exact tolerance and reason.
`api.bank_reconciliation_options` reads accounts, statements, statement lines,
journal lines, matches, offset accounts and persisted FX rates with stable UUID
cursors and 50-row pages.
Reads are permission checked on every request. Match evidence includes amounts,
member IDs, journal linkage, reason, actor and timestamp; reversal evidence remains visible.
`/finance/bank` provides file preview, import, source selection, match and confirmed
reversal. Local forms and sealed requests reuse the encrypted scoped draft store.
Offline mutation is disabled; restored source evidence is hidden until fresh access
verification. A confirmed command is cleared before any optional refresh.

## Verification boundary

Rollback tests cover imports, exact balance, malformed/duplicate input, permission,
cross-scope, exact/multi-line matches, over-tolerance rejection, adjustment and reversal,
immutable evidence, stale versions, replay, private tables and late atomic failure.
Client checks cover CSV/XLSX bounds, exact values, recovery, permission loss and UI.
Actual multi-session contention, installed behavior, Credential Manager restart and
owner acceptance require separate evidence. No down migration erases financial history.
