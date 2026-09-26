# Wave 4 — Workforce and delivery

**Date:** 2026-09-24  
**Status:** Approved for synthetic development  
**Implementation approval:** Owner instructed continuation on 2026-09-24 after contract review request  
**Scope:** Synthetic development, Windows first  
**Related:** [Roadmap](05_TEST_AND_DELIVERY.md), [architecture](01_ARCHITECTURE.md),
[security](03_DATA_SECURITY.md), [design system](04_DESIGN_SYSTEM.md),
[employee foundation](41_WAVE4_EMPLOYEE_FOUNDATION_CONTRACT.md),
[private HR and organization/calendar contract](42_WAVE4_PRIVATE_HR_ORGANIZATION_CALENDAR_CONTRACT.md).

## Outcome and scope

Wave 4 connects employees and work performed to governed payroll, project delivery,
service execution and asset accounting. A completed slice includes its database
contract, exact domain model, authenticated gateway, native workspace, encrypted
recovery and verification. A route, table or calculator alone is not completion.

The user has requested that Wave 4 start. This document supplies the detailed
specification and review step identified by the earlier delivery plan. Wave 3's
remaining finance, installation and authenticated acceptance retain their own
status and ownership; starting Wave 4 does not close those gates.

The first implementation is **employee records and effective-dated employment**.
It can be developed against shared foundations independently of bank reconciliation,
financial reports and payroll posting. Later slices require verified providers;
no assumption is made that all Wave 3 candidates are installed.

Included: employee directory and employment history; private HR; calendars,
attendance and leave; configurable synthetic payroll; projects, tasks, time and
expenses; tickets, SLA, work orders and equipment; fixed assets, depreciation,
maintenance and disposal. Performance review is a bounded objective/review workflow.

Excluded: recruitment marketplace, biometric collection, automated employee scoring,
external payroll/bank execution, statutory submission, live provider integration,
production data and rollout. Real Sri Lankan payroll requires separately validated
effective-dated rules and qualified review under the roadmap. This specification
supplies no legal rate, statutory formula or compliance certification.

## Decision baseline

- Reuse core scope, capabilities, entitlements, workflow, audit, command receipts,
  private attachments, notifications and encrypted drafts.
- An employee is a business identity, not an authentication user. Creating an
  employee never creates an account, sends an invitation or grants a role.
- Employment belongs to one legal entity. Rehire creates a new spell; moving to
  another entity creates a linked employment rather than rewriting history.
- Work dates use an explicit versioned entity/calendar time zone. Instants use UTC.
  Date ranges are half-open: `[start_date, end_date_exclusive)`; null end is open.
- Durations use integer seconds. Money, quantities and rates use canonical decimal
  strings and exact Dart/BigInt arithmetic; no binary floating-point totals.
- Original facts, approved inputs and posted effects retain immutable lineage.
  Changed rules or master data never silently recalculate historical outcomes.
- Server commands recalculate truth, check current access and versions, and enforce
  idempotency, configured approval and MFA. Authoritative transitions are online.
- Existing journals, stock, AR and AP remain authoritative. Add governed source
  adapters and mappings, not a second posting engine.
- Candidate testing and database installation are separate. Preserve active Wave 3
  work, stock-opening acceptance scenarios and running application binaries.

## Functional requirements

### Foundation and privacy

- FR-401: Every aggregate MUST enforce tenant, entity and applicable branch,
  authenticated actor, entitlement, capability and optimistic version.
- FR-402: Mutations MUST use named authenticated API commands. Business changes,
  receipt, redacted audit, lifecycle telemetry and required outbox events MUST commit
  atomically. Replay MUST recheck current access before returning a stored result.
- FR-403: Operational directory fields, HR-private fields and compensation/bank data
  MUST have separate read contracts and permissions. Module access MUST NOT imply
  payroll, private-attachment or private-export access.
- FR-404: Drafts MUST be encrypted and scoped to actor/tenant/entity/branch. Uncertain
  responses MUST preserve the original request for retry. Revocation/sign-out MUST
  clear visible sensitive data and lock local content.
- FR-405: Lists, pickers, history, imports and exports MUST be bounded, permission
  filtered and literal-search safe. Omitted scope MUST NOT broaden access.

### People

- FR-406: An authorized operator MUST create an entity-scoped employee with a unique
  code, display name and dated employment with branch, job and employment type.
  Codes MUST remain reserved after employment ends.
- FR-407: Assignment changes MUST preserve effective/recorded dates, actor, reason
  and history. Concurrent commands MUST NOT produce overlapping primary assignments
  or employment spells for the same employee in that entity.
- FR-408: Employment end/rehire MUST preserve attendance, leave, payroll and work
  evidence. Corrections affecting approved sources MUST require explicit impact
  resolution. Termination MUST NOT delete an authentication account.
- FR-409: HR-private details/documents MUST require explicit permissions. Account
  linking/self-service MUST use a separately governed verified link; matching an
  email address MUST NOT establish identity.
- FR-410: Department, manager, role and calendar assignments MUST be scoped and
  effective-dated; manager relationships MUST reject self-links and cycles.
- FR-411: Employee objectives/reviews MUST support attributable draft, submission,
  review and acknowledgement with restricted visibility. Acknowledgement MUST NOT
  imply agreement or change compensation automatically.

### Attendance and leave

- FR-412: Versioned calendars MUST specify time zone, working intervals, holidays
  and policy dates. Overnight and ambiguous/nonexistent local times MUST have
  explicit handling before an interval is accepted.
- FR-413: Attendance MUST preserve raw/manual source identity, instants, breaks,
  calculated duration, correction reason and approval. Duplicate imports or
  overlapping intervals MUST NOT double count payable time.
- FR-414: Leave policies MUST configure units, accrual, carry-forward, expiry and
  eligibility. Balances MUST derive from attributable ledger entries; adjustments
  MUST append a reasoned entry rather than overwrite a balance.
- FR-415: Leave submission, independent decision and cancellation MUST lock relevant
  balance/intervals, reject disallowed overlap/insufficient balance and reverse only
  original entitlement effects. Attendance/approved-leave conflicts require resolution.
- FR-416: Approved work/leave consumed by payroll MUST be sealed by version. Later
  corrections MUST produce explicit differences for an eligible later run.

### Payroll

- FR-417: Pay components/rules MUST be versioned and effective-dated with earning,
  deduction/employer-cost classification, proration, rounding and limits. Development
  fixtures MUST be visibly synthetic without statutory-validity claims.
- FR-418: A run MUST freeze entity, period, employees, assignments, approved inputs,
  rates, policies and exact per-component calculation evidence. Preview MUST explain
  every gross, deduction, employer-cost and net line.
- FR-419: Approval MUST be independent of preparation where required and bind to the
  precise revision. Material changes MUST invalidate approval; stale input versions
  MUST block posting.
- FR-420: Posting MUST atomically create payroll obligations, balanced journal effects,
  immutable payslip facts, audit and receipts once per run. Payroll liabilities MUST
  be distinct from supplier AP and reconcile to their own control attribution.
- FR-421: Reversal/correction MUST retain posted originals, reject incompatible
  settlement/period state and restore original effects once. Off-cycle adjustments
  MUST reference original employment, period and component basis.
- FR-422: Payslips, exports and recorded settlement MUST have separate permissions.
  Posting MUST NOT imply payment, bank reconciliation or statutory filing. Settlement
  evidence/reversal MUST reconcile to payroll obligations.

### Projects, time and expenses

- FR-423: Projects MUST define entity, accountable branch, customer where billable,
  manager, dates, currency, approved budget versions and milestone or time/material terms.
- FR-424: Tasks/resource plans MUST retain owners, dependencies, progress and capacity
  basis; circular task dependencies MUST be rejected.
- FR-425: Time entries MUST reference eligible employment and project/task or work
  order, exact duration and service date. Approval MUST reject prohibited overlap
  and duplicate consumption of the same work interval across modules.
- FR-426: Expenses MUST preserve exact currency/rate/tax evidence, attachments,
  allocations and approval. Reimbursement and supplier billing MUST NOT create
  duplicate obligations for the same expense source.
- FR-427: Billing MUST consume approved unbilled time/expense or eligible milestones
  through existing sales commands with source quantities and frozen rate/tax basis.
  Concurrent requests MUST NOT bill a source unit twice.
- FR-428: Project cost, commitments, revenue, budget and margin MUST state as-of date,
  currency and source basis. Internal cost requires permission; project closure MUST
  explicitly resolve open work and unbilled obligations.

### Service, equipment and maintenance

- FR-429: Tickets MUST preserve customer/contact, equipment, priority, contract or
  warranty, classification, owner and triage/resolution history.
- FR-430: SLA calculations MUST freeze calendar/policy versions and retain start,
  pause/resume reasons and due-time evidence. Reprioritization MUST NOT erase an
  earlier breach; authorized recalculation MUST retain both versions.
- FR-431: Dispatch MUST validate staff scope, eligibility, availability and required
  equipment. Work orders MUST support assignment, acceptance, work, completion,
  customer confirmation or reasoned exception, and configured independent closure.
- FR-432: Parts MUST use existing stock reservation/issue/return commands. Labor MUST
  reuse time capture. Completion MUST preserve cost and billing eligibility without
  implying invoice, payment or customer acceptance.
- FR-433: Equipment MUST distinguish customer equipment, internal fixed assets and
  stock identities. Warranty/contracts MUST preserve dates and coverage evidence;
  linking equipment MUST NOT automatically capitalize stock.
- FR-434: Preventive maintenance MUST use calendar/meter schedules, preserve readings
  and create at most one work order per occurrence. Resets, rollover, deferrals and
  retries MUST preserve original due history and reason.

### Fixed assets and integration

- FR-435: Capitalization MUST reference eligible procurement or governed opening
  evidence, ownership, location, custodian, cost components and in-service date.
  A source cost MUST NOT be capitalized twice or remain simultaneously in stock value.
- FR-436: Depreciation books MUST freeze cost, residual, useful life, method, calendar
  and conventions. Exact schedules MUST cap depreciation at depreciable value and
  allocate final rounding residue deterministically. Changes MUST be prospective
  and attributable unless a separately governed correction is required.
- FR-437: Depreciation posting MUST lock asset/book/period and create journals once.
  Closed periods or stale schedules MUST block it. Reversals MUST restore original
  values without rewriting old schedules.
- FR-438: Asset transfers, impairment, configured revaluation and disposal MUST retain
  cost/depreciation history, approval, proceeds and gain/loss evidence. Disposed assets
  MUST reject depreciation absent a governed reversal.
- FR-439: Native workspaces MUST have loading/error/empty/populated states, named
  pickers, permitted actions, history, keyboard access and recovery. Notifications,
  deep links, exports and attachments MUST recheck aggregate access.
- FR-440: Each slice MUST report source, tests, candidate/install status, rendered
  review, build, authenticated runtime and owner acceptance separately. Missing
  providers MUST produce actionable unavailable states, never fabricated success.

## Non-functional requirements

- NFR-401: Tenant tables MUST have RLS and cross-tenant/entity/branch tests. Privileged
  functions MUST use an empty search path and explicit execution grants.
- NFR-402: Compensation, health/identity details and bank data MUST be absent from
  directory responses, generic audit payloads, logs, notifications and global search.
- NFR-403: Financial arithmetic MUST specify precision, rounding and conservation
  properties. Duration calculation MUST avoid premature fractional-hour conversion.
- NFR-404: Contention tests MUST use real separate sessions for employment overlap,
  leave, payroll posting, billing consumption, parts issues and depreciation.
  Sequential replay tests are not contention evidence.
- NFR-405: Ordinary paged reads SHOULD meet 500 ms p95 and ordinary commands 1.5 s p95
  on a documented development load. Payroll/report jobs MUST be bounded and expose
  progress/failure; they MUST NOT hold an unbounded UI request open.
- NFR-406: Default pages MUST contain at most 50 rows, maximum 200. Proposed payroll
  bounds are 200 employees/run and 100 components/employee. Oversize requests MUST
  fail before effects; partitioning requires an explicit contract.
- NFR-407: Light/dark, both densities, keyboard/focus, 1024x720 through 1920x1080 and
  200% text scale MUST receive rendered verification.
- NFR-408: Encrypted drafts and uncertain retries MUST survive restart. Real Windows
  Credential Manager recovery acceptance requires a native restart test.
- NFR-409: Candidate checks MUST preserve acceptance data. Authentication/MFA is
  user-managed; no production change, external execution, commit or push is implied.
- NFR-410: Relevant analyzer, invariant/security, gateway/recovery, UI and isolated
  Windows-build checks MUST pass with attributable evidence.

## Data ownership and integration

These are proposed aggregates, not claims of installed tables.

| Owner | Aggregates | Integration |
|---|---|---|
| `people` | Employee, employment/spell revisions, assignments, private profile, reviews | Core scope; separately governed account link |
| `people` | Calendars, attendance, leave policies/ledger | Sealed approved work/leave inputs |
| `people` | Rule versions, payroll runs/calculations, payslip facts, obligations | Existing journal engine; dedicated payroll control attribution |
| `projects` | Projects/tasks, budgets, resources, time, expenses | Employment; procurement/sales/finance adapters |
| `service` | Tickets/SLA, equipment, contracts, work orders, maintenance | Employee eligibility, common time, inventory and sales |
| `finance` | Assets/books, cost components, schedules, depreciation/disposal | Procurement/stock provenance; existing periods and journals |

Child references use composite tenant/entity keys. Branch transfers require access
in both branches and cannot expose private history to the destination through an
operational directory. Implicit intercompany posting is outside initial slices.

Each posting command documents lock order consistent with its existing providers.
Lock source versions/quantities, open period and required mappings; commit business
effects and receipt atomically. Verify provider source-type support before exposing
an action. Reference dates and recorded timestamps are retained separately.

## Acceptance criteria and traceability

These are required scenarios, not completed test results.

| Criterion | Requirements | Given / when / then |
|---|---|---|
| AC-401 | FR-401–405; NFR-401–402 | Given another tenant/denied branch, when any read, mutation, replay, file or export is requested, then no protected data or business side effect is returned. |
| AC-402 | FR-406–407 | Given valid synthetic inputs, when an employee is created/changed, then one identity and an attributable nonoverlapping timeline appear with exact versions. |
| AC-403 | FR-408–410 | Given employment end, rehire or transfer, when applied, then history remains, dates/scopes are validated and account access is not implicitly changed. |
| AC-404 | FR-409, FR-411 | Given directory-only or review-limited access, when private HR/pay or another review is requested, then access is denied without private leakage. |
| AC-405 | FR-412–413; NFR-403 | Given overnight/duplicate/overlapping/clock-transition attendance, when calculated or corrected, then exact approved duration follows frozen rules and retains original facts. |
| AC-406 | FR-414–416; NFR-404 | Given competing leave requests, when decided concurrently, then balances respect policy and cancellation restores only its original effects. |
| AC-407 | FR-417–419; NFR-403 | Given synthetic pay rules, when calculated and approved, then all lines reproduce exactly and changed inputs invalidate posting readiness. |
| AC-408 | FR-420–421; NFR-404 | Given an approved run, when concurrent posting/reversal or a late failure occurs, then one complete balanced result or no business effect exists. |
| AC-409 | FR-422 | Given a posted unpaid run, when exporting or recording settlement, then access is checked independently and payment state requires settlement evidence. |
| AC-410 | FR-423–424 | Given a project plan, when budgets/dependencies change, then revisions survive and circular task dependencies are rejected. |
| AC-411 | FR-425–426 | Given duplicate work intervals or expense sources, when approved across modules, then duplicate payable/billable facts are rejected. |
| AC-412 | FR-427–428; NFR-404 | Given eligible project sources, when billed concurrently, then each unit is consumed once and dated margin reconciles to its stated basis. |
| AC-413 | FR-429–430 | Given a paused/reprioritized ticket, when SLA is evaluated, then frozen policy reproduces its due calculation and earlier breaches remain. |
| AC-414 | FR-431–432 | Given a work order, when dispatched/completed/reversed, then staffing, time, parts, cost and billing eligibility stay consistent. |
| AC-415 | FR-433–434 | Given equipment and due maintenance, when retried or a meter resets, then one attributable occurrence/work order exists with retained due evidence. |
| AC-416 | FR-435 | Given a cost source, when capitalized twice or after stock consumption, then source eligibility prevents duplicated asset/stock value. |
| AC-417 | FR-436–437; NFR-403–404 | Given an asset book, when revised or posted concurrently through its final period, then totals conserve depreciable value and each period posts once. |
| AC-418 | FR-438 | Given disposal or impairment, when posted/reversed, then original cost, accumulated depreciation and gain/loss remain auditable. |
| AC-419 | FR-404–405, FR-439; NFR-407–408 | Given narrow/large-text UI and restarted uncertain drafts, when resumed, then controls remain usable and only the original authorized request is retried. |
| AC-420 | FR-440; NFR-405–406, NFR-409–410 | Given all slice evidence, when readiness is reviewed, then performance/security/build/runtime results and remaining gates are reported separately. |

## Edge cases and failure behavior

- EC-401: Concurrent same-code employee creation → one success and one safe conflict;
  lost response with the original key returns the same created identity.
- EC-402: Changed body/scope reuses a key → no mutation; replay after revocation →
  deny without revealing the prior response.
- EC-403: Backdated employment change intersects approved payroll/time → explicit
  downstream correction, never silent rewriting of consumed history.
- EC-404: Same-day branch transfer → adjacent half-open intervals; destination access
  cannot reveal source-branch private history.
- EC-405: Calendar changed after leave/SLA approval → original policy remains until
  an explicit attributable recalculation.
- EC-406: Interval crosses midnight, clock fold/gap → explicit zone resolution;
  negative or unresolvable duration is rejected.
- EC-407: Leave cancelled after payroll consumption → linked later adjustment.
- EC-408: Negative net pay or deduction over configured cap → block approval/posting
  until allowed policy resolves it; no silent clamping.
- EC-409: Employment ends mid-period → frozen proration/final-settlement basis.
- EC-410: Posting response lost → sealed uncertain request and identical retry;
  optional refresh failure cannot undo a confirmed posting result.
- EC-411: Expense reaches reimbursement and supplier billing → unique source
  consumption rejects duplicate liability; corrections retain lineage.
- EC-412: Part unavailable or concurrent billing consumes remaining time → atomic
  rejection with fresh authorized remaining quantities.
- EC-413: Scheduler repeats or meter rolls over → occurrence identity and explicit
  reading event prevent duplicate maintenance and lost due history.
- EC-414: Disposal races depreciation → serialized state/period checks produce one
  consistent outcome with no post-disposal depreciation absent reversal.
- EC-415: Scope changes during an in-flight private read → discard old-context result,
  clear sensitive cache and lock the old draft.
- EC-416: Provider/rule/mapping unavailable → actionable unavailable state, never
  placeholder success.

## Delivery sequence

| Slice | Deliverable | Dependencies |
|---|---|---|
| W4-01 | Employee directory, employment spells and history | Review this spec/employee contract; verify installed shared foundations |
| W4-02 | Private HR, organization/calendars, reviews, governed account link | W4-01; privacy/retention and self-service contracts |
| W4-03 | Attendance, leave, approvals and corrections | W4-01–02; calendar and overlap contracts |
| W4-04 | Synthetic payroll calculation, posting, payslips and settlement | W4-03; verified journal/period controls and payroll-obligation adapter |
| W4-05 | Projects/tasks, time/expenses, billing and margin | W4-01–02; verified sales/procurement adapters for posting; may progress alongside W4-03–04 |
| W4-06 | Service/SLA, equipment, work orders and maintenance | W4-01–02; common time from W4-05; verified stock/sales adapters |
| W4-07 | Assets, capitalization, depreciation and disposal | Verified procurement/stock/journal provenance; W4-06 for maintenance links |
| W4-08 | Integrated security, load, recovery and acceptance | All slices; fresh provider installation and owner walkthrough evidence |

For each slice: contract/tests → failing critical tests → database/domain →
gateway/native UI/recovery → regression/rendered review → candidate validation →
coordinated development install → authenticated walkthrough. Continue independent
work when a dependent provider is unavailable, recording the specific blocked check.

## Approval and completion

Approval adopts employee/employment first, entity-scoped employment with linked
cross-entity moves, separated operational/private/payroll access, exact time/money,
synthetic payroll configuration and this delivery sequence. Business-specific leave,
pay, SLA and depreciation settings remain versioned setup choices; no default is
silently treated as legally approved.

Before later slices, their detailed contracts must define rule-language limits,
source adapters, journal mappings, settlement/reversal semantics, temporal conflicts
and query bounds at W4-01's level of detail. This specification does not claim those
contracts or implementations already exist.

Completion requires AC-401–420 with evidence, installed-development verification,
real contention/load, native restart and an authenticated owner walkthrough.
Production, statutory and external-execution gates remain separate.
