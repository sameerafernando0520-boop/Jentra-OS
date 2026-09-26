# W4-02 — Private HR, organization, calendars, reviews and account links

**Date:** 2026-09-26  
**Status:** Detailed synthetic-development contract; W4-02A calendar source verified and installed in development; authenticated acceptance and remaining organization/private HR work pending  
**Parent:** [Wave 4 specification](40_WAVE4_WORKFORCE_AND_DELIVERY_SPEC.md)  
**Depends on:** Installed [W4-01 employee foundation](41_WAVE4_EMPLOYEE_FOUNDATION_CONTRACT.md)  
**Coverage:** FR-401–405, FR-409–412, FR-439–440; AC-401, AC-403–405, AC-419–420

## User outcome and release boundary

An authorized HR operator assigns a synthetic employee to a dated department,
manager and work-calendar version; manages a small private contact profile; and
conducts an attributable objective/review cycle. An employee may separately
confirm a proposed link to an existing signed-in account. Directory readers see
none of the private profile, review or link evidence. Account linking alone grants
no tenant role or self-service access.

W4-02 is delivered in two installable increments. **W4-02A** covers department,
manager and calendar history. **W4-02B** covers private profile/document access,
reviews and account links. Each increment requires database, domain, gateway,
native UI/recovery, rollback-candidate, development-install and authenticated
evidence before being called complete. W4-01's native and contention gates stay
open independently. No production, statutory rule or real HR data is authorized.

Compensation, bank details, government identifiers, health data, biometric data,
recruitment and automatic employee scoring are outside W4-02. Private document
upload remains unavailable until its separate storage authorization and retention
path passes the tests below. A placeholder or generic attachment upload is not a
successful private-document feature.

## Scoped data contracts

Every row carries `tenant_id`, `legal_entity_id` where applicable, UUID identity,
version and attributable UTC timestamps. Composite foreign keys prove ancestry.
The current `people.employees` operational projection and W4-01 event redaction
remain unchanged.

| Aggregate | Required contract |
|---|---|
| Department | Entity-scoped immutable code and mutable display name; dated active interval; optional dated parent. A code remains reserved after retirement. Parent must be in the same entity. |
| Employee organization assignment | Employee and spell IDs; half-open civil-date interval inside an employment spell; branch, department, optional manager employee, role title and immutable calendar-version ID; recorded actor/time, reason and supersession lineage. At most one current assignment per employee/date. Missing assignment is explicit `unconfigured`, not an inferred default. |
| Calendar identity/version | Entity-scoped calendar code; IANA time zone; immutable version ID, effective interval and approval identity; weekly local working intervals, holiday/exception dates and source labels. An assignment freezes one version ID rather than following a mutable latest pointer. |
| Private profile | Separate protected table keyed by employee and entity; only synthetic personal contact and emergency-contact fields in this slice. Field-level change reason and version. No private field in operational employee JSON, generic search or W4-01 events. |
| Private document | Separate metadata and bucket path keyed by tenant/entity/employee/document, classification, purpose, MIME, size, checksum, actor, status and retention date. Content is never in SQL, audit JSON, a notification or an ordinary attachment URL. |
| Objective/review | Cycle, subject employee, reviewer employee, objective versions, bounded text, period, status, actor/timestamps, acknowledgement and immutable submitted revision. No derived pay or performance score. |
| Account link | Employee, exact `auth.users` ID, tenant membership ID, initiator, pending expiry, acceptance actor/time, status and revocation reason. One active account per employee and one active employee link per user in the tenant. |

### Organization and temporal rules

- Department parent changes and employee-manager changes are effective-dated. A
  command locks the affected entity hierarchy/timeline, rejects self-links and
  cycles at every affected boundary date, and checks the manager is employed in
  the same entity throughout the proposed interval. Concurrent changes cannot
  create a cycle that either command would reject alone.
- An organization assignment must fit inside one W4-01 spell and its authorized
  branch assignment on every covered date. Transfer/end/rehire either produces an
  explicitly compatible organization successor or fails with an impact-required
  result; it never silently retargets department, manager or calendar. W4-01 and
  W4-02 commands serialize on the same employee timeline.
- Calendar versions are immutable after approval or consumption. A new version
  has an effective start and may not overlap another approved version of that
  calendar. Changes to a consumed date require an impact-aware correction; W4-02
  does not rewrite attendance or payroll evidence.
- Weekly intervals use local start/end times with an explicit end-day offset of
  zero or one. Expand across day/week boundaries before rejecting overlap. Each
  holiday/exception has an explicit civil date, work/nonwork decision and reason;
  duplicates for the same date/version are rejected. No implicit jurisdictional
  holiday feed or statutory working-time assumption is supplied.
- Date-to-instant conversion uses the version's IANA zone. Nonexistent local
  times are rejected. Ambiguous local times require an explicitly selected UTC
  offset; the system records it with the resolved instant. Calendar previews show
  both local and UTC boundaries, including overnight intervals. W4-03 freezes
  this version and resolution evidence when it consumes work time.

### Private fields, documents and retention

`people.hr.private.view` and `people.hr.private.manage` are separate from
`people.employees.view`, `people.view`, `core.files.view` and payroll permissions.
Private reads require current People entitlement, active membership, entity and
branch scope, and the dedicated capability; manager status alone grants nothing.
Response schemas are explicit allowlists. The server never serializes the private
table and removes fields afterward. Search, picker, audit, outbox, notification,
export and error messages contain no personal contact value or document path.

The existing `jentra-attachments` bucket and `core.attachments` RPCs are
**unsuitable for HR documents**: their current Storage policies allow the broad
tenant `core.files.view/manage` permissions. W4-02B must use a separate private
bucket and per-document authorization that checks the exact employee, tenant,
entity, scope, entitlement and HR-document permission on each upload/download.
Neither generic file permission nor a guessed object path may grant access.
Short-lived access must be mediated by a trusted server component; secrets and
service-role keys never enter the desktop client. A removed membership or
revoked HR permission invalidates new access immediately. No content URL is
persisted in a draft, event or audit record.

A versioned tenant retention policy must name each private data class, purpose,
retention trigger and expiry, legal hold state, erasure actor and evidence format.
W4-02B cannot accept private content until the policy and a tested purge/redaction
worker are installed. Synthetic fixtures use an explicit 30-day expiry after
their test cycle closes; this is a development cleanup choice, not a legal
retention claim. Expiry removes profile/document content and access, while the
minimal append-only audit retains actor, action, scope, class and nonreversible
hash without the erased value. A legal hold blocks purge with an attributable
reason and review date. Export and erasure require distinct privileged commands
and cannot be inferred from an employee end date.

### Reviews and account linking

A review moves `draft → submitted → reviewed → acknowledged → closed` through
named commands and expected versions. The reviewer must be a different active
employee, eligible in the same entity for the review period, and explicitly
authorized; a manager relationship alone is insufficient. Draft visibility is
limited to its author and dedicated HR reviewers. The subject sees the submitted
revision when shared and can acknowledge receipt, without asserting agreement.
Later edits create a new attributable revision and require resubmission. Review
text and objectives never enter generic search, audit snapshots, AI prompts,
notifications or compensation calculations. Notifications contain only a safe
action label and a deep link that rechecks access.

An HR link initiator with `people.account_links.manage` and MFA selects an exact
existing active tenant membership, not an email match. The target authenticated
user must accept the pending link in their own session before its 24-hour expiry;
the server compares `auth.uid()` with the selected user ID. The command atomically
checks both membership and employee scope, enforces uniqueness and records both
actors. Rejected/expired/revoked links retain minimal audit lineage but grant no
access. Employee creation, work-email changes, link initiation and link acceptance
never invite a user or grant a role. Self-service additionally requires an active
link, current membership, `people.self.view`, the People entitlement and a
separate self-service read projection. Revocation checks run on every read and
replay; no stale local cache remains visible after loss of access.

## API, permissions and recovery

### First calendar-version increment

The [calendar candidate](../../supabase/migrations/20260926082441_wave4_calendar_versions.sql)
implements calendar identity, immutable published versions and attributable
events. This is part of W4-02A; it does not assign calendars to employees or
resolve civil times to instants. Its [verification record](../verification/wave4/calendar-candidate-20260926.md)
separates rollback proof from installation and native acceptance.

The [calendar client verification and installation review](../verification/wave4/calendar-client-20260926.md)
records the typed gateway, native workspace, encrypted recovery, client tests,
render previews and approved development installation. Authenticated acceptance
remains distinct.

Versions require an explicit half-open start/end range of at most 1,830 civil
days. Gaps are allowed and appear as unconfigured coverage. Calendar code is
immutable and reserved. A database exclusion constraint rejects overlapping
version ranges for the same calendar. Initial creation can publish historical
dates for a new identity; later publication must start after the entity's current
date. Published versions cannot be changed or deleted. Correcting consumed or
current/past rules requires a later impact-aware workflow.

`weekly_intervals` has at most 56 objects with integer `day_of_week` (1–7),
`start_minute`/`end_minute` (0–1439) and `end_day_offset` (0 or 1). Local duration
must be 1–1440 minutes; Sunday spill is checked against Monday for overlap.
`date_overrides` has at most 366 unique in-range dates, `is_working_day` and a
1–500-character reason. A working override uses existing regular hours (including
the previous day's overnight spill); it cannot invent unspecified hours. A
nonworking override closes the whole civil date; the later instant-resolution
adapter must clip overnight spill consistently. All schedules remain local
patterns until that adapter passes ambiguous/nonexistent-time tests.

| API | Calendar-version contract |
|---|---|
| `api.people_calendar_directory` | Explicit tenant/entity/branch, optional as-of date/literal search/UUID cursor; 50 identity rows with selected version metadata or explicit null coverage. |
| `api.people_calendar_detail` | Explicit calendar and immutable version IDs; returns the allowlisted local pattern only when ancestry matches. |
| `api.people_calendar_versions` / `api.people_calendar_history` | Scoped calendar plus UUID cursor; 50 version summaries or immutable events, respectively. |
| `api.people_calendar_command` | Shared envelope; `create`, `publish` or `rename`; current entitlement, view/manage capability, MFA and entity-wide management authority before replay. |

`create` requires `id`, `code`, `name`, `version_id`, `start_date`,
`end_date_exclusive`, `timezone`, `weekly_intervals`, `date_overrides`, `reason`
and expected version zero. `publish` omits code/name and uses the current
calendar aggregate version. `rename` accepts only identity, name and reason.
Unknown keys and malformed values fail before mutation. Publication and rename
increment the aggregate version once; the command response, audit and outbox
contain identity/version summaries rather than full pattern payloads. Existing
roles receive no automatic permission grant and plans are not enabled.

Read authority may be branch-scoped for an entity-shared calendar. Changes require
an entity-wide calendar-manage role in addition to the explicit branch context;
a branch-only manager cannot alter the rules shared by other branches.

All reads and commands are named `api` functions with explicit tenant/entity/
branch and bounded IDs/dates. No direct `authenticated` SELECT/INSERT/UPDATE on
private People base tables. Apply forced RLS and the W4-01 security-definer
pattern with `search_path = ''`, qualified identifiers and narrowly granted
EXECUTE. The server derives the actor from `auth.uid()`. Read limits default to
50, maximum 200 for directory-like lists; review/private history maximum 50.
Literal search and stable UUID keyset cursors cannot widen scope.

| Capability | Permitted operation |
|---|---|
| `people.organization.view/manage` | Scoped department and assignment read/change; manage requires MFA. |
| `people.calendars.view/manage` | Scoped calendar/version read/change; manage requires MFA. |
| `people.hr.private.view/manage` | Explicit private profile read/change; manage requires MFA. |
| `people.hr.documents.view/manage` | Exact-document metadata/content access through the separate path; manage requires MFA. |
| `people.reviews.view/manage/acknowledge` | Assigned review read/workflow and subject acknowledgement; management requires MFA. |
| `people.account_links.manage` / `people.self.view` | HR initiation/revocation versus linked self-service read; initiation/revocation requires MFA. |

All mutations use the shared request envelope, semantic idempotency hash,
expected version, actor-scoped receipt, redacted audit and required outbox in one
transaction. Replay rechecks current entitlement, membership, scope and
capability before returning a stored result. A retry cannot change the original
request body or accept a new account-link target. Denied resource IDs return a
uniform not-found response without existence or private-field hints.

Native routes under **People** expose separately gated Organization, Calendars,
Private HR and Reviews workspaces. Each has loading/error/empty/populated states,
scope/date labels, history, inline validation, keyboard/focus and 200% text
renders. Private drafts use actor/tenant/entity/branch/employee-specific encrypted
namespaces. Sign-out, scope loss or revocation clears visible private state and
locks drafts. An uncertain write preserves the exact sealed request across a
real Windows restart; a confirmed write survives a later optional refresh error.
Self-service never appears solely because an employee email equals the login.

## Required verification and exit

1. Rollback-only database tests prove cross-tenant/entity/branch denial, no
   private data in W4-01 directory/history/search, no direct table or generic
   attachment access, permission/MFA/entitlement denial, and replay denial after
   revocation. Check event/outbox/notification payloads for private values.
2. Prove adjacent/overnight/holiday/DST calendar cases; version immutability;
   manager self/cycle and cross-entity rejection; organization intervals inside
   employment; and failure when a consumed interval is changed. Use two real
   sessions for competing hierarchy/timeline updates.
3. Prove review actor independence, revision-bound acknowledgement, no pay side
   effect, and restricted subject/manager/HR visibility. Link tests use two
   authenticated users and cover exact-user acceptance, expiry, duplicate link,
   revocation, membership loss and no implicit role grant.
4. Prove per-document upload/download authorization against the broad existing
   `core.files.*` role, guessed paths, permission revocation and retention purge.
   No private-document UI ships until this path passes.
5. Run domain/gateway/draft-restart/UI tests, analyzer, light/dark 200% rendered
   inspection and an isolated Windows build. Separately record migration candidate,
   development installation, authenticated native walkthrough and owner decision.

The framework-free W4-02A calendar-pattern validator and rollback-verified SQL
candidate are source-only. This contract supplies no claim that W4-02 migrations,
policies or native screens, or the synthetic tenant, have been installed. Later W4-03 attendance and leave
must consume an approved calendar-version ID and refuse an unconfigured employee
rather than inventing a schedule.
