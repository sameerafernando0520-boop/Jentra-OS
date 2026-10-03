# Procurement reference access during scope changes

This clarifies FR-349, FR-384, FR-395, AC-322 and NFR-313 for existing
requisition, sourcing, order, receipt, bill, payment, purchase-return and product-unit reference
dialogs. It adds no posting command or historical correction.

Reference dialogs bind their originating controller and read access epoch,
including dialogs pushed to the root navigator. Disconnect, controller disposal,
scope replacement and definite permission/MFA/authentication denial hide all
cached choices, prevent selection and reject late success or failure. Reconnecting
does not revive a dialog from an obsolete access epoch: close it and open a fresh
scoped selector. A current denial also clears the originating controller's server
evidence, while retaining encrypted local inputs and sealed commands.

The originating epoch also governs command transmission after asynchronous
encrypted save/sealing. Reconnection cannot permit an obsolete operation to send;
the same sealed request may be retried from a fresh permitted workspace. Current
presentation ignores stale read/command failures while retaining their original
durable recovery outcome.

Search and keyset paging retain the existing bounded gateway contract. Read errors
show fixed public messages and never raw server/transport text. Cancel/close sends
no command. A reference choice is not authority to post: existing scoped command,
idempotency, optimistic version and confirmation/recovery rules remain unchanged.
Installed authentication and native process restart remain external acceptance.

The procurement adapter normalizes all existing register, reference, supplier
statement, return-source and allocation read methods. Known permission/MFA/auth
codes remain typed read failures; other malformed/rejected/unavailable responses
use fixed `READ_INVALID`, `READ_REJECTED` or `READ_UNAVAILABLE` messages. Existing
command error precedence and encrypted retry behavior are preserved.

Controller failures and optional post-confirmation register reads bind the epoch
captured before the operation begins. An obsolete or disposed failure changes
neither public error/message nor access state in a replacement connection. A
current `PERMISSION_DENIED`, `ACCESS_DENIED`, `MFA_REQUIRED` or
`AUTHENTICATION_REQUIRED` during the optional read clears all current server
register, selected-document, source, statement and allocation evidence and retains
its fixed typed guidance. It must not be flattened into a generic refresh message.
The already confirmed command remains durably acknowledged; local canonical input
and immutable retry identities are unaffected. A non-access refresh failure may
show fixed confirmed-but-unavailable guidance only in the originating epoch.

Purchase-return disposal advances the access epoch, clears the posted register
and eligible-source rows, cursors and kind, and notifies an already visible
workspace before releasing its listeners. Exact local inputs and the original
sealed request remain encrypted for a fresh permitted controller.

Server-derived reason, supplier-selection and reversal dialogs bind the same
originating access epoch. They hide private document/supplier evidence and remove
confirmation actions after disconnect, reconnect, disposal or definite denial.
An accepted reference or confirmation rechecks that epoch after the root route
result resolves; a pop-time access change cannot create a draft or authorize a
replacement action. Existing local-only save/discard and original sealed retry
inputs remain governed by their established offline recovery contract.

Controller providers treat connectivity as verified online only when its current
asynchronous value has neither loading nor error state and contains online data.
A retained prior online value during reload or error cannot authorize server
reads, choices or commands. Initial construction and subsequent notifications
use the same rule; unverified connectivity advances the existing access epoch
and clears server evidence while preserving encrypted local inputs and original
sealed requests. A later verified online result starts fresh access and cannot
revive an obsolete dialog or read result.
