# Protected project expense evidence

Candidate source contract, 2026-10-05. FR-403–405, FR-426, FR-439–440,
EC-410/415/416 and NFR-408/409 apply. This adapter is implemented source, not an
installed storage provider, legal retention policy, authenticated native acceptance
or an owner-approved deployment.

## Scope and authority

`20261005120000_wave4_project_expense_evidence.sql` creates the separate
`expense_private` schema and private `jentra-project-expense-private` bucket.
No generic `core.files` or private HR bucket is reused. Every document binds its
tenant, entity, branch, project, expense and document UUID. A future expense UUID
may reserve a document before the expense is created; an existing expense must
match the complete scope and be draft/rejected when new content is reserved.

Normal calls require the current financial/project module, cost-view permission,
membership and scoped role authority, active branch/entity, tenant trial/active
status and current AAL2. Independent `projects.expenses.evidence.view` permission
is required for attachment metadata. Management also requires
`projects.expenses.manage`; export separately requires
`projects.expenses.evidence.export`. Retention commands require
`projects.expenses.retention.manage`. Creating, replaying, reconciling or discovering
an entity policy requires this permission across the entity, with a null branch
scope check. A branch retention manager may manage holds on that branch's
documents but cannot create an entity policy. This migration grants no business
role or plan permission.

Private base tables use forced RLS and have no client/service-role table grants.
Only bounded API functions expose client operations; owner-only helpers have no
client EXECUTE grant. Trusted worker APIs remain service-only and revalidate the
human ticket's current scope, role, entitlement and AAL2 before upload verification
or delivery. Deactivated tenant, entity or branch invalidates an already issued
ticket. Download rechecks current human authority after the storage read.

## Immutable content and financial proofs

Content accepts text/plain, image/png, image/jpeg or application/pdf, up to 10 MiB,
with exact SHA256, MIME and byte length. Client names, object paths, storage URLs
and arbitrary evidence references are not content identities. Paths are generated
from five scoped UUIDs. Storage upload never replaces an existing object; an exact
retry must verify the stored original bytes.

The immutable proof is exactly `{id, version, digest}`, with content version 1.
Its protected digest binds full business scope, checksum, MIME, length and policy.
Lifecycle `record_version` increments separately. No mutable row version is used
as a new content revision. One expense has at most ten unique documents; finance
freezes sorted minimal proofs into its immutable expense revision and digest.

The owner-only integration is
`projects.expense_evidence_assert(tenant,entity,branch,project,expense,proofs,mode)`.
It rejects unexpected fields, duplicate IDs, wrong scope/version/digest or more
than ten proofs and returns a canonical array. Modes are:

| Mode | Required source behavior |
| --- | --- |
| `freeze` | Require expense management, attachment view and cost authority; freeze current active content and current policy/worker readiness. |
| `decision` | Recheck the previously frozen proof and current attachment/cost authority; reject retired/purging/purged content and stale worker readiness. No new attachment is accepted. |
| `read` | Recheck current attachment/cost authority; retain immutable original proof through retirement/purge for financial audit. This does not authorize byte download. |

An explicit empty array remains valid for narrative-only expenses and does not
require attachment permission or a running file provider; normal finance access
still applies. Financial create/correct, decision and own-receipt replay use the
helper before confirmed replay. Correct also rechecks the original revision;
detail and own receipts reauthorize frozen proofs. Finance command request hashes
remain bound to the original raw request.

## API and trusted delivery

`projects_expense_evidence_access` returns complete scoped actor identity and
availability. Availability requires an entity policy and a verified private worker
heartbeat less than 26 hours old. Unavailable means unavailable; it does not
fabricate files or grant permission. `projects_expense_evidence_list` returns at
most 50 metadata rows in ascending UUID order with an explicit cursor.

`projects_expense_evidence_command` accepts the usual immutable command envelope
with expected version and these actions: `policy_create`, `reserve`, `complete`,
`hold`, `release_hold`, `retire`. Scope, current original-action capability and
readiness are checked before replay. `complete` requires trusted verified content,
increments the record once and becomes active. Own receipts return minimal proof,
action and scoped confirmation, excluding private purpose, checksum and paths.

The user-authenticated `expense-private-documents` Edge handler obtains a scoped,
single-use ticket (30 second issue window), streams bounded bytes, verifies upload
and storage readback, then executes the original user completion command. A
consumed upload may verify only within its short verification window. Delivery
uses a separate download or export operation, verifies original bytes and performs
a final authority check. Responses are private/no-store, nosniff, safe generic
filenames, with no signed/public URLs or raw provider errors.

The secret-authenticated `expense-private-purge` handler accepts only a bounded
probe or purge request. Probe writes, reads, hashes and removes a private test
object and requires an explicit missing-object result before worker registration.
The deployment-supplied artifact SHA256 is recorded with that probe. Purge claims
at most 50 exact document jobs with 30 minute leases; each exact generated path is
validated. Completion follows successful removal and explicit absent-object
verification. Unexpected storage errors preserve the lease for recovery.

## Retention and locking

An explicit entity policy chooses 1–3650 days and purpose. Synthetic fixtures use
30 days; this does not assert a real jurisdictional retention period. Policy IDs
are immutable. Per-document holds record a reason and review date; they require
explicit release and never automatically expire. Retiring an attachment requires
a cancelled/rejected/reversed financial source. Posted active sources cannot lose
their attachment content through ordinary retirement/purge.

Unlinked reserved uploads older than 24 hours may be cleaned up. Retired content
may be purged only after its frozen policy interval, without a hold or a related
nonterminal expense. A worker marks the document purging before external deletion;
new holds then reject rather than claim a physically disappearing object.
Expired purge leases may retry safely. Purged rows retain immutable financial
proof, checksum and audit events; download still rejects purged content.

Global locks use payroll entity, projects entity, then service entity before
document/policy/ticket locks. Finance integration obtains the same advisories
before proof checks or replay to avoid inversion. Separate-session contention
evidence remains a delivery gate; sequential rollback replay is not contention.

## Native client and encrypted recovery

`SupabaseExpenseEvidenceGateway` snapshots commands and upload bytes before any
await, checks the current actor before/after transport, rejects scope/cursor or
confirmation mismatches, and verifies delivered bytes. Typed documents contain
metadata and minimal proofs, never content URLs. The native picker reads permitted
bounded files into memory and hashes them. Export requires an explicit destination
and rechecks authority after choosing the destination and after reading bytes.

`ExpenseEvidencePanel` takes `scope`, `projectId`, `expenseId`, `repository`,
`drafts`, optional `files`, `initialProofs`, `onChanged` and `editable`. Finance
embeds it in the expense editor and original revision review. Root owns the real
gateway override in `main.dart`; no route or generic file tab is introduced.
Read-only reviewers cannot change selection. An original retired proof may be
explicitly detached during a rejected-expense correction, but cannot be newly
attached. Permission loss clears visible metadata, selection, comparisons and
byte preview; late file-picker or byte responses cannot restore disposed views.
File reads use the selected length plus a one-byte bounded stream window, reject
growth before retaining excess chunks and reject incomplete or changed snapshots.
Image decoding has an actionable failure state, and its scoped framework image
cache is evicted when the preview closes, changes or is disposed.

`SensitiveExpenseEvidenceDraftStore` reauthorizes the exact scope/capability before
decryption. AES-GCM encrypts metadata and immutable command identity before
dispatch. Bytes, filenames, URLs and export destinations are never persisted.
Private bodies have a fixed 24-hour expiry; an encrypted minimal command receipt
survives uncertain expiry. Scope namespaces include actor/tenant/entity/branch,
project/expense and capability. Entity policy recovery uses a separate null
project/expense namespace, checked before a replacement policy choice.

Retry reconciles the original own receipt first, then reuses the original sealed
envelope. An upload retry requires the exact original checksum and size. An
expired private body cannot be guessed/replaced from the minimal receipt. A
confirmed server result survives failed local cleanup. Pending outcomes cannot
be discarded or overwritten; definite rejected requests retain compared metadata
and fixed expiry before an explicit new versioned request. Closing the panel
keeps the encrypted pending identity; file choice and preview bytes remain memory
only. Real Windows Credential Manager restart acceptance remains separate.

## Review and installation boundary

Source verification includes strict BEGIN/ROLLBACK SQL with exact result/query
hashes, domain/gateway/encrypted recovery/native regressions, trusted handler tests,
pinned Deno entrypoint checks and individually inspected light/dark previews.
The current checkpoint records actual counts and failures without promoting them
to installed behavior, private storage delivery, native sign-in, legal policy,
load/contention or owner signoff.

Deployment approval must identify this migration, the two function entrypoints
and config, private bucket/policy/grant changes, artifact digest and worker secret
provisioning, reviewed retention purpose/period, actual private probe schedule,
rollback/disable procedure and expected operational cost. No persistent migration,
function deployment, secret provisioning or policy activation is implied by this
contract. Post-install verification must exercise separate attachment-view/export
authority, revoked/deactivated scope, original financial replay, physical byte
delivery and purge/hold recovery before availability is accepted.
