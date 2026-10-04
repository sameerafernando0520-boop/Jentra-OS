# Wave 3 isolated-target verification tools

This contract governs preparation and future execution tools. It changes no public
database RPC, authenticated command, valuation rule or approved Wave 3 requirement.
The current development prompt permits offline preparation and synthetic strict
rollback verification. It does not permit persistent installation, authenticated
fixture creation, target load, acceptance-owned sequences or native acceptance.

Prepared fixture, load and race inputs must identify an owner-approved isolated
synthetic target, exact source and installed-ledger fingerprints, concrete existing
actors/scopes, fixture budget and new evidence paths. The shared development
project and production are forbidden. Approval strings in a file are not human
authorization: the operator must have the corresponding explicit user approval.
Secrets remain in environment variables and must never enter evidence.

Current ordinal-46 preparation explicitly selects its installation package,
ordered manifest and successful 45-to-46 schema review through `candidate_review`.
Every candidate body and its exact ordinal hash must match current source; all
45 historical bodies remain in their reviewed order before the policy tail.
The selection must retain three complete strict rollback suites and the actual
schema execution, with the four protected finance helpers unchanged. A legacy
45-body recipe remains historical and cannot be relabelled as current 46-body
preparation. Source bundles must contain the complete selected artifact and
candidate set. Fixture, load, race and live-RPC preflight inputs retain the same
selection; omission or a different selection fails before any dispatch.

Offline selection checks use explicitly fictitious test artifacts. They prove
the guard behavior only; they do not supply an observed schema, real target,
installation authority, signed sessions, fixture population or performance data.

Evidence files must be new. Execution reserves each final evidence path exclusively
before the first HTTP command; an existing path, including a competing reservation,
must fail without replacing earlier evidence or dispatching a command. Failed and
uncertain attempts retain the original command identities and failure evidence.

Receipt lanes use exact decimal strings. Every expected purchase-order version,
including the last receipt ordinal, must remain a safe integer; an oversized version
lane is rejected before producing commands. This guard does not approximate or wrap
an optimistic version. Receipt commands create actual provenance and atomic journals
through the existing scoped RPC; no stock or journal history is invented.

The nine race labels refer to these concrete command classes and source bindings:

| Label | Required class |
|---|---|
| Number reservation | Submit two distinct purchase requisitions through `transition_purchase_requisition`. |
| Order allocation | `reserve_sales_order_stock` on two distinct sales orders with concrete positive reservation lines. |
| Stock issue | `post_delivery` for two distinct delivery documents. |
| Receipt | `post_goods_receipt` with distinct receipt IDs, concrete purchase order, warehouse and accepted lines. |
| Matching | `bank_reconciliation_command` with action `match`, distinct match IDs and overlapping statement/journal claims. |
| Allocation | Customer or supplier credit allocation from two distinct immutable source items to the same target item. |
| Posting | `post_manual_journal` for the same approved document with two fresh command envelopes. |
| Close | `period_governance_command` with action `hard_lock` for the same period. |
| Reversal | `reverse_goods_receipt` for the same original receipt. |

Unrelated allowlisted RPCs and wrong actions cannot stand in for a race class.
Supplemental relational invariant bindings must refer to the corresponding command
source IDs. These cases do not claim coverage of every possible cross-module race;
close versus posting, credit exposure, tracking and allocation-correction scenarios
must retain their own approved concrete cases and evidence where required.

Each race requires two existing authenticated actors with different real session
IDs, approved outcomes/conflicts, scoped final reads and linked immutable-row hashes.
Client request overlap is reported separately from observed database lock overlap.
Small-cohort races require their exact approved fresh count hash; no performance
population is invented for them. Load requires the actual NFR-309 population and
raw measured samples for every NFR-307/308/320 class, including all five ordinary
report measurements. Generation timings measure actual new report commands.

Offline tests, source integrity and query preparation prove neither installation,
JWT authentication, live concurrency, population counts, p95, native acceptance nor
owner signoff. Foundation rehearsal SQL must use `finish(true)` and final rollback.

Entity/branch aged-balances samples use fresh AR/AP control-report generation,
which reads every dated open item in that exact scope without a party filter.
The measured operation includes generation, every frozen item page, and exact
currency-separated aging calculation at the requested cutoff. The calculation
retains separate unapplied credits (bucket -1), current (0), 1–30 (1), 31–60 (2),
61–90 (3) and more than 90 days (4), with original currency and base currency kept
distinct. It uses the existing dated residual amounts and due dates; it neither
revalues nor mutates them. Exact expected item count, at least two represented
parties and full expected bucket/count/amount evidence must match. Missing,
duplicate, stale, foreign, filtered or truncated pages fail the sample. A single
party statement or one summary page cannot pass an entity aged-balances benchmark.
