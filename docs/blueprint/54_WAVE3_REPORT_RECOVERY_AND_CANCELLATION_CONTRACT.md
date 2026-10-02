# Wave 3 report recovery and cancellation

This contract clarifies FR-386–FR-388, FR-395, EC-340 and NFR-313/320 for
inventory valuation, budget variance and bounded report presentation. Server report definitions,
frozen rows, exact decimal strings, permission checks and command authority remain
unchanged.

Inventory valuation and budget variance clear server-derived cost, stock, account, report and cursor
evidence when disconnected or current access is denied. Responses from a prior
access epoch or a disposed workspace cannot restore it. Reconnection rechecks
current scope before displaying a saved report. Encrypted local recovery retains
the user's inputs, original sealed command and confirmed report identifier;
it does not cache server report amounts or posted ledger truth. Legacy local
report summaries are discarded on recovery without creating historical provenance.

A successful generation stores confirmed input metadata and report identifier
atomically against the original command before optional report/page reads.
Failed reads cannot reseal or resend a confirmed command. Transport uncertainty
keeps the original identity and payload for exact retry; scope revocation clears
evidence while preserving governed recovery metadata.

Bounded report waiting and reading must expose accessible progress and cancellation.
Cancellation stops presentation and subsequent optional reads; it does not claim
to cancel a server transaction or erase a sealed command. An already dispatched
generation may finish and must still persist its authoritative receipt. Users may
leave a cancelled wait and recover the same request or confirmed report later.
No second command is prepared while the original result is unresolved. Tests must
distinguish cancellation before dispatch, during response, after confirmation and
after access changes. Installed/native progress and restart remain separate gates.

This presentation behavior applies to control reconciliation, close review,
financial statements, tax summaries, inventory valuation, budget variance and
operational list snapshots and dated party/bank snapshots. Budget actions also save the confirmed version against
the original command before optional list reads; this does not add cancellation to
budget approval or change its permissions or lifecycle. Current budget and report
reads reject responses from a prior access epoch. Scope denial clears budget editor
presentation while encrypted input and command recovery remain governed by the
existing draft boundary.

Known read-access denial (`PERMISSION_DENIED`, `ACCESS_DENIED`,
`MFA_REQUIRED`/`RECENT_MFA_REQUIRED`, `AUTHENTICATION_REQUIRED`) and invalid,
expired or missing authenticated JWT responses must clear report evidence and
require a fresh access check. This applies to the public report/options/page
reads and governed export previews above, including dated cash-flow account
classification options. Read normalization must not change command error
precedence, sealed retry identity or uncertain posting recovery.

Dated cash-flow classification options and their cursors are bound to the
current access epoch. Disconnect, denial and disposal invalidate in-flight
options; reconnect cannot publish an old reply. Encrypted recovery retains
classification inputs and the original sealed command, never account evidence.
A confirmed classification completes its original command before optional
account refresh; stale optional reads cannot restore account evidence.

Report read failures are bound to the same epoch as successful replies. A late
denial from an obsolete connection cannot revoke a newly connected workspace or
replace its current recovery/error presentation. Original command failure receipts
remain recorded locally; this guard applies to current UI presentation only.
