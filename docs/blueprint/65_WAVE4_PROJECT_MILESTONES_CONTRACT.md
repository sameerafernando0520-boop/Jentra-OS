# Governed project milestones

2026-10-04 additive candidate for FR-423/427/428. No installation or plan/role
grants. The projects module owns milestone terms, dated immutable revisions,
independent decisions, eligible whole billing units and recovery.

A milestone belongs to one project/entity/branch and active billable customer.
Preparation selects a named task from the current approved plan, an eligible
named accountable employee, a due date within project/task dates, explicit exact
commercial amount at project precision, commercial terms, payment terms and
payment days (0–365), and governed completion evidence reference. The original
customer/currency/plan/task/owner labels and terms remain frozen. No private cost
or compensation enters milestone APIs or generic telemetry.

Create/correct make a draft immutable revision; submit freezes its identity.
An independent reviewer approves or rejects the exact submitted digest. Approval
requires the same current approved plan, latest task progress exactly 10000,
eligible employment in the accountable branch at the due date and retained
completion evidence. Approval creates one whole immutable billable unit, quantity
1, source kind milestone, source ID the approved revision, exact amount, currency
and source digest/version; it never implies invoice/payment or creates a journal.
Finance uses installed sales commands with source reservation/consumption and
milestone payment terms. Current availability/status must be revalidated.

Correction/cancellation cannot erase original terms/decisions. Available units
are cancelled atomically before a new draft; reserved or billed units block with
an explicit billing impact requirement. A credit alone cannot revive a consumed
unit. Superseding a project plan cannot approve a stale pending milestone; an
already approved unit retains its original governed eligibility evidence.
Closure must resolve draft/submitted/rejected milestones and unbilled units.

Every API rechecks entitlement, operational scope, action permission and MFA
before actor-bound replay/receipt. Tables force RLS and reject direct client access.
Commands acquire project entity advisory, sorted employee, project and milestone
locks. API reads page at 50; typed money strings reject floats and precision loss.
Native UI uses named project/task/employee choices and explicit lifecycle actions.
Encrypted recovery seals original request before issue, freezes uncertainty,
durably acknowledges exact known receipts, and requires explicit stale comparison.
Epoch changes clear plaintext, including open pickers, and prevent obsolete
authorization/sealing/read responses from entering a replacement view.

Required candidate evidence includes stale plan/progress, independent decisions,
scoped receipt/replay/MFA/revocation/RLS, whole unit conservation, reserved/billed
guards, closure and late atomic failure. Actual API projections, native keyboard,
encrypted restart and themed/large-text previews are separate client evidence.
Persistent installation, authenticated acceptance, true contention/load,
Credential Manager restart and owner signoff remain separate gates.
