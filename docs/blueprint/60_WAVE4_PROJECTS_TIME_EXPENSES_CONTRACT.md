# W4-05 projects, common time, expenses and billing

2026-10-01. Synthetic development contract for FR-423–428, AC-410–412.
This document describes required behavior; it does not claim installation or
completion. Preserve all Wave 3 provider/acceptance ownership.

## Project planning and authority

Projects belong to one tenant, entity and accountable branch. Freeze customer
identity for billable terms, currency, dates, manager, commercial basis and budget
revision. Customer/product/account choices must be named and scoped; no arbitrary
UUID or JSON forms. Dated budget/resource/term revisions retain their originals
and independent approval. Current entitlement, scope, action permission and MFA
precede every privileged command and receipt/replay lookup. Cost visibility is
separate from project/time/billing visibility. No compensation, bank or private HR
fields are joined into operational or generic responses.

Bound a project task graph to 200 nodes, with at most 50 dependencies per node.
Reject duplicate nodes/edges, self-dependencies, foreign-project references,
cycles, invalid date windows and dependent completion before prerequisites.
Retain dated owners, planned seconds, progress and capacity calendar/organization
basis. Resource approval rechecks employment, branch assignment and current
published calendar resolution; no estimated capacity is presented as approved.

## Common interval ownership and time

Time retains employee, project/task or work order, civil service date, whole UTC
seconds, ordered breaks, original calendar/organization basis and immutable
revisions. Use the W4-03 `people.work_claims`, segments and allocations contract.
Approval either allocates an eligible approved attendance segment or creates a
direct project/service claim; it never creates a second payable claim over an
existing attendance claim. Shared allocation exclusion protects the same payable
segment across projects and service. Employee locks precede project/time locks;
multi-employee operations sort UUIDs. Approvers must be independent and eligible.
Correction/cancellation never rewrites a revision and must reject consumed or
payroll-sealed sources without a complete linked-impact path.

Rate × payable seconds / 3600 uses integer rational arithmetic and published
half-even precision; no fractional-hour intermediate. Project internal cost rates
are explicitly approved synthetic costing settings, independently visible from
customer bill rates. They do not infer an employee's payroll compensation.

## Expenses, evidence and obligations

Expense revisions retain original net/tax/gross currency amounts, tax definition
and version or an explicit no-tax reason, versioned exchange-rate evidence,
service date, named purpose/accounts, governed evidence references and allocation
order. Net plus tax must equal gross. Convert original gross and net once with
the frozen exact rational rate and precision; base tax is their difference.
Record any tax conversion rounding residue explicitly. Allocations use cumulative
half-even rounding in their frozen order, with at most 50 positive weights and
exact conservation of the converted original total.

Evidence access must recheck the expense, branch and attachment permission. A
private provider/installation gate must produce an unavailable state, rather than
accepting an unprotected URL or pretending a generic file grant is sufficient.
Independent expense approval freezes the source, mappings, rate/tax basis and
allocations. Reimbursement and supplier liability share one authoritative source
ownership claim. Posting/recorded settlement/reversal are distinct; no bank
execution is implied. Do not install the other owner's supplier AP candidates.
The live supplier-bill provider remains absent and must remain visibly gated until
its installed contract can be verified. Reimbursement can be developed separately
with its own exact control attribution and original journal effects.

## Exact billing units and installed sales integration

An approved time interval, expense allocation or eligible milestone is a whole
immutable billing unit, quantity exactly `1.000000`. Its price is its approved
exact amount at the project/entity's published precision. Time evidence retains
the original integer seconds and rational hourly rate. This avoids rounding one
second to a six-place fractional hour inside the installed sales quantity API.
Partial time billing requires separately approved interval splits before any
reservation/consumption; there is no silent duration truncation. Expense billing
prices are explicit commercial terms, not an inferred reimbursement amount.

Batch bounds are 200 whole units. Source IDs/versions/digests, customer, currency,
document date, service product/UOM, exact price and tax basis are frozen. Reserve
sources under sorted source locks before draft preparation. Use installed sales
upsert/workflow/post commands; do not create a parallel invoice or bypass its
approval, account, tax, exchange-rate, period or customer locks. Current verified
sales pricing supports non-stock direct invoice lines and positive exact quantity;
its source metadata alone does not prevent project double billing.

The module therefore owns immutable invoice/source links and a protected posting
intent tied to the current transaction. Linked invoice financial fields/lines
cannot be altered through ordinary sales editing. Direct sales posting must be
blocked unless the module's protected intent exists; a client-settable GUC is not
authorization. The module wrapper revalidates sources and calls the installed
post API, then consumes the exact whole units atomically with its receipt/outbox.
Failure rolls back invoice effects, source claims, numbering and journals. A
second batch cannot consume/reserve a unit again. Sales workflow decisions remain
attributable to their actual authorized actors. A credit does not automatically
release an original source for rebilling; a governed adjustment keeps its lineage.
Zero-value units retain quantity/evidence without implying a payment or income.

## Margin, closure, recovery and evidence

Task progress belongs to its immutable plan version. A revised dependency graph
starts with explicit zero progress; completion is never silently inherited from
an older plan. Plan approval requires the project's current prepared version.
An independent rejection may resolve an older pending basis using its original
digest and the current project version, preserving its original decision history.

Authorized as-of views distinguish posted revenue/credits, approved cost,
commitments, budgets, billable/unbilled units and recorded obligations. Every amount
states currency/date and provides source drill-down. No unposted invoice is
revenue. Closure resolves active tasks, pending changes, draft billing batches,
unbilled approved units and open expense liabilities explicitly; a reasoned
non-billable decision is immutable and does not hide internal cost.

Implement API-only forced RLS tables; typed decimal/UUID/date/version projections;
named paged pickers; native planning/time/expense/billing/margin workspaces;
permission-aware actions and complete encrypted recovery. Seal the exact request
before issuance, reconcile unknown results by original actor/action/key, retain
known confirmation before optional reads, clear plaintext on revocation and
require explicit current-version comparison before editing after conflict.

Verification must cover actual API-to-client projections, source conservation,
cycles, shared work overlap, expense ownership, stale/closed-period/late-failure
posting, direct linked-invoice protection, both themes/densities/200% text and an
isolated Windows build. Real separate-session contention, measured load,
authenticated native/MFA, Credential Manager restart and owner signoff remain
separate gates. New persistent database/storage/server installations require
their own completed review and specific owner approval.
