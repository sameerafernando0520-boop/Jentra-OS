# Wave 3 request observability

This additive client contract implements NFR-316 without changing command
authority, authentication settings, database grants, retry behavior or receipts.

Only allowlisted Wave 3 RPCs in the `api` profile are observed.
Generated named delivery, invoice, receipt and return RPCs are included alongside
their explicitly declared counterparts. Scoped queue depth includes CRM,
receivables/payables allocation and correction, inventory, financial reports,
bank actions, period governance and notification administration event families.
An event contains the operation name, UTC completion time, total elapsed microseconds, HTTP status,
outcome, command/request/correlation UUIDs and tenant/entity/branch UUIDs when
present. A command UUID provides the local correlation fallback until the server
returns its authoritative correlation UUID. Server structured outcomes may add
nonnegative integer reconciliation-gap or close-blocker counts. Existing frozen
reports remain the authority for amounts and source details.

Only fixed approved conflict, access, stock and period codes are logged. Request
payloads, response payloads, arbitrary exception/error messages, query text, actor
names, contact details, bank credentials, headers, tokens and attachment bytes
are excluded. Auth, Storage, stock-opening and Wave 4 requests pass through
unobserved. Logging cannot cause a successful request to fail, consume its response
twice, change response bytes, retry a command or turn uncertain transport failure
into confirmed rejection. Response metadata inspection is capped at 64 KiB;
larger responses still emit latency/status without copying full report contents.

The default sink emits structured local diagnostic events. It makes no remote
telemetry request and persists no business payload. Configured diagnostic sinks
receive only the typed allowlisted event. Dead-letter depth is read from the
existing server outbox by joining immutable command receipts for the requested
tenant/entity/branch. Only `core.roles.manage` in that current scope may read the
count; event payloads, errors and actor identities are never exposed. The read
has a 10,000-row diagnostic bound and rejects excess work with `LIMIT_EXCEEDED`,
never a silently partial count. This adds a tenant/status/command partial index
and an authenticated, read-only RPC in an unapplied additive migration.
Tests must exercise redaction, correlation,
conflict/stock denial, response streaming, oversized responses, sink failure,
transport uncertainty and server queue counts. These tests are not installed/native
observability or load acceptance.
