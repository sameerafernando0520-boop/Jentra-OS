# Governed stock opening: Wave 3 prerequisite

Implementation slice under approved FR-301–311, FR-350–356, FR-358, FR-360 and
AC-313–315. Synthetic development only. This adds the opening-stock path needed
by the authenticated lead-to-cash walkthrough; it does not claim the complete
inventory, stock-adjustment, transfer, procurement or valuation workspace.

## Command and read contract

- `api.upsert_stock_opening`: standard Wave 3 command envelope; requires
  `inventory.adjustments.post` and `inventory.cost.view`. Creates or version-saves
  an editable opening with `id`, `warehouse_id`, `document_date`, `reason`,
  `offset_account_id` (active posting equity account) and 1–100 `lines`.
- Lines contain unique `line_id`, `product_id`, exact positive `base_quantity`
  and `base_value` strings. Values must fit the entity rounding scale. Base units
  only; inventory account and product/unit/tracking snapshots are server-owned.
  Lot lines require `lot_code`, optional manufacture/expiry dates; serial lines
  require distinct `serial_codes`, one per whole base unit, at most 500 per line.
  Opening lots must be saleable and not expired at posting. Untracked lines
  reject tracking data. Service/nonstock products cannot enter stock openings.
- `api.transition_stock_opening`: submit/recall/cancel and approved/rejected
  decisions. Uses the configured `stock_opening` workflow, versioned approval
  matrix and permanent document sequence. Opening always requires approval;
  a workflow without an applicable approval step fails closed. A preparer or
  submitter cannot approve. The creator and latest editor are both recorded and
  excluded from approval. Decision actors require the configured scoped role,
  `workflow.approvals.decide`, `inventory.cost.view` and MFA where required.
- `api.post_stock_opening`: requires `inventory.adjustments.post` and
  `inventory.cost.view`, approved state, open period and unchanged active
  accounting/product mappings. Uses the same ordered stock locks as reservations
  and delivery. A warehouse/product with prior movement, nonzero balance,
  reservation or valuation cannot be opened again. Different lot lines for one
  product belong to the same opening document.
- Posting creates immutable source-linked stock movements, lot/serial identity,
  stock/valuation projections and a balanced base-currency inventory/equity journal
  atomically with its command receipt, audit, process event and outbox record.
  Replays return the original result. Posted openings cannot be edited, deleted
  or reopened. Correction/reversal is a separate future inventory slice.
- `api.stock_openings`: caller-RLS view with bounded client pagination, exact
  numeric strings and coherent line snapshots. Cost data is visible only when
  `inventory.cost.view` and opening/approval capability are both held.

## Verification and rollout

1. Prove the missing API contracts with failing SQL tests. Add only new objects;
   existing published migrations, order and receivables signatures remain intact.
2. Test candidate DDL and synthetic fixtures in one rollback transaction. Cover
   authorization/MFA, scope, decimal and tracking validation, approval separation,
   optimistic conflicts, replay, balanced posting, duplicate opening and rollback.
3. Capture before/after column manifests and pass the migration-architect
   compatibility checker. Application is gated on compatible output and this
   phase-specific rollback runbook.
4. Apply only to development `xpdoufauvrbdmxgngetv`; inspect the ledger if transport
   is ambiguous. After applying, rerun installed-object tests and advisors, match
   local SQL to the ledger, and confirm test records have not persisted.

Rollback: preflight and candidate phases end in rollback. The application phase
is atomic; on failure it must leave no partial schema. After successful application,
retain the compatible expansion and all posted history; disable use of a failing
new command and prepare a tested additive correction. Never drop financial/stock
history or rewrite published SQL. The existing app remains compatible throughout.

Authenticated acceptance still needs user-managed synthetic owner/approver
accounts and MFA, governed business masters and a signed-in native walkthrough.
SQL fixtures are rollback tests and do not substitute for real authentication.

## Applied development evidence: 2026-09-11

Applied as `20260910201410_governed_stock_openings` (database ledger uses UTC).
The development ledger now has 32 migrations. The local SQL matches the ledger
apart from the terminal newline added when reading the file into the tool. All
six installed opening functions match the rollback candidate definitions; the
five existing commerce/finance helper definitions are unchanged.

The initial structural red test failed all four missing-object assertions.
The completed candidate passed 80 assertions inside a rollback transaction,
including real `authenticated` database-role calls with synthetic JWT claims.
The same 80 assertions passed against installed objects. All eight existing
database suites also passed: 30 + 99 + 50 + 88 + 46 + 43 + 28 + 85 = 469.
Total installed coverage is **549 passing database assertions**.

Coverage includes exact totals, unit/currency precision, cross-tenant identifiers,
private-helper grants, MFA and cost permissions, creator/latest-editor/submitter
separation, multi-step approval, stale versions, changed mappings, closed periods,
lot/serial identity, existing quantity/valuation, immutable posting, command replay,
and audit/process/outbox records. A forced journal-sequence failure after stock
writes leaves no movement, stock balance or receipt. All posted opening valuations
reconcile to inventory control, and deferred constraints are forced before rollback.
Intermediate approval decisions keep their decision/audit/outbox history; a process
status event is emitted only when the document status changes.

The migration-architect compatibility checker exited 0 with `fully_compatible`,
zero breaking changes and zero potentially breaking changes. Security advisors
are clear. Performance advisors report only 350 informational unused-index
findings, including 13 on the new empty opening table. The required FK indexes
are retained; no duplicate-index or unindexed-FK warning was reported. See the
[unused-index guidance](https://supabase.com/docs/guides/database/database-linter?lint=0005_unused_index).

Final persistent counts are zero users, verified MFA factors, tenants, openings,
stock movements and journals. No synthetic test fixture was retained. No staging,
commit, push or production action occurred. Existing native recovery edits remain
in the checkout.

Evidence: [verification.json](../verification/stock-opening/verification.json),
[candidate TAP results](../verification/stock-opening/candidate-tests.json),
[compatibility report](../verification/stock-opening/compatibility.json), and
[ledger SQL](../verification/stock-opening/ledger-statements.json).

## Native implementation: 2026-09-11

Native slice contract (2026-09-11): `/inventory` opens the stock-opening register.
Both cost visibility and opening/approval capability are required, including for
direct navigation. Select active scoped warehouses, stocked products and posting
equity accounts with paginated lookups. Preserve exact-string quantities/values,
optional lot dates and individual serial codes. Local totals are a preview; the
saved server snapshot is authoritative. Local recovery is actor/business scoped
in a separate `inventory.stock_opening` encrypted namespace. Unknown outcomes
retain the immutable envelope; conflicts preserve edits until explicit discard
and reload. Saving failures prevent closing or dispatching unsaved fields.
The detail view shows approval state, posting effects and journal/movement references.
Self-approval is hidden for the creator, latest editor and submitter; the server
continues to enforce configured roles, steps, MFA and all financial rules.

The native stock-opening register/editor and Dart command integration are now
implemented, including the three explicit opening commands, exact-string values,
encrypted local drafts and immutable retry envelopes. Both recovery entry points
keep lifecycle snapshots read-only after interrupted or rejected requests.
See [native verification](18_WAVE3_STOCK_OPENING_NATIVE_VERIFICATION.md) for tests,
rendered previews, release evidence and the limits of that evidence.

## Remaining authenticated acceptance

Setup Centre already accepts document type text for sequences and workflows, so
use `stock_opening` with a mandatory approval matrix and the active posting equity
offset account.

Create the synthetic tenant/entity/branch/warehouse, base units and stocked
products, inventory/equity accounts, open fiscal period, opening/journal sequences,
and independent scoped approver through the governed setup flow. Perform opening
approval/posting and continue the existing sales-to-receivables walkthrough.
Account creation/sign-in and MFA remain user-managed and pending. Before that
walkthrough, rebuild the development-connected Windows release with the ignored
`.env.acceptance.json`; the native stock-opening build is an ordinary release.

The database and native opening workspace are implemented and locally verified.
An authenticated session and final acceptance of the complete Wave 3 inventory
workspace are still pending.
