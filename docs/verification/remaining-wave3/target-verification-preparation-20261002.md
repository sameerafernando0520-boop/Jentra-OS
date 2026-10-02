# Isolated-target preparation and independent review — 2026-10-02

The preparation review and corrected offline execution guards pass. Those offline
checks used no database, HTTP, persistent fixture, migration, authentication,
native executable or acceptance-owned store. A separately recorded development
candidate plan check used a synthetic transaction with strict `finish(true)` and
final rollback. This evidence prepares an approval request; it
does not authorize or establish installed verification, real concurrency, target
population, p95 or native acceptance. The source fingerprints, diagnostic runs
and machine-readable boundaries are in
[the companion evidence](target-verification-preparation-20261002.json).

The root Wave 3 task is still open. The durable
[plan](../../../.agent-harness/wave3-final-20261002-plan.json) and
[state](../../../.agent-harness/wave3-final-20261002-state.json) distinguish verified
offline preparation from remaining development, installed-target and native gates.
The controller runs executable checks itself. No owner waiver has been supplied.

## Findings and corrections

| Finding | Correction and evidence |
|---|---|
| Session/load final JSON writes could replace an existing evidence file. | Both runners exclusively reserve a new output descriptor with `wx` before dispatch and write through that descriptor. Existing and still-open competing reservations retain identical bytes; failed reservation dispatches nothing. |
| An unrelated allowlisted mutation could be labelled a receipt, match or other race. | Each of the nine labels now requires its actual reviewed RPC and payload class. Same-source or distinct-consumer contention is checked, and supplemental SQL source IDs must match those command payloads. Nine positive cases, nine unrelated-RPC denials and nine unrelated-postflight source denials pass. |
| A safe initial purchase-order version could become unsafe at a later receipt ordinal. | Plan and direct-command guards reject an out-of-range last version using `BigInt`. The last safe version is retained exactly. Initial regression: 1 passed / 2 failed. First correction: 51 passed / 1 failed because ordinary integer addition rounded the bound; the exact boundary correction passed all 52 preparation/guard tests. |
| Aged-balance benchmarks mapped to one party's statement instead of the complete scoped population. | AR/AP measurements now generate a fresh complete entity/branch control report, fetch every unfiltered frozen item page and derive exact aging totals during the same elapsed sample. Scope, cutoff, kind, complete count, multiple parties, currencies, unapplied credits and bucket totals must match. Sixteen targeted checks reject partial or unrelated evidence. |

Contract [57](../../blueprint/57_WAVE3_TARGET_VERIFICATION_CONTRACT.md) was recorded
before behavior changed. All 16 original preparation tests, 36 new guard tests and
16 complete entity-aging checks pass: 68 in total; the original session and load
self-tests also pass. The tests use fictitious
UUIDs/claims and small local temporary evidence files. Claims parsing is a guard,
not JWT signature, server revocation or authentication proof. No timing from these
tests is a load measurement.

The exact 68-test command and retained output are:

```powershell
& 'C:\Program Files\nodejs\node.exe' --test --test-isolation=none tools/wave3/target-verification-preparation.test.mjs tools/wave3/target_review_guards.test.mjs tools/wave3/target_review_aging.test.mjs
```

[The current 68-test log](target-review-final2-20261002.log) records 68 passed,
zero failed, and 93,146.2648 ms test-run duration; that duration is not p95 evidence.

## Current synthetic plan and security evidence

Contract [47](../../blueprint/47_WAVE3_CONTROL_READ_PLAN_CONTRACT.md) now requires
residual plan checks to project the actual residual columns. Identity-only reads
could let PostgreSQL prune that computation. Both scoped balance queries were
corrected to select the complete view result. The current
[query](representative-plans-residual-20261002.sql) and
[raw evidence](representative-plans-residual-20261002.json) retain exact source
and query hashes, 1,005 passing strict assertions and final rollback. The run
completed from 06:24:22 to 06:25:06 UTC on 2026-10-02.

Nine components used the authenticated SQL role and synthetic scoped JWT claims;
two private bank source components used the privileged role. Outsider reads and
authenticated direct writes were denied. The full payable residual view evaluated
19 rows. Receivable balance, allocation-history, requisition lifecycle and
reservation lifecycle selections returned no rows on this procurement fixture.
The fixture had 20 open items, 128 stock movement lines, 457 journal lines, eight
bank statement lines and zero reservations. Those empty selections and all single
synthetic execution timings remain structural evidence only. They do not complete
populated component, signed-session, contention, NFR-309 population or p95 gates.

A fresh post-rollback probe retained 37 installed migrations, latest
`20260929224939`, 85 API functions and unchanged four shared finance helper hashes.
Seven required race RPCs are absent from the installed schema: `post_goods_receipt`,
`post_manual_journal`, `period_governance_command`, `bank_reconciliation_command`,
`allocate_supplier_credit`, `reverse_goods_receipt` and
`transition_purchase_requisition`. Uncommitted candidate DDL/fixtures are invisible
to independent sessions. No complete nine-class business race can be run on this
installed schema under the present boundary. Request overlap or an unrelated
advisory-lock exercise cannot substitute for the required command outcomes.

The remaining approval must name the separate isolated installation, exact ordered
candidate hashes, eight compatibility decisions, restore point/window, resources,
existing distinct actors/sessions, permitted synthetic fixtures/sequences and
reviewed workload/invariant hashes described below. Native approval is separate.
There is no approved target binding or load/race execution in this review.

The independent SQL review checked required columns, scoped source types and
signatures against `schema-after-45-20260930.json`. The close invariant correctly
uses the prior period version for its immutable event. Receipt valuation remains
the existing authoritative scoped command result; foundation preparation invents
neither stock nor journal provenance. The six-assertion foundation rehearsal uses
`finish(true)` and final rollback. It is prepared SQL, not an executed or persistent
500-tenant fixture. This review is structural and source-based; the generated SQL
still needs execution on the exact approved installed target.

The 45 candidate bodies match the reviewed manifest. The captured compatibility
review reports zero breaking changes and eight potential incompatibilities, not
unqualified compatibility. Those warnings, older-client semantics and live data
preflight require owner acceptance before installation. The existing
[migration dependency and rollback runbook](migration-review-and-runbook-20260930.md)
governs installation. Re-query the installed ledger, API catalogue and shared
finance helpers immediately before requesting or using installation approval.

## Concrete inputs required before execution

1. Name a separate owner-approved synthetic Supabase project, direct host,
   PostgreSQL version, region, resource size, restore point and installation
   window. Explicit approval must identify the 45 candidate body hashes and tested
   ordinal order, eight warning decisions, allowed fixture count/resource budget
   and permitted synthetic sequences. Do not use the shared development project,
   production or stock-opening acceptance. Do not install or create this target
   under the current prompt.
2. Bind existing actors and exact tenant/entity/branch/warehouse/product/document
   UUIDs. Foundation rehearsal rolls back and therefore cannot supply persistent
   identities to later HTTP commands. Persistent hierarchy, membership, controls,
   active fiscal periods, approved purchase orders and untracked product lanes
   require a separately approved setup. These tools create no users or sessions.
3. Define each receipt lane's current order version, reviewed remaining quantity,
   exact accepted quantity and exact command value. The preflight rechecks current
   scope, approval, capacity/value, product/warehouse/GRNI control, active membership,
   open period, later movement, journal guards and installed receipt RPC source.
   The same deterministic seed retains original command, idempotency and document
   identities. A rejected or uncertain receipt stops generation; retain its original
   envelope and records instead of sending a new command or deleting history.
4. Approve concrete workload/race configurations and their hashes. A load run needs
   fresh actual NFR-309 counts and per-tenant/entity distribution. A small race run
   needs its exact approved fresh cohort count hash, independently of the load
   population. The wrapper reads the actual isolated ledger, deployed RPC bodies
   and count query rather than trusting self-reported fields.
5. Provide two existing authenticated actors and distinct actual session IDs for
   races. Bind every final read and supplemental immutable-row hash to the same
   command sources. Retain stable losing conflicts, exact winning effects and
   immutable originals. The nine prepared cases are concrete class coverage;
   credit exposure, tracking, allocation correction and close versus posting must
   retain their additional required scenario evidence. Request overlap alone does
   not demonstrate database lock overlap.
6. For load, supply all six operation classes, at least ten warmups and 100 measured
   samples per workload, exact response checks, fresh mutation identities and the
   five ordinary report measurements. Aged AR/AP samples must use all-party
   entity/branch control generation and collect every frozen item page; exact
   currency-separated bucket/count/residual expectations prove complete output.
   Generation, source collection and exact aging derivation share one measured
   elapsed sample. A party statement or one summary page is rejected as aging proof.
   Report generation and cached-page timings are distinct. Record region/resources,
   cache conditions, generator seed, actual counts, raw samples and nearest-rank p95.
7. Bind eleven prepared query components to real populated target IDs and retain
   raw unmodified `EXPLAIN (ANALYZE, BUFFERS, SETTINGS, FORMAT JSON)`. Nine use the
   authenticated SQL role with synthetic claims; two bank private-basis queries are
   explicitly privileged. Copied claims are not signed-session authentication, and
   an outer function plan may hide nested PL/pgSQL work. Review populated source
   components, denied/foreign scopes, tenant-leading access and flagged high-volume
   scans. A single execution time or empty plan cannot prove p95 or representative
   scale.

## Offline preparation commands

Run these from the repository root with reviewed concrete JSON inputs. The defaults
compile or validate recipes; none of these commands contains `--execute`:

```powershell
node tools/wave3/prepare-target-verification.mjs concrete-bindings.json --output docs/verification/remaining-wave3/fresh-preparation-directory
node tools/wave3/run-target-fixture-generator.mjs docs/verification/remaining-wave3/fresh-preparation-directory/fixture-plan.json
node tools/wave3/run-independent-sessions.mjs docs/verification/remaining-wave3/fresh-preparation-directory/race-plan.json
node tools/wave3/run-target-load.mjs docs/verification/remaining-wave3/fresh-preparation-directory/load-plan.json
node tools/wave3/prepare-target-race-invariants.mjs concrete-postflight-bindings.json --output docs/verification/remaining-wave3/fresh-postflight.sql
node tools/wave3/prepare-target-query-plans.mjs concrete-query-bindings.json --output docs/verification/remaining-wave3/fresh-plan-directory
node tools/wave3/run-reviewed-target-verification.mjs docs/verification/remaining-wave3/reviewed-run-binding.json
```

The future reviewed-run binding must record `explicit_user_approval` with a real
approval reference, exact source/config/installed-ledger hashes, fresh evidence
paths, and (for races) approved count and supplemental-invariant SQL hashes. Keep
tokens/public keys/passwords in approved environment variables only. The fixture
runner uses `WAVE3_FIXTURE_SESSION_TOKEN`; the load runner uses
`WAVE3_LOAD_SESSION_TOKEN`; races use `WAVE3_SESSION_A_TOKEN` and
`WAVE3_SESSION_B_TOKEN`. None is obtained or changed here. `psql` and its verified
TLS connection must already be available in the approved execution environment.

Only after the corresponding concrete human approval should an operator append
`--execute` to the fixture or reviewed-run wrapper. Reserve fresh evidence paths
for each approved run. Preserve original attempts after any failure or uncertainty.
Do not repair the migration ledger, retry under new command identities, delete
accepted fixtures or infer resource/teardown/native authority from load approval.
Ordinary candidate/installed fixture tests use strict `finish(true)` plus final
rollback; committed HTTP race/setup writes cannot be relabelled as rollback tests.

Native acceptance has a separate gate identifying the isolated Windows copy,
fresh test profile, existing actor/capabilities, allowed Credential Manager entries,
synthetic records/sequences and Storage prefix. Never launch the acceptance-owned
executable. Owner signoff remains separate from every preparation result above.
