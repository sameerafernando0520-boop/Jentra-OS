# Jentra Employee — employee app blueprint

**Author:** Codex  
**Date:** 2026-10-08 (Asia/Colombo)  
**Status:** Draft for review; proposed Android/iPhone companion app.  
**Reviewers:** Product owner, HR/payroll owner, engineering and design.  
**Dependencies:** [Shared foundation](SHARED_MOBILE_FOUNDATION.md), installed People contracts, approved self-service policies and [mobile design brief](MOBILE_DESIGN_BRIEF.md).

## Context

An employee needs to know today's work, request time off, understand a payslip and contact HR without using Jentra's administrative desktop. The product should make payroll understandable: show the period, earning/deduction components, original and corrected amounts, payment evidence state and an accountable route to question a calculation.

Jentra has governed employee/account links and private HR self projections. Attendance, leave and payroll have substantial candidate implementations, but existing attendance/leave endpoints are staff interfaces. Own payslip access currently lists summary facts; the detailed component and export interfaces require broader payroll rights. This app requires self-specific contracts, not broad permissions added to ordinary employees.

Current backend readiness is recorded in [Wave 4 status](../../development/wave4-status.md), dated October 6. A usable app must wait for its required backend installation, workers and authenticated acceptance. A mobile UI cannot make synthetic payroll legally valid or prove that salaries were paid.

## Users and daily experience

| User | Allowed experience | Excluded by default |
|---|---|---|
| Employee | Own published schedule, attendance, leave, payslips, selected documents, shared reviews and HR cases | Other employees, payroll configuration, salary posting or approvals |
| Delegated supervisor — E2 | Effective assigned-team leave/attendance decisions with separate permission and MFA | Team payslips, private HR documents, self-approval or arbitrary employee access |
| HR/payroll owner — desktop | Link administration, policy decisions, cases, corrections and statutory validation | Access gained merely by installing this app |

One person can be both an employee and a salesman. Each app resolves its own permitted scope; sales access does not grant HR access. Multiple employments must be selected through an authorized employment context rather than merging salaries or leave balances.

## Screens and navigation

Phone navigation: **Home · My work · Leave · Pay · More**. Inbox is reachable from the header. At enlarged text use readable wrapped labels or a More destination rather than shrinking them.

| Screen | Purpose / primary action |
|---|---|
| Sign in and join | Existing Jentra account; see and accept the exact employee link; resolve wrong-link requests with HR |
| Home | Today's published assignment, next shift, request status and private inbox items; one context-sensitive next action |
| My work | Own day/month records, planned versus approved time, source/evidence and attendance exceptions |
| Clock action | Check in/out or break capture when enabled; explain pending versus approved evidence and policy requirements |
| Attendance correction | Select own record, give reason and evidence, submit a request, follow the decision |
| Leave | Own available/used/pending balances, policy summary and request history with expiry/carry information |
| Request leave | Exact dates/portions, paid/unpaid type, balance preview, reason and authorized attachment |
| Pay | Own periods, gross/deductions/net, correction links and separately identified payment records |
| Payslip detail | Full component explanation, quantities/rates/rounding, approved inputs, original history and Ask payroll |
| My profile and documents | Employee-visible identity/contact fields; update requests; classified employee-visible documents |
| My reviews | Shared reviews and acknowledge receipt, with a separate dispute/comment path |
| HR help | Payroll query, attendance query, document request or general HR case with assigned owner and status |
| More | Language/theme, account/session/device controls, help, privacy and permitted E2 destinations |

Do not expose a payroll manager's editor or an employee directory through this navigation. Home shows no fabricated salary countdown, attendance score or balance.

## Functional Requirements

- FR-7101: The app MUST resolve each employee context from the accepted account link and active membership; onboarding MUST NOT create employment, silently match email or grant roles.
- FR-7102: Home MUST show only the selected employee's published work, own pending requests and permitted inbox events, with freshness and meaningful empty states.
- FR-7103: My work MUST show effective employment/organization/calendar context and own planned/approved intervals in the configured zone, including overnight shifts and employment changes.
- FR-7104: If mobile clock capture is enabled, the app MUST record check-in/out/break evidence under the published policy and show Pending verification until authoritative acceptance; raw mobile taps MUST NOT directly become payable time.
- FR-7105: An employee MUST be able to submit an attendance correction request with a reason and permitted evidence, preserving the original record and routing sealed/payroll-consumed changes through linked correction workflow.
- FR-7106: Leave MUST show own policy/version, available and pending entitlement, debits, expiry and carry evidence; an unavailable balance MUST NOT display as zero.
- FR-7107: Leave submission MUST validate own employment, calendar, type, exact dates/portions, overlap and balance on the server and provide an attributable request receipt.
- FR-7108: Employees MUST withdraw an unapproved request only where policy permits; approved/consumed leave MUST use a cancellation request for an authorized approver rather than rewriting or deleting effects.
- FR-7109: Payslip detail MUST show only the linked employee's immutable gross, deductions, employer cost where employee-visible, net and component basis/rate/rounding with original/correction links, period and currency.
- FR-7110: Payslip viewing/export MUST require current self permission, MFA and accepted link; export MUST be independently authorized and delivered privately, with no automatic salary attachment in messages or notifications.
- FR-7111: An employee MUST be able to raise a payroll query against an exact payslip/component revision, with an accountable HR/payroll owner, response and resolution history; a query MUST NOT edit posted pay.
- FR-7112: The profile MUST distinguish employee-editable contact fields from controlled identity/employment fields; controlled changes MUST become HR requests, with validated and audited accepted updates.
- FR-7113: Documents MUST expose only explicitly employee-visible classifications and support authorized own upload/download/request actions; generic self permission MUST NOT reveal confidential personnel files.
- FR-7114: Reviews MUST expose only shared nondraft material to the linked employee; acknowledgement MUST record receipt and MUST NOT imply agreement, pay approval or access to private review history.
- FR-7115: HR cases MUST support type, subject, description, optional private attachment, owner and open/awaiting_employee/resolved/closed history, with resolution feedback and reopen requests.
- FR-7116: The inbox MUST surface leave/correction/case/review/payslip events only to their authorized recipient; opening an event MUST refresh its current subject state.
- FR-7117: E2 supervisor approval MUST require explicit effective team authority, current source version, independent decision where required and MFA; self-approval and unrelated employee access MUST be denied.
- FR-7118: E2 project time and expense submission MUST reuse installed common-time/expense contracts, own assignment, exact amounts and private evidence; duplicate payable time and self-approved expenses MUST be denied.
- FR-7119: Offline entries MUST remain encrypted drafts or raw unverified evidence; users MUST explicitly review and submit online, with current policy/source versions and original command receipts.
- FR-7120: Every destination MUST respect installed provider readiness and entitlement; unavailable payroll/work/document features MUST show the next useful step without inventing facts or granting fallback permissions.

## Payroll clarity contract

Each employee-visible line shows its label/code, period, basis (fixed amount, paid time or earnings ratio), approved quantity/time, applicable rate/version, final exact amount and rounding explanation. Show currency beside totals. A concise summary can round for display under the entity policy, but drill-down and exports preserve the authoritative amount. Do not invent statutory labels for generic deductions.

Distinguish **Prepared**, **Approved**, **Posted payslip**, **Recorded settlement** and **Bank reconciled** only when those facts exist and are authorized. For this release, recorded synthetic settlement must be labelled as development evidence. A posted payslip alone must never show Paid. Real payroll needs separately verified jurisdiction rules, employment policy and payroll-owner sign-off.

If a consumed attendance or leave input changes, the employee sees an original payslip plus a linked later correction, its reason and signed difference. HR resolves the query; no app button recalculates or replaces the posted original.

## Attendance evidence policy

The default blueprint collects no continuous location or biometric data. Optional location is captured only at the clock action and only when the employer publishes a reviewed policy. Record location accuracy and evidence age. A site QR is an additional indicator, not proof of physical presence; GPS and a phone clock are also not inherently trusted. Denied permission or unreliable evidence opens an exception/correction path without blocking unrelated app tasks.

Offline capture retains device time, policy snapshot and capture evidence, labelled unverified. The server records receipt time, validates gaps/overlaps/current employment and applies the approved late-submission policy. The HR-approved canonical interval, not the device timestamp, feeds payroll. Correction of already sealed input follows the existing payroll correction contract.

## Non-Functional Requirements

Shared NFR-7001–7009 apply; these additional targets are proposed.

- NFR-7101: Own payslip, review and document tests MUST return zero protected content for any other employee, including cross-link, pagination, export and late-response cases.
- NFR-7102: Leave preview/submission MUST produce identical results for repeated inputs and reject at least two concurrent competing balance claims without double debit.
- NFR-7103: Clock action feedback MUST distinguish local capture from server acceptance within 300 ms locally and the shared command latency when online; no false approved state is permitted under timeout.
- NFR-7104: Private HR attachments MUST be limited to 10 MiB each and 5 per case, with PDF/JPEG/PNG allowlists, digest checks and server content validation; production retention is a reviewed policy.
- NFR-7105: Required E1 tasks MUST work at 360 logical-px width, both themes and 200% text in English/Sinhala/Tamil on physical Android/iPhone devices, without clipped pay values or unreachable actions.

## Acceptance Criteria

### AC-7101: Governed identity and Home (FR-7101, FR-7102, FR-7120; NFR-7101)

Given an unlinked, linked and revoked employee account, when each signs in or resumes, then only the valid linked context exposes own Home; link acceptance grants no extra capability and unavailable providers present truthful states.

### AC-7102: Own work and capture (FR-7103, FR-7104; NFR-7103)

Given an overnight shift and a phone with wrong time or denied location, when work is viewed and a clock event captured, then published zone meaning is preserved, evidence remains pending until accepted and an approved alternative route is offered.

### AC-7103: Immutable correction (FR-7105, FR-7119)

Given attendance already consumed by payroll and an offline correction draft, when the employee reconnects and submits it, then current policy/authority is rechecked, the original stays unchanged and a linked HR/payroll correction workflow is created once.

### AC-7104: Leave and competition (FR-7106, FR-7107; NFR-7102)

Given a published balance and two overlapping concurrent requests, when both are submitted, then the authoritative rules prevent duplicate debit/overlap and preserve the rejected conflict; the valid request has an attributable receipt.

### AC-7105: Leave withdrawal (FR-7108)

Given one pending and one approved/consumed request, when the employee asks to withdraw each, then the first follows allowed withdrawal and the second creates an approver-owned cancellation request without deleting history.

### AC-7106: Explain and export own pay (FR-7109, FR-7110; NFR-7101)

Given an original payslip and linked off-cycle correction, when its employee authenticates with required MFA and opens/exports them, then exact component basis and signed differences are visible, export is private and a different employee cannot retrieve any component/file.

### AC-7107: Payroll query and HR case (FR-7111, FR-7115; NFR-7104)

Given a deduction the employee questions, when a revision-bound query with an allowed attachment is submitted and resolved, then its accountable owner/history/reopen request remain visible to authorized actors and posted pay is unchanged.

### AC-7108: Profile and documents (FR-7112, FR-7113; NFR-7101, NFR-7104)

Given an editable contact field, a controlled legal-name field and a confidential HR document, when the employee requests updates or file access, then only the allowed contact update is directly accepted, legal-name change goes to HR and the confidential document is denied.

### AC-7109: Reviews and inbox (FR-7114, FR-7116)

Given shared and draft reviews plus a delayed notification, when the employee opens/acknowledges the shared review, then drafts/private history remain hidden, acknowledgement means receipt only and the inbox opens the latest authorized state.

### AC-7110: Delegated extensions (FR-7117, FR-7118)

Given a supervisor of a defined team and a project-assigned employee, when E2 approval/time/expense commands are attempted, then only current delegated subjects are permitted, self-approval/duplicate time are denied and revoked delegation blocks replay.

### AC-7111: Phone accessibility (FR-7102, FR-7109, FR-7116; NFR-7105)

Given each supported phone/language/theme with 200% text and screen reader enabled, when an employee views pay, requests leave and follows a case, then every required action and full amount remains readable and correctly announced.

## Edge Cases

- EC-7101: Employee link is accepted on one phone and revoked on another — server denial applies immediately to further requests; late responses are discarded and the offline lease limits retained nonpayroll references.
- EC-7102: Employment ends or branch/calendar changes during a request — use the effective earning/work dates and current read authority; HR decides any separately approved former-employee payslip policy.
- EC-7103: Leave policy changes, carry expires or another request consumes balance before submission — return changed basis/current balance for explicit review; do not silently alter the request.
- EC-7104: Double clock tap or simultaneous device capture — deduplicate stable event IDs and identify competing interval evidence; do not duplicate payable time.
- EC-7105: Missing checkout, overnight work or overlapping break — mark exception and require authorized interval resolution.
- EC-7106: Payroll provider absent, deduction exceeds earnings or input is stale — disclose the unavailable/rejected payroll state; no client-made replacement payslip.
- EC-7107: Export delivery fails after generation — recover the original authorized export receipt; reauthorize delivery rather than regenerate inconsistent salary facts.
- EC-7108: HR worker or attachment scan fails — retain a clear pending/failed state and retry/case route; do not claim document upload completion.
- EC-7109: Supervisor delegation ends before approval — deny the action and route the still-open request to the current owner.
- EC-7110: A user has multiple tenant employments — select the exact authorized context; no blended leave totals or cross-tenant pay history.

## API Contracts

The following reuse facts come from repository source, not a live October 8 backend probe:

| Existing interface | Existing access / limitation | Mobile use |
|---|---|---|
| `api.people_hr_self` | Accepted own link plus `people.self.view` | Reuse identity projection after installed verification |
| `people_hr_link_inbox`, `people_hr_command` | Governed link accept/reject; HR manages initiation/revocation | Reuse exact target account flow; membership setup remains separately governed |
| `people_hr_reviews`, `review_acknowledge` | Own shared nondraft review access; private full history has broader permission | Reuse permitted projection and acknowledgement |
| `people_payroll_self_payslips` — candidate | `people.payroll.payslip.self`, link and MFA; summary without lines | Reuse only after installation; add own detail |
| `people_payroll_payslip`, payroll export — candidate | Broad payslip view/export; export content is frozen JSON | Do not grant to employees; add own detail/export and controlled PDF rendering |
| Attendance/leave staff RPCs — candidates | General view/manage/import/approve; employee ID selectors | Add self-only reads, capture/requests and separate cancellation request |

Source contracts: [private HR](../../../supabase/migrations/20260929224939_wave4_private_hr.sql), [attendance](../../../supabase/migrations/20260928082234_wave4_attendance_intervals.sql), [leave](../../../supabase/migrations/20260928083449_wave4_leave_ledger.sql), [payroll](../../../supabase/migrations/20260930070000_wave4_synthetic_payroll.sql).

Proposed capabilities: `people.attendance.self.view`, `.self.capture`, `.self.request_correction`; `people.leave.self.view`, `.self.request`, `.self.withdraw`; `people.payroll.payslip.self.detail`, `.self.export`; `people.hr.documents.self.view`, `.self.submit`; `people.hr.cases.self`; `people.team.leave.approve`, `people.team.attendance.approve`. Naming and implied-capability review is required; new roles must not inherit staff-wide grants. Existing MFA requirements remain in force unless a separately approved narrower policy changes them.

Use `Scope`, `Page`, `Command`, `Receipt`, `Result`, `Decimal` and `UTCInstant` from the [shared contract](SHARED_MOBILE_FOUNDATION.md). No self command accepts an authoritative employee/user ID.

```typescript
interface LeaveRequestInput {
  leaveTypeId: string; policyVersion: string;
  portions: { civilDate: string; portionCode: string }[];
  reason: string; attachmentIds: string[];
}
interface AttendanceCaptureInput {
  captureId: string; kind: "in" | "out" | "break_start" | "break_end";
  deviceObservedAt: UTCInstant; policyVersion: string;
  locationEvidenceId?: string; siteEvidenceId?: string;
}
interface EmployeeSelfService {
  home(scope: Scope): Promise<Result<EmployeeHome>>;
  page(section: "work" | "leave" | "pay" | "documents" | "reviews" | "cases",
       scope: Scope, cursor?: string): Promise<Result<Page<SelfItem>>>;
  detail(section: string, subjectId: string): Promise<Result<SelfDetail>>;
  submit(intent: EmployeeIntent, command: Command<EmployeePayload>): Promise<Result<Receipt<SelfDetail>>>;
  exportOwnPayslip(command: Command<{ payslipId: string; revision: string }>): Promise<Result<Receipt<OwnExport>>>;
}
```

Proposed transports: `POST /rest/v1/rpc/employee_mobile_home`, `employee_self_page`, `employee_self_detail`, `employee_self_command`, `employee_self_export`, and E2 `employee_team_command`. `EmployeeIntent` is a discriminated allowlist of capture, correction_request, leave_submit, leave_withdraw, leave_cancel_request, contact_update, controlled_profile_request, document_reserve/finalize, review_acknowledge, case_submit/reply/reopen and E2 time/expense submission. Each intent has a separately validated payload; there is no arbitrary action string reaching general staff RPCs.

`EmployeeHome` contains linked-context label, own published work, requests and inbox references. `SelfItem/SelfDetail` are discriminated work/leave/payslip/document/review/case records matching the models below; each is a redacted employee projection. `OwnExport` contains frozen revision/digest, format and a private delivery reference. Server adapters must validate leave portions against the exact existing day/seconds contract. Errors add `EMPLOYMENT_INELIGIBLE`, `LEAVE_BALANCE_INSUFFICIENT`, `WORK_INTERVAL_CONFLICT`, `PAYROLL_INPUT_SEALED`, `DOCUMENT_NOT_EMPLOYEE_VISIBLE` and `DELEGATION_EXPIRED` to the common errors; source conflicts return a reviewable changed basis.

## Data Models

| Entity | Fields / types | Constraints and source |
|---|---|---|
| Linked employee context | link/employee/employment/entity/branch IDs, effective dates, calendar/zone/version | Existing governed link and employment; server-resolved |
| Own published schedule | assignment/calendar IDs, date, UTC intervals, breaks, version | Projection of published effective facts; no invented shift roster |
| Mobile attendance evidence | capture ID, kind, device/server UTC, policy version, optional location/site references, verification state | New immutable evidence; unique capture; does not directly approve work |
| Attendance correction request | id, own entry/seal reference, reason, evidence IDs, expected version, status/history | New request around existing correction effects; authorized owner resolves |
| Own leave projection/request | policy/grant/request IDs, version, dates/portions, paid/unpaid, exact balance/debit, state | Reuse leave ledger; server validates overlap/expiry/conservation |
| Own payslip detail | payslip/run/employee IDs, period, currency, decimal totals/lines, basis/rate/rounding, correction refs | Immutable payroll facts; self-filtered detail is new |
| Own payslip export | id, payslip revision, digest, format, recipient/actor, expiry/delivery ref | New self-authorized delivery; frozen source, not generated salary facts |
| HR case / payroll query | id, own subject/revision, type, text, owner, status, private attachment refs, events | New accountable case; immutable event history, controlled reopen |
| Profile change request | id, field allowlist, proposed value, current version, decision/history | Controlled employment/identity changes remain HR-owned |
| Employee-visible document | document/employee IDs, classification, visibility, digest, retention policy, scan state | New visibility contract around private document storage |
| Shared review | review ID/version, permitted content, acknowledgement UTC/actor, response refs | Existing own nondraft projection; no private history |
| Supervisor delegation | actor, team/subject scope, dated assignment, capabilities, version | New effective authorization; never inferred from job title |
| Own time/expense — E2 | assignment/project IDs, intervals or decimal amount/currency, evidence/version | Reuse project/time/expense contracts; distinct approval authority |

Inbox, device, local draft, recovery and attachment models are defined in the shared foundation. Server location evidence, if enabled, needs bounded coordinates/accuracy/capture time, explicit purpose and reviewed retention; it must not become a continuous employee-location record.

## Out of Scope

- OS-7101: Employee payroll editing, salary-run approval/posting and bank transfer — HR/payroll/finance controls remain separate.
- OS-7102: Recruitment marketplace, biometric attendance, automatic employee scoring and continuous tracking — not needed for employee self-service.
- OS-7103: Broad private-document access, unrestricted employee search and team salaries — incompatible with own-subject access.
- OS-7104: E2 supervisor/time/expense functions in the E1 release — separate extension gates apply.
- OS-7105: Automatic former-employee access and statutory certification — owner policies and real payroll validation remain required.

## Workflow walkthroughs and business measures

**Normal design walkthrough:** Employee accepts HR's exact account link, signs in with own permission, opens Leave, previews a permitted day, submits online, follows the supervisor/desktop decision in the inbox, and sees updated authoritative balance. HR later posts a payslip; employee opens its component breakdown with MFA and can raise a query. No broad HR grant is needed.

**Exception design walkthrough:** A missing checkout is discovered after payroll posting. The employee submits correction evidence; HR verifies it, the sealed source follows linked correction rules, and a later off-cycle payslip shows the difference. A network timeout reuses the original command receipt; the original pay is preserved.

Measure time to complete a leave request, HR case response age, payroll-query resolution time, repeated requests caused by uncertainty and failed own-subject journeys. These are proposed measures, with pilot baselines to be captured; no current improvement percentage is claimed.
