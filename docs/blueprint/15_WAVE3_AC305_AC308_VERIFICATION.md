# AC-305–AC-308: development verification and remaining work

Verified 2026-09-10 in `C:\Users\sheha\Desktop\Jentra OS`, on `main` at
continuation baseline `e35a05e`. The remaining lead-to-cash implementation is
installed in the approved synthetic-development project `xpdoufauvrbdmxgngetv`.
This is a development handoff, not authenticated native acceptance or production
release approval. No production data, external payments, Git staging, commit, or
push was performed in this continuation.

## Delivered scope

| Acceptance criterion | Implemented behavior |
| --- | --- |
| AC-305 / FR-326–327 | Partial delivery from orders; exact remaining base quantities; reservation consumption under shared order/product locks; costed stock and balanced inventory/COGS posting; lot/serial eligibility and immutable source links. |
| AC-306 / FR-328–329 | Versioned invoice drafts from order/delivery lines, or direct service/nonstock lines; configured approval; atomic invoice, AR, revenue/tax journal, audit and replay receipt; partial cumulative rounding; direct stocked invoice rejection. |
| AC-307 / FR-330–332 | Governed cash/bank setup and customer receipts; balanced cash/bank and AR; explicit one-to-many allocations, repeatable for many-to-one; exact residuals, FX differences, and separately authorized reasoned discounts/write-offs; unreconciled receipt state. |
| AC-308 / FR-333–334 | Source-linked partial returns/credits with reason/disposition; original issued cost, accounts, FX and cumulative carrying-base reversal; explicit credit application; as-of statements and aging reconstructed from append-only items/allocations. |

The desktop entry is **Fulfillment & receivables** (`/receivables`). It includes
document registers/editors, governed reference pickers, approval/posting actions,
statement/source/allocation drill-through, posting prerequisites, encrypted local
draft recovery, immutable interrupted-command retries and explicit stale-version
handling. Offline or unauthorized users cannot dispatch posting commands.
Open dialogs hide cached records when their business-scope controller is invalidated.

The existing AC-304 source files and published migration were not edited. New
delivery/invoice behavior consumes its order/reservation identities. An additive,
guarded integration adjusts credit exposure to count uninvoiced order amounts plus
AR residuals, preserving the existing RPC signatures and preventing double counting.

Credits reduce net AR but are not silently allocated to an invoice: use the
explicit allocation action to reduce that invoice's residual. Receipt posting does
not perform bank reconciliation or move money through an external payment service.

## Database application and proof

The migration skill's compatibility gate passed before each application; all
candidate tests ran inside rollback transactions. The phase-specific rollback
runbook is in [the implementation record](13_WAVE3_AC305_AC308_IMPLEMENTATION.md).
The seven un-applied candidate files were consolidated without losing their SQL;
their earlier versions remain recoverable from baseline Git history.

| Applied development version | Purpose | Normalized source/ledger MD5 |
| --- | --- | --- |
| `20260910135010` | Atomic delivery and receivables expansion | `33ae7e4e994722206d5755431b5266c3` |
| `20260910135507` | Leading-reference FK indexes and equivalent single cash/bank read policy | `495030c5377ec3422e560b71c80aa4d8` |

Local SQL matches both applied ledger statements after CR removal and edge
whitespace normalization. The live ledger contains **31 migrations**. Project
health is **ACTIVE_HEALTHY**. The installed table/view column manifest matches the
rollback-tested candidate: 87 existing relations expanded to 128. Existing API
column contracts are retained. SQL lint via `plpgsql_check` found no error/fatal
results in the examined new helpers and integrated order-credit/transition functions.

After both applications, all **469 strict SQL assertions** passed against installed
objects (no candidate DDL included in these final runs):

| Suite | Assertions |
| --- | ---: |
| Greenfield foundation | 30 |
| Wave 2 shared foundation | 99 |
| Wave 3 operational foundation | 50 |
| CRM pipeline | 88 |
| Lead-to-cash foundation | 46 |
| Quotation workspace | 43 |
| Order workspace / AC-304 | 28 |
| Delivery and receivables | 85 |
| Total | 469 |

The new suite covers atomic/replayed posting, authorization/RLS, direct-DML denial,
invalid lot/serial rollback, excess quantities, period/approval restrictions,
over-allocation, adjustments/FX, original-rate credits, partial carrying-value
rounding, exact AR-control reconciliation, historical aging, setup validation and
reference-index/policy contracts. Every suite ends in rollback; strict
`finish(true)` was used in-memory for older suites without changing those files.
Final checks found zero orders, deliveries, invoices, receipts, returns, journal
entries, open items or AC-305–AC-308 fixture tenants persisted.

Security advisors returned **zero findings**. Performance advisors returned no
missing-FK-index findings and no overlapping-policy warning after the follow-up.
There are 345 informational unused-index observations across the development
project; these are not a reason to remove indexes from an empty test environment.
Evaluate usage under representative load before changes ([Supabase guidance](https://supabase.com/docs/guides/database/database-linter?lint=0005_unused_index)).

## Client and rendered verification

| Suite | Passing tests |
| --- | ---: |
| Domain | 78 |
| Platform / encrypted storage / gateways | 64 |
| Design system | 10 |
| Desktop controllers / widgets / goldens | 117 |
| Total | 269 |

Whole-workspace analyzer: **no issues found**. Final non-mutating formatter:
**106 files, zero changes**. Whitespace checks pass. A targeted heuristic scan of
the receivables implementation and two migrations found no matching private-key,
secret-key, or credential-bearing database URL patterns; this is not a full-history
secret audit.

Six rendered receivables goldens were inspected and pass non-update comparison:
light invoice detail, dark invoice editor, 1024-pixel editor at 200% text scale,
interrupted-command recovery, receipt editor, and return/credit editor. The
scope-invalidation recovery test reproduced the old cached-dialog behavior before
the fix and passes afterward. Existing quotation/order golden files are unchanged.

The Windows release build passed, including a final incremental rebuild in 36.9
seconds after the dialog fix. A fresh hidden process remained responsive for ten
seconds and exposed three process-owned native windows at 13:55:30 UTC; that
process alone was then stopped. This was an **unconfigured backend preview**,
not an authenticated end-to-end transaction. Two later export-library formatting
changes were whitespace-only.

Machine-readable checks and the repeatable startup script are in
[`docs/verification/ac305-ac308`](../verification/ac305-ac308/).

## Remaining work and acceptance gates

1. **Authenticated Windows walkthrough and owner signoff.** Use governed synthetic
   tenant/entity/branch fixtures and appropriate separate operator/approver roles.
   Configure fiscal periods, workflows, document sequences, accounts/mappings,
   customers/products and opening stock/valuation through approved setup paths.
   Walk order → partial delivery → invoice → receipt/allocation → return/credit →
   dated statement and inspect stock, journals, audit and residuals together.
2. **Real restart recovery: local native evidence added 2026-09-11.** The
   [native recovery follow-up](16_WAVE3_NATIVE_RECOVERY_VERIFICATION.md) verifies
   the actual Windows secure-storage adapter and disk SQLite across forced
   process stops, offline edits, simulated dropped responses and byte-identical
   retries. Authenticated transport loss, simultaneous first launches, OS restart
   and broader storage/navigation failure cases remain explicitly open there.
3. **Concurrent/load and failure testing.** Exercise two actual database sessions
   racing deliveries/allocations, lock waits/deadlocks, large statements, workload
   latency and disk-write failure/navigation behavior. Transactional rejection and
   duplicate-click tests are not multi-session contention or load evidence.
4. **Separate Wave 3 slices.** Inventory opening/valuation setup, procurement,
   supplier payments, bank reconciliation and the broader finance workspace remain
   outside this AC-305–AC-308 handoff. Review their own approved acceptance criteria
   before implementation; they are not implied complete by lead-to-cash posting.
5. **Release authorization.** Production rollout, real business data, external
   payments and statutory/compliance readiness require separate approval and proof.

Do not edit either applied migration or reapply the superseded seven candidates.
Keep the current uncommitted follow-up changes intact for review. User continuation
messages authorize progress but are not acceptance signoff.
