# W4-02A organization and calendar instant resolution

Date: 2026-09-27. Status: source/candidate/client verified; development installation
and authenticated acceptance pending.
Parent: [W4-02](42_WAVE4_PRIVATE_HR_ORGANIZATION_CALENDAR_CONTRACT.md).
Coverage: FR-401–405, FR-407–410, FR-412, FR-439–440; AC-401/403/405/419;
EC-403–406/415–416. Existing employee/calendar migrations remain immutable.

## Organization

Departments are entity identities with unique reserved codes. Parent/name changes
are half-open dated revisions with immutable actor/reason history. At every
affected boundary, parent references must exist in the entity and the hierarchy
must remain acyclic. Entity-wide authority and MFA are needed to change shared
hierarchy; branch readers do not receive private employee fields.

An employee organization revision references its employee, spell, operational
branch assignment, department, optional employed manager, role title and immutable
calendar version. Its finite half-open dates must fit all referenced coverages;
one active revision covers an employee/date. The source department/manager is
operational data only. Missing coverage is explicitly unconfigured.
Replacement appends a revision and supersedes the prior revision without changing
its original dates/values. Expected employee version binds the mutation, and an
employee change advances that version. Consumed-date corrections require a
separate impact resolution before mutation.

Commands lock referenced employee rows in UUID order, then the entity organization
advisory lock. Hierarchy commands serialize on that same entity lock. Timeline
compatibility checks run at transaction end so existing employment commands either
retain compatible organization or fail with `ORGANIZATION_IMPACT_REQUIRED`.
No existing command silently creates a successor or retargets a calendar.

Ending an assignment creates a shorter compatible successor and preserves consumed
dates in its unchanged prefix. A future unconsumed assignment may instead be
withdrawn: an attributable immutable withdrawal event supersedes it without
creating a zero-duration replacement. Consumed assignments cannot be withdrawn or
retargeted. Trusted downstream consumption binds an exact source ID and dated
span to the original revision; generic authenticated clients cannot call it.

Five API-only forced-RLS tables hold identities, dated department revisions,
organization revisions, immutable consumption and withdrawals. Five scoped APIs
provide department directory, exact dated department lookup, department history,
employee organization/history and named commands. Commands include create/revise
department, assign/replace, end and withdraw. Reads
require `people.organization.view`; mutations additionally require
`people.organization.manage` and MFA. Lists use literal search, UUID keyset
pagination, default/maximum 50 for this increment. Commands use current access
before replay, existing actor-scoped receipts and atomic redacted audit/outbox.

## Local instant contract

The database resolves a local minute against an exact published calendar-version
ID and date within its coverage. The timezone is read from that version, never
accepted as an unrelated client substitute. A scoped read returns exact round-trip
UTC candidates with integer offset seconds, retaining historical second-based
offsets. Gaps return no candidates. Folds return the alternatives; accepting an
instant requires an explicit matching offset when more than one candidate exists.
An invalid selected offset is rejected. Overnight boundaries resolve independently
and exact elapsed duration is the difference of UTC instants, not wall minutes.

The resolver derives candidate offsets from PostgreSQL's zone rules around the
local date, then verifies every candidate by exact local-to-UTC-to-local round trip.
Fixtures must prove a normal date, New York gap/fold, Lord Howe half-hour changes,
Apia's skipped day, historical second offsets and overnight duration. Resolution
evidence names `pg-iana-roundtrip-v1`; approved downstream facts freeze the local
boundary, chosen offset, UTC instant and calendar version. Later zone-data changes
never rewrite that stored evidence. Calendar pattern previews are informational;
they do not create attendance or approve payable time.

Calendar reads require the current `people.calendars.view` capability and People
entitlement. No base-table grants, role grants or plan changes are introduced.
Gateways validate scope/version/date, allowlisted fields, UTC timestamps, sorted
unique offsets, and round-trip equality. The native detail workspace offers a
dated local-boundary preview with offset choices and visible UTC evidence.

## Verification and release

First write critical invariant/SQL security/gateway tests. Run rollback candidates
and installed employee/calendar regressions separately. Include denial after
scope/revocation, hierarchy/manager cycles, mismatched spells/branches/calendars,
stale expected versions, unknown fields, replay mismatch and failure atomicity.
Render native organization and resolution states light/dark at 200% text, check
keyboard/reachable controls and build in an isolated short Windows source copy.
Real concurrent hierarchy/timeline commands and actual native authenticated
restart remain separately evidenced. Candidate installation requires its concrete
review and the established owner authorization, with source hash and fresh ledger.
