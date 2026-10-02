# Inventory value corrections, partitions, disposition and reservation lifecycle

Additive candidate development for FR-354–361, EC-324/326–327 and AC-314/315.
Receipt provenance remains quantity attribution, independent of pooled moving
average. Original movements and journals are immutable.

Transfer, stock count and disposition transmission rechecks the originating scope/access epoch after asynchronous
encrypted save and sealing, immediately before dispatch. Disconnect, access
denial, reconnect or disposal during sealing leaves the original request locally
recoverable and sends no command from the obsolete workspace. A fresh permitted
workspace may retry that same envelope after current access verification.

The same transmission boundary applies to reservation release and both single-
and multi-receipt landed-value commands. The originating epoch is captured before
save/sealing; a later epoch cannot become the authority for the old operation.
Reservation reads clear evidence on definite permission/MFA/authentication denial,
and obsolete read failures cannot revoke a replacement connection. Confirmed
releases retain input-only recovery and original document/version identity.

Landed charges accept a bounded set of covered receipt lines with an explicit
quantity, original value or manually supplied positive exact weight basis. Cumulative
six-place rounding assigns the exact remainder deterministically. The server freezes
and hashes all receipt/provenance/valuation versions before posting through existing
sorted warehouse/product locks and journal engine. Receipt lines without supported
coverage or wholly consumed eligibility are rejected as required by EC-327.
Held inventory, explicit transit and consumed variance remain distinct. A reasoned
later correction uses the same immutable receipt attribution at its new posting
time and posts only the incremental value to current held/transit inventory and
consumed variance. It never fabricates original carrying-cost provenance, changes
historical quantities or destructively reverses consumed stock.
`api.preview_landed_extension` freezes/hashes one scoped bounded receipt set using
`quantity`, `original_value` or positive exact `manual` weights.
Preview and saved evidence bind tenant/entity/branch explicitly. The client
checks these identities and every requested manual weight before accepting a preview.
`api.post_landed_extension` consumes that preview through the standard command
envelope. New allocations use expected version zero; linked `correction_of`
commands use expected version one and a new nonnegative target total, retain the
original weights/accounts/receipt identities and post only the incremental delta.
A correction cannot fork an already corrected predecessor. Transit supplements
are immutable and settle exactly on transfer receive/reverse; dated valuation and
control readers include their original posting dates without rewriting transfers.

Counts larger than 500 tracked identities are partitioned into separate bounded
count documents sharing an immutable cutoff and partition group. An identity occurs
in exactly one partition. Independent approval/posting preserves each partition's
source/version and does not imply atomic posting of an unbounded group. Missing or
duplicate partitions are explicit; no identity or total is silently omitted.
`api.capture_stock_count_partitions` accepts a versioned scoped command with group
ID, warehouse/product, date, reason and offset account. It freezes at most 10,000
identities under the existing warehouse/product locks, with 500 identities per
document, one shared cutoff and a unique identity manifest. Larger groups fail
explicitly. `api.stock_count_partitions_page` returns at most 50 bounded documents
with expected, captured, posted, cancelled and missing counts and separate capture
and posting completeness. Ordinary count upsert cannot supply invented partition
metadata; legitimate partition edits retain their frozen identity and cutoff.
An unsubmitted count has no workflow snapshot. Cancelling it resolves the active
configured lifecycle; a JSON null is treated as absent. Submitted and approved
counts retain their frozen workflow snapshot.
Count and reservation workspaces clear current register/report/partition evidence
on disconnect or access denial and ignore replies from an earlier connection.
Confirmed count commands persist their returned document atomically with the
encrypted acknowledgement; pending requests retain their exact retry identity.

Permitted disposition consumes selected held lot/serial or untracked quantities,
including expired lot stock, at the pre-issue pooled carrying cost and posts an
exact inventory/variance journal. It requires reason, configured approval/MFA,
live scope and available quantity. Stock/reservation/tracking/provenance/journal,
audit, receipt and outbox are atomic. Normal saleable delivery still rejects expired
stock; disposed serials never become available in another location. Corrections
are linked immutable documents and never rewrite disposition history.
The candidate adds the separately privileged `inventory.dispositions.post`
capability. `api.upsert_stock_disposition`, `api.transition_stock_disposition` and
`api.post_stock_disposition` use standard scoped/versioned command envelopes and
the configured `inventory_disposition` workflow. Detail/register reads require
current source and cost access. Lines bind product, warehouse, exact quantity,
lot and serial identities. Linked additional corrections consume only currently
available stock. Reversals of lot/untracked dispositions restore the original
value/provenance only while compatible later stock history permits; serial
physical restoration is denied so a disposed serial cannot be reissued.
Disposition register and picker replies echo their tenant/entity/branch. Clients
validate that scope, bounded unique identities, exact value strings, version and
command identity before treating a response as confirmed. Loss of permission
clears visible server evidence while preserving encrypted local work; an older
in-flight read cannot repopulate a disconnected or replaced workspace. A confirmed
command is saved securely even when its workspace disconnects before the reply.
Draft cancellation resolves the configured lifecycle when no workflow snapshot
exists, including a JSON null snapshot.
Posted landed allocations and dispositions expose permitted source-document and
journal links using their original scope. Journal links require finance access;
operational links require every source and inventory-cost capability.

Expiry, cancellation, delivery, reversal, product retirement and explicit release
use the existing reservation history and exact remaining demand. Lifecycle commands
release their affected reservations atomically. A bounded permitted maintenance
command processes expired/retired holdings with explicit continuation; it never
changes posted stock or claims unbounded scheduled/background work.
`api.maintain_stock_reservations` accepts one mode (`expired` or `retired`),
reason, a 1–50 limit and a two-part order/reservation cursor. It processes the
page in sales-order then reservation order through the existing governed release
command, with one outer receipt and the existing per-reservation history. A
conflict aborts the entire page; retries replay the same outer receipt. The
returned cursor identifies the last processed identity, and `has_more` is
explicit. Sales-order cancellation and delivery already release or fulfil their
reservations within their posting transaction; the maintenance command handles
only remaining expired or retired holdings.

All candidates require strict synthetic rollback tests and compatibility review.

Transfer, count and disposition reference/serial dialogs bind their originating
controller and read-access epoch, including root-navigator dialogs. Disconnect,
disposal and definite permission/MFA/authentication denial hide cached choices
and reject late results. Reconnect never revives an obsolete selector; a new
scoped read is required. Current read denials clear server evidence while
retaining encrypted inputs and original sealed command identity. Read adapters
preserve known authentication failure states without changing command error
precedence. Fixed public read errors contain no raw transport/server diagnostics.

Count and disposition recovery stores retain document identity, version, cutoff,
tracking identities and exact user inputs, while omitting server monetary previews
and posted value evidence. Restoring an older encrypted envelope strips those read
values from presentation. Disconnect and definite access denial clear in-memory
cost previews; reconnect does not revive them. A permitted explicit detail reload
refreshes an unchanged saved document, never overwriting dirty inputs or a sealed
pending command. Confirming the original command atomically acknowledges its
receipt with the input-only recovery form even after disconnect/disposal. Live
scoped replies may supply the visible exact preview; historical values are never
recomputed or invented by the client.

The original single-receipt landed-value workspace likewise stores exact draft
inputs and linked reversal identity only; allocation previews and posted documents
are live scoped reads, never recovery payloads. Its options, preview and posting
presentation bind the originating access epoch. Confirmed posting completes the
original sealed command before optional reads even after access loss. Transfer
receive/reversal recovery omits copied server money, movement and event evidence
while retaining the selected transfer identity/version and exact editable inputs.
The multi-receipt workspace also clears previews/registers on definite permission,
MFA or authentication denial. Replies and failures from an obsolete read epoch
cannot lock a replacement connection or restore earlier cost evidence.
Single-receipt posting confirmations bind the originating read epoch and hide
their preview on disconnect, disposal or access denial. A restored linked reversal
shows its original allocation identity and reason without inventing a cached amount.

Reservation release recovery retains only reservation identity, original version,
status and the exact editable release reason/mode. Current product/warehouse
labels, quantity and expiry are scoped read evidence, omitted from new encrypted
drafts and stripped from legacy draft presentation. Disconnect, disposal and
definite access denial clear that evidence without replacing a sealed request.
Known release confirmation atomically stores its minimal acknowledgement before
optional queue refresh; an obsolete refresh failure cannot annotate a replacement
connection, and a current typed denial clears evidence after confirmation.
Opening a reservation requires its identity/version in the current scoped queue;
copied row labels never replace current evidence. Release confirmations bind the
originating read epoch, hide after access loss and cannot dispatch from an obsolete
dialog. Restored input-only confirmations identify the saved reservation/version
and release inputs without inventing quantity, product labels or expiry.

Installation, genuine native recovery, concurrent target-load and owner signoff
remain separate acceptance gates.
