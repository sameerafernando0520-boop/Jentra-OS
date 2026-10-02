# Operational reports, source navigation, dashboard and files

Additive candidate development under FR-312, FR-334, FR-349, FR-366,
FR-377, FR-382–394 and AC-320–324. No installation or authentication change.

`api.wave3_document_page` accepts explicit tenant/entity/working branch,
allowlisted aggregate kind, literal search, status, inclusive date range and UUID
cursor. It returns 50 deterministically ordered current records, generation time,
exact decimal strings and the exact filter/scope identity. Current lists explicitly
declare `basis=current`; they cannot answer historical report requests. Known
IDs and links recheck the aggregate's read permission in its actual branch.
Stock/cost sources additionally require current inventory and cost permission.
Unknown/foreign/forbidden identities return the same unavailable state.
Landed extensions and disposition sources join this allowlist. Multi-branch value
documents require every recorded leg/destination branch's current stock, cost and
valuation access on lists, source detail, files and frozen-report reopen.

`api.wave3_document_evidence` supplies one source header, a bounded 50-row child
page, immutable command/audit lineage, separately permitted related sources and
private attachment metadata. Every nested read shares a statement snapshot.
For a landed-value adjustment, the goods-receipt contextual link is resolved
from its recorded receipt movement line through the same-tenant movement and
goods-receipt keys. The client never treats a movement-line ID as a document ID.
Source identities do not authorize a different source or a file. Every contextual
link binds tenant/entity/branch, restores only an already permitted context and
fails without reading when the context is unavailable. Authentication is unchanged.
Context restoration first resolves the target tenant, entity and branch from the
authenticated scope catalogue, then changes the selected context once. An unknown
or forbidden target leaves the prior selection intact and has the same unavailable
screen as a forbidden document. Source and cost permission are rechecked after
restoration; URL fields are never treated as authority.
An obsolete or disposed destination cancels restoration before any selection
change. Notification rows offer a source action only for a complete allowlisted
source/scope identity, through this same checked route.
The command palette accepts only a complete relative operational document URL
with one UUID each for tenant, entity, branch and document, plus an allowlisted
kind. It opens through the same restoration and source-access path and performs
no record lookup or data disclosure while parsing the pasted link.

`api.generate_operational_report` freezes a complete filtered current list or a
customer/supplier dated statement or dated bank reconciliation into a private,
immutable report. It uses existing statements/bank/close builders and original
posted truth; it never labels a current list as historical. At most 10,000 rows,
8 MiB evidence and 50-row pages; oversized reports fail atomically. All amounts
remain decimal strings. Metadata records scope, filters, currency meaning, cutoff,
source generation time and lineage. Governed export contract 44 adds source type
`operational`; it reuses exact CSV/XLSX encoding, export jobs and sealed recovery.
The desktop offers a save/export action beside the authoritative live customer
and supplier statements and the bank reconciliation workspace. The frozen
request is sealed before transmission, replays the same command after uncertain
outcomes, verifies saved report scope and kind before showing a link, and clears
visible report metadata on disconnect or access revocation. A pending request
cannot be silently replaced by a changed statement selection.

Current-list filters include literal search, status and inclusive document-date
range. They are saved as view state in the existing encrypted local store, scoped
to actor, tenant, entity, branch and document kind. A pending report freezes its
own filter snapshot. Saved view state carries no source rows and cannot authorize
a later read; reopening always rechecks the server. Invalid dates, reverse ranges
and unsupported statuses fail visibly. The current-list report action consumes
the selected filter snapshot, never a stale screen result.

`api.wave3_dashboard` returns only currently permitted, scoped actionable queues
for pipeline, quotations, orders, fulfillment, procurement, inventory, AR/AP,
cash/bank, close and budgets. Counts are explicit current-state counts; dated
financial metrics reuse their authoritative report basis. No sample metric is
presented as live truth. Each card carries its timestamp, scope and destination.
Denial/disconnect/stale refresh clears prior server evidence.
The dashboard adds dated currency-separated pipeline and AR/AP aging summaries,
branch cash/bank controls, current period/budget states and scoped exceptions.
AR/AP summaries reuse immutable dated residual arithmetic, including unapplied
credits in a separate bucket, and reject more than 10,000 source items per kind.
Cash/bank metrics reuse the authoritative branch controls builder. Saved close
and budget review summaries carry their original cutoff/generation timestamp and
are explicitly labelled saved evidence. Current period/budget states carry the
current statement timestamp; they never imply that an old review is current.
Metrics are individually gated by all underlying permissions, tenant/entity/branch
filters and bounded output. Every metric includes its scope, basis and destination.
Any input/output bound failure is explicit; no partial metric is silently returned.

Wave 2 attachment allowlisting extends to these Wave 3 aggregate kinds. Registration,
completion, metadata reads and private Storage reads all require current underlying
aggregate access as well as file permission. Storage objects are immutable after
creation; ready files on posted sources cannot be replaced/deleted. A privileged,
reasoned rejection appends an audit record and makes the file unavailable. Uploads
retain existing bounded MIME/size/checksum policy and sealed command identities;
file bytes and signed URLs are never cached in a command draft. Failed upload does
not imply ready metadata, and replay never starts an unrelated upload.

Private-link and file-rejection dialogs bind the originating controller and its
verified read epoch, including root-navigator dialogs. Disconnect, disposed or
replaced scope, denied access and a fresh document read hide an already displayed
signed URL and reject late link/file-picker replies. Reconnecting cannot revive
the obsolete dialog. A current definite permission/MFA/authentication denial clears
document/file evidence; stale failures cannot relabel a replacement scope. A new
verified read is required before opening a new file action. These presentation
guards do not rewrite sealed uploads/rejections or cancel confirmed commands.
The private-link adapter classifies Storage HTTP 401 and 403 as current
authentication and permission denials. Rejected, malformed and unknown transport
responses use fixed public read errors without exposing raw Storage diagnostics.

Wave 3 in-app notification subscriptions are private tenant/entity/branch
configuration. Only an authenticated scope administrator may enable or disable
one for an active member through a versioned, idempotent command. Administrators
may disable an existing subscription after its member is suspended. Source and
inventory-cost permissions are checked at fan-out as well as source opening.
Posting never
depends on an external delivery worker. A successful Wave 3 outbox event creates
at most one generic in-app notice per subscribed recipient, command and event
class; suspended members receive none. Notification metadata carries the original
scope and correlation without copying financial values or private source text.
Opening its source always repeats document permission checks. Time-based due
events require a separate bounded scan and must not be represented as covered
by outbox classification alone.

`api.scan_wave3_due_notifications` is an authenticated, idempotent administrative
command for one permitted AR/AP scope and explicit cutoff. It examines at most
100 due positive open items in UUID order, reports examined/emitted counts and
an explicit continuation cursor, and computes dated residuals from immutable
allocation history. It never changes open items. Settled items and credits emit
no due notice. Only configured active recipients with current source permission
receive a generic notice, once per recipient/source/cutoff even across repeated
scans. A failed scan rolls back its notices, audit, outbox and receipt together.
The scan must be invoked by an authorized worker or administrator; scheduling
and installed worker acceptance remain separate gates.
The desktop administrator workspace offers scoped, bounded recipient and
subscription pages, versioned enable/disable actions and an explicit dated AR/AP
scan. It seals each command in existing encrypted recovery before transmission.
Unknown results lock edits and retry the original envelope; a scan advances its
cursor only after a verified receipt. No background schedule is implied.
`api.wave3_notification_admin_page` accepts `members` or `subscriptions` and an
optional UUID cursor, returns at most 50 rows plus continuation and requires
current `core.roles.manage` for the selected operational scope. It exposes no
private HR or credential fields.

Installation, private Storage/native file-dialog verification, keyboard QA,
Credential Manager process restart, target-scale p95 and owner signoff are separate.

Procurement requisitions, sourcing, orders, product-unit masters, receipts,
supplier bills/payments/returns, reservation and transfer
registers clear current server pages and selected financial evidence when access
or connection changes. Responses from an earlier connection cannot restore them.
Encrypted inputs and original uncertain command envelopes remain recoverable;
confirmed commands are acknowledged even if their source workspace disconnects.
An access rejection blocks mutation until a fresh permitted read succeeds.

Bank, requisition, sourcing, order, receipt, bill, payment, return and product-unit
commands bind the originating access epoch before asynchronous encrypted save and
sealing. Immediately before transmission they recheck that same epoch, online
state and current access. Disconnect followed by reconnect cannot transmit the
obsolete operation; the original sealed request remains recoverable for a fresh
permitted retry. Stale read or command failures cannot replace current error/access
presentation. Already dispatched confirmations remain durable before optional reads.

Attachment and private Storage RLS policies use authenticated read-only helpers
`core.wave3_attachment_access` and `core.wave3_storage_access`. They return only a
boolean after checking current membership, aggregate permission and every required
cost scope. `core.wave3_source_descriptor` returns the constant aggregate
allowlist, without tenant records. These policy helpers grant no mutation ability;
command, posting, allocation and correction helpers remain inaccessible to desktop
roles. No helper has PUBLIC or anonymous execution permission.

Private attachment signed-link reads normalize actual Storage session and scope
rejections to `AUTHENTICATION_REQUIRED` or `PERMISSION_DENIED`. Invalid/missing
objects and malformed responses show fixed read-rejected/invalid messages;
transport failures show a fixed unavailable message. No raw Storage diagnostics,
private object path or token is displayed in an error. An open link and any late
reply remain subject to the controller's current read-access epoch.
