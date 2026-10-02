# Procurement reference access during scope changes

This clarifies FR-349, FR-384, FR-395, AC-322 and NFR-313 for existing
requisition, sourcing, order, receipt, bill, payment and product-unit reference
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
