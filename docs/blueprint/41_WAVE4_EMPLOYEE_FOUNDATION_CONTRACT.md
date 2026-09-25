# W4-01 — Employee directory and employment foundation

**Date:** 2026-09-24  
**Status:** Approved for synthetic development on 2026-09-24; candidate rollback verified and installed in development as ledger version `20260925181927` on 2026-09-25; native acceptance open
**Parent:** [Wave 4 specification](40_WAVE4_WORKFORCE_AND_DELIVERY_SPEC.md)  
**Coverage:** FR-401–408, FR-439–440; foundation portions of AC-401–403 and AC-419

## User outcome

An HR operator opens **People → Employees**, finds a scoped employee, creates a
synthetic employee with an employment start, changes their assignment, ends an
employment spell and records rehire. Register/detail show effective dates and
attributable history. Capabilities determine allowed actions. Salary, bank,
identity-document and health fields are excluded from this first slice.

The implementation includes database governance, typed domain contracts,
authenticated reads/commands, native register/editor, encrypted recovery and tests.
Private profiles, manager hierarchies, self-service account links, payroll and
retrospective corrections with downstream effects are later slices.

## Proposed data model

| Aggregate | Fields and constraints |
|---|---|
| `people.employees` | UUID, tenant/entity, normalized code, display name, optional work email, version, created/updated actors and UTC times. Code unique in entity and immutable after creation. |
| `people.employment_spells` | UUID, composite employee scope, start, nullable exclusive end, originating branch, version and audit metadata. Same employee's spells do not overlap. |
| `people.employment_assignments` | UUID, composite employee/spell scope, branch, job title/type, effective start/exclusive end and revision identity. Exactly one primary assignment covers every employed date. |
| `people.employment_events` | Immutable ID, employee/spell, command, actor, recorded time, effective date, event kind, redacted changed fields, reason and superseded event link where applicable. |

Commands serialize on the employee before validating the complete timeline.
Composite FKs enforce tenant/entity ancestry. Database uniqueness and serialized
interval validation are the final arbiters, independently of the client.
Code uniqueness resolves concurrent creates.

Identity may be updated with expected version and an appended event. Name changes
do not rewrite the frozen name of a later approved business document. Codes are
not freed by deletion. Employment status is derived from dated spells/assignments,
not a daily background mutation of a mutable status flag.

## Capabilities and privacy

| Proposed capability | Allows |
|---|---|
| `people.employees.view` | Operational directory/detail in the authorized branch |
| `people.employees.manage` | Create/revise operational identity and initial employment |
| `people.employment.manage` | Assignment change, employment end, rehire and unconsumed correction |
| `people.employees.history.view` | Timeline events filtered to authorized branches |

Require People entitlement and existing authentication/MFA rules. Defining these
permissions does not grant them to existing roles; grants use the membership
mechanism. `people.view` alone and employee creation grant none of these rights.
Mutations require directory read plus the relevant manage permission. Employment
changes follow the privileged-permission MFA policy.

The candidate seeds `module.people` disabled for every current plan, without
changing existing plan decisions. Every read, command and replay checks an enabled
entitlement on the tenant subscription after role/scope checks. `trialing` requires
an unexpired trial; `active` requires an unexpired paid period when one is set.
Other subscription states fail closed. The desktop clears loaded employee data on
entitlement loss, retains sealed uncertain commands encrypted, and offers a fresh
read after the entitlement is restored. Plan enablement is a separate owner policy.

Requests have explicit non-null tenant/entity/branch. An as-of directory returns
employees assigned to that branch on the date. An ended-spell filter uses its last
assignment; future hires use a separate filter. Detail uses the same dated access
predicate. A cursor cannot widen the requested scope/filter.

History returns branch-authorized events only, without leaking other branch names,
destinations or event counts. Label the timeline as scoped when it may be incomplete.
Entity-wide HR viewing needs an explicit later scope mode. Transfer checks access
in both source and destination. Employee pickers expose operational identity and
eligibility only. Work email never proves account ownership.

## Dates, transitions and corrections

1. Use civil dates in the entity time zone. The UI's inclusive last-working date
   converts to the next civil date as the stored exclusive end, not a fixed 24-hour
   UTC addition. Null end means open employment.
2. Create identity, first spell, first assignment, event, audit and receipt atomically.
   Initial onboarding may use a historical start because the new identity has no
   approved downstream facts.
3. Assignment change splits an interval at the effective date and creates its
   successor. Preserve original revision/event evidence before changing derived
   interval boundaries. Do not silently erase an existing scheduled successor.
4. End employment closes the spell and its final assignment at the same exclusive
   date. Reject an end that silently truncates a scheduled successor. Account and
   membership state are not changed by this command.
5. Rehire retains employee ID/code and creates a new nonoverlapping spell with an
   initial assignment. Cross-entity movement is rejected here; it needs linked new
   employment. Types: `permanent`, `fixed_term`, `casual`, `contractor`; these are
   operational labels, not a legal worker-classification decision.
6. Before changing a current/historical assignment, the command must prove that no
   approved attendance, leave, payroll, time or work allocation consumes the affected
   interval. The dependency-check contract must fail closed for unknown installed
   consumers. W4-01 can conservatively allow only future changes when that proof is
   unavailable, with a clear correction-required response.
7. A scheduled assignment change can be cancelled through a reasoned command
   referencing its event and expected employee version. Append a superseding event
   and rebuild the validated timeline atomically; never delete the original event.
   Replacement follows as a new change after cancellation. Historical correction
   awaits the impact-aware later workflow.
8. A change cannot create gaps/overlap inside a spell, invalid zero-length intervals
   or downstream ineligibility. Later consumer modules must serialize consumption
   against the same employee/timeline version to prevent a check-then-use race.

## Public API proposal

Reuse `CommandEnvelope`: command ID, idempotency key, context, expected version,
client timestamp and payload. Map it to actual shared operational RPC parameters
after verifying their current definitions. `auth.uid()` is authoritative; the client
actor field is not. Create expects version zero; later commands compare and increment
the employee aggregate version once, including timeline changes.

| Proposed API | Inputs / result |
|---|---|
| `api.people_employee_directory` | Scoped read; explicit date/status/search, stable UUID keyset cursor; 50 rows maximum |
| `api.people_employee_detail` | Scoped operational detail for one employee and requested date/status; access predicate matches the register |
| `api.people_employee_history` | Scoped event read, employee and UUID cursor; at most 50 authorized events |
| `api.people_employee_branches` | Scoped branch picker for authorized employment managers |
| `api.people_employee_command` | Shared envelope with action `create`, `identity`, `assignment`, `end`, `rehire` or `correct`; action-specific payloads below; returns verified employee identity, scope and version |

The read and command functions are `security definer` with an empty search path,
explicit current permission checks and no base-table grants to desktop roles. This
preserves branch-filtered history without granting broad base-table SELECT. The
command payloads are: `create {id, code, display_name, work_email?, start_date,
job_title, employment_type}`, `identity {id, display_name, work_email?, reason}`,
`assignment {id, effective_date, destination_branch_id, job_title,
employment_type, reason}`, `end {id, spell_id, end_date_exclusive, reason}`,
`rehire {id, start_date, job_title, employment_type, reason}`, and `correct
{id, event_id, correction_action: cancel, reason}`.

API names are proposals and require collision checks before migration creation.
Read views use explicit columns, base RLS and minimum SELECT grants; direct base
reads must enforce the same scope/privacy restrictions. Private HR fields will use
separate protected tables/projections rather than expanding these operational views.

Input limits: uppercase code `[A-Z0-9][A-Z0-9_-]{0,31}`; trimmed display name/job title
1–160 characters; work email at most 254 with basic syntax validation; reason
1–1000 characters. Unknown keys, malformed dates and over-limit values fail before
mutation. Versions retain exact integer values within the verified transport range.
Server recorded time cannot be replaced by the client timestamp.

Command results identify request, employee/spell, scope, command kind, version and
authoritative outcome. Invalid/mismatched responses retain the sealed uncertain
request. Confirmed state survives a subsequent optional history-refresh failure.

Stable errors: `EMPLOYEE_CODE_EXISTS`, `EMPLOYMENT_OVERLAP`,
`EMPLOYMENT_DATE_INVALID`, `EMPLOYMENT_CORRECTION_REQUIRED`,
`EMPLOYMENT_FUTURE_EVENT_EXISTS`, `EMPLOYMENT_SCOPE_INVALID`, `VERSION_CONFLICT`,
`IDEMPOTENCY_MISMATCH`, plus shared auth/permission errors. Denied scopes cannot
leak another employee's existence or current private state.

## Native workspace and recovery

Route: `/people/employees`. Add capability-aware People navigation for this working
screen; preserve existing unrelated routes and approved visual tokens/artwork.

Register: search/date/status, employee code/name, job, branch and derived employment
state. Detail: operational identity, current/future assignment, employment history
and allowed actions. Editor: named branch picker, persistent labels, effective-date
preview, inline validation and clear explanations for blocked historical corrections.

Use an actor/scope-specific encrypted employee-editor namespace. Local drafting is
allowed; create/change/end/rehire/correct require online confirmation. An uncertain
command seals ID/key/body/version; disable payload edits until resolved. Recovery
distinguishes unsent, uncertain, confirmed and stale. Navigation cannot silently
discard uncertainty. Revocation locks drafts and discards old-context responses.

## Test-first implementation and exit

- Database: permission matrix, cross-tenant/entity/branch substitution, direct writes,
  directory privacy, dual-branch transfer denial, replay after revocation, stale
  version, duplicate codes, date/overlap constraints, corrections, consumed-history
  denial, future conflicts, late-failure rollback and immutable events.
- Two real sessions: same-code creates and competing timeline changes. The loser
  leaves no partial history or overlap. Once a governed downstream consumer is
  installed, its consumption/correction race is an integrated acceptance gate
  before historical correction is enabled; W4-01 rejects historical correction.
- Domain: half-open intervals, leap days, inclusive-end conversion, adjacent rehire,
  dated state, input bounds, exact versions and malformed response rejection.
- Gateway/recovery: scope/cursor matching, literal search, encrypted restart, retry
  identity, stale conflicts, response loss and permission/context revocation.
- UI: loading/error/empty/populated, capabilities, named pickers, correction limits,
  navigation guard, light/dark and 200% renders, keyboard and focus.
- Integration: focused shared-foundation regressions, clean analyzer, isolated
  Windows build, separately evidenced authenticated native walkthrough.

Before database work, refresh development health, ledger, helper definitions and
advisors. Candidate and installed-schema verification use rollback-only fixtures;
the development installation is recorded separately. No persistent privileged
employee fixtures, production change or acceptance-owned stock-opening changes
are authorized by this contract.
