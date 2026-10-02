# W4-06 synthetic service delivery contract

Prepared 2026-10-01. This is an additive development candidate, with installation
and authenticated acceptance remaining separate gates. It implements FR-429–434
and automated AC-413–415 evidence. No existing plan or role receives a grant.

Service owns equipment, immutable coverage and SLA policies, tickets, attributable
SLA clocks, work orders, dispatch bookings, approved labor and preventive maintenance
occurrences. Every aggregate carries tenant, entity and accountable branch. Named
APIs recheck membership, module entitlement, action permission and MFA before replay.
Independent approval and closure use different actors from preparation/completion.
Commands use exact expected versions and actor-bound immutable receipts. Required
audit and outbox insertion is atomic with business state; generic telemetry contains
only identifiers, versions and state, never contact, customer evidence or cost.

Equipment has an explicit serial/identity and kind: customer equipment, internal
asset or stock identity. Customer equipment belongs to an active customer party.
Optional contact must belong to that party. Coverage versions retain inclusive
start/exclusive end, equipment, customer, contract/warranty classification and
evidence reference. Ticket classification, contact, owner, priority and resolution
history are immutable events. Asset and stock linking require an installed scoped
provider; identity registration never capitalizes or changes stock value.

SLA policies freeze a published calendar version, a bounded date horizon (at most
366 days), response and resolution budgets in whole seconds, and UTC working slots.
Slots are derived from immutable civil patterns/holiday overrides. IANA boundaries
round-trip through the existing resolver. Clock folds require explicit offset
choices and clock gaps are rejected. No implicit offset is accepted. The algorithm
counts half-open working windows, excludes paused intervals, and calculates due
instants from exact remaining budgets. Pause/resume and reprioritization retain
original clocks and monotonically retained earlier breaches. Reprioritization
uses total elapsed active work, not a fresh unearned budget. Response freezes on
first accepted work order; resolution freezes at completed work. Calendar changes
cannot rewrite policy or earlier due evidence. Evaluation is explicit and bounded;
there is no activated scheduler.

Dispatch requires an eligible employee and frozen calendar assignment covering the
entire planned interval. Employee locks precede ticket/order locks, then dispatch
and common time rows. A GiST exclusion constraint prevents overlapping active
dispatch bookings across modules' service orders. Labor is a separate exact UTC
interval with at most 16 ordered breaks and a 36-hour maximum. Approval either
allocates an existing approved claim segment or creates a service claim with
non-break segments; service/project allocations share the existing exclusion
contract. Payroll-paid seconds are never created twice. Costs use explicit frozen
synthetic hourly rates, independently from private payroll; internal cost has a
separate permission. Claimed time is immutable. Cancellation revokes only the
original allocation/claim and rejects sealed or billed impact rather than erasing
history. Off-cycle sealed corrections require the payroll correction provider.

Work orders progress through dispatched, accepted, working, completed and closed,
with cancelled terminal history. Completion records attributable resolution.
Customer confirmation is distinct from payment/invoice; a reasoned exception is
required without confirmation. A configured independent closer must differ from
the completer. Open bookings/labor decisions and unresolved source consumption
block closure. Completed labor stays billing-eligible, not invoiced or paid.

Fresh installed inventory contracts have only stock opening and sales-specific
reservation/issue/return semantics. They do not support a truthful service work
order provenance. Service part commands therefore return an explicit provider
unavailable result before a business mutation. The adapter boundary retains
reservation/issue/return identities and original cost basis when such an installed
provider exists; installing another task's Wave 3 candidates is forbidden. Sales
posting exists, but service source consumption needs the reviewed projects billing
intent adapter. Eligible labor retains original whole seconds and exact frozen
rate/currency; adapters must consume one immutable unit once and atomically. No
standalone invoiced flag or fabricated journal is accepted.

Maintenance plans freeze equipment, policy, calendar or meter basis, interval and
original next threshold/date. Readings use unsigned integer units up to the safe
integer bound. Normal readings cannot decrease. Reset/rollover events retain old
and new raw readings, exact added units, explicit maximum for rollover and reason.
Logical cumulative totals never decrease. An occurrence key is plan/version plus
the original date or logical meter threshold; a unique key protects retries. Each
generation transaction creates one ticket and one work order, then advances only
its original threshold. Deferral retains original due identity and a later eligible
date; retries reuse that occurrence. Equipment/maintenance linking does not imply
capitalization or disposal authority.

Reads page by immutable UUID, default/max 50 items with a continuation cursor.
Details page SLA/work/labor/reading/occurrence events separately. Gateway projections
are strict typed allowlists; exact amounts travel as strings and seconds as bounded
integers. Native forms use named paged pickers, clear data on authority/scope loss,
and retain exact encrypted pending envelopes before sending. Unknown response,
timeout or parse errors freeze the original envelope. Confirmed state precedes
local cleanup and optional reads; stale drafts require explicit comparison.

Every read, picker, recovery load and command records its entry access epoch.
Disconnect, reconnect, access denial and disposal advance that epoch and clear
server records, labels, comparison and confirmed presentation. Authorization and
encrypted sealing must recheck the same epoch before dispatch; reconnecting does
not resume an obsolete operation. A fresh authorized recovery may retry only its
original sealed envelope. Late failures cannot revoke a replacement epoch.
Permission, authentication, MFA, scope and entitlement denial clear plaintext.
A validated command or receipt is durably acknowledged for its original actor,
scope, action and command before presentation or optional reads, including when
the originating view has disconnected or been disposed. Storage-full failures
retain the fixed local-storage guidance and preserve the original pending request.

Required evidence: rollback RLS/grants/scope/revocation/replay, SLA pause/repriority
and clock boundaries, dispatch/labor ownership, maintenance reset/retry and atomic
late failure; exact domain and actual-API gateway tests; encrypted restart/native
keyboard/large text/themed layouts; isolated Windows build. Sequential rollback
assertions are not real contention/load. Installation, authenticated two-actor
walkthrough, actual overlapping sessions, load and Credential Manager restart
remain distinct acceptance gates.

Candidate verification, including `-ClientSamples` API projection capture, must
complete strict pgTAP `finish(true)` after the assertions and immediate constraint
checks and before any sample output. Every generated candidate query ends in
`rollback;`. Capturing client samples cannot bypass assertion-count or unfinished
test detection and does not establish installed or authenticated-native acceptance.
