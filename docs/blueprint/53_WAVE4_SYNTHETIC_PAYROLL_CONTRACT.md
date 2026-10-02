# W4-04 synthetic payroll and sealed corrections

2026-09-30. Development contract for FR-416–422, AC-407–409 and EC-407–410.
Parent: [Wave 4 specification](40_WAVE4_WORKFORCE_AND_DELIVERY_SPEC.md).
All rates, policies, accounts and fixtures are visibly synthetic. There is no
statutory certification, submission, live bank execution or production activation.

## Exact rules and explanation

An entity owns immutable, dated component rules classified as earning, deduction
or employer cost. A rule has a stable component code, currency, fixed amount,
calculation basis (`fixed`, `hourly`, `earnings_ratio`), an exact rational rate,
proration (`none`, `eligible_days`, `paid_seconds`), rounding mode and precision,
and optional amount cap. Earnings-ratio rules can only be deductions or employer
costs and reference the already calculated earnings total; circular calculations
are prohibited. Fixed/hourly amounts and caps use decimal strings with no more
than six fractional digits, matching the journal provider's numeric precision.
There are no binary floating-point money calculations.

Each line retains the immutable rule/version, basis, exact numerator/denominator,
rounding (`half_away`, `half_even`, `truncate`, `floor`), chosen currency precision
(0–6), cap and final six-place decimal amount. Fixed prorated amounts use exact
eligible/period day or paid/planned second ratios. Hourly rules use approved paid
seconds divided by 3600 and cannot apply a second time proration.
Fixed paid-time proration cannot raise a whole-period fixed amount above 100%;
additional paid hours use a separately configured hourly component. Rule versions
must cover the entire input slice; a change within a period requires explicit
dated slices rather than a silently selected last rate. Paid seconds combine
exclusive approved work and separately attributable paid leave; unpaid leave is
not counted as paid time. More than one slice cannot own the same payable second.
The run explains gross, deductions, employer cost and net by employee and line.
Deduction totals exceeding earnings, missing bases, invalid precision, overflow,
mixed currencies and unavailable providers are explicit failures.

## Frozen runs and approval

A run is scoped to entity and accountable branch, a half-open earning period,
posting date and base currency. The first development posting adapter supports
the entity base currency only; foreign-currency payroll remains an explicit
provider gate until exact FX evidence is implemented. Preparation freezes at most
200 employees and 100 component versions per employee. It references employee
identity/version, dated employment spell and organization assignment, calendar,
approved common work claim/revision, leave request/debit effects and immutable
rule versions. Freeze occurs under employee locks in deterministic UUID order,
followed by the run lock. Posting rechecks the freeze and seals consumed inputs
under those same locks; concurrent correction cannot pass stale evidence. A
cancelled unposted preparation does not permanently consume its source inputs.
Each frozen input has a canonical digest. A native preview is reproducible without
editing the source or accepting client-calculated totals as posting authority.

Approval requires separate payroll approval permission, MFA, an actor different
from the preparer, current exact run revision and its frozen digest. Repreparation
creates a new immutable calculation revision and clears approval. Posting
rechecks source versions, active approved facts, required providers, account
mapping and open period under locks. It never posts a preview with stale inputs.

## Journal and obligation provider

The installed development provider was read on 2026-09-30:
`finance.flow_post_journal(jsonb,jsonb,text,uuid,uuid,uuid)` validates a balanced
base amount, calls `finance.wave3_lock_open_period`, checks active posting
accounts, reserves a journal number and posts immutable journal facts. Its lines
accept signed transaction/base decimal strings and source-line UUIDs. The period
provider locks an active open fiscal period for the posting date. Journal schema
permits additive payroll source types. These inspected definitions are provider
evidence; they do not establish a payroll adapter or load result.

Payroll keeps its own obligations and immutable effects, independent of supplier
AP. Earning expense debits balance net payable and deduction payable credits;
employer expense debits balance employer obligation credits. Control accounts are
explicit liability mappings with a purpose, cannot be supplier-AP control
accounts, and every payroll control line names the exact obligation source UUID.
Posting atomically produces one journal, obligations, payslip facts, input seals,
audit/outbox and actor-scoped command receipt. Any late failure rolls back all
business effects and document numbers. Competing commands can post only once.
Payslips and payroll amounts never enter generic People reads or generic audit.

## Reversal, difference and settlement

Posting does not imply payment. Independently permitted settlement records exact
obligation allocation, currency, amount, date, evidence reference and cash/bank
account. Allocation locks obligations, cannot overpay or repeat source evidence,
posts balanced settlement effects and retains original facts. Reversing settlement
references and reverses only its original allocations once. This is recorded
synthetic evidence; it is not an instruction to execute a bank transfer.

A run reversal rejects outstanding active settlement, closed periods and a prior
reversal, posts linked opposite journal/obligation effects and preserves payslips.
An input consumed by a posted run cannot be silently corrected. A correction
records the original seal and immutable replacement facts, calculates explicit
signed component differences using the original employment/period/rule basis,
and admits them once to an eligible later off-cycle run. It cannot invent a new
employee/rate or erase the prior run. Original frozen inputs remain queryable.

Separate capabilities govern configuration, preparation, approval, posting,
reversal, payslip read, export and settlement. Every command rechecks current
entitlement, scope/capability and MFA before actor-scoped replay. Payroll local
drafts are encrypted and sensitive bodies expire within 24 hours; uncertain
requests retain a minimal receipt. Access loss and late responses clear visible
data. Export freezes a specific payslip revision and digest after a fresh export
authorization check. Files retain no bank/identity fields unless separately
authorized and explicitly needed by the synthetic export contract.

## Required verification

SQL and client checks must prove exact tie rounding, partial employment, changed
rule coverage, caps, paid/unpaid sources, common-time exclusion, independent
approval, stale input denial, atomic late failure, duplicate posting, separate
payroll control attribution, immutable payslips, settlement conservation and
original-only reversal. Two real database connections must prove posting and
settlement contention. The 200×100 bound and read/command p95 require measured
evidence. Native signed-in workflows, Credential Manager restart and owner
acceptance remain separate gates. Source/candidate tests alone close none of them.
