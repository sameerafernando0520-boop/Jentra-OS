# W4-04 linked source corrections and off-cycle differences

2026-10-02. Synthetic development; unapplied until specifically reviewed and
approved. Extends contract 53. Original payroll, operational revision geometry,
leave debit effects, billed units, payslips and source seals remain immutable.

## Source authority and linked operational impacts

A correction references one posted original employee calculation and one to 200
of its exact sealed claims. Eligibility-only replacements stay within the original
approved paid bound. Geometry replacements append a new approved operational
revision and payable owner using exact whole-second local boundaries, chosen UTC
offsets and breaks inside the original earning period. Attendance, paid leave, direct
project and direct service claims have server-owned approval providers. Project
and service allocations against attendance are already paid through attendance
and are never paid twice. A missing provider fails explicitly.

Every replacement retains the original seal/source digest, current linked revision
and version, previous and replacement eligibility, reason and actor. Correction
preparation requires payroll preparation and the source's management permission;
independent approval requires payroll approval and the source's approval permission.
All commands require current People entitlement, scope and MFA before replay.
Post and reversal recheck source authority before confirmed replay. Private project
and service snapshots require the separate costing permission; an unavailable
linked provider or scope fails explicitly.

Cancelling payroll-consumed leave reverses each unreversed original grant debit,
retires the payable claim and advances the request/account version atomically.
Reversal appends new negative effects against those exact original grants and a
fresh sealed payable owner. If subsequent leave has consumed the restored grant,
reversal fails until its explicit original balance impact is resolved.

Attendance changes freeze every linked project/service operational impact. A
bounded `allocation_changes` list names each entry with retain, geometry or remove;
unknown or duplicate entries fail. Retained geometry must fit the revised payable
segments without truncation. Operational hooks release old allocations before
claim replacement and append immutable revisions and new allocations. Reversal
uses the original frozen impact list, including removed entries with no current
allocation. Cost and bill values reproduce original frozen rates against revised
exact seconds. Reserved billing fails; billed work requires separately posted
original credit proof. Posting never creates a credit or customer invoice.

## Reproduction, concurrency and decisions

Recompute the complete employee calculation with the original frozen rules,
employment period, calendar plan and exact rounding/cap basis. Subtract the last
applied complete rounded calculation, not rounded incremental hours. This preserves
cap crossings, signed differences and chained corrections. The full revised net
cannot be negative. A signed negative difference is an attributable recovery
balance, not silently clamped pay or a new bank instruction.

Entity advisories acquire payroll, projects then service before the employee,
original run and correction row. Every frozen proposal stores the chain sequence and predecessor;
posting rechecks both and each source revision/version. Two concurrent proposals
may be reviewed, but only one current proposal can apply. Stale proposals require
comparison and a new proposal, never a changed sealed retry. Approval binds exact
proposal digest/version and must be independent of preparation.

## Journal, payslip and signed balances

Off-cycle posting uses the verified existing balanced journal/open-period engine
with the original rule expense/liability accounts and original net mapping. It
atomically records signed adjustment balances, immutable difference payslip,
linked source effects, history, redacted audit/outbox and minimal actor receipt.
Posting date cannot precede the original earning period. Zero financial differences
are recorded as a no-journal correction, with explicit status and no fake journal.

Recorded settlements allocate absolute positive amounts to one direction at a
time: payable differences use a bank credit; recovery differences use a bank debit.
Current scoped bank version/currency and exact signed outstanding balances are
checked under locks. Source evidence is unique, and over-allocation fails. Original
settlement reversal restores only its original effects once. Correction reversal
requires no active settlement, no later applied correction and an open explicit
reversal date; it posts the original opposite journal and appends new source
versions, preserving the original payslip and all history. Optional bounded
`current_billing_impacts` names the original seal, current operational revision and
version, selected posted credit lines and named allocation credit choices. Reversal
validates current replacement billing proof independently; it never reuses the
original frozen credit lines. Available current units retire without credits;
reserved units block and billed replacements require fresh posted original proof.
Original regular run
reversal must reject while an active linked correction exists.

## Private native recovery and verification

The native correction workspace uses named original employee/calculation and
sealed-source choices, complete before/after/difference review, independent
actions, named current posted credits, allocation geometry/removal controls,
history, signed balances and bounded pages of 50. Drafts are encrypted
by actor/tenant/entity/branch/correction and expire after 24 hours. Uncertain
requests retain immutable sealed requests and a minimal receipt; expiration clears
private bodies but permits receipt reconciliation. Access loss clears visible
financial data and discards late responses. A confirmed command is retained before
any optional refresh or disk cleanup.

Required checks cover original-rule ties/caps, negative revised net, downward and
restoration chains, stale sources/chain, scope/grants/replay revocation, independent
approval, late failure atomicity, settlement direction/overpayment/reversal and
original-run protection. Candidate role fixtures are not authentication, actual
overlap contention, load, Credential Manager restart or owner signoff.
