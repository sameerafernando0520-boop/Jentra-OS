# Current candidate reuse and concrete acceptance preparation — 2026-10-03

Current HEAD is `7c08ea890746b1914c2f6e825523482a9146114c`. The freshly observed
development baseline remains 37 installed migrations through
`20260929224939_wave4_private_hr`, 85 API functions and four unchanged finance
helper fingerprints. No candidate is installed by this review.

[The exact reuse gate](database-verification-reuse-20261003.json) validates all
45 current candidate hashes and the dependency order. Rebuilding all three strict
candidate transactions from current source yields the exact SHA-256 of the
historical executed transactions: procurement 991, inventory 155 and receivables
182 assertions, total 1,328. There is no SQL change requiring a repeat execution.
These source-matched results retain their September 30 execution date and
synthetic rollback boundary. They are not newly executed tests, exhaustive fault
coverage, installed authentication, contention, native acceptance or owner signoff.

The October 2 representative-plan query also matches its executed SHA-256; all
101 recorded migration/test source hashes match current files. Its 1,005
assertions overlap the three suites and are not added to 1,328. AR balance,
allocation history, requisition lifecycle and reservation lifecycle remain empty
components in that fixture. Nine SQL-role/copied-claim reads and two privileged
bank reads remain structural evidence rather than signed-session/scale proof.

Current offline preparation passes 68/68 tests; session and load self-tests pass.
[Before/after source fingerprints](database-offline-checks-20261003.json) accompany
the three current logs. Their tiny offline durations are not p95 or lock timings.
The existing management token is available in the execution environment; only its
availability boolean was inspected. No token was printed or persisted.

If a new SQL change, failed assertion or unresolved scenario later justifies a
fresh run, root serializes it. Prepared transactions enforce `finish(true)` and
final `rollback;`, reject top-level `commit;` and contain the exact reviewed
candidate order. Use a fresh unused evidence output path for every attempt:

```powershell
& 'C:\Program Files\nodejs\node.exe' tools/wave3/run-candidate.mjs docs/verification/remaining-wave3/database-strict-procurement-20261003.sql docs/verification/remaining-wave3/database-executed-procurement-20261003-fresh.json
& 'C:\Program Files\nodejs\node.exe' tools/wave3/run-candidate.mjs docs/verification/remaining-wave3/database-strict-inventory-20261003.sql docs/verification/remaining-wave3/database-executed-inventory-20261003-fresh.json
& 'C:\Program Files\nodejs\node.exe' tools/wave3/run-candidate.mjs docs/verification/remaining-wave3/database-strict-receivables-20261003.sql docs/verification/remaining-wave3/database-executed-receivables-20261003-fresh.json
```

Those optional commands are prepared, not executed here. The existing runner uses
the existing management authorization and fixed synthetic development project;
it is unsuitable for independently authenticated race evidence. It must never be
used to install a migration or fabricate native/scale acceptance.

[The current installation package](database-installation-package-20261003.json)
pins every candidate body hash, the exact ordered manifest hash, eight phase
boundaries, compatibility capture, stop conditions and coordinated rollback
decisions. Ordinal 36 posted-journal evidence must precede ordinal 37 operational
evidence despite timestamps. A global migration-directory push would include
unrelated concurrent work and does not implement this reviewed order.

Before installation approval is concrete, bind a separate isolated synthetic
project/direct host, PostgreSQL version, region/resource size and installation
window. Obtain a named verified restore point/restore owner, fixture/sequence
scope and resource budget. Refresh the real ledger, catalogue, helpers and current
data immediately before using approval. Historical schema validity with identical
bodies is not a new live-data preflight. Stop on unexplained drift; retain every
partial-installation diagnostic. After accepted writes, rollback requires an
authorized isolated restore or reviewed additive forward repair, preserving
immutable journals, open items, receipt provenance and history.

Written owner decisions remain outstanding for eight semantic warnings:
value-only movement quantity/sign semantics, quantity-or-value nonempty movement,
nullable prior count status, count-missing equivalence, additive serial status,
additive movement kinds and nullable scoped project/cost-centre journal identity.
Older clients must treat unknown serial states as unavailable and retain unknown
movement kinds in reconciliation. History receives no invented dimension backfill.

The eight individual owner decisions below come from the unchanged historical
`schema-compatibility-final-20260930.json` potentially-breaking issue list. None
has been accepted by this review; each needs a fresh isolated data preflight.

| Decision | Exact constraint/behavior | Required review and stop condition |
|---|---|---|
| 1 | Journal project identity `(tenant_id, legal_entity_id, project_id)` references `finance.dimensions` in the same scope. | Accept nullable project identity and scoped references; stop on nonnull orphan/cross-scope rows. Do not invent historical dimension backfills. |
| 2 | Journal cost-centre identity `(tenant_id, legal_entity_id, cost_centre_id)` references the same scoped dimension key. | Accept nullable cost-centre identity; stop on nonnull orphan/cross-scope rows. Preserve existing ledger history. |
| 3 | Stock movement kinds add receipt/reversal, purchase return, transfer, adjustment, value adjustment and disposition/reversal to existing opening/delivery/sales-return kinds. | Confirm existing values fit the exact candidate enum and older clients preserve unknown permitted kinds in reconciliation. Stop on unexplained values or clients that drop them. |
| 4 | Serial `count_previous_status` is nullable, otherwise `available` or `quarantine`. | Review existing nonnull values and the provenance of previous status; stop rather than synthesize history for invalid rows. |
| 5 | Serial `status = count_missing` is equivalent to nonnull `count_previous_status`. | Accept the paired transition/restore semantics and preflight both mismatch directions; stop on ambiguous historical state. |
| 6 | Serial status permits `available`, `issued`, `quarantine`, `disposed`, `in_transit`, `count_missing`. | Review existing values and older-client unavailable-state handling before exposing added statuses; stop on silently editable unknown states. |
| 7 | Movement-line sign constraint permits zero quantity or zero value; otherwise quantity/value signs match. | Approve attributable value-only corrections and exact sign semantics. Preflight existing nonzero mismatches; no rewriting posted lines to satisfy the constraint. |
| 8 | Movement lines require nonzero quantity or nonzero value. | Accept rejection of empty lines; preflight both-zero legacy rows and explicitly handle any historical ambiguity through authorized immutable correction/restore decisions. |

Zero reported structural breaks with eight potential warnings is historical
candidate compatibility evidence, not owner approval or current live-data
compatibility. The exact ordered candidate hashes, eight phase/rollback decisions,
fresh data/catalogue preflight, named restore point/owner/window and permitted
effect scope must be bound together before isolated installation. No new target,
installation, persistent fixture, authenticated session or native launch is claimed.

For independent sessions, name two existing distinct actors and actual session IDs,
their tenant/entity/branch/warehouse/product/source records and allowed mutations.
Bind exact workload/race/count/postflight hashes. Uncommitted candidate DDL cannot
be shared between sessions, and seven required race RPCs are absent from the
current installed schema. Request overlap alone is not database lock overlap.
Retain original losing conflicts, single winning effects and immutable source
hashes. No user creation, sign-in, authentication or persistent fixture is
authorized by preparation.

For target-scale load, bind the actual 500 tenants, ten entities per tenant,
25 warehouses per entity, 100,000 products per large tenant, ten million stock
movements and twenty million journal lines, including generator seed/distribution
and resource budget. Record ten warmups and at least 100 measured samples per
workload, six operation classes and five ordinary report metrics. Fresh mutation
identities prevent idempotent replay from masquerading as posting speed. Complete
currency-separated entity aging must collect every frozen page. Raw populated
plans and nearest-rank p95 remain separate from offline guards and empty plans.

Native approval is a separate binding: a freshly hash-matched isolated Windows
copy, fresh profile, existing actor/capabilities, explicitly allowed native secure
store entries, Storage prefix, synthetic records/sequences and file locations.
Cover cold launch, credential-store/process restart, original-command recovery,
native file save/upload/retry, connectivity/scope/MFA changes, keyboard/screen
reader/reduced-motion and required-size/theme/density/200% renders. Never launch
the acceptance-owned executable. Owner signoff follows the complete evidence
review and remains distinct from installation/native approval.
