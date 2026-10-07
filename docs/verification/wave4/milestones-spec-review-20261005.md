# Milestone Spec review

2026-10-05. Root reviews the service agent's milestone implementation against
contracts 40/65 and FR-423/427/428, AC-410/412, EC-402/412/415. Root implemented
only shared application routing/provider wiring. This review covers actual SQL,
typed projections/gateway, controller, encrypted confirmation helper and tests;
it is separate from the implementer's own review and from installed acceptance.

No additional actionable source finding was identified in this snapshot.

Preparation binds a current independently approved plan, scoped task, dated
eligible named owner, due date inside project/task ranges, exact amount at project
precision and explicit customer/payment/commercial terms. Immutable revision
records preserve original customer/currency/labels and superseded terms. Approval
requires a different actor, the submitted digest, the still-current plan and the
latest task progress of exactly 10000. The approval event retains its eligibility
basis and creates a single whole billing unit, without posting an invoice or pay.

The finance adapter identifies the actual approved historical revision and
matching approval event/source version/digest/amount, preserving frozen payment
days when it calls the existing sales engine. Available correction/cancellation
terminally cancels the original unit; reserved/billed units require explicit
billing impact resolution. Closure denies unresolved milestones or unbilled
units. Source row status under shared project serialization remains authoritative.
Neither a credit nor a later master-data change revives a consumed unit.

Tables force RLS with no direct authenticated/service-role grants. Only four
named APIs have authenticated execute access; owner helpers are protected.
Scoped entitlement/capability/MFA checks precede actor-bound receipt/replay.
Reads/history are bounded at 50 and scoped through the owning project. Typed
responses reject foreign scope, missing fields and numeric money. Named task and
employee selection and immutable detail/history preserve an understandable
operational basis without exposing private cost.

The controller binds asynchronous authorization, reads, pickers, local sealing
and responses to the current authority/form epochs. Known responses are retained
before acknowledgement persistence; minimal encrypted confirmations include a
canonical digest of the complete original envelope. Altered body/timestamp with
reused identity cannot borrow confirmation. Exact-own-receipt reconciliation and
restart recovery preserve the sealed request, including storage cleanup failure.

Actual earlier rollback 140 includes a posted invoice from governed whole-unit
terms. The later actual 144 includes four scoped/revoked/late-failure regressions.
Independent Standards review found a 500/1000-character payment-term mismatch in
the consuming finance adapter; the owner fixed both sides to the approved limit.
The later actual 147 verifies maximum 1000-character terms through eligible unit
read and real invoice preparation, plus 1001-character rejection. Source binding
is retained in `asset-milestone-sql-final-hashes-20261005.json`. The separate
`milestones-lock-order-review-20261005.md` explains the inspected command call
path's projects/employee subset and its lack of backward payroll/service locks.
It retains real contention as an open requirement.
Current module evidence records domain 4,
gateway 5 and desktop 20 final update/no-update tests, clean focused analysis and
eight individually inspected previews. Global copy stability is explicitly false
because unrelated expense evidence files changed during those module checks.
The module-owned files match their captured hashes; that does not establish a
whole-app build, installed behavior, real billing contention, authenticated native,
Credential Manager restart or owner acceptance. Final integration retains these gates.
