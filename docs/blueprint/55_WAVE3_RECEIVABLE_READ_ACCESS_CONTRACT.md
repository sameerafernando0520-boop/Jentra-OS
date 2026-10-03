# Receivable statement and source read access

This contract clarifies FR-334, FR-386–FR-388, FR-395 and NFR-313 for the existing
receivable register, customer statement, source/reference and allocation dialogs.
It adds no historical corrections, valuation provenance or new posting commands.

Disconnect, disposed business scope and definite authentication/capability denial
clear current server-derived document/register, statement and picker evidence.
Late responses from a prior read access epoch cannot restore it. A reconnect does
not automatically revive the cleared evidence: a fresh scoped read must succeed.
Encrypted canonical draft inputs and sealed retry requests remain recoverable.
Provider entry and connection notifications require a successful, settled online
state. Loading or failed states retaining a previous online value invalidate the
current read epoch and cannot enable server reads or commands. A fresh settled
online state establishes a new epoch; it does not revive earlier dialog evidence.

Receivable command dispatch binds the originating read-access epoch before any
encrypted save or sealing and rechecks it immediately before transmission. A
disconnect/reconnect or replaced scope leaves the original request recoverable
without sending from the obsolete workspace. A command failure is still recorded
against its original request, but a late denial cannot revoke a replacement epoch
or restore earlier error/evidence presentation.
Opening an old register selection offline may recover its encrypted draft by ID;
it must not present the old server document as current authoritative evidence.

Root-navigator dialogs bind the controller and read access epoch. Offline or changed
scope hides their cached source amounts, allocations and reference choices, prevents
selection/mutation and permits closing. A late picker/source result must not open
or populate a dialog in a changed context. Current-scope statement reads and their
optional allocation pages enforce the same boundary. Distinct, fixed public error
states must not print raw transport/server exceptions.

The desktop adapter normalizes read failures to `PERMISSION_DENIED`, `MFA_REQUIRED`,
`AUTHENTICATION_REQUIRED`, `ACCESS_DENIED`, `READ_REJECTED`, `READ_INVALID` or
`READ_UNAVAILABLE`, preserving existing local scope/reference failures. These are
client read states, not new database command outcomes. SQLSTATE permission denial
and known authentication failures invalidate current read evidence; malformed
results and unknown transport errors use fixed public messages.
Document lookup uses a scoped query bounded to two rows, preserving the server's
permission/authentication error classification. Zero rows retains `NOT_FOUND`;
multiple rows or an invalid document is rejected rather than silently selected.

Command receipts remain authoritative. If an already dispatched command confirms
while offline, original recovery is resolved durably, but its returned document and
optional register read are not presented until a fresh permitted read. No confirmed
command is resent to reconstruct presentation. After durable confirmation, optional
register failures bind the originating read epoch: obsolete failures cannot change
the replacement connection's message or error, and current permission/MFA/authentication
denials hide the confirmed document and register while retaining the acknowledged
request and fixed public access guidance. They never create a new pending command.
Installed/native and real access
revocation verification remain separate acceptance gates.
# Root-dialog result continuation — 2026-10-03

An AR root dialog captures its originating controller's read-access epoch before
opening. It checks that same epoch and the originating context after the dialog
returns, before returning a reason, selected reference, recovery slot or discard
confirmation. A pop followed by disconnect/reconnect, access denial or disposal
cannot authorize a continuation in a replacement epoch. An unchanged permitted
epoch returns the original choice. Existing encrypted draft and original-command
recovery rules are unchanged.

