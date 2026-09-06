# Wave 3 quotation contracts — AC-303

## Scope and status

Implemented and development-applied server-first continuation of FR-319–FR-321 / AC-303, on `master` from
`15c9929`. The checkout was clean when this continuation began. Existing CRM,
quotation, order/credit/reservation migrations are immutable and unchanged.
This is not completion of the Windows quotation editor or the Wave 3 release gate.

## Implemented contract changes

- Submission fails closed without an active, unambiguous scoped workflow or a
  matching approval matrix. It revalidates active customer/contact/salesperson,
  governed FX, product/unit/tax definitions, and exact server calculations.
  Changed tax snapshots require an explicit draft save/recalculation.
- Each submission pins its workflow lifecycle and matching approval steps.
  Subsequent decisions use that policy snapshot, but recheck the actor's live
  membership, scoped role, capability and segregation of duties.
- Recall requires a reason, expected version and configured transition. It
  creates a new draft revision with new line identities and preserves published
  lines, snapshots and decisions. Explicit revision also allocates fresh line IDs.
- Submit, approve, reject, recall, accept, expire and cancel enforce the configured
  lifecycle. Expiry uses the server's UTC date; an older client date cannot make an
  expired quote acceptable. Revision, receipt, audit, process event and outbox
  writes remain atomic. No stock or credit mutations were added.
- `api.sales_quotation_details` returns one coherent header/current-lines snapshot.
  `api.sales_quotation_decisions` exposes revision-linked decisions with decimal
  amounts as text. Both use caller RLS; quotation-only readers gain read access to
  their scoped decisions without gaining approval/write capabilities.
- Additive Dart read contracts and Supabase gateway provide literal search,
  bounded keyset pagination, details, revisions and decisions. Decimal strings,
  six-place money/quantity, ten-place rates and BigInt conversions are preserved.
- `QuotationDraftStore` stores full actor/tenant/entity/branch-scoped drafts and
  immutable command envelopes through the existing encrypted repository. Unknown
  outcomes retain the exact retry envelope; confirmed rejections preserve edits;
  version conflicts require explicit resolution. No automatic sync/merge is added.

## Workflow configuration contract

Existing canonical lifecycle `states` and `transitions` remain valid. For quotation
actions outside the shared document enum, configure `lifecycle.quotation_transitions`,
for example:

```json
{
  "quotation_transitions": [
    ["submitted", "draft"], ["approved", "draft"],
    ["approved", "accepted"], ["submitted", "accepted"],
    ["submitted", "expired"], ["approved", "expired"],
    ["expired", "draft"], ["expired", "cancelled"]
  ]
}
```

Merge this property into the canonical lifecycle, not over it. `pending_approval`
maps to `submitted` for lifecycle edge checks. Approval is required by default;
only an explicit JSON boolean `requires_approval: false` permits a non-approval
submission. The server does not invent missing transitions or approval policy.
Each customer-facing revision stores the exact policy used at submission.

## Development migration plan and rollback runbook

Target: **only `xpdoufauvrbdmxgngetv`** (Jentra os, ACTIVE_HEALTHY, PostgreSQL
17.6.1.166). Pre-application ledger: 27 migrations, latest
`20260905123934_harden_crm_pipeline_ac302`; quotation tables are empty.

1. Validate the candidate in a transaction with synthetic fixtures and strict
   `finish(true)`, ending in ROLLBACK. A failure also aborts the entire transaction.
   Confirm no schema/ledger entry or synthetic data persists. This phase never
   requires deleting fixtures or changing immutable migrations.
2. Compatibility gate: before/after catalogue manifests in `docs/verification/ac303`
   were compared by the Migration Architect checker: exit 0, `fully_compatible`,
   zero breaking/potentially-breaking findings. Existing columns and signatures
   remain unchanged; the expansion adds a nullable JSONB column and two views.
   Column-local checks are recorded with their columns. Manual check: the new
   object-or-null check concerns only the new nullable column, so existing rows
   satisfy it without backfill. The checker does not prove SQL/RLS behavior;
   pgTAP and unchanged legacy signatures provide that separate evidence.
3. Apply the validated candidate as one development migration transaction, then
   reconcile its local filename with the returned ledger version. On ambiguous
   transport, inspect the ledger and definitions before any retry.
4. After commit, rerun all SQL suites, signature/privilege/RLS checks, fixture counts
   and advisors. If a regression occurs, stop quotation writes and prepare an
   additive corrective migration. Keep snapshots, decisions, ledger and new
   nullable column intact. Do not execute the compatibility tool's generic
   DROP-column suggestion or restore permissive workflow behavior.

The user's approved Wave 3 scope explicitly covers permission-checked RPCs,
forced RLS, exact financial values and development-only validated migrations.
The specification and migration skills guided these security/compatibility gates;
no authentication or encryption algorithm/key-management change was made.

## Verification evidence

AC-303 suite: **43 assertions passed before and after development application**, including fresh view-only reader,
tenant/entity/branch isolation, forced RLS, safe grants, exact inclusive/exclusive
tax and FX, policy pinning, revision/recall replay, stale versions, expiry and
injected late-outbox rollback. Tests were added before the corresponding fixes;
the initial missing-contract/recall tests and the later three revision tests failed
before implementation and passed after it. All fixtures roll back.

### Development application

Applied only to `xpdoufauvrbdmxgngetv` as
`20260906153036_complete_quotation_workspace_contracts.sql`; the ledger now has
**28 entries**. This migration is now immutable. Do not reapply or edit it.
The earlier local candidate filename was renamed to this returned ledger version,
without changing its contents. Local and ledger SQL SHA-256 match after normalizing
line endings and trailing newlines:

`ccce37097a8bae688dfaf075aba6914158c187623f98b1f3dfe659e08c03e556`

An initial connector transport failure was followed by read-only verification of
the ledger, views, column and helper: nothing had applied. Only after that proof
was a fresh application attempted; its success and ledger entry were confirmed.
No production project was changed.

### Final regression

| SQL suite | Passed |
|---|---:|
| Greenfield foundation | 30 |
| Wave 2 shared foundation | 99 |
| Wave 3 operational foundation | 50 |
| Wave 3 CRM pipeline | 88 |
| Wave 3 lead-to-cash foundation | 46 |
| Wave 3 quotation workspace contracts | 43 |
| **SQL total** | **356** |

Every SQL suite used a separate synthetic transaction with strict `finish(true)`
and ROLLBACK. Post-application counts are zero for quotations, quotation lines,
revisions, orders, CRM leads/opportunities and the new fixture users. Existing
credit/reservation behavior passes its unchanged assertions. The only change to
that test file is its explicit quotation lifecycle configuration.

| Dart/Flutter suite | Passed |
|---|---:|
| Framework-free domain (`dart test`) | 68 |
| Platform adapters/persistence | 33 |
| Design system | 10 |
| Desktop, including existing CRM/goldens | 38 |
| **Client total** | **149** |

- Analyzer: no issues. Non-mutating formatter check: **74 files, zero changes**.
- PostgreSQL `plpgsql_check`: **five new/replaced functions, zero findings**,
  both before and after application; the diagnostic extension was installed only
  inside rollback transactions. Search paths, public/private execute grants,
  caller-RLS views and forced table RLS were also checked directly.
- Windows: `flutter pub get --offline`, then `flutter build windows --debug --no-pub`
  passed against the final client source (96.4 seconds on the final run).
  This is build evidence, not a release build, cold-launch or authenticated UI run.
- Security advisors: **zero findings**. Performance advisors: **176 INFO-only
  unused-index notices**, no warnings/errors. Indexes were retained; empty
  development data is not representative usage evidence. See
  [unused-index guidance](https://supabase.com/docs/guides/database/database-linter?lint=0005_unused_index).
- Heuristic secret scan: **214 source/test/documentation files, zero matches**.
  It checked private keys, AWS/Supabase secret tokens, credentialed database URLs
  and JWT-shaped literals without printing matching contents. Gitleaks/Docker
  were unavailable locally; a complete history/Gitleaks scan remains a CI gate.
- Git whitespace checks passed. Prior CRM source, tests, immutable migrations and
  `.gitignore` match HEAD. Git tracks **zero** generated Windows Flutter/plugin
  artifacts and all four generated-path ignore checks pass. No files were staged,
  committed or pushed.

## Precise next slice

Bind the Windows quotation list/detail/editor and lifecycle controls to these
contracts, with bounded governed-reference pickers, encrypted draft recovery,
capability/connectivity/scope invalidation, explicit conflict UI and revision/
decision history. Add widget/golden tests and inspect the rendered workspace.
Only then call the complete AC-303 desktop workspace finished and continue the
AC-304 quote-to-order, credit/exposure and reservation interaction. Concurrent
multi-session stress/load proof and the full Wave 3 release gate remain separate.
