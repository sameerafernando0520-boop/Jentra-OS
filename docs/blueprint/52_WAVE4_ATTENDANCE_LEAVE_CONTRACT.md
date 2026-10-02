# W4-03 attendance, common work intervals and leave

2026-09-28. Synthetic development contract. Parent:
[Wave 4 specification](40_WAVE4_WORKFORCE_AND_DELIVERY_SPEC.md), FR-413–416,
AC-405–406, EC-405–409/411. Existing employee and calendar migrations are
immutable. The organization/instant-resolution candidates remain uninstalled;
attendance cannot become authoritative until their exact versions are present.

## Ownership and time

All work uses UTC instants at whole-second precision and half-open `[start,end)`
intervals. Local service dates and a published calendar version/zone are frozen
evidence, never the duration calculation. If an operator enters civil times, each
boundary is resolved against that exact calendar version; a gap is rejected, and
a fold requires a selected offset. An overnight interval may have a different
offset at each end. `end_utc-start_utc-sum(break seconds)` is the payable duration;
negative/zero or more than 36-hour spans are rejected. Breaks are contained,
ordered, disjoint, and excluded once. No decimal hour is stored.

There is one common, scoped claim for each approved payable work interval.
`attendance`, `project` and `service` are source kinds, not three independent
payroll facts. Active payable claims for the same employee cannot overlap,
including across branches and source kinds. Project and service allocation of an
attendance interval instead references an approved claim and records disjoint
subintervals; it does not add payable seconds. If there is no attendance claim,
project/service may propose a standalone claim, which must pass the same approval
and overlap gate. Any attempted duplicate allocation is rejected. Leave excludes
the approved payable span, and approved leave blocks overlapping payable claims.
Claims, allocations and approved leave lock the employee row first, then their
own aggregate rows. The database exclusion constraint remains the final arbiter
under concurrent transactions. Multiple source commands cannot create the same
payable fact by racing. An authorized correction revokes the old active claim and
creates a linked replacement, never edits the original evidence; a payroll seal
blocks in-place replacement and requires a linked later-period difference.

## Attendance

Raw clock events retain external source system, immutable source key, device or
manual origin, observed timestamp, imported timestamp and scope-bound checksum. Import
uniqueness is `(tenant,source_system,source_key)`, with a mismatched retry rejected.
There is no synthetic guess that two close timestamps are the same event.

An attendance entry has scoped employee and branch, paired UTC instants, exact
breaks, selected calendar version, local boundary/offset evidence, state, version
and immutable revisions. The operator may prepare a manual pair or propose a pair
from named raw events; the chosen raw IDs remain attached. A correction creates a
new revision with reason and superseded revision ID. Submission freezes a
revision for an independent decision. The approver must have a separate
`people.attendance.approve` capability and cannot be the submitter or revision
author. Rejection preserves facts without a payable claim. Approval checks active
employment/branch/calendar coverage at the service date, all overlaps and leave
conflicts, then creates the common claim and immutable decision event atomically.
Cancellation or correction reverses only that entry's current claim. Previously
approved facts remain queryable as history. Raw events are never deleted.

Lists and history use exact scope plus keyset pages (default 50, hard maximum
200), literal search, and no private HR fields. Named APIs return explicit
loading/empty/denied/unavailable states to the native client. Import batches are
bounded and validate the whole batch atomically. Generic audit/outbox contains
IDs, state, seconds and source category, never private HR content.

## Leave policy and entitlement

A versioned policy defines code, effective half-open dates, eligibility by
employment type, `hours` or `days`, day length in integer seconds if days,
accrual frequency (`monthly` or `once`), exact accrual seconds, carry cap seconds,
grant expiry rule, permitted negative balance (zero in this slice), and whether
unpaid leave may be requested. Units are converted to integer seconds when the
version is published and then frozen. Synthetic values are explicitly chosen by
the test owner; no statutory or contractual rate is inferred.

Each accrual period is idempotently keyed by employee, policy version and period.
A grant is an immutable credit with source, policy version, effective date and
expiry; duplicate accrual/adjustment source IDs are rejected. Balances are derived
from append-only effects grouped by grant. A reasoned adjustment adds a new
effect. Carry-forward at the boundary freezes a source-period balance, caps it
according to the published version, and creates a linked next-period grant once;
expiry affects availability, not historical balance. Readers can request an
as-of projection that states both effective and recorded cutoffs.

A leave request names employee, branch, policy version, `[start_utc,end_utc)`,
local/calendar evidence, exact charge seconds and reason. Each request occupies
one published working slot of at most 36 elapsed hours. A multi-day absence uses
one linked request per working slot, so nights/nonworking spans remain available.
An hours policy charges exact UTC seconds inside that slot. A days policy requires
the whole slot and charges its configured nominal day seconds; an ambiguous slot
boundary must have an explicit offset. A nonworking override rejects the slot.
Submission reserves no
entitlement. Independent decision requires `people.leave.approve`, MFA and a
different actor from request/last revision. Under the employee lock it checks
employment and calendar coverage, current policy eligibility, no conflicting
approved work/leave, then consumes available grants in deterministic expiry/date/
ID order. Each debit names its grant and exact request ID. Insufficient balance
rejects without partial ledger effects. A rejected request has no debit.
Cancellation requires a reason and appends exact positive reversal effects, one
per original debit, with unique `reversal_of` references. It cannot credit a
different grant or repeat a reversal. Expired restored grants remain expired.
Historical requests/decisions/effects cannot be rewritten or deleted.

An attendance/leave conflict requires an explicit correction or cancellation
first; neither command silently modifies the other module. Pending requests may
be resubmitted after a conflict. Scope or role loss is checked before replay and
before any balance/private reason read.

## Payroll consumption and recovery

Payroll input seals reference exact approved attendance revision/claim IDs and
leave request/effect IDs, source versions, seconds, policy/calendar IDs and a
digest. Seal creation locks the employee and facts, is idempotent per run/source,
and denies stale or unapproved sources. Corrections after a seal leave the frozen
record intact and create an attributable delta for an eligible later run. There
is no retroactive overwrite of a posted run. W4-04 must consume only these
explicit sealed projections and reject missing providers.

Every named command uses current People entitlement, member/scope/capability,
MFA for privileged transitions, expected version, client timestamp, exact payload
allowlist, actor-scoped idempotency, and atomic receipt/audit/outbox. The native
client encrypts draft and uncertain exact requests by actor/tenant/entity/branch/
aggregate. Retry rechecks access; a conflict requires comparison and explicit
replacement. Confirmed writes survive an optional subsequent read failure.
Sign-out, scope/capability loss and late responses clear/discard visible data.

The native source-event adapter computes a SHA-256 checksum bound to the actor's
tenant/entity/branch, employee, source system/key and strict UTC instant. The
checksum is invalidated when source fields change. The bounded CSV adapter uses
the exact `source_key,observed_utc` header and at most 200 records/64 KiB UTF-8.
It supports quoted CSV fields but rejects duplicate keys, extra columns, control
characters, untrimmed references, normalized dates and noncanonical UTC instants.
The selected scoped employee and explicitly named source system apply to every
row; no email/name matching chooses an employee. Preview precedes an explicit
submission. Source import records raw evidence only and creates no attendance,
approval, common payable claim, leave effect or payroll entitlement.

Batch checksum version 1 is SHA-256 over UTF-8 newline-separated tenant/entity/
branch/employee UUIDs, source system, exact source key and canonical UTC instant.
Its manifest is SHA-256 over `w4-clock-batch-v1`, those four UUIDs, source system
and row checksums in file order, again newline-separated. UUIDs are lowercase;
fields containing newlines/control characters are invalid. The server recomputes
both hashes. It stores immutable batch/row lineage and commits all new rows,
exact duplicate reuse, minimal receipt, redacted audit and outbox atomically.
A previously imported tenant/source-system/key is reusable only when its scoped
employee, UTC instant and checksum match exactly. Changed duplicates reject the
whole batch without exposing another scope. Exact uncertain retries retain the
original batch/event IDs, hashes and request in the encrypted operational store.
Only counts and a manifest digest enter the generic receipt/audit/outbox; file
paths/content and clock keys do not. Replay rechecks import authority and MFA.
Policy directory rows contain only the latest version; immutable policy history,
grant sources and attendance/leave history use 50-row keyset pages. Payroll
calculation fields are excluded from these operational APIs.

Leave reasons are private. Encrypted local body recovery expires within 24
hours, is authorized before/after decryption, and retains only minimal sealed
receipt metadata for an uncertain expired request. Native expiry is checked
before edits/saves/submission as well as by the access monitor. Receipt lookup
rechecks the current actor, original action capability and employee scope and
returns no private reason. Draft recovery cannot fabricate approval or extend an
expired in-memory body into a new saved request.

## Verification and installation

Rollback candidate tests must cover cross-tenant/branch reads, direct table
denial, revoked replay, duplicate raw source with changed checksum, DST gap/fold,
overnight/break exactness, competing approval, active work/leave overlap, policy
version/expiry/carry, two-source simultaneous leave decisions, insufficient
balance, original-grant reversal, sealed late correction, injected receipt/audit
failure and no persistent rollback fixtures. Real concurrent connections and
measured load remain separate from single-session SQL assertions. Client tests
cover allowlisted responses, exact integer seconds, encrypted restart, uncertain
retry, late access loss and native reachable layouts at 1024–1920 widths/200%
text in light and dark. Installation needs a concrete review and specific owner
approval; candidate checks alone do not establish installed or authenticated
behavior.
