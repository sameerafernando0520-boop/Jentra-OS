# Wave 3 local draft storage failures — EC-340

This clarifies FR-386, FR-387, FR-395, EC-340 and NFR-313. It changes only the
local encrypted persistence failure contract; authenticated command authority,
server error precedence, cryptography, recovery identity and acceptance-owned
stock-opening behavior remain governed by their existing contracts.

Failure to encrypt, write or atomically commit a draft must return a fixed,
retryable `LOCAL_STORAGE_FULL` domain error. This required public code covers both
full and unavailable secure storage. Safe `storage` metadata distinguishes
`full` from `unavailable`; it contains no path, SQL, draft, credential, raw native
exception or key. SQLite's structured FULL result and known operating-system
disk-full codes select `full`. Other persistence failures select `unavailable`.
An existing domain validation, scope, conflict or sealed-command error is not
reclassified. JSON serialization happens before the persistence boundary, so
invalid caller data does not masquerade as disk exhaustion.

The message keeps the editor open, explains that secure local saving could not
complete and directs the user to restore storage and retry. Callers keep current
in-memory input and preserve the previously durable encrypted form and original
pending command. They must not show a save-success state, navigate away based on
a failed save, or dispatch an authoritative command after its prerequisite save
or sealing fails. A failed local completion after an already dispatched command
must preserve uncertain recovery; it must not claim the server rolled back.

Repository transactions keep the original domain failure when user work rejects;
storage write/commit failures roll back all local acknowledgement changes.
Persistence retry uses the existing exact input and original sealed identity,
without replacing an encryption key, changing scope or inventing a new command.

Quotation and sales-order autosave retain the classified `LOCAL_STORAGE_FULL`
error in the current editor instead of replacing it with a generic autosave
failure. Their unsaved-edit and failed-edit navigation gates remain active. A
subsequent attempt to leave may display the existing explicit save/discard
guidance; it does not clear the in-memory fields, silently open another aggregate
or send a command. Retrying after storage recovery uses those exact fields.
Unclassified caller errors retain their existing `DRAFT_SAVE_FAILED` behavior.

Verification includes real synthetic SQLite capacity rejection, credential-key
failure, atomic acknowledgement rollback, unchanged validation/conflict errors
and redaction. Synthetic in-memory/file tests do not establish native disk-full,
Credential Manager, process restart or installed acceptance. No acceptance store,
Credential Manager setting or acceptance-owned executable is changed.
