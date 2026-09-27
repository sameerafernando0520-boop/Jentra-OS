# New-session prompt: complete remaining Wave 4 development

Prepared 2026-09-26. Copy this prompt into a new session working in the same
repository. The checkpoint below is dated evidence; refresh it before making
current-state claims.

Continue Jentra OS and complete **all remaining approved synthetic Wave 4
development**, including the unfinished parts of W4-01/W4-02 and W4-03 through
W4-08. Implement working verticals and their verification, rather than stopping
after an audit, plan, schema, mock screen or one successful slice. Continue across
context compactions with a written checkpoint. Keep developing independent slices
while an installation, provider, sign-in or owner-acceptance gate is pending.

Workspace: `C:\Users\sheha\Desktop\Jentra OS`.
Development Supabase project: `xpdoufauvrbdmxgngetv`.
Platform: Flutter Windows first; PowerShell. At prompt preparation the checkout
was on `main`, HEAD `b51eec0dce3a73236f3460325394a4dc19e7a2ce`, clean before this
prompt was added. Inspect the actual checkout again; do not assume it stayed clean.

## Authority and preservation

- Work solo. Preserve all concurrent source, tracked/untracked files, existing
  migrations, acceptance evidence and running applications. Make module-owned
  changes and minimal shared integration edits, rereading shared files before
  editing. Do not stage, commit, push, reset, clean, stash or switch branches.
- Scope is synthetic Wave 4 development. Preserve Wave 3 ownership and its
  stock-opening acceptance data, setup, identities, roles, periods, sequences,
  authentication, local stores and binaries, including `ACPT-*` fixtures. Wave 4
  completion does not close Wave 3 gates. Do not install another owner's Wave 3
  candidates to unblock yourself.
- Employee and calendar development installations were already explicitly
  approved and completed. Verify them; do not reinstall them or request the same
  approval again. Applied migration files are immutable; fixes are additive.
- For a new persistent migration or storage/server deployment, first finish the
  concrete contract, implementation, rollback/security checks, client checks and
  review artifact. Follow the established owner-approval boundary for that
  specific installation; show the exact scope and risk, then install and verify
  once approved. Keep unrelated development moving while approval is pending.
- Authentication and MFA are user-managed. Do not ask for passwords/codes, extract
  tokens, automate sign-in, or fabricate an owner audit through SQL impersonation.
  Rollback SQL role fixtures are test evidence, not authenticated runtime proof.
- Production, real HR/payroll data, statutory certification/submission, live
  payroll/bank execution, provider activation and external messages are outside
  this task. Use visibly synthetic fixtures and versioned development settings;
  do not invent legally approved rates or business policies.

## Read and audit first

Read applicable `AGENTS.md` instructions and these repository documents:

1. `docs/development/wave4-status.md`.
2. `docs/blueprint/01_ARCHITECTURE.md`, `03_DATA_SECURITY.md`,
   `04_DESIGN_SYSTEM.md` and `05_TEST_AND_DELIVERY.md`.
3. `docs/blueprint/40_WAVE4_WORKFORCE_AND_DELIVERY_SPEC.md`.
4. `docs/blueprint/41_WAVE4_EMPLOYEE_FOUNDATION_CONTRACT.md` and
   `42_WAVE4_PRIVATE_HR_ORGANIZATION_CALENDAR_CONTRACT.md`.
5. `docs/verification/wave4/employee-install-review-20260925.md`,
   `employee-native-acceptance-20260926.md`,
   `employee-contention-20260925.md`, `calendar-candidate-20260926.md` and
   `calendar-client-20260926.md`.
6. `docs/development/remaining-wave3-status.md` and the actual provider contracts
   needed for journal/period, stock, sales, procurement, tax and settlement
   integration. Read their installed definitions rather than assuming candidates
   are deployed.

Inspect the implemented People domain, gateways, encrypted stores, controllers,
screens and tests under `packages/jentra_domain`, `packages/jentra_platform` and
`apps/jentra_desktop`. Use the installed Supabase tools for a read-only refresh of
project health, ledger, API definitions/grants, RLS, subscriptions/capabilities,
provider source-type support and advisors. Use Plugin Management only when needed
to discover relevant installed capabilities; plugin installation is not a feature
deliverable.

Create a requirements gap matrix covering **FR-401–440, NFR-401–410, AC-401–420
and EC-401–416**. Distinguish working/verified, partial, missing, dependency-gated
and manual acceptance. Then implement; the matrix is not the endpoint. Allocate
unused contract document numbers after checking concurrent work.

## Existing checkpoint to preserve

**W4-01 employee foundation:** source implemented and installed in development as
`supabase/migrations/20260925181927_wave4_employee_foundation.sql`. Employee
identity, dated spells/branch assignments, immutable events, scoped APIs,
`/people/employees`, exact-request encrypted recovery and UI exist. Recorded
installed-schema verification passed 49 rollback assertions. Native authenticated
acceptance, real contention and Windows Credential Manager restart remain open.
Historical corrections touching downstream consumption remain gated until their
impact contract and contention proof exist.

**W4-02A calendar-version vertical:** source implemented and installed as
`supabase/migrations/20260926082441_wave4_calendar_versions.sql`. Preserve this
ledger-aligned filename. SQL SHA-256:
`857B26043339D3802A0D9421D134B70F1A114428E3232E73B47E509D295A1244`.
It provides three forced-RLS tables, five scoped APIs, explicit calendar
permissions, immutable versions/history, `/people/calendars`, create/publish/rename
and encrypted retries. Recorded checks passed 65 installed SQL assertions and
53 focused client checks: 13 domain, 14 platform and 26 desktop, including employee
regressions. Analysis, rendered previews and an isolated Windows build passed.
These do not establish signed-in acceptance or real contention.

Use `supabase/tests/build_employee_candidate.ps1 -Installed` and
`supabase/tests/build_calendar_candidate.ps1 -Installed` against their installed
schema; the default builders inject DDL and are inappropriate there. SQL checks
must end in `rollback;` and leave no fixtures or ledger changes.

Calendar versions currently describe **civil/local patterns only**. IANA zone,
UTC instant resolution, DST ambiguity/gap handling, organization hierarchy,
manager history and employee calendar assignments are unfinished. Private HR,
reviews and account links are unfinished. W4-03–07 are specified but not yet
implemented; integrated W4-08 evidence is open.

Last database verification recorded on 2026-09-26: 36 migrations, latest
`20260926082441`; seven People tables and ten scoped APIs; original
starter/growth/scale plans have People disabled; calendar role grants were not
automatically added. Dedicated plan `w4_employee_synthetic` has People enabled
and zero subscribers. Verify all of this again before acting.

The user selected a separate empty test account and reported creating a workspace,
but the last development query found no `w4-employee-synthetic` tenant/subscription.
The existing acceptance lab must remain unchanged. Reconcile the actual app
target and signed-in bootstrap result, rather than treating the report as database
proof or inventing a tenant/owner. Intended synthetic setup:

- Workspace `W4 Employee Synthetic Lab`, slug `w4-employee-synthetic`.
- Entity `W4 Synthetic Operations`, code `W4OPS`.
- Branch `Head Office`, code `HQ`.

Once its real identity and owner audit are verified, use the authorized setup
workflow to attach only that tenant to the dedicated synthetic plan and give its
operators the exact required capabilities. Calendar management requires
entity-wide authority and MFA. If bootstrap still needs the user, request the
smallest missing fact/action once and continue independent development.

## Complete the remaining slices in dependency order

1. **Finish W4-02A organization and calendar consumption.** Implement dated
   departments/parents and manager relationships with self/cycle prevention at
   every affected boundary, including competing hierarchy changes. Organization
   assignments must fit inside employment spells and authorized branch intervals,
   reference an immutable calendar version, and serialize with employee timeline
   commands. Transfer/end/rehire must preserve compatible history or return an
   explicit impact-required result. Implement IANA date-to-instant resolution:
   reject nonexistent local times, require a selected UTC offset for ambiguous
   times, and retain local/UTC resolution evidence. Cover overnight/week-wrap,
   holidays, gaps and consumed-version changes. Missing assignment is explicitly
   unconfigured, never an inferred default. Finish native workspaces and recovery.

2. **Finish W4-02B private HR, documents, reviews and account links.** Separate
   operational/private/payroll contracts and capabilities physically and in
   response allowlists. This increment is bounded to the approved private-contact
   profile; compensation, bank, health and government-identity fields are outside
   that profile. Build a separate private document bucket with trusted-server
   per-document authorization; `jentra-attachments` and generic `core.files.*`
   access are unsuitable. Install/test a versioned retention policy and
   purge/redaction worker before accepting private content, with legal holds and
   distinct export/erasure authority. Synthetic expiry is the explicit 30-day
   development cleanup choice, not a legal claim. Review commands must retain
   attributable revisions, independent eligible reviewers, restricted visibility
   and acknowledgement of receipt without agreement or pay effects. Account links
   use an exact active membership/user ID, HR initiation with MFA, target-user
   acceptance within 24 hours, uniqueness, expiry/revocation and separate
   self-service projections. Email matching never establishes identity, creates an
   account, sends an invitation or grants roles.

3. **W4-03 attendance and leave.** Write detailed contracts, then implement raw and
   manual attendance, exact UTC durations/breaks, correction history, duplicate
   import protection and approvals. Establish common work-interval ownership for
   attendance, project and service time before separate modules can double count
   it. Implement versioned eligibility/accrual/carry-forward/expiry policies and
   append-only leave balances, independent decisions, concurrent balance locking,
   overlap/conflict resolution and cancellation of original effects. Seal
   payroll-consumed inputs; later changes create linked differences.

4. **W4-04 synthetic payroll.** Implement bounded effective rule/component
   contracts, exact proration/rounding/limits, frozen inputs and reproducible
   calculation evidence, revision-bound independent approval, obligations,
   immutable payslips and atomic journal posting through the verified existing
   engine. Payroll control attribution is distinct from supplier AP. Include
   off-cycle corrections, original-effect reversal and explicit period/settlement
   restrictions. Payslip/export/recorded settlement permissions are separate;
   posting does not imply payment. Reconcile recorded settlement and reversals to
   payroll obligations. Reject stale inputs, unsupported mappings and unresolved
   negative-net/cap conditions rather than silently clamping.

5. **W4-05 projects, tasks, time and expenses.** Implement project terms, customer,
   currency, accountable branch, budgets, milestones and resource capacity;
   versioned task dependencies with cycle rejection; eligible employment/time
   approvals using the common interval contract; exact expense/tax/FX evidence
   and governed attachments. Prevent duplicate reimbursement/supplier liability.
   Consume approved unbilled units/milestones once through existing sales commands
   using frozen rate/tax basis. Provide authorized as-of cost, commitments,
   revenue, budget and margin with source drill-down and governed closure.

6. **W4-06 service, equipment and maintenance.** Implement tickets/triage,
   contracts/warranty and explicit equipment identity. Freeze SLA calendar/policy
   versions, pause/resume and due-time evidence; reprioritization retains earlier
   breaches. Dispatch validates scope, eligible employment, availability and
   equipment. Work orders support acceptance/work/completion, customer confirmation
   or reasoned exception and configured independent closure. Reuse common time
   and existing reservation/issue/return commands for parts. Preserve cost and
   billing eligibility without implying invoice/payment. Calendar/meter preventive
   maintenance must have one work order per occurrence, with reset/rollover,
   deferral and retry lineage. Equipment linking never implies capitalization.

7. **W4-07 fixed assets.** Implement verified procurement/stock/opening source
   eligibility, cost components, register/location/custodian/in-service history
   and capitalization without duplicate stock/asset value. Implement versioned
   books and exact depreciation schedules, residual/life/method/conventions,
   deterministic final rounding, prospective changes and governed corrections.
   Posting locks asset/book/period, rejects stale/closed-period/disposed state and
   uses existing journals once. Include original-effect reversal, transfers,
   impairment, configured revaluation and disposal with proceeds/gain/loss
   evidence. Serialize depreciation/disposal races and link maintenance where
   the actual provider is available.

8. **W4-08 integration and acceptance.** Close cross-module security, source
   ownership, correction, recovery, accounting and temporal gaps. Reconcile each
   acceptance criterion to actual evidence and an owner walkthrough. W4-05 may
   progress while W4-03/04 integration is gated; W4-07 can progress against verified
   finance providers. Verify dependencies before enabling authoritative actions.
   Missing providers get actionable unavailable states while their integration
   source and tests are completed; they do not produce fabricated success.

## Required implementation and verification standard

For each slice: detailed contract and critical failing tests → additive SQL/exact
domain → typed authenticated gateway → native UI/encrypted recovery → focused
regressions and rendered inspection → rollback candidate validation → concrete
installation review/authorized install → installed checks → authenticated evidence.

- Enforce actor, tenant/entity/branch, current membership/entitlement/capabilities,
  expected versions and required MFA on every named command and replay. Keep
  tenant tables RLS-protected, privileged search paths empty and grants explicit.
  Composite references, lock order and uniqueness must prevent cross-scope or
  duplicate consumption. Preserve API-only base-table denial where designed.
- Commit business changes, actor-scoped receipt, redacted audit and required
  telemetry/outbox atomically. Recheck access before returning a replay. Test
  changed bodies/scopes with a reused key, revocation before replay, stale
  versions, independent approval, injected late failure and original-effect
  reversals. No partial posting or destructive history rewrite.
- Use canonical decimal strings and exact Dart/BigInt arithmetic for money,
  rates/quantities; integer seconds for durations; half-open dated intervals and
  recorded/effective timestamps. Define precision, rounding and conservation.
  No `double`/`num` financial totals or premature fractional-hour rounding.
- Native workspaces need loading/error/empty/populated/denied/unavailable states,
  named scoped pickers, permitted actions, filters, bounded history, keyboard/focus,
  validation and recovery. Private values never enter directory/search/logs,
  generic audit/outbox/notifications, error messages or content URLs in drafts.
- Encrypt drafts by actor/tenant/entity/branch/aggregate. Preserve the exact sealed
  uncertain request across restart; do not silently replace it. Conflicts require
  comparison/replacement. Clear visible data on sign-out/context/access loss;
  discard old-context in-flight responses. A confirmed command survives an
  optional subsequent read failure.
- Run meaningful domain/invariant, SQL security/atomicity, gateway response,
  encrypted recovery and native UI tests, relevant analyzers and formatting.
  Inspect rendered light/dark, both densities, keyboard/focus, 1024×720 through
  1920×1080 and 200% text. Reach all controls and fix clipping; a passing golden
  comparison alone is not visual inspection or authenticated acceptance.
- Use a short isolated Windows source copy containing the actual current source
  changes. Exclude generated build/plugin directories such as
  `windows/flutter/ephemeral`, local authentication stores and secret configuration.
  Configure native acceptance separately without exposing secrets. Do not overwrite
  or interrupt the existing acceptance app. Compilation and real Credential
  Manager restart are separate evidence.
- Real contention requires two genuinely overlapping separate sessions for
  employment/hierarchy, leave, payroll, billing, stock parts and depreciation.
  Serialized connector calls and sequential pgTAP are not contention proof. If
  the available tooling cannot produce overlap, finish a runnable protocol and
  state that precise external gate without claiming a pass.
- Document workload and measure read p95 against 500 ms and ordinary-command p95
  against 1.5 s. Default pages ≤50, directory maximum 200; private/review history
  maximum 50. Proposed payroll bounds are 200 employees/run and 100
  components/employee; enforce or explicitly refine the contract. Oversize jobs
  fail before effects; long jobs expose bounded progress/failure.
- Refresh live ledger/advisors/provider grants before installation and verify
  after it. Record SQL hashes, assertion counts, commands/results, scope, source
  revision and no residual rollback fixtures. Review advisor findings within
  scope; do not broadly change authentication/settings to quiet unrelated findings.

## Deliverables and stopping rule

Maintain `docs/development/wave4-status.md`, the FR/NFR/AC/EC gap matrix, detailed
slice contracts and `docs/verification/wave4/` evidence as implementation proceeds.
Provide working source, additive migrations/builders, tests, native workspaces,
recovery and verified provider adapters for every remaining slice. Review your own
final changes and fix material defects before handoff.

Report source completion, automated tests, rollback candidate checks, installation,
Windows build, rendered review, real contention/load, authenticated runtime,
Credential Manager restart and owner acceptance separately. Do not declare Wave 4
complete while required evidence is missing. If a gate genuinely needs the owner
or an unavailable provider/tool, identify the exact action, already-completed work
and remaining check; continue all independent authorized work first.

Start now with the fresh audit, then finish organization/calendar instant
resolution and continue through the remaining dependency order. Do not stop after
restating this prompt or finishing only the next feature.
